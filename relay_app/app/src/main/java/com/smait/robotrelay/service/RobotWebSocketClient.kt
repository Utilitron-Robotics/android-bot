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
import java.util.concurrent.atomic.AtomicReference
import javax.net.SocketFactory

// Following the excellent logic from the Flutter app
enum class SafetyZone {
    CLEAR,
    WARN,
    CREEP,
    STOP
}

/**
 * WebSocket client for connecting to the robot base via USB/wired connection.
 * Uses a specific SocketFactory to bind to the wired network interface,
 * allowing WiFi to remain connected for internet access.
 */
class RobotWebSocketClient(
    val robotIp: String = "192.168.20.22",  // Wired IP, not WiFi hotspot
    private val robotPort: Int = 9090,
    private val socketFactory: SocketFactory? = null
) {
    companion object {
        private const val TAG = "RobotWSClient"
        private const val RECONNECT_DELAY_MS = 1000L  // Reduced from 3000ms for faster recovery

        // Zone constants from Flutter app
        private const val STOP_DISTANCE = 0.20f
        private const val CREEP_DISTANCE = 0.50f
        private const val WARN_DISTANCE = 0.80f
        private const val CREEP_SPEED = 0.05
    }

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var webSocket: WebSocket? = null
    private var isConnecting = false

    // --- State Management ---
    private val _connectionState = MutableStateFlow(ConnectionState.DISCONNECTED)
    val connectionState: StateFlow<ConnectionState> = _connectionState

    // Large buffer for message bursts - map messages are huge and frequent during nav
    private val _incomingMessages = MutableSharedFlow<String>(extraBufferCapacity = 500)
    val incomingMessages: SharedFlow<String> = _incomingMessages

    private val _robotStatus = MutableStateFlow<RobotStatusData?>(null)
    val robotStatus: StateFlow<RobotStatusData?> = _robotStatus

    private val safetyZone = AtomicReference(SafetyZone.CLEAR)

    // Build OkHttpClient with optional SocketFactory for network binding
    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.SECONDS) // No timeout for WebSocket
        .writeTimeout(10, TimeUnit.SECONDS)
        .pingInterval(30, TimeUnit.SECONDS)
        .apply {
            // Use specific SocketFactory to bind to USB/wired network interface
            socketFactory?.let { sf ->
                Log.i(TAG, "Using custom SocketFactory for USB/wired network binding")
                socketFactory(sf)
            }
        }
        .build()

    private val listener = object : WebSocketListener() {
        override fun onOpen(webSocket: WebSocket, response: Response) {
            Log.i(TAG, "Connected to robot at $robotIp:$robotPort")
            _connectionState.value = ConnectionState.CONNECTED
            isConnecting = false
            scope.launch {
                delay(500)
                setupSubscriptions()
            }
        }

        override fun onMessage(webSocket: WebSocket, text: String) {
            // Log map messages specially - they're huge and might be the issue
            val isMapMsg = text.contains("\"/map\"") || text.contains("\"topic\":\"/map\"")
            if (isMapMsg) {
                Log.i(TAG, ">>> RECEIVED /map message (${text.length} bytes)")
            } else {
                Log.d(TAG, text.take(200)) // Truncate other messages
            }

            // Use tryEmit (non-blocking) instead of emit (suspending)
            val emitted = _incomingMessages.tryEmit(text)
            if (!emitted) {
                Log.w(TAG, "Message buffer full, dropped: ${if (isMapMsg) "/map" else text.take(50)}")
            } else if (isMapMsg) {
                Log.i(TAG, ">>> /map message emitted to SharedFlow")
            }

            scope.launch {
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
            Log.e(TAG, "Connection failed to $robotIp:$robotPort")
            Log.e(TAG, "Error: ${t.message}", t)
            response?.let { Log.e(TAG, "Response: ${it.code} ${it.message}") }
            _connectionState.value = ConnectionState.ERROR
            isConnecting = false
            scheduleReconnect()
        }
    }

    fun connect() {
        if (isConnecting || _connectionState.value == ConnectionState.CONNECTED) return
        isConnecting = true
        _connectionState.value = ConnectionState.CONNECTING
        val url = "ws://$robotIp:$robotPort"
        Log.i(TAG, "Connecting to $url (socketFactory=${if (socketFactory != null) "custom" else "default"})")
        val request = Request.Builder().url(url).build()
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
        send(SmaitProtocol.advertiseVelocity())
        send(SmaitProtocol.advertiseCancelGoal())
        send(SmaitProtocol.advertiseSoftStop())
        send(SmaitProtocol.subscribeRobotStatus())
        send(SmaitProtocol.subscribeRobotPose())
        send(SmaitProtocol.subscribeNaviStatus())
        send(SmaitProtocol.subscribeSensorsCore())
        send(SmaitProtocol.subscribeLaserData())
        // Subscribe to /map so it's always flowing to Flutter clients
        // This ensures map works after Flutter hot restart
        val mapSubMsg = SmaitProtocol.subscribeMapSimple()
        val mapSent = send(mapSubMsg)
        Log.i(TAG, ">>> Sending /map subscription: $mapSubMsg")
        Log.i(TAG, ">>> /map subscription sent: $mapSent")
    }

    private fun parseStatusUpdate(json: String) {
        try {
            val obj = com.google.gson.JsonParser.parseString(json).asJsonObject
            val topic = obj.get("topic")?.asString ?: return
            val msg = obj.get("msg")?.asJsonObject ?: return
            val current = _robotStatus.value ?: RobotStatusData()

            when (topic) {
                SmaitProtocol.TOPIC_ROBOT_STATUS -> {
                    _robotStatus.value = current.copy(
                        battery = msg.get("battery")?.asInt ?: current.battery,
                        charger = msg.get("charger")?.asInt ?: current.charger,
                        navStatus = msg.get("nav_status")?.asInt ?: current.navStatus,
                        controlState = msg.get("control_state")?.asInt ?: current.controlState,
                        softEstop = msg.get("soft_estop")?.asBoolean ?: current.softEstop,
                        hardEstop = msg.get("hard_estop")?.asBoolean ?: current.hardEstop,
                        velocity = msg.get("velocity")?.asJsonArray?.map { it.asDouble } ?: current.velocity,
                        buildingName = msg.get("current_building_name")?.asString,
                        floorName = msg.get("current_floor_name")?.asString,
                        currentGoalName = msg.get("current_goal_name")?.asString
                    )
                }
                SmaitProtocol.TOPIC_ROBOT_POSE -> {
                    _robotStatus.value = current.copy(
                        x = msg.get("x")?.asDouble ?: current.x,
                        y = msg.get("y")?.asDouble ?: current.y,
                        theta = msg.get("theta")?.asDouble ?: current.theta
                    )
                }
                SmaitProtocol.TOPIC_SENSORS_CORE -> {
                    val bumper = msg.get("bumper")?.asInt ?: 0
                    val cliff = msg.get("cliff")?.asInt ?: 0
                    if (bumper > 0 || cliff > 0) {
                        safetyZone.set(SafetyZone.STOP)
                        Log.w(TAG, "SAFETY STOP: Bumper or Cliff detected!")
                        stop()
                    }
                    _robotStatus.value = current.copy(
                        sensors = SensorStatus(
                            bumperLeft = bumper and 4 != 0,
                            bumperCenter = bumper and 2 != 0,
                            bumperRight = bumper and 1 != 0,
                            cliffLeft = cliff and 4 != 0,
                            cliffCenter = cliff and 2 != 0,
                            cliffRight = cliff and 1 != 0
                        )
                    )
                }
                SmaitProtocol.TOPIC_LASER_DATA -> {
                    val points = msg.get("points")?.asJsonArray?.mapNotNull { it.asFloat.takeIf { f -> f > 0.01 } } ?: emptyList()
                    checkLaserData(points)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse status: ${e.message}")
        }
    }

    private fun checkLaserData(points: List<Float>) {
        if (points.isEmpty()) return

        // Split into arcs as per Flutter app logic (Front: 40-60%)
        val frontStartIndex = (points.size * 0.4).toInt()
        val frontEndIndex = (points.size * 0.6).toInt()
        val frontPoints = points.subList(frontStartIndex, frontEndIndex)
        val minFront = frontPoints.minOrNull() ?: Float.MAX_VALUE

        val newZone = when {
            minFront < STOP_DISTANCE -> SafetyZone.STOP
            minFront < CREEP_DISTANCE -> SafetyZone.CREEP
            minFront < WARN_DISTANCE -> SafetyZone.WARN
            else -> SafetyZone.CLEAR
        }

        val oldZone = safetyZone.getAndSet(newZone)
        if (newZone != oldZone) {
            Log.i(TAG, "LIDAR Safety Zone changed: $newZone (was $oldZone) at ${minFront}m")
            if (newZone == SafetyZone.STOP) {
                stop()
            }
        }
        _robotStatus.value = _robotStatus.value?.copy(safetyZone = newZone)
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
        var adjustedLinear = linearX
        when (safetyZone.get()) {
            SafetyZone.STOP -> {
                if (linearX > 0) {
                    Log.d(TAG, "Forward velocity blocked by STOP zone.")
                    adjustedLinear = 0.0
                }
            }
            SafetyZone.CREEP -> {
                if (linearX > CREEP_SPEED) {
                    Log.d(TAG, "Forward velocity limited to CREEP speed.")
                    adjustedLinear = CREEP_SPEED
                }
            }
            else -> { /* WARN or CLEAR, no adjustment needed */ }
        }
        send(SmaitProtocol.publishVelocity(adjustedLinear, angularZ))
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
        // Deprecated - speed is now handled in MainActivity
    }

    fun startSlam() {
        // TODO: Replace with actual command from robot documentation
        Log.w(TAG, "startSlam() not implemented")
    }

    fun stopSlam() {
        // TODO: Replace with actual command from robot documentation
        Log.w(TAG, "stopSlam() not implemented")
    }
}

enum class ConnectionState {
    DISCONNECTED,
    CONNECTING,
    CONNECTED,
    ERROR
}

data class SensorStatus(
    val bumperLeft: Boolean = false,
    val bumperCenter: Boolean = false,

    val bumperRight: Boolean = false,
    val cliffLeft: Boolean = false,
    val cliffCenter: Boolean = false,
    val cliffRight: Boolean = false
)

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
    val theta: Double = 0.0,
    val buildingName: String? = null,
    val floorName: String? = null,
    val currentGoalName: String? = null,
    val sensors: SensorStatus = SensorStatus(),
    val safetyZone: SafetyZone = SafetyZone.CLEAR
)
