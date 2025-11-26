package com.opendroids.tourbot.data.model

import androidx.annotation.RawRes

data class Waypoint(
    val id: String,
    val scriptContent: String,
    @RawRes val audioResId: Int = 0
)
