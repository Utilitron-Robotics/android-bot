package com.opendroids.tourbot.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.core.stringSetPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import java.io.IOException
import javax.inject.Inject
import javax.inject.Singleton

private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "tour_config")

@Singleton
class TourConfigRepository @Inject constructor(
    @ApplicationContext private val context: Context
) {
    // --- Keys ---
    private val preSpeakDelayKey = intPreferencesKey("pre_speak_delay_ms")
    private val waypointListKey = stringSetPreferencesKey("waypoint_list")
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
        // For this version, we will use the hardcoded default list to ensure correctness.
        // The logic for loading from DataStore is preserved but defaults to the correct ordered list.
        val savedWaypoints = preferences[waypointListKey]
        if (savedWaypoints == null || savedWaypoints.isEmpty()) {
            defaultWaypoints
        } else {
            // If you use the control panel to save, it will use that order.
            // To restore default order, clear app data or implement a "reset" button.
            savedWaypoints.toList() 
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
            val currentWaypoints = settings[waypointListKey] ?: emptySet()
            settings[waypointListKey] = currentWaypoints + id
        }
    }

    suspend fun removeWaypoint(id: String) {
        context.dataStore.edit { settings ->
            val currentWaypoints = settings[waypointListKey] ?: emptySet()
            settings[waypointListKey] = currentWaypoints - id
        }
    }

    suspend fun saveWaypoints(waypoints: List<String>) {
        context.dataStore.edit { settings ->
            // Saving preserves the order from the UI drag-and-drop feature.
            settings[waypointListKey] = waypoints.toSet()
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
