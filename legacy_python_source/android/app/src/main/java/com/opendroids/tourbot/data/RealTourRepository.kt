package com.opendroids.tourbot.data

import com.opendroids.tourbot.data.remote.RobotClient
import com.opendroids.tourbot.data.remote.model.RobotCommand
import com.opendroids.tourbot.data.remote.model.RobotStatusMessage
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onCompletion
import kotlinx.coroutines.flow.onStart
import javax.inject.Inject

class RealTourRepository @Inject constructor(
    private val robotClient: RobotClient
) : TourRepository {

    override fun connect(url: String) {
        robotClient.connect(url)
    }

    override fun disconnect() {
        robotClient.disconnect()
    }

    override suspend fun goTo(poi: String) {
        val command = RobotCommand(
            op = "call_service",
            service = "/poi",
            id = "nav_$poi",
            args = mapOf("poi" to poi)
        )
        robotClient.sendCommand(command)
    }

    override suspend fun cancelNavigation() {
        // 1. Advertise
        robotClient.sendCommand(RobotCommand(
            op = "advertise",
            id = "cancel_goal",
            topic = "/move_base/cancel",
            type = "actionlib_msgs/GoalID"
        ))
        // 2. Publish
        robotClient.sendCommand(RobotCommand(
            op = "publish",
            topic = "/move_base/cancel",
            id = "cancel_goal",
            msg = mapOf("stamp" to "", "id" to "")
        ))
        // 3. Unadvertise
        robotClient.sendCommand(RobotCommand(
            op = "unadvertise",
            id = "cancel_goal",
            topic = "/move_base/cancel"
        ))
    }

    override fun getBatteryLevel(): Flow<Float> {
        val topic = "/mobile_base/sensors/core"
        val type = "kobuki_msgs/SensorState"
        val id = "get_sensors_core"

        return robotClient.messages
            .filter { it.topic == topic && it.msg?.battery != null }
            .map { it.msg!!.battery!! }
            .onStart {
                robotClient.sendCommand(RobotCommand("subscribe", id, topic, type))
            }
            .onCompletion {
                robotClient.sendCommand(RobotCommand("unsubscribe", id, topic))
            }
    }

    override fun observeStatus(): Flow<RobotStatusMessage> {
        val topic = "/robot_status"
        val type = "yutong_assistance/RobotStatus"
        val id = "get_robot_status"

        return robotClient.messages
            .filter { it.topic == topic && it.msg != null }
            .map { it.msg!! }
            .onStart {
                robotClient.sendCommand(RobotCommand("subscribe", id, topic, type))
            }
            .onCompletion {
                robotClient.sendCommand(RobotCommand("unsubscribe", id, topic))
            }
    }
}
