package com.utilitron.robotrelay.service

import android.util.Log
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlin.math.*

/**
 * ObstacleClassifier - LIDAR-based intelligent obstacle detection
 *
 * This is the BRAIN that makes robots useful in crowds instead of plant stands.
 *
 * Key insight: When robot velocity ≈ 0, any movement in LIDAR = obstacle moving
 *
 * Classifies obstacles as:
 * - MOVING_PERSON: Single moving entity (wait patiently, they'll move)
 * - CROWD: Multiple moving entities (announce "please make way")
 * - STATIC_UNEXPECTED: Object not on map (fallen trash, crate - request help)
 * - STATIC_EXPECTED: Wall or mapped obstacle (definitely reroute)
 * - UNKNOWN: Can't determine (fall back to time-based escalation)
 */
class ObstacleClassifier(
    private val onClassificationChanged: (ObstacleClassification) -> Unit
) {
    companion object {
        private const val TAG = "ObstacleClassifier"

        // Velocity threshold to consider robot "stopped" (m/s)
        private const val STOPPED_VELOCITY_THRESHOLD = 0.05

        // Distance threshold for "same point" comparison (meters)
        private const val POINT_MATCH_THRESHOLD = 0.15

        // Movement threshold to classify as "moving" (meters between scans)
        private const val MOVEMENT_THRESHOLD = 0.10

        // Number of scans to keep for movement analysis
        private const val SCAN_HISTORY_SIZE = 10

        // Minimum points to consider an obstacle cluster
        private const val MIN_CLUSTER_POINTS = 3

        // Path corridor width for intersection detection (meters)
        private const val PATH_CORRIDOR_WIDTH = 0.6

        // Human-sized obstacle dimensions (meters)
        private const val HUMAN_MIN_WIDTH = 0.3
        private const val HUMAN_MAX_WIDTH = 1.2

        // Confidence decay per scan without confirmation
        private const val CONFIDENCE_DECAY = 0.1f
    }

    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    // Scan history for movement detection
    private val scanHistory = ArrayDeque<TimestampedScan>(SCAN_HISTORY_SIZE)

    // Current robot state
    private var robotX = 0.0
    private var robotY = 0.0
    private var robotTheta = 0.0
    private var robotLinearVel = 0.0
    private var robotAngularVel = 0.0

    // Navigation path for intersection detection
    private var globalPath: List<Point2D> = emptyList()

    // Occupancy grid map for wall detection
    private var mapData: IntArray? = null
    private var mapWidth = 0
    private var mapHeight = 0
    private var mapResolution = 0.05  // meters per cell
    private var mapOriginX = 0.0
    private var mapOriginY = 0.0
    private var hasMapData = false

    // Classification state
    private val _classification = MutableStateFlow(ObstacleClassification.clear())
    val classification: StateFlow<ObstacleClassification> = _classification

    // Configuration
    var enabled = true
    var sensitivityLevel = SensitivityLevel.MEDIUM

    /**
     * Update robot pose from /robot_pose
     */
    fun updateRobotPose(x: Double, y: Double, theta: Double) {
        robotX = x
        robotY = y
        robotTheta = theta
    }

    /**
     * Update robot velocity from robot_status
     */
    fun updateRobotVelocity(linear: Double, angular: Double) {
        robotLinearVel = linear
        robotAngularVel = angular
    }

    /**
     * Update global navigation path from /global_path
     */
    fun updateGlobalPath(pathPoints: List<Point2D>) {
        globalPath = pathPoints
        Log.d(TAG, "Updated global path with ${pathPoints.size} points")
    }

    /**
     * Update occupancy grid map from /map
     * This is THE KEY to distinguishing walls from unexpected obstacles!
     */
    fun updateMap(
        data: IntArray,
        width: Int,
        height: Int,
        resolution: Double,
        originX: Double,
        originY: Double
    ) {
        mapData = data
        mapWidth = width
        mapHeight = height
        mapResolution = resolution
        mapOriginX = originX
        mapOriginY = originY
        hasMapData = true
        Log.i(TAG, "Updated map: ${width}x${height}, res=${resolution}m, origin=($originX, $originY)")
    }

    /**
     * Check if a world coordinate is a known obstacle (wall) on the map.
     * Returns true if the point is marked as occupied in the occupancy grid.
     */
    private fun isKnownObstacle(worldX: Double, worldY: Double): Boolean {
        if (!hasMapData || mapData == null) return false

        // Convert world coordinates to map cell indices
        val mapX = ((worldX - mapOriginX) / mapResolution).toInt()
        val mapY = ((worldY - mapOriginY) / mapResolution).toInt()

        // Check bounds
        if (mapX < 0 || mapX >= mapWidth || mapY < 0 || mapY >= mapHeight) {
            return false
        }

        // Get occupancy value (0=free, 100=occupied, -1=unknown)
        val index = mapY * mapWidth + mapX
        if (index < 0 || index >= mapData!!.size) return false

        val occupancy = mapData!![index]
        return occupancy > 50  // Consider >50 as occupied (wall)
    }

    /**
     * Check if ALL points in an obstacle cluster are at known wall locations.
     * Only returns true if the entire cluster matches the map.
     */
    private fun isClusterOnKnownWall(cluster: ObstacleCluster): Boolean {
        if (!hasMapData) return false

        // Check center point and a few samples
        val worldCenter = transformToWorld(cluster.center.x, cluster.center.y, robotX, robotY, robotTheta)
        if (!isKnownObstacle(worldCenter.x, worldCenter.y)) {
            return false
        }

        // Check some sample points too for confidence
        val samplePoints = cluster.points.take(5)
        val matchCount = samplePoints.count { p ->
            val wp = transformToWorld(p.x, p.y, robotX, robotY, robotTheta)
            isKnownObstacle(wp.x, wp.y)
        }

        // If most samples match map obstacles, it's a known wall
        return matchCount >= samplePoints.size * 0.6
    }

    /**
     * Process new LIDAR scan data
     * Called from RobotWebSocketClient when /laser_data arrives
     *
     * @param px Array of X coordinates (robot frame)
     * @param py Array of Y coordinates (robot frame)
     */
    fun processLidarScan(px: List<Double>, py: List<Double>) {
        if (!enabled) return
        if (px.size != py.size || px.isEmpty()) return

        val timestamp = System.currentTimeMillis()
        val points = px.zip(py).map { (x, y) -> Point2D(x, y) }

        // Store scan in history
        scanHistory.addLast(TimestampedScan(timestamp, points))
        while (scanHistory.size > SCAN_HISTORY_SIZE) {
            scanHistory.removeFirst()
        }

        // Need at least 2 scans to detect movement
        if (scanHistory.size < 2) return

        // Analyze obstacle
        scope.launch {
            val classification = analyzeObstacle(points, timestamp)
            if (classification != _classification.value) {
                Log.i(TAG, "Classification changed: ${_classification.value.type} -> ${classification.type}")
                _classification.value = classification
                onClassificationChanged(classification)
            }
        }
    }

    /**
     * Main analysis logic
     */
    private fun analyzeObstacle(currentPoints: List<Point2D>, timestamp: Long): ObstacleClassification {
        // Step 1: Find obstacle clusters in the path corridor
        val pathObstacles = findObstaclesInPath(currentPoints)

        if (pathObstacles.isEmpty()) {
            return ObstacleClassification.clear()
        }

        // Step 2: Determine if robot is stopped (high confidence for movement detection)
        val robotStopped = abs(robotLinearVel) < STOPPED_VELOCITY_THRESHOLD &&
                          abs(robotAngularVel) < STOPPED_VELOCITY_THRESHOLD * 2

        // Step 3: Detect movement by comparing to previous scans
        val movementInfo = detectMovement(pathObstacles, robotStopped)

        // Step 4: Classify based on movement and size
        return classifyObstacle(pathObstacles, movementInfo, robotStopped)
    }

    /**
     * Find obstacle points that intersect with the navigation path
     */
    private fun findObstaclesInPath(points: List<Point2D>): List<ObstacleCluster> {
        if (globalPath.isEmpty()) {
            // No path info - use front arc as fallback
            return findObstaclesInFrontArc(points)
        }

        // Transform points to world frame
        val worldPoints = points.map { p ->
            transformToWorld(p.x, p.y, robotX, robotY, robotTheta)
        }

        // Find points within corridor of path
        val pathObstaclePoints = worldPoints.filter { wp ->
            globalPath.any { pathPoint ->
                distance(wp, pathPoint) < PATH_CORRIDOR_WIDTH
            }
        }

        if (pathObstaclePoints.isEmpty()) {
            return emptyList()
        }

        // Cluster the points
        return clusterPoints(pathObstaclePoints)
    }

    /**
     * Fallback: Find obstacles in front arc when no path available
     */
    private fun findObstaclesInFrontArc(points: List<Point2D>): List<ObstacleCluster> {
        // Front arc: points roughly in front of robot (±45 degrees)
        val frontPoints = points.filter { p ->
            val angle = atan2(p.y, p.x)
            abs(angle) < PI / 4 && p.x > 0 && p.x < 3.0  // Within 3m, front 90°
        }

        if (frontPoints.isEmpty()) {
            return emptyList()
        }

        return clusterPoints(frontPoints)
    }

    /**
     * Cluster nearby points into obstacle groups
     */
    private fun clusterPoints(points: List<Point2D>): List<ObstacleCluster> {
        if (points.isEmpty()) return emptyList()

        val clusters = mutableListOf<MutableList<Point2D>>()
        val assigned = BooleanArray(points.size)

        for (i in points.indices) {
            if (assigned[i]) continue

            val cluster = mutableListOf(points[i])
            assigned[i] = true

            // Find all nearby points
            for (j in (i + 1) until points.size) {
                if (assigned[j]) continue

                // Check if close to any point in cluster
                if (cluster.any { distance(it, points[j]) < POINT_MATCH_THRESHOLD * 2 }) {
                    cluster.add(points[j])
                    assigned[j] = true
                }
            }

            if (cluster.size >= MIN_CLUSTER_POINTS) {
                clusters.add(cluster)
            }
        }

        return clusters.map { clusterPoints ->
            val centerX = clusterPoints.map { it.x }.average()
            val centerY = clusterPoints.map { it.y }.average()
            val width = clusterPoints.maxOf { it.x } - clusterPoints.minOf { it.x }
            val depth = clusterPoints.maxOf { it.y } - clusterPoints.minOf { it.y }

            ObstacleCluster(
                center = Point2D(centerX, centerY),
                points = clusterPoints,
                width = maxOf(width, depth),  // Use larger dimension
                pointCount = clusterPoints.size
            )
        }
    }

    /**
     * Detect if obstacles are moving by comparing scan history
     */
    private fun detectMovement(
        currentClusters: List<ObstacleCluster>,
        robotStopped: Boolean
    ): MovementInfo {
        if (scanHistory.size < 3) {
            return MovementInfo(isMoving = false, confidence = 0f, movingCount = 0)
        }

        val previousScan = scanHistory[scanHistory.size - 2]
        val olderScan = scanHistory[scanHistory.size - 3]

        // If robot is stopped, movement detection is highly reliable
        val baseConfidence = if (robotStopped) 0.9f else 0.5f

        var movingClusterCount = 0
        var totalMovement = 0.0

        for (cluster in currentClusters) {
            // Find matching cluster in previous scan
            val previousMatch = findMatchingCluster(cluster, previousScan.points)
            val olderMatch = findMatchingCluster(cluster, olderScan.points)

            if (previousMatch != null && olderMatch != null) {
                // Calculate movement between scans
                val movement1 = distance(cluster.center, previousMatch)
                val movement2 = distance(previousMatch, olderMatch)

                val avgMovement = (movement1 + movement2) / 2

                // Compensate for robot movement if not stopped
                val effectiveMovement = if (robotStopped) {
                    avgMovement
                } else {
                    // Rough compensation - subtract expected robot-induced movement
                    val scanInterval = (previousScan.timestamp - olderScan.timestamp) / 1000.0
                    val robotMovement = abs(robotLinearVel) * scanInterval
                    maxOf(0.0, avgMovement - robotMovement)
                }

                if (effectiveMovement > MOVEMENT_THRESHOLD) {
                    movingClusterCount++
                    totalMovement += effectiveMovement
                }
            }
        }

        val isMoving = movingClusterCount > 0
        val confidence = if (isMoving) {
            (baseConfidence * minOf(1f, (totalMovement / 0.5).toFloat())).coerceIn(0f, 1f)
        } else {
            baseConfidence
        }

        return MovementInfo(
            isMoving = isMoving,
            confidence = confidence,
            movingCount = movingClusterCount,
            averageMovement = if (movingClusterCount > 0) totalMovement / movingClusterCount else 0.0
        )
    }

    /**
     * Find a matching point cluster in previous scan data
     */
    private fun findMatchingCluster(cluster: ObstacleCluster, previousPoints: List<Point2D>): Point2D? {
        // Find centroid of nearby points in previous scan
        val nearbyPoints = previousPoints.filter { p ->
            distance(p, cluster.center) < cluster.width + POINT_MATCH_THRESHOLD
        }

        if (nearbyPoints.size < MIN_CLUSTER_POINTS) return null

        return Point2D(
            nearbyPoints.map { it.x }.average(),
            nearbyPoints.map { it.y }.average()
        )
    }

    /**
     * Final classification based on all gathered information
     */
    private fun classifyObstacle(
        clusters: List<ObstacleCluster>,
        movement: MovementInfo,
        robotStopped: Boolean
    ): ObstacleClassification {
        if (clusters.isEmpty()) {
            return ObstacleClassification.clear()
        }

        val totalWidth = clusters.sumOf { it.width }
        val clusterCount = clusters.size

        // Determine type based on movement and size
        val type = when {
            // Multiple moving entities = crowd
            movement.isMoving && movement.movingCount > 1 -> ObstacleType.CROWD

            // Single moving entity of human size = person
            movement.isMoving && clusters.any {
                it.width in HUMAN_MIN_WIDTH..HUMAN_MAX_WIDTH
            } -> ObstacleType.MOVING_PERSON

            // Moving but unusual size = could be another robot
            movement.isMoving -> ObstacleType.MOVING_UNKNOWN

            // Static, human-sized = person standing still
            !movement.isMoving && robotStopped && clusters.any {
                it.width in HUMAN_MIN_WIDTH..HUMAN_MAX_WIDTH
            } -> ObstacleType.STATIC_PERSON

            // Static, large = unexpected obstacle (crate, fallen object)
            !movement.isMoving && totalWidth > 0.5 -> ObstacleType.STATIC_UNEXPECTED

            // Can't determine
            else -> ObstacleType.UNKNOWN
        }

        // Calculate confidence
        val confidence = when {
            robotStopped && movement.isMoving -> movement.confidence
            robotStopped && !movement.isMoving -> 0.8f
            !robotStopped -> movement.confidence * 0.6f  // Lower confidence when moving
            else -> 0.5f
        }

        // Determine if it's in the path
        val inPath = globalPath.isNotEmpty() || clusters.any { it.center.x > 0 && it.center.x < 2.0 }

        return ObstacleClassification(
            type = type,
            confidence = confidence,
            inPath = inPath,
            clusterCount = clusterCount,
            averageDistance = clusters.map { sqrt(it.center.x.pow(2) + it.center.y.pow(2)) }.average(),
            isMoving = movement.isMoving,
            suggestedAction = determineSuggestedAction(type, confidence)
        )
    }

    /**
     * Determine what action the robot should take
     */
    private fun determineSuggestedAction(type: ObstacleType, confidence: Float): SuggestedAction {
        return when (type) {
            ObstacleType.CLEAR -> SuggestedAction.NONE
            ObstacleType.MOVING_PERSON -> SuggestedAction.WAIT_PATIENTLY
            ObstacleType.CROWD -> SuggestedAction.ANNOUNCE_CROWD
            ObstacleType.STATIC_PERSON -> SuggestedAction.POLITE_REQUEST
            ObstacleType.STATIC_UNEXPECTED -> SuggestedAction.REQUEST_HELP
            ObstacleType.MOVING_UNKNOWN -> SuggestedAction.WAIT_AND_OBSERVE
            ObstacleType.UNKNOWN -> SuggestedAction.ESCALATE_NORMALLY
        }
    }

    // === Utility functions ===

    private fun distance(p1: Point2D, p2: Point2D): Double {
        return sqrt((p1.x - p2.x).pow(2) + (p1.y - p2.y).pow(2))
    }

    private fun transformToWorld(localX: Double, localY: Double,
                                  robotX: Double, robotY: Double, robotTheta: Double): Point2D {
        val cos = cos(robotTheta)
        val sin = sin(robotTheta)
        return Point2D(
            robotX + localX * cos - localY * sin,
            robotY + localX * sin + localY * cos
        )
    }

    fun destroy() {
        scope.cancel()
    }
}

