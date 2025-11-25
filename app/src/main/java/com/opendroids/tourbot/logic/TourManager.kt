package com.opendroids.tourbot.logic

import android.content.Context
import android.util.Log
import com.opendroids.tourbot.data.TourConfigRepository
import com.opendroids.tourbot.data.TourRepository
import com.opendroids.tourbot.data.model.TourState
import com.opendroids.tourbot.data.model.Waypoint
import com.opendroids.tourbot.data.remote.model.RobotStatusMessage
import com.opendroids.tourbot.data.settings.SettingsManager
import com.opendroids.tourbot.ui.audio.AudioPlayer
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.transformWhile
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout
import java.io.IOException
import javax.inject.Inject
import javax.inject.Singleton

private const val TAG = "TourManager"
private const val MAX_RECONNECTION_ATTEMPTS = 3
private const val RECONNECTION_DELAY_MS = 2000L
private const val AUDIO_PLAYBACK_TIMEOUT_MS = 120_000L // 2 minutes
private const val MAX_IDLE_MESSAGES = 50

@Singleton
class TourManager @Inject constructor(
    @param:ApplicationContext private val context: Context,
    private val tourRepository: TourRepository,
    private val audioPlayer: AudioPlayer,
    private val settingsManager: SettingsManager,
    private val tourConfigRepository: TourConfigRepository
) {

    private val _tourState = MutableStateFlow<TourState>(TourState.Idle)
    val tourState: StateFlow<TourState> = _tourState.asStateFlow()

    private var tourJob: Job? = null
    private val tourScope = CoroutineScope(Dispatchers.Main)

    // Shared flow for status updates to handle single subscription and avoid stale states
    private var statusCollectionJob: Job? = null
    private val _sharedStatusFlow = MutableSharedFlow<RobotStatusMessage>(
        replay = 0,
        extraBufferCapacity = 1,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )

    val waypointIds: StateFlow<List<String>> = tourConfigRepository.waypointIds
        .stateIn(tourScope, SharingStarted.Eagerly, emptyList())

    fun startTour() {
        tourJob?.cancel() 
        _tourState.value = TourState.Idle

        Log.i(TAG, "🎬 Tour start requested.")
        tourJob = tourScope.launch {
            runTour()
        }
    }

    fun abort() {
        if (tourState.value is TourState.Idle) return
        
        Log.i(TAG, "⛔ Tour abort requested")
        // Simple cancellation - matches Python behavior (just cancel the task)
        tourJob?.cancel(CancellationException("User aborted tour"))
    }

    /**
     * Main tour execution loop - Direct port of Python's _run_tour_background()
     * 
     * This follows the same structure as the Python version:
     * 1. Connect to robot
     * 2. Subscribe to status
     * 3. Check battery level (optional, logs warning if low)
     * 4. Play "start" script without navigation
     * 5. Loop through waypoints: navigate -> play script
     * 6. Disconnect and complete
     */
    private suspend fun runTour() {
    try {
        // 1. Connect and check battery
        val robotUrl = settingsManager.robotUrl.first()
        
        Log.i(TAG, "Connecting to robot...")
        if (!tourRepository.tryConnect(robotUrl)) {
             throw IOException("Failed to connect to robot at $robotUrl")
        }
        Log.i(TAG, "Robot connected successfully")
        
        // Start persistent status collection (Subscribe ONCE)
        Log.i(TAG, "Subscribing to robot status updates...")
        tourRepository.subscribeStatus() // Send subscription command
        statusCollectionJob?.cancel()
        statusCollectionJob = tourScope.launch {
            tourRepository.observeStatus().collect {
                _sharedStatusFlow.emit(it)
            }
        }
        // Allow some time for subscription to establish and potential stale messages to flush
        delay(1000)

        // Battery check - Ported from Python (lines 238-247 in tour_bot.py)
        // Python: battery = await self.commands.get_battery_level(timeout=3.0)
        // Kotlin: Using Flow with timeout instead of direct async call
        Log.i(TAG, "Checking battery level...")
        try {
            withTimeout(5000) {
                tourRepository.getBatteryLevel().take(1).collect { battery ->
                    Log.i(TAG, "🔋 Battery level at tour start: $battery%")
                    // Match Python's warning thresholds
                    if (battery < 20) {
                        Log.w(TAG, "⚠️ LOW BATTERY WARNING: $battery% - Tour may fail!")
                        audioPlayer.speak("Warning, battery is critically low at $battery percent.")
                    } else if (battery < 40) {
                        Log.w(TAG, "⚠️ Battery is low: $battery% - Monitor closely")
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ Could not read battery level: ${e.message}")
        }

        // 2. Play START script
        playScriptAtLocation("start", "Playing introduction")

        // 3. Iterate through waypoints (including 'end' which returns to home)
        val waypoints = waypointIds.value
        for ((index, id) in waypoints.withIndex()) {
            _tourState.value = TourState.Navigating(createWaypoint(id)!!)
            
            val navSuccess = navigateToWaypointWithRetry(id)
            
            if (!navSuccess) {
                Log.e(TAG, "Failed to reach $id, aborting tour")
                audioPlayer.speak("Failed to reach $id, aborting tour.")
                _tourState.value = TourState.Error("Failed to reach $id")
                return // Exits runTour, cleanup happens in finally
            }
            
            // Play script after arriving at waypoint
            playScriptAtLocation(id, "At $id")
        }

        _tourState.value = TourState.Completed
        audioPlayer.speak("Tour completed.")
        Log.i(TAG, "✅ TOUR COMPLETED")
        
        // Disconnect after successful completion (matches Python)
        cleanupAndDisconnect()
        Log.i(TAG, "Disconnected from robot after tour completion")

    } catch (e: CancellationException) {
        // Tour cancelled by user - matches Python's asyncio.CancelledError handler
        Log.w(TAG, "⛔ Tour cancelled: ${e.message}")
        _tourState.value = TourState.Idle
        cleanupAndDisconnect()
        // Re-throw to allow parent coroutine to know about cancellation
        throw e
    } catch (e: Exception) {
        // Unexpected error - matches Python's Exception handler
        Log.e(TAG, "Tour failed: ${e.message}", e)
        audioPlayer.speak("Tour failed with an error.")
        _tourState.value = TourState.Error(e.message ?: "Unknown error")
        cleanupAndDisconnect()
    } finally {
        // Always cleanup resources (matches Python's implicit cleanup)
        Log.i(TAG, "Cleaning up tour resources...")
        audioPlayer.stop()
        try {
            tourRepository.cancelNavigation()
        } catch (e: Exception) {
            Log.w(TAG, "Error cancelling navigation: ${e.message}")
        }
        statusCollectionJob?.cancel()
    }
}
    
    private suspend fun cleanupAndDisconnect() {
        statusCollectionJob?.cancel()
        try {
            tourRepository.unsubscribeStatus()
        } catch (e: Exception) {
            Log.w(TAG, "Error unsubscribing: ${e.message}")
        }
        try {
            tourRepository.disconnect()
        } catch (e: Exception) {
            Log.w(TAG, "Error disconnecting: ${e.message}")
        }
    }
    
    /**
     * Navigate to waypoint with automatic retry on failure
     * Ported from Python's _navigate_to_waypoint() (lines 310-362 in tour_bot.py)
     * 
     * Python logic:
     * 1. Try to navigate
     * 2. If ConnectionError -> reconnect -> retry once
     * 3. Return success/failure
     */
    private suspend fun navigateToWaypointWithRetry(marker: String): Boolean {
        try {
            Log.i(TAG, "Sending navigation command to $marker...")
            tourRepository.goTo(marker)

            Log.i(TAG, "Waiting for arrival at $marker...")
            val success = waitForArrival(marker)

            if (success) {
                Log.i(TAG, "✓ Reached $marker")
                return true
            }
            
            // Navigation failed - attempt recovery (matches Python's reconnection logic)
            Log.w(TAG, "⚠️ Navigation to $marker failed or timed out. Attempting recovery...")
            
            val reconnected = reconnectRobot()
            if (!reconnected) {
                return false
            }

            // Retry navigation after reconnection (matches Python retry)
            Log.i(TAG, "🔄 Retrying waypoint $marker...")
            try {
                tourRepository.goTo(marker)
                val retrySuccess = waitForArrival(marker)
                if (retrySuccess) {
                    Log.i(TAG, "✓ Reached $marker after reconnection")
                    return true
                }
            } catch (retryError: Exception) {
                Log.e(TAG, "❌ Retry failed: ${retryError.message}")
            }
            
            return false

        } catch (e: Exception) {
            // Connection error during navigation - attempt reconnect (matches Python)
            Log.w(TAG, "⚠️ Exception during navigation: ${e.message}")
            
            val reconnected = reconnectRobot()
            if (!reconnected) {
                return false
            }

            // Retry navigation
            Log.i(TAG, "🔄 Retrying waypoint $marker...")
            try {
                tourRepository.goTo(marker)
                val retrySuccess = waitForArrival(marker)
                if (retrySuccess) {
                    Log.i(TAG, "✓ Reached $marker after reconnection")
                    return true
                }
            } catch (retryError: Exception) {
                Log.e(TAG, "❌ Retry failed: ${retryError.message}")
            }
            return false
        }
    }
    
    /**
     * Reconnect to robot after connection loss
     * Ported from BaseRobotApplication.reconnect_robot() in base_api.py (lines 52-91)
     * 
     * Uses constants matching Python settings:
     * - MAX_RECONNECTION_ATTEMPTS = 3 (matches MAX_RECONNECTION_ATTEMPTS)
     * - RECONNECTION_DELAY_MS = 2000 (matches RECONNECTION_DELAY)
     */
    private suspend fun reconnectRobot(): Boolean {
        Log.w(TAG, "🔄 Attempting to reconnect...")
        val robotUrl = settingsManager.robotUrl.first()

        // Cancel existing status collection on disconnect
        statusCollectionJob?.cancel()

        for (attempt in 1..MAX_RECONNECTION_ATTEMPTS) {
            try {
                Log.i(TAG, "Reconnection attempt $attempt/$MAX_RECONNECTION_ATTEMPTS")
                
                // Clean up old connection (matches Python's try/except cleanup)
                try { tourRepository.disconnect() } catch (e: Exception) { /* ignore */ }
                delay(500) // Brief pause before reconnect
                
                if (tourRepository.tryConnect(robotUrl)) {
                    Log.i(TAG, "✓ Reconnected successfully")
                    
                    // Resubscribe to status (matches Python's resubscription)
                    tourRepository.subscribeStatus()
                    
                    // Restart status collection after reconnection
                    statusCollectionJob = tourScope.launch {
                        tourRepository.observeStatus().collect {
                            _sharedStatusFlow.emit(it)
                        }
                    }
                    delay(1000) // Wait for subscription to establish
                    
                    return true
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ Reconnection attempt $attempt failed: ${e.message}")
            }
            if (attempt < MAX_RECONNECTION_ATTEMPTS) {
                delay(RECONNECTION_DELAY_MS)
            }
        }
        
        Log.e(TAG, "❌ All reconnection attempts exhausted")
        return false
    }

private suspend fun playScriptAtLocation(waypointId: String, description: String) {
    Log.i(TAG, "Processing waypoint: $waypointId ($description)")
    val waypoint = createWaypoint(waypointId) ?: return

    _tourState.value = TourState.Speaking(waypoint)

    try {
        withTimeout(AUDIO_PLAYBACK_TIMEOUT_MS) {
            if (waypoint.audioResId != 0) {
                audioPlayer.play(waypoint.audioResId, waypoint.scriptContent)
            } else {
                audioPlayer.speak(waypoint.scriptContent)
            }
        }
        Log.i(TAG, "✓ Audio playback complete for ${waypoint.id}")
    } catch (e: TimeoutCancellationException) {
        Log.w(TAG, "⚠️ Audio playback timed out for ${waypoint.id} after ${AUDIO_PLAYBACK_TIMEOUT_MS}ms")
    }

    // Delay after speech before next move
    delay(1000)
}
    
    /**
     * Wait for robot to arrive at destination by monitoring status messages
     * Ported from TiboCommands.wait_until_arrival() in tibo_commands.py (lines 194-308)
     * 
     * Python logic: Simple while loop calling receive_message()
     * Kotlin adaptation: Uses Flow collection with transformWhile for same logic
     * 
     * Status codes (matches Python exactly):
     * - 600/605: Idle/Standby - wait for movement
     * - 601: Moving - navigation in progress
     * - 602: Paused/Recalculating - continue waiting
     * - 603: Navigation complete (success)
     * - 604: Already at destination (success)
     * - Other: Navigation failed
     */
    private suspend fun waitForArrival(destinationName: String): Boolean {
        Log.d(TAG, "waitForArrival: Starting for $destinationName")

        return try {
            withTimeout(300_000) { // 5 minutes timeout (matches Python's default)
                var navigationStarted = false
                var idleMessageCount = 0
                
                // Collect from the shared flow (single subscription)
                // IMPORTANT: Only emit when we have a FINAL result (arrived or failed)
                // NOT during intermediate states (moving, pausing, etc.)
                _sharedStatusFlow
                    .mapNotNull { it.navStatus }
                    .transformWhile { nav ->
                        Log.d(TAG, "waitForArrival: Received navStatus=$nav")
                        when (nav) {
                            601 -> { // Moving
                                idleMessageCount = 0 // Reset counter
                                if (!navigationStarted) {
                                    navigationStarted = true
                                    Log.i(TAG, "🚶 Robot moving to $destinationName...")
                                }
                                // DON'T emit - just continue waiting
                                true // Continue collecting
                            }
                            603, 604 -> { // Arrived or Already There
                                if (nav == 603 && !navigationStarted) {
                                    Log.d(TAG, "waitForArrival: Ignoring stale 603 before movement started")
                                    true // Ignore stale 603 before movement starts
                                } else {
                                    Log.i(TAG, "✓ Arrived at $destinationName (status $nav)")
                                    emit(true) // SUCCESS - emit and stop
                                    false // Stop collecting (Success)
                                }
                            }
                            600, 605 -> { // Idle / Standby
                                if (!navigationStarted) {
                                    idleMessageCount++
                                    if (idleMessageCount < MAX_IDLE_MESSAGES) {
                                        if (idleMessageCount == 1) Log.d(TAG, "Robot in idle state $nav, waiting...")
                                        true // Continue waiting
                                    } else {
                                        Log.e(TAG, "❌ Navigation failed - robot stuck in idle state $nav after $idleMessageCount messages")
                                        emit(false) // FAILURE - emit and stop
                                        false // Stop collecting (Fail)
                                    }
                                } else {
                                    Log.w(TAG, "Robot returned to idle state $nav after starting navigation")
                                    true // Continue waiting
                                }
                            }
                            602 -> { // Paused
                                if (!navigationStarted) {
                                    idleMessageCount++
                                    if (idleMessageCount < MAX_IDLE_MESSAGES) {
                                        if (idleMessageCount == 1) Log.d(TAG, "Robot in state 602 before navigation started, waiting...")
                                        true // Continue waiting
                                    } else {
                                        Log.e(TAG, "❌ Navigation failed - stuck in status $nav")
                                        emit(false) // FAILURE - emit and stop
                                        false // Stop collecting
                                    }
                                } else {
                                    Log.d(TAG, "Robot paused/recalculating (status 602), continuing to wait...")
                                    true // Continue waiting
                                }
                            }
                            else -> { // Error status
                                Log.e(TAG, "waitForArrival: Unknown nav status: $nav for $destinationName. Emitting false.")
                                emit(false) // FAILURE - emit and stop
                                false // Stop collecting
                            }
                        }
                    }.first() // Returns the first (and only) emitted value (true/false)
            }
        } catch (e: TimeoutCancellationException) {
            Log.e(TAG, "Navigation timed out for $destinationName")
            false
        }
    }

    private suspend fun createWaypoint(id: String): Waypoint? {
        return try {
            val script = tourConfigRepository.getScript(id) // Get script from repository
            val resId = context.resources.getIdentifier(id.lowercase(), "raw", context.packageName)
            if (resId == 0) Log.w(TAG, "Audio resource not found for: $id")
            Waypoint(id, script.trim(), resId)
        } catch (e: IOException) {
            Log.e(TAG, "Error loading assets for waypoint $id", e)
            null
        }
    }
}