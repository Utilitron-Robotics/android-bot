package com.opendroids.tourbot.data.model

data class Waypoint(
    val id: String,
    val name: String,
    val script: String = "",
    val audioResId: Int = 0 // Added audioResId property
)
