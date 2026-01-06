package com.smait.robotrelay.service

import android.util.Log
import com.google.gson.Gson
import com.google.gson.JsonObject
import com.smait.robotrelay.protocol.SmaitProtocol
import fi.iki.elonen.NanoHTTPD
import fi.iki.elonen.NanoWSD
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.io.IOException

/**
 * Relay server that accepts connections from external devices
 * and forwards commands to the robot base.
 *
 * Endpoints:
 * - WebSocket ws://tablet-ip:8765 - Full bidirectional relay
 * - HTTP POST /cmd - Send single command
 * - HTTP GET /status - Get robot status
 * - HTTP POST /velocity - Send velocity command
 * - HTTP POST /navigate - Navigate to POI
 * - HTTP POST /stop - Emergency stop
 */
class RelayServer(
    private val robotClient: RobotWebSocketClient,
    private val port: Int = 8765,
    private val taskExecutor: TaskExecutor? = null,
    private val configStore: RelayHttpServer.ConfigStore? = null
) {

    interface TaskExecutor {
        fun speakText(text: String)
        fun stopSpeak()  // Stop current TTS to prevent queue buildup
        fun displayUrl(url: String)
        fun closeDisplay()
        fun runTask(type: String, data: String, waitSeconds: Int)
        fun cancelTask()
        fun playAlertSound(soundType: String)
        fun setTtsApiKey(apiKey: String?)
        fun hasTtsApiKey(): Boolean
    }
    companion object {
        private const val TAG = "RelayServer"
    }

    private val gson = Gson()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    private var httpServer: RelayHttpServer? = null
    private var wsServer: RelayWebSocketServer? = null

    private val _isRunning = MutableStateFlow(false)
    val isRunning: StateFlow<Boolean> = _isRunning

    private val _connectedClients = MutableStateFlow(0)
    val connectedClients: StateFlow<Int> = _connectedClients

    private var messageForwarderJob: Job? = null
    private var connectionWatcherJob: Job? = null
    private var navStatusWatcherJob: Job? = null
    private var lastRobotConnectedState = false

    // Command buffer for task execution
    lateinit var commandBuffer: CommandBuffer
        private set

    fun start() {
        try {
            // Initialize command buffer
            commandBuffer = CommandBuffer(robotClient, taskExecutor) { statusJson ->
                // Broadcast buffer status to all connected Flutter clients
                wsServer?.broadcast(statusJson)
            }
            commandBuffer.start()

            // Start HTTP server on port
            httpServer = RelayHttpServer(port, robotClient, gson, taskExecutor, configStore)
            httpServer?.start()

            // Start WebSocket server on port + 1
            wsServer = RelayWebSocketServer(port + 1, robotClient, scope, { count ->
                _connectedClients.value = count
            }, taskExecutor, commandBuffer)
            wsServer?.start()

            _isRunning.value = true
            Log.i(TAG, "Relay server started on HTTP:$port, WS:${port + 1}")

            // Forward robot messages to connected WebSocket clients
            // Use SupervisorJob and restart on failure to handle client disconnects gracefully
            startMessageForwarder()

            // CRITICAL: Watch robot connection state and restart forwarder on reconnect
            startConnectionWatcher()

            // Watch nav status for command buffer completion
            startNavStatusWatcher()
        } catch (e: IOException) {
            Log.e(TAG, "Failed to start server: ${e.message}")
            _isRunning.value = false
        }
    }

    /**
     * Watch robot nav status and forward to command buffer
     */
    private fun startNavStatusWatcher() {
        navStatusWatcherJob?.cancel()
        navStatusWatcherJob = scope.launch {
            robotClient.robotStatus.collect { status ->
                if (status != null) {
                    commandBuffer.onNavStatus(status.navStatus, status.currentGoalName ?: "")
                }
            }
        }
    }

    /**
     * Watch robot connection state and restart the message forwarder when robot reconnects.
     * This is critical because the SharedFlow collect() can get stuck when robot disconnects.
     */
    private fun startConnectionWatcher() {
        connectionWatcherJob?.cancel()
        connectionWatcherJob = scope.launch {
            robotClient.connectionState.collect { state ->
                val isConnected = state == ConnectionState.CONNECTED
                Log.i(TAG, "Robot connection state: $state (was connected: $lastRobotConnectedState)")

                // Detect reconnection: was disconnected/error, now connected
                if (isConnected && !lastRobotConnectedState) {
                    Log.i(TAG, ">>> Robot reconnected! Restarting message forwarder...")
                    // Give robot time to establish subscriptions
                    delay(1000)
                    startMessageForwarder()
                }

                lastRobotConnectedState = isConnected
            }
        }
    }

    /**
     * Start the message forwarder coroutine with auto-restart on failure.
     * This is critical for resilience - if a client disconnects abruptly (e.g., Flutter hot reload),
     * the forwarder should continue working for other clients.
     */
    private fun startMessageForwarder() {
        messageForwarderJob?.cancel()
        messageForwarderJob = scope.launch {
            var restartCount = 0
            var mapMsgCount = 0
            var lastMapTime = 0L
            var lastMessageTime = System.currentTimeMillis()
            var totalMessageCount = 0L

            // Start liveness monitor that logs heartbeat every 10 seconds
            val livenessJob = launch {
                while (isActive) {
                    delay(10_000)
                    val timeSinceLastMsg = System.currentTimeMillis() - lastMessageTime
                    val robotConnected = robotClient.connectionState.value == ConnectionState.CONNECTED
                    Log.i(TAG, "Forwarder heartbeat: ${totalMessageCount} msgs, last msg ${timeSinceLastMsg}ms ago, robot=$robotConnected")

                    // If robot is connected but we haven't received messages in 30 seconds, log warning
                    if (robotConnected && timeSinceLastMsg > 30_000) {
                        Log.w(TAG, ">>> WARNING: No messages in ${timeSinceLastMsg}ms despite robot being connected!")
                    }
                }
            }

            while (isActive && _isRunning.value) {
                try {
                    Log.i(TAG, "Message forwarder starting (restart #$restartCount)")
                    robotClient.incomingMessages.collect { message ->
                        try {
                            lastMessageTime = System.currentTimeMillis()
                            totalMessageCount++

                            // Track /map messages - they're large but needed for Flutter clients
                            val isMapMsg = message.contains("\"/map\"") || message.contains("\"topic\":\"/map\"")
                            if (isMapMsg) {
                                mapMsgCount++
                                val timeSinceLast = lastMessageTime - lastMapTime
                                Log.i(TAG, ">>> /map #$mapMsgCount (${message.length} bytes, ${timeSinceLast}ms since last)")
                                lastMapTime = lastMessageTime
                            }

                            wsServer?.broadcast(message)
                        } catch (t: Throwable) {
                            Log.w(TAG, "Broadcast error (continuing): ${t.javaClass.simpleName}: ${t.message}")
                        }
                    }
                    Log.i(TAG, "Message forwarder flow completed, will restart...")
                } catch (t: Throwable) {
                    Log.e(TAG, "Message forwarder error: ${t.javaClass.simpleName}: ${t.message}")
                    t.printStackTrace()
                }
                // Minimal delay before restart - speed is critical for safety
                if (isActive && _isRunning.value) {
                    restartCount++
                    delay(100)  // Reduced from 500ms for faster recovery
                }
            }
            livenessJob.cancel()
            Log.i(TAG, "Message forwarder stopped")
        }
    }

    fun stop() {
        connectionWatcherJob?.cancel()
        messageForwarderJob?.cancel()
        navStatusWatcherJob?.cancel()
        if (::commandBuffer.isInitialized) {
            commandBuffer.stop()
        }
        httpServer?.stop()
        wsServer?.stop()
        _isRunning.value = false
        Log.i(TAG, "Relay server stopped")
    }

    fun destroy() {
        stop()
        scope.cancel()
    }
}

