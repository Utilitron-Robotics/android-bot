package com.utilitron.robotrelay.service

import android.util.Log
import kotlin.math.*

/**
 * LidarDepthFusion - Confirms people detection by fusing LIDAR + depth camera
 *
 * Problem: LIDAR can "ghost" - false positives from reflections, glass, multi-path
 * Solution: Use depth camera as confirmation. If depth sees nothing where LIDAR
 * claims there's a person, it's likely a ghost.
 *
 * Strategy:
 * 1. Track depth camera detections with timestamps
 * 2. Track LIDAR detections with timestamps
 * 3. CONFIRM a detection only if:
 *    - Both sensors see something at approximately the same location, OR
 *    - Depth camera is stale (no data) - fall back to LIDAR-only
 * 4. REJECT as ghost if:
 *    - Depth camera is fresh and stable but shows nothing at LIDAR location
 */
class LidarDepthFusion {

    companion object {
        private const val TAG = "LIDAR_DEPTH_FUSION"

        // Distance threshold to consider two detections as "same location" (meters)
        private const val CONFIRMATION_DISTANCE = 0.6

        // How fresh depth data must be to use for confirmation (ms)
        private const val DEPTH_FRESHNESS_THRESHOLD_MS = 1000

        // How stable depth must be to consider "no change" (ms without new detections)
        private const val DEPTH_STABILITY_THRESHOLD_MS = 500

        // Minimum confidence to report a detection
        private const val MIN_REPORT_CONFIDENCE = 0.4

        // Ghost detection: if LIDAR sees something new but depth is stable and empty
        private const val GHOST_CHECK_ENABLED = true
    }

    data class Detection(
        val x: Double,
        val y: Double,
        val timestamp: Long,
        val source: Source,
        val confidence: Double = 1.0,
        val width: Double = 0.0,
        val pointCount: Int = 0
    )

    data class ConfirmedPerson(
        val x: Double,
        val y: Double,
        val confidence: Double,   // Higher if both sensors agree
        val source: ConfirmationSource,
        val lidarPoints: Int,
        val depthPoints: Int
    )

    enum class Source { LIDAR, DEPTH }

    enum class ConfirmationSource {
        BOTH_SENSORS,      // Highest confidence - both agree
        DEPTH_ONLY,        // Depth sees it, LIDAR doesn't (unusual but possible)
        LIDAR_CONFIRMED,   // LIDAR + depth confirms existence
        LIDAR_UNCONFIRMED, // LIDAR only, depth stale - use with caution
        GHOST_REJECTED     // LIDAR sees it but depth explicitly shows nothing
    }

    // Recent detections from each sensor
    private val lidarDetections = mutableListOf<Detection>()
    private val depthDetections = mutableListOf<Detection>()

    // Timestamps for staleness tracking
    private var lastLidarUpdate = 0L
    private var lastDepthUpdate = 0L
    private var lastDepthChangeTime = 0L  // When depth detections last changed

    // Previous depth detection count (for change detection)
    private var previousDepthCount = 0

    /**
     * Update with new LIDAR detections
     */
    fun updateLidar(detections: List<Detection>) {
        val now = System.currentTimeMillis()
        lastLidarUpdate = now

        lidarDetections.clear()
        lidarDetections.addAll(detections.map { it.copy(timestamp = now, source = Source.LIDAR) })

        Log.d(TAG, "LIDAR update: ${detections.size} detections")
    }

    /**
     * Update with new depth camera detections
     */
    fun updateDepth(detections: List<Detection>) {
        val now = System.currentTimeMillis()
        lastDepthUpdate = now

        // Detect if depth has changed
        val depthChanged = detections.size != previousDepthCount ||
            detections.any { newDet ->
                depthDetections.none { oldDet ->
                    distance(newDet.x, newDet.y, oldDet.x, oldDet.y) < 0.3
                }
            }

        if (depthChanged) {
            lastDepthChangeTime = now
            previousDepthCount = detections.size
        }

        depthDetections.clear()
        depthDetections.addAll(detections.map { it.copy(timestamp = now, source = Source.DEPTH) })

        Log.d(TAG, "Depth update: ${detections.size} detections, changed=$depthChanged")
    }

