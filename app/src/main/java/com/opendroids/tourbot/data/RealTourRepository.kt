package com.opendroids.tourbot.data

import android.util.Log
import com.opendroids.tourbot.data.remote.RobotClient
import com.opendroids.tourbot.data.remote.model.RobotCommand
import com.opendroids.tourbot.data.remote.model.RobotStatusMessage
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.mapNotNull
import javax.inject.Inject
import javax.inject.Singleton

private const val TAG = "RealTourRepository"

@Singleton
class RealTourRepository @Inject constructor(
    private val robotClient: RobotClient
) : TourRepository {

    override fun connect(url: String) {
        robotClient.connect(url)
    }

    override suspend fun tryConnect(url: String): Boolean {
        return robotClient.tryConnect(url)
    }

    override fun disconnect() {
        robotClient.disconnect()
    }

    override fun observeStatus(): Flow<RobotStatusMessage> {
        return robotClient.messages
            .filter { it.topic == "/robot_status" && it.msg != null }
            .map { it.msg!! }
    }

    override fun getBatteryLevel(): Flow<Float> {
        return observeStatus()
            .mapNotNull { it.battery }
    }

    override suspend fun subscribeStatus() {
        Log.d(TAG, "Subscribing to robot status")
        val command = RobotCommand(
            op = "subscribe",
            id = "get_robot_status",
            topic = "/robot_status",
            type = "yutong_assistance/RobotStatus"
        )
        robotClient.sendCommand(command)
    }

    override suspend fun unsubscribeStatus() {
        Log.d(TAG, "Unsubscribing from robot status")
        val command = RobotCommand(
            op = "unsubscribe",
            id = "get_robot_status",
            topic = "/robot_status"
        )
        robotClient.sendCommand(command)
    }

    override fun goTo(poi: String) {
        val command = RobotCommand(
            op = "call_service",
            service = "/poi",
            id = "nav_$poi",
            args = mapOf("poi" to poi)
        )
        robotClient.sendCommand(command)
        Log.d(TAG, "Sent goTo command for: $poi")
    }

    override suspend fun cancelNavigation() {
        val advertise = RobotCommand(
            op = "advertise",
            topic = "/move_base/cancel",
            type = "actionlib_msgs/GoalID",
            id = "cancel_goal"
        )
        val publish = RobotCommand(
            op = "publish",
            topic = "/move_base/cancel",
            msg = emptyMap(), // Empty goal ID cancels all
            id = "cancel_goal"
        )
        val unadvertise = RobotCommand(
            op = "unadvertise",
            topic = "/move_base/cancel",
            id = "cancel_goal"
        )

        robotClient.sendCommand(advertise)
        delay(100)
        robotClient.sendCommand(publish)
        delay(100)
        robotClient.sendCommand(unadvertise)

        Log.d(TAG, "Sent cancel navigation sequence")
    }
}
