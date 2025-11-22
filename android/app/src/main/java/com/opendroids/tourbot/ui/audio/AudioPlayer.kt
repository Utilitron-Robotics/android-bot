package com.opendroids.tourbot.ui.audio

import android.content.Context
import android.media.MediaPlayer
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.Locale
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine
import kotlin.random.Random

private const val TAG = "AudioPlayer"

@Singleton
class AudioPlayer @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private var mediaPlayer: MediaPlayer? = null
    private lateinit var tts: TextToSpeech
    
    private val _amplitude = MutableStateFlow(0)
    val amplitude: StateFlow<Int> = _amplitude.asStateFlow()

    private val _captionText = MutableStateFlow("")
    val captionText: StateFlow<String> = _captionText.asStateFlow()

    private var amplitudeJob: Job? = null
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob()) // Changed to Dispatchers.Default

    init {
        tts = TextToSpeech(context) { status ->
            if (status == TextToSpeech.SUCCESS) {
                val result = tts.setLanguage(Locale.US)
                if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
                    Log.e(TAG, "TTS Language not supported")
                } else {
                    Log.i(TAG, "TTS Initialized successfully")
                }
            } else {
                Log.e(TAG, "TTS Initialization failed")
            }
        }
    }

    suspend fun play(resourceId: Int) = suspendCoroutine<Unit> { cont ->
        stop() // Stop any existing playback to be safe

        try {
            if (resourceId == 0) {
                Log.e(TAG, "Invalid resource ID")
                cont.resume(Unit)
                return@suspendCoroutine
            }

            mediaPlayer = MediaPlayer.create(context, resourceId)
            if (mediaPlayer == null) {
                Log.e(TAG, "Failed to create MediaPlayer for resource: $resourceId")
                cont.resume(Unit)
                return@suspendCoroutine
            }

            mediaPlayer?.setOnCompletionListener {
                stop()
                cont.resume(Unit)
            }
            
            mediaPlayer?.setOnErrorListener { _, what, extra ->
                Log.e(TAG, "MediaPlayer error: what=$what, extra=$extra")
                stop()
                cont.resume(Unit)
                true
            }

            mediaPlayer?.start()
            startAmplitudePolling() // Start polling for MediaPlayer amplitude

        } catch (e: Exception) {
            Log.e(TAG, "Error initializing playback", e)
            stop()
            cont.resume(Unit)
        }
    }

    suspend fun speak(text: String) {
        // Corrected: Perform suspend calls before entering the suspendCoroutine block
        if (::tts.isInitialized) {
            delay(100) // Small warm-up delay
        }

        return suspendCoroutine { cont ->
            if (::tts.isInitialized) {
                if (tts.isSpeaking) {
                    tts.stop() // Stop current speech if any
                }
                stopAmplitudePolling() // Stop any existing amplitude polling

                val utteranceId = UUID.randomUUID().toString()
                val params = Bundle()
                params.putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, utteranceId)

                tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) {
                        Log.d(TAG, "TTS Start: $utteranceId")
                        // Start amplitude simulation
                        amplitudeJob = scope.launch {
                            while (isActive) {
                                _amplitude.value = Random.nextInt(500, 2000) // Random amplitude for mouth movement
                                delay(50)
                            }
                        }
                    }

                    override fun onDone(utteranceId: String?) {
                        Log.d(TAG, "TTS Done: $utteranceId")
                        stopAmplitudePolling() // Stop amplitude simulation
                        _captionText.value = "" // Clear caption
                        cont.resume(Unit)
                    }

                    override fun onError(utteranceId: String?) {
                        Log.e(TAG, "TTS Error: $utteranceId")
                        stopAmplitudePolling() // Stop amplitude simulation
                        _captionText.value = "" // Clear caption
                        cont.resume(Unit) // Resume even on error to unblock coroutine
                    }

                    override fun onStop(utteranceId: String?, interrupted: Boolean) {
                        Log.d(TAG, "TTS Stop: $utteranceId, interrupted: $interrupted")
                        stopAmplitudePolling() // Stop amplitude simulation
                        _captionText.value = "" // Clear caption
                        if (interrupted && cont.context.isActive) {
                            cont.resume(Unit) // Resume if interrupted
                        }
                    }

                    override fun onRangeStart(utteranceId: String?, start: Int, end: Int, frame: Int) {
                        // Update caption with the current word/segment
                        _captionText.value = text.substring(start, end)
                    }
                })

                val result = tts.speak(text, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
                if (result == TextToSpeech.ERROR) {
                    Log.e(TAG, "Error speaking text: $text")
                    stopAmplitudePolling()
                    _captionText.value = ""
                    cont.resume(Unit)
                }
            } else {
                Log.e(TAG, "TTS not initialized, cannot speak.")
                cont.resume(Unit)
            }
        }
    }

    fun stop() {
        stopAmplitudePolling() // Stop any active amplitude polling
        try {
            if (mediaPlayer?.isPlaying == true) {
                mediaPlayer?.stop()
            }
        } catch (e: Exception) {
             Log.e(TAG, "Error stopping audio", e)
        } finally {
            mediaPlayer?.release()
            mediaPlayer = null
            _amplitude.value = 0
        }
    }

    private fun startAmplitudePolling() {
        amplitudeJob?.cancel()
        amplitudeJob = scope.launch {
            while (isActive) {
                mediaPlayer?.let { mp ->
                    try {
                        if (mp.isPlaying) {
                            // Re-implementing workaround for maxAmplitude()
                            val amp = 1000 // Placeholder value
                            _amplitude.value = amp
                        } else {
                            _amplitude.value = 0
                        }
                    } catch (e: Exception) {
                        _amplitude.value = 0
                    }
                } ?: run {
                    _amplitude.value = 0
                }
                delay(50) // Poll every 50ms
            }
        }
    }

    private fun stopAmplitudePolling() {
        amplitudeJob?.cancel()
        amplitudeJob = null
        _amplitude.value = 0
    }

    fun release() {
        tts.stop()
        tts.shutdown()
        scope.cancel() // Cancel coroutine scope for amplitude polling
        mediaPlayer?.release() // Ensure media player is also released
        mediaPlayer = null
    }
}
