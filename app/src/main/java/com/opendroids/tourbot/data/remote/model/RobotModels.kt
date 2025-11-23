package com.opendroids.tourbot.data.remote.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Represents a command sent to the robot via WebSocket.
 * Matches the structure used in python tibo_commands.py
 */
@Serializable
data class RobotCommand(
    val op: String,
    val id: String? = null,
    val topic: String? = null,
    val type: String? = null,
    val service: String? = null,
    val args: Map<String, String>? = null,
    val msg: Map<String, String>? = null
)

/**
 * Represents a message received from the robot.
 */
@Serializable
data class RobotMessage(
    val op: String? = null,
    val topic: String? = null,
    val msg: RobotStatusMessage? = null
)

/**
 * The content payload of a robot status message.
 * Specifically tailored for /robot_status topic.
 */
@Serializable
data class RobotStatusMessage(
    @SerialName("nav_status") val navStatus: Int? = null,
    val battery: Float? = null,
    val velocity: List<Float>? = null,
    val currentPoi: String? = null // Added currentPoi field
)