package com.smait.robotrelay.service

import android.util.Log
import com.smait.robotrelay.protocol.SmaitProtocol
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import okhttp3.*
import java.util.concurrent.TimeUnit

/**
 * WebSocket client for connecting to the robot base
 * Default robot IP: 10.42.0.1:9090 (direct WiFi)
 */
class RobotWebSocketClient(
    private val robotIp: String = "10.42.0.1",
    private val robotPort: Int = 9090
) {
    companion object {
        private const val TAG = "RobotWSClient"
        private const val RECONNECT_DELAY_MS = 3000L
    }

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var webSocket: WebSocket? = null
    private var isConnecting = false

    private val _connectionState = MutableStateFlow(ConnectionState.DISCONNECTED)
    val connectionState: StateFlow<ConnectionState> = _connectionState

    private val _incomingMessages = MutableSharedFlow<String>(extraBufferCapacity = 100)
    val incomingMessages: SharedFlow<String> = _incomingMessages

    private val _robotStatus = MutableStateFlow<RobotStatusData?>(null)
    val robotStatus: StateFlow<RobotStatusData?> = _robotStatus

    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.SECONDS) // No timeout for WebSocket
        .writeTimeout(10, TimeUnit.SECONDS)
        .pingInterval(30, TimeUnit.SECONDS)
        .build()

    private val listener = object : WebSocketListener() {
        override fun onOpen(webSocket: WebSocket, response: Response) {
            Log.i(TAG, "Connected to robot at $robotIp:$robotPort")
            _connectionState.value = ConnectionState.CONNECTED
            isConnecting = false

            // Subscribe to essential topics
            scope.launch {
                delay(500)
                setupSubscriptions()
            }
        }

        override fun onMessage(webSocket: WebSocket, text: String) {
            Log.d(TAG, "Received: ${text.take(200)}...")
            scope.launch {
                _incomingMessages.emit(text)
                parseStatusUpdate(text)
            }
        }

        override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
            Log.i(TAG, "Connection closing: $code - $reason")
            webSocket.close(1000, null)
        }

        override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
            Log.i(TAG, "Connection closed: $code - $reason")
            _connectionState.value = ConnectionState.DISCONNECTED
            scheduleReconnect()
        }

        override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
            Log.e(TAG, "Connection failed: ${t.message}")
            _connectionState.value = ConnectionState.ERROR
            isConnecting = false
            scheduleReconnect()
        }
    }

    fun connect() {
        if (isConnecting || _connectionState.value == ConnectionState.CONNECTED) {
            Log.d(TAG, "Already connected or connecting")
            return
        }

        isConnecting = true
        _connectionState.value = ConnectionState.CONNECTING

        val url = "ws://$robotIp:$robotPort"
        Log.i(TAG, "Connecting to $url")

        val request = Request.Builder()
            .url(url)
            .build()

        webSocket = client.newWebSocket(request, listener)
    }

    fun disconnect() {
        webSocket?.close(1000, "Client disconnect")
        webSocket = null
        _connectionState.value = ConnectionState.DISCONNECTED
    }

    fun send(message: String): Boolean {
        return webSocket?.send(message) ?: false.also {
            Log.w(TAG, "Cannot send - not connected")
        }
    }

    private fun setupSubscriptions() {
        // Advertise velocity control
        send(SmaitProtocol.advertiseVelocity())
        send(SmaitProtocol.advertiseCancelGoal())
        send(SmaitProtocol.advertiseSoftStop())

        // Subscribe to status updates
        send(SmaitProtocol.subscribeRobotStatus())
        send(SmaitProtocol.subscribeRobotPose())
        send(SmaitProtocol.subscribeNaviStatus())
    }

    private fun parseStatusUpdate(json: String) {
        try {
            val obj = com.google.gson.JsonParser.parseString(json).asJsonObject
            val topic = obj.get("topic")?.asString ?: return
            val msg = obj.get("msg")?.asJsonObject ?: return

            when (topic) {
                SmaitProtocol.TOPIC_ROBOT_STATUS -> {
                    _robotStatus.value = RobotStatusData(
                        battery = msg.get("battery")?.asInt ?: 0,
                        charger = msg.get("charger")?.asInt ?: 0,
                        navStatus = msg.get("nav_status")?.asInt ?: 0,
                        controlState = msg.get("control_state")?.asInt ?: 0,
                        softEstop = msg.get("soft_estop")?.asBoolean ?: false,
                        hardEstop = msg.get("hard_estop")?.asBoolean ?: false,
                        velocity = msg.get("velocity")?.asJsonArray?.map { it.asDouble } ?: listOf(0.0, 0.0)
                    )
                }
                SmaitProtocol.TOPIC_ROBOT_POSE -> {
                    val current = _robotStatus.value ?: RobotStatusData()
                    _robotStatus.value = current.copy(
                        x = msg.get("x")?.asDouble ?: 0.0,
                        y = msg.get("y")?.asDouble ?: 0.0,
                        theta = msg.get("theta")?.asDouble ?: 0.0
                    )
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse status: ${e.message}")
        }
    }

    private fun scheduleReconnect() {
        scope.launch {
            delay(RECONNECT_DELAY_MS)
            if (_connectionState.value != ConnectionState.CONNECTED) {
                Log.i(TAG, "Attempting reconnect...")
                connect()
            }
        }
    }

    fun destroy() {
        disconnect()
        scope.cancel()
    }

    // === Control Methods ===

    fun sendVelocity(linearX: Double, angularZ: Double) {
        send(SmaitProtocol.publishVelocity(linearX, angularZ))
    }

    fun stop() {
        send(SmaitProtocol.stopRobot())
    }

    fun cancelNavigation() {
        send(SmaitProtocol.publishCancelGoal())
    }

    fun setSoftStop(enabled: Boolean) {
        send(SmaitProtocol.publishSoftStop(enabled))
    }

    fun navigateToPoi(poiName: String) {
        send(SmaitProtocol.callNavigateToPoi(poiName))
    }

    fun setSpeedMode(mode: Int) {
        send(SmaitProtocol.callSetSpeedMode(mode))
    }
}

enum class ConnectionState {
    DISCONNECTED,
    CONNECTING,
    CONNECTED,
    ERROR
}

data class RobotStatusData(
    val battery: Int = 0,
    val charger: Int = 0,
    val navStatus: Int = 0,
    val controlState: Int = 0,
    val softEstop: Boolean = false,
    val hardEstop: Boolean = false,
    val velocity: List<Double> = listOf(0.0, 0.0),
    val x: Double = 0.0,
    val y: Double = 0.0,
    val theta: Double = 0.0
)
