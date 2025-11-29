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

/**
 * ╔══════════════════════════════════════════════════════════════════════════════╗
 * ║  CRITICAL: PRODUCTION TOUR CONFIGURATION - DO NOT MODIFY WITHOUT REVIEW      ║
 * ╠══════════════════════════════════════════════════════════════════════════════╣
 * ║  These robots operate in a 16-FLOOR BUILDING guiding real visitors.          ║
 * ║  Incorrect waypoint order = robot goes to WRONG FLOORS = angry customers.    ║
 * ║                                                                              ║
 * ║  RULES FOR AI ASSISTANTS:                                                    ║
 * ║  1. NEVER use Set or stringSetPreferencesKey for waypoints (loses order!)    ║
 * ║  2. NEVER change defaultWaypoints without explicit human approval            ║
 * ║  3. NEVER add "sample" waypoints like "lobby", "office", "test", etc.        ║
 * ║  4. Waypoint IDs MUST match files in assets/tour_scripts/*.txt               ║
 * ║  5. Order is CRITICAL - robot physically navigates in this sequence          ║
 * ║                                                                              ║
 * ║  HISTORY: GitHub Copilot broke this on Nov 23 2025 by using .toSet()         ║
 * ║           which randomized waypoint order and corrupted customer devices.    ║
 * ╚══════════════════════════════════════════════════════════════════════════════╝
 */
@Singleton
class TourConfigRepository @Inject constructor(
    @ApplicationContext private val context: Context
) {
    // --- Keys ---
    private val preSpeakDelayKey = intPreferencesKey("pre_speak_delay_ms")

    // WARNING: Must use stringPreferencesKey (NOT stringSetPreferencesKey!)
    // Sets do not preserve order. We store as pipe-delimited string.
    private val waypointListKey = stringPreferencesKey("waypoint_list_ordered")
    private fun scriptKey(waypointId: String) = stringPreferencesKey("script_$waypointId")

    // --- Defaults ---
    private val defaultPreSpeakDelay = 500 // 0.5 seconds

    /**
     * DEFAULT TOUR WAYPOINTS - Physical locations the robot visits IN ORDER.
     * Each ID must have a matching script file: assets/tour_scripts/{id}.txt
     *
     * DO NOT MODIFY without verifying:
     * 1. Script file exists for each waypoint
     * 2. Robot SLAM system has the POI registered
     * 3. Physical route is navigable in this order
     */
    private val defaultWaypoints = listOf(
        "empty_1",      // Floor/office stop 1
        "armin",        // Armin's office
        "empty_2",      // Floor/office stop 2
        "opendroids",   // Open Droids office
        "utilitron",    // Utilitron office
        "emerson",      // Emerson's office
        "avatar",       // Avatar office
        "end"           // Return to start/home position
    )

    // --- Public Flows ---
    val preSpeakDelay: Flow<Int> = context.dataStore.data.map { preferences ->
        preferences[preSpeakDelayKey] ?: defaultPreSpeakDelay
    }

    // This flow provides the ordered list of waypoints for the tour.
    // Uses pipe-delimited string to preserve order (NOT Set!)
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

    // --- Public Methods ---
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

    /**
     * Save waypoints list - ORDER IS PRESERVED.
     *
     * WARNING TO AI: Do NOT convert to Set! Do NOT use .toSet()!
     * The joinToString() preserves the exact order from the List.
     */
    suspend fun saveWaypoints(waypoints: List<String>) {
        context.dataStore.edit { settings ->
            // CORRECT: joinToString preserves List order
            // WRONG: .toSet() would randomize order - NEVER DO THIS
            settings[waypointListKey] = waypoints.joinToString(WAYPOINT_DELIMITER)
            Log.d(TAG, "Saved waypoints (order preserved): $waypoints")
        }
    }

    // Reset waypoints to defaults (useful for recovering from corrupted state)
    suspend fun resetWaypointsToDefaults() {
        context.dataStore.edit { settings ->
            settings[waypointListKey] = defaultWaypoints.joinToString(WAYPOINT_DELIMITER)
            Log.i(TAG, "Reset waypoints to defaults: $defaultWaypoints")
        }
    }

    // Alias for compatibility
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
