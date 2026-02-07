package com.utilitron.robotrelay.grpc

import android.content.Context
import android.util.Log
import com.utilitron.robotrelay.service.RobotWebSocketClient
import com.utilitron.robotrelay.service.RelayServer
import com.utilitron.robotrelay.service.ConnectionState
import com.utilitron.robotrelay.service.WebRtcManager
import com.utilitron.robotrelay.service.CommandBuffer
import io.grpc.stub.StreamObserver
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import java.util.concurrent.ConcurrentHashMap
import com.utilitron.robotrelay.grpc.RobotControlProto.*
import com.utilitron.robotrelay.grpc.RobotControlGrpc

/**
 * gRPC service implementation for robot control
 * Replaces fragile WebSocket with robust WAN-ready protocol
 */
class RobotControlServiceImpl(
    private val robotClient: RobotWebSocketClient,
    private val taskExecutor: RelayServer.TaskExecutor?,
    private val context: Context,
    private val commandBuffer: CommandBuffer? = null
) : RobotControlGrpc.RobotControlImplBase() {

    companion object {
        private const val TAG = "RobotControlGRPC"
        private const val HEARTBEAT_INTERVAL_MS = 1000L  // Heartbeat: the one allowed hardcoded interval
    }

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val activeStreams = ConcurrentHashMap<String, StreamObserver<ServerMessage>>()
    private val streamActive = ConcurrentHashMap<String, Boolean>()  // Track stream lifecycle
    private val webRtcManagers = ConcurrentHashMap<String, WebRtcManager>()

    // Mutex to synchronize gRPC stream writes - prevents DATA_LOSS errors from concurrent onNext() calls
    private val streamLocks = ConcurrentHashMap<String, Any>()


    /**
     * Bidirectional streaming - the CORE of gRPC communication
     * One persistent connection for all commands and status updates
     */
    override fun controlStream(
        responseObserver: StreamObserver<ServerMessage>
    ): StreamObserver<ClientMessage> {

        val streamId = System.currentTimeMillis().toString()
        activeStreams[streamId] = responseObserver
        streamActive[streamId] = true
        streamLocks[streamId] = Any()  // Create lock for this stream

        Log.i(TAG, "New gRPC stream connected: $streamId")

        // Thread-safe send helper - prevents DATA_LOSS from concurrent onNext() calls
        fun safeSend(message: ServerMessage): Boolean {
            if (streamActive[streamId] != true) return false
            val lock = streamLocks[streamId] ?: return false
            return try {
                synchronized(lock) {
                    responseObserver.onNext(message)
                }
                true
            } catch (e: Exception) {
                Log.e(TAG, "Failed to send message: ${e.message}")
                streamActive[streamId] = false
                false
            }
        }

        // Initialize WebRTC Manager for this stream
        val webRtcManager = WebRtcManager(context, robotClient) { signal ->
            val serverMessage = ServerMessage.newBuilder().setWebrtcSignal(signal).build()
            safeSend(serverMessage)
        }
        webRtcManagers[streamId] = webRtcManager

        // Start heartbeat for this stream — send first beat immediately
        val heartbeatJob = scope.launch {
            while (isActive && streamActive[streamId] == true) {
                val heartbeat = buildHeartbeat()
                val message = ServerMessage.newBuilder()
                    .setHeartbeat(heartbeat)
                    .build()
                if (!safeSend(message)) break
                delay(HEARTBEAT_INTERVAL_MS)
            }
        }

        // Subscribe to robot status updates
        val statusJob = scope.launch {
            robotClient.robotStatus.collect { status ->
                if (status != null && streamActive[streamId] == true) {
                    val now = System.currentTimeMillis()
                    val dataAge = if (robotClient.lastRobotDataTime > 0)
                        now - robotClient.lastRobotDataTime else -1L

                    // LIDAR-specific staleness: if no /scan data for 3s, signal -1
                    val lidarAge = if (robotClient.lastLidarTime > 0)
                        now - robotClient.lastLidarTime else -1L
                    val minRange = if (lidarAge < 0 || lidarAge > 3000)
                        -1.0 else robotClient.minFrontDistance.toDouble()

                    val robotStatus = RobotStatus.newBuilder()
                        .setConnected(robotClient.connectionState.value == ConnectionState.CONNECTED)
                        .setNavStatus(status.navStatus)
                        .setNavGoal(status.currentGoalName ?: "")
                        .setBattery(status.battery)
                        .setSafetyZone(status.safetyZone.name)
                        .setPose(Pose2D.newBuilder()
                            .setX(status.x)
                            .setY(status.y)
                            .setTheta(status.theta)
                            .build())
                        .setLinearVelocity(status.velocity.getOrNull(0) ?: 0.0)
                        .setAngularVelocity(status.velocity.getOrNull(1) ?: 0.0)
                        .setDataAgeMs(dataAge)
                        .setMinRangeMeters(minRange)
                        .build()

                    val message = ServerMessage.newBuilder()
                        .setRobotStatus(robotStatus)
                        .build()

                    safeSend(message)
                }
            }
        }

        return object : StreamObserver<ClientMessage> {
            override fun onNext(value: ClientMessage) {
                when (value.messageCase) {
                    ClientMessage.MessageCase.COMMAND -> handleCommand(value.command, streamId)
                    ClientMessage.MessageCase.BUFFER_CONTROL -> handleBufferControl(value.bufferControl)
                    ClientMessage.MessageCase.REQUEST_MAP_STREAM -> {
                        Log.i(TAG, "Received RequestMapStream from client")
                        webRtcManagers[streamId]?.startMapStream()
                    }
                    ClientMessage.MessageCase.WEBRTC_SIGNAL -> {
                        Log.v(TAG, "Received WebRTCSignal from client")
                        webRtcManagers[streamId]?.handleSignal(value.webrtcSignal)
                    }
                    ClientMessage.MessageCase.HEARTBEAT_REQUEST -> {} // Heartbeat already running
                    else -> Log.w(TAG, "Unknown message type: ${value.messageCase}")
                }
            }

            override fun onError(t: Throwable) {
                Log.e(TAG, "Stream error: ${t.message}")
                cleanup(streamId, heartbeatJob, statusJob)
            }

            override fun onCompleted() {
                Log.i(TAG, "Stream completed: $streamId")
                cleanup(streamId, heartbeatJob, statusJob)
                responseObserver.onCompleted()
            }
        }
    }

    /**
     * Simple unary RPC for one-off commands
     */
    override fun sendCommand(
        request: Command,
        responseObserver: StreamObserver<CommandResponse>
    ) {
        scope.launch {
            try {
                val success = executeCommand(request)
                val response = CommandResponse.newBuilder()
                    .setSuccess(success)
                    .setCommandId(request.id)
                    .setMessage(if (success) "Command executed" else "Command failed")
                    .build()
                responseObserver.onNext(response)
                responseObserver.onCompleted()
            } catch (e: Exception) {
                Log.e(TAG, "Command execution failed: ${e.message}")
                responseObserver.onError(e)
            }
        }
    }

    /**
     * Server-streaming for continuous heartbeat
     */
    override fun streamHeartbeat(
        request: HeartbeatRequest,
        responseObserver: StreamObserver<Heartbeat>
    ) {
        scope.launch {
            while (isActive) {
                try {
                    val heartbeat = buildHeartbeat()
                    responseObserver.onNext(heartbeat)
                    delay(HEARTBEAT_INTERVAL_MS)
                } catch (e: Exception) {
                    Log.e(TAG, "Heartbeat stream failed: ${e.message}")
                    responseObserver.onError(e)
                    break
                }
            }
        }
    }

    private fun handleCommand(command: Command, streamId: String) {
        scope.launch {
            val success = executeCommand(command)

            // Send result back to stream (only if still active)
            if (streamActive[streamId] == true) {
                val result = CommandResult.newBuilder()
                    .setCommandId(command.id)
                    .setStatus(if (success) "success" else "failed")
                    .setMessage(command.type)
                    .build()

                val message = ServerMessage.newBuilder()
                    .setCommandResult(result)
                    .build()

                // Use synchronized send to prevent DATA_LOSS from concurrent writes
                val lock = streamLocks[streamId]
                val observer = activeStreams[streamId]
                if (lock != null && observer != null) {
                    try {
                        synchronized(lock) {
                            observer.onNext(message)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to send command result: ${e.message}")
                        streamActive[streamId] = false
                    }
                }
            }
        }
    }

    private suspend fun executeCommand(command: Command): Boolean {
        return try {
            when (command.type) {
                "navigate" -> {
                    val waypoint = command.dataMap["waypoint"] ?: return false
                    // Navigate using rosbridge protocol
                    val navMsg = """{"op":"call_service","service":"/poi","args":{"poi":"$waypoint"}}"""
                    robotClient.send(navMsg)
                    true
                }
                "velocity" -> {
                    val linear = command.dataMap["linear"]?.toDoubleOrNull() ?: 0.0
                    val angular = command.dataMap["angular"]?.toDoubleOrNull() ?: 0.0
                    robotClient.sendVelocity(linear, angular)
                    true
                }
                "stop" -> {
                    robotClient.sendVelocity(0.0, 0.0)
                    true
                }
                "cancel" -> {
                    robotClient.cancelNavigation()
                    true
                }
                "speak" -> {
                    val text = command.dataMap["text"] ?: return false
                    taskExecutor?.speakText(text)
                    true
                }
                "display" -> {
                    val url = command.dataMap["url"] ?: return false
                    taskExecutor?.displayUrl(url)
                    true
                }
                else -> {
                    Log.w(TAG, "Unknown command type: ${command.type}")
                    false
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Command execution error: ${e.message}")
            false
        }
    }

    private fun handleBufferControl(control: BufferControl) {
        when (control.controlCase) {
            BufferControl.ControlCase.LOAD -> {
                // Load commands into buffer
                Log.i(TAG, "Loading ${control.load.commandsList.size} commands")
                // TODO: Implement command loading via gRPC
            }
            BufferControl.ControlCase.PAUSE -> {
                Log.i(TAG, "gRPC: Pausing buffer")
                commandBuffer?.pause()
            }
            BufferControl.ControlCase.RESUME -> {
                Log.i(TAG, "gRPC: Resuming buffer")
                commandBuffer?.resume()
            }
            BufferControl.ControlCase.SKIP -> {
                Log.i(TAG, "gRPC: Skipping current command")
                commandBuffer?.skip()
            }
            BufferControl.ControlCase.CLEAR -> {
                Log.i(TAG, "gRPC: Clearing buffer")
                commandBuffer?.clear()
            }
            else -> Log.w(TAG, "Unknown buffer control: ${control.controlCase}")
        }
    }

    private fun buildHeartbeat(): Heartbeat {
        val status = robotClient.robotStatus.value
        val isConnected = robotClient.connectionState.value == ConnectionState.CONNECTED

        return Heartbeat.newBuilder()
            .setTimestamp(System.currentTimeMillis())
            .setRobot(RobotStatus.newBuilder()
                .setConnected(isConnected)
                .setNavStatus(status?.navStatus ?: 0)
                .setNavGoal(status?.currentGoalName ?: "")
                .setBattery(status?.battery ?: 0)
                .setSafetyZone(status?.safetyZone?.name ?: "CLEAR")
                .setPose(Pose2D.newBuilder()
                    .setX(status?.x ?: 0.0)
                    .setY(status?.y ?: 0.0)
                    .setTheta(status?.theta ?: 0.0)
                    .build())
                .setLinearVelocity(status?.velocity?.getOrNull(0) ?: 0.0)
                .setAngularVelocity(status?.velocity?.getOrNull(1) ?: 0.0)
                .build())
            .setBuffer(BufferState.newBuilder()
                .setPaused(false)
                .setPendingCount(0)
                .setCompletedCount(0)
                .build())
            .setCrowdConfig(CrowdConfig.newBuilder()
                .setSafeDistanceMeters(1.5)
                .setRampRate(0.2)
                .build())
            .build()
    }

    private fun cleanup(streamId: String, vararg jobs: Job) {
        streamActive[streamId] = false  // Mark inactive FIRST to stop sends
        activeStreams.remove(streamId)
        streamActive.remove(streamId)
        streamLocks.remove(streamId)  // Clean up the lock
        webRtcManagers[streamId]?.close()
        webRtcManagers.remove(streamId)
        jobs.forEach { it.cancel() }
    }

    fun shutdown() {
        scope.cancel()
        webRtcManagers.values.forEach { it.close() }
        webRtcManagers.clear()
        activeStreams.clear()
    }
}