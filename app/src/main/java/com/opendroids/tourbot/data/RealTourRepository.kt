package com.opendroids.tourbot.data

import android.util.Log
import com.opendroids.tourbot.data.remote.RobotClient
import com.opendroids.tourbot.data.remote.model.RobotCommand
import com.opendroids.tourbot.data.remote.model.RobotStatusMessage
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.collect
import javax.inject.Inject
import javax.inject.Singleton

private const val TAG = "RealTourRepository"

@Singleton
class RealTourRepository @Inject constructor(
    private val robotClient: RobotClient
) : TourRepository {

    override suspend fun tryConnect(url: String): Boolean {
        Log.d(TAG, "Trying to connect to $url")
        return robotClient.tryConnect(url)
    }

    override fun connect(url: String) {
        // This can now be a simple delegation if tryConnect is called first
        if (!robotClient.isConnected.value) {
            robotClient.connect(url)
        }
    }

    override fun disconnect() {
        robotClient.disconnect()
    }

    override fun goTo(poi: String) {
        val command = RobotCommand(
            op = "call_service",
            service = "/poi",
            id = "nav_${poi}",
            args = mapOf("poi" to poi)
        )
        robotClient.sendCommand(command)
    }

    override suspend fun cancelNavigation() {
        val advertiseCommand = RobotCommand(op = "advertise", id = "cancel_goal", topic = "/move_base/cancel", type = "actionlib_msgs/GoalID")
        robotClient.sendCommand(advertiseCommand)
        // In a real implementation, you might wait for confirmation before sending the next command
        val publishCommand = RobotCommand(op = "publish", topic = "/move_base/cancel", id = "cancel_goal", msg = mapOf("stamp" to "", "id" to ""))
        robotClient.sendCommand(publishCommand)
        val unadvertiseCommand = RobotCommand(op = "unadvertise", id = "cancel_goal", topic = "/move_base/cancel")
        robotClient.sendCommand(unadvertiseCommand)
    }

    override fun getBatteryLevel(): Flow<Float> = flow {
        // Subscribe to sensor core topic matching Python implementation
        val subscribeCommand = RobotCommand(
            op = "subscribe",
            topic = "/mobile_base/sensors/core",
            type = "kobuki_msgs/SensorState",
            id = "get_sensors_core"
        )
        robotClient.sendCommand(subscribeCommand)
        Log.d(TAG, "Subscribed to /mobile_base/sensors/core for battery reading")

        try {
            // Listen for battery messages
            robotClient.messages
                .filter { it.topic == "/mobile_base/sensors/core" }
                .mapNotNull { it.msg?.battery }
                .take(1)
                .collect { battery ->
                    Log.i(TAG, "🔋 Battery level: $battery%")
                    emit(battery)
                }
        } finally {
            // Unsubscribe after getting value or if flow is cancelled
            val unsubscribeCommand = RobotCommand(
                op = "unsubscribe",
                topic = "/mobile_base/sensors/core",
                id = "get_sensors_core"
            )
            robotClient.sendCommand(unsubscribeCommand)
            Log.d(TAG, "Unsubscribed from /mobile_base/sensors/core")
        }
    }

    override fun observeStatus(): Flow<RobotStatusMessage> {
        // Subscribe to the status topic if not already
        val subscribeCommand = RobotCommand(op = "subscribe", topic = "/robot_status", type = "yutong_assistance/RobotStatus", id = "get_robot_status")
        robotClient.sendCommand(subscribeCommand)
        
        return robotClient.messages.map { it.msg ?: RobotStatusMessage() }
    }

    override suspend fun unsubscribeStatus() {
        val unsubscribeCommand = RobotCommand(
            op = "unsubscribe",
            topic = "/robot_status",
            id = "get_robot_status"
        )
        robotClient.sendCommand(unsubscribeCommand)
        Log.i(TAG, "Unsubscribed from robot status updates")
    }
}
