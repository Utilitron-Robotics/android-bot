package com.smait.robotrelay.grpc

import android.util.Log
import com.smait.robotrelay.service.RobotWebSocketClient
import com.smait.robotrelay.service.RelayServer
import io.grpc.stub.StreamObserver
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import java.util.concurrent.ConcurrentHashMap
import robotcontrol.RobotControlProto.*
import robotcontrol.RobotControlGrpc

/**
 * gRPC service implementation for robot control
 * Replaces fragile WebSocket with robust WAN-ready protocol
 */
class RobotControlServiceImpl(
    private val robotClient: RobotWebSocketClient,
    private val taskExecutor: RelayServer.TaskExecutor?
) : RobotControlGrpc.RobotControlImplBase() {

    companion object {
        private const val TAG = "RobotControlGRPC"
        private const val HEARTBEAT_INTERVAL_MS = 1000L
    }

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val activeStreams = ConcurrentHashMap<String, StreamObserver<ServerMessage>>()

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

        // Start heartbeat for this stream
        val heartbeatJob = scope.launch {
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
            robotClient.status.collect { status ->
                val robotStatus = RobotStatus.newBuilder()
                    .setConnected(robotClient.isConnected.value)
                    .setNavStatus(status.navStatus)
                    .setNavGoal(status.currentGoal ?: "")
                    .setBattery(status.batteryPercent)
                    .setSafetyZone(status.safetyZone ?: "CLEAR")
                    .setPose(Pose2D.newBuilder()
                        .setX(status.position?.x ?: 0.0)
                        .setY(status.position?.y ?: 0.0)
                        .setTheta(status.position?.theta ?: 0.0)
                        .build())
                    .setLinearVelocity(status.velocity?.linear?.x ?: 0.0)
                    .setAngularVelocity(status.velocity?.angular?.z ?: 0.0)
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

        return object : StreamObserver<ClientMessage> {
            override fun onNext(value: ClientMessage) {
                when (value.messageCase) {
                    ClientMessage.MessageCase.COMMAND -> handleCommand(value.command, streamId)
                    ClientMessage.MessageCase.BUFFER_CONTROL -> handleBufferControl(value.bufferControl)
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
                    robotClient.callService("/poi", mapOf("poi" to waypoint))
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
        val status = robotClient.latestStatus.value

        return Heartbeat.newBuilder()
            .setTimestamp(System.currentTimeMillis())
            .setRobot(RobotStatus.newBuilder()
                .setConnected(robotClient.isConnected.value)
                .setNavStatus(status.navStatus)
                .setNavGoal(status.currentGoal ?: "")
                .setBattery(status.batteryPercent)
                .setSafetyZone(status.safetyZone ?: "CLEAR")
                .setPose(Pose2D.newBuilder()
                    .setX(status.position?.x ?: 0.0)
                    .setY(status.position?.y ?: 0.0)
                    .setTheta(status.position?.theta ?: 0.0)
                    .build())
                .setLinearVelocity(status.velocity?.linear?.x ?: 0.0)
                .setAngularVelocity(status.velocity?.angular?.z ?: 0.0)
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
        jobs.forEach { it.cancel() }
    }

    fun shutdown() {
        scope.cancel()
        activeStreams.clear()
    }
}