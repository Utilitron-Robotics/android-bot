package com.utilitron.robotrelay.service

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import kotlin.math.min
import kotlin.math.pow
import kotlin.random.Random

/**
 * Adaptive connection retry policy with backpressure.
 *
 * Learns from connection patterns and adjusts behavior:
 * - Exponential backoff with jitter for failures
 * - Faster recovery when historically reliable
 * - Slower retry when consistently failing
 * - Centralized, configurable limits (not hardcoded)
 *
 * Configuration stored in SharedPreferences for runtime adjustment.
 */
class AdaptiveConnectionPolicy(context: Context) {

    companion object {
        private const val TAG = "AdaptiveConnPolicy"
        private const val PREFS_NAME = "connection_policy"

        // Preference keys (centralized, not hardcoded in logic)
        private const val KEY_BASE_DELAY_MS = "base_delay_ms"
        private const val KEY_MAX_DELAY_MS = "max_delay_ms"
        private const val KEY_BACKOFF_MULTIPLIER = "backoff_multiplier"
        private const val KEY_JITTER_FACTOR = "jitter_factor"
        private const val KEY_STALE_THRESHOLD_FAILURES = "stale_threshold_failures"
        private const val KEY_ERROR_THRESHOLD_FAILURES = "error_threshold_failures"
        private const val KEY_SUCCESS_STREAK_FOR_FAST_RETRY = "success_streak_for_fast_retry"

        // Learned state keys
        private const val KEY_LIFETIME_SUCCESSES = "lifetime_successes"
        private const val KEY_LIFETIME_FAILURES = "lifetime_failures"
        private const val KEY_LAST_SUCCESS_TIME = "last_success_time"
        private const val KEY_AVG_CONNECTION_DURATION_MS = "avg_connection_duration_ms"
    }

    private val prefs: SharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    // === Configurable Parameters (read from prefs, with sensible defaults) ===

    /** Base delay before first retry (ms) */
    val baseDelayMs: Long
        get() = prefs.getLong(KEY_BASE_DELAY_MS, 2000L)

    /** Maximum delay between retries (ms) - caps exponential growth */
    val maxDelayMs: Long
        get() = prefs.getLong(KEY_MAX_DELAY_MS, 60000L)

    /** Multiplier for exponential backoff (e.g., 1.5 = 50% increase each failure) */
    val backoffMultiplier: Float
        get() = prefs.getFloat(KEY_BACKOFF_MULTIPLIER, 1.5f)

    /** Jitter factor to prevent thundering herd (0.0-1.0) */
    val jitterFactor: Float
        get() = prefs.getFloat(KEY_JITTER_FACTOR, 0.3f)

    /** Consecutive failures before entering STALE state */
    val staleThresholdFailures: Int
        get() = prefs.getInt(KEY_STALE_THRESHOLD_FAILURES, 1)

    /** Consecutive failures before entering ERROR state */
    val errorThresholdFailures: Int
        get() = prefs.getInt(KEY_ERROR_THRESHOLD_FAILURES, 5)

    /** How many successful connections before we trust fast retry */
    val successStreakForFastRetry: Int
        get() = prefs.getInt(KEY_SUCCESS_STREAK_FOR_FAST_RETRY, 3)

    // === Learned State (persisted across sessions) ===

    private var lifetimeSuccesses: Long
        get() = prefs.getLong(KEY_LIFETIME_SUCCESSES, 0)
        set(value) = prefs.edit().putLong(KEY_LIFETIME_SUCCESSES, value).apply()

    private var lifetimeFailures: Long
        get() = prefs.getLong(KEY_LIFETIME_FAILURES, 0)
        set(value) = prefs.edit().putLong(KEY_LIFETIME_FAILURES, value).apply()

    private var lastSuccessTime: Long
        get() = prefs.getLong(KEY_LAST_SUCCESS_TIME, 0)
        set(value) = prefs.edit().putLong(KEY_LAST_SUCCESS_TIME, value).apply()

