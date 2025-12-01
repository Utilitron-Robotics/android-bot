package com.opendroids.tourbot.logic.executors

import android.util.Log
import com.opendroids.tourbot.ui.audio.AudioPlayer
import javax.inject.Inject
import javax.inject.Singleton

private const val TAG = "SpeechExecutor"

@Singleton
class SpeechExecutor @Inject constructor(
    private val audioPlayer: AudioPlayer
) {
    suspend fun execute(text: String): Boolean {
        Log.i(TAG, "Executing speech: \"$text\"")
        audioPlayer.speak(text)
        return true
    }
}
