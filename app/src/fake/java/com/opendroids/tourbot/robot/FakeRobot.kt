package com.opendroids.tourbot.robot

import com.opendroids.tourbot.data.ConnectionStatus
import com.opendroids.tourbot.data.model.NavigationStatus
import com.opendroids.tourbot.data.model.SpeechStatus
import com.opendroids.tourbot.data.model.Waypoint
import com.opendroids.tourbot.data.remote.model.RobotStatusMessage
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import javax.inject.Inject

class FakeRobot @Inject constructor() : Robot {
    override fun connect(url: String): Flow<ConnectionStatus> = flow {
        emit(ConnectionStatus.CONNECTING)
        delay(1000)
        emit(ConnectionStatus.CONNECTED)
    }

    override fun disconnect() {
        // No-op
    }

    override fun getStatus(): Flow<RobotStatusMessage> = flow {
        while (true) {
            emit(
                RobotStatusMessage(
                    navStatus = 0, // Changed from "Idle" (String) to 0 (Int?)
                    battery = 0.8f,
                    velocity = listOf(0.0f, 0.0f, 0.0f), // Changed from 0.0f (Float) to List<Float>?
                    currentPoi = "start"
                )
            )
            delay(1000)
        }
    }

    override fun navigateTo(waypointId: String): Flow<NavigationStatus> = flow {
        emit(NavigationStatus.NAVIGATING)
        delay(3000)
        emit(NavigationStatus.SUCCEEDED)
    }

    override fun speak(text: String): Flow<SpeechStatus> = flow {
        emit(SpeechStatus.SPEAKING)
        delay(2000)
        emit(SpeechStatus.SUCCEEDED)
    }

    override fun pause() {
        // No-op
    }

    override fun resume() {
        // No-op
    }

    override fun getWaypoints(): Flow<List<Waypoint>> = flow {
        emit(
            listOf(
                Waypoint("start", "Start"),
                Waypoint("waypoint1", "Waypoint 1"),
                Waypoint("waypoint2", "Waypoint 2"),
                Waypoint("end", "End")
            )
        )
    }
}
