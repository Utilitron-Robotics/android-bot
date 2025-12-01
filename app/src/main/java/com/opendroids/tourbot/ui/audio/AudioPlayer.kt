package com.opendroids.tourbot.ui.audio

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.MediaPlayer
import android.media.audiofx.Visualizer
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import androidx.core.content.ContextCompat
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
import kotlin.math.abs
import kotlin.random.Random

private const val TAG = "AudioPlayer"
private const val DEFAULT_WPM = 150 // Words per minute for caption timing estimation

@Singleton
class AudioPlayer @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private var mediaPlayer: MediaPlayer? = null
    private var visualizer: Visualizer? = null
    private lateinit var tts: TextToSpeech
    private val ttsInitialized = CompletableDeferred<Boolean>()

    private val _amplitude = MutableStateFlow(0)
    val amplitude: StateFlow<Int> = _amplitude.asStateFlow()

    private val _captionText = MutableStateFlow("")
    val captionText: StateFlow<String> = _captionText.asStateFlow()

    private var amplitudeJob: Job? = null
    private var captionJob: Job? = null
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    // Check if we have audio recording permission for Visualizer
    private val hasRecordAudioPermission: Boolean
        get() = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED

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

            // Start real audio visualization if we have permission
            val audioSessionId = mediaPlayer?.audioSessionId ?: 0
            if (audioSessionId != 0 && hasRecordAudioPermission) {
                startVisualizerCapture(audioSessionId)
            } else {
                // Fallback to simulated amplitude if no permission
                startAmplitudePolling(isTts = false)
            }

            // Start progressive caption display if caption text is provided
            if (caption.isNotBlank()) {
                val duration = mediaPlayer?.duration ?: 0
                startProgressiveCaptions(caption, duration)
            }

        } catch (e: Exception) {
            Log.e(TAG, "Error initializing playback", e)
            stop()
            if (cont.context.isActive) cont.resume(Unit)
        }
    }

    /**
     * Display captions progressively word-by-word, synchronized with audio duration.
     * Words are displayed at a rate that matches the audio playback.
     */
    private fun startProgressiveCaptions(fullText: String, audioDurationMs: Int) {
        captionJob?.cancel()

        val words = fullText.split(Regex("\\s+")).filter { it.isNotBlank() }
        if (words.isEmpty()) {
            _captionText.value = fullText
            return
        }

        // Calculate time per word based on audio duration
        // Use audio duration if available, otherwise estimate based on WPM
        val totalDurationMs = if (audioDurationMs > 0) {
            audioDurationMs.toLong()
        } else {
            // Estimate: words / WPM * 60 * 1000
            (words.size.toFloat() / DEFAULT_WPM * 60 * 1000).toLong()
        }

        val msPerWord = (totalDurationMs / words.size).coerceAtLeast(100L)

        captionJob = scope.launch {
            var displayedText = StringBuilder()
            for ((index, word) in words.withIndex()) {
                if (!isActive) break

                // Build up the displayed text progressively
                if (displayedText.isNotEmpty()) {
                    displayedText.append(" ")
                }
                displayedText.append(word)

                // Show recent words (last ~10 words to keep captions readable)
                val recentWords = words.subList(
                    maxOf(0, index - 9),
                    index + 1
                ).joinToString(" ")

                _captionText.value = recentWords
                delay(msPerWord)
            }

            // Keep final caption visible briefly
            delay(500)
            if (isActive) {
                _captionText.value = ""
            }
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
                    // For TTS, we don't have a media player audio session ID directly.
                    // We'll rely on the simulated amplitude for TTS for now.
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
        stopCaptions()

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

    private fun stopCaptions() {
        captionJob?.cancel()
        captionJob = null
    }

    /**
     * Start capturing real audio amplitude using Android's Visualizer API.
     * This provides actual waveform data for accurate lip sync.
     */
    private fun startVisualizerCapture(audioSessionId: Int) {
        releaseVisualizer()

        try {
            visualizer = Visualizer(audioSessionId).apply {
                captureSize = Visualizer.getCaptureSizeRange()[0] // Minimum size for efficiency
                setDataCaptureListener(
                    object : Visualizer.OnDataCaptureListener {
                        override fun onWaveFormDataCapture(
                            visualizer: Visualizer?,
                            waveform: ByteArray?,
                            samplingRate: Int
                        ) {
                            waveform?.let { data ->
                                // Calculate RMS amplitude from waveform
                                var sum = 0L
                                for (byte in data) {
                                    // Convert unsigned byte to signed (-128 to 127) then to absolute
                                    val sample = (byte.toInt() and 0xFF) - 128
                                    sum += sample * sample // Corrected line
                                }
                                val rms = kotlin.math.sqrt(sum.toDouble() / data.size)
                                // Scale to 0-15000 range for compatibility with existing code
                                val scaledAmplitude = (rms * 100).toInt().coerceIn(0, 15000)
                                _amplitude.value = scaledAmplitude
                            }
                        }

                        override fun onFftDataCapture(
                            visualizer: Visualizer?,
                            fft: ByteArray?,
                            samplingRate: Int
                        ) {
                            // We use waveform, not FFT
                        }
                    },
                    Visualizer.getMaxCaptureRate() / 2, // Capture rate
                    true,  // Enable waveform capture
                    false  // Disable FFT capture
                )
                enabled = true
            }
            Log.d(TAG, "Visualizer started for audio session $audioSessionId")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create Visualizer, falling back to simulated amplitude", e)
            releaseVisualizer()
            startAmplitudePolling(isTts = false)
        }
    }

    private fun releaseVisualizer() {
        try {
            visualizer?.enabled = false
            visualizer?.release()
        } catch (e: Exception) {
            Log.w(TAG, "Error releasing visualizer", e)
        }
        visualizer = null
    }

    private fun startAmplitudePolling(isTts: Boolean) {
        amplitudeJob?.cancel()
        amplitudeJob = scope.launch {
            while (isActive) {
                val currentAmplitude = if (isTts) {
                    // For TTS, generate random amplitude that varies naturally
                    Random.nextInt(500, 2000)
                } else {
                    // Fallback when Visualizer isn't available
                    Random.nextInt(800, 1500)
                }
                _amplitude.value = currentAmplitude
                delay(50) // Poll every 50ms
            }
        }
    }

    private fun stopAmplitudePolling() {
        amplitudeJob?.cancel()
        amplitudeJob = null
        releaseVisualizer()
        _amplitude.value = 0
    }

    fun release() {
        stopCaptions()
        stopAmplitudePolling()
        if (::tts.isInitialized) {
            tts.stop()
            tts.shutdown()
        }
        scope.cancel() // Cancel coroutine scope
        mediaPlayer?.release()
        mediaPlayer = null
    }
}
