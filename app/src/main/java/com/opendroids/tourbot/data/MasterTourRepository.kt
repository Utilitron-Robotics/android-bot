package com.opendroids.tourbot.data

import android.util.Log
import com.opendroids.tourbot.data.remote.model.RobotStatusMessage
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.flatMapLatest
import javax.inject.Inject
import javax.inject.Singleton

private const val TAG = "MasterTourRepository"

enum class ConnectionStatus {
    DISCONNECTED,
    CONNECTING,
    CONNECTED,
    ERROR_NO_BASE // New status for when real connection fails
}

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

    private val _connectionStatus = MutableStateFlow(ConnectionStatus.DISCONNECTED)
    val connectionStatus: StateFlow<ConnectionStatus> = _connectionStatus.asStateFlow()

    private val _promptForTestMode = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    val promptForTestMode: SharedFlow<Unit> = _promptForTestMode.asSharedFlow()

    // Get the currently active repository based on test mode
    private val activeRepository: TourRepository
        get() = if (_isInTestMode.value) fakeRepository else realRepository

    override fun connect(url: String) {
        Log.d(TAG, "connect() called, testMode=${_isInTestMode.value}")
        // This method might need to be updated to reflect connection status as well.
        // For now, let's focus on tryConnect.
        activeRepository.connect(url)
    }

    override suspend fun tryConnect(url: String): Boolean {
        Log.d(TAG, "tryConnect() called, testMode=${_isInTestMode.value}")
        _connectionStatus.value = ConnectionStatus.CONNECTING
        if (_isInTestMode.value) {
            // If already in test mode, just try connecting with the fake repository
            val success = fakeRepository.tryConnect(url)
            _connectionStatus.value = if (success) ConnectionStatus.CONNECTED else ConnectionStatus.DISCONNECTED
            return success
        } else {
            // Try connecting to the real base
            val realConnectionSuccess = realRepository.tryConnect(url)
            if (realConnectionSuccess) {
                _connectionStatus.value = ConnectionStatus.CONNECTED
                return true
            } else {
                // Real connection failed, offer test mode
                _connectionStatus.value = ConnectionStatus.ERROR_NO_BASE
                _promptForTestMode.emit(Unit) // Signal UI to show prompt
                return false // Indicate that real connection failed
            }
        }
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
        // When test mode is explicitly set, update connection status if it was previously an error
        if (isTest && _connectionStatus.value == ConnectionStatus.ERROR_NO_BASE) {
            _connectionStatus.value = ConnectionStatus.CONNECTED // Assume test mode connection is always successful for now
        } else if (!isTest && _connectionStatus.value == ConnectionStatus.CONNECTED) {
            // If switching back to real mode, and was connected, assume disconnected until re-connect
            _connectionStatus.value = ConnectionStatus.DISCONNECTED
        }
    }

    override fun disconnect() {
        Log.d(TAG, "disconnect() called")
        activeRepository.disconnect()
        _connectionStatus.value = ConnectionStatus.DISCONNECTED
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
