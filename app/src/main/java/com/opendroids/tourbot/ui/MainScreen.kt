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
                verticalArrangement = Arrangement.Center
            ) {
                Text(
                    text = when (val state = tourState) {
                        is TourState.Idle -> "Ready for Tour"
                        is TourState.Navigating -> "Navigating to ${state.targetWaypoint.id}..."
                        is TourState.Speaking -> "Speaking at ${state.currentWaypoint.id}"
                        is TourState.Completed -> "Tour Completed"
                        is TourState.Aborted -> "Tour Aborted"
                        is TourState.ReturningHome -> "Returning to ${state.homeWaypoint.id}..."
                        is TourState.Error -> "Error: ${state.message}"
                    },
                    color = Color.White,
                    style = MaterialTheme.typography.headlineSmall,
                    modifier = Modifier.padding(16.dp)
                )

                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                        .padding(32.dp)
                ) {
                    PointCloudFace(
                        amplitude = amplitude,
                        isSpeaking = tourState is TourState.Speaking
                    )
                }

                val captionText by audioPlayer.captionText.collectAsState()
                Text(
                    text = captionText,
                    color = Color.White,
                    style = MaterialTheme.typography.bodyLarge,
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 32.dp, vertical = 16.dp)
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
