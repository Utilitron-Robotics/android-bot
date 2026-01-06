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
        pendingNavWaypoint = null
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
                    Log.i(TAG, "Nav arrived at $goalName")
                    waitingForNavArrival = false
                    pendingNavWaypoint = null
                    completeCommand(cmd.id, "success")
                }
            }
            604 -> { // Failed
                Log.i(TAG, "Nav failed to $pendingNavWaypoint")
                waitingForNavArrival = false
                pendingNavWaypoint = null
                completeCommand(cmd.id, "robot_failed")
            }
            602 -> { // Cancelled
                Log.i(TAG, "Nav cancelled to $pendingNavWaypoint")
                waitingForNavArrival = false
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

                // Wait for nav completion or timeout
                val timeout = cmd.timeoutMs ?: 60000L
                val deadline = System.currentTimeMillis() + timeout

                while (waitingForNavArrival && System.currentTimeMillis() < deadline) {
                    delay(100)
                }

                if (waitingForNavArrival) {
                    // Timeout
                    waitingForNavArrival = false
                    pendingNavWaypoint = null
                    completeCommand(cmd.id, "timeout")
                }
                // Otherwise completed via onNavStatus callback
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

            "close_display" -> {
                withContext(Dispatchers.Main) {
                    taskExecutor?.closeDisplay()
                }
                completeCommand(cmd.id, "success")
            }

            "wait" -> {
                val durationMs = (cmd.data["duration_ms"] as? Number)?.toLong() ?: 0L
                delay(durationMs)
                completeCommand(cmd.id, "success")
            }

            "sound" -> {
                val sound = cmd.data["sound"] as? String ?: "beep"
                withContext(Dispatchers.Main) {
                    taskExecutor?.playAlertSound(sound)
                }
                delay(500)  // Brief delay for sound to play
                completeCommand(cmd.id, "success")
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
