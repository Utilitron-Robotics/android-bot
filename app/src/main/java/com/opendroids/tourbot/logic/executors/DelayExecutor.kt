package com.opendroids.tourbot.logic.executors

import android.util.Log
import com.opendroids.tourbot.logic.tasks.DelayTask
import kotlinx.coroutines.delay
import javax.inject.Inject

private const val TAG = "DelayExecutor"

class DelayExecutor @Inject constructor() : TaskExecutor<DelayTask> {

    override suspend fun execute(task: DelayTask): Boolean {
        Log.i(TAG, "Executing DelayTask for ${task.durationMs}ms")
        delay(task.durationMs)
        return true
    }
}
