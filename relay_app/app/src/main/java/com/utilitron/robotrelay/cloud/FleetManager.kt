package com.utilitron.robotrelay.cloud

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import com.utilitron.robotrelay.service.ConnectionState
import com.utilitron.robotrelay.service.RobotStatusData
import com.utilitron.robotrelay.service.RobotWebSocketClient

/**
 * Fleet Manager - Bridges local robot control with cloud fleet management
 *
 * Responsibilities:
 * - Manages cloud connection lifecycle
 * - Forwards robot status to cloud
 * - Receives and dispatches cloud commands to robot
 * - Handles offline/online transitions gracefully
 */
class FleetManager(
    private val context: Context,
    private val robotClient: RobotWebSocketClient,
) {
    companion object {
        private const val TAG = "FleetManager"
        private const val PREFS_NAME = "fleet_config"
        private const val KEY_ENABLED = "cloud_enabled"
        private const val KEY_API_ENDPOINT = "api_endpoint"
        private const val KEY_API_KEY = "api_key"
        private const val KEY_ROBOT_ID = "robot_id"
    }

    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private var cloudClient: AwsIotClient? = null

    // Configuration
    var isEnabled: Boolean
        get() = prefs.getBoolean(KEY_ENABLED, false)
        set(value) = prefs.edit().putBoolean(KEY_ENABLED, value).apply()

    var apiEndpoint: String
        get() = prefs.getString(KEY_API_ENDPOINT, AwsIotClient.DEFAULT_API_ENDPOINT)!!
        set(value) = prefs.edit().putString(KEY_API_ENDPOINT, value).apply()

    var apiKey: String?
        get() = prefs.getString(KEY_API_KEY, null)
        set(value) = prefs.edit().putString(KEY_API_KEY, value).apply()

    var robotId: String
        get() = prefs.getString(KEY_ROBOT_ID, generateDefaultRobotId())!!
        set(value) = prefs.edit().putString(KEY_ROBOT_ID, value).apply()

    // Callbacks
    var onCloudStatusChanged: ((Boolean) -> Unit)? = null
    var onCommandExecuted: ((String, Boolean) -> Unit)? = null

    /**
     * Initialize fleet management
     */
    fun initialize() {
        if (isEnabled) {
            connect()
        }
    }

    /**
     * Connect to cloud fleet management
     */
    fun connect() {
        if (cloudClient != null) {
            Log.w(TAG, "Already connected to cloud")
            return
        }

        cloudClient = AwsIotClient(context, robotId).apply {
            configure(apiEndpoint, apiKey = apiKey)

            onConnectionChanged = { connected ->
                Log.i(TAG, "Cloud connection: $connected")
                onCloudStatusChanged?.invoke(connected)

                if (connected) {
                    sendAlert(
                        "startup",
                        "Robot $robotId connected to fleet",
                        AlertSeverity.INFO
                    )
                }
            }

            onCommandReceived = { command ->
                handleCloudCommand(command)
            }

            enable()
        }

        isEnabled = true
        Log.i(TAG, "Fleet manager started for robot: $robotId")
    }

    /**
     * Disconnect from cloud
     */
    fun disconnect() {
        cloudClient?.disable()
        cloudClient?.destroy()
        cloudClient = null
        isEnabled = false
        Log.i(TAG, "Fleet manager stopped")
    }

    /**
     * Update cloud with robot status
     */
    fun updateRobotStatus(status: RobotStatusData) {
        cloudClient?.updateStatus(
            RobotCloudStatus(
                battery = status.battery,
                x = status.x,
                y = status.y,
                theta = status.theta,
                navStatus = status.navStatus,
                currentGoal = status.currentGoalName,
                estop = status.softEstop || status.hardEstop,
                robotConnected = robotClient.connectionState.value == ConnectionState.CONNECTED,
                building = status.buildingName,
                floor = status.floorName,
            )
        )
    }

    /**
     * Handle command from cloud fleet management
     */
    private fun handleCloudCommand(command: FleetCommand) {
        Log.i(TAG, "Received cloud command: ${command.type} (${command.id})")

        val success = when (command.type) {
            FleetCommand.TYPE_NAVIGATE -> {
                command.poi?.let { poi ->
                    robotClient.navigateToPoi(poi)
                    true
                } ?: false
            }

            FleetCommand.TYPE_STOP -> {
                robotClient.stop()
                true
            }

            FleetCommand.TYPE_ESTOP -> {
                robotClient.setSoftStop(command.enabled)
                true
            }

            FleetCommand.TYPE_CANCEL_GOAL -> {
                robotClient.cancelNavigation()
                true
            }

            FleetCommand.TYPE_VELOCITY -> {
                robotClient.sendVelocity(command.linear, command.angular)
                true
            }

            FleetCommand.TYPE_SET_SPEED_MODE -> {
                robotClient.setSpeedMode(command.speedMode)
                true
            }

            FleetCommand.TYPE_SPEAK -> {
                // TODO: Implement TTS
                Log.i(TAG, "Speak command: ${command.text}")
                true
            }

            else -> {
                Log.w(TAG, "Unknown command type: ${command.type}")
                false
            }
        }

        cloudClient?.reportCommandComplete(
            command.id,
            success,
            if (!success) "Command execution failed" else null
        )

        onCommandExecuted?.invoke(command.type, success)
    }

    /**
     * Send alert to cloud
     */
    fun sendAlert(type: String, message: String, severity: AlertSeverity = AlertSeverity.INFO) {
        cloudClient?.sendAlert(type, message, severity)
    }

    /**
     * Generate default robot ID from device info
     */
    private fun generateDefaultRobotId(): String {
        val model = android.os.Build.MODEL.replace(" ", "_")
        val serial = android.os.Build.SERIAL.takeLast(6)
        return "robot_${model}_$serial"
    }

    fun destroy() {
        disconnect()
    }
}
