package com.smait.robotrelay.cloud

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import com.google.gson.Gson
import com.google.gson.annotations.SerializedName
import com.google.gson.reflect.TypeToken
import kotlinx.coroutines.*
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit

/**
 * AWS Fleet API client - syncs config across ALL robots
 *
 * Change config once in the cloud → every robot gets it.
 * No more local bullshit configuration per robot.
 */
class FleetApiClient(private val context: Context) {
    companion object {
        private const val TAG = "FleetAPI"
        private const val PREFS_NAME = "fleet_config"
        private const val KEY_API_URL = "api_url"
        private const val KEY_ROBOT_ID = "robot_id"

        // Default API endpoint (from CloudFormation)
        private const val DEFAULT_API_URL = "https://tkua99lzm0.execute-api.us-west-1.amazonaws.com/dev"
    }

    private val gson = Gson()
    private val prefs: SharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .build()

    // Cached config
    private var _config: MutableMap<String, Any> = mutableMapOf()
    val config: Map<String, Any> get() = _config.toMap()

    // Robot ID for this tablet
    var robotId: String
        get() = prefs.getString(KEY_ROBOT_ID, "") ?: ""
        set(value) = prefs.edit().putString(KEY_ROBOT_ID, value).apply()

    // API URL (configurable)
    var apiUrl: String
        get() = prefs.getString(KEY_API_URL, DEFAULT_API_URL) ?: DEFAULT_API_URL
        set(value) = prefs.edit().putString(KEY_API_URL, value).apply()

    // Listeners for config changes
    private val listeners = mutableListOf<(Map<String, Any>) -> Unit>()

    fun addConfigListener(listener: (Map<String, Any>) -> Unit) {
        listeners.add(listener)
    }

    fun removeConfigListener(listener: (Map<String, Any>) -> Unit) {
        listeners.remove(listener)
    }

    private fun notifyListeners() {
        listeners.forEach { it(_config) }
    }

    // === Config Operations ===

    /**
     * Fetch fleet config from cloud
     */
    suspend fun fetchConfig(): Map<String, Any>? {
        return withContext(Dispatchers.IO) {
            try {
                val request = Request.Builder()
                    .url("$apiUrl/fleet/config")
                    .get()
                    .build()

                val response = client.newCall(request).execute()
                if (response.isSuccessful) {
                    val body = response.body?.string() ?: "{}"
                    val type = object : TypeToken<Map<String, Any>>() {}.type
                    _config = gson.fromJson(body, type) ?: mutableMapOf()
                    notifyListeners()
                    Log.i(TAG, "Fetched ${_config.size} config keys")
                    _config
                } else {
                    Log.e(TAG, "Config fetch failed: ${response.code}")
                    null
                }
            } catch (e: Exception) {
                Log.e(TAG, "Config fetch error: ${e.message}")
                null
            }
        }
    }

    /**
     * Get a config value
     */
    @Suppress("UNCHECKED_CAST")
    fun <T> getConfig(key: String, default: T? = null): T? {
        return _config[key] as? T ?: default
    }

    /**
     * Update config values in cloud
     */
    suspend fun setConfig(updates: Map<String, Any>): Boolean {
        return withContext(Dispatchers.IO) {
            try {
                val json = gson.toJson(updates)
                val request = Request.Builder()
                    .url("$apiUrl/fleet/config")
                    .post(json.toRequestBody("application/json".toMediaType()))
                    .build()

                val response = client.newCall(request).execute()
                if (response.isSuccessful) {
                    _config.putAll(updates)
                    notifyListeners()
                    Log.i(TAG, "Updated config: ${updates.keys}")
                    true
                } else {
                    Log.e(TAG, "Config update failed: ${response.code}")
                    false
                }
            } catch (e: Exception) {
                Log.e(TAG, "Config update error: ${e.message}")
                false
            }
        }
    }

    // === Robot Registration ===

    /**
     * Register this tablet as a robot/relay
     */
    suspend fun register(
        robotId: String,
        tabletModel: String = android.os.Build.MODEL,
        androidVersion: Int = android.os.Build.VERSION.SDK_INT,
        appVersion: String = "1.0.0",
        capabilities: Map<String, Boolean> = mapOf("tts" to true, "relay" to true)
    ): Boolean {
        this.robotId = robotId

        return withContext(Dispatchers.IO) {
            try {
                val body = mapOf(
                    "robot_id" to robotId,
                    "tablet_model" to tabletModel,
                    "android_version" to androidVersion,
                    "app_version" to appVersion,
                    "capabilities" to capabilities
                )

                val request = Request.Builder()
                    .url("$apiUrl/fleet/register")
                    .post(gson.toJson(body).toRequestBody("application/json".toMediaType()))
                    .build()

                val response = client.newCall(request).execute()
                if (response.isSuccessful) {
                    Log.i(TAG, "Registered as $robotId")
                    true
                } else {
                    Log.e(TAG, "Registration failed: ${response.code}")
                    false
                }
            } catch (e: Exception) {
                Log.e(TAG, "Registration error: ${e.message}")
                false
            }
        }
    }

