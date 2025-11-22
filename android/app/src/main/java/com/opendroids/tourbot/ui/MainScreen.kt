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
import com.opendroids.tourbot.data.TourConfigRepository
import com.opendroids.tourbot.data.model.TourState
import com.opendroids.tourbot.logic.TourManager
import com.opendroids.tourbot.ui.audio.AudioPlayer
import com.opendroids.tourbot.ui.components.RobotFace
import com.opendroids.tourbot.ui.settings.ControlPanel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen(
    tourManager: TourManager,
    audioPlayer: AudioPlayer,
    tourConfigRepository: TourConfigRepository, // Inject TourConfigRepository
    viewModel: MainViewModel = hiltViewModel()
) {
    val tourState by tourManager.tourState.collectAsState()
    val amplitude by audioPlayer.amplitude.collectAsState()
    val captionText by audioPlayer.captionText.collectAsState() // Collect caption text
    var showControlPanel by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("TourBot") },
                actions = {
                    IconButton(onClick = { showControlPanel = true }) {
                        Icon(Icons.Default.Settings, contentDescription = "Settings")
                    }
                }
            )
        }
    ) { padding ->
        Surface(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding),
            color = Color.Black
        ) {
            Column(
                modifier = Modifier.fillMaxSize(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                // Status Text
                Text(
                    text = when (val state = tourState) {
                        is TourState.Idle -> "Ready for Tour"
                        is TourState.Navigating -> "Navigating to ${state.targetWaypoint.id}..."
                        is TourState.Speaking -> "Speaking at ${state.currentWaypoint.id}"
                        is TourState.Completed -> "Tour Completed"
                        is TourState.Error -> "Error: ${state.message}"
                    },
                    color = Color.White,
                    style = MaterialTheme.typography.headlineSmall,
                    modifier = Modifier.padding(16.dp)
                )

                // Robot Face
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                        .padding(32.dp)
                ) {
                    RobotFace(amplitude = amplitude)
                }

                // Captions
                Text(
                    text = captionText, // Display real-time caption text
                    color = Color.White,
                    style = MaterialTheme.typography.bodyLarge,
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 32.dp, vertical = 16.dp)
                        .heightIn(min = 72.dp) // Reserve space for captions
                )

                // Controls
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
                    tourManager = tourManager,
                    tourConfigRepository = tourConfigRepository
                )
            }
        }
    }
}
