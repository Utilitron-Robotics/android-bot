package com.opendroids.tourbot.data.remote

import android.util.Log
import com.opendroids.tourbot.data.remote.model.RobotCommand
import com.opendroids.tourbot.data.remote.model.RobotMessage
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import okio.ByteString
import java.io.ByteArrayOutputStream
import java.util.concurrent.TimeUnit
import java.util.zip.Inflater
import javax.inject.Inject
import javax.inject.Singleton

private const val TAG = "RobotClient"

@Singleton
class RobotClient @Inject constructor() {

    private val client = OkHttpClient.Builder()
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .pingInterval(20, TimeUnit.SECONDS)
        .build()

    private var webSocket: WebSocket? = null
    private val json = Json { ignoreUnknownKeys = true }

    private val _messages = MutableSharedFlow<RobotMessage>()
    val messages: Flow<RobotMessage> = _messages.asSharedFlow()

    private val _isConnected = MutableStateFlow(false)
    val isConnected: StateFlow<Boolean> = _isConnected.asStateFlow()

    private var connectionResult = CompletableDeferred<Boolean>()

    suspend fun tryConnect(url: String): Boolean {
        if (isConnected.value) return true
        connectionResult = CompletableDeferred()
        val request = Request.Builder().url(url).build()
        webSocket = client.newWebSocket(request, createListener())

        // Wait for 5 seconds for the connection to establish or fail
        return withTimeoutOrNull(5000) {
            connectionResult.await()
        } ?: false
    }

    fun connect(url: String) {
        if (isConnected.value) return
        val request = Request.Builder().url(url).build()
        webSocket = client.newWebSocket(request, createListener())
    }

    fun disconnect() {
        webSocket?.close(1000, "Disconnect requested")
        webSocket = null
        _isConnected.value = false
    }

    fun sendCommand(command: RobotCommand) {
        if (webSocket == null) {
            Log.w(TAG, "Cannot send command, WebSocket is not connected.")
            return
        }
        val jsonCommand = json.encodeToString(command)
        Log.d(TAG, "→ Sending: $jsonCommand")
        webSocket?.send(jsonCommand)
    }

    private fun createListener(): WebSocketListener {
        return object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                Log.i(TAG, "✓ Connected to robot")
                _isConnected.value = true
                connectionResult.complete(true)
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                Log.v(TAG, "← Received: $text")
                try {
                    val message = json.decodeFromString<RobotMessage>(text)
                    CoroutineScope(Dispatchers.IO).launch {
                        _messages.emit(message)
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to parse message: $text", e)
                }
            }

            override fun onMessage(webSocket: WebSocket, bytes: ByteString) {
                Log.v(TAG, "← Received bytes: ${bytes.size}")
                try {
                    val decompressed = decompress(bytes.toByteArray())
                    val message = json.decodeFromString<RobotMessage>(decompressed)
                    CoroutineScope(Dispatchers.IO).launch {
                        _messages.emit(message)
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to parse byte message: ${bytes.hex()}", e)
                }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.e(TAG, "Connection failure", t)
                this@RobotClient.webSocket = null
                _isConnected.value = false
                connectionResult.complete(false)
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                Log.i(TAG, "Robot connection closing: $code / $reason")
                this@RobotClient.webSocket = null
                _isConnected.value = false
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                Log.i(TAG, "Robot connection closed: $code / $reason")
                this@RobotClient.webSocket = null
                _isConnected.value = false
            }
        }
    }

    private fun decompress(data: ByteArray): String {
        val inflater = Inflater()
        inflater.setInput(data)
        val outputStream = ByteArrayOutputStream()
        val buffer = ByteArray(1024)
        while (!inflater.finished()) {
            val count = inflater.inflate(buffer)
            outputStream.write(buffer, 0, count)
        }
        inflater.end()
        return outputStream.toString("UTF-8")
    }
}
