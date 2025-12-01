package com.opendroids.tourbot.logic.executors

import android.util.Log
import com.opendroids.tourbot.data.TourRepository
import com.opendroids.tourbot.logic.tasks.GoToTask
import javax.inject.Inject

private const val TAG = "NavigationExecutor"

class NavigationExecutor @Inject constructor(
    private val tourRepository: TourRepository
) : TaskExecutor<GoToTask> {

    override suspend fun execute(task: GoToTask): Boolean {
        Log.i(TAG, "Executing GoToTask for waypoint: ${task.waypointId}")
        // For now, we'll just use the existing navigateToWaypointWithRetry logic.
        // This can be further refactored later.
        return tourRepository.goTo(task.waypointId)
    }
}