    /**
     * Get fused, confirmed person detections.
     * Call this after updating both sensors to get the final list.
     */
    fun getConfirmedPeople(): List<ConfirmedPerson> {
        val now = System.currentTimeMillis()
        val confirmed = mutableListOf<ConfirmedPerson>()

        val depthFresh = (now - lastDepthUpdate) < DEPTH_FRESHNESS_THRESHOLD_MS
        val depthStable = (now - lastDepthChangeTime) > DEPTH_STABILITY_THRESHOLD_MS

        Log.d(TAG, "Fusion check: lidar=${lidarDetections.size} depth=${depthDetections.size} " +
                   "depthFresh=$depthFresh depthStable=$depthStable")

        // Process each LIDAR detection
        for (lidarDet in lidarDetections) {
            // Try to find matching depth detection
            val matchingDepth = depthDetections.find { depthDet ->
                distance(lidarDet.x, lidarDet.y, depthDet.x, depthDet.y) < CONFIRMATION_DISTANCE
            }

            when {
                // BEST: Both sensors see something at this location
                matchingDepth != null -> {
                    val avgX = (lidarDet.x + matchingDepth.x) / 2
                    val avgY = (lidarDet.y + matchingDepth.y) / 2
                    confirmed.add(ConfirmedPerson(
                        x = avgX,
                        y = avgY,
                        confidence = 0.95,  // High confidence when both agree
                        source = ConfirmationSource.BOTH_SENSORS,
                        lidarPoints = lidarDet.pointCount,
                        depthPoints = matchingDepth.pointCount
                    ))
                    Log.i(TAG, "CONFIRMED (both): (%.2f, %.2f)".format(avgX, avgY))
                }

                // Depth is stale - can't confirm, but don't reject either
                !depthFresh -> {
                    confirmed.add(ConfirmedPerson(
                        x = lidarDet.x,
                        y = lidarDet.y,
                        confidence = 0.6,  // Lower confidence without depth confirmation
                        source = ConfirmationSource.LIDAR_UNCONFIRMED,
                        lidarPoints = lidarDet.pointCount,
                        depthPoints = 0
                    ))
                    Log.d(TAG, "UNCONFIRMED (depth stale): (%.2f, %.2f)".format(lidarDet.x, lidarDet.y))
                }

                // GHOST CHECK: Depth is fresh and stable, but sees nothing at LIDAR location
                depthFresh && depthStable && GHOST_CHECK_ENABLED -> {
                    // This is likely a ghost - LIDAR reflection, not a real person
                    Log.w(TAG, "GHOST rejected: LIDAR sees (%.2f, %.2f) but depth is stable+empty"
                        .format(lidarDet.x, lidarDet.y))
                    // Don't add to confirmed list
                }

                // Depth is fresh but changing - might be a person depth hasn't caught yet
                else -> {
                    confirmed.add(ConfirmedPerson(
                        x = lidarDet.x,
                        y = lidarDet.y,
                        confidence = 0.5,  // Medium confidence - depth is active but no match
                        source = ConfirmationSource.LIDAR_UNCONFIRMED,
                        lidarPoints = lidarDet.pointCount,
                        depthPoints = 0
                    ))
                    Log.d(TAG, "UNCONFIRMED (depth active): (%.2f, %.2f)".format(lidarDet.x, lidarDet.y))
                }
            }
        }

        // Also add depth-only detections (rare but possible - LIDAR might miss someone)
        for (depthDet in depthDetections) {
            val hasLidarMatch = lidarDetections.any { lidarDet ->
                distance(lidarDet.x, lidarDet.y, depthDet.x, depthDet.y) < CONFIRMATION_DISTANCE
            }

            if (!hasLidarMatch) {
                confirmed.add(ConfirmedPerson(
                    x = depthDet.x,
                    y = depthDet.y,
                    confidence = 0.7,  // Depth-only is fairly reliable
                    source = ConfirmationSource.DEPTH_ONLY,
                    lidarPoints = 0,
                    depthPoints = depthDet.pointCount
                ))
                Log.d(TAG, "DEPTH-ONLY: (%.2f, %.2f)".format(depthDet.x, depthDet.y))
            }
        }

        // Filter by minimum confidence
        val filtered = confirmed.filter { it.confidence >= MIN_REPORT_CONFIDENCE }

        if (filtered.isNotEmpty()) {
            Log.i(TAG, "Fusion result: ${filtered.size} confirmed people " +
                       "(${filtered.count { it.source == ConfirmationSource.BOTH_SENSORS }} both, " +
                       "${filtered.count { it.source == ConfirmationSource.DEPTH_ONLY }} depth-only, " +
                       "${filtered.count { it.source == ConfirmationSource.LIDAR_UNCONFIRMED }} unconfirmed)")
        }

        return filtered
    }

    /**
     * Check if depth camera data is currently available and fresh
     */
    fun isDepthAvailable(): Boolean {
        return (System.currentTimeMillis() - lastDepthUpdate) < DEPTH_FRESHNESS_THRESHOLD_MS
    }

    /**
     * Get ghost rejection statistics for debugging
     */
    fun getStats(): FusionStats {
        val now = System.currentTimeMillis()
        return FusionStats(
            lidarCount = lidarDetections.size,
            depthCount = depthDetections.size,
            lidarAgeMs = now - lastLidarUpdate,
            depthAgeMs = now - lastDepthUpdate,
            depthStableMs = now - lastDepthChangeTime
        )
    }

    private fun distance(x1: Double, y1: Double, x2: Double, y2: Double): Double {
        return sqrt((x1 - x2).pow(2) + (y1 - y2).pow(2))
    }

    data class FusionStats(
        val lidarCount: Int,
        val depthCount: Int,
        val lidarAgeMs: Long,
        val depthAgeMs: Long,
        val depthStableMs: Long
    )
}
