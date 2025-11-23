package com.opendroids.tourbot.data

import android.util.Log
import com.opendroids.tourbot.data.remote.model.RobotStatusMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

private const val TAG = "MasterTourRepository"

@Singleton
class MasterTourRepository @Inject constructor(
    private val realRepository: RealTourRepository,
    private val fakeRepository: FakeTourRepository
) : TourRepository {

    private lateinit var activeRepository: TourRepository

    private val _isInTestMode = MutableStateFlow(false)
    val isInTestMode: StateFlow<Boolean> = _isInTestMode.asStateFlow()

    private val scope = CoroutineScope(Dispatchers.IO)

    init {
        // Default to fake until a connection is attempted
        activeRepository = fakeRepository
        _isInTestMode.value = true
    }

    override fun connect(url: String) {
        scope.launch {
            Log.d(TAG, "Attempting to connect with RealRepository...")
            val connectionSuccessful = realRepository.tryConnect(url)
            if (connectionSuccessful) {
                Log.i(TAG, "✅ RealRepository connected. Switching to REAL mode.")
                activeRepository = realRepository
                _isInTestMode.value = false
            } else {
                Log.w(TAG, "⚠️ RealRepository failed to connect. Falling back to FAKE mode.")
                activeRepository = fakeRepository
                _isInTestMode.value = true
            }
            // Delegate the connect call to the now-active repository
            activeRepository.connect(url)
        }
    }

    // Delegate all other TourRepository methods to the currently active repository
    override fun disconnect() = activeRepository.disconnect()
    override suspend fun goTo(poi: String) = activeRepository.goTo(poi)
    override suspend fun cancelNavigation() = activeRepository.cancelNavigation()
    override fun getBatteryLevel(): Flow<Float> = activeRepository.getBatteryLevel()
    override fun observeStatus(): Flow<RobotStatusMessage> = activeRepository.observeStatus()
}
