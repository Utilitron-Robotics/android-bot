package com.opendroids.tourbot.ui.connection

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.opendroids.tourbot.data.ConnectionStatus
import com.opendroids.tourbot.robot.Robot
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class ConnectionViewModel @Inject constructor(
    private val robot: Robot
) : ViewModel() {

    val connectionStatus: StateFlow<ConnectionStatus> = robot.connect("")
        .stateIn(viewModelScope, SharingStarted.Eagerly, ConnectionStatus.DISCONNECTED)

    fun connect(url: String) {
        viewModelScope.launch {
            robot.connect(url)
        }
    }

    fun disconnect() {
        robot.disconnect()
    }
}
