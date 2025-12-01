package com.opendroids.tourbot.data.remote.model

import kotlinx.serialization.Serializable

@Serializable
data class RobotStatusMessage(
    val navStatus: Int? = null,
    val battery: Float? = null,
    val velocity: List<Float>? = null,
    val currentPoi: String? = null
)
