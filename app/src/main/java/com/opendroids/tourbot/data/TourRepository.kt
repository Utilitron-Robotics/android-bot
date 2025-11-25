package com.opendroids.tourbot.data

import com.opendroids.tourbot.data.remote.model.RobotStatusMessage
import kotlinx.coroutines.flow.Flow

interface TourRepository {
    fun connect(url: String)
    fun disconnect()

    // High-level commands
    fun goTo(poi: String)
    suspend fun cancelNavigation()
    fun getBatteryLevel(): Flow<Float>

    // Low-level status observation
    fun observeStatus(): Flow<RobotStatusMessage>
    suspend fun subscribeStatus()
    suspend fun unsubscribeStatus()
    
    // Function to attempt connection and report success/failure
    suspend fun tryConnect(url: String): Boolean
}
