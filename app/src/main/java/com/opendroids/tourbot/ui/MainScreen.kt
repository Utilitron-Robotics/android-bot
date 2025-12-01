package com.opendroids.tourbot.ui

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
import com.opendroids.tourbot.data.MasterTourRepository
import com.opendroids.tourbot.data.TourConfigRepository
import com.opendroids.tourbot.data.model.TourState
import com.opendroids.tourbot.data.remote.model.RobotStatusMessage
import com.opendroids.tourbot.logic.TourManager
import com.opendroids.tourbot.ui.audio.AudioPlayer
import com.opendroids.tourbot.ui.components.WaypointCarousel
import com.opendroids.tourbot.ui.components.pointcloud.PointCloudFace
import com.opendroids.tourbot.ui.settings.ControlPanel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen(
    tourManager: TourManager,
    audioPlayer: AudioPlayer,
    tourConfigRepository: TourConfigRepository,
    masterTourRepository: MasterTourRepository,
    viewModel: MainViewModel = hiltViewModel()
) {
    val tourState by tourManager.tourState.collectAsState()
    val amplitude by audioPlayer.amplitude.collectAsState()
    val waypointIds by tourManager.waypointIds.collectAsState()
    
    val currentWaypointId = when (val state = tourState) {
        is TourState.Navigating -> state.targetWaypoint.id
        is TourState.Speaking -> state.currentWaypoint.id
        is TourState.ReturningHome -> state.homeWaypoint.id
        else -> waypointIds.firstOrNull() ?: ""
    }

    var showControlPanel by remember { mutableStateOf(false) }
    val showNerdData by viewModel.showNerdData.collectAsState()
    val robotStatus by viewModel.robotStatus.collectAsState()
    val isInTestMode by masterTourRepository.isInTestMode.collectAsState()
    val robotUrl by viewModel.robotUrl.collectAsState()

    Box(modifier = Modifier.fillMaxSize()) {
        Surface(
            modifier = Modifier.fillMaxSize(),
            color = Color.Black
        ) {
            Column(
                modifier = Modifier.fillMaxSize(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.SpaceBetween // Changed for new layout
            ) {
                // --- Top Section ---
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

                    WaypointCarousel(
                        waypointIds = waypointIds,
                        currentWaypointId = currentWaypointId,
                        modifier = Modifier.height(80.dp)
                    )
                }

                // --- Center Section (Future Media Box) ---
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                        .padding(horizontal = 32.dp, vertical = 16.dp),
                    contentAlignment = Alignment.Center
                ) {
                    // This is where the image/video/website will go.
                    // For now, the point cloud is here.
                    PointCloudFace(
                        amplitude = amplitude,
                        isSpeaking = tourState is TourState.Speaking
                    )
                }

                // --- Bottom Section ---
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
                            onClick = { tourManager.startTour() },
                            modifier = Modifier.padding(bottom = 48.dp)
                        ) {
                            Text("Start Tour")
                        }
                    } else {
                        Button(
                            onClick = { tourManager.abort() },
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
                    onDismiss = { showControlPanel = false },
                    tourConfigRepository = tourConfigRepository,
                    masterTourRepository = masterTourRepository,
                    mainViewModel = viewModel
                )
            }
        }

        if (showNerdData) {
            NerdStatsOverlay(
                robotStatus = robotStatus,
                tourState = tourState,
                isInTestMode = isInTestMode,
                robotUrl = robotUrl,
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(8.dp)
            )
        }

        IconButton(
            onClick = { showControlPanel = true },
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(top = 8.dp, end = 8.dp)
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
private fun NerdStatsOverlay(
    robotStatus: RobotStatusMessage?,
    tourState: TourState,
    isInTestMode: Boolean,
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
            
            Text("Mode: ${if (isInTestMode) "TEST" else "PRODUCTION"}", color = if (isInTestMode) Color.Yellow else Color.Green)
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
