package com.opendroids.tourbot.logic

import android.content.Context
import android.util.Log
import com.opendroids.tourbot.data.ErrorLogger
import com.opendroids.tourbot.data.TourConfigRepository
import com.opendroids.tourbot.data.model.TourState
import com.opendroids.tourbot.data.model.Waypoint
import com.opendroids.tourbot.logic.executors.DelayExecutor
import com.opendroids.tourbot.logic.executors.WaypointTaskExecutor
import com.opendroids.tourbot.logic.tasks.DelayTask
import com.opendroids.tourbot.logic.tasks.Task
import com.opendroids.tourbot.logic.tasks.WaypointTask
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.io.IOException
import javax.inject.Inject
import javax.inject.Singleton

private const val TAG = "TaskOrchestrator"

@Singleton
class TaskOrchestrator @Inject constructor(
    @ApplicationContext private val context: Context,
    private val waypointTaskExecutor: WaypointTaskExecutor,
    private val delayExecutor: DelayExecutor,
    private val errorLogger: ErrorLogger,
    private val tourConfigRepository: TourConfigRepository
) {
    private var taskJob: Job? = null
    private val orchestratorScope = CoroutineScope(Dispatchers.Main)

    private val _tourState = MutableStateFlow<TourState>(TourState.Idle)
    val tourState: StateFlow<TourState> = _tourState.asStateFlow()

    fun executeTasks(tasks: List<Task>) {
        if (taskJob?.isActive == true) {
            Log.w(TAG, "Cannot start new task list, another is already in progress.")
            return
        }

        taskJob = orchestratorScope.launch {
            Log.i(TAG, "Starting execution of ${tasks.size} tasks.")
            val firstTask = tasks.first()
            if (firstTask is WaypointTask) {
                val waypoint = createWaypoint(firstTask.waypointId)
                if (waypoint != null) {
                    _tourState.value = TourState.Navigating(waypoint)
                } else {
                    val errorMessage = "Failed to create waypoint for id: ${firstTask.waypointId}"
                    Log.e(TAG, errorMessage)
                    errorLogger.logError(errorMessage)
                    _tourState.value = TourState.Error(errorMessage)
                    return@launch
                }
            }
            
            for (task in tasks) {
                val success = executeTask(task)
                if (!success) {
                    val errorMessage = "Failed to execute task: ${task.id}. Aborting task list."
                    Log.e(TAG, errorMessage)
                    errorLogger.logError(errorMessage)
                    _tourState.value = TourState.Error(errorMessage)
                    break 
                }
            }
            if (taskJob?.isCancelled == false) {
                _tourState.value = TourState.Completed
            }
            Log.i(TAG, "Finished executing all tasks.")
        }
    }

    fun cancelTasks() {
        if (taskJob?.isActive == true) {
            Log.i(TAG, "Cancelling all tasks.")
            taskJob?.cancel()
            _tourState.value = TourState.Aborted
        }
    }

    suspend fun returnHome(homeWaypointId: String) {
        if (taskJob?.isActive == true) {
            Log.w(TAG, "Cannot return home, a tour is currently active. Aborting current tour first.")
            cancelTasks()
        }

        taskJob = orchestratorScope.launch {
            val homeWaypoint = createWaypoint(homeWaypointId)
            if (homeWaypoint == null) {
                val errorMessage = "Failed to create home waypoint for id: $homeWaypointId"
                Log.e(TAG, errorMessage)
                errorLogger.logError(errorMessage)
                _tourState.value = TourState.Error(errorMessage)
                return@launch
            }

            _tourState.value = TourState.ReturningHome(homeWaypoint)
            Log.i(TAG, "Returning to home waypoint: $homeWaypointId")

            val homeWaypointTask = WaypointTask(homeWaypointId, tourConfigRepository.getScript(homeWaypointId))
            val success = executeTask(homeWaypointTask)

            if (success) {
                _tourState.value = TourState.Idle
                Log.i(TAG, "Successfully returned home.")
            } else {
                val errorMessage = "Failed to return to home waypoint: $homeWaypointId"
                Log.e(TAG, errorMessage)
                errorLogger.logError(errorMessage)
                _tourState.value = TourState.Error(errorMessage)
            }
        }
    }

    fun resetToIdle() {
        taskJob?.cancel() // Ensure any active task is cancelled
        _tourState.value = TourState.Idle
        Log.i(TAG, "Tour state reset to Idle.")
    }

    private suspend fun executeTask(task: Task): Boolean {
        return when (task) {
            is WaypointTask -> {
                val waypoint = createWaypoint(task.waypointId)
                if (waypoint != null) {
                    _tourState.value = TourState.Navigating(waypoint)
                    val navSuccess = waypointTaskExecutor.execute(task)
                    if (navSuccess) {
                        _tourState.value = TourState.Speaking(waypoint)
                    }
                    navSuccess
                } else {
                    false
                }
            }
            is DelayTask -> delayExecutor.execute(task)
            else -> {
                val errorMessage = "Unknown task type: ${task::class.java.simpleName}"
                Log.e(TAG, errorMessage)
                errorLogger.logError(errorMessage)
                false
            }
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
            val errorMessage = "Error loading assets for waypoint $id"
            Log.e(TAG, "❌ $errorMessage", e)
            errorLogger.logError(errorMessage, e)
            null
        }
    }
}
