package com.opendroids.tourbot.data.model

/**
 * Represents the current state of the tour.
 */
sealed class TourState {
    /**
     * The robot is idle and ready to start a tour.
     */
    object Idle : TourState()

    /**
     * The robot is navigating to a specific waypoint.
     * @property targetWaypoint The waypoint the robot is moving towards.
     */
    data class Navigating(val targetWaypoint: Waypoint) : TourState()

    /**
     * The robot has arrived and is presenting the script.
     * @property currentWaypoint The waypoint where the robot is currently located.
     */
    data class Speaking(val currentWaypoint: Waypoint) : TourState()

    /**
     * The tour has been successfully completed.
     */
    object Completed : TourState()

    /**
     * An error occurred during the tour.
     * @property message The error message describing what went wrong.
     */
    data class Error(val message: String) : TourState()
}