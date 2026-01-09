package com.smait.robotrelay.service

import android.app.*
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Binder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import com.smait.robotrelay.cloud.FleetApiClient
import com.smait.robotrelay.protocol.SmaitProtocol
import com.smait.robotrelay.ui.MainActivity
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.util.*
import javax.net.SocketFactory

/**
 * Task types that can be performed at waypoints
 */
enum class TaskType {
    DELIVER,  // Wait for pickup, play sound
    SPEAK,    // Text-to-speech announcement
    DISPLAY   // Show URL/video on tablet screen
}

/**
 * A task to execute at a waypoint
 */
data class WaypointTask(
    val type: TaskType,
    val data: String,  // For SPEAK: text, for DISPLAY: URL, for DELIVER: pickup message
    val waitSeconds: Int = 0  // How long to wait (for DELIVER tasks)
)

/**
 * Foreground service to keep the relay running
 */
class RelayService : Service(), TextToSpeech.OnInitListener, RelayServer.TaskExecutor, RelayHttpServer.ConfigStore {

    companion object {
        private const val TAG = "RelayService"
        private const val NOTIFICATION_ID = 1
        private const val CHANNEL_ID = "robot_relay_channel"
        private const val CONFIG_PREFS = "task_config"
        private const val CONFIG_KEY = "waypoint_modes"
        private const val TTS_API_KEY = "google_tts_api_key"

        // Robot IP via WIRED USB connection (tablet is physically connected to robot)
        // See NETWORKING.md for architecture details
        private const val ROBOT_WIRED_IP = "192.168.20.22"

        // Broadcast actions for UI updates
        const val ACTION_DISPLAY = "com.smait.robotrelay.DISPLAY"
        const val ACTION_TASK_STATUS = "com.smait.robotrelay.TASK_STATUS"
        const val ACTION_COUNTDOWN = "com.smait.robotrelay.COUNTDOWN"
        const val ACTION_TOUR_MODE = "com.smait.robotrelay.TOUR_MODE"
        const val ACTION_TOUR_STANDBY = "com.smait.robotrelay.TOUR_STANDBY"
        const val EXTRA_URL = "url"
        const val EXTRA_STATUS = "status"
        const val EXTRA_COUNTDOWN_SECONDS = "countdown_seconds"
        const val EXTRA_COUNTDOWN_LABEL = "countdown_label"
        const val EXTRA_TOUR_ACTION = "tour_action"
        const val EXTRA_TOUR_PIN = "tour_pin"
        const val EXTRA_TOUR_SEQUENCE_ID = "tour_sequence_id"
        const val EXTRA_TOUR_BUTTON_TEXT = "tour_button_text"


        // Common phrases to precache for instant playback
        private val PRECACHE_PHRASES = listOf(
            "Your order is ready",
            "Your delivery has arrived",
            "Please collect your items",
            "Thank you! Have a nice day",
            "Navigation cancelled",
            "Destination reached",
            "Obstacle detected",
            "Battery low"
        )
    }

    private val binder = RelayBinder()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val mainHandler = Handler(Looper.getMainLooper())

    // TTS engines - Cloud TTS (high quality) with device TTS fallback
    private var cloudTts: CloudTtsService? = null
    private var tts: TextToSpeech? = null  // Legacy fallback
    private val _ttsReady = MutableStateFlow(false)
    val ttsReady: StateFlow<Boolean> = _ttsReady
    private var currentUtteranceCallback: (() -> Unit)? = null

    // AWS Fleet API client - syncs config across ALL robots
    private lateinit var fleetClient: FleetApiClient
    private var fleetSyncJob: Job? = null

    // Obstacle intelligence - DISABLED by default to avoid constant LIDAR processing
    // Only enable explicitly for motion-triggered tours (greeting visitors)
    private var obstacleIntelligenceEnabled = false  // OFF by default
    private var obstacleAnnouncementsEnabled = false  // TTS announcements OFF
    private var lastObstacleAnnouncement: Long = 0
    private var lastObstacleType: ObstacleType? = null
    private val OBSTACLE_ANNOUNCE_COOLDOWN = 5000L  // 5 seconds between same-type announcements