/**
 * HTTP server for REST-like commands
 */
class RelayHttpServer(
    port: Int,
    private val robotClient: RobotWebSocketClient,
    private val gson: Gson,
    private val taskExecutor: RelayServer.TaskExecutor? = null,
    private val configStore: ConfigStore? = null
) : NanoHTTPD(port) {

    companion object {
        private const val TAG = "RelayHTTP"
    }

    interface ConfigStore {
        fun getConfig(): String?
        fun saveConfig(json: String)
    }

    override fun serve(session: IHTTPSession): Response {
        val uri = session.uri
        val method = session.method

        Log.d(TAG, "$method $uri")

        // CORS headers for browser access
        val corsHeaders = mutableMapOf(
            "Access-Control-Allow-Origin" to "*",
            "Access-Control-Allow-Methods" to "GET, POST, DELETE, OPTIONS",
            "Access-Control-Allow-Headers" to "Content-Type"
        )

        if (method == Method.OPTIONS) {
            return newFixedLengthResponse(Response.Status.OK, "text/plain", "").apply {
                corsHeaders.forEach { (k, v) -> addHeader(k, v) }
            }
        }

        val response = when {
            uri == "/discovery" && method == Method.GET -> handleDiscovery()
            uri == "/status" && method == Method.GET -> handleGetStatus()
            uri == "/cmd" && method == Method.POST -> handleRawCommand(session)
            uri == "/velocity" && method == Method.POST -> handleVelocity(session)
            uri == "/navigate" && method == Method.POST -> handleNavigate(session)
            uri == "/stop" && method == Method.POST -> handleStop()
            uri == "/estop" && method == Method.POST -> handleEStop(session)
            uri == "/cancel" && method == Method.POST -> handleCancel()
            uri == "/info" && method == Method.GET -> handleGetInfo()
            // Map endpoint - HTTP transport for large map data (more reliable than WS)
            uri == "/map" && method == Method.GET -> handleGetMap()
            uri == "/map/refresh" && method == Method.POST -> handleRefreshMap()
            // Task endpoints
            uri == "/speak" && method == Method.POST -> handleSpeak(session)
            uri == "/display" && method == Method.POST -> handleDisplay(session)
            uri == "/display" && method == Method.DELETE -> handleCloseDisplay()
            uri == "/task" && method == Method.POST -> handleTask(session)
            uri == "/task" && method == Method.DELETE -> handleCancelTask()
            // Config sync endpoints
            uri == "/config" && method == Method.GET -> handleGetConfig()
            uri == "/config" && method == Method.POST -> handleSaveConfig(session)
            // TTS API key configuration
            uri == "/tts/apikey" && method == Method.POST -> handleSetTtsApiKey(session)
            uri == "/tts/apikey" && method == Method.GET -> handleGetTtsStatus()
            uri == "/" && method == Method.GET -> handleRoot()
            else -> newFixedLengthResponse(Response.Status.NOT_FOUND, MIME_PLAINTEXT, "Not found")
        }

        corsHeaders.forEach { (k, v) -> response.addHeader(k, v) }
        return response
    }

    private fun handleRoot(): Response {
        val html = """
            <!DOCTYPE html>
            <html>
            <head><title>Robot Relay</title></head>
            <body>
                <h1>Robot Relay Server</h1>
                <p>Connection: ${robotClient.connectionState.value}</p>
                <h2>Robot Control:</h2>
                <ul>
                    <li>GET /status - Robot status</li>
                    <li>POST /cmd - Raw command (JSON body)</li>
                    <li>POST /velocity - {"linear": 0.2, "angular": 0.0}</li>
                    <li>POST /navigate - {"poi": "P1"}</li>
                    <li>POST /stop - Stop robot</li>
                    <li>POST /estop - {"enabled": true/false}</li>
                    <li>POST /cancel - Cancel navigation</li>
                </ul>
                <h2>Tablet Tasks:</h2>
                <ul>
                    <li>POST /speak - {"text": "Hello!"} - TTS announcement</li>
                    <li>POST /display - {"url": "https://..."} - Show webpage/video</li>
                    <li>DELETE /display - Close displayed content</li>
                    <li>POST /task - {"type": "DELIVER|SPEAK|DISPLAY", "data": "...", "wait_seconds": 10}</li>
                    <li>DELETE /task - Cancel current task</li>
                </ul>
                <h2>Config Sync:</h2>
                <ul>
                    <li>GET /config - Get shared task mode configurations</li>
                    <li>POST /config - Save task mode configurations (JSON body)</li>
                </ul>
                <h2>TTS Settings:</h2>
                <ul>
                    <li>GET /tts/apikey - Check if Google Cloud TTS API key is set</li>
                    <li>POST /tts/apikey - {"api_key": "YOUR_KEY"} - Set API key for high-quality TTS</li>
                </ul>
                <p>WebSocket: ws://[this-ip]:${(this as NanoHTTPD).listeningPort + 1}</p>
            </body>
            </html>
        """.trimIndent()
        return newFixedLengthResponse(Response.Status.OK, "text/html", html)
    }

    private fun handleDiscovery(): Response {
        val status = robotClient.robotStatus.value
        val data = mapOf(
            "type" to "SMAIT_RELAY",
            "version" to "1.0",
            "relayHttpPort" to (this as NanoHTTPD).listeningPort,
            "relayWsPort" to (this as NanoHTTPD).listeningPort + 1,
            "robotConnected" to (robotClient.connectionState.value == ConnectionState.CONNECTED),
            "robotIp" to robotClient.robotIp,
            "deviceName" to android.os.Build.MODEL,
            "battery" to (status?.battery ?: 0),
            "navStatus" to (status?.navStatus ?: 0)
        )
        return newFixedLengthResponse(Response.Status.OK, "application/json", gson.toJson(data))
    }

    private fun handleGetStatus(): Response {
        val status = robotClient.robotStatus.value
        val data = mapOf(
            "connected" to (robotClient.connectionState.value == ConnectionState.CONNECTED),
            "connectionState" to robotClient.connectionState.value.name,
            "robot" to status
        )
        return newFixedLengthResponse(Response.Status.OK, "application/json", gson.toJson(data))
    }

    private fun handleGetInfo(): Response {
        robotClient.send(com.smait.robotrelay.protocol.SmaitProtocol.callGetRobotInfo())
        return newFixedLengthResponse(Response.Status.OK, "application/json",
            gson.toJson(mapOf("status" to "requested")))
    }

    private fun handleRawCommand(session: IHTTPSession): Response {
        val body = getBody(session)
        val success = robotClient.send(body)
        return newFixedLengthResponse(
            if (success) Response.Status.OK else Response.Status.SERVICE_UNAVAILABLE,
            "application/json",
            gson.toJson(mapOf("sent" to success))
        )
    }

    private fun handleVelocity(session: IHTTPSession): Response {
        return try {
            val body = gson.fromJson(getBody(session), JsonObject::class.java)
            val linear = body.get("linear")?.asDouble ?: 0.0
            val angular = body.get("angular")?.asDouble ?: 0.0
            robotClient.sendVelocity(linear, angular)
            newFixedLengthResponse(Response.Status.OK, "application/json",
                gson.toJson(mapOf("linear" to linear, "angular" to angular)))
        } catch (e: Exception) {
            newFixedLengthResponse(Response.Status.BAD_REQUEST, "application/json",
                gson.toJson(mapOf("error" to e.message)))
        }
    }

    private fun handleNavigate(session: IHTTPSession): Response {
        return try {
            val body = gson.fromJson(getBody(session), JsonObject::class.java)
            val poi = body.get("poi")?.asString ?: throw IllegalArgumentException("Missing 'poi'")
            robotClient.navigateToPoi(poi)
            newFixedLengthResponse(Response.Status.OK, "application/json",
                gson.toJson(mapOf("navigating_to" to poi)))
        } catch (e: Exception) {
            newFixedLengthResponse(Response.Status.BAD_REQUEST, "application/json",
                gson.toJson(mapOf("error" to e.message)))
        }
    }

    private fun handleStop(): Response {
        robotClient.stop()
        return newFixedLengthResponse(Response.Status.OK, "application/json",
            gson.toJson(mapOf("stopped" to true)))
    }

    private fun handleEStop(session: IHTTPSession): Response {
        return try {
            val body = gson.fromJson(getBody(session), JsonObject::class.java)
            val enabled = body.get("enabled")?.asBoolean ?: true
            robotClient.setSoftStop(enabled)
            newFixedLengthResponse(Response.Status.OK, "application/json",
                gson.toJson(mapOf("estop" to enabled)))
        } catch (e: Exception) {
            newFixedLengthResponse(Response.Status.BAD_REQUEST, "application/json",
                gson.toJson(mapOf("error" to e.message)))
        }
    }

    private fun handleCancel(): Response {
        robotClient.cancelNavigation()
        return newFixedLengthResponse(Response.Status.OK, "application/json",
            gson.toJson(mapOf("cancelled" to true)))
    }

    // === Map HTTP Transport ===
    // More reliable than WebSocket for large payloads

    private fun handleGetMap(): Response {
        val mapJson = robotClient.cachedMapMessage
        if (mapJson == null) {
            Log.w(TAG, "GET /map - no cached map available")
            return newFixedLengthResponse(Response.Status.NOT_FOUND, "application/json",
                gson.toJson(mapOf(
                    "error" to "No map data available",
                    "hint" to "Robot may not be publishing /map or relay just started"
                )))
        }

        val age = System.currentTimeMillis() - robotClient.mapLastUpdated
        Log.i(TAG, "GET /map - serving cached map (${mapJson.length} bytes, ${age}ms old)")

        // Return the raw rosbridge message (contains topic and msg)
        return newFixedLengthResponse(Response.Status.OK, "application/json", mapJson).apply {
            addHeader("X-Map-Age-Ms", age.toString())
            addHeader("X-Map-Size", mapJson.length.toString())
        }
    }

    private fun handleRefreshMap(): Response {
        Log.i(TAG, "POST /map/refresh - triggering map refresh")
        robotClient.refreshMap()
        return newFixedLengthResponse(Response.Status.OK, "application/json",
            gson.toJson(mapOf(
                "refreshing" to true,
                "message" to "Map refresh initiated, GET /map in a few seconds"
            )))
    }

    // === Task Endpoints ===

    private fun handleSpeak(session: IHTTPSession): Response {
        return try {
            val body = gson.fromJson(getBody(session), JsonObject::class.java)
            val text = body.get("text")?.asString ?: throw IllegalArgumentException("Missing 'text'")
            taskExecutor?.speakText(text) ?: throw IllegalStateException("Task executor not available")
            newFixedLengthResponse(Response.Status.OK, "application/json",
                gson.toJson(mapOf("speaking" to text)))
        } catch (e: Exception) {
            newFixedLengthResponse(Response.Status.BAD_REQUEST, "application/json",
                gson.toJson(mapOf("error" to e.message)))
        }
    }

    private fun handleDisplay(session: IHTTPSession): Response {
        return try {
            val body = gson.fromJson(getBody(session), JsonObject::class.java)
            val url = body.get("url")?.asString ?: throw IllegalArgumentException("Missing 'url'")
            taskExecutor?.displayUrl(url) ?: throw IllegalStateException("Task executor not available")
            newFixedLengthResponse(Response.Status.OK, "application/json",
                gson.toJson(mapOf("displaying" to url)))
        } catch (e: Exception) {
            newFixedLengthResponse(Response.Status.BAD_REQUEST, "application/json",
                gson.toJson(mapOf("error" to e.message)))
        }
    }

    private fun handleCloseDisplay(): Response {
        taskExecutor?.closeDisplay()
        return newFixedLengthResponse(Response.Status.OK, "application/json",
            gson.toJson(mapOf("closed" to true)))
    }

    private fun handleTask(session: IHTTPSession): Response {
        return try {
            val body = gson.fromJson(getBody(session), JsonObject::class.java)
            val type = body.get("type")?.asString ?: throw IllegalArgumentException("Missing 'type'")
            val data = body.get("data")?.asString ?: ""
            val waitSeconds = body.get("wait_seconds")?.asInt ?: 0

            taskExecutor?.runTask(type, data, waitSeconds)
                ?: throw IllegalStateException("Task executor not available")

            newFixedLengthResponse(Response.Status.OK, "application/json",
                gson.toJson(mapOf("executing" to type, "data" to data)))
        } catch (e: Exception) {
            newFixedLengthResponse(Response.Status.BAD_REQUEST, "application/json",
                gson.toJson(mapOf("error" to e.message)))
        }
    }

    private fun handleCancelTask(): Response {
        taskExecutor?.cancelTask()
        return newFixedLengthResponse(Response.Status.OK, "application/json",
            gson.toJson(mapOf("cancelled" to true)))
    }

    // === Config Sync Endpoints ===

    private fun handleGetConfig(): Response {
        val config = configStore?.getConfig() ?: "{}"
        return newFixedLengthResponse(Response.Status.OK, "application/json", config)
    }

    private fun handleSaveConfig(session: IHTTPSession): Response {
        return try {
            val body = getBody(session)
            configStore?.saveConfig(body) ?: throw IllegalStateException("Config store not available")
            Log.i(TAG, "Config saved: ${body.take(100)}...")
            newFixedLengthResponse(Response.Status.OK, "application/json",
                gson.toJson(mapOf("saved" to true)))
        } catch (e: Exception) {
            newFixedLengthResponse(Response.Status.BAD_REQUEST, "application/json",
                gson.toJson(mapOf("error" to e.message)))
        }
    }

    // === TTS API Key Endpoints ===

    private fun handleSetTtsApiKey(session: IHTTPSession): Response {
        return try {
            val body = gson.fromJson(getBody(session), JsonObject::class.java)
            val apiKey = body.get("api_key")?.asString
            taskExecutor?.setTtsApiKey(apiKey)
                ?: throw IllegalStateException("Task executor not available")
            Log.i(TAG, "TTS API key ${if (apiKey.isNullOrEmpty()) "cleared" else "set"}")
            newFixedLengthResponse(Response.Status.OK, "application/json",
                gson.toJson(mapOf("configured" to !apiKey.isNullOrEmpty())))
        } catch (e: Exception) {
            newFixedLengthResponse(Response.Status.BAD_REQUEST, "application/json",
                gson.toJson(mapOf("error" to e.message)))
        }
    }

    private fun handleGetTtsStatus(): Response {
        val hasKey = taskExecutor?.hasTtsApiKey() ?: false
        return newFixedLengthResponse(Response.Status.OK, "application/json",
            gson.toJson(mapOf("configured" to hasKey, "engine" to if (hasKey) "google_cloud" else "device")))
    }

    private fun getBody(session: IHTTPSession): String {
        val files = mutableMapOf<String, String>()
        session.parseBody(files)
        return files["postData"] ?: ""
    }
}

