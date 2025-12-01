package com.opendroids.tourbot.ui.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.opendroids.tourbot.data.settings.SettingsManager
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val settingsManager: SettingsManager
) : ViewModel() {

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

    val carouselAtTop: StateFlow<Boolean> = settingsManager.carouselAtTop
        .stateIn(
            scope = viewModelScope,
            started = SharingStarted.WhileSubscribed(5_000),
            initialValue = false
        )

    fun setRobotUrl(url: String) {
        viewModelScope.launch {
            settingsManager.setRobotUrl(url)
        }
    }

    fun onShowNerdDataChange(show: Boolean) {
        viewModelScope.launch {
            settingsManager.setShowNerdData(show)
        }
    }

    fun setCarouselAtTop(atTop: Boolean) {
        viewModelScope.launch {
            settingsManager.setCarouselAtTop(atTop)
        }
    }
}
