package com.opendroids.tourbot.data

import android.util.Log
import com.opendroids.tourbot.data.remote.RobotClient
import com.opendroids.tourbot.data.remote.model.RobotCommand
import com.opendroids.tourbot.data.remote.model.RobotStatusMessage
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
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

    override suspend fun goTo(poi: String) {
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

    override fun getBatteryLevel(): Flow<Float> {
        // This requires a more complex implementation to request and listen for battery status
        // For now, returning a flow from the main status message
        return observeStatus().map { it.battery ?: 0f }
    }

    override fun observeStatus(): Flow<RobotStatusMessage> {
        // Subscribe to the status topic if not already
        val subscribeCommand = RobotCommand(op = "subscribe", topic = "/robot_status", type = "yutong_assistance/RobotStatus", id = "get_robot_status")
        robotClient.sendCommand(subscribeCommand)
        
        return robotClient.messages.map { it.msg ?: RobotStatusMessage() }
    }
}
