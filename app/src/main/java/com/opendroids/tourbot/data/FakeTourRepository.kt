package com.opendroids.tourbot.data

import android.util.Log
import com.opendroids.tourbot.data.remote.model.RobotStatusMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

private const val TAG = "FakeTourRepository"

@Singleton
class FakeTourRepository @Inject constructor() : TourRepository {

    private val coroutineScope = CoroutineScope(Dispatchers.IO)
    private var navigationJob: Job? = null

    private val _robotStatus = MutableStateFlow(RobotStatusMessage(
        navStatus = 600, // Idle
        battery = 0.8f,
        velocity = listOf(0f, 0f, 0f),
        currentPoi = "start"
    ))

    override suspend fun tryConnect(url: String): Boolean {
        return true
    }

    override fun connect(url: String) {
        Log.d(TAG, "connect called with url: $url")
    }

    override fun disconnect() {
        Log.d(TAG, "disconnect called")
        navigationJob?.cancel()
    }

    override fun goTo(poi: String) {
        Log.d(TAG, "goTo called with poi: $poi")
        navigationJob?.cancel() // Cancel any ongoing navigation
        navigationJob = coroutineScope.launch {
            // 1. Start navigating
            _robotStatus.update { it.copy(navStatus = 601, velocity = listOf(0.5f, 0f, 0f)) }
            Log.d(TAG, "Status updated to NAVIGATING (601) for $poi")

            // 2. Simulate travel time
            delay(2000) // Wait for 2 seconds

            // 3. Arrive at destination
            _robotStatus.update { it.copy(navStatus = 603, velocity = listOf(0f, 0f, 0f), currentPoi = poi) }
            Log.d(TAG, "Status updated to ARRIVED (603) for $poi")
        }
    }

    override suspend fun cancelNavigation() {
        navigationJob?.cancel()
        _robotStatus.update { it.copy(navStatus = 600, velocity = listOf(0f, 0f, 0f)) }
        Log.d(TAG, "cancelNavigation: Status updated to IDLE (600)")
    }

    override fun getBatteryLevel(): Flow<Float> {
        return _robotStatus.asStateFlow().map { it.battery ?: 0f }
    }

    override fun observeStatus(): Flow<RobotStatusMessage> {
        return _robotStatus.asStateFlow()
    }

    override suspend fun subscribeStatus() {
        Log.d(TAG, "subscribeStatus called")
    }

    override suspend fun unsubscribeStatus() {
        Log.d(TAG, "unsubscribeStatus called")
    }
}
