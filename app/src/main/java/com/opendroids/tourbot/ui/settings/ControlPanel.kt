package com.opendroids.tourbot.ui.settings

import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Menu
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.opendroids.tourbot.ui.MainViewModel
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ControlPanel(
    onDismiss: () -> Unit,
    mainViewModel: MainViewModel,
    settingsViewModel: SettingsViewModel = hiltViewModel()
) {
    val scope = rememberCoroutineScope()
    val waypointIds by mainViewModel.waypointIds.collectAsState()
    val homeWaypointId by mainViewModel.homeWaypointId.collectAsState()
    val isInTestMode by mainViewModel.isInTestMode.collectAsState()
    val preSpeakDelay by settingsViewModel.preSpeakDelay.collectAsState()
    val robotUrl by mainViewModel.robotUrl.collectAsState()
    val showNerdData by mainViewModel.showNerdData.collectAsState()

    var showScriptEditor by remember { mutableStateOf<String?>(null) }
    var showAddWaypointDialog by remember { mutableStateOf(false) }

    val listState = rememberLazyListState()
    val dragDropState = rememberDragDropState(listState) { fromIndex, toIndex ->
        // This state should be hoisted to the ViewModel
    }

    ModalBottomSheet(onDismissRequest = onDismiss) {
        val tabs = listOf("Settings", "Error Log")
        var selectedTabIndex by remember { mutableStateOf(0) }

        Column(
            modifier = Modifier
                .navigationBarsPadding()
                .padding(horizontal = 16.dp)
                .verticalScroll(rememberScrollState())
        ) {
            TabRow(selectedTabIndex = selectedTabIndex) {
                tabs.forEachIndexed { index, title ->
                    Tab(
                        selected = selectedTabIndex == index,
                        onClick = { selectedTabIndex = index },
                        text = { Text(title) }
                    )
                }
            }

            when (selectedTabIndex) {
                0 -> SettingsTab(
                    preSpeakDelay = preSpeakDelay,
                    onPreSpeakDelayChange = { settingsViewModel.setPreSpeakDelay(it) },
                    robotUrl = robotUrl,
                    onRobotUrlChange = { mainViewModel.setRobotUrl(it) },
                    waypointIds = waypointIds,
                    onWaypointClick = { showScriptEditor = it },
                    onRemoveWaypoint = { id ->
                        // mainViewModel.removeWaypoint(id)
                    },
                    onAddWaypointClick = { showAddWaypointDialog = true },
                    dragDropState = dragDropState,
                    onSaveWaypoints = { newWaypointIds ->
                        // mainViewModel.saveWaypoints(newWaypointIds)
                    },
                    isInTestMode = isInTestMode,
                    onTestModeChange = { mainViewModel.setTestMode(it) },
                    homeWaypointId = homeWaypointId,
                    onHomeWaypointSelected = { mainViewModel.setHomeWaypoint(it) },
                    showNerdData = showNerdData,
                    onShowNerdDataChange = { mainViewModel.onShowNerdDataChange(it) }
                )
                1 -> ErrorLogTab(mainViewModel = mainViewModel)
            }
            Spacer(modifier = Modifier.height(32.dp))
        }
    }

    showScriptEditor?.let { waypointId ->
        ScriptEditorDialog(
            waypointId = waypointId,
            onDismiss = { showScriptEditor = null },
            onSave = { script ->
                // mainViewModel.saveScript(waypointId, script)
            }
        )
    }

    if (showAddWaypointDialog) {
        AddWaypointDialog(
            onDismiss = { showAddWaypointDialog = false },
            onAdd = { newId ->
                // mainViewModel.addWaypoint(newId)
                showAddWaypointDialog = false
                showScriptEditor = newId
            }
        )
    }
}

