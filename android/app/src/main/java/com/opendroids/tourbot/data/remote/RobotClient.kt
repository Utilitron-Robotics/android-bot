package com.opendroids.tourbot.data.remote

import android.util.Log
import com.opendroids.tourbot.data.remote.model.RobotCommand
import com.opendroids.tourbot.data.remote.model.RobotMessage
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.shareIn
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

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

    fun connect(url: String) {
        if (webSocket != null) return
        
        val request = Request.Builder().url(url).build()
        webSocket = client.newWebSocket(request, createListener())
    }

    fun disconnect() {
        webSocket?.close(1000, "Disconnect requested")
        webSocket = null
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
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                Log.v(TAG, "← Received: $text")
                try {
                    val message = json.decodeFromString<RobotMessage>(text)
                    // Use a coroutine to emit the message on the shared flow
                    CoroutineScope(Dispatchers.IO).launch {
                        _messages.emit(message)
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to parse message: $text", e)
                }
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                Log.e(TAG, "Connection failure", t)
                this@RobotClient.webSocket = null // Corrected: refer to class member
            }
            
            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                Log.i(TAG, "Robot connection closing: $code / $reason")
                this@RobotClient.webSocket = null // Corrected: refer to class member
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                Log.i(TAG, "Robot connection closed: $code / $reason")
                this@RobotClient.webSocket = null
            }
        }
    }
}
