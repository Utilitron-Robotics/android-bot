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
import kotlinx.coroutines.SupervisorJob
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
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout
import java.io.IOException
import java.util.concurrent.atomic.AtomicBoolean
import javax.inject.Inject
import javax.inject.Singleton

private const val TAG = "TourManager"
private const val MAX_RECONNECTION_ATTEMPTS = 3
private const val RECONNECTION_DELAY_MS = 2000L
private const val AUDIO_PLAYBACK_TIMEOUT_MS = 120_000L // 2 minutes
private const val MAX_IDLE_MESSAGES = 50
private const val AUTO_RESET_DELAY_MS = 5000L // Reset to Idle 5 seconds after completion

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
    private val tourScope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    private val isStartingTour = AtomicBoolean(false)
    private val tourMutex = Mutex()

    private var statusCollectionJob: Job? = null
    private val _sharedStatusFlow = MutableSharedFlow<RobotStatusMessage>(
        replay = 0,
        extraBufferCapacity = 1,
        onBufferOverflow = BufferOverflow.DROP_OLDEST
    )

    val waypointIds: StateFlow<List<String>> = tourConfigRepository.waypointIds
        .stateIn(tourScope, SharingStarted.Eagerly, emptyList())

    fun startTour() {
        if (!isStartingTour.compareAndSet(false, true)) {
            Log.w(TAG, "⚠️ startTour() called while already starting - ignoring duplicate call")
            return
        }

        val currentState = _tourState.value
        if (currentState !is TourState.Idle &&
            currentState !is TourState.Completed &&
            currentState !is TourState.Error) {
            Log.w(TAG, "⚠️ Tour already in progress (state: $currentState) - ignoring start request")
            isStartingTour.set(false)
            return
        }

        Log.i(TAG, "🎬 Tour start requested.")
        tourJob?.cancel()
        _tourState.value = TourState.Idle

        tourJob = tourScope.launch {
            try {
                runTour()
            } finally {
                isStartingTour.set(false)
            }
        }
    }

    fun abort() {
        if (tourState.value is TourState.Idle || tourState.value is TourState.ReturningHome) return

        Log.i(TAG, "⛔ Tour abort requested")
        tourJob?.cancel(CancellationException("User aborted tour"))

        tourScope.launch {
            _tourState.value = TourState.Aborted
            audioPlayer.speak("Tour aborted. Returning to start.")
            delay(1000) // Give a moment for the message to be seen
            returnHome()
        }
    }

    private suspend fun returnHome() {
        val homeId = tourConfigRepository.homeWaypointId.first()
        val homeWaypoint = createWaypoint(homeId)
        if (homeWaypoint == null) {
            Log.e(TAG, "Cannot return home, home waypoint '$homeId' not found.")
            _tourState.value = TourState.Error("Home waypoint not found")
            return
        }

        Log.i(TAG, "↩️ Returning to home waypoint: $homeId")
        _tourState.value = TourState.ReturningHome(homeWaypoint)

        val navSuccess = navigateToWaypointWithRetry(homeId)
        if (navSuccess) {
            Log.i(TAG, "✓ Arrived at home waypoint.")
            audioPlayer.speak("Arrived at start location.")
        } else {
            Log.e(TAG, "❌ Failed to return to home waypoint.")
            audioPlayer.speak("Failed to return to the start location.")
            _tourState.value = TourState.Error("Failed to return home")
        }
        delay(2000)
        _tourState.value = TourState.Idle
    }

    private suspend fun runTour() {
        try {
            val robotUrl = settingsManager.robotUrl.first()
            
            Log.i(TAG, "Connecting to robot...")
            if (!tourRepository.tryConnect(robotUrl)) {
                 throw IOException("Failed to connect to robot at $robotUrl")
            }
            Log.i(TAG, "Robot connected successfully")
            
            Log.i(TAG, "Subscribing to robot status updates...")
            tourRepository.subscribeStatus()
            statusCollectionJob?.cancel()
            statusCollectionJob = tourScope.launch {
                tourRepository.observeStatus().collect {
                    _sharedStatusFlow.emit(it)
                }
            }
            delay(1000)

            Log.i(TAG, "Checking battery level...")
            try {
                withTimeout(5000) {
                    tourRepository.getBatteryLevel().take(1).collect { battery ->
                        Log.i(TAG, "🔋 Battery level at tour start: $battery%")
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

            playScriptAtLocation("start", "Playing introduction")

            val waypoints = waypointIds.value
            for (id in waypoints) {
                _tourState.value = TourState.Navigating(createWaypoint(id)!!)
                
                val navSuccess = navigateToWaypointWithRetry(id)
                
                if (!navSuccess) {
                    Log.e(TAG, "Failed to reach $id, aborting tour")
                    audioPlayer.speak("Failed to reach $id, aborting tour.")
                    _tourState.value = TourState.Error("Failed to reach $id")
                    return
                }
                
                playScriptAtLocation(id, "At $id")
            }

            _tourState.value = TourState.Completed
            audioPlayer.speak("Tour completed.")
            Log.i(TAG, "✅ TOUR COMPLETED")

            cleanupAndDisconnect()
            Log.i(TAG, "Disconnected from robot after tour completion")

            delay(AUTO_RESET_DELAY_MS)
            _tourState.value = TourState.Idle
            Log.i(TAG, "Tour state reset to Idle")

        } catch (e: CancellationException) {
            Log.w(TAG, "⛔ Tour cancelled: ${e.message}")
            // Don't set state here, abort() handles it
            cleanupAndDisconnect()
            throw e
        } catch (e: Exception) {
            Log.e(TAG, "Tour failed: ${e.message}", e)
            audioPlayer.speak("Tour failed with an error.")
            _tourState.value = TourState.Error(e.message ?: "Unknown error")
            cleanupAndDisconnect()
        } finally {
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
            
            val reconnected = reconnectRobot()
            if (!reconnected) {
                return false
            }

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
            
            val reconnected = reconnectRobot()
            if (!reconnected) {
                return false
            }

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

        statusCollectionJob?.cancel()

        for (attempt in 1..MAX_RECONNECTION_ATTEMPTS) {
            try {
                Log.i(TAG, "Reconnection attempt $attempt/$MAX_RECONNECTION_ATTEMPTS")
                
                try { tourRepository.disconnect() } catch (e: Exception) { /* ignore */ }
                delay(500)
                
                if (tourRepository.tryConnect(robotUrl)) {
                    Log.i(TAG, "✓ Reconnected successfully")
                    
                    tourRepository.subscribeStatus()
                    
                    statusCollectionJob = tourScope.launch {
                        tourRepository.observeStatus().collect {
                            _sharedStatusFlow.emit(it)
                        }
                    }
                    delay(1000)
                    
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

    val preSpeakDelayMs = tourConfigRepository.preSpeakDelay.first()
    if (preSpeakDelayMs > 0) {
        Log.d(TAG, "Pre-speak delay: ${preSpeakDelayMs}ms")
        delay(preSpeakDelayMs.toLong())
    }

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

    delay(1000)
}
    
    private suspend fun waitForArrival(destinationName: String): Boolean {
        Log.d(TAG, "waitForArrival: Starting for $destinationName")

        return try {
            withTimeout(300_000) {
                var navigationStarted = false
                var idleMessageCount = 0
                
                _sharedStatusFlow
                    .mapNotNull { it.navStatus }
                    .transformWhile { nav ->
                        Log.d(TAG, "waitForArrival: Received navStatus=$nav")
                        when (nav) {
                            601 -> {
                                idleMessageCount = 0
                                if (!navigationStarted) {
                                    navigationStarted = true
                                    Log.i(TAG, "🚶 Robot moving to $destinationName...")
                                }
                                true
                            }
                            603, 604 -> {
                                if (nav == 603 && !navigationStarted) {
                                    Log.d(TAG, "waitForArrival: Ignoring stale 603 before movement started")
                                    true
                                } else {
                                    Log.i(TAG, "✓ Arrived at $destinationName (status $nav)")
                                    emit(true)
                                    false
                                }
                            }
                            600, 605 -> {
                                if (!navigationStarted) {
                                    idleMessageCount++
                                    if (idleMessageCount < MAX_IDLE_MESSAGES) {
                                        if (idleMessageCount == 1) Log.d(TAG, "Robot in idle state $nav, waiting...")
                                        true
                                    } else {
                                        Log.e(TAG, "❌ Navigation failed - robot stuck in idle state $nav after $idleMessageCount messages")
                                        emit(false)
                                        false
                                    }
                                } else {
                                    Log.w(TAG, "Robot returned to idle state $nav after starting navigation")
                                    true
                                }
                            }
                            602 -> {
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
                            else -> {
                                Log.e(TAG, "waitForArrival: Unknown nav status: $nav for $destinationName. Emitting false.")
                                emit(false)
                                false
                            }
                        }
                    }.first()
            }
        } catch (e: TimeoutCancellationException) {
            Log.e(TAG, "Navigation timed out for $destinationName")
            false
        }
    }

    private suspend fun createWaypoint(id: String): Waypoint? {
        return try {
            val script = tourConfigRepository.getScript(id)
            val resId = context.resources.getIdentifier(id.lowercase(), "raw", context.packageName)

            if (resId == 0) {
                Log.w(TAG, "⚠️ DEPLOYMENT WARNING: Audio resource 'R.raw.${id.lowercase()}' not found!")
                Log.w(TAG, "   Expected file: app/src/main/res/raw/${id.lowercase()}.wav")
                Log.w(TAG, "   Falling back to TTS for waypoint '$id'")
            }

            if (script.isBlank() || script.startsWith("Script for")) {
                Log.w(TAG, "⚠️ DEPLOYMENT WARNING: Script not found for waypoint '$id'")
                Log.w(TAG, "   Expected file: app/src/main/assets/tour_scripts/$id.txt")
            }

            Waypoint(id, script.trim(), resId)
        } catch (e: IOException) {
            Log.e(TAG, "❌ Error loading assets for waypoint $id", e)
            null
        }
    }
}
