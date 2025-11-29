package com.opendroids.tourbot.data

import android.content.Context
import android.util.Log
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

private const val TAG = "TourConfigRepository"
private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "tour_config")
private const val WAYPOINT_DELIMITER = "|"

@Singleton
class TourConfigRepository @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val preSpeakDelayKey = intPreferencesKey("pre_speak_delay_ms")
    private val waypointListKey = stringPreferencesKey("waypoint_list_ordered")
    private fun scriptKey(waypointId: String) = stringPreferencesKey("script_$waypointId")

    private val defaultPreSpeakDelay = 500

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

    val preSpeakDelay: Flow<Int> = context.dataStore.data.map { preferences ->
        preferences[preSpeakDelayKey] ?: defaultPreSpeakDelay
    }

    val waypointIds: Flow<List<String>> = context.dataStore.data.map { preferences ->
        val savedWaypointsString = preferences[waypointListKey]
        if (savedWaypointsString.isNullOrBlank()) {
            Log.d(TAG, "No saved waypoints, using defaults: $defaultWaypoints")
            defaultWaypoints
        } else {
            val waypoints = savedWaypointsString.split(WAYPOINT_DELIMITER).filter { it.isNotBlank() }
            Log.d(TAG, "Loaded waypoints (ordered): $waypoints")
            waypoints
        }
    }

    suspend fun setPreSpeakDelay(delayMs: Int) {
        context.dataStore.edit { settings ->
            settings[preSpeakDelayKey] = delayMs
        }
    }

    suspend fun addWaypoint(id: String) {
        context.dataStore.edit { settings ->
            val currentString = settings[waypointListKey] ?: ""
            val currentList = if (currentString.isBlank()) {
                defaultWaypoints.toMutableList()
            } else {
                currentString.split(WAYPOINT_DELIMITER).filter { it.isNotBlank() }.toMutableList()
            }
            if (!currentList.contains(id)) {
                currentList.add(id)
                settings[waypointListKey] = currentList.joinToString(WAYPOINT_DELIMITER)
                Log.d(TAG, "Added waypoint '$id', new list: $currentList")
            }
        }
    }

    suspend fun removeWaypoint(id: String) {
        context.dataStore.edit { settings ->
            val currentString = settings[waypointListKey] ?: ""
            val currentList = if (currentString.isBlank()) {
                defaultWaypoints.toMutableList()
            } else {
                currentString.split(WAYPOINT_DELIMITER).filter { it.isNotBlank() }.toMutableList()
            }
            currentList.remove(id)
            settings[waypointListKey] = currentList.joinToString(WAYPOINT_DELIMITER)
            Log.d(TAG, "Removed waypoint '$id', new list: $currentList")
        }
    }

    suspend fun saveWaypoints(waypoints: List<String>) {
        context.dataStore.edit { settings ->
            settings[waypointListKey] = waypoints.joinToString(WAYPOINT_DELIMITER)
            Log.d(TAG, "Saved waypoints (order preserved): $waypoints")
        }
    }

    suspend fun resetWaypointsToDefaults() {
        context.dataStore.edit { settings ->
            settings[waypointListKey] = defaultWaypoints.joinToString(WAYPOINT_DELIMITER)
            Log.i(TAG, "Reset waypoints to defaults: $defaultWaypoints")
        }
    }

    suspend fun resetToDefaults() = resetWaypointsToDefaults()

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