    private var avgConnectionDurationMs: Long
        get() = prefs.getLong(KEY_AVG_CONNECTION_DURATION_MS, 0)
        set(value) = prefs.edit().putLong(KEY_AVG_CONNECTION_DURATION_MS, value).apply()

    // === Session State (resets each app launch) ===

    private var sessionConsecutiveFailures = 0
    private var sessionConsecutiveSuccesses = 0
    private var sessionConnectionStartTime: Long = 0
    private var wasEverConnectedThisSession = false
    private var lastStateEmitted: ConnectionState = ConnectionState.DISCONNECTED

    // === Public API ===

    /**
     * Call when connection attempt starts.
     */
    fun onConnecting() {
        sessionConnectionStartTime = System.currentTimeMillis()
    }

    /**
     * Call when connection succeeds.
     * Returns the state to emit (may suppress if unchanged).
     */
    fun onConnected(): ConnectionState {
        val now = System.currentTimeMillis()

        // Update learned state
        lifetimeSuccesses++
        lastSuccessTime = now
        sessionConsecutiveSuccesses++
        sessionConsecutiveFailures = 0
        wasEverConnectedThisSession = true

        Log.i(TAG, "Connected (lifetime: $lifetimeSuccesses successes, $lifetimeFailures failures)")

        lastStateEmitted = ConnectionState.CONNECTED
        return ConnectionState.CONNECTED
    }

    /**
     * Call when connection is lost or fails.
     * Returns the state to emit (with backpressure - may return same state to suppress).
     */
    fun onConnectionLost(reason: String): ConnectionState {
        val now = System.currentTimeMillis()

        // Update session counters
        sessionConsecutiveFailures++
        sessionConsecutiveSuccesses = 0
        lifetimeFailures++

        // Update average connection duration if we were connected
        if (sessionConnectionStartTime > 0 && wasEverConnectedThisSession) {
            val duration = now - sessionConnectionStartTime
            avgConnectionDurationMs = if (avgConnectionDurationMs == 0L) {
                duration
            } else {
                // Exponential moving average
                (avgConnectionDurationMs * 0.8 + duration * 0.2).toLong()
            }
        }

        // Determine appropriate state based on failure count
        val newState = when {
            // First failure(s) after being connected - go STALE
            wasEverConnectedThisSession && sessionConsecutiveFailures <= staleThresholdFailures -> {
                Log.i(TAG, "Connection lost ($reason), entering STALE [failure $sessionConsecutiveFailures/$errorThresholdFailures]")
                ConnectionState.STALE
            }
            // Exceeded error threshold - go ERROR
            sessionConsecutiveFailures >= errorThresholdFailures -> {
                if (lastStateEmitted != ConnectionState.ERROR) {
                    Log.w(TAG, "Connection failed ($reason), entering ERROR after $sessionConsecutiveFailures failures")
                }
                ConnectionState.ERROR
            }
            // Not yet at error threshold - stay/go STALE
            else -> {
                if (lastStateEmitted != ConnectionState.STALE) {
                    Log.i(TAG, "Connection failed ($reason), entering STALE [failure $sessionConsecutiveFailures/$errorThresholdFailures]")
                }
                ConnectionState.STALE
            }
        }

        // Backpressure: only emit if state actually changed
        if (newState == lastStateEmitted && newState != ConnectionState.CONNECTED) {
            Log.d(TAG, "Suppressing duplicate state: $newState (failure $sessionConsecutiveFailures)")
            return lastStateEmitted // Return same state - caller should not emit
        }

        lastStateEmitted = newState
        return newState
    }

    /**
     * Check if state transition should be announced (for TTS).
     * Separate from state emission - announcements have stricter backpressure.
     */
    fun shouldAnnounce(newState: ConnectionState, previousState: ConnectionState): Boolean {
        // Never announce CONNECTING
        if (newState == ConnectionState.CONNECTING) return false

        // Always announce transitions TO connected
        if (newState == ConnectionState.CONNECTED && previousState != ConnectionState.CONNECTED) return true

        // Only announce FIRST transition to STALE (from CONNECTED)
        if (newState == ConnectionState.STALE && previousState == ConnectionState.CONNECTED) return true

        // Only announce FIRST transition to ERROR (from STALE)
        if (newState == ConnectionState.ERROR && previousState == ConnectionState.STALE) return true

        // Don't announce repeated states or other transitions
        return false
    }

