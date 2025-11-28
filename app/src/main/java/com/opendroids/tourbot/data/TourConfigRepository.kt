package com.opendroids.tourbot.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import java.io.IOException
import javax.inject.Inject
import javax.inject.Singleton

private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "tour_config")
private const val WAYPOINT_DELIMITER = "|"

@Singleton
class TourConfigRepository @Inject constructor(
    @ApplicationContext private val context: Context
) {
    // --- Keys ---
    private val preSpeakDelayKey = intPreferencesKey("pre_speak_delay_ms")
    // Changed from stringSetPreferencesKey to stringPreferencesKey to preserve order
    private val waypointListKey = stringPreferencesKey("waypoint_list_ordered")
    private fun scriptKey(waypointId: String) = stringPreferencesKey("script_$waypointId")

    // --- Defaults ---
    private val defaultPreSpeakDelay = 500 // 0.5 seconds

    // This is the single source of truth for the tour order, matching the Python implementation.
    private val defaultWaypoints = listOf(
        "empty_1",
        "armin",
        "empty_2",
        "opendroids",
        "utilitron",
        "emerson",
        "avatar",
        "end"
    )

    // --- Public Flows ---
    val preSpeakDelay: Flow<Int> = context.dataStore.data.map { preferences ->
        preferences[preSpeakDelayKey] ?: defaultPreSpeakDelay
    }

    // This flow provides the ordered list of waypoints for the tour.
    val waypointIds: Flow<List<String>> = context.dataStore.data.map { preferences ->
        val savedWaypointsString = preferences[waypointListKey]
        if (savedWaypointsString.isNullOrBlank()) {
            defaultWaypoints
        } else {
            // Parse the delimiter-separated string back to ordered list
            savedWaypointsString.split(WAYPOINT_DELIMITER).filter { it.isNotBlank() }
        }
    }

    // --- Public Methods ---
    suspend fun setPreSpeakDelay(delayMs: Int) {
        context.dataStore.edit { settings ->
            settings[preSpeakDelayKey] = delayMs
        }
    }

    suspend fun addWaypoint(id: String) {
        context.dataStore.edit { settings ->
            val currentWaypointsString = settings[waypointListKey] ?: ""
            val currentWaypoints = if (currentWaypointsString.isBlank()) {
                mutableListOf()
            } else {
                currentWaypointsString.split(WAYPOINT_DELIMITER).toMutableList()
            }
            if (!currentWaypoints.contains(id)) {
                currentWaypoints.add(id)
                settings[waypointListKey] = currentWaypoints.joinToString(WAYPOINT_DELIMITER)
            }
        }
    }

    suspend fun removeWaypoint(id: String) {
        context.dataStore.edit { settings ->
            val currentWaypointsString = settings[waypointListKey] ?: ""
            val currentWaypoints = currentWaypointsString.split(WAYPOINT_DELIMITER)
                .filter { it.isNotBlank() && it != id }
            settings[waypointListKey] = currentWaypoints.joinToString(WAYPOINT_DELIMITER)
        }
    }

    suspend fun saveWaypoints(waypoints: List<String>) {
        context.dataStore.edit { settings ->
            // Store as delimiter-separated string to preserve order
            settings[waypointListKey] = waypoints.joinToString(WAYPOINT_DELIMITER)
        }
    }

    suspend fun resetToDefaults() {
        context.dataStore.edit { settings ->
            settings.remove(waypointListKey)
        }
    }

    suspend fun getScript(waypointId: String): String {
        val key = scriptKey(waypointId)
        val preferences = context.dataStore.data.first()
        return preferences[key] ?: loadScriptFromAssets(waypointId)
    }

    suspend fun saveScript(waypointId: String, script: String) {
        val key = scriptKey(waypointId)
        context.dataStore.edit { settings ->
            settings[key] = script
        }
    }

    private fun loadScriptFromAssets(waypointId: String): String {
        return try {
            context.assets.open("tour_scripts/$waypointId.txt").bufferedReader().use { it.readText() }
        } catch (e: IOException) {
            "Script for $waypointId not found."
        }
    }
}
