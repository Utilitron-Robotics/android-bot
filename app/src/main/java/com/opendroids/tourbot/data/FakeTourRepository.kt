package com.opendroids.tourbot.data

import android.util.Log
import com.opendroids.tourbot.data.remote.model.RobotStatusMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

private const val TAG = "FakeTourRepository"
private const val STATUS_EMIT_INTERVAL_MS = 100L
private const val SIMULATED_TRAVEL_TIME_MS = 2000L

@Singleton
class FakeTourRepository @Inject constructor() : TourRepository {

    private val coroutineScope = CoroutineScope(Dispatchers.IO)
    private var navigationJob: Job? = null
    private var statusEmitJob: Job? = null

    private val _robotStatus = MutableStateFlow(RobotStatusMessage(
        navStatus = 600, // Idle
        battery = 0.8f,
        velocity = listOf(0f, 0f, 0f),
        currentPoi = "start"
    ))

    // Use SharedFlow for status emissions to ensure collectors receive updates
    // regardless of when they start collecting (with replay=1 for latest state)
    private val _statusStream = MutableSharedFlow<RobotStatusMessage>(
        replay = 1,
        extraBufferCapacity = 10
    )

    init {
        // Emit initial state
        coroutineScope.launch {
            _statusStream.emit(_robotStatus.value)
        }
    }

    override suspend fun tryConnect(url: String): Boolean {
        Log.d(TAG, "tryConnect called with url: $url")
        return true
    }

    override fun connect(url: String) {
        Log.d(TAG, "connect called with url: $url")
    }

    override fun disconnect() {
        Log.d(TAG, "disconnect called")
        navigationJob?.cancel()
        statusEmitJob?.cancel()
    }

    override fun goTo(poi: String) {
        Log.d(TAG, "goTo called with poi: $poi")
        navigationJob?.cancel()
        statusEmitJob?.cancel()

        navigationJob = coroutineScope.launch {
            // 1. Update to navigating state
            val navigatingStatus = _robotStatus.value.copy(
                navStatus = 601,
                velocity = listOf(0.5f, 0f, 0f)
            )
            _robotStatus.value = navigatingStatus
            _statusStream.emit(navigatingStatus)
            Log.d(TAG, "Status updated to NAVIGATING (601) for $poi")

            // 2. Continuously emit status while navigating (simulates real robot streaming)
            statusEmitJob = launch {
                while (isActive) {
                    delay(STATUS_EMIT_INTERVAL_MS)
                    _statusStream.emit(_robotStatus.value)
                }
            }

            // 3. Simulate travel time
            delay(SIMULATED_TRAVEL_TIME_MS)

            // 4. Stop continuous emission and arrive
            statusEmitJob?.cancel()

            val arrivedStatus = _robotStatus.value.copy(
                navStatus = 603,
                velocity = listOf(0f, 0f, 0f),
                currentPoi = poi
            )
            _robotStatus.value = arrivedStatus
            _statusStream.emit(arrivedStatus)
            Log.d(TAG, "Status updated to ARRIVED (603) for $poi")

            // 5. Continue emitting arrived status briefly to ensure collector catches it
            repeat(5) {
                delay(STATUS_EMIT_INTERVAL_MS)
                _statusStream.emit(_robotStatus.value)
            }
        }
    }

    override suspend fun cancelNavigation() {
        navigationJob?.cancel()
        statusEmitJob?.cancel()
        val idleStatus = _robotStatus.value.copy(navStatus = 600, velocity = listOf(0f, 0f, 0f))
        _robotStatus.value = idleStatus
        _statusStream.emit(idleStatus)
        Log.d(TAG, "cancelNavigation: Status updated to IDLE (600)")
    }

    override fun getBatteryLevel(): Flow<Float> {
        return _statusStream.map { it.battery ?: 0f }
    }

    override fun observeStatus(): Flow<RobotStatusMessage> {
        // Return the SharedFlow which continuously emits during navigation
        return _statusStream.asSharedFlow()
    }

    override suspend fun subscribeStatus() {
        Log.d(TAG, "subscribeStatus called")
        // Emit current state when subscribing to ensure collector gets initial value
        _statusStream.emit(_robotStatus.value)
    }

    override suspend fun unsubscribeStatus() {
        Log.d(TAG, "unsubscribeStatus called")
        statusEmitJob?.cancel()
    }
}
