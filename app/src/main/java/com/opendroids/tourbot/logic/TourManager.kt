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
        tourJob?.cancel(CancellationException("User aborted tour to return to start"))
    }

    private suspend fun returnToStart() {
        Log.i(TAG, "Returning to start...")
        try {
            audioPlayer.speak("Tour aborted. Returning to start.")
            val startWaypoint = createWaypoint("start") ?: return
            _tourState.value = TourState.Navigating(startWaypoint)
            
            // Best effort return
            tourRepository.goTo("start")
            if (waitForArrival("start")) {
                Log.i(TAG, "✓ Arrived back at start.")
                audioPlayer.speak("Arrived at start.")
            } else {
                Log.e(TAG, "Failed to return to start.")
                audioPlayer.speak("Failed to return to start.")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error during return to start: ${e.message}", e)
        } finally {
            _tourState.value = TourState.Idle
            cleanupAndDisconnect()
        }
    }

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
            statusCollectionJob?.cancel()
            statusCollectionJob = tourScope.launch {
                tourRepository.observeStatus().collect {
                    _sharedStatusFlow.emit(it)
                }
            }
            // Allow some time for subscription to establish and potential stale messages to flush
            delay(1000)

            Log.i(TAG, "Checking battery level...")
            try {
                withTimeout(5000) {
                    tourRepository.getBatteryLevel().take(1).collect { battery ->
                        Log.i(TAG, "🔋 Battery level at tour start: $battery%")
                        if (battery < 20) audioPlayer.speak("Warning, battery is low at $battery percent.")
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "⚠️ Could not read battery level: ${e.message}")
            }

            // 2. Play START script
            Log.i(TAG, "Playing START script")
            createWaypoint("start")?.let {
                _tourState.value = TourState.Speaking(it)
                playAudioWithTimeout(it)
            }
            delay(1000) // Delay after intro

            // 3. Iterate through waypoints (excluding "start")
            for (id in waypointIds.value.drop(1)) {
                val waypoint = createWaypoint(id) ?: continue

                // Navigate
                _tourState.value = TourState.Navigating(waypoint)
                
                val navSuccess = navigateToWaypointWithRetry(waypoint.id)
                
                if (!navSuccess) {
                    Log.e(TAG, "Failed to reach ${waypoint.id}, aborting tour")
                    audioPlayer.speak("Failed to reach ${waypoint.id}, aborting tour.")
                    _tourState.value = TourState.Error("Failed to reach ${waypoint.id}")
                    return // Exits runTour, cleanup happens in finally
                }
                
                Log.i(TAG, "✓ Reached ${waypoint.id}")
                audioPlayer.speak("Arrived at ${waypoint.id}.") // Announce arrival

                // Wait for pre-speak delay + slight extra delay for settling
                val preSpeakDelay = tourConfigRepository.preSpeakDelay.first()
                Log.d(TAG, "Waiting for pre-speak delay of $preSpeakDelay ms")
                delay(preSpeakDelay.toLong() + 500)

                // Speak
                _tourState.value = TourState.Speaking(waypoint)
                Log.i(TAG, "Playing audio for ${waypoint.id}")
                playAudioWithTimeout(waypoint)
                Log.i(TAG, "✓ Audio playback complete for ${waypoint.id}")
                
                // Delay after speech before next move
                delay(1000)
            }

            _tourState.value = TourState.Completed
            audioPlayer.speak("Tour completed.")
            Log.i(TAG, "✅ TOUR COMPLETED")
            
            // Explicitly disconnect after successful tour
            cleanupAndDisconnect()
            Log.i(TAG, "Disconnected from robot after tour completion")

        } catch (e: CancellationException) {
            Log.w(TAG, "⛔ Tour cancelled: ${e.message}")
            // Launch a new coroutine to handle returning to the start
            tourScope.launch {
                returnToStart()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Tour failed: ${e.message}", e)
            audioPlayer.speak("Tour failed with an error.")
            _tourState.value = TourState.Error(e.message ?: "Unknown error")
            // Try to disconnect on error
            cleanupAndDisconnect()
        } finally {
            Log.i(TAG, "Cleaning up main tour resources...")
            audioPlayer.stop() // Stop any ongoing audio playback
            tourRepository.cancelNavigation()
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
            
            Log.w(TAG, "⚠️ Navigation to $marker failed or timed out. Attempting recovery...")
            
            // Attempt reconnection
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

        } catch (e: Exception) {
            Log.w(TAG, "⚠️ Exception during navigation: ${e.message}")
            
             // Attempt reconnection
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
    
    private suspend fun reconnectRobot(): Boolean {
        Log.w(TAG, "🔄 Attempting to reconnect...")
        val robotUrl = settingsManager.robotUrl.first()

        // Cancel existing status collection on disconnect
        statusCollectionJob?.cancel()

        for (attempt in 1..MAX_RECONNECTION_ATTEMPTS) {
            try {
                Log.i(TAG, "Reconnection attempt $attempt/$MAX_RECONNECTION_ATTEMPTS")
                
                // Clean up old connection
                try { tourRepository.disconnect() } catch (e: Exception) { /* ignore */ }
                delay(500) // Brief pause
                
                if (tourRepository.tryConnect(robotUrl)) {
                    Log.i(TAG, "✓ Reconnected successfully")
                    
                    // Restart status collection after reconnection
                    statusCollectionJob = tourScope.launch {
                        tourRepository.observeStatus().collect {
                            _sharedStatusFlow.emit(it)
                        }
                    }
                    delay(1000) // Wait for re-subscription
                    
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

    private suspend fun playAudioWithTimeout(waypoint: Waypoint) {
        try {
            withTimeout(AUDIO_PLAYBACK_TIMEOUT_MS) {
                if (waypoint.audioResId != 0) {
                    audioPlayer.play(waypoint.audioResId, waypoint.scriptContent)
                } else {
                    audioPlayer.speak(waypoint.scriptContent)
                }
            }
        } catch (e: TimeoutCancellationException) {
            Log.w(TAG, "⚠️ Audio playback timed out for ${waypoint.id} after ${AUDIO_PLAYBACK_TIMEOUT_MS}ms")
        }
    }
    
    private suspend fun waitForArrival(destinationName: String): Boolean {
        Log.d(TAG, "waitForArrival: Starting for $destinationName")

        return try {
            withTimeout(300_000) { // 5 minutes timeout
                var navigationStarted = false
                var idleMessageCount = 0
                
                // Collect from the shared flow (single subscription)
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
                                emit(true) // Keep alive signal
                                true // Continue collecting
                            }
                            603, 604 -> { // Arrived or Already There
                                if (nav == 603 && !navigationStarted) {
                                    Log.d(TAG, "waitForArrival: Ignoring stale 603 before movement started")
                                    true // Ignore stale 603 before movement starts
                                } else {
                                    Log.i(TAG, "✓ Arrived at $destinationName (status $nav)")
                                    emit(true) 
                                    false // Stop collecting (Success)
                                }
                            }
                            600, 605 -> { // Idle / Standby
                                if (!navigationStarted) {
                                    idleMessageCount++
                                    if (idleMessageCount < MAX_IDLE_MESSAGES) {
                                        if (idleMessageCount == 1) Log.d(TAG, "Robot in idle state $nav, waiting...")
                                        true
                                    } else {
                                        Log.e(TAG, "❌ Navigation failed - robot stuck in idle state $nav after $idleMessageCount messages")
                                        emit(false)
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
                                        true
                                    } else {
                                        Log.e(TAG, "❌ Navigation failed - stuck in status $nav")
                                        emit(false)
                                        false
                                    }
                                } else {
                                    Log.d(TAG, "Robot paused/recalculating (status 602), continuing to wait...")
                                    true
                                }
                            }
                            else -> { // Error status
                                Log.e(TAG, "waitForArrival: Unknown nav status: $nav for $destinationName. Emitting false.")
                                emit(false)
                                false // Stop collecting
                            }
                        }
                    }.first() // Returns the first emitted value (true/false)
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