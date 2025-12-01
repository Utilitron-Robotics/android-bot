package com.opendroids.tourbot.logic.tasks

/**
 * Represents a single, discrete action the robot can perform.
 * A "tour" or any other robot routine is simply a list of these tasks.
 */
sealed interface Task {
    /** A unique identifier for this specific task instance. */
    val id: String
}

/**
 * A task to navigate the robot to a specific, named waypoint (POI).
 *
 * @param waypointId The name of the Point of Interest to navigate to.
 */
data class GoToTask(val waypointId: String) : Task {
    override val id: String = "GoTo_$waypointId"
}

/**
 * A task to make the robot speak a given text string using Text-to-Speech (TTS).
 *
 * @param text The text for the robot to speak.
 */
data class SpeakTask(val text: String) : Task {
    override val id: String = "Speak_${text.take(20)}"
}

/**
 * A task to play a pre-recorded audio file from the application's resources.
 *
 * @param resourceId The resource ID of the audio file (e.g., R.raw.intro).
 */
data class PlayAudioTask(val resourceId: Int) : Task {
    override val id: String = "PlayAudio_$resourceId"
}

/**
 * A task that does nothing for a specified duration. Useful for creating pauses.
 *
 * @param durationMs The delay duration in milliseconds.
 */
data class DelayTask(val durationMs: Long) : Task {
    override val id: String = "Delay_$durationMs"
}
