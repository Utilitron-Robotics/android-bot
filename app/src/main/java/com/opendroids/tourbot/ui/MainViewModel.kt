package com.opendroids.tourbot.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.opendroids.tourbot.data.ErrorLogger
import com.opendroids.tourbot.data.TourConfigRepository
import com.opendroids.tourbot.data.model.TourState
import com.opendroids.tourbot.robot.Robot
import com.opendroids.tourbot.data.remote.model.RobotStatusMessage
import com.opendroids.tourbot.data.settings.SettingsManager
import com.opendroids.tourbot.logic.TaskOrchestrator
import com.opendroids.tourbot.logic.TourManager
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class MainViewModel @Inject constructor(
    private val settingsManager: SettingsManager,
    private val tourManager: TourManager,
    private val taskOrchestrator: TaskOrchestrator,
    private val tourConfigRepository: TourConfigRepository,
    private val robot: Robot, // Injected Robot interface directly
    val errorLogger: ErrorLogger
) : ViewModel() {

    val tourState: StateFlow<TourState> = taskOrchestrator.tourState
    val waypointIds: StateFlow<List<String>> = tourConfigRepository.waypointIds.stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())
    val robotStatus: StateFlow<RobotStatusMessage?> = robot.getStatus().stateIn(viewModelScope, SharingStarted.Eagerly, null) // Using Robot directly
    val homeWaypointId: StateFlow<String> = tourConfigRepository.homeWaypointId.stateIn(viewModelScope, SharingStarted.Eagerly, "")

    // Removed _showTestModeDialog and related logic as it's handled by build flavors now

    val robotUrl: StateFlow<String> = settingsManager.robotUrl
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = ""
        )

    val showNerdData: StateFlow<Boolean> = settingsManager.showNerdData
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = false
        )

    val errors = errorLogger.errors

    fun setRobotUrl(url: String) {
        viewModelScope.launch {
            settingsManager.setRobotUrl(url)
        }
    }

    fun setHomeWaypoint(waypointId: String) {
        viewModelScope.launch {
            tourConfigRepository.setHomeWaypoint(waypointId)
        }
    }

    fun onShowNerdDataChange(show: Boolean) {
        viewModelScope.launch {
            settingsManager.setShowNerdData(show)
        }
    }

    fun startTour() {
        viewModelScope.launch {
            tourManager.startTour()
        }
    }

    fun abortTour() {
        tourManager.abortTour()
    }

    fun logError(message: String, throwable: Throwable? = null) {
        errorLogger.logError(message, throwable)
    }

    fun clearErrors() {
        errorLogger.clearErrors()
    }

    // Removed connect and setTestMode functions as they are now in ConnectionViewModel
}
