package com.utilitron.robotrelay.service

import android.util.Log
import kotlin.math.*

/**
 * DepthPeopleDetector - Detects people from raw depth camera data
 *
 * Since the robot's built-in /detected_people_array topic doesn't publish,
 * we process raw depth data ourselves to find humans.
 *
 * Detection arena: 0.5m - 4m in front, ±2m to sides
 * Human height filter: 0.5m - 2.0m above ground (filters out floor/ceiling)
 * Cluster size: 0.3m - 1.2m width (human-sized)
 */
class DepthPeopleDetector {

    companion object {
        private const val TAG = "DEPTH_PEOPLE"

        // Detection arena bounds (robot frame, meters)
        private const val MIN_X = 0.5    // Minimum distance in front
        private const val MAX_X = 4.0    // Maximum distance in front
        private const val MIN_Y = -2.0   // Left side
        private const val MAX_Y = 2.0    // Right side

        // Human height filter (Z axis, meters above ground)
        private const val MIN_HEIGHT = 0.5   // Filter out floor
        private const val MAX_HEIGHT = 2.0   // Filter out ceiling

        // Clustering parameters - TIGHTENED to reduce ghosting
        private const val CLUSTER_DISTANCE = 0.35  // Max distance between points in cluster (tighter = less ghosting)
        private const val MIN_CLUSTER_POINTS = 8   // Minimum points to be a person (higher = more evidence required)
        private const val MIN_CLUSTER_WIDTH = 0.25 // Minimum human width (allow slim profiles)
        private const val MAX_CLUSTER_WIDTH = 1.2  // Maximum human width

        // Cross-section validation - reject suspiciously thin clusters (likely reflections)
        private const val MIN_CROSS_SECTION_RATIO = 0.15  // min(width,depth)/max(width,depth) - 0.15 = very elongated allowed

        // Rate limiting
        private const val MIN_PROCESS_INTERVAL_MS = 100 // Don't process faster than 10Hz
    }

    private var lastProcessTime = 0L

    data class DetectedPerson(
        val x: Double,      // Position in robot frame (meters)
        val y: Double,
        val width: Double,  // Estimated width
        val confidence: Double,
        val pointCount: Int
    )

    /**
     * Process raw point cloud data from depth camera.
     *
     * @param points List of 3D points (x, y, z) in robot frame
     * @return List of detected person positions (x, y in robot frame)
     */
    fun processPointCloud(points: List<Triple<Double, Double, Double>>): List<DetectedPerson> {
        val now = System.currentTimeMillis()
        if (now - lastProcessTime < MIN_PROCESS_INTERVAL_MS) {
            return emptyList()
        }
        lastProcessTime = now

        if (points.isEmpty()) {
            Log.d(TAG, "No points to process")
            return emptyList()
        }

        Log.d(TAG, "Processing ${points.size} points")

        // Step 1: Filter points to detection arena and human height
        val filteredPoints = points.filter { (x, y, z) ->
            x in MIN_X..MAX_X &&
            y in MIN_Y..MAX_Y &&
            z in MIN_HEIGHT..MAX_HEIGHT
        }

        Log.d(TAG, "After filtering: ${filteredPoints.size} points in arena")

        if (filteredPoints.size < MIN_CLUSTER_POINTS) {
            return emptyList()
        }

        // Step 2: Project to 2D (ignore Z for clustering, we already filtered by height)
        val points2D = filteredPoints.map { (x, y, _) -> Pair(x, y) }

        // Step 3: Cluster points
        val clusters = clusterPoints(points2D)
        Log.d(TAG, "Found ${clusters.size} clusters")

        // Step 4: Filter clusters by human size and cross-section
        val people = clusters.filter { cluster ->
            val width = cluster.maxOf { it.first } - cluster.minOf { it.first }
            val depth = cluster.maxOf { it.second } - cluster.minOf { it.second }
            val size = maxOf(width, depth)
            val minDim = minOf(width, depth)

            // Cross-section ratio: thin line-like clusters are likely reflections/ghosts
            val crossSectionRatio = if (size > 0.01) minDim / size else 0.0

            val validSize = size in MIN_CLUSTER_WIDTH..MAX_CLUSTER_WIDTH
            val validCrossSection = crossSectionRatio >= MIN_CROSS_SECTION_RATIO || minDim >= 0.15
            val validPoints = cluster.size >= MIN_CLUSTER_POINTS

            if (!validCrossSection && cluster.size >= MIN_CLUSTER_POINTS) {
                Log.d(TAG, "Rejected thin cluster: ${cluster.size} pts, " +
                          "size=%.2f, ratio=%.2f (likely ghost/reflection)".format(size, crossSectionRatio))
            }

            validSize && validCrossSection && validPoints
        }.map { cluster ->
            val centerX = cluster.map { it.first }.average()
            val centerY = cluster.map { it.second }.average()
            val width = maxOf(
                cluster.maxOf { it.first } - cluster.minOf { it.first },
                cluster.maxOf { it.second } - cluster.minOf { it.second }
            )
            val confidence = (cluster.size.toDouble() / 100).coerceIn(0.5, 1.0)

            DetectedPerson(
                x = centerX,
                y = centerY,
                width = width,
                confidence = confidence,
                pointCount = cluster.size
            )
        }

        Log.i(TAG, "Detected ${people.size} people: ${people.map { "(%.2f, %.2f)".format(it.x, it.y) }}")

        return people
    }

