package com.opendroids.tourbot.data.settings

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "settings")

@Singleton
class SettingsManager @Inject constructor(@ApplicationContext appContext: Context) {

    private val settingsDataStore = appContext.dataStore

    val robotUrl: Flow<String> = settingsDataStore.data
        .map { preferences ->
            preferences[KEY_ROBOT_URL] ?: "ws://10.42.0.1:9090"
        }

    val showNerdData: Flow<Boolean> = settingsDataStore.data
        .map { preferences ->
            preferences[KEY_SHOW_NERD_DATA] ?: false
        }

    val carouselAtTop: Flow<Boolean> = settingsDataStore.data
        .map { preferences ->
            preferences[KEY_CAROUSEL_AT_TOP] ?: false
        }

    suspend fun setRobotUrl(url: String) {
        settingsDataStore.edit { settings ->
            settings[KEY_ROBOT_URL] = url
        }
    }

    suspend fun setShowNerdData(show: Boolean) {
        settingsDataStore.edit { settings ->
            settings[KEY_SHOW_NERD_DATA] = show
        }
    }

    suspend fun setCarouselAtTop(atTop: Boolean) {
        settingsDataStore.edit { settings ->
            settings[KEY_CAROUSEL_AT_TOP] = atTop
        }
    }

    companion object {
        private val KEY_ROBOT_URL = stringPreferencesKey("robot_url")
        private val KEY_SHOW_NERD_DATA = booleanPreferencesKey("show_nerd_data")
        private val KEY_CAROUSEL_AT_TOP = booleanPreferencesKey("carousel_at_top")
    }
}
