package com.smait.robotrelay.service

import android.util.Log
import com.google.gson.Gson
import com.google.gson.JsonObject
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.util.*
import java.util.concurrent.ConcurrentLinkedQueue

/**
 * CommandBuffer - A dumb queue that executes commands sequentially.
 *
 * NO LOGIC. NO RETRIES. NO DECISIONS.
 *
 * - Accepts commands from Flutter
 * - Executes them one at a time
 * - Reports status back via callback
 * - Flutter decides what to do on failure
 */
class CommandBuffer(
    private val robotClient: RobotWebSocketClient,
    private val taskExecutor: RelayServer.TaskExecutor?,
    private val onStatusUpdate: (String) -> Unit  // Sends JSON to Flutter
) {
    companion object {
        private const val TAG = "CommandBuffer"
    }

    private val gson = Gson()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // Command queue
    private val pendingQueue = ConcurrentLinkedQueue<BufferCommand>()
    private var currentCommand: BufferCommand? = null
    private val completedHistory = mutableListOf<CompletedCommand>()
    private val maxHistory = 10

    // State
    private val _paused = MutableStateFlow(false)
    val paused: StateFlow<Boolean> = _paused

    private var executionJob: Job? = null
    private var heartbeatJob: Job? = null
    private var currentCommandStartTime: Long = 0

    // Track navigation for completion detection
    private var waitingForNavArrival = false
    private var pendingNavWaypoint: String? = null
    private var navArrivalPending = false  // 603 received, waiting for robot to actually stop

    // Recovery state (accessible from onNavStatus callback)
    private var recoveryAttempts = 0
    private var triggerRecovery = false  // Set by 604 handler to trigger recovery in while loop
    private var inRecovery = false       // True during recovery maneuvers, prevents 602 from cancelling

    // Recovery configuration (sent from Flutter, stored in DynamoDB)
    private var recoveryConfig = RecoveryConfig()

    // Crowd logic configuration for speed ramping
    private var crowdConfig = CrowdLogicConfig()

    /**
     * Start the buffer (heartbeat + execution loop)
     */
    fun start() {
        Log.i(TAG, "CommandBuffer starting")
        startHeartbeat()
        startExecutionLoop()
    }

    /**
     * Stop the buffer
     */
    fun stop() {
        Log.i(TAG, "CommandBuffer stopping")
        heartbeatJob?.cancel()
        executionJob?.cancel()
        scope.cancel()
    }

    /**
     * Load commands into buffer
     */
    fun loadCommands(commands: List<BufferCommand>, clearExisting: Boolean = false) {
        if (clearExisting) {
            pendingQueue.clear()
            Log.i(TAG, "Cleared existing commands")
        }

        commands.forEach { cmd ->
            pendingQueue.add(cmd)
            Log.i(TAG, "Queued: ${cmd.type} (id=${cmd.id})")
        }

        Log.i(TAG, "Loaded ${commands.size} commands, total pending: ${pendingQueue.size}")
        sendStatusUpdate()
    }

    /**
     * Clear all pending commands AND stop current command
     */
    fun clear() {
        pendingQueue.clear()

        // CRITICAL: Also cancel the current command
        // This breaks out of while loops in commands like motion_standby and wait
        if (currentCommand != null) {
            Log.i(TAG, "Buffer cleared - also cancelling current command: ${currentCommand?.type}")
            // Mark it as cancelled BEFORE clearing it (completeCommand needs currentCommand)
            completeCommand(currentCommand!!.id, "cancelled")
        } else {
            Log.i(TAG, "Buffer cleared")
            sendStatusUpdate()
        }
    }

    /**
     * Pause execution after current command
     */
    fun pause() {
        _paused.value = true
        Log.i(TAG, "Buffer paused")
        sendStatusUpdate()
    }

    /**
     * Resume execution
     */
    fun resume() {
        _paused.value = false
        Log.i(TAG, "Buffer resumed")
        sendStatusUpdate()
    }

    /**
     * Skip current command
     */
    fun skip() {
        currentCommand?.let { cmd ->
            Log.i(TAG, "Skipping: ${cmd.type} (id=${cmd.id})")
            completeCommand(cmd.id, "skipped")
        }
        waitingForNavArrival = false
        navArrivalPending = false
        pendingNavWaypoint = null
    }

    /**
     * Called when the "Start Tour" button is pressed on the tablet.
     * Completes the current motion_standby command.
     */
    fun notifyTourStarted() {
        val cmd = currentCommand ?: return
        if (cmd.type != "motion_standby") {
            Log.w(TAG, "notifyTourStarted called but current command is ${cmd.type}")
            return
        }
        Log.i(TAG, "Tour started via button press, completing motion_standby")
        completeCommand(cmd.id, "success")
    }

    /**
     * Called when robot navigation status changes
     */
    fun onNavStatus(status: Int, goalName: String) {
        if (!waitingForNavArrival) return

        val cmd = currentCommand ?: return
        if (cmd.type != "navigate") return

        when (status) {
            603 -> { // Arrived
                if (goalName == pendingNavWaypoint || pendingNavWaypoint != null) {
                    Log.i(TAG, "Nav reported arrival at $goalName, verifying robot has stopped...")
                    // Don't complete immediately - the robot may still be maneuvering
                    // The executeCommand loop will verify robot has actually stopped
                    // by checking velocity before completing the navigation
                    navArrivalPending = true
                }
            }
            604 -> { // Failed - path blocked, find another way
                if (recoveryAttempts < recoveryConfig.maxRecoveryAttempts) {
                    Log.i(TAG, "Path blocked to $pendingNavWaypoint - searching for escape route...")
                    triggerRecovery = true
                } else {
                    // All attempts exhausted - cry for help like a sad R2D2
                    Log.w(TAG, "Trapped! No escape route found after $recoveryAttempts attempts")
                    scope.launch(Dispatchers.Main) {
                        taskExecutor?.speakText("I'm stuck. I need help please.")
                        delay(2000)
                        taskExecutor?.playAlertSound("sad")  // Sad beeps
                    }
                    waitingForNavArrival = false
                    navArrivalPending = false
                    pendingNavWaypoint = null
                    completeCommand(cmd.id, "robot_failed")
                }
            }
            602 -> { // Cancelled
                // CRITICAL: If recovery is pending OR in progress, don't cancel!
                // The robot base sends 602 after 604 to say "I cancelled the failed nav"
                // and we send cancel ourselves during recovery - ignore both cases
                if (triggerRecovery || inRecovery) {
                    Log.i(TAG, "Nav cancelled but recovery ${if (inRecovery) "in progress" else "pending"} - ignoring 602")
                    return
                }
                Log.i(TAG, "Nav cancelled to $pendingNavWaypoint")
                waitingForNavArrival = false
                navArrivalPending = false
                pendingNavWaypoint = null
                completeCommand(cmd.id, "cancelled")
            }
        }
    }

    /**
     * Heartbeat - sends status every second
     */
    private fun startHeartbeat() {
        heartbeatJob?.cancel()
        heartbeatJob = scope.launch {
            while (isActive) {
                delay(1000)
                sendHeartbeat()
            }
        }
    }

    private fun sendHeartbeat() {
        val status = robotClient.robotStatus.value
        val heartbeat = mapOf(
            "op" to "buffer_heartbeat",
            "timestamp" to System.currentTimeMillis(),
            "buffer" to mapOf(
                "paused" to _paused.value,
                "current" to currentCommand?.let { cmd ->
                    mapOf(
                        "id" to cmd.id,
                        "type" to cmd.type,
                        "started_at" to currentCommandStartTime,
                        "elapsed_ms" to (System.currentTimeMillis() - currentCommandStartTime)
                    )
                },
                "pending_count" to pendingQueue.size,
                "completed_count" to completedHistory.size
            ),
            "robot" to mapOf(
                "connected" to (robotClient.connectionState.value == ConnectionState.CONNECTED),
                "nav_status" to (status?.navStatus ?: 0),
                "nav_goal" to (status?.currentGoalName ?: ""),
                "battery" to (status?.battery ?: 0),
                "safety_zone" to (status?.safetyZone?.name ?: "CLEAR")
            ),
            "crowd_config" to mapOf(
                "safe_distance_meters" to crowdConfig.safeDistanceMeters,
                "ramp_rate" to crowdConfig.rampRate
            )
        )
        onStatusUpdate(gson.toJson(heartbeat))
    }

    private fun sendStatusUpdate() {
        sendHeartbeat() // Reuse heartbeat format for immediate updates
    }

    /**
     * Execution loop - runs commands one at a time
     */
    private fun startExecutionLoop() {
        executionJob?.cancel()
        executionJob = scope.launch {
            while (isActive) {
                // Wait if paused
                while (_paused.value && isActive) {
                    delay(100)
                }

                // Get next command
                val cmd = pendingQueue.poll()
                if (cmd == null) {
                    delay(100)  // Nothing to do, wait a bit
                    continue
                }

                // Execute command
                currentCommand = cmd
                currentCommandStartTime = System.currentTimeMillis()

                Log.i(TAG, "Executing: ${cmd.type} (id=${cmd.id})")
                sendCommandStarted(cmd)

                try {
                    executeCommand(cmd)
                } catch (e: Exception) {
                    Log.e(TAG, "Command failed: ${e.message}")
                    completeCommand(cmd.id, "error", e.message)
                }
            }
        }
    }

    /**
     * Execute a single command
     */
    private suspend fun executeCommand(cmd: BufferCommand) {
        when (cmd.type) {
            "navigate" -> {
                val waypoint = cmd.data["waypoint"] as? String ?: return
                pendingNavWaypoint = waypoint
                waitingForNavArrival = true

                // Reset recovery state for this navigation
                recoveryAttempts = 0
                triggerRecovery = false

                robotClient.navigateToPoi(waypoint)
                navArrivalPending = false

                // Wait for nav completion or timeout
                val timeout = cmd.timeoutMs ?: 120000L  // Increased to 2min to allow recovery attempts
                val deadline = System.currentTimeMillis() + timeout
                var lastProgressTime = System.currentTimeMillis()
                var lastPosition: Pair<Double, Double>? = null
                var stoppedSince: Long? = null  // Track when robot stopped after 603
                // Note: stuckThreshold now comes from recoveryConfig.stuckThresholdMs

                while (waitingForNavArrival && System.currentTimeMillis() < deadline) {
                    delay(100)

                    // Check if we're making progress
                    val status = robotClient.robotStatus.value
                    val currentPos = status?.let { Pair(it.x, it.y) }
                    val velocity = status?.velocity?.getOrElse(0) { 0.0 } ?: 0.0

                    // If 603 received, verify robot has actually stopped before completing
                    if (navArrivalPending) {
                        if (kotlin.math.abs(velocity) < 0.05) {
                            // Robot velocity ~0
                            if (stoppedSince == null) {
                                stoppedSince = System.currentTimeMillis()
                                Log.i(TAG, "Robot stopped after arrival report, waiting to confirm...")
                            } else if (System.currentTimeMillis() - stoppedSince > 500) {
                                // Stopped for 500ms - actually arrived
                                Log.i(TAG, "Confirmed arrival at $waypoint (stopped for 500ms)")
                                waitingForNavArrival = false
                                navArrivalPending = false
                                pendingNavWaypoint = null
                                completeCommand(cmd.id, "success")
                                break
                            }
                        } else {
                            // Still moving - reset stopped timer
                            stoppedSince = null
                        }
                    }

                    if (currentPos != null && lastPosition != null) {
                        val dx = currentPos.first - lastPosition!!.first
                        val dy = currentPos.second - lastPosition!!.second
                        val distance = kotlin.math.sqrt(dx * dx + dy * dy)

                        if (distance > 0.1) {  // Moved more than 10cm
                            lastProgressTime = System.currentTimeMillis()
                        }
                    }
                    lastPosition = currentPos

                    // Check if stuck and in obstacle zone, OR if 604 triggered recovery
                    val stuckTime = System.currentTimeMillis() - lastProgressTime
                    val safetyZone = status?.safetyZone
                    // Check if LIDAR blocked (STOP or CREEP zones)
                    val isBlocked = safetyZone == SafetyZone.STOP || safetyZone == SafetyZone.CREEP

                    // Smart recovery: push but if not moving, stop pushing and try something else
                    val shouldRecover = triggerRecovery || (stuckTime > recoveryConfig.stuckThresholdMs && isBlocked)

                    if (shouldRecover && recoveryAttempts < recoveryConfig.maxRecoveryAttempts) {
                        val wasTriggeredBy604 = triggerRecovery
                        triggerRecovery = false
                        inRecovery = true  // Prevent 602 from cancelling during recovery
                        recoveryAttempts++

                        Log.i(TAG, "Recovery #$recoveryAttempts/${recoveryConfig.maxRecoveryAttempts} - ${if (wasTriggeredBy604) "nav failed" else "stuck ${stuckTime/1000}s"}")

                        robotClient.cancelNavigation()
                        delay(300)

                        if (recoveryConfig.announceRecovery) {
                            withContext(Dispatchers.Main) {
                                taskExecutor?.speakText("Looking for an alternative path.")
                            }
                            delay(1500)
                        }

                        // SMART VELOCITY: Send command, check if actually moving, stop if blocked
                        suspend fun smartVelocity(linear: Double, angular: Double, maxMs: Long): Boolean {
                            val start = System.currentTimeMillis()
                            var blockedCount = 0
                            while (System.currentTimeMillis() - start < maxMs) {
                                robotClient.sendVelocity(linear, angular)
                                delay(200)

                                // Check actual velocity - if we commanded motion but aren't moving, we're blocked
                                val actualVel = robotClient.robotStatus.value?.velocity ?: listOf(0.0, 0.0)
                                val actualLinear = if (actualVel.isNotEmpty()) kotlin.math.abs(actualVel[0]) else 0.0
                                val actualAngular = if (actualVel.size > 1) kotlin.math.abs(actualVel[1]) else 0.0
                                val commandedMotion = kotlin.math.abs(linear) > 0.01 || kotlin.math.abs(angular) > 0.01
                                val actuallyMoving = actualLinear > 0.02 || actualAngular > 0.05

                                if (commandedMotion && !actuallyMoving) {
                                    blockedCount++
                                    if (blockedCount >= 3) {
                                        // Pushed 3 times, not moving - stop, don't be stubborn
                                        Log.i(TAG, "Commanded velocity but not moving - blocked, stopping")
                                        robotClient.sendVelocity(0.0, 0.0)
                                        return false
                                    }
                                } else {
                                    blockedCount = 0  // Reset if we moved
                                }
                            }
                            robotClient.sendVelocity(0.0, 0.0)
                            return true
                        }

                        // STEP 1: Back up
                        Log.i(TAG, "Backing up...")
                        smartVelocity(-recoveryConfig.backupSpeed, 0.0, recoveryConfig.backupDurationMs.toLong())
                        delay(200)

                        // STEP 2: Spin to find clear direction
                        val spinDuration = (2 * Math.PI / recoveryConfig.spinSpeed * 1000).toLong()
                        var foundClear = false
                        Log.i(TAG, "Spinning to find clear path...")

                        val spinStart = System.currentTimeMillis()
                        while (System.currentTimeMillis() - spinStart < spinDuration && !foundClear) {
                            val moved = smartVelocity(0.0, recoveryConfig.spinSpeed, 400)
                            if (!moved) break  // Can't spin, give up on this attempt

                            val currentStatus = robotClient.robotStatus.value
                            val currentZone = currentStatus?.safetyZone
                            // Check if LIDAR shows clear path (CLEAR or WARN zone)
                            if (currentZone == SafetyZone.CLEAR || currentZone == SafetyZone.WARN) {
                                foundClear = true
                                Log.i(TAG, "Found clear direction (LIDAR clear)!")
                            }
                        }
                        robotClient.sendVelocity(0.0, 0.0)
                        delay(200)

                        // STEP 3: Nudge forward if clear
                        if (foundClear) {
                            Log.i(TAG, "Nudging forward...")
                            smartVelocity(recoveryConfig.nudgeSpeed, 0.0, recoveryConfig.nudgeDurationMs.toLong())
                        }

                        Log.i(TAG, "Recovery complete, retrying navigation to $waypoint")
                        delay(300)
                        inRecovery = false  // Done with recovery, 602 can cancel again
                        robotClient.navigateToPoi(waypoint)
                        lastProgressTime = System.currentTimeMillis()
                    }
                }

                if (waitingForNavArrival) {
                    // Timeout after all attempts
                    waitingForNavArrival = false
                    navArrivalPending = false
                    pendingNavWaypoint = null
                    Log.w(TAG, "Navigation to $waypoint timed out after $recoveryAttempts recovery attempts")
                    completeCommand(cmd.id, "timeout")
                }
                // Otherwise completed via arrival confirmation loop above
            }

            "speak" -> {
                val text = cmd.data["text"] as? String ?: return
                val completion = CompletableDeferred<Unit>()

                withContext(Dispatchers.Main) {
                    taskExecutor?.speakText(text)
                    // TTS doesn't have reliable callback, estimate duration
                    val estimatedMs = (text.split(" ").size * 300L).coerceIn(1000, 30000)
                    delay(estimatedMs)
                }

                completeCommand(cmd.id, "success")
            }

            "display" -> {
                val url = cmd.data["url"] as? String ?: return
                val durationMs = (cmd.data["duration_ms"] as? Number)?.toLong() ?: 0L

                withContext(Dispatchers.Main) {
                    taskExecutor?.displayUrl(url)
                }

                if (durationMs > 0) {
                    delay(durationMs)
                    withContext(Dispatchers.Main) {
                        taskExecutor?.closeDisplay()
                    }
                }

                completeCommand(cmd.id, "success")
            }

            "display_default" -> {
                // Show default POI display (waypoint name/company branding)
                // When no custom URL is configured for a stop
                val waypoint = cmd.data["waypoint"] as? String ?: "Unknown"
                val durationMs = (cmd.data["duration_ms"] as? Number)?.toLong() ?: 0L

                withContext(Dispatchers.Main) {
                    // Use a default branding URL with waypoint as parameter
                    // The tablet app should show POI name prominently with company logo
                    taskExecutor?.displayUrl("default://waypoint/$waypoint")
                }

                if (durationMs > 0) {
                    delay(durationMs)
                    withContext(Dispatchers.Main) {
                        taskExecutor?.closeDisplay()
                    }
                }

                completeCommand(cmd.id, "success")
            }

            "close_display" -> {
                withContext(Dispatchers.Main) {
                    taskExecutor?.closeDisplay()
                }
                completeCommand(cmd.id, "success")
            }

            "wait" -> {
                val durationMs = (cmd.data["duration_ms"] as? Number)?.toLong() ?: 0L
                val showCountdown = cmd.data["show_countdown"] as? Boolean ?: false
                val label = cmd.data["label"] as? String ?: "Next stop in"
                val deadline = System.currentTimeMillis() + durationMs

                if (showCountdown) {
                    // Initial countdown update
                    withContext(Dispatchers.Main) {
                        taskExecutor?.updateCountdown((durationMs / 1000).toInt(), label)
                    }
                }

                var lastUpdate = System.currentTimeMillis()
                while (System.currentTimeMillis() < deadline && currentCommand != null) {
                    delay(100)
                    if (showCountdown && System.currentTimeMillis() - lastUpdate >= 1000) {
                        val remainingMs = deadline - System.currentTimeMillis()
                        withContext(Dispatchers.Main) {
                            taskExecutor?.updateCountdown((remainingMs / 1000).toInt().coerceAtLeast(0), label)
                        }
                        lastUpdate = System.currentTimeMillis()
                    }
                }

                if (showCountdown) {
                    // Hide countdown when done
                    withContext(Dispatchers.Main) {
                        taskExecutor?.updateCountdown(0, "")
                    }
                }

                if (currentCommand != null) {
                    completeCommand(cmd.id, "success")
                }
            }


            "sound" -> {
                val sound = cmd.data["sound"] as? String ?: "beep"
                withContext(Dispatchers.Main) {
                    taskExecutor?.playAlertSound(sound)
                }
                delay(500)  // Brief delay for sound to play
                completeCommand(cmd.id, "success")
            }

            "motion_standby" -> {
                val greeting = cmd.data["greeting"] as? String ?: "Hello! Would you like a tour?"
                val sequenceId = cmd.data["sequence_id"] as? String ?: ""
                val buttonText = cmd.data["button_text"] as? String ?: "Start Tour"
                val pin = cmd.data["pin"] as? String

                Log.i(TAG, "Entering motion standby for sequence: $sequenceId, button: $buttonText")

                // Activate tour mode to lock the screen
                withContext(Dispatchers.Main) {
                    taskExecutor?.startTourMode(pin)
                    // Notify UI to show the "Start Tour" button on the lock screen
                    taskExecutor?.notifyTourStandby(sequenceId, buttonText)
                }

                // Wait indefinitely until the command is completed by a button press or skipped
                while (currentCommand != null) {
                    delay(500)
                }

                // Command was completed externally (e.g., button press, skip, clear)
                Log.i(TAG, "Exiting motion standby for sequence: $sequenceId")
            }


            "set_recovery_config" -> {
                // Update recovery configuration from Flutter
                val stuckMs = (cmd.data["stuck_threshold_ms"] as? Number)?.toLong() ?: recoveryConfig.stuckThresholdMs
                val maxAttempts = (cmd.data["max_recovery_attempts"] as? Number)?.toInt() ?: recoveryConfig.maxRecoveryAttempts
                val backupMs = (cmd.data["backup_duration_ms"] as? Number)?.toLong() ?: recoveryConfig.backupDurationMs
                val backupSpd = (cmd.data["backup_speed"] as? Number)?.toDouble() ?: recoveryConfig.backupSpeed
                val spinSpd = (cmd.data["spin_speed"] as? Number)?.toDouble() ?: recoveryConfig.spinSpeed
                val nudgeMs = (cmd.data["nudge_duration_ms"] as? Number)?.toLong() ?: recoveryConfig.nudgeDurationMs
                val nudgeSpd = (cmd.data["nudge_speed"] as? Number)?.toDouble() ?: recoveryConfig.nudgeSpeed
                val announce = cmd.data["announce_recovery"] as? Boolean ?: recoveryConfig.announceRecovery

                recoveryConfig = RecoveryConfig(
                    stuckThresholdMs = stuckMs,
                    maxRecoveryAttempts = maxAttempts,
                    backupDurationMs = backupMs,
                    backupSpeed = backupSpd,
                    spinSpeed = spinSpd,
                    nudgeDurationMs = nudgeMs,
                    nudgeSpeed = nudgeSpd,
                    announceRecovery = announce
                )

                Log.i(TAG, "Recovery config updated: stuckMs=$stuckMs, maxAttempts=$maxAttempts, backupMs=$backupMs")
                completeCommand(cmd.id, "success")
            }

            "set_crowd_config" -> {
                // Update crowd logic / speed ramping configuration from Flutter
                val safeDist = (cmd.data["safe_distance_meters"] as? Number)?.toDouble() ?: crowdConfig.safeDistanceMeters
                val rate = (cmd.data["ramp_rate"] as? Number)?.toDouble() ?: crowdConfig.rampRate

                crowdConfig = CrowdLogicConfig(
                    safeDistanceMeters = safeDist.coerceIn(0.3, 3.0),  // 1-10 feet range
                    rampRate = rate.coerceIn(0.1, 1.0)
                )

                // TODO: Forward to robot client for velocity ramping in WARN zone
                // robotClient.setCrowdConfig method doesn't exist yet

                Log.i(TAG, "Crowd config updated: safeDistance=${crowdConfig.safeDistanceMeters}m, rampRate=${crowdConfig.rampRate}")
                completeCommand(cmd.id, "success")
            }

            "loop" -> {
                // Loop command - restart the sequence from the beginning
                // IMPORTANT: Clear any motion trigger state to prevent auto-triggering
                Log.i(TAG, "Loop command received - restarting sequence")

                // Clear motion detection state if it was active
                withContext(Dispatchers.Main) {
                    taskExecutor?.stopTourMode()  // Ensure we're not in motion standby
                }

                // Mark this command as complete
                completeCommand(cmd.id, "success")

                // The buffer executor will reload commands after this completes
            }

            else -> {
                Log.w(TAG, "Unknown command type: ${cmd.type}")
                completeCommand(cmd.id, "unknown_type")
            }
        }
    }

    private fun sendCommandStarted(cmd: BufferCommand) {
        val event = mapOf(
            "op" to "buffer_cmd_started",
            "command" to mapOf(
                "id" to cmd.id,
                "type" to cmd.type,
                "data" to cmd.data
            ),
            "timestamp" to System.currentTimeMillis()
        )
        onStatusUpdate(gson.toJson(event))
    }

    private fun completeCommand(id: String, result: String, error: String? = null) {
        val cmd = currentCommand
        if (cmd?.id != id) return

        val duration = System.currentTimeMillis() - currentCommandStartTime

        Log.i(TAG, "Completed: ${cmd.type} (id=$id) result=$result duration=${duration}ms")

        // Add to history
        completedHistory.add(CompletedCommand(id, cmd.type, result, duration))
        if (completedHistory.size > maxHistory) {
            completedHistory.removeAt(0)
        }

        // Clear current
        currentCommand = null

        // Send event
        val event = mapOf(
            "op" to "buffer_cmd_completed",
            "command_id" to id,
            "result" to result,
            "duration_ms" to duration,
            "error" to error,
            "timestamp" to System.currentTimeMillis()
        )
        onStatusUpdate(gson.toJson(event))
    }
}

