package com.opendroids.tourbot.data.model

/**
 * Represents a stop on the tour.
 *
 * @property id Unique identifier for the waypoint (e.g., "armin", "empty_1")
 * @property scriptContent The text script to be displayed/read for this waypoint
 * @property audioResourceId The Android resource ID for the audio file associated with this waypoint
 */
data class Waypoint(
    val id: String,
    val scriptContent: String,
    val audioResourceId: Int
)