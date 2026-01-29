package com.utilitron.robotrelay.service

import kotlin.math.sqrt
import kotlin.math.pow

/**
 * Tracks individual people from depth camera detections.
 *
 * Assigns stable IDs, smooths jittery positions, and maintains
 * identity across frames using nearest-neighbor matching.
 *
 * IDs reset when person leaves detection range (not seen for MAX_MISSING_FRAMES).
 */
class PeopleTracker {

    companion object {
        // Maximum distance (meters) to associate detection with existing track
        private const val MAX_ASSOCIATION_DISTANCE = 0.8

        // Frames without detection before track is removed
        private const val MAX_MISSING_FRAMES = 15  // ~3 seconds at 5Hz

        // Position smoothing factor (0-1, higher = more smoothing)
        private const val SMOOTHING_ALPHA = 0.3

        // Velocity smoothing factor
        private const val VELOCITY_ALPHA = 0.2
    }

    data class TrackedPerson(
        val id: Int,
        var x: Double,
        var y: Double,
        var vx: Double = 0.0,  // velocity x (m/s estimate)
        var vy: Double = 0.0,  // velocity y (m/s estimate)
        var heading: Double = 0.0,  // facing direction (radians, 0 = forward)
        var framesMissing: Int = 0,
        var lastUpdateTime: Long = System.currentTimeMillis(),
        var confidence: Double = 1.0  // decays when missing
    )

    private val tracks = mutableMapOf<Int, TrackedPerson>()
    private var nextId = 1
    private val idPool = mutableListOf<Int>()  // Recycled IDs from removed tracks

    /**
     * Update tracker with new detections.
     * @param px X positions of detected people (robot frame, meters)
     * @param py Y positions of detected people (robot frame, meters)
     * @param headings Optional heading angles (radians), inferred from velocity if not provided
     * @return List of currently tracked people with stable IDs
     */
    @Synchronized
    fun update(px: List<Double>, py: List<Double>, headings: List<Double>? = null): List<TrackedPerson> {
        val now = System.currentTimeMillis()

        // Pair detections: list of (x, y)
        val detections = px.zip(py)

        // Track which detections have been matched
        val matchedDetections = mutableSetOf<Int>()
        val matchedTracks = mutableSetOf<Int>()

        // Predict positions based on velocity
        tracks.values.forEach { track ->
            val dt = (now - track.lastUpdateTime) / 1000.0  // seconds
            if (dt > 0 && dt < 2.0) {  // sanity check
                track.x += track.vx * dt
                track.y += track.vy * dt
            }
        }

        // Match detections to existing tracks (greedy nearest-neighbor)
        // Build distance matrix and sort by distance
        val associations = mutableListOf<Triple<Int, Int, Double>>()  // (trackId, detectionIdx, distance)

        for ((detIdx, detection) in detections.withIndex()) {
            for (track in tracks.values) {
                val dist = distance(detection.first, detection.second, track.x, track.y)
                if (dist < MAX_ASSOCIATION_DISTANCE) {
                    associations.add(Triple(track.id, detIdx, dist))
                }
            }
        }

        // Sort by distance and greedily match
        associations.sortBy { it.third }

        for ((trackId, detIdx, _) in associations) {
            if (trackId in matchedTracks || detIdx in matchedDetections) continue

            // Match found - update track
            val track = tracks[trackId]!!
            val (newX, newY) = detections[detIdx]

            // Calculate velocity before smoothing
            val dt = (now - track.lastUpdateTime) / 1000.0
            if (dt > 0 && dt < 2.0) {
                val rawVx = (newX - track.x) / dt
                val rawVy = (newY - track.y) / dt
                track.vx = track.vx * (1 - VELOCITY_ALPHA) + rawVx * VELOCITY_ALPHA
                track.vy = track.vy * (1 - VELOCITY_ALPHA) + rawVy * VELOCITY_ALPHA

                // Infer heading from velocity if moving, or use provided heading
                val providedHeading = headings?.getOrNull(detIdx)
                if (providedHeading != null) {
                    track.heading = track.heading * (1 - SMOOTHING_ALPHA) + providedHeading * SMOOTHING_ALPHA
                } else {
                    // Infer from velocity direction if moving fast enough
                    val speed = sqrt(track.vx.pow(2) + track.vy.pow(2))
                    if (speed > 0.1) {  // Moving at least 0.1 m/s
                        val inferredHeading = kotlin.math.atan2(track.vy, track.vx)
                        track.heading = track.heading * (1 - SMOOTHING_ALPHA) + inferredHeading * SMOOTHING_ALPHA
                    }
                }
            }

            // Smooth position update (exponential moving average)
            track.x = track.x * (1 - SMOOTHING_ALPHA) + newX * SMOOTHING_ALPHA
            track.y = track.y * (1 - SMOOTHING_ALPHA) + newY * SMOOTHING_ALPHA

            track.framesMissing = 0
            track.lastUpdateTime = now
            track.confidence = 1.0

            matchedTracks.add(trackId)
            matchedDetections.add(detIdx)
        }

        // Create new tracks for unmatched detections
        for ((detIdx, detection) in detections.withIndex()) {
            if (detIdx in matchedDetections) continue

            val newId = getNextId()
            tracks[newId] = TrackedPerson(
                id = newId,
                x = detection.first,
                y = detection.second,
                heading = headings?.getOrNull(detIdx) ?: 0.0,
                lastUpdateTime = now
            )
        }

        // Update unmatched tracks (increment missing count, decay confidence)
        for (track in tracks.values) {
            if (track.id !in matchedTracks) {
                track.framesMissing++
                track.confidence *= 0.9  // decay
            }
        }

        // Remove stale tracks and recycle their IDs
        val staleIds = tracks.filter { it.value.framesMissing > MAX_MISSING_FRAMES }.keys.toList()
        for (id in staleIds) {
            tracks.remove(id)
            recycleId(id)
        }

        return tracks.values.toList()
    }

    /**
     * Get all currently tracked people.
     */
    @Synchronized
    fun getTrackedPeople(): List<TrackedPerson> = tracks.values.toList()

    /**
     * Get number of currently tracked people.
     */
    @Synchronized
    fun getCount(): Int = tracks.size

    /**
     * Clear all tracks.
     */
    @Synchronized
    fun clear() {
        tracks.clear()
        idPool.clear()
        nextId = 1
    }

    private fun distance(x1: Double, y1: Double, x2: Double, y2: Double): Double {
        return sqrt((x2 - x1).pow(2) + (y2 - y1).pow(2))
    }

    private fun getNextId(): Int {
        return if (idPool.isNotEmpty()) {
            idPool.removeAt(0)
        } else {
            nextId++
        }
    }

    private fun recycleId(id: Int) {
        // Keep pool sorted so we reuse lower IDs first
        idPool.add(id)
        idPool.sort()
    }
}