// === Data Classes ===

data class Point2D(val x: Double, val y: Double)

data class TimestampedScan(
    val timestamp: Long,
    val points: List<Point2D>
)

data class ObstacleCluster(
    val center: Point2D,
    val points: List<Point2D>,
    val width: Double,
    val pointCount: Int
)

data class MovementInfo(
    val isMoving: Boolean,
    val confidence: Float,
    val movingCount: Int,
    val averageMovement: Double = 0.0
)

enum class ObstacleType {
    CLEAR,              // No obstacle in path
    MOVING_PERSON,      // Single moving human-sized entity
    CROWD,              // Multiple moving entities
    STATIC_PERSON,      // Person standing still
    STATIC_UNEXPECTED,  // Object not on map (crate, fallen trash)
    MOVING_UNKNOWN,     // Moving but can't classify (robot?)
    UNKNOWN             // Can't determine
}

enum class SuggestedAction {
    NONE,               // Path is clear
    WAIT_PATIENTLY,     // Moving obstacle - wait a few seconds
    WAIT_AND_OBSERVE,   // Unknown moving thing - wait and see
    POLITE_REQUEST,     // Person standing still - ask politely
    ANNOUNCE_CROWD,     // Crowd blocking - louder announcement
    REQUEST_HELP,       // Static unexpected obstacle - need human intervention
    ESCALATE_NORMALLY   // Can't determine - use time-based escalation
}

enum class SensitivityLevel {
    LOW,    // Less sensitive - fewer false positives
    MEDIUM, // Balanced
    HIGH    // More sensitive - catches more but may have false positives
}

data class ObstacleClassification(
    val type: ObstacleType,
    val confidence: Float,
    val inPath: Boolean,
    val clusterCount: Int,
    val averageDistance: Double,
    val isMoving: Boolean,
    val suggestedAction: SuggestedAction
) {
    companion object {
        fun clear() = ObstacleClassification(
            type = ObstacleType.CLEAR,
            confidence = 1f,
            inPath = false,
            clusterCount = 0,
            averageDistance = 0.0,
            isMoving = false,
            suggestedAction = SuggestedAction.NONE
        )
    }

    fun toJson(): Map<String, Any> = mapOf(
        "type" to type.name,
        "confidence" to confidence,
        "in_path" to inPath,
        "cluster_count" to clusterCount,
        "average_distance" to averageDistance,
        "is_moving" to isMoving,
        "suggested_action" to suggestedAction.name
    )
}