    /**
     * Process flat point arrays (px, py format from some topics)
     */
    fun processPointArrays(px: List<Double>, py: List<Double>): List<DetectedPerson> {
        if (px.size != py.size || px.isEmpty()) return emptyList()

        // These are 2D points, assume human height (can't filter by Z)
        val filteredPoints = px.zip(py).filter { (x, y) ->
            x in MIN_X..MAX_X && y in MIN_Y..MAX_Y
        }

        Log.d(TAG, "Processing ${px.size} 2D points, ${filteredPoints.size} in arena")

        if (filteredPoints.size < MIN_CLUSTER_POINTS) {
            return emptyList()
        }

        val clusters = clusterPoints(filteredPoints)

        return clusters.filter { cluster ->
            val width = cluster.maxOf { it.first } - cluster.minOf { it.first }
            val depth = cluster.maxOf { it.second } - cluster.minOf { it.second }
            val size = maxOf(width, depth)
            val minDim = minOf(width, depth)

            // Cross-section ratio: thin line-like clusters are likely reflections/ghosts
            val crossSectionRatio = if (size > 0.01) minDim / size else 0.0

            val validSize = size in MIN_CLUSTER_WIDTH..MAX_CLUSTER_WIDTH
            val validCrossSection = crossSectionRatio >= MIN_CROSS_SECTION_RATIO || minDim >= 0.15
            val validPoints = cluster.size >= MIN_CLUSTER_POINTS

            if (!validCrossSection && cluster.size >= MIN_CLUSTER_POINTS) {
                Log.d(TAG, "Rejected thin 2D cluster: ${cluster.size} pts, " +
                          "size=%.2f, ratio=%.2f (likely ghost)".format(size, crossSectionRatio))
            }

            validSize && validCrossSection && validPoints
        }.map { cluster ->
            DetectedPerson(
                x = cluster.map { it.first }.average(),
                y = cluster.map { it.second }.average(),
                width = maxOf(
                    cluster.maxOf { it.first } - cluster.minOf { it.first },
                    cluster.maxOf { it.second } - cluster.minOf { it.second }
                ),
                confidence = (cluster.size.toDouble() / 100).coerceIn(0.5, 1.0),
                pointCount = cluster.size
            )
        }.also {
            if (it.isNotEmpty()) {
                Log.i(TAG, "Detected ${it.size} people from 2D points (tighter clustering)")
            }
        }
    }

    /**
     * Simple distance-based clustering (DBSCAN-lite)
     */
    private fun clusterPoints(points: List<Pair<Double, Double>>): List<List<Pair<Double, Double>>> {
        if (points.isEmpty()) return emptyList()

        val clusters = mutableListOf<MutableList<Pair<Double, Double>>>()
        val assigned = BooleanArray(points.size)

        for (i in points.indices) {
            if (assigned[i]) continue

            val cluster = mutableListOf(points[i])
            assigned[i] = true

            // Expand cluster with nearby points
            var j = 0
            while (j < cluster.size) {
                val current = cluster[j]
                for (k in points.indices) {
                    if (assigned[k]) continue
                    if (distance(current, points[k]) < CLUSTER_DISTANCE) {
                        cluster.add(points[k])
                        assigned[k] = true
                    }
                }
                j++
            }

            clusters.add(cluster)
        }

        return clusters
    }

    private fun distance(p1: Pair<Double, Double>, p2: Pair<Double, Double>): Double {
        return sqrt((p1.first - p2.first).pow(2) + (p1.second - p2.second).pow(2))
    }
}
