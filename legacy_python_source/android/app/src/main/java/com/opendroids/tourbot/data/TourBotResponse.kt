package com.opendroids.tourbot.data

import kotlinx.serialization.Serializable

@Serializable
data class TourBotResponse(
    val tourId: String,
    val movement: String,
    val arrival: String
)
