package com.utilitron.robotrelay.service

import android.content.Context
import android.util.Log
import java.io.File
import java.io.FileWriter
import java.text.SimpleDateFormat
import java.util.*

/**
 * PeopleDetectionLogger - Logs all people detection activity to a file for debugging
 *
 * Log file location: /data/data/com.utilitron.robotrelay/files/people_detection.log
 * Pull from device: adb pull /data/data/com.utilitron.robotrelay/files/people_detection.log
 *
 * Logs include:
 * - Topic discoveries (what topics exist on the robot)
 * - Incoming people-related messages
 * - Fusion decisions (confirmed/rejected ghosts)
 * - Detection events
 */
class PeopleDetectionLogger private constructor(private val context: Context) {

    companion object {
        private const val TAG = "PeopleDetectionLogger"
        private const val LOG_FILE = "people_detection.log"
        private const val MAX_LOG_SIZE = 5 * 1024 * 1024  // 5MB max

        @Volatile
        private var instance: PeopleDetectionLogger? = null

        fun init(context: Context) {
            if (instance == null) {
                synchronized(this) {
                    if (instance == null) {
                        instance = PeopleDetectionLogger(context.applicationContext)
                        instance?.log("=== LOGGER INITIALIZED ===")
                        instance?.log("Pull log: adb pull /data/data/com.utilitron.robotrelay/files/$LOG_FILE")
                    }
                }
            }
        }

        fun get(): PeopleDetectionLogger? = instance
    }

    private val logFile: File = File(context.filesDir, LOG_FILE)
    private val dateFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)

    init {
        // Rotate log if too large
        if (logFile.exists() && logFile.length() > MAX_LOG_SIZE) {
            val backupFile = File(context.filesDir, "$LOG_FILE.old")
            logFile.renameTo(backupFile)
        }
    }

    /**
     * Log a message with timestamp
     */
    @Synchronized
    fun log(message: String) {
        try {
            val timestamp = dateFormat.format(Date())
            val line = "[$timestamp] $message\n"

            FileWriter(logFile, true).use { writer ->
                writer.append(line)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to write log: ${e.message}")
        }
    }

    /**
     * Log topic discovery event
     */
    fun logTopicDiscovery(topics: List<String>) {
        log("=== TOPIC DISCOVERY (${topics.size} topics) ===")

        // Filter and highlight people-related topics
        val peopleKeywords = listOf("people", "person", "human", "body", "skeleton",
            "depth", "camera", "detect", "track", "pose", "face", "hand")

        val relevantTopics = topics.filter { topic ->
            peopleKeywords.any { keyword -> topic.lowercase().contains(keyword) }
        }

        log("RELEVANT TOPICS (${relevantTopics.size}):")
        relevantTopics.forEach { log("  - $it") }

        // Also log all topics in a compact form
        log("ALL TOPICS: ${topics.joinToString(", ")}")
    }

    /**
     * Log when a people-related topic receives data
     */
    fun logTopicData(topic: String, dataSize: Int, preview: String? = null) {
        val msg = "TOPIC DATA: $topic (${dataSize} bytes)"
        log(if (preview != null) "$msg: $preview" else msg)
    }

    /**
     * Log LIDAR detection
     */
    fun logLidarDetection(pointCount: Int, detectedPeople: Int, positions: List<Pair<Double, Double>>) {
        val posStr = positions.take(5).joinToString(", ") { "(%.2f, %.2f)".format(it.first, it.second) }
        log("LIDAR: $pointCount pts → $detectedPeople people at [$posStr]")
    }

    /**
     * Log depth camera detection
     */
    fun logDepthDetection(pointCount: Int, detectedPeople: Int, positions: List<Pair<Double, Double>>) {
        val posStr = positions.take(5).joinToString(", ") { "(%.2f, %.2f)".format(it.first, it.second) }
        log("DEPTH: $pointCount pts → $detectedPeople people at [$posStr]")
    }

    /**
     * Log fusion decision
     */
    fun logFusionDecision(
        lidarCount: Int,
        depthCount: Int,
        confirmedCount: Int,
        ghostsRejected: Int,
        confirmedPositions: List<Pair<Double, Double>>
    ) {
        val posStr = confirmedPositions.take(5).joinToString(", ") { "(%.2f, %.2f)".format(it.first, it.second) }
        log("FUSION: lidar=$lidarCount, depth=$depthCount → $confirmedCount confirmed, $ghostsRejected ghosts at [$posStr]")
    }

    /**
     * Log ghost rejection
     */
    fun logGhostRejected(x: Double, y: Double, reason: String) {
        log("GHOST REJECTED: (%.2f, %.2f) - $reason".format(x, y))
    }

    /**
     * Log raw message from a topic (for debugging unknown formats)
     */
    fun logRawMessage(topic: String, keys: Set<String>, preview: String) {
        log("RAW MSG [$topic] keys=$keys preview=${preview.take(500)}")
    }

    /**
     * Get log file path for display
     */
    fun getLogFilePath(): String = logFile.absolutePath

    /**
     * Get log file size
     */
    fun getLogFileSize(): Long = if (logFile.exists()) logFile.length() else 0
}
