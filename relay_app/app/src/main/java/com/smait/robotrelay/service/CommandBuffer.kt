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
     * Clear all pending commands
     */
    fun clear() {
        pendingQueue.clear()
        Log.i(TAG, "Buffer cleared")
        sendStatusUpdate()
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
            604 -> { // Failed
                Log.i(TAG, "Nav failed to $pendingNavWaypoint")
                waitingForNavArrival = false
                navArrivalPending = false
                pendingNavWaypoint = null
                completeCommand(cmd.id, "robot_failed")
            }
            602 -> { // Cancelled
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
                "battery" to (status?.battery ?: 0)
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

                robotClient.navigateToPoi(waypoint)
                navArrivalPending = false

                // Wait for nav completion or timeout
                val timeout = cmd.timeoutMs ?: 60000L
                val deadline = System.currentTimeMillis() + timeout
                var lastProgressTime = System.currentTimeMillis()
                var lastPosition: Pair<Double, Double>? = null
                var recoveryAttempts = 0
                val maxRecoveryAttempts = 3
                val stuckThresholdMs = 45000L  // 45 seconds stuck = try recovery
                var stoppedSince: Long? = null  // Track when robot stopped after 603

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

                    // Check if stuck and in obstacle zone
                    val stuckTime = System.currentTimeMillis() - lastProgressTime
                    val safetyZone = status?.safetyZone
                    val isBlocked = safetyZone == SafetyZone.STOP || safetyZone == SafetyZone.CREEP

                    if (stuckTime > stuckThresholdMs && isBlocked && recoveryAttempts < maxRecoveryAttempts) {
                        recoveryAttempts++
                        Log.i(TAG, "Robot stuck for ${stuckTime/1000}s in $safetyZone zone, attempting recovery spin #$recoveryAttempts")

                        // Cancel current navigation before recovery maneuver
                        robotClient.cancelNavigation()
                        delay(300)

                        // Announce recovery attempt
                        withContext(Dispatchers.Main) {
                            taskExecutor?.speakText("Looking for an alternative path.")
                        }
                        delay(1500)

                        // Spin until we find a clear direction (or max 360°)
                        // The SLAM sees the hole but hesitates - we need to face it and nudge
                        val spinDuration = 12500L  // Max 360° at 0.5 rad/s
                        val spinStart = System.currentTimeMillis()
                        var foundClear = false
                        Log.i(TAG, "Starting recovery spin, looking for clear path...")

                        while (System.currentTimeMillis() - spinStart < spinDuration && !foundClear) {
                            robotClient.sendVelocity(0.0, 0.5)  // Spin slowly
                            delay(400)

                            // Check if we're now facing a clear direction
                            val currentZone = robotClient.robotStatus.value?.safetyZone
                            if (currentZone == SafetyZone.CLEAR || currentZone == SafetyZone.WARN) {
                                foundClear = true
                                Log.i(TAG, "Found clear direction! Zone: $currentZone")
                            }
                        }
                        robotClient.sendVelocity(0.0, 0.0)  // Stop spinning
                        delay(300)

                        // Nudge forward into the gap - this kicks the SLAM planner into action
                        if (foundClear) {
                            Log.i(TAG, "Nudging forward into the gap...")
                            val nudgeDuration = 1500L  // ~30cm at 0.2 m/s
                            val nudgeStart = System.currentTimeMillis()
                            while (System.currentTimeMillis() - nudgeStart < nudgeDuration) {
                                robotClient.sendVelocity(0.2, 0.0)  // Slow forward
                                delay(400)
                            }
                            robotClient.sendVelocity(0.0, 0.0)  // Stop
                            delay(300)
                        }

                        Log.i(TAG, "Recovery maneuver complete, re-attempting navigation to $waypoint")

                        // Re-attempt navigation
                        delay(500)
                        robotClient.navigateToPoi(waypoint)
                        lastProgressTime = System.currentTimeMillis()  // Reset stuck timer
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
                val deadline = System.currentTimeMillis() + durationMs
                // Check every 100ms if we've been skipped (currentCommand becomes null)
                while (System.currentTimeMillis() < deadline && currentCommand != null) {
                    delay(100)
                }
                // Only complete if we weren't skipped
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
                // Wait for motion detection to trigger tour start
                // When a person approaches, greet them and show start button
                val greeting = cmd.data["greeting"] as? String ?: "Hello! Would you like a tour?"
                val sequenceId = cmd.data["sequence_id"] as? String ?: ""
                val buttonText = cmd.data["button_text"] as? String ?: "Start Tour"
                val displayUrl = cmd.data["display_url"] as? String

                Log.i(TAG, "Entering motion standby mode for sequence: $sequenceId, button: $buttonText")

                // Show "waiting for visitor" on tablet
                withContext(Dispatchers.Main) {
                    taskExecutor?.displayUrl("motion://standby?sequence=$sequenceId")
                }

                // Monitor for motion (person approaching)
                var motionDetected = false
                var greetingSpoken = false
                val startTime = System.currentTimeMillis()
                val maxWaitMs = 300000L  // 5 minute max wait

                while (!motionDetected && currentCommand != null &&
                       System.currentTimeMillis() - startTime < maxWaitMs) {
                    // Check for motion via obstacle classification
                    // The classification is updated by RobotWebSocketClient
                    val status = robotClient.robotStatus.value
                    if (status?.obstacleInPath == true && status.obstacleMoving == true) {
                        if (!greetingSpoken) {
                            Log.i(TAG, "Motion detected! Speaking greeting...")
                            greetingSpoken = true
                            withContext(Dispatchers.Main) {
                                // Play arrival sound first
                                taskExecutor?.playAlertSound("arrival")
                                delay(500)
                                // Speak greeting
                                taskExecutor?.speakText(greeting)
                                // Show start tour button with custom text
                                val encodedButton = java.net.URLEncoder.encode(buttonText, "UTF-8")
                                taskExecutor?.displayUrl("motion://start_tour?sequence=$sequenceId&button=$encodedButton")
                            }
                        }
                        // Wait for tour start button press (handled via tablet event)
                        // The button press will complete this command
                        delay(100)
                    } else {
                        delay(500)  // Check every 500ms when no motion
                    }
                }

                // If we exited due to timeout or skip, mark as such
                if (currentCommand != null && !motionDetected) {
                    Log.i(TAG, "Motion standby timed out or skipped")
                    completeCommand(cmd.id, "timeout")
                }
                // If tour was started via button, command is completed by notifyTourStarted()
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
