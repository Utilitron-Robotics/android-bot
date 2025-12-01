package com.opendroids.tourbot.logic.executors

import android.util.Log
import com.opendroids.tourbot.data.ErrorLogger
import com.opendroids.tourbot.data.model.NavigationStatus
import com.opendroids.tourbot.robot.Robot
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.transformWhile
import kotlinx.coroutines.withTimeout
import javax.inject.Inject
import javax.inject.Singleton

private const val TAG = "NavigationExecutor"
private const val MAX_IDLE_MESSAGES = 50 // This might need adjustment or removal if Robot.getStatus() is used differently

@Singleton
class NavigationExecutor @Inject constructor(
    private val robot: Robot, // Changed from TourRepository to Robot
    private val errorLogger: ErrorLogger
) {

    suspend fun execute(waypointId: String): Boolean {
        Log.i(TAG, "Executing navigation to waypoint: $waypointId")
        return navigateToWaypointWithRetry(waypointId)
    }

    private suspend fun navigateToWaypointWithRetry(waypointId: String): Boolean {
        try {
            Log.i(TAG, "Initiating navigation to $waypointId...")
            val success = waitForNavigationCompletion(waypointId)

            if (success) {
                Log.i(TAG, "✓ Reached $waypointId")
                return true
            }
            
            val errorMessage = "Navigation to $waypointId failed or timed out."
            Log.w(TAG, "⚠️ $errorMessage")
            errorLogger.logError(errorMessage)
            return false

        } catch (e: Exception) {
            val errorMessage = "Exception during navigation to $waypointId: ${e.message}"
            Log.w(TAG, "⚠️ $errorMessage")
            errorLogger.logError(errorMessage, e)
            return false
        }
    }

    private suspend fun waitForNavigationCompletion(destinationName: String): Boolean {
        Log.d(TAG, "waitForNavigationCompletion: Starting for $destinationName")

        return try {
            withTimeout(300_000) { // 5 minutes timeout
                robot.navigateTo(destinationName)
                    .transformWhile { status ->
                        when (status) {
                            NavigationStatus.NAVIGATING -> {
                                Log.i(TAG, "🚶 Robot moving to $destinationName...")
                                emit(false) // Continue waiting, but don't consider it a final success yet
                                true // Continue collecting
                            }
                            NavigationStatus.SUCCEEDED -> {
                                Log.i(TAG, "✓ Arrived at $destinationName")
                                emit(true)
                                false // Stop collecting (Success)
                            }
                            NavigationStatus.FAILED -> {
                                val errorMessage = "Navigation to $destinationName failed."
                                Log.e(TAG, "❌ $errorMessage")
                                errorLogger.logError(errorMessage)
                                emit(false)
                                false // Stop collecting (Fail)
                            }
                        }
                    }.first() // Get the first emitted value (true for success, false for failure)
            }
        } catch (e: TimeoutCancellationException) {
            val errorMessage = "Navigation timed out for $destinationName"
            Log.e(TAG, errorMessage)
            errorLogger.logError(errorMessage, e)
            false
        }
    }
}
