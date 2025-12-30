package com.smait.robotrelay.ui

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.net.wifi.WifiManager
import android.os.Bundle
import android.os.IBinder
import android.text.format.Formatter
import android.view.MotionEvent
import android.view.View
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import com.smait.robotrelay.databinding.ActivityMainBinding
import com.smait.robotrelay.service.ConnectionState
import com.smait.robotrelay.service.RelayService
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private var service: RelayService? = null
    private var bound = false
    private var velocityJob: Job? = null

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            val relayBinder = binder as RelayService.RelayBinder
            service = relayBinder.getService()
            bound = true
            observeService()
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            service = null
            bound = false
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        setupUI()
        startRelayService()
    }

    override fun onStart() {
        super.onStart()
        Intent(this, RelayService::class.java).also { intent ->
            bindService(intent, connection, Context.BIND_AUTO_CREATE)
        }
    }

    override fun onStop() {
        super.onStop()
        if (bound) {
            unbindService(connection)
            bound = false
        }
    }

    private fun startRelayService() {
        val intent = Intent(this, RelayService::class.java).apply {
            putExtra("robot_ip", "10.42.0.1")  // Direct robot WiFi
            putExtra("robot_port", 9090)
            putExtra("relay_port", 8765)
        }
        startForegroundService(intent)
    }

    private fun setupUI() {
        // Display IP address
        updateIpAddress()

        // Control buttons
        binding.btnStop.setOnClickListener {
            service?.stop()
        }

        binding.btnEstop.setOnClickListener {
            service?.emergencyStop(true)
        }

        binding.btnReleaseEstop.setOnClickListener {
            service?.emergencyStop(false)
        }

        binding.btnReconnect.setOnClickListener {
            service?.reconnectRobot()
        }

        binding.btnCancel.setOnClickListener {
            service?.cancelNavigation()
        }

        // Joystick controls
        setupJoystickButton(binding.btnForward, 0.3, 0.0)
        setupJoystickButton(binding.btnBackward, -0.3, 0.0)
        setupJoystickButton(binding.btnLeft, 0.0, 0.5)
        setupJoystickButton(binding.btnRight, 0.0, -0.5)
        setupJoystickButton(binding.btnForwardLeft, 0.2, 0.3)
        setupJoystickButton(binding.btnForwardRight, 0.2, -0.3)

        // POI navigation
        binding.btnGoPoi.setOnClickListener {
            val poi = binding.etPoi.text.toString()
            if (poi.isNotBlank()) {
                service?.navigateTo(poi)
            }
        }
    }

    private fun setupJoystickButton(button: View, linear: Double, angular: Double) {
        button.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    velocityJob = lifecycleScope.launch {
                        while (true) {
                            service?.sendVelocity(linear, angular)
                            delay(100) // Send velocity every 100ms
                        }
                    }
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    velocityJob?.cancel()
                    service?.stop()
                    true
                }
                else -> false
            }
        }
    }

    private fun observeService() {
        service?.let { svc ->
            lifecycleScope.launch {
                svc.getConnectionState().collectLatest { state ->
                    binding.tvRobotStatus.text = "Robot: ${state.name}"
                    binding.tvRobotStatus.setTextColor(
                        when (state) {
                            ConnectionState.CONNECTED -> 0xFF00AA00.toInt()
                            ConnectionState.CONNECTING -> 0xFFAAAA00.toInt()
                            else -> 0xFFAA0000.toInt()
                        }
                    )
                }
            }

            lifecycleScope.launch {
                svc.getRobotStatus().collectLatest { status ->
                    status?.let {
                        binding.tvBattery.text = "Battery: ${it.battery}%"
                        binding.tvPosition.text = String.format("Pos: (%.2f, %.2f) θ=%.1f°",
                            it.x, it.y, Math.toDegrees(it.theta))
                        binding.tvVelocity.text = String.format("Vel: %.2f m/s, %.2f rad/s",
                            it.velocity.getOrElse(0) { 0.0 },
                            it.velocity.getOrElse(1) { 0.0 })
                        binding.tvNavStatus.text = "Nav: ${getNavStatusText(it.navStatus)}"
                        binding.tvEstop.text = if (it.softEstop || it.hardEstop) "E-STOP ACTIVE" else ""
                        binding.tvEstop.visibility = if (it.softEstop || it.hardEstop) View.VISIBLE else View.GONE
                    }
                }
            }

            lifecycleScope.launch {
                svc.isRelayRunning().collectLatest { running ->
                    binding.tvRelayStatus.text = if (running) "Relay: Active" else "Relay: Stopped"
                }
            }

            lifecycleScope.launch {
                svc.getConnectedClients().collectLatest { count ->
                    binding.tvClients.text = "Clients: $count"
                }
            }
        }
    }

    private fun updateIpAddress() {
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val ip = Formatter.formatIpAddress(wifiManager.connectionInfo.ipAddress)
        binding.tvIpAddress.text = "Relay: http://$ip:8765 | ws://$ip:8766"
    }

    private fun getNavStatusText(status: Int): String = when (status) {
        600 -> "Waiting"
        601 -> "Running"
        602 -> "Cancelled"
        603 -> "Success"
        604 -> "Failed"
        else -> "Unknown ($status)"
    }
}
