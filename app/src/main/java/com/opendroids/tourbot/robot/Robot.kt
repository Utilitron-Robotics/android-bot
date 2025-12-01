package com.opendroids.tourbot.robot

import com.opendroids.tourbot.data.ConnectionStatus
import com.opendroids.tourbot.data.model.NavigationStatus
import com.opendroids.tourbot.data.model.SpeechStatus
import com.opendroids.tourbot.data.model.Waypoint
import com.opendroids.tourbot.data.remote.model.RobotStatusMessage
import kotlinx.coroutines.flow.Flow

interface Robot {
    fun connect(url: String): Flow<ConnectionStatus>
    fun disconnect()
    fun getStatus(): Flow<RobotStatusMessage>
    fun navigateTo(waypointId: String): Flow<NavigationStatus>
    fun speak(text: String): Flow<SpeechStatus>
    fun pause()
    fun resume()
    fun getWaypoints(): Flow<List<Waypoint>>
}
