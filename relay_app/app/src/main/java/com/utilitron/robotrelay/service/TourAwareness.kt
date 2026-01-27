package com.utilitron.robotrelay.service

import android.util.Log
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.StateFlow

/**
 * TourAwareness - Monitors group status during tour navigation.
 *
 * Uses depth camera people detection to track the tour group and trigger
 * callbacks when:
 * - Group falls behind (distance increases)
 * - Path is blocked by person (need to say "excuse me")
 * - Group is lost (no people detected for extended time)
 * - Person approaches (greeting opportunity)
 *
 * Design: Runs as a coroutine during navigation, uses existing StateFlows
 * from RobotWebSocketClient. Does NOT control the robot - just notifies.
 */
class TourAwareness(
    private val peopleDetected: StateFlow<Boolean>,
    private val peopleCount: StateFlow<Int>,
    private val avgPeopleDistance: StateFlow<Float>,
    private val navStatus: () -> Int,  // Lambda to get current nav status
    private val onGroupFallingBehind: suspend (distanceMeters: Float) -> Unit,
    private val onPathBlockedByPerson: suspend () -> Unit,
    private val onGroupLost: suspend () -> Unit,
    private val onPersonApproaching: suspend (distanceMeters: Float) -> Unit
) {
    companion object {
        private const val TAG = "TourAwareness"

        // Thresholds
        const val GROUP_FOLLOW_DISTANCE = 3.0f    // Normal following distance (meters)
        const val GROUP_FALLING_BEHIND = 5.0f     // "Please keep up" threshold
        const val GROUP_LOST_DISTANCE = 8.0f      // "Where did everyone go?" threshold
        const val BLOCKED_DISTANCE = 0.8f         // "Excuse me" threshold (person in path)
        const val APPROACHING_DISTANCE = 2.0f     // Greeting distance

        // Timing
        const val CHECK_INTERVAL_MS = 500L        // How often to check
        const val FALLING_BEHIND_COOLDOWN_MS = 15000L  // Don't spam "keep up"
        const val BLOCKED_COOLDOWN_MS = 10000L    // Don't spam "excuse me"
        const val LOST_GRACE_PERIOD_MS = 10000L   // Wait before declaring group lost
        const val APPROACHING_COOLDOWN_MS = 30000L // Don't spam greetings
    }

    private var monitorJob: Job? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // Cooldown tracking
    private var lastFallingBehindTime = 0L
    private var lastBlockedTime = 0L
    private var lastApproachingTime = 0L
    private var groupLostSince = 0L  // 0 = group is present

    // State tracking for edge detection
    private var wasGroupPresent = false

    /**
     * Start monitoring. Call when navigation begins.
     */
    fun startMonitoring() {
        if (monitorJob?.isActive == true) return

        Log.i(TAG, "Starting tour awareness monitoring")
        resetState()

        monitorJob = scope.launch {
            while (isActive) {
                delay(CHECK_INTERVAL_MS)
                checkGroupStatus()
            }
        }
    }

    /**
     * Stop monitoring. Call when navigation ends.
     */
    fun stopMonitoring() {
        Log.i(TAG, "Stopping tour awareness monitoring")
        monitorJob?.cancel()
        monitorJob = null
    }

    /**
     * Check if currently monitoring.
     */
    val isMonitoring: Boolean get() = monitorJob?.isActive == true

    /**
     * Reset state for new tour segment.
     */
    fun resetState() {
        lastFallingBehindTime = 0L
        lastBlockedTime = 0L
        lastApproachingTime = 0L
        groupLostSince = 0L
        wasGroupPresent = false
    }

    private suspend fun checkGroupStatus() {
        val now = System.currentTimeMillis()
        val detected = peopleDetected.value
        val count = peopleCount.value
        val distance = avgPeopleDistance.value
        val isNavigating = navStatus() == 601  // 601 = moving

        // Only do group tracking during active navigation
        if (!isNavigating) {
            // Reset lost timer when not navigating
            groupLostSince = 0L
            return
        }

        val groupPresent = detected && count > 0 && distance < Float.MAX_VALUE

        // === BLOCKED BY PERSON ===
        // Someone standing right in front during navigation
        if (groupPresent && distance < BLOCKED_DISTANCE) {
            if (now - lastBlockedTime > BLOCKED_COOLDOWN_MS) {
                Log.i(TAG, "Path blocked by person at ${String.format("%.2f", distance)}m")
                lastBlockedTime = now
                onPathBlockedByPerson()
            }
            return  // Don't check other conditions when blocked
        }

        // === GROUP FALLING BEHIND ===
        // Group is present but getting far
        if (groupPresent && distance > GROUP_FALLING_BEHIND) {
            if (now - lastFallingBehindTime > FALLING_BEHIND_COOLDOWN_MS) {
                Log.i(TAG, "Group falling behind at ${String.format("%.2f", distance)}m")
                lastFallingBehindTime = now
                onGroupFallingBehind(distance)
            }
        }

        // === GROUP LOST ===
        // No people detected for extended period during navigation
        if (!groupPresent) {
            if (groupLostSince == 0L) {
                groupLostSince = now
                Log.d(TAG, "Group disappeared, starting grace period")
            } else if (now - groupLostSince > LOST_GRACE_PERIOD_MS) {
                Log.i(TAG, "Group lost - no people detected for ${(now - groupLostSince) / 1000}s")
                groupLostSince = now  // Reset to avoid spamming
                onGroupLost()
            }
        } else {
            // Group is back
            if (groupLostSince > 0) {
                Log.d(TAG, "Group returned after ${(now - groupLostSince) / 1000}s")
            }
            groupLostSince = 0L
        }

        // === PERSON APPROACHING ===
        // Rising edge: someone just entered detection range
        if (groupPresent && !wasGroupPresent && distance < APPROACHING_DISTANCE) {
            if (now - lastApproachingTime > APPROACHING_COOLDOWN_MS) {
                Log.i(TAG, "Person approaching at ${String.format("%.2f", distance)}m")
                lastApproachingTime = now
                onPersonApproaching(distance)
            }
        }

        wasGroupPresent = groupPresent
    }

    fun destroy() {
        stopMonitoring()
        scope.cancel()
    }
}
