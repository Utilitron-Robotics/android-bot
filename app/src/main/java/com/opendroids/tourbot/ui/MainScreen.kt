package com.opendroids.tourbot.ui

import android.Manifest
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.google.accompanist.permissions.ExperimentalPermissionsApi
import com.opendroids.tourbot.data.ConnectionStatus
import com.opendroids.tourbot.data.model.TourState
import com.opendroids.tourbot.data.remote.model.RobotStatusMessage
import com.opendroids.tourbot.robot.Robot
import com.opendroids.tourbot.ui.audio.AudioPlayer
import com.opendroids.tourbot.ui.components.WaypointCarousel
import com.opendroids.tourbot.ui.components.pointcloud.PointCloudFace
import com.opendroids.tourbot.ui.connection.ConnectionViewModel
import com.opendroids.tourbot.ui.settings.ControlPanel
import com.opendroids.tourbot.ui.settings.SettingsViewModel
import com.opendroids.tourbot.ui.tour.TourViewModel

@OptIn(ExperimentalMaterial3Api::class, ExperimentalPermissionsApi::class)
@Composable
fun MainScreen(
    audioPlayer: AudioPlayer,
    robot: Robot,
    tourViewModel: TourViewModel = hiltViewModel(),
    settingsViewModel: SettingsViewModel = hiltViewModel(),
    connectionViewModel: ConnectionViewModel = hiltViewModel()
) {
    val tourState by tourViewModel.tourState.collectAsState()
    val amplitude by audioPlayer.amplitude.collectAsState()
    val waypointIds by tourViewModel.waypointIds.collectAsState()
    val connectionStatus by connectionViewModel.connectionStatus.collectAsState()

    val currentWaypointId = when (val state = tourState) {
        is TourState.Navigating -> state.targetWaypoint.id
        is TourState.Speaking -> state.currentWaypoint.id
        is TourState.ReturningHome -> state.homeWaypoint.id
        else -> waypointIds.firstOrNull() ?: ""
    }

    var showControlPanel by remember { mutableStateOf(false) }
    val showNerdData by settingsViewModel.showNerdData.collectAsState()
    val robotStatus by robot.getStatus().collectAsState(initial = null)
    val robotUrl by settingsViewModel.robotUrl.collectAsState()

    LaunchedEffect(Unit) {
        connectionViewModel.connect(robotUrl)
    }

    Box(modifier = Modifier.fillMaxSize()) {
        Surface(
            modifier = Modifier.fillMaxSize(),
            color = Color.Black
        ) {
            Column(
                modifier = Modifier.fillMaxSize(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.SpaceBetween
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(
                        text = when (val state = tourState) {
                            is TourState.Idle -> "Ready for Tour"
                            is TourState.Navigating -> "Navigating..."
                            is TourState.Speaking -> "Speaking at..."
                            is TourState.Completed -> "Tour Completed"
                            is TourState.Aborted -> "Tour Aborted"
                            is TourState.ReturningHome -> "Returning to Start..."
                            is TourState.Error -> "Error: ${state.message}"
                        },
                        color = Color.White,
                        style = MaterialTheme.typography.titleLarge,
                        modifier = Modifier.padding(top = 32.dp)
                    )

                    ConnectionStatusIndicator(connectionStatus = connectionStatus)

                    WaypointCarousel(
                        waypointIds = waypointIds,
                        currentWaypointId = currentWaypointId,
                        modifier = Modifier.height(80.dp)
                    )
                }

                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    val captionText by audioPlayer.captionText.collectAsState()
                    Text(
                        text = captionText,
                        color = Color.White,
                        style = MaterialTheme.typography.bodyLarge,
                        textAlign = TextAlign.Center,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 32.dp)
                            .heightIn(min = 72.dp)
                    )

                    if (tourState is TourState.Idle || tourState is TourState.Completed || tourState is TourState.Error) {
                        Button(
                            onClick = { tourViewModel.startTour() },
                            modifier = Modifier.padding(bottom = 48.dp)
                        ) {
                            Text("Start Tour")
                        }
                    } else {
                        Button(
                            onClick = { tourViewModel.abortTour() },
                            colors = ButtonDefaults.buttonColors(containerColor = Color.Red),
                            modifier = Modifier.padding(bottom = 48.dp)
                        ) {
                            Text("Abort Tour")
                        }
                    }
                }
            }

            if (showControlPanel) {
                ControlPanel(
                    onDismiss = { showControlPanel = false }
                )
            }
        }

        Box(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(top = 8.dp, end = 8.dp)
                .size(100.dp)
        ) {
            PointCloudFace(
                amplitude = amplitude,
                isSpeaking = tourState is TourState.Speaking
            )
        }

        if (showNerdData) {
            NerdStatsOverlay(
                robotStatus = robotStatus,
                tourState = tourState,
                robotUrl = robotUrl,
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(8.dp)
            )
        }

        IconButton(
            onClick = { showControlPanel = true },
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(bottom = 8.dp, end = 8.dp)
        ) {
            Icon(
                imageVector = Icons.Default.Settings,
                contentDescription = "Settings",
                tint = Color.White
            )
        }
    }
}

@Composable
fun ConnectionStatusIndicator(connectionStatus: ConnectionStatus) {
    val color = when (connectionStatus) {
        ConnectionStatus.CONNECTED -> Color.Green
        ConnectionStatus.CONNECTING -> Color.Yellow
        ConnectionStatus.DISCONNECTED -> Color.Red
        ConnectionStatus.ERROR_NO_BASE -> Color.Red
    }
    val text = when (connectionStatus) {
        ConnectionStatus.CONNECTED -> "Connected"
        ConnectionStatus.CONNECTING -> "Connecting..."
        ConnectionStatus.DISCONNECTED -> "Disconnected"
        ConnectionStatus.ERROR_NO_BASE -> "Error: No Base"
    }

    Row(
        modifier = Modifier
            .padding(8.dp)
            .background(Color.DarkGray.copy(alpha = 0.5f), MaterialTheme.shapes.small)
            .padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(10.dp)
                .background(color, MaterialTheme.shapes.small)
        )
        Spacer(modifier = Modifier.width(8.dp))
        Text(
            text = text,
            color = Color.White,
            style = MaterialTheme.typography.labelSmall
        )
    }
}

@Composable
private fun NerdStatsOverlay(
    robotStatus: RobotStatusMessage?,
    tourState: TourState,
    robotUrl: String,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(containerColor = Color.Black.copy(alpha = 0.6f)),
    ) {
        Column(modifier = Modifier.padding(8.dp)) {
            Text("NERD STATS", style = MaterialTheme.typography.titleMedium, color = Color.White)
            Spacer(modifier = Modifier.height(4.dp))
            
            Text("Tour State: ${tourState::class.java.simpleName}", color = Color.White)
            Text("Robot URL: $robotUrl", color = Color.White)
            
            Divider(modifier = Modifier.padding(vertical = 4.dp))

            if (robotStatus == null) {
                Text("No status received yet.", color = Color.White)
            } else {
                Text("Nav Status: ${robotStatus.navStatus}", color = Color.White)
                Text("Battery: ${robotStatus.battery}", color = Color.White)
                Text("Velocity: ${robotStatus.velocity}", color = Color.White)
                Text("Current POI: ${robotStatus.currentPoi}", color = Color.White)
            }
        }
    }
}