@Composable
fun SettingsTab(
    preSpeakDelay: Int,
    onPreSpeakDelayChange: (Int) -> Unit,
    robotUrl: String,
    onRobotUrlChange: (String) -> Unit,
    waypointIds: List<String>,
    onWaypointClick: (String) -> Unit,
    onRemoveWaypoint: (String) -> Unit,
    onAddWaypointClick: () -> Unit,
    dragDropState: DragDropState,
    onSaveWaypoints: (List<String>) -> Unit,
    isInTestMode: Boolean,
    onTestModeChange: (Boolean) -> Unit,
    homeWaypointId: String,
    onHomeWaypointSelected: (String) -> Unit,
    showNerdData: Boolean,
    onShowNerdDataChange: (Boolean) -> Unit
) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Text("Base Control", style = MaterialTheme.typography.titleMedium)
        OutlinedTextField(
            value = robotUrl,
            onValueChange = onRobotUrlChange,
            label = { Text("Robot WebSocket URL") },
            modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp)
        )
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp)
        ) {
            Text("Test Mode", modifier = Modifier.weight(1f))
            Switch(checked = isInTestMode, onCheckedChange = onTestModeChange)
        }
        HomeWaypointSelector(
            waypointIds = waypointIds,
            selectedWaypointId = homeWaypointId,
            onWaypointSelected = onHomeWaypointSelected
        )
        NerdDataToggle(
            checked = showNerdData,
            onCheckedChange = onShowNerdDataChange
        )
        Divider(modifier = Modifier.padding(vertical = 16.dp))
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(vertical = 8.dp)) {
            Text("Pre-speak delay (ms):", modifier = Modifier.weight(1f))
            OutlinedTextField(
                value = preSpeakDelay.toString(),
                onValueChange = { onPreSpeakDelayChange(it.toIntOrNull() ?: 0) },
                modifier = Modifier.width(100.dp)
            )
        }
        Divider(modifier = Modifier.padding(vertical = 16.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Waypoint Scripts", style = MaterialTheme.typography.titleMedium)
            Spacer(modifier = Modifier.weight(1f))
            IconButton(onClick = onAddWaypointClick) {
                Icon(Icons.Default.Add, contentDescription = "Add Waypoint")
            }
        }
        Box(modifier = Modifier.height(300.dp)) {
            LazyColumn(
                state = dragDropState.listState,
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
                            .clickable { onWaypointClick(waypointId) },
                        leadingContent = {
                            Icon(
                                imageVector = Icons.Default.Menu,
                                contentDescription = "Drag to reorder"
                            )
                        },
                        trailingContent = {
                            IconButton(onClick = { onRemoveWaypoint(waypointId) }) {
                                Icon(Icons.Default.Delete, contentDescription = "Delete Waypoint")
                            }
                        }
                    )
                }
            }
        }
    }
}

@Composable
private fun NerdDataToggle(
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Column(Modifier.weight(1f)) {
            Text("Show Nerd Data", style = MaterialTheme.typography.bodyLarge)
            Text(
                "Display robot communication log on screen",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.typography.bodySmall.color.copy(alpha = 0.7f)
            )
        }
        Spacer(Modifier.width(16.dp))
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeWaypointSelector(
    waypointIds: List<String>,
    selectedWaypointId: String,
    onWaypointSelected: (String) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }

    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp)
    ) {
        Text("Home Waypoint", modifier = Modifier.weight(1f))
        ExposedDropdownMenuBox(
            expanded = expanded,
            onExpandedChange = { expanded = !expanded }
        ) {
            OutlinedTextField(
                value = selectedWaypointId,
                onValueChange = {},
                readOnly = true,
                trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
                modifier = Modifier.menuAnchor()
            )
            ExposedDropdownMenu(
                expanded = expanded,
                onDismissRequest = { expanded = false }
            ) {
                waypointIds.forEach { waypointId ->
                    DropdownMenuItem(
                        text = { Text(waypointId) },
                        onClick = {
                            onWaypointSelected(waypointId)
                            expanded = false
                        }
                    )
                }
            }
        }
    }
}

@Composable
fun ErrorLogTab(mainViewModel: MainViewModel) {
    val errors by mainViewModel.errors.collectAsState()
    val listState = rememberLazyListState()

    Column(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text("Error Log", style = MaterialTheme.typography.titleMedium)
            Button(onClick = { mainViewModel.clearErrors() }) {
                Text("Clear Log")
            }
        }
        Spacer(modifier = Modifier.height(8.dp))
        Box(modifier = Modifier.height(300.dp)) {
            LazyColumn(state = listState, modifier = Modifier.fillMaxSize()) {
                if (errors.isEmpty()) {
                    item { Text("No errors logged yet.") }
                } else {
                    itemsIndexed(errors, key = { _, error -> error.timestamp + error.message }) { _, error ->
                        Column(modifier = Modifier.padding(vertical = 4.dp)) {
                            Text(text = error.timestamp, style = MaterialTheme.typography.labelSmall)
                            Text(text = error.message, color = MaterialTheme.colorScheme.error)
                            error.stackTrace?.let {
                                Text(text = it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error.copy(alpha = 0.7f))
                            }
                        }
                        Divider()
                    }
                }
            }
        }
    }
}

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
        val currentItemCenter = currentItem.offset + currentItem.size / 2 + draggingItemOffset

        val targetIndex = listState.layoutInfo.visibleItemsInfo
            .firstOrNull {
                val targetCenter = it.offset + it.size / 2
                when {
                    currentIndex < it.index -> currentItemCenter > targetCenter
                    currentIndex > it.index -> currentItemCenter < targetCenter
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
    onDismiss: () -> Unit,
    onSave: (String) -> Unit
) {
    val scope = rememberCoroutineScope()
    var script by remember { mutableStateOf("") }

    // In a real app, you'd fetch the script content here
    // LaunchedEffect(waypointId) {
    //     script = mainViewModel.getScript(waypointId)
    // }

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
                onSave(script)
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