    /**
     * Update robot status to cloud
     */
    suspend fun updateStatus(
        battery: Int? = null,
        position: Map<String, Double>? = null,
        navStatus: Int? = null,
        currentGoal: String? = null,
        estop: Boolean? = null,
        building: String? = null,
        floor: String? = null
    ): Boolean {
        if (robotId.isEmpty()) return false

        return withContext(Dispatchers.IO) {
            try {
                val body = mutableMapOf<String, Any>(
                    "robot_id" to robotId,
                    "timestamp" to System.currentTimeMillis()
                )
                battery?.let { body["battery"] = it }
                position?.let { body["position"] = it }
                navStatus?.let { body["nav_status"] = it }
                currentGoal?.let { body["current_goal"] = it }
                estop?.let { body["estop"] = it }
                building?.let { body["building"] = it }
                floor?.let { body["floor"] = it }

                val request = Request.Builder()
                    .url("$apiUrl/fleet/status")
                    .post(gson.toJson(body).toRequestBody("application/json".toMediaType()))
                    .build()

                val response = client.newCall(request).execute()
                response.isSuccessful.also { success ->
                    if (!success) Log.e(TAG, "Status update failed: ${response.code}")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Status update error: ${e.message}")
                false
            }
        }
    }

    // === Command Polling ===

    data class Command(
        @SerializedName("command_id") val commandId: String,
        val type: String,
        val payload: Map<String, Any>?,
        val status: String,
        val timestamp: Long
    )

    /**
     * Poll for pending commands from cloud
     */
    suspend fun getPendingCommands(): List<Command> {
        if (robotId.isEmpty()) return emptyList()

        return withContext(Dispatchers.IO) {
            try {
                val request = Request.Builder()
                    .url("$apiUrl/fleet/commands/$robotId")
                    .get()
                    .build()

                val response = client.newCall(request).execute()
                if (response.isSuccessful) {
                    val body = response.body?.string() ?: "{}"
                    val result = gson.fromJson(body, CommandsResponse::class.java)
                    result.commands
                } else {
                    emptyList()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Command fetch error: ${e.message}")
                emptyList()
            }
        }
    }

    private data class CommandsResponse(val commands: List<Command>)

    /**
     * Acknowledge receipt of a command
     */
    suspend fun ackCommand(commandId: String): Boolean {
        if (robotId.isEmpty()) return false

        return withContext(Dispatchers.IO) {
            try {
                val body = mapOf(
                    "robot_id" to robotId,
                    "command_id" to commandId
                )

                val request = Request.Builder()
                    .url("$apiUrl/fleet/commands/ack")
                    .post(gson.toJson(body).toRequestBody("application/json".toMediaType()))
                    .build()

                client.newCall(request).execute().isSuccessful
            } catch (e: Exception) {
                Log.e(TAG, "Command ack error: ${e.message}")
                false
            }
        }
    }

    /**
     * Mark command as complete
     */
    suspend fun completeCommand(commandId: String, status: String = "completed", message: String? = null): Boolean {
        if (robotId.isEmpty()) return false

        return withContext(Dispatchers.IO) {
            try {
                val body = mutableMapOf<String, Any>(
                    "robot_id" to robotId,
                    "command_id" to commandId,
                    "status" to status
                )
                message?.let { body["message"] = it }

                val request = Request.Builder()
                    .url("$apiUrl/fleet/commands/complete")
                    .post(gson.toJson(body).toRequestBody("application/json".toMediaType()))
                    .build()

                client.newCall(request).execute().isSuccessful
            } catch (e: Exception) {
                Log.e(TAG, "Command complete error: ${e.message}")
                false
            }
        }
    }

    // === Convenience Getters ===

    /**
     * Get TTS API key from fleet config
     */
    fun getTtsApiKey(): String? = getConfig("tts_api_key")

    /**
     * Get waypoint mode assignments from fleet config
     */
    @Suppress("UNCHECKED_CAST")
    fun getWaypointModes(): Map<String, Any>? = getConfig("waypoint_modes")

    fun destroy() {
        scope.cancel()
        listeners.clear()
    }
}
