package com.opendroids.tourbot.logic.executors

import android.util.Log
import com.opendroids.tourbot.logic.tasks.PlayAudioTask
import com.opendroids.tourbot.ui.audio.AudioPlayer
import javax.inject.Inject

private const val TAG = "PlayAudioExecutor"

class PlayAudioExecutor @Inject constructor(
    private val audioPlayer: AudioPlayer
) : TaskExecutor<PlayAudioTask> {

    override suspend fun execute(task: PlayAudioTask): Boolean {
        Log.i(TAG, "Executing PlayAudioTask for resource: ${task.resourceId}")
        audioPlayer.play(task.resourceId, "")
        // Similar to speak, we assume play is a suspend function.
        return true
    }
}
