package com.opendroids.tourbot.ui.tour

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.opendroids.tourbot.data.model.TourState
import com.opendroids.tourbot.logic.TourManager
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class TourViewModel @Inject constructor(
    private val tourManager: TourManager
) : ViewModel() {

    val tourState: StateFlow<TourState> = tourManager.tourState

    fun startTour() {
        viewModelScope.launch {
            tourManager.startTour()
        }
    }

    fun abortTour() {
        tourManager.abortTour()
    }
}
