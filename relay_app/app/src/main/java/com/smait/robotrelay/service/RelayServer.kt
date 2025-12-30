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
    private val port: Int = 8765
) {
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
            httpServer = RelayHttpServer(port, robotClient, gson)
            httpServer?.start()

            // Start WebSocket server on port + 1
            wsServer = RelayWebSocketServer(port + 1, robotClient, scope) { count ->
                _connectedClients.value = count
            }
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
    private val gson: Gson
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
            "Access-Control-Allow-Methods" to "GET, POST, OPTIONS",
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
                <h2>Endpoints:</h2>
                <ul>
                    <li>GET /status - Robot status</li>
                    <li>POST /cmd - Raw command (JSON body)</li>
                    <li>POST /velocity - {"linear": 0.2, "angular": 0.0}</li>
                    <li>POST /navigate - {"poi": "P1"}</li>
                    <li>POST /stop - Stop robot</li>
                    <li>POST /estop - {"enabled": true/false}</li>
                    <li>POST /cancel - Cancel navigation</li>
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
    private val onClientCountChanged: (Int) -> Unit
) : NanoWSD(port) {

    companion object {
        private const val TAG = "RelayWS"
    }

    private val clients = mutableListOf<WebSocket>()

    override fun openWebSocket(handshake: IHTTPSession): WebSocket {
        return RelayWebSocket(handshake, robotClient, scope) { ws, connected ->
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
        private val onConnectionChanged: (WebSocket, Boolean) -> Unit
    ) : NanoWSD.WebSocket(handshake) {

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
