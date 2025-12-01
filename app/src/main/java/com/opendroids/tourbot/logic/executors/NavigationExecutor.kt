package com.opendroids.tourbot.logic.executors

import android.util.Log
import com.opendroids.tourbot.data.ErrorLogger
import com.opendroids.tourbot.data.TourRepository
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.flow.transformWhile
import kotlinx.coroutines.withTimeout
import javax.inject.Inject
import javax.inject.Singleton

private const val TAG = "NavigationExecutor"
private const val MAX_IDLE_MESSAGES = 50

@Singleton
class NavigationExecutor @Inject constructor(
    private val tourRepository: TourRepository,
    private val errorLogger: ErrorLogger
) {

    suspend fun execute(waypointId: String): Boolean {
        Log.i(TAG, "Executing navigation to waypoint: $waypointId")
        return navigateToWaypointWithRetry(waypointId)
    }

    private suspend fun navigateToWaypointWithRetry(marker: String): Boolean {
        try {
            tourRepository.goTo(marker)
            Log.i(TAG, "Waiting for arrival at $marker...")
            val success = waitForArrival(marker)

            if (success) {
                Log.i(TAG, "✓ Reached $marker")
                return true
            }
            
            val errorMessage = "Navigation to $marker failed or timed out."
            Log.w(TAG, "⚠️ $errorMessage")
            errorLogger.logError(errorMessage)
            return false

        } catch (e: Exception) {
            val errorMessage = "Exception during navigation to $marker: ${e.message}"
            Log.w(TAG, "⚠️ $errorMessage")
            errorLogger.logError(errorMessage, e)
            return false
        }
    }

    private suspend fun waitForArrival(destinationName: String): Boolean {
        Log.d(TAG, "waitForArrival: Starting for $destinationName")

        return try {
            withTimeout(300_000) { // 5 minutes timeout
                var navigationStarted = false
                var idleMessageCount = 0
                
                tourRepository.observeStatus()
                    .mapNotNull { it.navStatus }
                    .transformWhile { nav ->
                        when (nav) {
                            601 -> { // Moving
                                idleMessageCount = 0
                                if (!navigationStarted) {
                                    navigationStarted = true
                                    Log.i(TAG, "🚶 Robot moving to $destinationName...")
                                }
                                true // Continue collecting
                            }
                            603, 604 -> { // Arrived or Already There
                                Log.i(TAG, "✓ Arrived at $destinationName (status $nav)")
                                emit(true)
                                false // Stop collecting (Success)
                            }
                            600, 605 -> { // Idle / Standby
                                if (!navigationStarted) {
                                    idleMessageCount++
                                    if (idleMessageCount < MAX_IDLE_MESSAGES) {
                                        if (idleMessageCount == 1) Log.d(TAG, "Robot in idle state $nav, waiting...")
                                        true // Continue waiting
                                    } else {
                                        val errorMessage = "Navigation failed - robot stuck in idle state $nav after $idleMessageCount messages"
                                        Log.e(TAG, "❌ $errorMessage")
                                        errorLogger.logError(errorMessage)
                                        emit(false)
                                        false // Stop collecting (Fail)
                                    }
                                } else {
                                    Log.w(TAG, "Robot returned to idle state $nav after starting navigation")
                                    true // Continue waiting
                                }
                            }
                            else -> { // Error status
                                val errorMessage = "waitForArrival: Unknown or failure nav status: $nav for $destinationName."
                                Log.e(TAG, errorMessage)
                                errorLogger.logError(errorMessage)
                                emit(false)
                                false // Stop collecting
                            }
                        }
                    }.first()
            }
        } catch (e: TimeoutCancellationException) {
            val errorMessage = "Navigation timed out for $destinationName"
            Log.e(TAG, errorMessage)
            errorLogger.logError(errorMessage, e)
            false
        }
    }
}
