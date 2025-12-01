package com.opendroids.tourbot.logic

import android.content.Context
import com.opendroids.tourbot.data.TourConfigRepository
import com.opendroids.tourbot.data.model.TourState
import com.opendroids.tourbot.logic.tasks.Task
import com.opendroids.tourbot.logic.tasks.WaypointTask
import com.opendroids.tourbot.ui.audio.AudioPlayer
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class TourManager @Inject constructor(
    private val tourConfigRepository: TourConfigRepository,
    private val taskOrchestrator: TaskOrchestrator,
    private val audioPlayer: AudioPlayer,
    @ApplicationContext private val context: Context
) {
    private val tourManagerScope = CoroutineScope(Dispatchers.Main)

    val tourState: StateFlow<TourState> = taskOrchestrator.tourState

    suspend fun startTour() {
        // Play intro message
        val introMessage = readAssetFile("tour_scripts/start.txt")
        if (introMessage.isNotBlank()) {
            audioPlayer.speak(introMessage)
        }

        val waypointIds = tourConfigRepository.waypointIds.first()
        val tasks = mutableListOf<Task>()

        for (waypointId in waypointIds) {
            val script = tourConfigRepository.getScript(waypointId)
            tasks.add(WaypointTask(waypointId, script))
        }

        taskOrchestrator.executeTasks(tasks)
    }

    fun abortTour() {
        tourManagerScope.launch {
            taskOrchestrator.cancelTasks()
            audioPlayer.stop() // Stop any ongoing audio playback

            val homeWaypointId = tourConfigRepository.homeWaypointId.first()
            if (homeWaypointId.isNotBlank()) {
                taskOrchestrator.returnHome(homeWaypointId)
            } else {
                // If no home waypoint is set, just reset to Idle
                // This case should ideally not happen if a default home waypoint is always set
                taskOrchestrator.resetToIdle() // Assuming a resetToIdle function exists or can be added
            }
        }
    }

    private fun readAssetFile(fileName: String): String {
        return try {
            context.assets.open(fileName).bufferedReader().use { it.readText() }
        } catch (e: Exception) {
            e.printStackTrace()
            ""
        }
    }
}