/**
 * WebSocket server for full bidirectional relay
 */
class RelayWebSocketServer(
    port: Int,
    private val robotClient: RobotWebSocketClient,
    private val scope: CoroutineScope,
    private val onClientCountChanged: (Int) -> Unit,
    private val taskExecutor: RelayServer.TaskExecutor? = null,
    private val commandBuffer: CommandBuffer? = null
) : NanoWSD(port) {

    companion object {
        private const val TAG = "RelayWS"
        private const val PING_INTERVAL_MS = 10_000L  // Send ping every 10 seconds
    }

    private val clients = mutableListOf<WebSocket>()
    private var pingJob: Job? = null

    override fun start(timeout: Int, daemon: Boolean) {
        // Use a long socket timeout (60 seconds) to avoid premature disconnects
        super.start(60000, daemon)
        // Start periodic ping to keep connections alive
        pingJob = scope.launch {
            while (isActive) {
                delay(PING_INTERVAL_MS)
                pingAllClients()
            }
        }
    }

    override fun start() {
        start(60000, false)
    }

    override fun stop() {
        pingJob?.cancel()
        super.stop()
    }

    private fun pingAllClients() {
        synchronized(clients) {
            clients.forEach { client ->
                try {
                    client.ping(ByteArray(0))
                } catch (e: Exception) {
                    Log.w(TAG, "Ping failed for client: ${e.message}")
                }
            }
        }
    }

    override fun openWebSocket(handshake: IHTTPSession): WebSocket {
        return RelayWebSocket(handshake, robotClient, scope, taskExecutor, commandBuffer) { ws, connected ->
            synchronized(clients) {
                if (connected) {
                    clients.add(ws)
                } else {
                    clients.remove(ws)
                }
                onClientCountChanged(clients.size)
            }
            Log.i(TAG, "Clients: ${clients.size}")
        }
    }

    fun broadcast(message: String) {
        val deadClients = mutableListOf<WebSocket>()
        synchronized(clients) {
            clients.forEach { client ->
                try {
                    client.send(message)
                } catch (e: Exception) {
                    Log.e(TAG, "Broadcast error, removing dead client: ${e.message}")
                    deadClients.add(client)
                }
            }
            // Remove dead clients
            if (deadClients.isNotEmpty()) {
                clients.removeAll(deadClients)
                onClientCountChanged(clients.size)
            }
        }
    }

    class RelayWebSocket(
        handshake: IHTTPSession,
        private val robotClient: RobotWebSocketClient,
        private val scope: CoroutineScope,
        private val taskExecutor: RelayServer.TaskExecutor?,
        private val commandBuffer: CommandBuffer?,
        private val onConnectionChanged: (WebSocket, Boolean) -> Unit
    ) : NanoWSD.WebSocket(handshake) {

        private val gson = com.google.gson.Gson()

        override fun onOpen() {
            Log.i(TAG, "Client connected")
            onConnectionChanged(this, true)
            // Force /map refresh using the robust refreshMap method
            Log.i(TAG, "Triggering map refresh for new Flutter client")
            robotClient.refreshMap()
        }

        override fun onClose(code: WebSocketFrame.CloseCode, reason: String, initiatedByRemote: Boolean) {
            Log.i(TAG, "Client disconnected: $reason")
            onConnectionChanged(this, false)
        }

        override fun onMessage(message: WebSocketFrame) {
            val payload = message.textPayload

            // Check for tablet-specific commands (intercept before forwarding to robot)
            try {
                val json = gson.fromJson(payload, com.google.gson.JsonObject::class.java)
                val op = json.get("op")?.asString

                // Log all ops that start with "tablet_" or "buffer_" for debugging
                if (op?.startsWith("tablet_") == true || op?.startsWith("buffer_") == true) {
                    Log.i(TAG, ">>> Received command: op=$op")
                }

                when (op) {
                    // === BUFFER PROTOCOL (new, preferred) ===
                    "buffer_load" -> {
                        val commands = json.getAsJsonArray("commands")?.map { cmdJson ->
                            BufferCommand.fromJson(cmdJson.asJsonObject)
                        } ?: emptyList()
                        val clearExisting = json.get("clear_existing")?.asBoolean ?: false
                        Log.i(TAG, "Buffer load: ${commands.size} commands, clear=$clearExisting")
                        commandBuffer?.loadCommands(commands, clearExisting)
                        return
                    }
                    "buffer_clear" -> {
                        Log.i(TAG, "Buffer clear")
                        commandBuffer?.clear()
                        return
                    }
                    "buffer_pause" -> {
                        Log.i(TAG, "Buffer pause")
                        commandBuffer?.pause()
                        return
                    }
                    "buffer_resume" -> {
                        Log.i(TAG, "Buffer resume")
                        commandBuffer?.resume()
                        return
                    }
                    "buffer_skip" -> {
                        Log.i(TAG, "Buffer skip")
                        commandBuffer?.skip()
                        return
                    }
                    "buffer_status" -> {
                        Log.i(TAG, "Buffer status request")
                        // Heartbeat will send current status
                        return
                    }

                    // === LEGACY TABLET COMMANDS (still supported) ===
                    "tablet_stop_speak" -> {
                        Log.i(TAG, "Tablet stop speak")
                        taskExecutor?.stopSpeak()
                        return
                    }
                    "tablet_speak" -> {
                        val text = json.get("text")?.asString
                        if (text == null) {
                            Log.e(TAG, "tablet_speak missing 'text' field!")
                            return
                        }
                        Log.i(TAG, "Tablet speak: $text")
                        if (taskExecutor != null) {
                            taskExecutor.speakText(text)
                        } else {
                            Log.e(TAG, "taskExecutor is null! Cannot speak.")
                        }
                        return
                    }
                    "tablet_display" -> {
                        val url = json.get("url")?.asString
                        if (url == null) {
                            Log.e(TAG, "tablet_display missing 'url' field!")
                            return
                        }
                        Log.i(TAG, "Tablet display: ${url.take(100)}...")
                        if (taskExecutor != null) {
                            taskExecutor.displayUrl(url)
                        } else {
                            Log.e(TAG, "taskExecutor is null! Cannot display.")
                        }
                        return
                    }
                    "tablet_close_display" -> {
                        Log.i(TAG, "Tablet close display")
                        taskExecutor?.closeDisplay()
                        return
                    }
                    "tablet_task" -> {
                        val type = json.get("type")?.asString ?: return
                        val data = json.get("data")?.asString ?: ""
                        val wait = json.get("wait_seconds")?.asInt ?: 0
                        Log.i(TAG, "Tablet task: $type")
                        taskExecutor?.runTask(type, data, wait)
                        return
                    }
                    "tablet_cancel" -> {
                        Log.i(TAG, "Tablet cancel task")
                        taskExecutor?.cancelTask()
                        return
                    }
                    "tablet_play_sound" -> {
                        val sound = json.get("sound")?.asString ?: "beep"
                        Log.i(TAG, "Tablet play sound: $sound")
                        taskExecutor?.playAlertSound(sound)
                        return
                    }
                    "tablet_refresh_map" -> {
                        Log.i(TAG, ">>> Manual map refresh requested by Flutter")
                        robotClient.refreshMap()
                        return
                    }
                    // Handle rosbridge ping - respond with pong to keep connection alive
                    "ping" -> {
                        try {
                            send("""{"op":"pong"}""")
                        } catch (e: Exception) {
                            Log.w(TAG, "Failed to send pong: ${e.message}")
                        }
                        return
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error parsing message: ${e.message}")
                // Not a tablet command, forward to robot
            }

            Log.d(TAG, "Relaying: ${payload.take(100)}...")
            robotClient.send(payload)
        }

        override fun onPong(pong: WebSocketFrame) {}

        override fun onException(exception: IOException) {
            Log.e(TAG, "WebSocket error: ${exception.message}")
            onConnectionChanged(this, false)
        }
    }
}
