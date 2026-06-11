package com.utilitron.robotrelay.service

import android.util.Log
import com.google.gson.Gson
import com.google.gson.JsonObject
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.NetworkInterface

/**
 * UDP Discovery service for relay auto-discovery.
 *
 * Listens for broadcast messages on port 9999 and responds with relay info.
 * Protocol:
 *   Request:  "UTILITRON_RELAY_DISCOVER" (broadcast to 255.255.255.255:9999)
 *   Response: JSON with relay info (unicast back to sender)
 */
class DiscoveryService(
    private val relayPort: Int = 8765,
    private val robotClient: RobotWebSocketClient? = null
) {
    companion object {
        private const val TAG = "DiscoveryService"
        const val DISCOVERY_PORT = 9999
        const val DISCOVERY_REQUEST = "UTILITRON_RELAY_DISCOVER"
        const val DISCOVERY_RESPONSE_TYPE = "UTILITRON_RELAY_RESPONSE"
        const val CHLOE_AV_TYPE = "CHLOE_AV"

        // Beacon arrives every few seconds; silence longer than this means
        // the AV service is gone and clients get told ONCE - a dead stream
        // is never republished.
        const val CHLOE_AV_STALE_MS = 10_000L
    }

    private val gson = Gson()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var socket: DatagramSocket? = null
    private var isRunning = false

    /** Chloe AV endpoint learned from her UDP beacon. Host comes from the
     *  packet source address - nothing hardcoded, networks change per floor. */
    data class ChloeAvInfo(
        val host: String,
        val port: Int,
        val videoPath: String,
        val audioPath: String,
        val cameraAvailable: Boolean,
        val name: String
    )

    // No timestamp in the data class: StateFlow equality then suppresses
    // repeat beacons, so collectors only fire on real change.
    private val _chloeAv = MutableStateFlow<ChloeAvInfo?>(null)
    val chloeAv: StateFlow<ChloeAvInfo?> = _chloeAv

    @Volatile
    private var chloeAvLastSeenMs = 0L
    private var chloeAvStaleJob: Job? = null

    data class DiscoveryResponse(
        val type: String = DISCOVERY_RESPONSE_TYPE,
        val relayHttpPort: Int,
        val relayWsPort: Int,
        val robotConnected: Boolean,
        val robotIp: String?,
        val localIps: List<String>,
        val deviceName: String,
        val version: String = "1.0"
    )

    fun start() {
        if (isRunning) return
        isRunning = true

        scope.launch {
            try {
                socket = DatagramSocket(DISCOVERY_PORT)
                socket?.broadcast = true
                Log.i(TAG, "Discovery service started on port $DISCOVERY_PORT")

                val buffer = ByteArray(1024)
                while (isRunning && isActive) {
                    try {
                        val packet = DatagramPacket(buffer, buffer.size)
                        socket?.receive(packet)

                        val message = String(packet.data, 0, packet.length).trim()
                        Log.d(TAG, "Received: '$message' from ${packet.address}:${packet.port}")

                        if (message == DISCOVERY_REQUEST) {
                            // Send response back to sender
                            val response = createResponse()
                            val responseJson = gson.toJson(response)
                            val responseBytes = responseJson.toByteArray()

                            val responsePacket = DatagramPacket(
                                responseBytes,
                                responseBytes.size,
                                packet.address,
                                packet.port
                            )
                            socket?.send(responsePacket)
                            Log.i(TAG, "Sent discovery response to ${packet.address}:${packet.port}")
                        } else if (message.startsWith("{")) {
                            handleJsonBeacon(message, packet.address?.hostAddress)
                        }
                    } catch (e: Exception) {
                        if (isRunning) {
                            Log.w(TAG, "Error receiving packet: ${e.message}")
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Discovery service error: ${e.message}")
            }
        }
    }

    /** Parse a JSON beacon on the discovery port. Currently: CHLOE_AV. */
    private fun handleJsonBeacon(message: String, senderHost: String?) {
        if (senderHost == null) return
        try {
            val json = gson.fromJson(message, JsonObject::class.java)
            if (json.get("type")?.asString != CHLOE_AV_TYPE) return

            chloeAvLastSeenMs = System.currentTimeMillis()
            val info = ChloeAvInfo(
                host = senderHost,
                port = json.get("port")?.asInt ?: return,
                videoPath = json.get("video_path")?.asString ?: "/video.mjpg",
                audioPath = json.get("audio_path")?.asString ?: "/audio.wav",
                cameraAvailable = json.get("camera")?.asBoolean ?: false,
                name = json.get("name")?.asString ?: "chloe"
            )
            if (_chloeAv.value != info) {
                Log.i(TAG, "Chloe AV beacon: $info")
            }
            _chloeAv.value = info
            armChloeAvStaleCheck()
        } catch (e: Exception) {
            Log.d(TAG, "Ignoring malformed JSON beacon: ${e.message}")
        }
    }

    /** One pending stale-check per beacon; fires only if beacons stop. */
    private fun armChloeAvStaleCheck() {
        chloeAvStaleJob?.cancel()
        chloeAvStaleJob = scope.launch {
            delay(CHLOE_AV_STALE_MS)
            if (System.currentTimeMillis() - chloeAvLastSeenMs >= CHLOE_AV_STALE_MS) {
                Log.w(TAG, "Chloe AV beacon stale - marking unavailable")
                _chloeAv.value = null
            }
        }
    }

    fun stop() {
        isRunning = false
        chloeAvStaleJob?.cancel()
        try {
            socket?.close()
        } catch (e: Exception) {
            Log.w(TAG, "Error closing socket: ${e.message}")
        }
        socket = null
    }

    fun destroy() {
        stop()
        scope.cancel()
    }

    private fun createResponse(): DiscoveryResponse {
        return DiscoveryResponse(
            relayHttpPort = relayPort,
            relayWsPort = relayPort + 1,
            robotConnected = robotClient?.connectionState?.value == ConnectionState.CONNECTED,
            robotIp = robotClient?.robotIp,
            localIps = getLocalIpAddresses(),
            deviceName = android.os.Build.MODEL
        )
    }

    /**
     * Get all local IP addresses (non-loopback)
     */
    private fun getLocalIpAddresses(): List<String> {
        val ips = mutableListOf<String>()
        try {
            val interfaces = NetworkInterface.getNetworkInterfaces()
            while (interfaces.hasMoreElements()) {
                val iface = interfaces.nextElement()
                if (iface.isLoopback || !iface.isUp) continue

                val addresses = iface.inetAddresses
                while (addresses.hasMoreElements()) {
                    val addr = addresses.nextElement()
                    if (addr is java.net.Inet4Address && !addr.isLoopbackAddress) {
                        ips.add(addr.hostAddress ?: continue)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting local IPs: ${e.message}")
        }
        return ips
    }
}
