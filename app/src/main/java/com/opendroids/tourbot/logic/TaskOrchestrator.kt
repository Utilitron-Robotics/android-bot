package com.opendroids.tourbot.logic

import android.util.Log
import com.opendroids.tourbot.data.ErrorLogger
import com.opendroids.tourbot.logic.executors.*
import com.opendroids.tourbot.logic.tasks.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

private const val TAG = "TaskOrchestrator"

@Singleton
class TaskOrchestrator @Inject constructor(
    private val navigationExecutor: NavigationExecutor,
    private val speechExecutor: SpeechExecutor,
    private val playAudioExecutor: PlayAudioExecutor,
    private val delayExecutor: DelayExecutor,
    private val errorLogger: ErrorLogger
) {
    private var taskJob: Job? = null
    private val orchestratorScope = CoroutineScope(Dispatchers.Main)

    fun executeTasks(tasks: List<Task>) {
        if (taskJob?.isActive == true) {
            Log.w(TAG, "Cannot start new task list, another is already in progress.")
            return
        }

        taskJob = orchestratorScope.launch {
            Log.i(TAG, "Starting execution of ${tasks.size} tasks.")
            for (task in tasks) {
                val success = executeTask(task)
                if (!success) {
                    val errorMessage = "Failed to execute task: ${task.id}. Aborting task list."
                    Log.e(TAG, errorMessage)
                    errorLogger.logError(errorMessage)
                    break // Stop executing the list of tasks
                }
            }
            Log.i(TAG, "Finished executing all tasks.")
        }
    }

    fun cancelTasks() {
        if (taskJob?.isActive == true) {
            Log.i(TAG, "Cancelling all tasks.")
            taskJob?.cancel()
        }
    }

    private suspend fun executeTask(task: Task): Boolean {
        return when (task) {
            is GoToTask -> navigationExecutor.execute(task)
            is SpeakTask -> speechExecutor.execute(task)
            is PlayAudioTask -> playAudioExecutor.execute(task)
            is DelayTask -> delayExecutor.execute(task)
        }
    }
}
