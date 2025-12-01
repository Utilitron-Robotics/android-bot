package com.opendroids.tourbot.ui.tour

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.opendroids.tourbot.data.ErrorLogger
import com.opendroids.tourbot.data.TourConfigRepository
import com.opendroids.tourbot.data.model.TourState
import com.opendroids.tourbot.logic.TourManager
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class TourViewModel @Inject constructor(
    private val tourManager: TourManager,
    private val tourConfigRepository: TourConfigRepository,
    private val errorLogger: ErrorLogger
) : ViewModel() {

    val tourState: StateFlow<TourState> = tourManager.tourState

    val waypointIds: StateFlow<List<String>> = tourConfigRepository.waypointIds.stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())
    val homeWaypointId: StateFlow<String> = tourConfigRepository.homeWaypointId.stateIn(viewModelScope, SharingStarted.Eagerly, "")

    val errors = errorLogger.errors

    fun startTour() {
        viewModelScope.launch {
            tourManager.startTour()
        }
    }

    fun abortTour() {
        tourManager.abortTour()
    }

    fun clearErrors() {
        errorLogger.clearErrors()
    }

    fun setHomeWaypoint(waypointId: String) {
        viewModelScope.launch {
            tourConfigRepository.setHomeWaypoint(waypointId)
        }
    }
}
