package com.opendroids.tourbot.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.opendroids.tourbot.data.ErrorLogger
import com.opendroids.tourbot.data.TourRepository
import com.opendroids.tourbot.data.remote.model.RobotStatusMessage
import com.opendroids.tourbot.data.settings.SettingsManager
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class MainViewModel @Inject constructor(
    private val settingsManager: SettingsManager,
    private val tourRepository: TourRepository,
    private val errorLogger: ErrorLogger
) : ViewModel() {

    val robotUrl: StateFlow<String> = settingsManager.robotUrl
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = ""
        )

    val robotStatus: StateFlow<RobotStatusMessage?> = tourRepository.observeStatus()
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = null
        )

    val errors = errorLogger.errors

    fun setRobotUrl(url: String) {
        viewModelScope.launch {
            settingsManager.setRobotUrl(url)
        }
    }

    fun connectToRobot(url: String) {
        tourRepository.connect(url)
    }

    fun disconnectFromRobot() {
        tourRepository.disconnect()
    }

    fun goToPoi(poi: String) {
        tourRepository.goTo(poi)
    }

    fun cancelNavigation() {
        viewModelScope.launch {
            tourRepository.cancelNavigation()
        }
    }

    fun logError(message: String, throwable: Throwable? = null) {
        errorLogger.logError(message, throwable)
    }

    fun clearErrors() {
        errorLogger.clearErrors()
    }
}