/**
 * A command in the buffer
 */
data class BufferCommand(
    val id: String = UUID.randomUUID().toString(),
    val type: String,  // navigate, speak, display, wait, sound, close_display
    val data: Map<String, Any?> = emptyMap(),
    val timeoutMs: Long? = null
) {
    companion object {
        fun fromJson(json: JsonObject): BufferCommand {
            val gson = Gson()
            return BufferCommand(
                id = json.get("id")?.asString ?: UUID.randomUUID().toString(),
                type = json.get("type")?.asString ?: "unknown",
                data = json.get("data")?.let {
                    gson.fromJson(it, Map::class.java) as Map<String, Any?>
                } ?: extractDataFromFlat(json),
                timeoutMs = json.get("timeout_ms")?.asLong
            )
        }

        // Support flat format: {"type": "navigate", "waypoint": "Kitchen"}
        private fun extractDataFromFlat(json: JsonObject): Map<String, Any?> {
            val data = mutableMapOf<String, Any?>()
            json.entrySet().forEach { (key, value) ->
                if (key !in listOf("id", "type", "timeout_ms", "data")) {
                    data[key] = when {
                        value.isJsonPrimitive -> {
                            val prim = value.asJsonPrimitive
                            when {
                                prim.isBoolean -> prim.asBoolean
                                prim.isNumber -> prim.asNumber
                                else -> prim.asString
                            }
                        }
                        else -> value.toString()
                    }
                }
            }
            return data
        }
    }
}

