package com.opendroids.tourbot.logic.tasks

sealed interface Task {
    val id: String
}

data class WaypointTask(
    val waypointId: String,
    val script: String
) : Task {
    override val id: String = "WaypointTask_$waypointId"
}

data class DelayTask(val durationMs: Long) : Task {
    override val id: String = "Delay_$durationMs"
}
