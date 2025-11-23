package com.opendroids.tourbot.data

import android.util.Log // Import Log
import com.opendroids.tourbot.data.remote.model.RobotStatusMessage
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

private const val TAG = "FakeTourRepository" // Define TAG

@Singleton
class FakeTourRepository @Inject constructor() : TourRepository {

    private val _robotStatus = MutableStateFlow(RobotStatusMessage(
        navStatus = 0, // Idle
        battery = 0.8f,
        velocity = listOf(0f, 0f, 0f),
        currentPoi = "start" // Initial POI
    ))

    override suspend fun tryConnect(url: String): Boolean {
        // The fake repository should always fail the "tryConnect" so the master can fall back to it.
        return false
    }

    override fun connect(url: String) {
        Log.d(TAG, "connect called with url: $url")
    }

    override fun disconnect() {
        Log.d(TAG, "disconnect called")
    }

    override suspend fun goTo(poi: String) {
        Log.d(TAG, "goTo called with poi: $poi")
        _robotStatus.update { it.copy(navStatus = 601, velocity = listOf(0.5f, 0f, 0f)) } // Simulate navigating
        Log.d(TAG, "Status updated to NAVIGATING (601) for $poi")
        delay(3000) // Simulate navigation time
        _robotStatus.update { it.copy(navStatus = 603, velocity = listOf(0f, 0f, 0f), currentPoi = poi) } // Simulate arrival
        Log.d(TAG, "Status updated to ARRIVED (603) for $poi")
    }

    override suspend fun cancelNavigation() {
        Log.d(TAG, "cancelNavigation called")
        _robotStatus.update { it.copy(navStatus = 0, velocity = listOf(0f, 0f, 0f)) } // Simulate cancelling navigation
        Log.d(TAG, "Status updated to IDLE (0) after cancellation")
    }

    override fun getBatteryLevel(): Flow<Float> {
        return _robotStatus.asStateFlow().map { it.battery ?: 0f }
    }

    override fun observeStatus(): Flow<RobotStatusMessage> {
        return _robotStatus.asStateFlow()
    }
}
