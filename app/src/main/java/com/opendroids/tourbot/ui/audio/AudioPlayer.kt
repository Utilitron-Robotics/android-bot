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
    private val ttsInitialized = CompletableDeferred<Boolean>()

    private val _amplitude = MutableStateFlow(0)
    val amplitude: StateFlow<Int> = _amplitude.asStateFlow()

    private val _captionText = MutableStateFlow("")
    val captionText: StateFlow<String> = _captionText.asStateFlow()

    private var amplitudeJob: Job? = null
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    init {
        tts = TextToSpeech(context) { status ->
            if (status == TextToSpeech.SUCCESS) {
                val result = tts.setLanguage(Locale.US)
                if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
                    Log.e(TAG, "TTS Language not supported")
                    ttsInitialized.complete(false)
                } else {
                    Log.i(TAG, "TTS Initialized successfully")
                    ttsInitialized.complete(true)
                }
            } else {
                Log.e(TAG, "TTS Initialization failed")
                ttsInitialized.complete(false)
            }
        }
    }

    suspend fun play(resourceId: Int, caption: String = "") = suspendCoroutine<Unit> { cont ->
        stop(releaseMedia = true) // Stop any existing playback
        _captionText.value = caption // Set caption text

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
                if (cont.context.isActive) cont.resume(Unit)
            }
            
            mediaPlayer?.setOnErrorListener { _, what, extra ->
                Log.e(TAG, "MediaPlayer error: what=$what, extra=$extra")
                stop()
                if (cont.context.isActive) cont.resume(Unit)
                true
            }

            mediaPlayer?.start()
            startAmplitudePolling(isTts = false) // Start polling for MediaPlayer amplitude

        } catch (e: Exception) {
            Log.e(TAG, "Error initializing playback", e)
            stop()
            if (cont.context.isActive) cont.resume(Unit)
        }
    }

    suspend fun speak(text: String) {
        if (!ttsInitialized.await()) {
            Log.e(TAG, "TTS not initialized or failed to initialize, cannot speak.")
            return
        }
        
        stop(releaseTts = true)

        return suspendCoroutine { cont ->
            val utteranceId = UUID.randomUUID().toString()
            val params = Bundle()
            params.putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, utteranceId)

            tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {
                    Log.d(TAG, "TTS Start: $utteranceId")
                    startAmplitudePolling(isTts = true)
                }

                override fun onDone(utteranceId: String?) {
                    Log.d(TAG, "TTS Done: $utteranceId")
                    stopAmplitudePolling()
                    _captionText.value = ""
                    if (cont.context.isActive) cont.resume(Unit)
                }

                override fun onError(utteranceId: String?) {
                    Log.e(TAG, "TTS Error: $utteranceId")
                    stopAmplitudePolling()
                    _captionText.value = ""
                    if (cont.context.isActive) cont.resume(Unit)
                }

                override fun onStop(utteranceId: String?, interrupted: Boolean) {
                    Log.d(TAG, "TTS Stop: $utteranceId, interrupted: $interrupted")
                    stopAmplitudePolling()
                    _captionText.value = ""
                    if (interrupted && cont.context.isActive) {
                        cont.resume(Unit)
                    }
                }

                override fun onRangeStart(utteranceId: String?, start: Int, end: Int, frame: Int) {
                    if (start < end && end <= text.length) {
                        _captionText.value = text.substring(start, end)
                    }
                }
            })

            val result = tts.speak(text, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
            if (result == TextToSpeech.ERROR) {
                Log.e(TAG, "Error queuing text for TTS: $text")
                stopAmplitudePolling()
                _captionText.value = ""
                if (cont.context.isActive) cont.resume(Unit)
            }
        }
    }


    fun stop(releaseMedia: Boolean = true, releaseTts: Boolean = true) {
        stopAmplitudePolling()
        if (releaseTts && ::tts.isInitialized && tts.isSpeaking) {
            tts.stop()
        }

        if (releaseMedia) {
            try {
                mediaPlayer?.stop()
            } catch (e: Exception) {
                Log.e(TAG, "Error stopping media player", e)
            } finally {
                mediaPlayer?.release()
                mediaPlayer = null
            }
        }
        _captionText.value = ""
    }

    private fun startAmplitudePolling(isTts: Boolean) {
        amplitudeJob?.cancel()
        amplitudeJob = scope.launch {
            while (isActive) {
                val currentAmplitude = if (isTts) {
                    Random.nextInt(500, 2000)
                } else {
                    1000 // Placeholder for MediaPlayer amplitude
                }
                _amplitude.value = currentAmplitude
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
        if (::tts.isInitialized) {
            tts.stop()
            tts.shutdown()
        }
        scope.cancel() // Cancel coroutine scope for amplitude polling
        mediaPlayer?.release() // Ensure media player is also released
        mediaPlayer = null
    }
}
