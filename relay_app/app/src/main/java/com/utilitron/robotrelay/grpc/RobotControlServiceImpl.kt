package com.utilitron.robotrelay.grpc

import android.content.Context
import android.util.Log
import com.utilitron.robotrelay.service.RobotWebSocketClient
import com.utilitron.robotrelay.service.RelayServer
import com.utilitron.robotrelay.service.ConnectionState
import com.utilitron.robotrelay.service.WebRtcManager
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
    private val context: Context
) : RobotControlGrpc.RobotControlImplBase() {

    companion object {
        private const val TAG = "RobotControlGRPC"
        private const val HEARTBEAT_INTERVAL_MS = 1000L
        private const val STREAM_STABILIZE_DELAY_MS = 100L
    }

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val activeStreams = ConcurrentHashMap<String, StreamObserver<ServerMessage>>()
    private val webRtcManagers = ConcurrentHashMap<String, WebRtcManager>()


    /**
     * Bidirectional streaming - the CORE of gRPC communication
     * One persistent connection for all commands and status updates
     */
    override fun controlStream(
        responseObserver: StreamObserver<ServerMessage>
    ): StreamObserver<ClientMessage> {

        val streamId = System.currentTimeMillis().toString()
        activeStreams[streamId] = responseObserver

        Log.i(TAG, "New gRPC stream connected: $streamId")

        // Initialize WebRTC Manager for this stream
        val webRtcManager = WebRtcManager(context, robotClient) { signal ->
            val serverMessage = ServerMessage.newBuilder().setWebrtcSignal(signal).build()
            responseObserver.onNext(serverMessage)
        }
        webRtcManagers[streamId] = webRtcManager

        // Start heartbeat for this stream
        val heartbeatJob = scope.launch {
            delay(STREAM_STABILIZE_DELAY_MS)
            while (isActive) {
                try {
                    val heartbeat = buildHeartbeat()
                    val message = ServerMessage.newBuilder()
                        .setHeartbeat(heartbeat)
                        .build()
                    responseObserver.onNext(message)
                    delay(HEARTBEAT_INTERVAL_MS)
                } catch (e: Exception) {
                    Log.e(TAG, "Heartbeat failed: ${e.message}")
                    break
                }
            }
        }

        // Subscribe to robot status updates
        val statusJob = scope.launch {
            robotClient.robotStatus.collect { status ->
                if (status != null) {
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
                        .build()

                    val message = ServerMessage.newBuilder()
                        .setRobotStatus(robotStatus)
                        .build()

                    try {
                        responseObserver.onNext(message)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to send status update: ${e.message}")
                    }
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
                        Log.d(TAG, "Received WebRTCSignal from client")
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

            // Send result back to stream
            val result = CommandResult.newBuilder()
                .setCommandId(command.id)
                .setStatus(if (success) "success" else "failed")
                .setMessage(command.type)
                .build()

            val message = ServerMessage.newBuilder()
                .setCommandResult(result)
                .build()

            activeStreams[streamId]?.onNext(message)
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
            }
            BufferControl.ControlCase.PAUSE -> {
                // Pause buffer execution
                Log.i(TAG, "Pausing buffer")
            }
            BufferControl.ControlCase.RESUME -> {
                // Resume buffer execution
                Log.i(TAG, "Resuming buffer")
            }
            BufferControl.ControlCase.SKIP -> {
                // Skip current command
                Log.i(TAG, "Skipping current command")
            }
            BufferControl.ControlCase.CLEAR -> {
                // Clear all commands
                Log.i(TAG, "Clearing buffer")
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
        activeStreams.remove(streamId)
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