package com.opendroids.tourbot.ui.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.opendroids.tourbot.data.TourConfigRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val tourConfigRepository: TourConfigRepository
) : ViewModel() {

    val preSpeakDelay: StateFlow<Int> = tourConfigRepository.preSpeakDelay
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = 0
        )

    fun setPreSpeakDelay(delayMs: Int) {
        viewModelScope.launch {
            tourConfigRepository.setPreSpeakDelay(delayMs)
        }
    }
}
