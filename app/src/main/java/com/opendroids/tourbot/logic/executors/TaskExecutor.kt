package com.opendroids.tourbot.logic.executors

import com.opendroids.tourbot.logic.tasks.Task

/**
 * A generic interface for a component that knows how to execute a specific type of [Task].
 * @param T The specific subtype of [Task] this executor can handle.
 */
interface TaskExecutor<T : Task> {
    /**
     * Executes the given task.
     * @return `true` if the task completed successfully, `false` otherwise.
     */
    suspend fun execute(task: T): Boolean
}
