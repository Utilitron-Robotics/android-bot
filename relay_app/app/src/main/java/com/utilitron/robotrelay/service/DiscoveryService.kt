package com.utilitron.robotrelay.service

import android.util.Log
import com.google.gson.Gson
import kotlinx.coroutines.*
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
    }

    private val gson = Gson()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var socket: DatagramSocket? = null
    private var isRunning = false

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

    fun stop() {
        isRunning = false
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