    lateinit var robotClient: RobotWebSocketClient
        private set
    lateinit var relayServer: RelayServer
        private set
    private var discoveryService: DiscoveryService? = null

    // gRPC server for WAN-ready communication (OPUS LEVEL!)
    private var grpcServer: com.smait.robotrelay.grpc.GrpcServer? = null

    // Current task execution state
    private val _currentTask = MutableStateFlow<WaypointTask?>(null)
    val currentTask: StateFlow<WaypointTask?> = _currentTask

    private val _taskStatus = MutableStateFlow("")
    val taskStatus: StateFlow<String> = _taskStatus

    // Alert sound tracking - prevent stacking
    private var alertSoundPlayer: android.media.MediaPlayer? = null
    private var pendingSoundRunnables = mutableListOf<Runnable>()

    // Robot connection settings - tablet is WIRED to robot base
    private var robotIp = ROBOT_WIRED_IP
    private var robotPort = 9090
    private var relayPort = 8765

    inner class RelayBinder : Binder() {
        fun getService(): RelayService = this@RelayService
    }

    override fun onBind(intent: Intent): IBinder = binder

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "Service created")
        createNotificationChannel()

        // Initialize AWS Fleet API client
        fleetClient = FleetApiClient(this)

        // Fetch fleet config from cloud (will update TTS key if available)
        scope.launch {
            val config = fleetClient.fetchConfig()
            if (config != null) {
                Log.i(TAG, "Fetched fleet config: ${config.keys}")

                // Use TTS key from fleet config if available
                val fleetTtsKey = fleetClient.getTtsApiKey()
                if (!fleetTtsKey.isNullOrEmpty()) {
                    Log.i(TAG, "Using TTS API key from fleet config")
                    withContext(Dispatchers.Main) {
                        initializeTts(fleetTtsKey)
                    }
                    return@launch
                }
            }

            // Fall back to local preferences
            val prefs = getSharedPreferences(CONFIG_PREFS, Context.MODE_PRIVATE)
            val localApiKey = prefs.getString(TTS_API_KEY, null)
            withContext(Dispatchers.Main) {
                initializeTts(localApiKey)
            }
        }

        // Start periodic fleet sync (every 30 seconds)
        startFleetSync()

        // Initialize legacy TTS as additional fallback
        tts = TextToSpeech(this, this)
    }

    /**
     * Initialize Cloud TTS with given API key
     */
    private fun initializeTts(apiKey: String?) {
        cloudTts = CloudTtsService(this, apiKey)
        cloudTts?.init()

        if (!apiKey.isNullOrEmpty()) {
            cloudTts?.precache(PRECACHE_PHRASES)
        }
    }

    /**
     * Start periodic fleet config sync
     */
    private fun startFleetSync() {
        fleetSyncJob?.cancel()
        fleetSyncJob = scope.launch {
            while (isActive) {
                delay(30_000) // 30 seconds
                try {
                    fleetClient.fetchConfig()

                    // Update robot status in cloud if registered
                    if (fleetClient.robotId.isNotEmpty() && ::robotClient.isInitialized) {
                        val status = robotClient.robotStatus.value
                        if (status != null) {
                            fleetClient.updateStatus(
                                battery = status.battery,
                                navStatus = status.navStatus,
                                currentGoal = status.currentGoalName,
                                estop = status.softEstop || status.hardEstop
                            )
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Fleet sync failed: ${e.message}")
                }
            }
        }
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            tts?.let { engine ->
                val result = engine.setLanguage(Locale.US)
                if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
                    Log.e(TAG, "TTS language not supported")
                    _ttsReady.value = false
                } else {
                    _ttsReady.value = true
                    Log.i(TAG, "TTS initialized successfully")

                    // Set up utterance listener
                    engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                        override fun onStart(utteranceId: String?) {}
                        override fun onDone(utteranceId: String?) {
                            currentUtteranceCallback?.invoke()
                            currentUtteranceCallback = null
                        }
                        override fun onError(utteranceId: String?) {
                            currentUtteranceCallback?.invoke()
                            currentUtteranceCallback = null
                        }
                    })
                }
            }
        } else {
            Log.e(TAG, "TTS initialization failed")
            _ttsReady.value = false
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i(TAG, "Service starting")

        // Get config from intent
        intent?.let {
            robotIp = it.getStringExtra("robot_ip") ?: robotIp
            robotPort = it.getIntExtra("robot_port", robotPort)
            relayPort = it.getIntExtra("relay_port", relayPort)
        }

        // Log available networks for debugging
        findUsbNetworkSocketFactory() // Just for logging

        Log.i(TAG, "Connecting to robot at ws://$robotIp:$robotPort")

        // Stop existing clients if they are running
        if (::robotClient.isInitialized) robotClient.destroy()
        if (::relayServer.isInitialized) relayServer.destroy()

        // Start as foreground service
        startForeground(NOTIFICATION_ID, createNotification("Starting..."))

        // Initialize clients - let Android handle routing
        // The 10.42.0.x subnet should only be reachable via USB
        robotClient = RobotWebSocketClient(robotIp, robotPort, null)
        relayServer = RelayServer(robotClient, relayPort, this, this)

        // Connect to robot
        robotClient.connect()

        // Enable obstacle intelligence for smart crowd handling
        if (obstacleIntelligenceEnabled) {
            robotClient.enableObstacleIntelligence { classification ->
                handleObstacleClassification(classification)
            }
        }

        // Start relay server (WebSocket - port 8766) - LEGACY, keeping for backward compatibility
        relayServer.start()

        // Start gRPC server (port 50051) - THIS IS THE REAL WAN-READY PROTOCOL!
        try {
            grpcServer = com.smait.robotrelay.grpc.GrpcServer(
                port = 50051,
                robotClient = robotClient,
                taskExecutor = this
            )
            grpcServer?.start()
            Log.i(TAG, "✅ gRPC server started on port 50051 - WAN-READY!")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start gRPC server: ${e.message}")
            // Continue without gRPC - legacy WebSocket still works
        }

        // Start UDP discovery service for auto-discovery
        discoveryService = DiscoveryService(relayPort, robotClient)
        discoveryService?.start()

        // Update notification with status
        scope.launch {
            robotClient.connectionState.collect { state ->
                updateNotification("Robot: ${state.name} | Relay: ${if (relayServer.isRunning.value) "Running" else "Stopped"}")
            }
        }

        return START_REDELIVER_INTENT
    }

    override fun onDestroy() {
        Log.i(TAG, "Service destroying")
        fleetSyncJob?.cancel()
        fleetClient.destroy()
        discoveryService?.destroy()
        cloudTts?.destroy()
        tts?.stop()
        tts?.shutdown()
        relayServer.destroy()
        robotClient.destroy()
        scope.cancel()
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Robot Relay",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Robot relay service status"
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(status: String): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Robot Relay Active")
            .setContentText(status)
            .setSmallIcon(android.R.drawable.ic_menu_share)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun updateNotification(status: String) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, createNotification(status))
    }

    /**
     * Find the USB/Ethernet network and return its SocketFactory.
     * This allows the robot connection to use the wired interface
     * while WiFi handles internet traffic.
     */
    private fun findUsbNetworkSocketFactory(): SocketFactory? {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

        // Get all networks and log what we find
        val networks = cm.allNetworks
        Log.i(TAG, "Found ${networks.size} network(s)")

        for (network in networks) {
            val caps = cm.getNetworkCapabilities(network)
            if (caps == null) {
                Log.d(TAG, "Network $network has no capabilities")
                continue
            }

            // Log all transports for this network
            val transports = mutableListOf<String>()
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) transports.add("WIFI")
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) transports.add("CELLULAR")
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) transports.add("ETHERNET")
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_BLUETOOTH)) transports.add("BLUETOOTH")
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) transports.add("VPN")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (caps.hasTransport(NetworkCapabilities.TRANSPORT_USB)) transports.add("USB")
            }
            Log.i(TAG, "Network $network transports: ${transports.joinToString(", ")}")

            // Skip WiFi networks - we want USB/Ethernet
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                continue
            }

            // Check for Ethernet (USB network adapters appear as Ethernet)
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) {
                Log.i(TAG, ">>> Using ETHERNET network for robot connection")
                return network.socketFactory
            }

            // Also check for USB transport (Android 12+)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                if (caps.hasTransport(NetworkCapabilities.TRANSPORT_USB)) {
                    Log.i(TAG, ">>> Using USB network for robot connection")
                    return network.socketFactory
                }
            }
        }

        // No USB/Ethernet found
        Log.w(TAG, "No USB/Ethernet network found! Available transports logged above.")
        Log.w(TAG, "Robot connection will use default routing (may fail if only WiFi available)")
        return null
    }

    // Public methods for UI

    fun getConnectionState(): StateFlow<ConnectionState> = robotClient.connectionState
    fun getRobotStatus(): StateFlow<RobotStatusData?> = robotClient.robotStatus
    fun isRelayRunning(): StateFlow<Boolean> = relayServer.isRunning
    fun getConnectedClients(): StateFlow<Int> = relayServer.connectedClients

    // Fleet API access
    fun getFleetClient(): FleetApiClient = fleetClient

    /**
     * Register this tablet as a robot in the fleet
     */
    fun registerWithFleet(robotId: String) {
        scope.launch {
            val success = fleetClient.register(robotId)
            if (success) {
                Log.i(TAG, "Registered with fleet as: $robotId")
            }
        }
    }

    /**
     * Manually trigger fleet config sync
     */
    fun syncFleetConfig() {
        scope.launch {
            val config = fleetClient.fetchConfig()
            if (config != null) {
                // Check if TTS key changed
                val newTtsKey = fleetClient.getTtsApiKey()
                if (!newTtsKey.isNullOrEmpty()) {
                    mainHandler.post {
                        cloudTts?.destroy()
                        initializeTts(newTtsKey)
                    }
                }
            }
        }
    }

    fun reconnectRobot() {
        robotClient.disconnect()
        robotClient.connect()
    }

    fun sendVelocity(linear: Double, angular: Double) {
        robotClient.sendVelocity(linear, angular)
    }

    fun stop() {
        robotClient.stop()
    }

    fun emergencyStop(enabled: Boolean) {
        robotClient.setSoftStop(enabled)
    }

    fun navigateTo(poi: String) {
        robotClient.navigateToPoi(poi)
    }

    fun cancelNavigation() {
        robotClient.cancelNavigation()
    }

    fun setSpeedMode(mode: Int) {
        robotClient.setSpeedMode(mode)
    }

    fun startSlam() {
        robotClient.startSlam()
    }

    fun stopSlam() {
        robotClient.stopSlam()
    }

    // === Task Execution Methods ===

    fun speak(text: String, onComplete: (() -> Unit)? = null) {
        Log.i(TAG, "speak() called: text='$text'")
        Log.i(TAG, "Speaking: $text")
        _taskStatus.value = "Speaking..."

        // Use Cloud TTS (handles its own fallback to device TTS)
        mainHandler.post {
            cloudTts?.speak(text) {
                mainHandler.post {
                    _taskStatus.value = ""
                    onComplete?.invoke()
                }
            }
        }
    }

    fun display(url: String) {
        Log.i(TAG, "display() called: url='${url.take(100)}...'")
        _taskStatus.value = "Displaying content"

        // Broadcast must be sent from main thread for reliable delivery
        mainHandler.post {
            val intent = Intent(ACTION_DISPLAY).apply {
                putExtra(EXTRA_URL, url)
            }
            LocalBroadcastManager.getInstance(this).sendBroadcast(intent)
            Log.i(TAG, "Display broadcast sent")
        }
    }

    override fun closeDisplay() {
        Log.i(TAG, "closeDisplay() called")
        _taskStatus.value = ""

        mainHandler.post {
            val intent = Intent(ACTION_DISPLAY).apply {
                putExtra(EXTRA_URL, "") // Empty URL = close
            }
            LocalBroadcastManager.getInstance(this).sendBroadcast(intent)
            Log.i(TAG, "Close display broadcast sent")
        }
    }

    /**
     * Update countdown timer overlay on tablet screen
     * @param seconds Countdown seconds (0 = hide countdown)
     * @param label Label text (e.g., "Next stop in", "Waiting...")
     */
    override fun updateCountdown(seconds: Int, label: String) {
        mainHandler.post {
            val intent = Intent(ACTION_COUNTDOWN).apply {
                putExtra(EXTRA_COUNTDOWN_SECONDS, seconds)
                putExtra(EXTRA_COUNTDOWN_LABEL, label)
            }
            LocalBroadcastManager.getInstance(this).sendBroadcast(intent)
            if (seconds > 0) {
                Log.d(TAG, "Countdown update: $seconds sec - $label")
            }
        }
    }

    /**
     * Start tour mode - locks tablet screen to prevent access to controls
     * @param pin Optional PIN code to unlock (default is 1234)
     */
    override fun startTourMode(pin: String?) {
        Log.i(TAG, "Starting tour mode (pin=${if (pin.isNullOrEmpty()) "default" else "custom"})")
        mainHandler.post {
            val intent = Intent(ACTION_TOUR_MODE).apply {
                putExtra(EXTRA_TOUR_ACTION, "start")
                if (!pin.isNullOrEmpty()) {
                    putExtra(EXTRA_TOUR_PIN, pin)
                }
            }
            LocalBroadcastManager.getInstance(this).sendBroadcast(intent)
        }
    }

    /**
     * Stop tour mode - unlocks tablet screen
     */
    override fun stopTourMode() {
        Log.i(TAG, "Stopping tour mode")
        mainHandler.post {
            val intent = Intent(ACTION_TOUR_MODE).apply {
                putExtra(EXTRA_TOUR_ACTION, "stop")
            }
            LocalBroadcastManager.getInstance(this).sendBroadcast(intent)
        }
        // Also hide countdown
        updateCountdown(0, "")
    }

    /**
     * Notifies the UI that a tour is in standby, ready to be started by a visitor.
     * This allows the lock screen to show a "Start Tour" button.
     */
    override fun notifyTourStandby(sequenceId: String, buttonText: String) {
        Log.i(TAG, "Notifying UI of tour standby: sequenceId=$sequenceId, buttonText=$buttonText")
        mainHandler.post {
            val intent = Intent(ACTION_TOUR_STANDBY).apply {
                putExtra(EXTRA_TOUR_SEQUENCE_ID, sequenceId)
                putExtra(EXTRA_TOUR_BUTTON_TEXT, buttonText)
            }
            LocalBroadcastManager.getInstance(this).sendBroadcast(intent)
        }
    }


    /**
     * Called when tour mode is unlocked via PIN entry on tablet
     * Notifies Flutter that user manually exited tour mode
     */
    fun notifyTourUnlocked() {
        Log.i(TAG, "Tour mode unlocked by user")
        // Send event to Flutter via WebSocket
        relayServer.commandBuffer.let { buffer ->
            // This will be picked up by Flutter via buffer_heartbeat
        }
        // TODO: Send explicit event to Flutter when tour is unlocked
    }

    /**
     * Called when "Start Tour" button is pressed on motion standby screen.
     * Completes the motion_standby command in CommandBuffer.
     */
    fun notifyTourStarted(sequenceId: String) {
        Log.i(TAG, "Tour started via button press for sequence: $sequenceId")
        relayServer.commandBuffer.notifyTourStarted()
    }

    // === Obstacle Intelligence ===

    /**
     * Handle obstacle classification from LIDAR intelligence.
     *
     * KEY INSIGHT: Only announce for:
     * - MOVING objects (person, other robot, falling item) - they might move
     * - UNEXPECTED STATIC objects in path that SHOULD be open
     *
     * NEVER announce for:
     * - Walls, corners, map obstacles (robot should just navigate around)
     * - Reflections, self-detection
     * - Anything the path planner should handle quietly
     *
     * CRITICAL: Only announce obstacles when ACTIVELY NAVIGATING (navStatus == 601)
     * When idle, we should be looking for people to greet, not yelling at walls!
     */
    private fun handleObstacleClassification(classification: ObstacleClassification) {
        if (!obstacleAnnouncementsEnabled) return
        if (classification.type == ObstacleType.CLEAR) return

        // THE SIMPLE CHECK: Only announce during ACTIVE NAVIGATION (601)
        val navStatus = robotClient.robotStatus.value?.navStatus ?: 0
        if (navStatus != 601) return  // Not navigating = no announcements

        // Must be in the robot's path
        if (!classification.inPath) return

        // Only announce for MOVING obstacles (walls don't move)
        if (!classification.isMoving) return

        // Check cooldown to avoid spamming announcements
        // Use TWO cooldowns:
        // 1. Short cooldown for ANY announcement (prevents rapid fire)
        // 2. Longer cooldown for same-type (avoids repeating the same thing)
        val now = System.currentTimeMillis()
        val timeSinceLastAnnouncement = now - lastObstacleAnnouncement

        // Always wait at least 3 seconds between ANY announcements
        if (timeSinceLastAnnouncement < 3000L) {
            return
        }

        // Wait 5 seconds before repeating same type
        if (classification.type == lastObstacleType && timeSinceLastAnnouncement < OBSTACLE_ANNOUNCE_COOLDOWN) {
            return
        }

        // Determine announcement based on type
        val announcement = when (classification.suggestedAction) {
            SuggestedAction.WAIT_PATIENTLY -> {
                // Moving person - they'll likely move on their own
                Log.i(TAG, "Obstacle: Moving person detected, waiting patiently")
                null  // Don't announce yet, just wait
            }
            SuggestedAction.WAIT_AND_OBSERVE -> {
                // Unknown moving thing - could be another robot
                Log.i(TAG, "Obstacle: Unknown moving object, observing")
                null  // Don't announce, just observe
            }
            SuggestedAction.POLITE_REQUEST -> {
                // Person standing still - ask nicely
                Log.i(TAG, "Obstacle: Static person in path, polite request")
                "Excuse me, you're in my path. Please step aside."
            }
            SuggestedAction.ANNOUNCE_CROWD -> {
                // Multiple people blocking - louder announcement
                Log.i(TAG, "Obstacle: Crowd detected, announcing")
                "Attention please. The path is blocked. Please make way."
            }
            SuggestedAction.REQUEST_HELP -> {
                // Unexpected static obstacle - need human help
                Log.i(TAG, "Obstacle: Unexpected static obstacle, requesting help")
                "There's an obstacle blocking my path. I need assistance."
            }
            SuggestedAction.ESCALATE_NORMALLY -> {
                // Can't classify - let time-based system handle it
                Log.i(TAG, "Obstacle: Unknown, falling back to normal escalation")
                null
            }
            SuggestedAction.NONE -> null
        }

        // Make announcement if we have one
        if (announcement != null) {
            lastObstacleAnnouncement = now
            lastObstacleType = classification.type
            speak(announcement)
        }
    }

    /**
     * Enable/disable obstacle intelligence
     */
    fun setObstacleIntelligenceEnabled(enabled: Boolean) {
        obstacleIntelligenceEnabled = enabled
        robotClient.setObstacleIntelligenceEnabled(enabled)
        Log.i(TAG, "Obstacle intelligence ${if (enabled) "enabled" else "disabled"}")
    }

    fun executeTask(task: WaypointTask, onComplete: (() -> Unit)? = null) {
        Log.i(TAG, "Executing task: ${task.type} - ${task.data}")
        _currentTask.value = task

        scope.launch(Dispatchers.Main) {
            when (task.type) {
                TaskType.SPEAK -> {
                    val completion = CompletableDeferred<Unit>()
                    speak(task.data) { completion.complete(Unit) }
                    completion.await()
                }

                TaskType.DISPLAY -> {
                    display(task.data)
                    if (task.waitSeconds > 0) {
                        delay(task.waitSeconds * 1000L)
                        closeDisplay()
                    }
                }

                TaskType.DELIVER -> {
                    val completion = CompletableDeferred<Unit>()
                    speak(task.data.ifEmpty { "Your order has arrived. Please collect your items." }) {
                        completion.complete(Unit)
                    }
                    completion.await()

                    if (task.waitSeconds > 0) {
                        _taskStatus.value = "Waiting for pickup..."
                        delay(task.waitSeconds * 1000L)
                    }

                    val thankCompletion = CompletableDeferred<Unit>()
                    speak("Thank you! Have a nice day.") { thankCompletion.complete(Unit) }
                    thankCompletion.await()
                }
            }

            _currentTask.value = null
            _taskStatus.value = ""
            onComplete?.invoke()
        }
    }

    override fun cancelTask() {
        cloudTts?.stop()
        tts?.stop()
        closeDisplay()
        _currentTask.value = null
        _taskStatus.value = ""
    }

    /**
     * Set Google Cloud TTS API key (internal implementation)
     */
    private fun updateTtsApiKey(apiKey: String?) {
        val prefs = getSharedPreferences(CONFIG_PREFS, Context.MODE_PRIVATE)
        if (apiKey.isNullOrEmpty()) {
            prefs.edit().remove(TTS_API_KEY).apply()
        } else {
            prefs.edit().putString(TTS_API_KEY, apiKey).apply()
        }

        // Reinitialize Cloud TTS with new key
        cloudTts?.destroy()
        cloudTts = CloudTtsService(this, apiKey)
        cloudTts?.init()

        if (!apiKey.isNullOrEmpty()) {
            cloudTts?.precache(PRECACHE_PHRASES)
        }

        Log.i(TAG, "TTS API key ${if (apiKey.isNullOrEmpty()) "cleared" else "set"}")
    }

    /**
     * Check if Cloud TTS API key is configured (internal implementation)
     */
    private fun checkHasTtsApiKey(): Boolean {
        val prefs = getSharedPreferences(CONFIG_PREFS, Context.MODE_PRIVATE)
        return !prefs.getString(TTS_API_KEY, null).isNullOrEmpty()
    }

    // === TaskExecutor Interface Methods (for WebSocket/HTTP API) ===

    override fun setTtsApiKey(apiKey: String?) {
        updateTtsApiKey(apiKey)
    }

    override fun hasTtsApiKey(): Boolean {
        return checkHasTtsApiKey()
    }

    override fun speakText(text: String, onComplete: (() -> Unit)?) {
        Log.i(TAG, ">>> speakText() called from TaskExecutor: '$text' (callback=${onComplete != null})")
        // Stop any current speech to prevent queuing (for blocked path warnings)
        cloudTts?.stop()
        tts?.stop()
        speak(text, onComplete)
    }

    override fun stopSpeak() {
        Log.i(TAG, ">>> stopSpeak() called - clearing TTS queue")
        cloudTts?.stop()
        tts?.stop()
    }

    override fun displayUrl(url: String) {
        Log.i(TAG, ">>> displayUrl() called from TaskExecutor: '${url.take(100)}...'")
        display(url)
    }

    override fun runTask(type: String, data: String, waitSeconds: Int) {
        val taskType = try {
            TaskType.valueOf(type.uppercase())
        } catch (e: Exception) {
            Log.e(TAG, "Unknown task type: $type")
            return
        }
        executeTask(WaypointTask(taskType, data, waitSeconds))
    }

    override fun playAlertSound(soundType: String) {
        Log.i(TAG, ">>> playAlertSound() called: '$soundType'")
        // Run sound generation on background thread to avoid blocking
        scope.launch(Dispatchers.Default) {
            try {
                // Cancel any pending sounds first to prevent stacking
                withContext(Dispatchers.Main) { cancelPendingSounds() }

                when (soundType.lowercase()) {
                    "horn", "alarm" -> {
                        // Generate loud horn sound: 3 descending tones
                        Log.i(TAG, "Generating horn sound...")
                        generateTone(440.0, 300)  // A4
                        delay(100)
                        generateTone(349.23, 300) // F4
                        delay(100)
                        generateTone(293.66, 400) // D4
                        Log.i(TAG, "Horn sound complete")
                    }
                    "beep" -> {
                        // Single attention beep
                        Log.i(TAG, "Generating beep sound...")
                        generateTone(880.0, 200)  // A5 - high pitched beep
                        Log.i(TAG, "Beep sound complete")
                    }
                    "arrival", "arrival_beep" -> {
                        // Loud beep-boop for POI/Delivery arrival
                        Log.i(TAG, "Generating arrival beep-boop sound...")
                        generateTone(880.0, 150)  // A5 - high beep
                        delay(50)
                        generateTone(1047.0, 150) // C6 - higher beep
                        delay(50)
                        generateTone(880.0, 200)  // A5 - back down
                        Log.i(TAG, "Arrival sound complete")
                    }
                    "delivery" -> {
                        // Extra loud celebratory sound for delivery arrival
                        Log.i(TAG, "Generating delivery arrival sound...")
                        generateTone(523.25, 100) // C5
                        delay(30)
                        generateTone(659.25, 100) // E5
                        delay(30)
                        generateTone(783.99, 100) // G5
                        delay(30)
                        generateTone(1047.0, 200) // C6 - triumphant high note
                        Log.i(TAG, "Delivery sound complete")
                    }
                    else -> {
                        Log.i(TAG, "Generating default beep...")
                        generateTone(660.0, 150)  // E5
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to play alert sound: ${e.message}", e)
            }
        }
    }

    /**
     * Generate a pure tone using AudioTrack - works on all devices
     */
    private fun generateTone(frequencyHz: Double, durationMs: Int) {
        val sampleRate = 44100
        val numSamples = (sampleRate * durationMs / 1000.0).toInt()
        val samples = ShortArray(numSamples)

        // Generate sine wave with fade in/out to avoid clicks
        val fadeLength = (numSamples * 0.1).toInt() // 10% fade
        for (i in 0 until numSamples) {
            val angle = 2.0 * Math.PI * i / (sampleRate / frequencyHz)
            var amplitude = 32767.0 * 0.8 // 80% volume to avoid clipping

            // Fade in
            if (i < fadeLength) {
                amplitude *= i.toDouble() / fadeLength
            }
            // Fade out
            if (i > numSamples - fadeLength) {
                amplitude *= (numSamples - i).toDouble() / fadeLength
            }

            samples[i] = (Math.sin(angle) * amplitude).toInt().toShort()
        }

        // Create and play AudioTrack
        val bufferSize = android.media.AudioTrack.getMinBufferSize(
            sampleRate,
            android.media.AudioFormat.CHANNEL_OUT_MONO,
            android.media.AudioFormat.ENCODING_PCM_16BIT
        )

        val audioTrack = android.media.AudioTrack.Builder()
            .setAudioAttributes(
                android.media.AudioAttributes.Builder()
                    .setUsage(android.media.AudioAttributes.USAGE_ALARM)
                    .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            .setAudioFormat(
                android.media.AudioFormat.Builder()
                    .setEncoding(android.media.AudioFormat.ENCODING_PCM_16BIT)
                    .setSampleRate(sampleRate)
                    .setChannelMask(android.media.AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setBufferSizeInBytes(maxOf(bufferSize, samples.size * 2))
            .setTransferMode(android.media.AudioTrack.MODE_STATIC)
            .build()

        audioTrack.write(samples, 0, samples.size)
        audioTrack.play()

        // Wait for playback to complete
        Thread.sleep(durationMs.toLong() + 50)
        audioTrack.stop()
        audioTrack.release()
    }

    private fun cancelPendingSounds() {
        // Cancel any pending sound handlers
        pendingSoundRunnables.forEach { mainHandler.removeCallbacks(it) }
        pendingSoundRunnables.clear()

        // Stop and release current player
        alertSoundPlayer?.let { player ->
            try {
                if (player.isPlaying) {
                    player.stop()
                }
                player.release()
            } catch (e: Exception) {
                Log.w(TAG, "Error releasing alert player: ${e.message}")
            }
        }
        alertSoundPlayer = null
    }

    // === ConfigStore Interface Methods ===

    override fun getConfig(): String? {
        val prefs = getSharedPreferences(CONFIG_PREFS, Context.MODE_PRIVATE)
        return prefs.getString(CONFIG_KEY, null)
    }

    override fun saveConfig(json: String) {
        val prefs = getSharedPreferences(CONFIG_PREFS, Context.MODE_PRIVATE)
        prefs.edit().putString(CONFIG_KEY, json).apply()
        Log.i(TAG, "Config saved to SharedPreferences")
    }
}
