package com.smait.robotrelay.service

import android.app.*
import android.content.Intent
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import com.smait.robotrelay.ui.MainActivity
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.util.*

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

        // Broadcast actions for UI updates
        const val ACTION_DISPLAY = "com.smait.robotrelay.DISPLAY"
        const val ACTION_TASK_STATUS = "com.smait.robotrelay.TASK_STATUS"
        const val EXTRA_URL = "url"
        const val EXTRA_STATUS = "status"
    }

    private val binder = RelayBinder()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // TTS engine
    private var tts: TextToSpeech? = null
    private var ttsReady = false
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

    private var robotIp = "192.168.20.22"
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
                } else {
                    ttsReady = true
                    Log.i(TAG, "TTS initialized successfully")

                    // Set up utterance listener
                    engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                        override fun onStart(utteranceId: String?) {
                            Log.d(TAG, "TTS started: $utteranceId")
                        }

                        override fun onDone(utteranceId: String?) {
                            Log.d(TAG, "TTS done: $utteranceId")
                            currentUtteranceCallback?.invoke()
                            currentUtteranceCallback = null
                        }

                        override fun onError(utteranceId: String?) {
                            Log.e(TAG, "TTS error: $utteranceId")
                            currentUtteranceCallback?.invoke()
                            currentUtteranceCallback = null
                        }
                    })
                }
            }
        } else {
            Log.e(TAG, "TTS initialization failed")
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

        // Start as foreground service
        startForeground(NOTIFICATION_ID, createNotification("Starting..."))

        // Initialize clients
        robotClient = RobotWebSocketClient(robotIp, robotPort)
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

        return START_STICKY
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

    // === Task Execution Methods ===

    /**
     * Speak text using TTS
     * @param text The text to speak
     * @param onComplete Callback when speech is done
     */
    fun speak(text: String, onComplete: (() -> Unit)? = null) {
        if (!ttsReady) {
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

        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "task_${System.currentTimeMillis()}")
    }

    /**
     * Display a URL/video on the tablet screen
     * Sends broadcast to MainActivity to show WebView/VideoView
     */
    fun display(url: String) {
        Log.i(TAG, "Displaying: $url")
        _taskStatus.value = "Displaying content"

        val intent = Intent(ACTION_DISPLAY).apply {
            putExtra(EXTRA_URL, url)
        }
        LocalBroadcastManager.getInstance(this).sendBroadcast(intent)
    }

    /**
     * Close any displayed content
     */
    override fun closeDisplay() {
        Log.i(TAG, "Closing display")
        _taskStatus.value = ""

        val intent = Intent(ACTION_DISPLAY).apply {
            putExtra(EXTRA_URL, "") // Empty URL = close
        }
        LocalBroadcastManager.getInstance(this).sendBroadcast(intent)
    }

    /**
     * Execute a waypoint task
     */
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
                    // Announce arrival
                    val completion = CompletableDeferred<Unit>()
                    speak(task.data.ifEmpty { "Your order has arrived. Please collect your items." }) {
                        completion.complete(Unit)
                    }
                    completion.await()

                    // Wait for pickup
                    if (task.waitSeconds > 0) {
                        _taskStatus.value = "Waiting for pickup..."
                        delay(task.waitSeconds * 1000L)
                    }

                    // Thank customer
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

    /**
     * Cancel current task
     */
    override fun cancelTask() {
        tts?.stop()
        closeDisplay()
        _currentTask.value = null
        _taskStatus.value = ""
    }

    // === TaskExecutor Interface Methods (for HTTP API) ===

    override fun speakText(text: String) {
        speak(text, null)
    }

    override fun displayUrl(url: String) {
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
