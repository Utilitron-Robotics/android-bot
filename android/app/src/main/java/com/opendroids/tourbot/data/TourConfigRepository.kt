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

@Singleton
class TourConfigRepository @Inject constructor(
    @ApplicationContext private val context: Context
) {
    // --- Keys ---
    private val preSpeakDelayKey = intPreferencesKey("pre_speak_delay_ms")
    private fun scriptKey(waypointId: String) = stringPreferencesKey("script_$waypointId")

    // --- Defaults ---
    private val defaultPreSpeakDelay = 500 // 0.5 seconds

    // --- Public Flows ---
    val preSpeakDelay: Flow<Int> = context.dataStore.data.map { preferences ->
        preferences[preSpeakDelayKey] ?: defaultPreSpeakDelay
    }

    // --- Public Methods ---
    suspend fun setPreSpeakDelay(delayMs: Int) {
        context.dataStore.edit { settings ->
            settings[preSpeakDelayKey] = delayMs
        }
    }

    suspend fun getScript(waypointId: String): String {
        val key = scriptKey(waypointId)
        val preferences = context.dataStore.data.first()
        // If script is not in DataStore, load from asset and save it for future edits.
        return preferences[key] ?: loadScriptFromAssetsAndSave(waypointId, key)
    }

    suspend fun saveScript(waypointId: String, script: String) {
        val key = scriptKey(waypointId)
        context.dataStore.edit { settings ->
            settings[key] = script
        }
    }

    private suspend fun loadScriptFromAssetsAndSave(waypointId: String, key: Preferences.Key<String>): String {
        return try {
            val scriptFromAsset = context.assets.open("tour_scripts/$waypointId.txt").bufferedReader().use { it.readText() }
            context.dataStore.edit { settings ->
                settings[key] = scriptFromAsset
            }
            scriptFromAsset
        } catch (e: IOException) {
            "Script for $waypointId not found."
        }
    }
}
