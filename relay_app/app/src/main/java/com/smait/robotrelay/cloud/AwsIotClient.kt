package com.smait.robotrelay.cloud

import android.content.Context
import android.util.Log
import kotlinx.coroutines.*
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap
import javax.net.ssl.HttpsURLConnection

/**
 * AWS IoT / Fleet Management Client
 * Connects tablets to cloud for centralized robot fleet control
 *
 * Architecture:
 * - Each tablet registers as a "thing" in AWS IoT
 * - Publishes robot status to cloud topics
 * - Receives commands from cloud (navigate, stop, etc.)
 * - Supports both MQTT (IoT Core) and HTTPS (API Gateway) backends
 */
class AwsIotClient(
    private val context: Context,
    private val robotId: String,
) {
    companion object {
        private const val TAG = "AwsIotClient"

        // Topic patterns for MQTT
        const val TOPIC_STATUS = "robots/{id}/status"
        const val TOPIC_TELEMETRY = "robots/{id}/telemetry"
        const val TOPIC_COMMANDS = "robots/{id}/commands"
        const val TOPIC_FLEET_BROADCAST = "fleet/broadcast"

        // Default endpoints (configure in settings)
        const val DEFAULT_API_ENDPOINT = "https://api.frontiertower.io"
        const val DEFAULT_IOT_ENDPOINT = "wss://iot.frontiertower.io"
    }

    // Configuration
    private var apiEndpoint: String = DEFAULT_API_ENDPOINT
    private var iotEndpoint: String = DEFAULT_IOT_ENDPOINT
    private var apiKey: String? = null
    private var isEnabled: Boolean = false

    // State
    private var isConnected: Boolean = false
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var statusJob: Job? = null

    // Callbacks
    var onCommandReceived: ((FleetCommand) -> Unit)? = null
    var onConnectionChanged: ((Boolean) -> Unit)? = null

    // Last known robot state for reporting
    private var lastRobotStatus: RobotCloudStatus? = null

    /**
     * Configure cloud connection
     */
    fun configure(
        apiEndpoint: String = DEFAULT_API_ENDPOINT,
        iotEndpoint: String = DEFAULT_IOT_ENDPOINT,
        apiKey: String? = null,
    ) {
        this.apiEndpoint = apiEndpoint
        this.iotEndpoint = iotEndpoint
        this.apiKey = apiKey
    }

    /**
     * Enable cloud connectivity
     */
    fun enable() {
        if (isEnabled) return
        isEnabled = true

        scope.launch {
            register()
            startStatusReporting()
            startCommandPolling()
        }
    }

    /**
     * Disable cloud connectivity
     */
    fun disable() {
        isEnabled = false
        statusJob?.cancel()
        scope.launch {
            deregister()
        }
    }

    /**
     * Register this robot/tablet with the fleet
     */
    private suspend fun register() {
        try {
            val payload = JSONObject().apply {
                put("robot_id", robotId)
                put("tablet_model", android.os.Build.MODEL)
                put("android_version", android.os.Build.VERSION.SDK_INT)
                put("app_version", getAppVersion())
                put("capabilities", JSONObject().apply {
                    put("navigation", true)
                    put("velocity_control", true)
                    put("estop", true)
                    put("video_stream", false) // Future
                })
            }

            val response = httpPost("$apiEndpoint/fleet/register", payload)
            if (response != null) {
                isConnected = true
                onConnectionChanged?.invoke(true)
                Log.i(TAG, "Registered with fleet: $robotId")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Registration failed: ${e.message}")
            isConnected = false
            onConnectionChanged?.invoke(false)
        }
    }

    /**
     * Deregister from fleet
     */
    private suspend fun deregister() {
        try {
            val payload = JSONObject().apply {
                put("robot_id", robotId)
            }
            httpPost("$apiEndpoint/fleet/deregister", payload)
            isConnected = false
            onConnectionChanged?.invoke(false)
            Log.i(TAG, "Deregistered from fleet")
        } catch (e: Exception) {
            Log.e(TAG, "Deregistration failed: ${e.message}")
        }
    }

    /**
     * Update robot status in the cloud
     */
    fun updateStatus(status: RobotCloudStatus) {
        lastRobotStatus = status
    }

    /**
     * Start periodic status reporting
     */
    private fun startStatusReporting() {
        statusJob = scope.launch {
            while (isEnabled) {
                lastRobotStatus?.let { status ->
                    reportStatus(status)
                }
                delay(5000) // Report every 5 seconds
            }
        }
    }

    /**
     * Report current status to cloud
     */
    private suspend fun reportStatus(status: RobotCloudStatus) {
        try {
            val payload = JSONObject().apply {
                put("robot_id", robotId)
                put("timestamp", System.currentTimeMillis())
                put("battery", status.battery)
                put("position", JSONObject().apply {
                    put("x", status.x)
                    put("y", status.y)
                    put("theta", status.theta)
                })
                put("nav_status", status.navStatus)
                put("current_goal", status.currentGoal)
                put("estop", status.estop)
                put("online", status.robotConnected)
                put("building", status.building)
                put("floor", status.floor)
            }

            httpPost("$apiEndpoint/fleet/status", payload)
        } catch (e: Exception) {
            Log.w(TAG, "Status report failed: ${e.message}")
        }
    }

    /**
     * Start polling for commands (fallback when WebSocket unavailable)
     */
    private fun startCommandPolling() {
        scope.launch {
            while (isEnabled) {
                try {
                    val response = httpGet("$apiEndpoint/fleet/commands/$robotId")
                    response?.let { parseCommands(it) }
                } catch (e: Exception) {
                    Log.w(TAG, "Command poll failed: ${e.message}")
                }
                delay(2000) // Poll every 2 seconds
            }
        }
    }

    /**
     * Parse and dispatch commands from cloud
     */
    private fun parseCommands(response: JSONObject) {
        val commands = response.optJSONArray("commands") ?: return

        for (i in 0 until commands.length()) {
            val cmd = commands.getJSONObject(i)
            val command = FleetCommand(
                id = cmd.getString("id"),
                type = cmd.getString("type"),
                payload = cmd.optJSONObject("payload") ?: JSONObject(),
                timestamp = cmd.optLong("timestamp", System.currentTimeMillis())
            )

            onCommandReceived?.invoke(command)

            // Acknowledge command
            scope.launch {
                acknowledgeCommand(command.id)
            }
        }
    }

    /**
     * Acknowledge command receipt
     */
    private suspend fun acknowledgeCommand(commandId: String) {
        try {
            val payload = JSONObject().apply {
                put("robot_id", robotId)
                put("command_id", commandId)
                put("status", "received")
            }
            httpPost("$apiEndpoint/fleet/commands/ack", payload)
        } catch (e: Exception) {
            Log.w(TAG, "Command ack failed: ${e.message}")
        }
    }

    /**
     * Report command completion
     */
    fun reportCommandComplete(commandId: String, success: Boolean, message: String? = null) {
        scope.launch {
            try {
                val payload = JSONObject().apply {
                    put("robot_id", robotId)
                    put("command_id", commandId)
                    put("status", if (success) "completed" else "failed")
                    message?.let { put("message", it) }
                }
                httpPost("$apiEndpoint/fleet/commands/complete", payload)
            } catch (e: Exception) {
                Log.w(TAG, "Command complete report failed: ${e.message}")
            }
        }
    }

    /**
     * Send alert to fleet management
     */
    fun sendAlert(alertType: String, message: String, severity: AlertSeverity = AlertSeverity.INFO) {
        scope.launch {
            try {
                val payload = JSONObject().apply {
                    put("robot_id", robotId)
                    put("alert_type", alertType)
                    put("message", message)
                    put("severity", severity.name.lowercase())
                    put("timestamp", System.currentTimeMillis())
                }
                httpPost("$apiEndpoint/fleet/alerts", payload)
            } catch (e: Exception) {
                Log.w(TAG, "Alert send failed: ${e.message}")
            }
        }
    }

    // HTTP helpers

    private suspend fun httpPost(url: String, payload: JSONObject): JSONObject? {
        return withContext(Dispatchers.IO) {
            try {
                val conn = URL(url).openConnection() as HttpURLConnection
                conn.requestMethod = "POST"
                conn.setRequestProperty("Content-Type", "application/json")
                apiKey?.let { conn.setRequestProperty("X-API-Key", it) }
                conn.doOutput = true
                conn.connectTimeout = 10000
                conn.readTimeout = 10000

                OutputStreamWriter(conn.outputStream).use { writer ->
                    writer.write(payload.toString())
                }

                if (conn.responseCode == 200) {
                    BufferedReader(InputStreamReader(conn.inputStream)).use { reader ->
                        JSONObject(reader.readText())
                    }
                } else {
                    Log.w(TAG, "HTTP POST $url returned ${conn.responseCode}")
                    null
                }
            } catch (e: Exception) {
                Log.e(TAG, "HTTP POST failed: ${e.message}")
                null
            }
        }
    }

    private suspend fun httpGet(url: String): JSONObject? {
        return withContext(Dispatchers.IO) {
            try {
                val conn = URL(url).openConnection() as HttpURLConnection
                conn.requestMethod = "GET"
                apiKey?.let { conn.setRequestProperty("X-API-Key", it) }
                conn.connectTimeout = 10000
                conn.readTimeout = 10000

                if (conn.responseCode == 200) {
                    BufferedReader(InputStreamReader(conn.inputStream)).use { reader ->
                        JSONObject(reader.readText())
                    }
                } else {
                    null
                }
            } catch (e: Exception) {
                Log.e(TAG, "HTTP GET failed: ${e.message}")
                null
            }
        }
    }

    private fun getAppVersion(): String {
        return try {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: "1.0.0"
        } catch (e: Exception) {
            "1.0.0"
        }
    }

    fun destroy() {
        disable()
        scope.cancel()
    }
}

/**
 * Robot status for cloud reporting
 */
data class RobotCloudStatus(
    val battery: Int = 0,
    val x: Double = 0.0,
    val y: Double = 0.0,
    val theta: Double = 0.0,
    val navStatus: Int = 0,
    val currentGoal: String? = null,
    val estop: Boolean = false,
    val robotConnected: Boolean = false,
    val building: String? = null,
    val floor: String? = null,
)

/**
 * Command from fleet management
 */
data class FleetCommand(
    val id: String,
    val type: String,  // navigate, stop, estop, velocity, speak, etc.
    val payload: JSONObject,
    val timestamp: Long,
) {
    // Common command types
    companion object {
        const val TYPE_NAVIGATE = "navigate"
        const val TYPE_STOP = "stop"
        const val TYPE_ESTOP = "estop"
        const val TYPE_VELOCITY = "velocity"
        const val TYPE_SPEAK = "speak"
        const val TYPE_SET_SPEED_MODE = "set_speed_mode"
        const val TYPE_CANCEL_GOAL = "cancel_goal"
    }

    // Convenience getters
    val poi: String? get() = payload.optString("poi", null)
    val enabled: Boolean get() = payload.optBoolean("enabled", false)
    val linear: Double get() = payload.optDouble("linear", 0.0)
    val angular: Double get() = payload.optDouble("angular", 0.0)
    val text: String? get() = payload.optString("text", null)
    val speedMode: Int get() = payload.optInt("speed_mode", -1)
}

/**
 * Alert severity levels
 */
enum class AlertSeverity {
    INFO,
    WARNING,
    ERROR,
    CRITICAL
}
