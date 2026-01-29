package com.utilitron.robotrelay.core

import android.util.Log
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * Heartbeat infrastructure for reliable WAN communication
 *
 * Drummer: Sends heartbeats at regular intervals
 * Messenger: Receives heartbeats and detects connection staleness
 *
 * Both Flutter and Relay use this pattern for bidirectional health monitoring.
 */

/**
 * Processing type for command groups
 */
enum class ProcessingType {
    /** Commands execute one at a time, each waits for completion */
    SEQUENTIAL,

    /** Commands in group can execute simultaneously */
    PARALLEL,

    /** Wait for specific condition before proceeding */
    BARRIER
}

/**
 * A command group with its processing type
 */
data class CommandGroup(
    val type: ProcessingType,
    val commandIds: List<String>,
    val barrierCondition: String? = null
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "type" to type.name.lowercase(),
        "command_ids" to commandIds,
        "barrier_condition" to barrierCondition
    ).filterValues { it != null }

    companion object {
        fun fromMap(map: Map<String, Any?>): CommandGroup = CommandGroup(
            type = ProcessingType.values().firstOrNull {
                it.name.equals(map["type"] as? String, ignoreCase = true)
            } ?: ProcessingType.SEQUENTIAL,
            commandIds = (map["command_ids"] as? List<*>)?.mapNotNull { it as? String } ?: emptyList(),
            barrierCondition = map["barrier_condition"] as? String
        )
    }
}

/**
 * Heartbeat data sent between Flutter and Relay
 */
data class HeartbeatData(
    val timestamp: Long,
    val source: String,
    val sequenceNumber: Int,
    val payload: Map<String, Any?>? = null
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "timestamp" to timestamp,
        "source" to source,
        "sequence" to sequenceNumber,
        "payload" to payload
    ).filterValues { it != null }

    companion object {
        fun fromMap(map: Map<String, Any?>): HeartbeatData = HeartbeatData(
            timestamp = (map["timestamp"] as? Number)?.toLong() ?: 0L,
            source = map["source"] as? String ?: "unknown",
            sequenceNumber = (map["sequence"] as? Number)?.toInt() ?: 0,
            payload = map["payload"] as? Map<String, Any?>
        )
    }
}

/**
 * Drummer - Sends heartbeats at regular intervals
 *
 * Usage:
 * ```kotlin
 * val drummer = Drummer(
 *     intervalMs = 1000,
 *     source = "relay",
 *     onBeat = { data -> sendToFlutter(data) }
 * )
 * drummer.start()
 * ```
 */
class Drummer(
    private val intervalMs: Long = 1000,
    private val source: String,
    private val onBeat: (HeartbeatData) -> Unit,
    private val payloadBuilder: (() -> Map<String, Any?>)? = null
) {
    companion object {
        private const val TAG = "Drummer"
    }

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var job: Job? = null
    private var sequenceNumber = 0
    private var isRunning = false

    /** Start sending heartbeats */
    fun start() {
        if (isRunning) return
        isRunning = true
        sequenceNumber = 0

        job = scope.launch {
            // Send first beat immediately
            sendBeat()

            // Then at regular intervals
            while (isActive) {
                delay(intervalMs)
                sendBeat()
            }
        }
        Log.i(TAG, "[$source] Started with ${intervalMs}ms interval")
    }

    /** Stop sending heartbeats */
    fun stop() {
        job?.cancel()
        job = null
        isRunning = false
        Log.i(TAG, "[$source] Stopped at sequence $sequenceNumber")
    }

    private fun sendBeat() {
        sequenceNumber++
        val data = HeartbeatData(
            timestamp = System.currentTimeMillis(),
            source = source,
            sequenceNumber = sequenceNumber,
            payload = payloadBuilder?.invoke()
        )
        onBeat(data)
    }

    fun isRunning() = isRunning
    fun currentSequence() = sequenceNumber
}