    /**
     * Calculate delay before next retry attempt.
     * Uses exponential backoff with jitter, adapted by learned reliability.
     */
    fun getRetryDelayMs(): Long {
        // Base delay with exponential backoff
        val exponentialDelay = baseDelayMs * backoffMultiplier.toDouble().pow(sessionConsecutiveFailures - 1)
        val cappedDelay = min(exponentialDelay, maxDelayMs.toDouble())

        // Add jitter to prevent thundering herd
        val jitter = cappedDelay * jitterFactor * (Random.nextDouble() - 0.5) * 2
        val delayWithJitter = (cappedDelay + jitter).toLong().coerceAtLeast(baseDelayMs)

        // Adapt based on reliability history
        val reliabilityFactor = calculateReliabilityFactor()
        val adaptedDelay = (delayWithJitter * reliabilityFactor).toLong()

        Log.d(TAG, "Retry delay: ${adaptedDelay}ms (base=$baseDelayMs, failures=$sessionConsecutiveFailures, reliability=${"%.2f".format(reliabilityFactor)})")

        return adaptedDelay
    }

    /**
     * Check if we should even attempt reconnection.
     * Returns false if we should give up (circuit breaker pattern).
     */
    fun shouldAttemptReconnect(): Boolean {
        // Always try if we were connected this session
        if (wasEverConnectedThisSession) return true

        // If never connected and many failures, slow way down but don't give up
        // (Robot might just be powering up)
        return true
    }

    /**
     * Calculate reliability factor based on history.
     * < 1.0 = historically reliable, use faster retries
     * > 1.0 = historically unreliable, use slower retries
     */
    private fun calculateReliabilityFactor(): Double {
        val total = lifetimeSuccesses + lifetimeFailures
        if (total < 10) return 1.0 // Not enough data

        val successRate = lifetimeSuccesses.toDouble() / total

        return when {
            successRate > 0.95 -> 0.5  // Very reliable - fast retry
            successRate > 0.80 -> 0.75 // Reliable
            successRate > 0.50 -> 1.0  // Average
            successRate > 0.20 -> 1.5  // Unreliable
            else -> 2.0               // Very unreliable - slow retry
        }
    }

    /**
     * Reset session state (call on intentional disconnect or app restart).
     */
    fun resetSession() {
        sessionConsecutiveFailures = 0
        sessionConsecutiveSuccesses = 0
        sessionConnectionStartTime = 0
        wasEverConnectedThisSession = false
        lastStateEmitted = ConnectionState.DISCONNECTED
        Log.i(TAG, "Session reset")
    }

    /**
     * Update a configuration parameter at runtime.
     */
    fun setConfig(key: String, value: Any) {
        when (value) {
            is Long -> prefs.edit().putLong(key, value).apply()
            is Int -> prefs.edit().putInt(key, value).apply()
            is Float -> prefs.edit().putFloat(key, value).apply()
            else -> Log.w(TAG, "Unknown config type for $key: ${value::class.simpleName}")
        }
        Log.i(TAG, "Config updated: $key = $value")
    }

    /**
     * Get current stats for debugging/display.
     */
    fun getStats(): Map<String, Any> = mapOf(
        "sessionFailures" to sessionConsecutiveFailures,
        "sessionSuccesses" to sessionConsecutiveSuccesses,
        "wasConnected" to wasEverConnectedThisSession,
        "lifetimeSuccesses" to lifetimeSuccesses,
        "lifetimeFailures" to lifetimeFailures,
        "avgConnectionDurationMs" to avgConnectionDurationMs,
        "currentState" to lastStateEmitted.name,
        "reliabilityFactor" to calculateReliabilityFactor()
    )
}
