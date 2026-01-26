package com.utilitron.robotrelay.service

import android.util.Log
import com.utilitron.robotrelay.protocol.ChassisProtocol
import com.utilitron.robotrelay.protocol.SubscribeMsg
import org.json.JSONObject
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
    val robotIp: String = "192.168.20.22",  // Wired USB connection to robot
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

    // Cache the latest map message for HTTP transport (more reliable than WS for big payloads)
    @Volatile
    private var _cachedMapMessage: String? = null
    val cachedMapMessage: String? get() = _cachedMapMessage

    @Volatile
    private var _mapLastUpdated: Long = 0
    val mapLastUpdated: Long get() = _mapLastUpdated

    private val _robotStatus = MutableStateFlow<RobotStatusData?>(null)
    val robotStatus: StateFlow<RobotStatusData?> = _robotStatus

    // Track when we last received ANY data from the robot
    // This is critical for detecting stale data even when heartbeats are flowing
    @Volatile
    private var _lastRobotDataTime: Long = 0
    val lastRobotDataTime: Long get() = _lastRobotDataTime

    // People detection from /people_detected topic
    private val _peopleDetected = MutableStateFlow(false)
    val peopleDetected: StateFlow<Boolean> = _peopleDetected

    private val safetyZone = AtomicReference(SafetyZone.CLEAR)

    // Detach mode: relaxed safety for pile/charger proximity
    // When true, STOP distance is reduced to allow close-quarters docking
    private val _detachMode = MutableStateFlow(false)
    val detachMode: StateFlow<Boolean> = _detachMode

    // Crowd control: minimum front LIDAR distance for gradient speed ramping
    @Volatile
    var minFrontDistance: Float = Float.MAX_VALUE
        private set

    // Track when LIDAR specifically last delivered data (separate from general robot data)
    @Volatile
    var lastLidarTime: Long = 0
        private set

    // Rate limit costmap logging (it's HUGE - 40k+ cells at 2Hz)
    private var lastCostmapLogTime: Long = 0
    private var lastPeopleArrayLogTime: Long = 0

    // Raw LIDAR points for visualization (in robot frame)
    // These are the px/py coordinates that show people/obstacles as silhouettes
    @Volatile
    var lidarPointsX: List<Double> = emptyList()
        private set
    @Volatile
    var lidarPointsY: List<Double> = emptyList()
        private set

    // Crowd control config: distance-proportional speed limiting
    private var crowdSafeDistance: Double = 0.9  // meters - ramping begins here
    private var crowdRampRate: Double = 0.5      // 0.1=gentle, 1.0=aggressive

    // Fragment reassembly for map data (chassis sends fragmented PNG per protocol docs)
    private val _mapFragments = mutableMapOf<Int, String>()  // num -> data chunk
    private var _mapFragmentTotal = 0

    // Obstacle classifier for intelligent crowd handling
    private var obstacleClassifier: ObstacleClassifier? = null
    private var onObstacleClassification: ((ObstacleClassification) -> Unit)? = null

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
            // CRITICAL: Track when we last got ANY data from robot
            // Must happen IMMEDIATELY on message receipt, before any coroutine launch
            // so heartbeat always sees fresh timestamp (fixes data_age_ms=-1 bug)
            _lastRobotDataTime = System.currentTimeMillis()

            // Handle map fragments (chassis sends fragmented PNG per protocol docs)
            if (text.contains("\"op\":\"fragment\"") || text.contains("\"op\": \"fragment\"")) {
                handleMapFragment(text)
                return
            }

            // Handle /static_map service response (fallback for latched topic)
            if (text.contains("\"service_response\"") && text.contains("static_map")) {
                try {
                    val obj = com.google.gson.JsonParser.parseString(text).asJsonObject
                    if (obj.get("result")?.asBoolean == true) {
                        val values = obj.getAsJsonObject("values")
                        val mapData = values?.getAsJsonObject("map")
                        if (mapData != null) {
                            // Convert service response to topic message format for Flutter
                            val topicMsg = com.google.gson.JsonObject().apply {
                                addProperty("op", "publish")
                                addProperty("topic", "/map")
                                add("msg", mapData)
                            }
                            val converted = topicMsg.toString()
                            Log.i(TAG, ">>> RECEIVED /static_map service response (${converted.length} bytes)")
                            _cachedMapMessage = converted
                            _mapLastUpdated = System.currentTimeMillis()
                            Log.i(TAG, ">>> Map cached from service call")
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to parse static_map response: ${e.message}")
                }
                return
            }

            // Handle complete map message (non-fragmented or after reassembly)
            val isMapMsg = text.contains("\"topic\":\"/map\"") || text.contains("\"topic\": \"/map\"")
            if (isMapMsg) {
                Log.i(TAG, ">>> RECEIVED /map message (${text.length} bytes)")
                _cachedMapMessage = text
                _mapLastUpdated = System.currentTimeMillis()
                Log.i(TAG, ">>> Map cached for HTTP transport")
            } else {
                Log.d(TAG, text.take(200))
            }

            val emitted = _incomingMessages.tryEmit(text)
            if (!emitted) {
                Log.w(TAG, "Message buffer full, dropped: ${if (isMapMsg) "/map" else text.take(50)}")
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
        send(ChassisProtocol.advertiseVelocity())
        send(ChassisProtocol.advertiseCancelGoal())
        send(ChassisProtocol.advertiseSoftStop())
        send(ChassisProtocol.subscribeRobotStatus())
        send(ChassisProtocol.subscribeRobotPose())
        send(ChassisProtocol.subscribeNaviStatus())
        send(ChassisProtocol.subscribeSensorsCore())
        send(ChassisProtocol.subscribeLaserData())
        // Also subscribe to /scan (sensor_msgs/LaserScan) - some robots publish this instead of /laser_data
        send(ChassisProtocol.toJson(SubscribeMsg(
            op = ChassisProtocol.OP_SUBSCRIBE,
            id = "get_scan",
            topic = "/scan",
            type = "sensor_msgs/LaserScan",
            throttleRate = 150
        )))
        send(ChassisProtocol.subscribeGlobalPath())  // For obstacle path intersection
        send(ChassisProtocol.subscribePeopleDetected())  // For human motion detection (boolean)
        send(ChassisProtocol.subscribeDetectedPeopleArray())  // Rich people detection data
        send(ChassisProtocol.subscribeHandpose())  // Hand gesture detection
        send(ChassisProtocol.subscribeLocalCostmap())  // Real-time obstacle blocks (OEM-style)
        // Subscribe to /map (raw OccupancyGrid, no fragmentation - works on our robots)
        val mapSubMsg = ChassisProtocol.subscribeMap()
        val mapSent = send(mapSubMsg)
        Log.i(TAG, ">>> Sending /map subscription: $mapSubMsg")
        Log.i(TAG, ">>> /map subscription sent: $mapSent")
    }

    /**
     * Enable obstacle intelligence for smart crowd announcements.
     * Only announces for moving obstacles or unexpected static obstacles.
     * Never yells at walls, corners, or reflections.
     */
    fun enableObstacleIntelligence(callback: (ObstacleClassification) -> Unit) {
        onObstacleClassification = callback
        obstacleClassifier = ObstacleClassifier { classification ->
            // Update robot status with obstacle info for CommandBuffer motion detection
            _robotStatus.value?.let { current ->
                _robotStatus.value = current.copy(
                    obstacleInPath = classification.inPath && classification.type != ObstacleType.CLEAR,
                    obstacleMoving = classification.isMoving,
                    obstacleType = classification.type.name
                )
            }
            callback(classification)
        }
        Log.i(TAG, "Obstacle intelligence enabled")
    }

    fun disableObstacleIntelligence() {
        obstacleClassifier?.destroy()
        obstacleClassifier = null
        onObstacleClassification = null
        Log.i(TAG, "Obstacle intelligence disabled")
    }

    fun setObstacleIntelligenceEnabled(enabled: Boolean) {
        obstacleClassifier?.enabled = enabled
    }

    /**
     * Handle a map fragment from the chassis (fragmented PNG per protocol docs).
     * Collects all fragments and reassembles the complete map message.
     */
    private fun handleMapFragment(text: String) {
        try {
            val json = JSONObject(text)
            val num = json.optInt("num", -1)
            val total = json.optInt("total", -1)
            val data = json.optString("data", "")
            if (num < 0 || total <= 0 || data.isEmpty()) return

            Log.i(TAG, ">>> Map fragment $num/$total (${data.length} bytes)")

            synchronized(_mapFragments) {
                _mapFragmentTotal = total
                _mapFragments[num] = data

                if (_mapFragments.size == total) {
                    // All fragments received - reassemble
                    val reassembled = StringBuilder()
                    for (i in 0 until total) {
                        reassembled.append(_mapFragments[i] ?: "")
                    }
                    _mapFragments.clear()

                    val completeMessage = reassembled.toString()
                    Log.i(TAG, ">>> Map reassembled: ${completeMessage.length} bytes from $total fragments")

                    // Cache the reassembled map for HTTP transport
                    _cachedMapMessage = completeMessage
                    _mapLastUpdated = System.currentTimeMillis()

                    // Emit to SharedFlow for WebSocket clients
                    _incomingMessages.tryEmit(completeMessage)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error handling map fragment: ${e.message}")
        }
    }

    /**
     * Force a map refresh by unsubscribing and resubscribing.
     * Uses fragmented+compressed subscription per chassis protocol docs.
     */
    fun refreshMap() {
        if (_connectionState.value != ConnectionState.CONNECTED) {
            Log.w(TAG, "Cannot refresh map - not connected to robot")
            return
        }

        scope.launch {
            Log.i(TAG, ">>> MAP REFRESH: Starting refresh sequence")

            val unsubMsg = ChassisProtocol.unsubscribe(ChassisProtocol.TOPIC_MAP, "get_map")
            send(unsubMsg)
            delay(300)

            _cachedMapMessage = null
            val subMsg = ChassisProtocol.subscribeMap()
            val sent = send(subMsg)
            Log.i(TAG, ">>> MAP REFRESH: Sent subscribe (success=$sent)")

            delay(2000)
            if (_connectionState.value == ConnectionState.CONNECTED && _cachedMapMessage == null) {
                Log.i(TAG, ">>> MAP REFRESH: No map from subscription, retrying...")
                send(subMsg)

                delay(2000)
                if (_connectionState.value == ConnectionState.CONNECTED && _cachedMapMessage == null) {
                    // Fallback: call /static_map service (works for latched topics)
                    Log.i(TAG, ">>> MAP REFRESH: Subscription failed, calling /static_map service")
                    val serviceCall = """{"op":"call_service","id":"get_static_map","service":"/static_map","type":"nav_msgs/GetMap"}"""
                    send(serviceCall)
                }
            }
        }
    }

    private fun parseStatusUpdate(json: String) {
        // Note: _lastRobotDataTime is now set in onMessage() directly (before coroutine launch)
        // This ensures heartbeat always sees fresh timestamp regardless of coroutine scheduling

        try {
            val obj = com.google.gson.JsonParser.parseString(json).asJsonObject
            val topic = obj.get("topic")?.asString ?: return
            val msg = obj.get("msg")?.asJsonObject ?: return
            val current = _robotStatus.value ?: RobotStatusData()

            when (topic) {
                ChassisProtocol.TOPIC_ROBOT_STATUS -> {
                    val velocity = msg.get("velocity")?.asJsonArray?.map { it.asDouble } ?: current.velocity
                    _robotStatus.value = current.copy(
                        battery = msg.get("battery")?.asInt ?: current.battery,
                        charger = msg.get("charger")?.asInt ?: current.charger,
                        navStatus = msg.get("nav_status")?.asInt ?: current.navStatus,
                        controlState = msg.get("control_state")?.asInt ?: current.controlState,
                        softEstop = msg.get("soft_estop")?.asBoolean ?: current.softEstop,
                        hardEstop = msg.get("hard_estop")?.asBoolean ?: current.hardEstop,
                        velocity = velocity,
                        buildingName = msg.get("current_building_name")?.asString,
                        floorName = msg.get("current_floor_name")?.asString,
                        currentGoalName = msg.get("current_goal_name")?.asString
                    )
                    // Feed velocity to obstacle classifier
                    if (velocity.size >= 2) {
                        obstacleClassifier?.updateRobotVelocity(velocity[0], velocity[1])
                    }
                }
                ChassisProtocol.TOPIC_ROBOT_POSE -> {
                    val x = msg.get("x")?.asDouble ?: current.x
                    val y = msg.get("y")?.asDouble ?: current.y
                    val theta = msg.get("theta")?.asDouble ?: current.theta
                    _robotStatus.value = current.copy(x = x, y = y, theta = theta)
                    // Feed to obstacle classifier
                    obstacleClassifier?.updateRobotPose(x, y, theta)
                }
                ChassisProtocol.TOPIC_SENSORS_CORE -> {
                    val bumper = msg.get("bumper")?.asInt ?: 0
                    val cliff = msg.get("cliff")?.asInt ?: 0

                    // Parse ultrasonic sensor data (analog_input array)
                    // Per Chassis protocol: only analog_input[1] is valid (central ultrasonic sensor)
                    val analogInput = msg.get("analog_input")?.asJsonArray
                    val ultrasonicMm = if (analogInput != null && analogInput.size() >= 2) {
                        analogInput.get(1).asInt  // Central ultrasonic in millimeters
                    } else {
                        9999  // No data or out of range
                    }
                    val ultrasonicMeters = ultrasonicMm / 1000.0

                    // Log ultrasonic data periodically for debugging
                    if (System.currentTimeMillis() % 2000 < 100) {  // ~Every 2 seconds
                        Log.d(TAG, "Ultrasonic: ${ultrasonicMm}mm (${String.format("%.2f", ultrasonicMeters)}m)")
                    }

                    // Check if we're docking with charger - ignore bumper/cliff during docking
                    val currentGoal = _robotStatus.value?.currentGoalName ?: ""
                    val isDocking = currentGoal.contains("Pile", ignoreCase = true) ||
                                  currentGoal.contains("Charger", ignoreCase = true) ||
                                  currentGoal.contains("Dock", ignoreCase = true)

                    if (bumper > 0 || cliff > 0) {
                        if (isDocking) {
                            // Docking with charger - this is expected! The tongs snap in!
                            Log.i(TAG, "Bumper contact during docking - charging tongs engaging!")
                        } else {
                            // Physical collision - always stop. Bumper = real contact,
                            // not a false reading like LIDAR. Cancel nav if active.
                            safetyZone.set(SafetyZone.STOP)
                            Log.w(TAG, "SAFETY STOP: Bumper or Cliff detected! (physical contact)")
                            stop()
                            if (_robotStatus.value?.navStatus == 601) {
                                cancelNavigation()
                                Log.w(TAG, "Navigation cancelled due to physical collision")
                            }
                        }
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
                    // TODO: Add ultrasonic distance to RobotStatusData for motion detection
                }
                ChassisProtocol.TOPIC_LASER_DATA -> {
                    // Try px/py format first (coordinate arrays)
                    val px = msg.get("px")?.asJsonArray?.map { it.asDouble }
                    val py = msg.get("py")?.asJsonArray?.map { it.asDouble }

                    if (px != null && py != null && px.size == py.size) {
                        // Store raw points for visualization (shows people/obstacles as silhouettes)
                        lidarPointsX = px
                        lidarPointsY = py

                        // Feed coordinate data to obstacle classifier
                        obstacleClassifier?.processLidarScan(px, py)

                        // Convert to distances for safety zone check
                        // Filter > 0.05m to eliminate ground reflections and sensor noise
                        val distances = px.zip(py).map { (x, y) ->
                            kotlin.math.sqrt(x * x + y * y).toFloat()
                        }.filter { it > 0.05f }
                        checkLaserData(distances)
                    } else {
                        // Fallback to points array (distance format)
                        val points = msg.get("points")?.asJsonArray?.mapNotNull {
                            it.asFloat.takeIf { f -> f > 0.05 }
                        } ?: emptyList()
                        checkLaserData(points)
                    }
                }
                "/scan" -> {
                    // sensor_msgs/LaserScan - ranges array of float distances
                    val ranges = msg.get("ranges")?.asJsonArray?.mapNotNull { el ->
                        try {
                            val r = el.asFloat
                            if (r > 0.05f && r < 30.0f) r else null
                        } catch (e: Exception) { null }
                    } ?: emptyList()
                    if (ranges.isNotEmpty()) {
                        checkLaserData(ranges)
                    }
                }
                ChassisProtocol.TOPIC_GLOBAL_PATH -> {
                    // Navigation path for obstacle-in-path detection
                    val px = msg.get("px")?.asJsonArray?.map { it.asDouble }
                    val py = msg.get("py")?.asJsonArray?.map { it.asDouble }
                    if (px != null && py != null && px.size == py.size) {
                        val pathPoints = px.zip(py).map { (x, y) -> Point2D(x, y) }
                        obstacleClassifier?.updateGlobalPath(pathPoints)
                    }
                }
                ChassisProtocol.TOPIC_PEOPLE_DETECTED -> {
                    // Robot's built-in people detection (boolean)
                    val detected = msg.get("data")?.asBoolean ?: false
                    if (detected != _peopleDetected.value) {
                        Log.i(TAG, ">>> PEOPLE_DETECTED: $detected")
                        _peopleDetected.value = detected
                    }
                }
                ChassisProtocol.TOPIC_DETECTED_PEOPLE_ARRAY -> {
                    // Rich people detection data - log summary only (once per second max)
                    if (lastPeopleArrayLogTime == 0L || System.currentTimeMillis() - lastPeopleArrayLogTime > 1000) {
                        lastPeopleArrayLogTime = System.currentTimeMillis()
                        // Try to find array field
                        val people = msg.get("people")?.asJsonArray
                            ?: msg.get("data")?.asJsonArray
                            ?: msg.get("detections")?.asJsonArray
                            ?: msg.get("persons")?.asJsonArray
                        if (people != null && people.size() > 0) {
                            Log.i(TAG, ">>> DETECTED_PEOPLE_ARRAY: ${people.size()} people detected")
                            // Log first person's structure ONCE to understand format
                            if (lastPeopleArrayLogTime < 5000) {
                                Log.i(TAG, ">>> First person structure: ${people.firstOrNull()}")
                            }
                        } else {
                            // Log the keys to understand the message format
                            Log.i(TAG, ">>> DETECTED_PEOPLE_ARRAY keys: ${msg.keySet()}")
                        }
                    }
                }
                ChassisProtocol.TOPIC_HANDPOSE -> {
                    // Hand gesture detection - LOG to understand format
                    Log.i(TAG, ">>> HANDPOSE: ${msg}")
                    val gestureId = msg.get("data")?.asInt
                    if (gestureId != null) {
                        Log.i(TAG, ">>> Hand gesture ID: $gestureId")
                    }
                }
                ChassisProtocol.TOPIC_LOCAL_COSTMAP -> {
                    // Local costmap - MASSIVE data, just track that we're getting it
                    // Don't log the actual data - it's 40,000+ cells at 2Hz!
                    if (lastCostmapLogTime == 0L || System.currentTimeMillis() - lastCostmapLogTime > 10000) {
                        val info = msg.get("info")?.asJsonObject
                        val width = info?.get("width")?.asInt ?: 0
                        val height = info?.get("height")?.asInt ?: 0
                        Log.i(TAG, ">>> LOCAL_COSTMAP: Receiving ${width}x${height} grid (logging once per 10s)")
                        lastCostmapLogTime = System.currentTimeMillis()
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse status: ${e.message}")
        }
    }

    private fun checkLaserData(points: List<Float>) {
        if (points.isEmpty()) return
        lastLidarTime = System.currentTimeMillis()

        // Split into arcs as per Flutter app logic (Front: 40-60%)
        val frontStartIndex = (points.size * 0.4).toInt()
        val frontEndIndex = (points.size * 0.6).toInt()
        val frontPoints = points.subList(frontStartIndex, frontEndIndex)
        // Filter out likely ground reflections / noise (readings under 5cm are not real obstacles)
        val validFrontPoints = frontPoints.filter { it > 0.05f }
        val minFront = validFrontPoints.minOrNull() ?: Float.MAX_VALUE

        // Track for crowd control gradient speed ramping
        minFrontDistance = minFront

        // Detach mode: pile/charger is physically close, relax thresholds
        val stopDist = if (_detachMode.value) 0.08f else STOP_DISTANCE   // 8cm vs 20cm
        val creepDist = if (_detachMode.value) 0.20f else CREEP_DISTANCE // 20cm vs 50cm
        val warnDist = if (_detachMode.value) 0.40f else WARN_DISTANCE   // 40cm vs 80cm

        val newZone = when {
            minFront < stopDist -> SafetyZone.STOP
            minFront < creepDist -> SafetyZone.CREEP
            minFront < warnDist -> SafetyZone.WARN
            else -> SafetyZone.CLEAR
        }

        val oldZone = safetyZone.getAndSet(newZone)
        if (newZone != oldZone) {
            val obstacleType = _robotStatus.value?.obstacleType ?: "UNKNOWN"
            Log.i(TAG, "Safety zone: $newZone (was $oldZone) at ${minFront}m, obstacle=$obstacleType" +
                    if (_detachMode.value) " [DETACH]" else "")
        }
        _robotStatus.value = _robotStatus.value?.copy(safetyZone = newZone)
    }

    /**
     * Set detach mode for close-quarters operation near pile/charger.
     * Relaxes LIDAR safety thresholds to allow docking/undocking.
     */
    fun setDetachMode(enabled: Boolean) {
        if (_detachMode.value != enabled) {
            _detachMode.value = enabled
            Log.i(TAG, "Detach mode: ${if (enabled) "ON" else "OFF"} - safety thresholds ${if (enabled) "relaxed" else "normal"}")
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
        obstacleClassifier?.destroy()
        disconnect()
        scope.cancel()
    }

    // === Control Methods ===

    fun sendVelocity(linearX: Double, angularZ: Double) {
        // During autonomous navigation, move_base controls velocity via its own
        // costmaps and local planner. Don't interfere with teleop overrides.
        val isNavigating = _robotStatus.value?.navStatus == 601
        if (isNavigating) {
            // Don't send teleop velocity during autonomous nav - it overrides move_base
            return
        }

        var adjustedLinear = linearX

        if (linearX > 0) {
            val distance = minFrontDistance.toDouble()
            val obstacleType = _robotStatus.value?.obstacleType ?: "CLEAR"
            val peopleNearby = _peopleDetected.value

            // Use classifier + human detector to determine response:
            // - Wall/mapped obstacle: hard stop
            // - Human/crowd: gradient push-through (they'll move)
            // - Unknown + people detected: treat as crowd
            // - Unknown + no people: cautious gradient (might be furniture)
            val isWall = obstacleType == "STATIC_EXPECTED"
            val isHuman = obstacleType in listOf("MOVING_PERSON", "CROWD", "STATIC_PERSON")
            val treatAsCrowd = isHuman || (peopleNearby && obstacleType == "UNKNOWN")

            if (distance < crowdSafeDistance) {
                if (isWall && !_detachMode.value) {
                    // Known wall: hard stop (don't push through walls)
                    adjustedLinear = 0.0
                    Log.d(TAG, "Wall detected - hard stop")
                } else {
                    // Human/crowd/unknown: gradient speed ramp, push through
                    val fraction = (distance / crowdSafeDistance).coerceIn(0.0, 1.0)
                    val rampedFraction = Math.pow(fraction, crowdRampRate)
                    // Minimum push speed: always keep moving through crowds
                    val minFraction = CREEP_SPEED / linearX.coerceAtLeast(CREEP_SPEED)
                    adjustedLinear = linearX * rampedFraction.coerceAtLeast(minFraction)

                    if (adjustedLinear != linearX) {
                        Log.d(TAG, "Crowd ramp: ${String.format("%.2f", linearX)} → ${String.format("%.2f", adjustedLinear)} " +
                                "(dist=${String.format("%.2f", distance)}m, type=$obstacleType, people=$peopleNearby)")
                    }
                }
            }
        }
        send(ChassisProtocol.publishVelocity(adjustedLinear, angularZ))
    }

    /**
     * Update crowd control configuration for speed ramping.
     */
    fun setCrowdConfig(safeDistanceMeters: Double, rampRate: Double) {
        crowdSafeDistance = safeDistanceMeters.coerceIn(0.3, 3.0)
        crowdRampRate = rampRate.coerceIn(0.1, 1.0)
        Log.i(TAG, "Crowd config: safeDistance=${crowdSafeDistance}m, rampRate=$crowdRampRate")
    }

    fun stop() {
        send(ChassisProtocol.stopRobot())
    }

    fun cancelNavigation() {
        send(ChassisProtocol.publishCancelGoal())
    }

    fun setSoftStop(enabled: Boolean) {
        send(ChassisProtocol.publishSoftStop(enabled))
    }

    fun navigateToPoi(poiName: String) {
        send(ChassisProtocol.callNavigateToPoi(poiName))
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
    DISCONNECTED,  // Initial state or intentional disconnect
    CONNECTING,    // Actively attempting to connect
    CONNECTED,     // Successfully connected
    STALE,         // Was connected, lost connection, quietly retrying
    ERROR          // Failed after multiple attempts, needs attention
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
    val safetyZone: SafetyZone = SafetyZone.CLEAR,
    // Obstacle intelligence fields (from ObstacleClassifier)
    val obstacleInPath: Boolean = false,
    val obstacleMoving: Boolean = false,
    val obstacleType: String = "CLEAR"
)
