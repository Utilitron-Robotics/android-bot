package com.smait.robotrelay.service

import android.app.*
import android.content.Intent
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import com.smait.robotrelay.ui.MainActivity
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.StateFlow

/**
 * Foreground service to keep the relay running
 */
class RelayService : Service() {

    companion object {
        private const val TAG = "RelayService"
        private const val NOTIFICATION_ID = 1
        private const val CHANNEL_ID = "robot_relay_channel"
    }

    private val binder = RelayBinder()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    lateinit var robotClient: RobotWebSocketClient
        private set
    lateinit var relayServer: RelayServer
        private set

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
        relayServer = RelayServer(robotClient, relayPort)

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
}
