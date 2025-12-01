package com.opendroids.tourbot.logic.executors

import android.util.Log
import com.opendroids.tourbot.logic.tasks.SpeakTask
import com.opendroids.tourbot.ui.audio.AudioPlayer
import javax.inject.Inject

private const val TAG = "SpeechExecutor"

class SpeechExecutor @Inject constructor(
    private val audioPlayer: AudioPlayer
) : TaskExecutor<SpeakTask> {

    override suspend fun execute(task: SpeakTask): Boolean {
        Log.i(TAG, "Executing SpeakTask: \"${task.text}\"")
        audioPlayer.speak(task.text)
        // Here we assume speak is a suspend function that completes when speech is done.
        // If it's not, we'll need to use a callback or other mechanism to await completion.
        return true
    }
}
