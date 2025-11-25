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

    private var activeRepository: TourRepository = fakeRepository

    private val _isInTestMode = MutableStateFlow(true)
    val isInTestMode: StateFlow<Boolean> = _isInTestMode.asStateFlow()

    private val scope = CoroutineScope(Dispatchers.IO)

    override fun connect(url: String) {
        scope.launch {
            if (_isInTestMode.value) {
                Log.d(TAG, "In test mode, using FakeRepository")
                activeRepository = fakeRepository
                activeRepository.connect(url)
            } else {
                Log.d(TAG, "Attempting to connect with RealRepository...")
                val connectionSuccessful = realRepository.tryConnect(url)
                if (connectionSuccessful) {
                    Log.i(TAG, "✅ RealRepository connected. Switching to REAL mode.")
                    activeRepository = realRepository
                } else {
                    Log.w(TAG, "⚠️ RealRepository failed to connect. No fallback.")
                    // No change in active repository, user must manually switch to test mode
                }
                activeRepository.connect(url)
            }
        }
    }

    override suspend fun tryConnect(url: String): Boolean {
        return if (_isInTestMode.value) {
            fakeRepository.tryConnect(url)
        } else {
            realRepository.tryConnect(url)
        }
    }

    fun setTestMode(isTest: Boolean) {
        _isInTestMode.value = isTest
        activeRepository = if (isTest) {
            Log.i(TAG, "Switched to FAKE mode.")
            fakeRepository
        } else {
            Log.i(TAG, "Switched to REAL mode.")
            realRepository
        }
    }

    // Delegate all other TourRepository methods to the currently active repository
    override fun disconnect() = activeRepository.disconnect()
    override fun goTo(poi: String) = activeRepository.goTo(poi)
    override suspend fun cancelNavigation() = activeRepository.cancelNavigation()
    override fun getBatteryLevel(): Flow<Float> = activeRepository.getBatteryLevel()
    override fun observeStatus(): Flow<RobotStatusMessage> = activeRepository.observeStatus()
    override suspend fun unsubscribeStatus() = activeRepository.unsubscribeStatus()
}
