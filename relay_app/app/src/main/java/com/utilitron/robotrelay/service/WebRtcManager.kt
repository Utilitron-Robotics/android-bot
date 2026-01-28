package com.utilitron.robotrelay.service

import android.content.Context
import android.util.Log
import com.google.gson.Gson
import com.utilitron.robotrelay.grpc.RobotControlProto.WebRTCSignal
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import org.webrtc.*
import java.nio.ByteBuffer
import java.util.zip.Deflater

// NOTE: This file is written assuming the protobuf classes have been regenerated
// after the .proto file modification. The build process must be run for this
// code to compile.

/**
 * Manages the WebRTC connection and data channel for streaming map data.
 */
class WebRtcManager(
    private val context: Context,
    private val robotWebSocketClient: RobotWebSocketClient,
    private val signalingSender: (signal: WebRTCSignal) -> Unit
) {

    companion object {
        private const val TAG = "WebRtcManager"
        private const val MAP_DATA_CHANNEL_NAME = "map_data_channel"
        private const val DEPTH_DATA_CHANNEL_NAME = "depth_data_channel"
    }

    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    private var peerConnectionFactory: PeerConnectionFactory? = null
    private var peerConnection: PeerConnection? = null
    private var mapDataChannel: DataChannel? = null
    private var depthDataChannel: DataChannel? = null
    private val gson = Gson()

    private val iceServers = listOf(
        PeerConnection.IceServer.builder("stun:stun.l.google.com:19302").createIceServer()
    )

    private val peerConnectionObserver = object : PeerConnection.Observer {
        override fun onSignalingChange(p0: PeerConnection.SignalingState?) {
            Log.d(TAG, "onSignalingChange: $p0")
        }

        override fun onIceConnectionChange(newState: PeerConnection.IceConnectionState?) {
            Log.d(TAG, "onIceConnectionChange: $newState")
        }

        override fun onIceConnectionReceivingChange(p0: Boolean) {}

        override fun onIceGatheringChange(newState: PeerConnection.IceGatheringState?) {
            Log.d(TAG, "onIceGatheringChange: $newState")
        }

        override fun onIceCandidate(candidate: IceCandidate?) {
            if (candidate != null) {
                Log.d(TAG, "onIceCandidate: Sending ICE candidate")
                val signal = WebRTCSignal.newBuilder()
                    .setCandidate(candidate.sdp)
                    .setCandidateMid(candidate.sdpMid)
                    .setCandidateMlineIndex(candidate.sdpMLineIndex)
                    .build()
                signalingSender(signal)
            }
        }

        override fun onIceCandidatesRemoved(p0: Array<out IceCandidate>?) {}

        override fun onAddStream(p0: MediaStream?) {}

        override fun onRemoveStream(p0: MediaStream?) {}

        override fun onDataChannel(dataChannel: DataChannel?) {
            Log.d(TAG, "onDataChannel: ${dataChannel?.label()}")
            // This side (the sender) shouldn't receive data channels, but log if we do.
        }

        override fun onRenegotiationNeeded() {
            Log.d(TAG, "onRenegotiationNeeded")
        }

        override fun onAddTrack(p0: RtpReceiver?, p1: Array<out MediaStream>?) {}
    }

    init {
        initializeFactory()
    }

    private fun initializeFactory() {
        val options = PeerConnectionFactory.InitializationOptions.builder(context)
            .createInitializationOptions()
        PeerConnectionFactory.initialize(options)
        peerConnectionFactory = PeerConnectionFactory.builder().createPeerConnectionFactory()
    }

    fun startMapStream() {
        if (peerConnectionFactory == null) {
            Log.e(TAG, "PeerConnectionFactory is not initialized!")
            return
        }
        Log.i(TAG, "Starting map stream: creating PeerConnection")

        val rtcConfig = PeerConnection.RTCConfiguration(iceServers).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
        }
        peerConnection = peerConnectionFactory!!.createPeerConnection(rtcConfig, peerConnectionObserver)

        if (peerConnection == null) {
            Log.e(TAG, "Failed to create PeerConnection")
            return
        }

        // Create the data channel for sending map data
        val mapChannelInit = DataChannel.Init().apply {
            ordered = true // Ensure map chunks arrive in order
            negotiated = false
            id = 0
        }
        mapDataChannel = peerConnection!!.createDataChannel(MAP_DATA_CHANNEL_NAME, mapChannelInit)
        mapDataChannel?.registerObserver(object : DataChannel.Observer {
            override fun onBufferedAmountChange(p0: Long) {}
            override fun onStateChange() {
                Log.d(TAG, "MapDataChannel state changed: ${mapDataChannel?.state()}")
                if (mapDataChannel?.state() == DataChannel.State.OPEN) {
                    Log.v(TAG, "WebRTC Map Data Channel OPEN. Starting map data subscription.")
                    subscribeToMapData()
                }
            }
            override fun onMessage(p0: DataChannel.Buffer?) {}
        })

        // Create the data channel for sending depth camera images
        val depthChannelInit = DataChannel.Init().apply {
            ordered = false // Depth frames can arrive out of order, we want latest
            negotiated = false
            id = 1
        }
        depthDataChannel = peerConnection!!.createDataChannel(DEPTH_DATA_CHANNEL_NAME, depthChannelInit)
        depthDataChannel?.registerObserver(object : DataChannel.Observer {
            override fun onBufferedAmountChange(p0: Long) {}
            override fun onStateChange() {
                Log.d(TAG, "DepthDataChannel state changed: ${depthDataChannel?.state()}")
                if (depthDataChannel?.state() == DataChannel.State.OPEN) {
                    Log.v(TAG, "WebRTC Depth Data Channel OPEN. Starting depth data subscription.")
                    subscribeToDepthData()
                }
            }
            override fun onMessage(p0: DataChannel.Buffer?) {}
        })

        // Create and send offer
        peerConnection!!.createOffer(object : SdpObserver {
            override fun onCreateSuccess(sdp: SessionDescription?) {
                if (sdp != null) {
                    peerConnection!!.setLocalDescription(object : SdpObserver {
                        override fun onCreateSuccess(p0: SessionDescription?) {}
                        override fun onSetSuccess() {
                            Log.d(TAG, "setLocalDescription success. Sending offer.")
                            val signal = WebRTCSignal.newBuilder().setSdp(sdp.description).build()
                            signalingSender(signal)
                        }
                        override fun onCreateFailure(p0: String?) {}
                        override fun onSetFailure(p0: String?) {
                            Log.e(TAG, "setLocalDescription failed: $p0")
                        }
                    }, sdp)
                }
            }
            override fun onSetSuccess() {}
            override fun onCreateFailure(p0: String?) {
                Log.e(TAG, "createOffer failed: $p0")
            }
            override fun onSetFailure(p0: String?) {}
        }, MediaConstraints())
    }

    fun handleSignal(signal: WebRTCSignal) {
        when (signal.signalCase) {
            WebRTCSignal.SignalCase.SDP -> {
                Log.d(TAG, "handleSignal: Received SDP Answer")
                val sdp = SessionDescription(SessionDescription.Type.ANSWER, signal.sdp)
                peerConnection?.setRemoteDescription(object : SdpObserver {
                    override fun onCreateSuccess(p0: SessionDescription?) {}
                    override fun onSetSuccess() {
                        Log.d(TAG, "setRemoteDescription success.")
                    }
                    override fun onCreateFailure(p0: String?) {}
                    override fun onSetFailure(p0: String?) {
                        Log.e(TAG, "setRemoteDescription failed: $p0")
                    }
                }, sdp)
            }
            WebRTCSignal.SignalCase.CANDIDATE -> {
                Log.d(TAG, "handleSignal: Received ICE Candidate")
                val candidate = IceCandidate(signal.candidateMid, signal.candidateMlineIndex, signal.candidate)
                peerConnection?.addIceCandidate(candidate)
            }
            else -> {
                Log.w(TAG, "handleSignal: Unknown signal type")
            }
        }
    }

    private fun subscribeToMapData() {
        scope.launch {
            robotWebSocketClient.incomingMessages
                .filter { it.contains("\"topic\":\"/map\"") }
                .map { jsonString ->
                    // Instead of sending raw JSON, parse out the critical data
                    val mapMessage = gson.fromJson(jsonString, MapMessage::class.java)
                    mapMessage.msg?.data
                }
                .filter { it != null }
                .collect { mapData ->
                    // Compress and send the map data
                    val compressedData = compress(mapData!!)
                    val buffer = ByteBuffer.wrap(compressedData)
                    mapDataChannel?.send(DataChannel.Buffer(buffer, true))
                    Log.d(TAG, "Sent compressed map data: ${compressedData.size} bytes")
                }
        }
    }

    private fun subscribeToDepthData() {
        scope.launch {
            robotWebSocketClient.incomingMessages
                .filter { it.contains("\"topic\":\"/upcamera/depth/image_raw\"") }
                .collect { jsonString ->
                    try {
                        // Parse the depth image message
                        val depthMessage = gson.fromJson(jsonString, DepthImageMessage::class.java)
                        val msg = depthMessage.msg ?: return@collect

                        val width = msg.width ?: 0
                        val height = msg.height ?: 0
                        val encoding = msg.encoding ?: ""
                        val dataBase64 = msg.data ?: return@collect

                        if (width <= 0 || height <= 0) return@collect

                        // Create a compact message with metadata + raw data
                        // Format: [width:2][height:2][encoding_len:1][encoding:N][data...]
                        val encodingBytes = encoding.toByteArray(Charsets.UTF_8)
                        val imageBytes = android.util.Base64.decode(dataBase64, android.util.Base64.DEFAULT)

                        val headerSize = 2 + 2 + 1 + encodingBytes.size
                        val packet = ByteArray(headerSize + imageBytes.size)

                        // Write header
                        packet[0] = (width shr 8).toByte()
                        packet[1] = width.toByte()
                        packet[2] = (height shr 8).toByte()
                        packet[3] = height.toByte()
                        packet[4] = encodingBytes.size.toByte()
                        System.arraycopy(encodingBytes, 0, packet, 5, encodingBytes.size)
                        System.arraycopy(imageBytes, 0, packet, headerSize, imageBytes.size)

                        val buffer = ByteBuffer.wrap(packet)
                        depthDataChannel?.send(DataChannel.Buffer(buffer, true))
                        Log.d(TAG, "Sent depth image: ${width}x${height} $encoding (${packet.size} bytes)")
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to process depth image: ${e.message}")
                    }
                }
        }
    }

    private fun compress(data: List<Int>): ByteArray {
        // The OccupancyGrid data is a list of integers from -1 to 100.
        // Converting to ByteArray is more efficient than string representation.
        val byteArray = data.map { it.toByte() }.toByteArray()
        val deflater = Deflater()
        deflater.setInput(byteArray)
        deflater.finish()
        val output = ByteArray(byteArray.size)
        val compressedSize = deflater.deflate(output)
        return output.copyOf(compressedSize)
    }

    fun close() {
        Log.i(TAG, "Closing WebRTC Manager")
        mapDataChannel?.close()
        depthDataChannel?.close()
        peerConnection?.close()
        peerConnectionFactory?.dispose()
        peerConnection = null
        peerConnectionFactory = null
    }

    // Helper data class for parsing the /map message from JSON
    private data class MapMessage(val msg: MapData?)
    private data class MapData(val data: List<Int>?)

    // Helper data class for parsing depth image message from JSON
    private data class DepthImageMessage(val msg: DepthImageData?)
    private data class DepthImageData(
        val width: Int?,
        val height: Int?,
        val encoding: String?,
        val data: String?  // base64 encoded
    )
}