/**
 * Messenger - Receives heartbeats and detects staleness
 *
 * Uses SINC-style rhythm detection - learns the actual heartbeat interval
 * and adapts its staleness threshold accordingly.
 *
 * Usage:
 * ```kotlin
 * val messenger = Messenger(
 *     expectedSource = "flutter",
 *     missedBeatsThreshold = 3,
 *     onStale = { handleDisconnect() },
 *     onRecovered = { handleReconnect() }
 * )
 * messenger.receiveHeartbeat(data)
 * ```
 */
class Messenger(
    private val expectedSource: String,
    private val missedBeatsThreshold: Int = 3,
    private val initialIntervalMs: Long = 1000,  // Starting assumption, adapts via EMA
    private val minCheckIntervalMs: Long = 100,   // Floor: never check faster than this
    private val maxCheckIntervalMs: Long = 5000,  // Ceiling: never check slower than this
    private val onStale: (() -> Unit)? = null,
    private val onRecovered: (() -> Unit)? = null,
    private val onHeartbeat: ((HeartbeatData) -> Unit)? = null
) {
    companion object {
        private const val TAG = "Messenger"
    }

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var checkJob: Job? = null

    // SINC-style rhythm learning - adapts to actual heartbeat interval via EMA
    private var expectedIntervalMs: Long = initialIntervalMs
    private var lastSequence = 0
    private var lastTimestamp: Long = 0

    // State
    private val _isStale = MutableStateFlow(true) // Start as stale until first heartbeat
    val isStale: StateFlow<Boolean> = _isStale

    private val _isConnected = MutableStateFlow(false)
    val isConnected: StateFlow<Boolean> = _isConnected

    /**
     * Calculate adaptive check interval based on learned rhythm.
     * Check at half the expected beat interval (Nyquist-ish) -
     * fast enough to catch missed beats, slow enough not to waste cycles.
     */
    private fun adaptiveCheckInterval(): Long {
        return (expectedIntervalMs / 2).coerceIn(minCheckIntervalMs, maxCheckIntervalMs)
    }

    /** Start monitoring for staleness */
    fun start() {
        checkJob?.cancel()
        checkJob = scope.launch {
            while (isActive) {
                delay(adaptiveCheckInterval())  // Adapts to learned rhythm
                checkStaleness()
            }
        }
        Log.i(TAG, "[$expectedSource] Started monitoring (initial interval: ${initialIntervalMs}ms)")
    }

    /** Stop monitoring */
    fun stop() {
        checkJob?.cancel()
        checkJob = null
        Log.i(TAG, "[$expectedSource] Stopped monitoring")
    }

    /** Process incoming heartbeat */
    fun receiveHeartbeat(data: HeartbeatData) {
        if (data.source != expectedSource) return

        val now = System.currentTimeMillis()

        // Learn the rhythm (exponential moving average)
        if (lastTimestamp > 0) {
            val actualInterval = now - lastTimestamp
            if (actualInterval > 0 && actualInterval < 10000) { // Sanity check
                val oldMs = expectedIntervalMs * 0.9
                val newMs = actualInterval * 0.1
                expectedIntervalMs = (oldMs + newMs).toLong()
            }
        }

        lastTimestamp = now
        lastSequence = data.sequenceNumber

        // Check for recovery
        val wasStale = _isStale.value
        _isStale.value = false
        _isConnected.value = true

        if (wasStale) {
            Log.i(TAG, "[$expectedSource] Connection recovered at seq $lastSequence")
            onRecovered?.invoke()
        }

        onHeartbeat?.invoke(data)
    }

    /** Check if connection has gone stale */
    private fun checkStaleness() {
        if (lastTimestamp == 0L) return // Never received a heartbeat

        val now = System.currentTimeMillis()
        val elapsed = now - lastTimestamp
        val expectedBeats = elapsed.toDouble() / expectedIntervalMs

        if (expectedBeats >= missedBeatsThreshold && !_isStale.value) {
            _isStale.value = true
            _isConnected.value = false
            Log.i(TAG, "[$expectedSource] Connection STALE - missed ${String.format("%.1f", expectedBeats)} beats")
            onStale?.invoke()
        }
    }

    fun learnedIntervalMs() = expectedIntervalMs
    fun lastSequence() = lastSequence
}
