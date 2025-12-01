package com.opendroids.tourbot.logic.executors

import com.opendroids.tourbot.logic.tasks.WaypointTask
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class WaypointTaskExecutor @Inject constructor(
    private val navigationExecutor: NavigationExecutor,
    private val speechExecutor: SpeechExecutor
) : TaskExecutor<WaypointTask> {

    override suspend fun execute(task: WaypointTask): Boolean {
        val navSuccess = navigationExecutor.execute(task.waypointId)
        if (!navSuccess) {
            return false
        }
        return speechExecutor.execute(task.script)
    }
}