/**
 * Record of a completed command
 */
data class CompletedCommand(
    val id: String,
    val type: String,
    val result: String,
    val durationMs: Long
)

/**
 * Recovery configuration for navigation failures
 * Sent from Flutter, stored in DynamoDB for fleet-wide sync
 */
data class RecoveryConfig(
    val stuckThresholdMs: Long = 15000L,      // Time stuck before recovery (default 15s)
    val maxRecoveryAttempts: Int = 3,         // Max retries before giving up
    val backupDurationMs: Long = 3000L,       // How long to reverse (longer at slow speed)
    val backupSpeed: Double = 0.05,           // TORTOISE: 5cm/s - gentle bump
    val spinSpeed: Double = 0.3,              // Slower spin
    val nudgeDurationMs: Long = 2000L,        // Nudge duration (longer at slow speed)
    val nudgeSpeed: Double = 0.05,            // TORTOISE: 5cm/s - gentle nudge
    val announceRecovery: Boolean = true      // TTS "Looking for alternative path"
)

/**
 * Crowd Logic configuration for speed ramping
 * Controls how aggressively robot slows down when approaching obstacles
 */
data class CrowdLogicConfig(
    val safeDistanceMeters: Double = 0.9,     // Distance where ramping begins (~3 feet)
    val rampRate: Double = 0.5                // 0.1 = gentle, 1.0 = aggressive
)
