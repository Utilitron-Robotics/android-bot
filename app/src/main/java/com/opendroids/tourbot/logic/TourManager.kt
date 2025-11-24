package com.opendroids.tourbot.logic

import android.content.Context
import android.util.Log
import com.opendroids.tourbot.data.TourConfigRepository // Import TourConfigRepository
import com.opendroids.tourbot.data.TourRepository
import com.opendroids.tourbot.data.model.TourState
import com.opendroids.tourbot.data.model.Waypoint
import com.opendroids.tourbot.data.settings.SettingsManager
import com.opendroids.tourbot.ui.audio.AudioPlayer
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.delay
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

@Singleton
class TourManager @Inject constructor(
    @param:ApplicationContext private val context: Context,
    private val tourRepository: TourRepository,
    private val audioPlayer: AudioPlayer,
    private val settingsManager: SettingsManager,
    private val tourConfigRepository: TourConfigRepository // Inject TourConfigRepository
) {

    private val _tourState = MutableStateFlow<TourState>(TourState.Idle)
    val tourState: StateFlow<TourState> = _tourState.asStateFlow()

    private var tourJob: Job? = null
    private val tourScope = CoroutineScope(Dispatchers.Main)

    val waypointIds: StateFlow<List<String>> = tourConfigRepository.waypointIds
        .stateIn(tourScope, SharingStarted.Eagerly, emptyList())

    fun startTour() {
        // Corrected: Always cancel the previous job to ensure a clean start.
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
            tourRepository.disconnect()
        }
    }

    private suspend fun runTour() {
        try {
            // 1. Connect and check battery
            val robotUrl = settingsManager.robotUrl.first()
            tourRepository.connect(robotUrl)
            
            Log.i(TAG, "Checking battery level...")
            tourRepository.getBatteryLevel().take(1).collect { battery ->
                Log.i(TAG, "🔋 Battery level at tour start: $battery%")
                if (battery < 20) audioPlayer.speak("Warning, battery is low at $battery percent.")
            }

            // 2. Play START script
            Log.i(TAG, "Playing START script")
            createWaypoint("start")?.let {
                _tourState.value = TourState.Speaking(it)
                if (it.audioResId != 0) {
                    audioPlayer.play(it.audioResId, it.scriptContent)
                } else {
                    audioPlayer.speak(it.scriptContent)
                }
            }

            // 3. Iterate through waypoints (excluding "start")
            for (id in waypointIds.value.drop(1)) {
                val waypoint = createWaypoint(id) ?: continue

                // Navigate
                _tourState.value = TourState.Navigating(waypoint)
                Log.i(TAG, "Sending navigation command to ${waypoint.id}")
                tourRepository.goTo(waypoint.id)
                
                Log.i(TAG, "Waiting for arrival at ${waypoint.id}...")
                if (!waitForArrival(waypoint.id)) {
                    Log.e(TAG, "Failed to reach ${waypoint.id}, aborting tour")
                    audioPlayer.speak("Failed to reach ${waypoint.id}, aborting tour.")
                    _tourState.value = TourState.Error("Failed to reach ${waypoint.id}")
                    return // Exits runTour, cleanup happens in finally
                }
                Log.i(TAG, "✓ Reached ${waypoint.id}")
                audioPlayer.speak("Arrived at ${waypoint.id}.") // Announce arrival

                // Wait for pre-speak delay
                val preSpeakDelay = tourConfigRepository.preSpeakDelay.first()
                Log.d(TAG, "Waiting for pre-speak delay of $preSpeakDelay ms")
                delay(preSpeakDelay.toLong())

                // Speak
                _tourState.value = TourState.Speaking(waypoint)
                Log.i(TAG, "Playing audio for ${waypoint.id}")
                if (waypoint.audioResId != 0) {
                    audioPlayer.play(waypoint.audioResId, waypoint.scriptContent)
                } else {
                    audioPlayer.speak(waypoint.scriptContent) // Fallback to TTS
                }
                Log.i(TAG, "✓ Audio playback complete for ${waypoint.id}")
            }

            _tourState.value = TourState.Completed
            audioPlayer.speak("Tour completed.")
            Log.i(TAG, "✅ TOUR COMPLETED")

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
        } finally {
            Log.i(TAG, "Cleaning up main tour resources...")
            audioPlayer.stop() // Stop any ongoing audio playback
            tourRepository.cancelNavigation()
            // Disconnect is now handled by returnToStart or if the tour completes naturally
        }
    }
    
    private suspend fun waitForArrival(destinationName: String): Boolean {
        Log.d(TAG, "waitForArrival: Starting for $destinationName")

        return try {
            withTimeout(300_000) { // 5 minutes timeout
                var navigationStarted = false
                tourRepository.observeStatus()
                    .mapNotNull { it.navStatus }
                    .transformWhile { nav ->
                        Log.d(TAG, "waitForArrival: Received navStatus=$nav, navigationStarted=$navigationStarted for $destinationName")
                        when (nav) {
                            601 -> { // Moving
                                if (!navigationStarted) {
                                    navigationStarted = true
                                    Log.i(TAG, "🚶 Robot moving to $destinationName...")
                                }
                                Log.d(TAG, "waitForArrival: Continuing for navStatus=601")
                                true // Continue collecting
                            }
                            603, 604 -> { // Arrived or Already There
                                if (nav == 603 && !navigationStarted) {
                                    Log.d(TAG, "waitForArrival: Ignoring stale 603 before movement started for $destinationName")
                                    true // Ignore stale 603 before movement starts
                                } else {
                                    Log.d(TAG, "waitForArrival: Emitting true for navStatus=$nav for $destinationName")
                                    emit(true)
                                    false // Stop collecting
                                }
                            }
                            600, 602, 605 -> { // Idle, Paused, Standby -> keep waiting
                                Log.d(TAG, "waitForArrival: Continuing for navStatus=$nav (Idle/Paused/Standby)")
                                true
                            }
                            else -> { // Error status
                                Log.e(TAG, "waitForArrival: Unknown nav status: $nav for $destinationName. Emitting false.")
                                emit(false)
                                false // Stop collecting
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
