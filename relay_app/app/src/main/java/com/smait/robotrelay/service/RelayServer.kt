package com.smait.robotrelay.service

import android.util.Log
import com.google.gson.Gson
import com.google.gson.JsonObject
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
    private val taskExecutor: TaskExecutor? = null
) {

    interface TaskExecutor {
        fun speakText(text: String)
        fun displayUrl(url: String)
        fun closeDisplay()
        fun runTask(type: String, data: String, waitSeconds: Int)
        fun cancelTask()
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

    fun start() {
        try {
            // Start HTTP server on port
            httpServer = RelayHttpServer(port, robotClient, gson, taskExecutor)
            httpServer?.start()

            // Start WebSocket server on port + 1
            wsServer = RelayWebSocketServer(port + 1, robotClient, scope, { count ->
                _connectedClients.value = count
            }, taskExecutor)
            wsServer?.start()

            _isRunning.value = true
            Log.i(TAG, "Relay server started on HTTP:$port, WS:${port + 1}")

            // Forward robot messages to connected WebSocket clients
            scope.launch {
                robotClient.incomingMessages.collect { message ->
                    wsServer?.broadcast(message)
                }
            }
        } catch (e: IOException) {
            Log.e(TAG, "Failed to start server: ${e.message}")
            _isRunning.value = false
        }
    }

    fun stop() {
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
    private val taskExecutor: RelayServer.TaskExecutor? = null
) : NanoHTTPD(port) {

    companion object {
        private const val TAG = "RelayHTTP"
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
            uri == "/status" && method == Method.GET -> handleGetStatus()
            uri == "/cmd" && method == Method.POST -> handleRawCommand(session)
            uri == "/velocity" && method == Method.POST -> handleVelocity(session)
            uri == "/navigate" && method == Method.POST -> handleNavigate(session)
            uri == "/stop" && method == Method.POST -> handleStop()
            uri == "/estop" && method == Method.POST -> handleEStop(session)
            uri == "/cancel" && method == Method.POST -> handleCancel()
            uri == "/info" && method == Method.GET -> handleGetInfo()
            // Task endpoints
            uri == "/speak" && method == Method.POST -> handleSpeak(session)
            uri == "/display" && method == Method.POST -> handleDisplay(session)
            uri == "/display" && method == Method.DELETE -> handleCloseDisplay()
            uri == "/task" && method == Method.POST -> handleTask(session)
            uri == "/task" && method == Method.DELETE -> handleCancelTask()
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
                <p>WebSocket: ws://[this-ip]:${(this as NanoHTTPD).listeningPort + 1}</p>
            </body>
            </html>
        """.trimIndent()
        return newFixedLengthResponse(Response.Status.OK, "text/html", html)
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
    private val taskExecutor: RelayServer.TaskExecutor? = null
) : NanoWSD(port) {

    companion object {
        private const val TAG = "RelayWS"
    }

    private val clients = mutableListOf<WebSocket>()

    override fun openWebSocket(handshake: IHTTPSession): WebSocket {
        return RelayWebSocket(handshake, robotClient, scope, taskExecutor) { ws, connected ->
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
        synchronized(clients) {
            clients.forEach { client ->
                try {
                    client.send(message)
                } catch (e: Exception) {
                    Log.e(TAG, "Broadcast error: ${e.message}")
                }
            }
        }
    }

    class RelayWebSocket(
        handshake: IHTTPSession,
        private val robotClient: RobotWebSocketClient,
        private val scope: CoroutineScope,
        private val taskExecutor: RelayServer.TaskExecutor?,
        private val onConnectionChanged: (WebSocket, Boolean) -> Unit
    ) : NanoWSD.WebSocket(handshake) {

        private val gson = com.google.gson.Gson()

        override fun onOpen() {
            Log.i(TAG, "Client connected")
            onConnectionChanged(this, true)
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

                // Log all ops that start with "tablet_" for debugging
                if (op?.startsWith("tablet_") == true) {
                    Log.i(TAG, ">>> Received tablet command: op=$op, executor=${taskExecutor != null}")
                }

                when (op) {
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
