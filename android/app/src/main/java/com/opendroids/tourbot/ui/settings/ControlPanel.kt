package com.opendroids.tourbot.ui.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.opendroids.tourbot.data.TourConfigRepository
import com.opendroids.tourbot.logic.TourManager
import com.opendroids.tourbot.ui.MainViewModel
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ControlPanel(
    onDismiss: () -> Unit,
    tourManager: TourManager,
    tourConfigRepository: TourConfigRepository,
    mainViewModel: MainViewModel, // Pass MainViewModel
    settingsViewModel: SettingsViewModel = hiltViewModel()
) {
    val preSpeakDelay by settingsViewModel.preSpeakDelay.collectAsState()
    val robotUrl by mainViewModel.robotUrl.collectAsState() // Get robotUrl from MainViewModel
    var showScriptEditor by remember { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Control Panel") },
        text = {
            Column(modifier = Modifier.fillMaxWidth()) {
                // Robot URL Editor
                Text("Base Control", style = MaterialTheme.typography.titleMedium)
                OutlinedTextField(
                    value = robotUrl,
                    onValueChange = { mainViewModel.setRobotUrl(it) },
                    label = { Text("Robot WebSocket URL") },
                    modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp)
                )

                Divider(modifier = Modifier.padding(vertical = 16.dp))

                // Pre-speak delay editor
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.padding(vertical = 8.dp)
                ) {
                    Text("Pre-speak delay (ms):", modifier = Modifier.weight(1f))
                    OutlinedTextField(
                        value = preSpeakDelay.toString(),
                        onValueChange = { settingsViewModel.setPreSpeakDelay(it.toIntOrNull() ?: 0) },
                        modifier = Modifier.width(100.dp)
                    )
                }

                Divider(modifier = Modifier.padding(vertical = 16.dp))

                // Waypoint script list
                Text("Waypoint Scripts", style = MaterialTheme.typography.titleMedium)
                LazyColumn(modifier = Modifier.height(300.dp)) {
                    items(tourManager.waypointIds) { waypointId ->
                        ListItem(
                            headlineContent = { Text(waypointId) },
                            modifier = Modifier.clickable { showScriptEditor = waypointId }
                        )
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text("Close")
            }
        }
    )

    // Script Editor Dialog
    showScriptEditor?.let { waypointId ->
        ScriptEditorDialog(
            waypointId = waypointId,
            tourConfigRepository = tourConfigRepository,
            onDismiss = { showScriptEditor = null }
        )
    }
}

@Composable
fun ScriptEditorDialog(
    waypointId: String,
    tourConfigRepository: TourConfigRepository,
    onDismiss: () -> Unit
) {
    val scope = rememberCoroutineScope()
    var script by remember { mutableStateOf("") }

    LaunchedEffect(waypointId) {
        script = tourConfigRepository.getScript(waypointId)
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Edit Script for: $waypointId") },
        text = {
            OutlinedTextField(
                value = script,
                onValueChange = { script = it },
                modifier = Modifier.fillMaxWidth().height(200.dp)
            )
        },
        confirmButton = {
            Button(onClick = {
                scope.launch {
                    tourConfigRepository.saveScript(waypointId, script)
                }
                onDismiss()
            }) {
                Text("Save")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        }
    )
}
