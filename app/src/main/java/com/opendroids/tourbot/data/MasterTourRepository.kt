package com.opendroids.tourbot.data

import android.util.Log
import com.opendroids.tourbot.data.remote.model.RobotStatusMessage
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.flatMapLatest
import javax.inject.Inject
import javax.inject.Singleton

private const val TAG = "MasterTourRepository"

/**
 * Master repository that delegates to either FakeTourRepository (test mode)
 * or RealTourRepository (production mode).
 *
 * IMPORTANT: Test mode should NOT be changed during an active tour.
 * The switch only takes full effect when a new tour is started.
 */
@OptIn(ExperimentalCoroutinesApi::class)
@Singleton
class MasterTourRepository @Inject constructor(
    private val realRepository: RealTourRepository,
    private val fakeRepository: FakeTourRepository
) : TourRepository {

    private val _isInTestMode = MutableStateFlow(false)
    val isInTestMode: StateFlow<Boolean> = _isInTestMode.asStateFlow()

    // Get the currently active repository based on test mode
    private val activeRepository: TourRepository
        get() = if (_isInTestMode.value) fakeRepository else realRepository

    override fun connect(url: String) {
        Log.d(TAG, "connect() called, testMode=${_isInTestMode.value}")
        activeRepository.connect(url)
    }

    override suspend fun tryConnect(url: String): Boolean {
        Log.d(TAG, "tryConnect() called, testMode=${_isInTestMode.value}")
        return activeRepository.tryConnect(url)
    }

    /**
     * Switch between test and real mode.
     * WARNING: Should not be called during an active tour - changes take effect on next tour start.
     */
    fun setTestMode(isTest: Boolean) {
        if (_isInTestMode.value == isTest) {
            Log.d(TAG, "Test mode already set to $isTest, no change needed")
            return
        }

        Log.i(TAG, "Switching to ${if (isTest) "FAKE" else "REAL"} mode")
        _isInTestMode.value = isTest
    }

    override fun disconnect() {
        Log.d(TAG, "disconnect() called")
        activeRepository.disconnect()
    }

    override fun goTo(poi: String) {
        Log.d(TAG, "goTo($poi) called, testMode=${_isInTestMode.value}")
        activeRepository.goTo(poi)
    }

    override suspend fun cancelNavigation() {
        Log.d(TAG, "cancelNavigation() called")
        activeRepository.cancelNavigation()
    }

    /**
     * Returns a Flow that automatically switches to the appropriate repository's
     * battery flow when test mode changes.
     */
    override fun getBatteryLevel(): Flow<Float> {
        return _isInTestMode.flatMapLatest { isTest ->
            if (isTest) {
                fakeRepository.getBatteryLevel()
            } else {
                realRepository.getBatteryLevel()
            }
        }
    }

    /**
     * Returns a Flow that automatically switches to the appropriate repository's
     * status flow when test mode changes.
     */
    override fun observeStatus(): Flow<RobotStatusMessage> {
        return _isInTestMode.flatMapLatest { isTest ->
            if (isTest) {
                fakeRepository.observeStatus()
            } else {
                realRepository.observeStatus()
            }
        }
    }

    override suspend fun subscribeStatus() {
        Log.d(TAG, "subscribeStatus() called")
        activeRepository.subscribeStatus()
    }

    override suspend fun unsubscribeStatus() {
        Log.d(TAG, "unsubscribeStatus() called")
        activeRepository.unsubscribeStatus()
    }
}
