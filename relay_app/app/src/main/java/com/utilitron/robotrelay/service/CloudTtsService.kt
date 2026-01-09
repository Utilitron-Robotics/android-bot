package com.utilitron.robotrelay.service

import android.content.Context
import android.media.MediaPlayer
import android.speech.tts.TextToSpeech
import android.util.Base64
import android.util.Log
import com.google.gson.Gson
import com.google.gson.annotations.SerializedName
import kotlinx.coroutines.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.*
import java.util.concurrent.TimeUnit

/**
 * Google Cloud Text-to-Speech service with caching and fallback
 *
 * Uses Google Cloud TTS API for high-quality neural voices,
 * with local caching and fallback to device TTS when offline.
 */
class CloudTtsService(
    private val context: Context,
    private val apiKey: String? = null
) {
    companion object {
        private const val TAG = "CloudTTS"
        private const val TTS_API_URL = "https://texttospeech.googleapis.com/v1/text:synthesize"
        private const val CACHE_DIR = "tts_cache"
        private const val MAX_CACHE_SIZE_MB = 50
        private const val MAX_CACHE_AGE_DAYS = 30

        // High-quality neural voices
        private const val DEFAULT_VOICE = "en-US-Neural2-J"  // Male, clear
        private const val FEMALE_VOICE = "en-US-Neural2-F"   // Female, friendly
    }

    private val gson = Gson()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    private var mediaPlayer: MediaPlayer? = null
    private var fallbackTts: TextToSpeech? = null
    private var fallbackReady = false
    private var currentCallback: (() -> Unit)? = null

    /** True when TTS is currently speaking */
    val isSpeaking: Boolean
        get() = currentCallback != null

    private val cacheDir: File by lazy {
        File(context.cacheDir, CACHE_DIR).apply { mkdirs() }
    }

    // Request/Response models for Google Cloud TTS API
    data class TtsRequest(
        val input: TtsInput,
        val voice: VoiceSelection,
        val audioConfig: AudioConfig
    )

    data class TtsInput(val text: String)

    data class VoiceSelection(
        val languageCode: String = "en-US",
        val name: String = DEFAULT_VOICE
    )

    data class AudioConfig(
        val audioEncoding: String = "MP3",
        val speakingRate: Double = 1.0,
        val pitch: Double = 0.0,
        val volumeGainDb: Double = 0.0
    )

    data class TtsResponse(
        @SerializedName("audioContent")
        val audioContent: String  // Base64 encoded audio
    )

    /**
     * Initialize the service - sets up fallback TTS
     */
    fun init() {
        // Initialize fallback TTS
        fallbackTts = TextToSpeech(context) { status ->
            if (status == TextToSpeech.SUCCESS) {
                fallbackTts?.language = Locale.US
                fallbackReady = true
                Log.i(TAG, "Fallback TTS initialized")
            } else {
                Log.e(TAG, "Fallback TTS init failed")
            }
        }

        // Clean old cache
        cleanCache()
    }

    /**
     * Speak text using Cloud TTS (with cache) or fallback to device TTS
     *
     * IMPORTANT: New speech interrupts any current speech. The previous callback
     * is invoked immediately (signaling completion/interruption) so callers
     * waiting on it can proceed. This prevents buffer hangs and ensures
     * warnings don't stack - they interrupt and replace.
     */
    fun speak(text: String, voice: String = DEFAULT_VOICE, onComplete: (() -> Unit)? = null) {
        Log.i(TAG, "speak: '$text' (apiKey=${if (apiKey != null) "set" else "none"})")

        // Stop current playback and invoke old callback (so buffer doesn't hang)
        val oldCallback = currentCallback
        currentCallback = null
        mediaPlayer?.stop()
        mediaPlayer?.release()
        mediaPlayer = null
        fallbackTts?.stop()
        oldCallback?.invoke()  // Signal previous speech is done (interrupted)

        currentCallback = onComplete

        // Try Cloud TTS if API key is set
        if (!apiKey.isNullOrEmpty()) {
            scope.launch {
                try {
                    val audioFile = getOrSynthesizeAudio(text, voice)
                    if (audioFile != null) {
                        playAudio(audioFile)
                        return@launch
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Cloud TTS failed: ${e.message}")
                }

                // Fallback to device TTS
                withContext(Dispatchers.Main) {
                    speakWithFallback(text)
                }
            }
        } else {
            // No API key - use device TTS directly
            speakWithFallback(text)
        }
    }

    /**
     * Get audio from cache or synthesize new
     */
    private suspend fun getOrSynthesizeAudio(text: String, voice: String): File? {
        val cacheKey = getCacheKey(text, voice)
        val cachedFile = File(cacheDir, "$cacheKey.mp3")

        // Check cache
        if (cachedFile.exists()) {
            Log.d(TAG, "Cache hit: $cacheKey")
            return cachedFile
        }

        // Synthesize new audio
        Log.d(TAG, "Cache miss, synthesizing: $cacheKey")
        return synthesizeAudio(text, voice, cachedFile)
    }

    /**
     * Call Google Cloud TTS API
     */
    private suspend fun synthesizeAudio(text: String, voice: String, outputFile: File): File? {
        val request = TtsRequest(
            input = TtsInput(text),
            voice = VoiceSelection(name = voice),
            audioConfig = AudioConfig()
        )

        val jsonBody = gson.toJson(request)
        val requestBody = jsonBody.toRequestBody("application/json".toMediaType())

        val httpRequest = Request.Builder()
            .url("$TTS_API_URL?key=$apiKey")
            .post(requestBody)
            .build()

        return withContext(Dispatchers.IO) {
            try {
                val response = client.newCall(httpRequest).execute()
                if (!response.isSuccessful) {
                    Log.e(TAG, "API error: ${response.code} - ${response.body?.string()}")
                    return@withContext null
                }

                val body = response.body?.string() ?: return@withContext null
                val ttsResponse = gson.fromJson(body, TtsResponse::class.java)

                // Decode base64 audio and save to file
                val audioBytes = Base64.decode(ttsResponse.audioContent, Base64.DEFAULT)
                FileOutputStream(outputFile).use { it.write(audioBytes) }

                Log.i(TAG, "Synthesized ${audioBytes.size} bytes -> ${outputFile.name}")
                outputFile
            } catch (e: Exception) {
                Log.e(TAG, "Synthesis error: ${e.message}")
                null
            }
        }
    }

    /**
     * Play audio file using MediaPlayer
     */
    private suspend fun playAudio(file: File) {
        withContext(Dispatchers.Main) {
            try {
                mediaPlayer?.release()
                mediaPlayer = MediaPlayer().apply {
                    setDataSource(file.absolutePath)
                    setOnCompletionListener {
                        currentCallback?.invoke()
                        currentCallback = null
                    }
                    setOnErrorListener { _, what, extra ->
                        Log.e(TAG, "MediaPlayer error: $what, $extra")
                        currentCallback?.invoke()
                        currentCallback = null
                        true
                    }
                    prepare()
                    start()
                }
                Log.i(TAG, "Playing: ${file.name}")
            } catch (e: Exception) {
                Log.e(TAG, "Playback error: ${e.message}")
                currentCallback?.invoke()
                currentCallback = null
            }
        }
    }

    /**
     * Fallback to device TTS
     */
    private fun speakWithFallback(text: String) {
        if (!fallbackReady || fallbackTts == null) {
            Log.e(TAG, "Fallback TTS not ready")
            currentCallback?.invoke()
            currentCallback = null
            return
        }

        val utteranceId = "cloud_tts_${System.currentTimeMillis()}"
        fallbackTts?.setOnUtteranceProgressListener(object : android.speech.tts.UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {}
            override fun onDone(utteranceId: String?) {
                currentCallback?.invoke()
                currentCallback = null
            }
            override fun onError(utteranceId: String?) {
                currentCallback?.invoke()
                currentCallback = null
            }
        })

        fallbackTts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, utteranceId)
        Log.i(TAG, "Using fallback TTS: $text")
    }

    /**
     * Stop current playback
     */
    fun stop() {
        mediaPlayer?.stop()
        mediaPlayer?.release()
        mediaPlayer = null
        fallbackTts?.stop()
        currentCallback?.invoke()
        currentCallback = null
    }

    /**
     * Pre-cache common phrases for instant playback
     */
    fun precache(phrases: List<String>) {
        if (apiKey.isNullOrEmpty()) return

        scope.launch {
            phrases.forEach { phrase ->
                try {
                    getOrSynthesizeAudio(phrase, DEFAULT_VOICE)
                    delay(500) // Rate limit
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to precache: $phrase")
                }
            }
            Log.i(TAG, "Precached ${phrases.size} phrases")
        }
    }

    /**
     * Generate cache key from text and voice
     */
    private fun getCacheKey(text: String, voice: String): String {
        val input = "$text|$voice"
        val digest = MessageDigest.getInstance("MD5").digest(input.toByteArray())
        return digest.joinToString("") { "%02x".format(it) }
    }

    /**
     * Clean old cache files
     */
    private fun cleanCache() {
        scope.launch {
            try {
                val now = System.currentTimeMillis()
                val maxAge = MAX_CACHE_AGE_DAYS * 24 * 60 * 60 * 1000L
                var totalSize = 0L

                val files = cacheDir.listFiles()?.sortedByDescending { it.lastModified() } ?: return@launch

                files.forEach { file ->
                    // Delete old files
                    if (now - file.lastModified() > maxAge) {
                        file.delete()
                        return@forEach
                    }

                    totalSize += file.length()

                    // Delete if over size limit
                    if (totalSize > MAX_CACHE_SIZE_MB * 1024 * 1024) {
                        file.delete()
                    }
                }

                Log.d(TAG, "Cache cleaned: ${totalSize / 1024}KB in ${files.size} files")
            } catch (e: Exception) {
                Log.w(TAG, "Cache clean error: ${e.message}")
            }
        }
    }

    fun destroy() {
        stop()
        fallbackTts?.shutdown()
        fallbackTts = null
        scope.cancel()
    }
}
