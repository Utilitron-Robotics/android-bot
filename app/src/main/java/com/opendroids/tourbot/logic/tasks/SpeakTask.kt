package com.opendroids.tourbot.logic.tasks

/**
 * A task to make the robot speak a given text string using Text-to-Speech (TTS).
 *
 * @param text The text for the robot to speak.
 */
data class SpeakTask(val text: String) : Task {
    override val id: String = "Speak_${text.take(20)}"
}
