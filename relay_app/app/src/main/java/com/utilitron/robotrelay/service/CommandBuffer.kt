package com.utilitron.robotrelay.service

import android.util.Log
import com.google.gson.Gson
import com.google.gson.JsonObject
import com.utilitron.robotrelay.core.HeartbeatData
import com.utilitron.robotrelay.core.Messenger
import com.utilitron.robotrelay.core.ProcessingType
import kotlinx.coroutines.*
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import java.util.*

/**
 * CommandBuffer - A dumb queue that executes commands sequentially.
 *
 * NO LOGIC. NO RETRIES. NO DECISIONS.
 *
 * - Accepts commands from Flutter
 * - Executes them one at a time
 * - Reports status back via callback
 * - Flutter decides what to do on failure
 *
 * Bidirectional Heartbeat:
 * - Drummer: Sends heartbeats TO Flutter (Relay→Flutter) via sendHeartbeat()
 * - Messenger: Receives heartbeats FROM Flutter (Flutter→Relay)
 */
class CommandBuffer(
    private val robotClient: RobotWebSocketClient,
    private val taskExecutor: RelayServer.TaskExecutor?,
    private val onStatusUpdate: (String) -> Unit,  // Sends JSON to Flutter
    private val heartbeatIntervalMs: Long = 1000,  // Configurable heartbeat pace (sets the rhythm)
    private val minHeartbeatMs: Long = 200,        // Floor: never beat faster than this
    private val maxHeartbeatMs: Long = 5000        // Ceiling: never beat slower than this
) {
    companion object {
        private const val TAG = "CommandBuffer"
    }

    /** Navigation signals from onNavStatus — replaces polling loop */
    sealed class NavSignal {
        data class Moving(val goalName: String) : NavSignal()
        data class Arrived(val goalName: String) : NavSignal()
        data class Failed(val goalName: String) : NavSignal()
        data class Cancelled(val goalName: String) : NavSignal()
        object StuckAnnouncement : NavSignal()
        object RecoveryTriggered : NavSignal()
    }

    private val gson = Gson()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // Command list with index-based execution (enables looping without re-queuing)
    // MutableList so we can insert/remove/reorder in flight (deliveries, etc.)
    private var commandList: MutableList<BufferCommand> = mutableListOf()
    @Volatile
    private var currentIndex: Int = -1  // -1 = stopped, 0+ = executing
    private var loopStartIndex: Int = 0  // Index to return to on loop (after initial nav+button_standby)
    @Volatile
    private var currentCommand: BufferCommand? = null
    private val completedHistory = mutableListOf<CompletedCommand>()
    private val maxHistory = 10

    // State
    private val _paused = MutableStateFlow(false)
    val paused: StateFlow<Boolean> = _paused

    // Signal channels — replace polling loops with event-driven waits
    private val commandAvailable = Channel<Unit>(Channel.CONFLATED)  // Signals when commands are loaded
    private val navSignal = Channel<NavSignal>(Channel.CONFLATED)     // Signals nav state changes from onNavStatus
    private var externalCompletion: CompletableDeferred<Unit>? = null // Signals when command is completed externally

    private var executionJob: Job? = null
    private var heartbeatJob: Job? = null
    private var currentCommandStartTime: Long = 0
    private var heartbeatSequence: Int = 0  // For SINC rhythm detection

    // Track navigation for completion detection
    private var waitingForNavArrival = false
    private var pendingNavWaypoint: String? = null
    private var navArrivalPending = false  // 603 received, waiting for robot to actually stop
    private var hasStartedMoving = false   // Robot confirmed 601 for OUR goal (not previous one)
    private var navCommandSentAt = 0L      // Timestamp when we sent the POI command

    // Recovery state (accessible from onNavStatus callback)
    private var recoveryAttempts = 0
    private var triggerRecovery = false  // Set by 604 handler to trigger recovery in while loop
    private var inRecovery = false       // True during recovery maneuvers, prevents 602 from cancelling
    private var stuckAnnouncementPending = false  // Set when stuck, nav loop handles TTS+sound

    // Recovery configuration (sent from Flutter, stored in DynamoDB)
    private var recoveryConfig = RecoveryConfig()

    // Crowd logic configuration for speed ramping
    private var crowdConfig = CrowdLogicConfig()

    // === Bidirectional Heartbeat: Messenger receives heartbeats FROM Flutter ===
    private val flutterMessenger = Messenger(
        expectedSource = "flutter",
        missedBeatsThreshold = 3,
        onStale = { Log.w(TAG, "Flutter connection STALE - no heartbeat") },
        onRecovered = { Log.i(TAG, "Flutter connection RECOVERED") }
    )

    /** Is Flutter connection stale (no heartbeat received recently)? */
    val isFlutterStale: Boolean get() = flutterMessenger.isStale.value

    /** Is Flutter connected? */
    val isFlutterConnected: Boolean get() = flutterMessenger.isConnected.value

    /**
     * Called when Flutter acknowledges a heartbeat.
     * This proves the bidirectional connection is alive - Flutter received our heartbeat
     * and was able to send an ACK back.
     */
    fun onHeartbeatAck(sequence: Int, timestamp: Long) {
        val heartbeat = HeartbeatData(
            timestamp = timestamp,
            source = "flutter",
            sequenceNumber = sequence
        )
        flutterMessenger.receiveHeartbeat(heartbeat)
        Log.v(TAG, "Flutter ACK received (seq=$sequence) - bidirectional connection confirmed")
    }

    /**
     * Start the buffer (heartbeat + execution loop)
     */
    fun start() {
        Log.i(TAG, "CommandBuffer starting")
        startHeartbeat()
        startExecutionLoop()
        flutterMessenger.start()  // Start monitoring Flutter heartbeats
    }

    /**
     * Stop the buffer
     */
    fun stop() {
        Log.i(TAG, "CommandBuffer stopping")
        heartbeatJob?.cancel()
        executionJob?.cancel()
        flutterMessenger.stop()  // Stop monitoring Flutter heartbeats
        scope.cancel()
    }

    /**
     * Receive heartbeat from Flutter (Flutter→Relay direction)
     * Called by RelayWebSocket when it receives a flutter_heartbeat message
     */
    fun receiveFlutterHeartbeat(json: JsonObject) {
        val data = HeartbeatData(
            timestamp = json.get("timestamp")?.asLong ?: System.currentTimeMillis(),
            source = json.get("source")?.asString ?: "flutter",
            sequenceNumber = json.get("sequence")?.asInt ?: 0,
            payload = null  // We don't need the payload for rhythm detection
        )
        flutterMessenger.receiveHeartbeat(data)
    }

    /**
     * Load commands into buffer
     */
    fun loadCommands(commands: List<BufferCommand>, clearExisting: Boolean = false) {
        if (clearExisting) {
            commandList = mutableListOf()
            currentIndex = -1
            // Also cancel the current running command so it exits its loop
            // (e.g., button_standby waits on currentCommand != null)
            currentCommand = null
            waitingForNavArrival = false
            navArrivalPending = false
            pendingNavWaypoint = null
            hasStartedMoving = false
            Log.i(TAG, "Cleared existing commands + cancelled current")
        }

        commandList = commands.toMutableList()
        currentIndex = 0  // Start from beginning

        // Calculate loop start index (skip initial nav + button_standby)
        // This prevents showing the START button twice when looping
        loopStartIndex = 0
        if (commands.isNotEmpty() && commands[0].type == "navigate") {
            loopStartIndex = 1
            if (commands.size > 1 && commands[1].type == "button_standby") {
                loopStartIndex = 2
            }
        }

        commands.forEachIndexed { index, cmd ->
            Log.i(TAG, "Command[$index]: ${cmd.type} (id=${cmd.id})")
        }

        Log.i(TAG, "Loaded ${commands.size} commands, loopStartIndex=$loopStartIndex")
        commandAvailable.trySend(Unit)  // Signal execution loop that commands are ready
        sendStatusUpdate()
    }

    /**
     * Clear all pending commands AND stop current command
     */
    fun clear() {
        currentIndex = -1  // Stop execution
        commandList = mutableListOf()
        waitingForNavArrival = false
        navArrivalPending = false
        pendingNavWaypoint = null
        hasStartedMoving = false

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
        val cmd = currentCommand
        if (cmd == null) {
            Log.w(TAG, ">>> SKIP called but currentCommand is NULL! Nothing to skip.")
            Log.w(TAG, "    commandList.size=${commandList.size}")
            return
        }
        Log.i(TAG, ">>> SKIP: Skipping ${cmd.type} (id=${cmd.id})")
        completeCommand(cmd.id, "skipped")
        waitingForNavArrival = false
        navArrivalPending = false
        pendingNavWaypoint = null
        hasStartedMoving = false
        Log.i(TAG, ">>> SKIP: Done, command should advance")
    }

    /**
     * Called when the "Start Tour" button is pressed on the tablet.
     * Completes the current standby command (motion_standby or button_standby).
     */
    fun notifyTourStarted() {
        val cmd = currentCommand
        if (cmd == null) {
            Log.e(TAG, "notifyTourStarted called but currentCommand is NULL! Buffer may have been cleared/restarted.")
            Log.e(TAG, "  commandList.size=${commandList.size}, completedHistory.size=${completedHistory.size}")
            return
        }
        if (cmd.type != "motion_standby" && cmd.type != "button_standby") {
            Log.w(TAG, "notifyTourStarted called but current command is ${cmd.type} (id=${cmd.id})")
            return
        }
        Log.i(TAG, "Tour started via button press, completing ${cmd.type} (id=${cmd.id})")
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
            601 -> { // Moving
                // Robot started moving - check if it's toward our goal
                if (goalName == pendingNavWaypoint || (pendingNavWaypoint != null && goalName.isNullOrEmpty())) {
                    if (!hasStartedMoving) {
                        Log.i(TAG, "Robot started moving toward $pendingNavWaypoint")
                        hasStartedMoving = true
                        navSignal.trySend(NavSignal.Moving(goalName))
                    }
                } else {
                    Log.d(TAG, "Robot moving but goal='$goalName' doesn't match pending='$pendingNavWaypoint'")
                }
            }
            603 -> { // Arrived
                val currentPos = robotClient.robotStatus.value?.let { "(${it.x}, ${it.y})" } ?: "unknown"
                Log.i(TAG, ">>> 603 ARRIVAL: robot says arrived at '$goalName', we wanted '$pendingNavWaypoint', pos=$currentPos")

                val isOurArrival = pendingNavWaypoint != null &&
                                   (goalName == pendingNavWaypoint || goalName.isNullOrEmpty())

                if (isOurArrival) {
                    Log.i(TAG, "Nav reported arrival at $goalName, verifying robot has stopped...")
                    navArrivalPending = true
                    navSignal.trySend(NavSignal.Arrived(goalName))
                } else {
                    Log.w(TAG, ">>> IGNORING 603: goalName='$goalName' doesn't match pendingNavWaypoint='$pendingNavWaypoint'")
                }
            }
            604 -> { // Failed - path blocked, find another way
                if (recoveryAttempts < recoveryConfig.maxRecoveryAttempts) {
                    Log.i(TAG, "Path blocked to $pendingNavWaypoint - searching for escape route...")
                    triggerRecovery = true
                    navSignal.trySend(NavSignal.RecoveryTriggered)
                } else {
                    Log.w(TAG, "Trapped! No escape route found after $recoveryAttempts attempts")
                    stuckAnnouncementPending = true
                    navSignal.trySend(NavSignal.StuckAnnouncement)
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

                // ROBUST 602 HANDLING: Multiple layers to avoid false cancellation
                // Layer 1: Grace period - ignore 602 within 3s of sending POI command
                //          (robot is still processing the new command, 602 is for old goal)
                val timeSinceSend = System.currentTimeMillis() - navCommandSentAt
                if (timeSinceSend < 3000 && !hasStartedMoving) {
                    Log.i(TAG, "Ignoring 602 - within grace period (${timeSinceSend}ms since POI sent, goal='$goalName')")
                    return
                }

                // Layer 2: GoalName mismatch - if 602 reports a different goal than ours,
                //          it's cancelling a previous nav, not ours
                if (goalName.isNotEmpty() && goalName != pendingNavWaypoint) {
                    Log.i(TAG, "Ignoring 602 - goalName '$goalName' != pending '$pendingNavWaypoint' (previous nav cancellation)")
                    return
                }

                // Layer 3: Movement check - if robot never started moving toward our goal,
                //          this 602 is from the old nav being cancelled
                if (!hasStartedMoving) {
                    Log.i(TAG, "Ignoring 602 - robot hasn't started moving toward $pendingNavWaypoint yet")
                    return
                }

                // All checks passed - this is a real cancellation of our current navigation
                Log.i(TAG, "Nav cancelled to $pendingNavWaypoint (confirmed: robot was moving, goal matches)")
                navSignal.trySend(NavSignal.Cancelled(goalName))
                waitingForNavArrival = false
                navArrivalPending = false
                pendingNavWaypoint = null
                currentIndex = -1  // Stop execution on real cancellation
                completeCommand(cmd.id, "cancelled")
            }
        }
    }

    /**
     * Heartbeat - sends status at configured rhythm.
     * The Drummer sets the pace, Flutter's Messenger learns to follow.
     */
    private fun startHeartbeat() {
        heartbeatJob?.cancel()
        val interval = heartbeatIntervalMs.coerceIn(minHeartbeatMs, maxHeartbeatMs)
        heartbeatJob = scope.launch {
            while (isActive) {
                delay(interval)  // Configurable rhythm, not hardcoded
                sendHeartbeat()
            }
        }
        Log.i(TAG, "Heartbeat started at ${interval}ms interval")
    }

    private fun sendHeartbeat() {
        val status = robotClient.robotStatus.value
        val now = System.currentTimeMillis()

        // Calculate how stale the robot data is
        // If lastRobotDataTime is 0, we've never received data - definitely stale
        val robotDataAge = if (robotClient.lastRobotDataTime > 0) {
            now - robotClient.lastRobotDataTime
        } else {
            -1L  // Never received data
        }

        val heartbeat = mapOf(
            "op" to "buffer_heartbeat",
            "timestamp" to now,
            "source" to "relay",  // For Messenger to identify source
            "sequence" to heartbeatSequence++,  // For SINC rhythm detection
            "buffer" to mapOf(
                "paused" to _paused.value,
                "current" to currentCommand?.let { cmd ->
                    mapOf(
                        "id" to cmd.id,
                        "type" to cmd.type,
                        "started_at" to currentCommandStartTime,
                        "elapsed_ms" to (now - currentCommandStartTime)
                    )
                },
                "pending_count" to (commandList.size - currentIndex).coerceAtLeast(0),
                "completed_count" to completedHistory.size,
                "current_index" to currentIndex,
                "loop_start_index" to loopStartIndex
            ),
            "robot" to mapOf(
                "connected" to (robotClient.connectionState.value == ConnectionState.CONNECTED),
                "nav_status" to (status?.navStatus ?: 0),
                "nav_goal" to (status?.currentGoalName ?: ""),
                "battery" to (status?.battery ?: 0),
                "safety_zone" to (status?.safetyZone?.name ?: "CLEAR"),
                // CRITICAL: Include position so Flutter always has it even if pose messages get lost
                "x" to (status?.x ?: 0.0),
                "y" to (status?.y ?: 0.0),
                "theta" to (status?.theta ?: 0.0),
                // CRITICAL: Data freshness so Flutter knows if we're serving stale data
                "data_age_ms" to robotDataAge
            ),
            "crowd_config" to mapOf(
                "safe_distance_meters" to crowdConfig.safeDistanceMeters,
                "ramp_rate" to crowdConfig.rampRate
            ),
            // Bidirectional heartbeat status: is Flutter sending heartbeats to us?
            "flutter_heartbeat" to mapOf(
                "connected" to isFlutterConnected,
                "stale" to isFlutterStale,
                "learned_interval_ms" to flutterMessenger.learnedIntervalMs(),
                "last_sequence" to flutterMessenger.lastSequence()
            )
        )
        onStatusUpdate(gson.toJson(heartbeat))
    }

    private fun sendStatusUpdate() {
        sendHeartbeat() // Reuse heartbeat format for immediate updates
    }

    /**
     * Execution loop - runs commands one at a time using index-based access
     */
    private fun startExecutionLoop() {
        executionJob?.cancel()
        executionJob = scope.launch {
            while (isActive) {
                // Wait if paused — suspends until unpaused (no polling)
                _paused.first { !it }

                // Wait for commands to be available — suspends until loadCommands() signals
                if (currentIndex < 0 || currentIndex >= commandList.size) {
                    commandAvailable.receive()  // Suspends until commands are loaded
                    continue
                }

                val cmd = commandList[currentIndex]
                currentIndex++  // Advance index for next iteration

                // Execute command
                currentCommand = cmd
                currentCommandStartTime = System.currentTimeMillis()

                Log.i(TAG, "Executing[${currentIndex - 1}/${commandList.size}]: ${cmd.type} (id=${cmd.id})")
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
                hasStartedMoving = false  // Reset - first 602 is expected (cancels previous goal)
                navCommandSentAt = System.currentTimeMillis()  // Grace period starts now

                // Reset recovery state for this navigation
                recoveryAttempts = 0
                triggerRecovery = false
                stuckAnnouncementPending = false

                // Check if navigating to/from charger - be less paranoid about obstacles
                val isChargingRelated = waypoint.contains("Pile", ignoreCase = true) ||
                                       waypoint.contains("Charger", ignoreCase = true) ||
                                       waypoint.contains("Dock", ignoreCase = true) ||
                                       waypoint.contains("Charging", ignoreCase = true)

                if (isChargingRelated) {
                    Log.i(TAG, "Navigating to/from charger '$waypoint' - detach mode ON")
                    robotClient.setDetachMode(true)
                }

                robotClient.navigateToPoi(waypoint)
                navArrivalPending = false

                // Wait for nav completion or timeout
                val timeout = cmd.timeoutMs ?: 120000L
                val deadline = System.currentTimeMillis() + timeout
                var lastProgressTime = System.currentTimeMillis()
                var lastPosition: Pair<Double, Double>? = null
                var stoppedSince: Long? = null

                while (waitingForNavArrival && System.currentTimeMillis() < deadline) {
                    // Wait for a nav signal or check progress on robot status changes
                    // Uses withTimeoutOrNull so we still check progress periodically
                    // when status changes arrive (position, velocity) without explicit nav signals
                    val signal = withTimeoutOrNull(500) { navSignal.receive() }

                    // Check if stuck announcement is pending (604 exhausted all recovery attempts)
                    if (signal is NavSignal.StuckAnnouncement || stuckAnnouncementPending) {
                        stuckAnnouncementPending = false
                        Log.i(TAG, "Playing stuck announcement with TTS+sound...")

                        // Speak the stuck message and wait for completion
                        val ttsComplete = CompletableDeferred<Unit>()
                        withContext(Dispatchers.Main) {
                            taskExecutor?.speakText("I'm stuck. I need help please.") {
                                ttsComplete.complete(Unit)
                            }
                        }
                        ttsComplete.await()

                        // Play sad sound and wait for completion
                        val soundComplete = CompletableDeferred<Unit>()
                        withContext(Dispatchers.Main) {
                            taskExecutor?.playAlertSound("sad") {
                                soundComplete.complete(Unit)
                            }
                        }
                        soundComplete.await()

                        Log.i(TAG, "Stuck announcement complete, marking nav as failed")
                        waitingForNavArrival = false
                        navArrivalPending = false
                        pendingNavWaypoint = null
                        completeCommand(cmd.id, "robot_failed")
                        break
                    }

                    // Check if we're making progress
                    val status = robotClient.robotStatus.value
                    val currentPos = status?.let { Pair(it.x, it.y) }
                    val velocity = status?.velocity?.getOrElse(0) { 0.0 } ?: 0.0

                    // If 603 received, verify robot has actually stopped before completing
                    if (navArrivalPending) {
                        // Special case for charger - be more lenient with "arrival" detection
                        val arrivalVelocityThreshold = if (isChargingRelated) 0.1 else 0.05
                        val arrivalConfirmTime = if (isChargingRelated) 300L else 500L

                        if (kotlin.math.abs(velocity) < arrivalVelocityThreshold) {
                            // Robot velocity ~0 (or close enough for charger)
                            if (stoppedSince == null) {
                                stoppedSince = System.currentTimeMillis()
                                Log.i(TAG, "Robot stopped after arrival report, waiting to confirm...")
                            } else if (System.currentTimeMillis() - stoppedSince > arrivalConfirmTime) {
                                // Stopped for sufficient time - actually arrived
                                Log.i(TAG, "Confirmed arrival at $waypoint (stopped for ${arrivalConfirmTime}ms)")
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

                    // Recovery triggers:
                    // 1. Robot explicitly reports 604 (path failed) - immediate
                    // 2. Timeout: no progress for extended period - fallback
                    //    (Don't use relay LIDAR zone - move_base has its own costmaps
                    //    and our LIDAR interpretation causes false positives)
                    val stuckTime = System.currentTimeMillis() - lastProgressTime
                    val stuckTimeout = if (isChargingRelated) {
                        Long.MAX_VALUE  // Never time-out recover near charger (detach mode)
                    } else {
                        recoveryConfig.stuckThresholdMs * 4  // 60s default - genuine stuck only
                    }
                    val shouldRecover = if (isChargingRelated) {
                        false  // Detach mode: never recover near pile/charger
                    } else {
                        triggerRecovery || (stuckTime > stuckTimeout)
                    }

                    if (shouldRecover && recoveryAttempts < recoveryConfig.maxRecoveryAttempts) {
                        val reason = if (triggerRecovery) "nav failed (604)" else "stuck ${stuckTime/1000}s"
                        triggerRecovery = false
                        inRecovery = true  // Prevent 602 from cancelling during recovery
                        recoveryAttempts++

                        Log.i(TAG, "Recovery #$recoveryAttempts/${recoveryConfig.maxRecoveryAttempts} - $reason")

                        robotClient.cancelNavigation()
                        // Wait for navStatus to leave 601 so sendVelocity won't be blocked
                        withTimeoutOrNull(2000) {
                            robotClient.robotStatus.first { it?.navStatus != 601 }
                        }

                        if (recoveryConfig.announceRecovery) {
                            val ttsComplete = CompletableDeferred<Unit>()
                            withContext(Dispatchers.Main) {
                                taskExecutor?.speakText("Looking for an alternative path.") {
                                    ttsComplete.complete(Unit)
                                }
                            }
                            ttsComplete.await()  // Wait for actual TTS completion
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

                        // STEP 2: Spin to find clear direction
                        // CRITICAL: Spin at least 90 degrees BEFORE checking for clear!
                        // Otherwise we might just find "clear" looking back the way we came
                        val spinDuration = (2 * Math.PI / recoveryConfig.spinSpeed * 1000).toLong()
                        val minSpinBeforeCheck = (Math.PI / 2 / recoveryConfig.spinSpeed * 1000).toLong()  // 90 degrees
                        var foundClear = false
                        Log.i(TAG, "Spinning to find clear path (min ${minSpinBeforeCheck}ms before checking)...")

                        val spinStart = System.currentTimeMillis()
                        while (System.currentTimeMillis() - spinStart < spinDuration && !foundClear) {
                            val moved = smartVelocity(0.0, recoveryConfig.spinSpeed, 400)
                            if (!moved) break  // Can't spin, give up on this attempt

                            // Only start checking for clear AFTER minimum spin
                            val spinElapsed = System.currentTimeMillis() - spinStart
                            if (spinElapsed >= minSpinBeforeCheck) {
                                val currentStatus = robotClient.robotStatus.value
                                val currentZone = currentStatus?.safetyZone
                                // Check if LIDAR shows clear path (CLEAR or WARN zone)
                                if (currentZone == SafetyZone.CLEAR || currentZone == SafetyZone.WARN) {
                                    foundClear = true
                                    Log.i(TAG, "Found clear direction after ${spinElapsed}ms spin (zone=$currentZone)")
                                }
                            }
                        }
                        robotClient.sendVelocity(0.0, 0.0)

                        // STEP 3: Nudge forward if clear
                        if (foundClear) {
                            Log.i(TAG, "Nudging forward...")
                            smartVelocity(recoveryConfig.nudgeSpeed, 0.0, recoveryConfig.nudgeDurationMs.toLong())
                        }

                        Log.i(TAG, "Recovery complete, retrying navigation to $waypoint")
                        // Wait for robot to confirm stopped before retrying nav
                        withTimeoutOrNull(2000) {
                            robotClient.robotStatus.first { status ->
                                val vel = status?.velocity ?: listOf(0.0, 0.0)
                                kotlin.math.abs(vel[0]) < 0.01 && kotlin.math.abs(vel.getOrElse(1) { 0.0 }) < 0.01
                            }
                        }
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
                // Always deactivate detach mode when navigation ends
                if (isChargingRelated) {
                    robotClient.setDetachMode(false)
                }
            }

            "speak" -> {
                val text = cmd.data["text"] as? String ?: return
                val completion = CompletableDeferred<Unit>()

                withContext(Dispatchers.Main) {
                    taskExecutor?.speakText(text) {
                        // TTS completion callback - triggered when speech is done
                        completion.complete(Unit)
                    }
                }

                // Wait for actual TTS completion (no more guessing!)
                completion.await()
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
                val soundComplete = CompletableDeferred<Unit>()

                withContext(Dispatchers.Main) {
                    taskExecutor?.playAlertSound(sound) {
                        soundComplete.complete(Unit)
                    }
                }

                // Wait for actual sound completion (no guessing!)
                soundComplete.await()
                completeCommand(cmd.id, "success")
            }

            "motion_standby" -> {
                // Motion detection: wait for person → greet → AUTO-START (no button!)
                val greeting = cmd.data["greeting"] as? String ?: "Hello! Would you like a tour?"
                val sequenceId = cmd.data["sequence_id"] as? String ?: ""
                val pin = cmd.data["pin"] as? String
                val standbyDisplayUrl = cmd.data["display_url"] as? String

                Log.i(TAG, "Entering motion standby for sequence: $sequenceId - waiting for person...")

                // Show standby display if provided
                if (standbyDisplayUrl != null && standbyDisplayUrl.isNotEmpty()) {
                    withContext(Dispatchers.Main) {
                        taskExecutor?.displayUrl(standbyDisplayUrl)
                    }
                }

                // Wait for person detected — suspends until signal fires (no polling)
                robotClient.peopleDetected.first { it || currentCommand == null }

                if (currentCommand == null) {
                    Log.i(TAG, "Motion standby cancelled")
                    return
                }

                Log.i(TAG, "Person detected! Speaking greeting...")

                // Speak greeting
                val ttsComplete = CompletableDeferred<Unit>()
                withContext(Dispatchers.Main) {
                    taskExecutor?.speakText(greeting) {
                        ttsComplete.complete(Unit)
                    }
                }
                ttsComplete.await()

                // Lock screen and auto-start tour
                withContext(Dispatchers.Main) {
                    taskExecutor?.startTourMode(pin)
                }

                Log.i(TAG, "Motion detected - auto-starting tour: $sequenceId")
                completeCommand(cmd.id, "success")
            }

            "button_standby" -> {
                // Like motion_standby but no greeting/motion detection - just show button immediately
                val sequenceId = cmd.data["sequence_id"] as? String ?: ""
                val buttonText = cmd.data["button_text"] as? String ?: "Start Tour"
                val pin = cmd.data["pin"] as? String
                val displayUrl = cmd.data["display_url"] as? String
                val greetingText = cmd.data["greeting_text"] as? String
                    ?: "HI Welcome to the Robotics Floor! If you would like a Tour tap the Start Button and Follow Me!"

                Log.i(TAG, "Entering button standby for sequence: $sequenceId, button: $buttonText")

                // Wait for any active TTS to finish before showing button
                if (taskExecutor?.isTtsSpeaking() == true) {
                    Log.i(TAG, "Waiting for TTS to finish before showing button...")
                    // TTS completion is signaled via callback — wait with a safety timeout
                    withTimeoutOrNull(5000) {
                        while (taskExecutor.isTtsSpeaking()) { delay(100) }
                    }
                    Log.i(TAG, "TTS finished, showing button")
                }

                // Show standby display URL if provided (e.g., frontiertower.io)
                if (displayUrl != null && displayUrl.isNotEmpty()) {
                    withContext(Dispatchers.Main) {
                        taskExecutor?.displayUrl(displayUrl)
                    }
                }

                // Show button now that TTS is idle
                withContext(Dispatchers.Main) {
                    taskExecutor?.notifyTourStandby(sequenceId, buttonText)
                }

                // Track when we last played the greeting
                var lastGreetingTime = 0L
                var lastGreetingTtsComplete: CompletableDeferred<Unit>? = null
                val startedAt = System.currentTimeMillis()
                var wasDetectedLastCycle = false

                // Wait for button press or command cancellation — collect peopleDetected for greeting
                // Rising edge detection: only greet on false→true transition
                val standbyJob = scope.launch {
                    robotClient.peopleDetected.collect { peopleDetected ->
                        if (currentCommand == null) return@collect

                        val risingEdge = peopleDetected && !wasDetectedLastCycle
                        wasDetectedLastCycle = peopleDetected

                        if (risingEdge) {
                            // Wait for any previous greeting to finish before starting another
                            lastGreetingTtsComplete?.let { prev ->
                                if (!prev.isCompleted) return@collect  // Still speaking, skip
                            }

                            val now = System.currentTimeMillis()
                            val timeSinceStart = now - startedAt

                            // Skip detections during initial sensor settling
                            if (timeSinceStart <= 1_500L) {
                                Log.d(TAG, "RISING EDGE: Detection during initial settling")
                                return@collect
                            }

                            // Cooldown: don't re-greet until previous greeting TTS is done
                            // (replaces hardcoded 30s cooldown — now driven by TTS completion)
                            if (lastGreetingTime == 0L || lastGreetingTtsComplete?.isCompleted != false) {
                                Log.i(TAG, "RISING EDGE: People approaching - playing greeting: $greetingText")
                                lastGreetingTime = now
                                val ttsComplete = CompletableDeferred<Unit>()
                                lastGreetingTtsComplete = ttsComplete
                                withContext(Dispatchers.Main) {
                                    taskExecutor?.speakText(greetingText) { ttsComplete.complete(Unit) }
                                }
                            }
                        }
                    }
                }

                // Suspend until command is completed externally (button press, skip, clear)
                // completeCommand() signals externalCompletion — no polling
                val completion = CompletableDeferred<Unit>()
                externalCompletion = completion
                completion.await()
                standbyJob.cancel()

                // Command was completed externally (e.g., button press, skip, clear)
                Log.i(TAG, "Exiting button standby for sequence: $sequenceId")
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

                // Forward to robot client for LIDAR-based velocity ramping
                robotClient.setCrowdConfig(crowdConfig.safeDistanceMeters, crowdConfig.rampRate)

                Log.i(TAG, "Crowd config updated: safeDistance=${crowdConfig.safeDistanceMeters}m, rampRate=${crowdConfig.rampRate}")
                completeCommand(cmd.id, "success")
            }

            "loop" -> {
                // Loop command - restart the sequence from loopStartIndex
                // This skips the initial nav + button_standby that already ran
                Log.i(TAG, "Loop command - resetting to index $loopStartIndex (skipping initial nav/button_standby)")

                // Clear motion detection state if it was active
                withContext(Dispatchers.Main) {
                    taskExecutor?.stopTourMode()  // Ensure we're not in motion standby
                }

                // Mark this command as complete
                completeCommand(cmd.id, "success")

                // Reset index to loop start (after initial nav+button_standby)
                // This is the key fix: robot is already at start, don't show button again
                currentIndex = loopStartIndex
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
                "data" to cmd.data,
                "processing_type" to cmd.processingType.name.lowercase()
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

        // Clear current and signal any waiting code
        currentCommand = null
        externalCompletion?.complete(Unit)
        externalCompletion = null

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
    val timeoutMs: Long? = null,
    val processingType: ProcessingType = ProcessingType.SEQUENTIAL  // Sequential by default
) {
    companion object {
        fun fromJson(json: JsonObject): BufferCommand {
            val gson = Gson()
            val processingTypeStr = json.get("processing_type")?.asString
            val processingType = ProcessingType.values().firstOrNull {
                it.name.equals(processingTypeStr, ignoreCase = true)
            } ?: ProcessingType.SEQUENTIAL

            return BufferCommand(
                id = json.get("id")?.asString ?: UUID.randomUUID().toString(),
                type = json.get("type")?.asString ?: "unknown",
                data = json.get("data")?.let {
                    gson.fromJson(it, Map::class.java) as Map<String, Any?>
                } ?: extractDataFromFlat(json),
                timeoutMs = json.get("timeout_ms")?.asLong,
                processingType = processingType
            )
        }

        // Support flat format: {"type": "navigate", "waypoint": "Kitchen"}
        private fun extractDataFromFlat(json: JsonObject): Map<String, Any?> {
            val data = mutableMapOf<String, Any?>()
            json.entrySet().forEach { (key, value) ->
                if (key !in listOf("id", "type", "timeout_ms", "data", "processing_type")) {
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
