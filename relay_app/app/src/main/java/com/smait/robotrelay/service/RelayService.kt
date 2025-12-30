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
class RelayService : Service(), TextToSpeech.OnInitListener, RelayServer.TaskExecutor {

    companion object {
        private const val TAG = "RelayService"
        private const val NOTIFICATION_ID = 1
        private const val CHANNEL_ID = "robot_relay_channel"

        // Robot base IP via USB wired connection (NOT the WiFi hotspot IP!)
        // WiFi hotspot: 10.42.0.1 | Wired/USB: 192.168.20.22
        private const val ROBOT_WIRED_IP = "192.168.20.22"

        // Broadcast actions for UI updates
        const val ACTION_DISPLAY = "com.smait.robotrelay.DISPLAY"
        const val ACTION_TASK_STATUS = "com.smait.robotrelay.TASK_STATUS"
        const val EXTRA_URL = "url"
        const val EXTRA_STATUS = "status"
    }

    private val binder = RelayBinder()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private val mainHandler = Handler(Looper.getMainLooper())

    // TTS engine
    private var tts: TextToSpeech? = null
    private val _ttsReady = MutableStateFlow(false)
    val ttsReady: StateFlow<Boolean> = _ttsReady
    private var currentUtteranceCallback: (() -> Unit)? = null

    lateinit var robotClient: RobotWebSocketClient
        private set
    lateinit var relayServer: RelayServer
        private set

    // Current task execution state
    private val _currentTask = MutableStateFlow<WaypointTask?>(null)
    val currentTask: StateFlow<WaypointTask?> = _currentTask

    private val _taskStatus = MutableStateFlow("")
    val taskStatus: StateFlow<String> = _taskStatus

    // Robot connection settings - defaults to wired (USB) connection
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

        // Initialize TTS
        tts = TextToSpeech(this, this)
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
        relayServer = RelayServer(robotClient, relayPort, this)

        // Connect to robot
        robotClient.connect()

        // Start relay server
        relayServer.start()

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
        Log.i(TAG, "speak() called: text='$text', ttsReady=${_ttsReady.value}, tts=${tts != null}")

        if (!_ttsReady.value) {
            Log.w(TAG, "TTS not ready, skipping: $text")
            onComplete?.invoke()
            return
        }

        Log.i(TAG, "Speaking: $text")
        _taskStatus.value = "Speaking..."

        currentUtteranceCallback = {
            _taskStatus.value = ""
            onComplete?.invoke()
        }

        // TTS must be called from main thread
        mainHandler.post {
            val result = tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "task_${System.currentTimeMillis()}")
            Log.i(TAG, "TTS speak() returned: $result")
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
        tts?.stop()
        closeDisplay()
        _currentTask.value = null
        _taskStatus.value = ""
    }

    // === TaskExecutor Interface Methods (for WebSocket/HTTP API) ===

    override fun speakText(text: String) {
        Log.i(TAG, ">>> speakText() called from TaskExecutor: '$text'")
        speak(text, null)
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
}
