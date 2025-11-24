@file:OptIn(ExperimentalMaterial3Api::class)

package com.opendroids.tourbot.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.opendroids.tourbot.data.TourConfigRepository
import com.opendroids.tourbot.logic.TourManager
import com.opendroids.tourbot.ui.MainViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

@Composable
fun ControlPanel(
    onDismiss: () -> Unit,
    tourManager: TourManager,
    tourConfigRepository: TourConfigRepository,
    mainViewModel: MainViewModel,
    settingsViewModel: SettingsViewModel = hiltViewModel()
) {
    val preSpeakDelay by settingsViewModel.preSpeakDelay.collectAsState()
    val robotUrl by mainViewModel.robotUrl.collectAsState()
    val isTestMode by mainViewModel.isTestMode.collectAsState()
    var waypointIds by remember { mutableStateOf(emptyList<String>()) }
    var showScriptEditor by remember { mutableStateOf<String?>(null) }
    var showAddWaypointDialog by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    val dragDropState = rememberDragDropState(listState) { fromIndex, toIndex ->
        waypointIds = waypointIds.toMutableList().apply {
            add(toIndex, removeAt(fromIndex))
        }
    }

    LaunchedEffect(key1 = Unit) {
        tourManager.waypointIds.collect {
            if (!dragDropState.isDragging) {
                waypointIds = it
            }
        }
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Control Panel") },
        text = {
            Column(modifier = Modifier.fillMaxWidth()) {
                // ... (rest of the settings remain the same)
                Text("Base Control", style = MaterialTheme.typography.titleMedium)
                OutlinedTextField(
                    value = robotUrl,
                    onValueChange = { mainViewModel.setRobotUrl(it) },
                    label = { Text("Robot WebSocket URL") },
                    modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp)
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Test Mode")
                    Spacer(modifier = Modifier.weight(1f))
                    Switch(checked = isTestMode, onCheckedChange = { mainViewModel.setTestMode(it) })
                }
                Divider(modifier = Modifier.padding(vertical = 16.dp))
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(vertical = 8.dp)) {
                    Text("Pre-speak delay (ms):", modifier = Modifier.weight(1f))
                    OutlinedTextField(
                        value = preSpeakDelay.toString(),
                        onValueChange = { settingsViewModel.setPreSpeakDelay(it.toIntOrNull() ?: 0) },
                        modifier = Modifier.width(100.dp)
                    )
                }
                Divider(modifier = Modifier.padding(vertical = 16.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Waypoint Scripts", style = MaterialTheme.typography.titleMedium)
                    Spacer(modifier = Modifier.weight(1f))
                    IconButton(onClick = { showAddWaypointDialog = true }) {
                        Icon(Icons.Default.Add, contentDescription = "Add Waypoint")
                    }
                }

                Box(modifier = Modifier.height(300.dp)) {
                    LazyColumn(
                        state = listState,
                        modifier = Modifier.pointerInput(dragDropState) {
                            detectDragGesturesAfterLongPress(
                                onDrag = { change, dragAmount ->
                                    change.consume()
                                    dragDropState.onDrag(dragAmount)
                                },
                                onDragStart = { offset -> dragDropState.onDragStart(offset) },
                                onDragEnd = { dragDropState.onDragEnd() },
                                onDragCancel = { dragDropState.onDragCancel() }
                            )
                        },
                        userScrollEnabled = !dragDropState.isDragging
                    ) {
                        itemsIndexed(waypointIds, key = { _, item -> item }) { index, waypointId ->
                            val displacementOffset = if (index == dragDropState.draggingItemIndex) {
                                dragDropState.draggingItemOffset
                            } else {
                                0f
                            }
                            ListItem(
                                headlineContent = { Text(waypointId) },
                                modifier = Modifier
                                    .graphicsLayer { translationY = displacementOffset }
                                    .clickable { showScriptEditor = waypointId },
                                leadingContent = {
                                    Icon(
                                        imageVector = Icons.Default.Menu,
                                        contentDescription = "Drag to reorder"
                                    )
                                },
                                trailingContent = {
                                    IconButton(onClick = {
                                        scope.launch {
                                            tourConfigRepository.removeWaypoint(waypointId)
                                        }
                                    }) {
                                        Icon(Icons.Default.Delete, contentDescription = "Delete Waypoint")
                                    }
                                }
                            )
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = {
                scope.launch {
                    tourConfigRepository.saveWaypoints(waypointIds)
                }
                onDismiss()
            }) {
                Text("Save & Close")
            }
        }
    )

    showScriptEditor?.let { waypointId ->
        ScriptEditorDialog(
            waypointId = waypointId,
            tourConfigRepository = tourConfigRepository,
            onDismiss = { showScriptEditor = null }
        )
    }

    if (showAddWaypointDialog) {
        AddWaypointDialog(
            onDismiss = { showAddWaypointDialog = false },
            onAdd = { newId ->
                scope.launch {
                    tourConfigRepository.addWaypoint(newId)
                    showAddWaypointDialog = false
                    showScriptEditor = newId
                }
            }
        )
    }
}

// Drag and Drop State Helper
class DragDropState(
    val listState: LazyListState,
    private val onMove: (Int, Int) -> Unit
) {
    var draggingItemIndex by mutableStateOf<Int?>(null)
    var draggingItemOffset by mutableStateOf(0f)
    val isDragging by derivedStateOf { draggingItemIndex != null }

    fun onDragStart(offset: Offset) {
        listState.layoutInfo.visibleItemsInfo
            .firstOrNull { offset.y.toInt() in it.offset..it.offset + it.size }
            ?.also {
                draggingItemIndex = it.index
            }
    }

    fun onDrag(dragAmount: Offset) {
        draggingItemOffset += dragAmount.y
        val currentIndex = draggingItemIndex ?: return
        val currentItem = listState.layoutInfo.visibleItemsInfo.firstOrNull { it.index == currentIndex } ?: return
        val currentItemCenter = currentItem.offset + draggingItemOffset

        val targetIndex = listState.layoutInfo.visibleItemsInfo
            .firstOrNull {
                val targetCenter = it.offset + it.size / 2
                when {
                    currentIndex < it.index -> currentItemCenter > targetCenter // Dragging down
                    currentIndex > it.index -> currentItemCenter < targetCenter // Dragging up
                    else -> false
                }
            }?.index

        if (targetIndex != null) {
            onMove(currentIndex, targetIndex)
            draggingItemIndex = targetIndex
        }
    }

    fun onDragEnd() {
        draggingItemIndex = null
        draggingItemOffset = 0f
    }

    fun onDragCancel() {
        draggingItemIndex = null
        draggingItemOffset = 0f
    }
}

@Composable
fun rememberDragDropState(
    lazyListState: LazyListState,
    onMove: (Int, Int) -> Unit
): DragDropState {
    return remember { DragDropState(lazyListState, onMove) }
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

@Composable
fun AddWaypointDialog(
    onDismiss: () -> Unit,
    onAdd: (String) -> Unit
) {
    var newWaypointId by remember { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add Waypoint") },
        text = {
            OutlinedTextField(
                value = newWaypointId,
                onValueChange = { newWaypointId = it },
                label = { Text("Waypoint ID") },
                singleLine = true
            )
        },
        confirmButton = {
            Button(
                onClick = {
                    if (newWaypointId.isNotBlank()) {
                        onAdd(newWaypointId)
                    }
                },
                enabled = newWaypointId.isNotBlank()
            ) {
                Text("Add")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        }
    )
}
