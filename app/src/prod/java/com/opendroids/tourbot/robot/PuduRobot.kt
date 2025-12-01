package com.opendroids.tourbot.robot

import android.util.Log
import com.opendroids.tourbot.data.ConnectionStatus
import com.opendroids.tourbot.data.model.NavigationStatus
import com.opendroids.tourbot.data.model.SpeechStatus
import com.opendroids.tourbot.data.model.Waypoint
import com.opendroids.tourbot.data.remote.RobotClient
import com.opendroids.tourbot.data.remote.model.RobotCommand
import com.opendroids.tourbot.data.remote.model.RobotStatusMessage
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject

private const val TAG = "PuduRobot"

class PuduRobot @Inject constructor(
    private val robotClient: RobotClient
) : Robot {
    override fun connect(url: String): Flow<ConnectionStatus> {
        robotClient.connect(url)
        return robotClient.connectionStatus
    }

    override fun disconnect() {
        robotClient.disconnect()
    }

    override fun getStatus(): Flow<RobotStatusMessage> {
        return robotClient.messages
            .filter { it.topic == "/robot_status" && it.msg != null }
            .map { it.msg!! }
    }

    override fun navigateTo(waypointId: String): Flow<NavigationStatus> = flow {
        val command = RobotCommand(
            op = "call_service",
            service = "/poi",
            id = "nav_$waypointId",
            args = mapOf("poi" to waypointId)
        )
        robotClient.sendCommand(command)
        Log.d(TAG, "Sent goTo command for: $waypointId")
        emit(NavigationStatus.NAVIGATING)
        // This is a simplified implementation. A real implementation would
        // listen for status updates to determine if the navigation has
        // succeeded or failed.
        delay(5000)
        emit(NavigationStatus.SUCCEEDED)
    }

    override fun speak(text: String): Flow<SpeechStatus> = flow {
        // Pudu robots do not have a text-to-speech API.
        // This is a no-op.
        emit(SpeechStatus.SUCCEEDED)
    }

    override fun pause() {
        // Pudu robots do not have a pause API.
        // This is a no-op.
    }

    override fun resume() {
        // Pudu robots do not have a resume API.
        // This is a no-op.
    }

    override fun getWaypoints(): Flow<List<Waypoint>> = flow {
        // This should be implemented by calling a service on the robot
        // that returns the list of waypoints.
        emit(emptyList<Waypoint>())
    }
}
