package com.smait.robotrelay.ui

import android.content.*
import android.graphics.Rect
import android.net.wifi.WifiManager
import android.os.Bundle
import android.os.IBinder
import android.text.format.Formatter
import android.util.Log
import android.view.MotionEvent
import android.view.View
import android.view.inputmethod.InputMethodManager
import android.webkit.WebViewClient
import android.widget.EditText
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import com.smait.robotrelay.R
import com.smait.robotrelay.databinding.ActivityMainBinding
import com.smait.robotrelay.protocol.SmaitProtocol
import com.smait.robotrelay.service.ConnectionState
import com.smait.robotrelay.service.RelayService
import com.smait.robotrelay.service.SafetyZone
import com.smait.robotrelay.service.SensorStatus
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

class MainActivity : AppCompatActivity() {

    companion object {
        private const val TAG = "MainActivity"
        // Robot IP via WIRED USB connection (tablet is physically connected to robot)
        // See NETWORKING.md for architecture details
        private const val ROBOT_WIRED_IP = "192.168.20.22"
    }

    private lateinit var binding: ActivityMainBinding
    private var service: RelayService? = null
    private var bound = false
    private var velocityJob: Job? = null
    private var speedMultiplier = 1.0 // 1.0 = Medium, 0.5 = Slow, 1.5 = Fast

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

    private val displayReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val url = intent?.getStringExtra(RelayService.EXTRA_URL)
            Log.i(TAG, ">>> displayReceiver.onReceive: url='${url?.take(100) ?: "null"}...'")
            if (url.isNullOrEmpty()) {
                Log.i(TAG, "Hiding WebView, showing main layout")
                binding.webView.visibility = View.GONE
                binding.mainLayout.visibility = View.VISIBLE
            } else {
                Log.i(TAG, "Showing WebView, loading URL")
                binding.mainLayout.visibility = View.GONE
                binding.webView.visibility = View.VISIBLE
                binding.webView.loadUrl(url)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        setupUI()
        startRelayService(getRobotIp())
    }

    override fun onStart() {
        super.onStart()
        Intent(this, RelayService::class.java).also { intent ->
            bindService(intent, connection, Context.BIND_AUTO_CREATE)
        }
        LocalBroadcastManager.getInstance(this)
            .registerReceiver(displayReceiver, IntentFilter(RelayService.ACTION_DISPLAY))
    }

    override fun onStop() {
        super.onStop()
        if (bound) {
            unbindService(connection)
            bound = false
        }
        LocalBroadcastManager.getInstance(this).unregisterReceiver(displayReceiver)
    }

    override fun dispatchTouchEvent(ev: MotionEvent?): Boolean {
        if (ev?.action == MotionEvent.ACTION_DOWN) {
            val v = currentFocus
            if (v is EditText) {
                val outRect = Rect()
                v.getGlobalVisibleRect(outRect)
                if (!outRect.contains(ev.rawX.toInt(), ev.rawY.toInt())) {
                    v.clearFocus()
                    val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
                    imm.hideSoftInputFromWindow(v.windowToken, 0)
                }
            }
        }
        return super.dispatchTouchEvent(ev)
    }

    private fun startRelayService(robotIp: String) {
        val intent = Intent(this, RelayService::class.java).apply {
            putExtra("robot_ip", robotIp)
            putExtra("robot_port", 9090)
            putExtra("relay_port", 8765)
        }
        startForegroundService(intent)
    }

    private fun getRobotIp(): String {
        val prefs = getSharedPreferences("relay_prefs", Context.MODE_PRIVATE)
        // Default to wired connection (tablet is USB connected to robot)
        return prefs.getString("robot_ip", ROBOT_WIRED_IP) ?: ROBOT_WIRED_IP
    }

    private fun saveRobotIp(ip: String) {
        val prefs = getSharedPreferences("relay_prefs", Context.MODE_PRIVATE)
        prefs.edit().putString("robot_ip", ip).apply()
    }

    private fun setupUI() {
        binding.webView.webViewClient = WebViewClient()
        binding.webView.settings.javaScriptEnabled = true
        updateIpAddress()
        binding.etRobotIp.setText(getRobotIp())

        binding.btnStop.setOnClickListener { service?.stop() }
        binding.btnEstop.setOnClickListener { service?.emergencyStop(true) }
        binding.btnReleaseEstop.setOnClickListener { service?.emergencyStop(false) }

        binding.btnReconnect.setOnClickListener {
            val newIp = binding.etRobotIp.text.toString()
            saveRobotIp(newIp)
            startRelayService(newIp)
        }

        binding.btnCancel.setOnClickListener { service?.cancelNavigation() }

        binding.btnSpeedSlow.setOnClickListener {
            speedMultiplier = 0.5
            binding.tvSpeedStatus.text = "Speed: Slow"
        }
        binding.btnSpeedMedium.setOnClickListener {
            speedMultiplier = 1.0
            binding.tvSpeedStatus.text = "Speed: Medium"
        }
        binding.btnSpeedFast.setOnClickListener {
            speedMultiplier = 1.5
            binding.tvSpeedStatus.text = "Speed: Fast"
        }

        binding.btnSlamOn.setOnClickListener {
            service?.startSlam()
            binding.tvSlamStatus.text = "Mode: Enabling..."
            binding.ivSlamIcon.visibility = View.GONE
        }
        binding.btnSlamOff.setOnClickListener {
            service?.stopSlam()
            binding.tvSlamStatus.text = "Mode: Disabled"
            binding.ivSlamIcon.visibility = View.GONE
        }

        setupJoystickButton(binding.btnForward, 0.3, 0.0)
        setupJoystickButton(binding.btnBackward, -0.3, 0.0)
        setupJoystickButton(binding.btnLeft, 0.0, 0.5)
        setupJoystickButton(binding.btnRight, 0.0, -0.5)
        setupJoystickButton(binding.btnForwardLeft, 0.2, 0.3)
        setupJoystickButton(binding.btnForwardRight, 0.2, -0.3)

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
                    velocityJob?.cancel()
                    velocityJob = lifecycleScope.launch {
                        while (true) {
                            service?.sendVelocity(linear * speedMultiplier, angular * speedMultiplier)
                            delay(100)
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

    private fun speak(text: String) {
        lifecycleScope.launch {6
            // Wait until TTS is ready before trying to speak
            service?.ttsReady?.filter { it }?.first()
            if (binding.switchAudio.isChecked) {
                service?.speak(text)
            }
        }
    }

    private fun observeService() {
        service?.let { svc ->
            lifecycleScope.launch {
                svc.getConnectionState().collect { state ->
                    binding.tvRobotStatus.text = "Robot: ${state.name}"
                    binding.tvRobotStatus.setTextColor(
                        when (state) {
                            ConnectionState.CONNECTED -> ContextCompat.getColor(this@MainActivity, R.color.status_green)
                            ConnectionState.CONNECTING -> ContextCompat.getColor(this@MainActivity, R.color.status_yellow)
                            else -> ContextCompat.getColor(this@MainActivity, R.color.status_red)
                        }
                    )
                    if (state != ConnectionState.CONNECTING) {
                        speak("Robot ${state.name.lowercase()}")
                    }
                }
            }

            lifecycleScope.launch {
                svc.getRobotStatus().collect { status ->
                    status?.let {
                        binding.tvBattery.text = "Battery: ${it.battery}%"
                        binding.tvPosition.text = String.format("Pos: (%.2f, %.2f) θ=%.1f°", it.x, it.y, Math.toDegrees(it.theta))
                        binding.tvVelocity.text = String.format("Vel: %.2f m/s, %.2f rad/s", it.velocity.getOrElse(0) { 0.0 }, it.velocity.getOrElse(1) { 0.0 })
                        binding.tvNavStatus.text = "Nav: ${getNavStatusText(it.navStatus)}"
                        binding.tvEstop.text = if (it.softEstop || it.hardEstop) "E-STOP ACTIVE" else ""
                        binding.tvEstop.visibility = if (it.softEstop || it.hardEstop) View.VISIBLE else View.GONE
                        updateSensorStatus(it.sensors, it.safetyZone)
                        updateSlamStatus(it.controlState)
                    }
                }
            }

            lifecycleScope.launch {
                svc.getRobotStatus().map { it?.safetyZone }.distinctUntilChanged().collect { zone ->
                    when (zone) {
                        SafetyZone.STOP -> speak("Stop. Obstacle too close.")
                        SafetyZone.CREEP -> speak("Obstacle ahead. Creeping.")
                        SafetyZone.WARN -> speak("Warning. Obstacle detected.")
                        else -> {}
                    }
                }
            }

            lifecycleScope.launch {
                svc.getRobotStatus().map { it?.navStatus }.distinctUntilChanged().collect { navStatus ->
                    when (navStatus) {
                        SmaitProtocol.NAV_SUCCESS -> speak("Navigation successful.")
                        SmaitProtocol.NAV_FAILED -> speak("Navigation failed.")
                        SmaitProtocol.NAV_CANCELLED -> speak("Navigation cancelled.")
                    }
                }
            }

            lifecycleScope.launch {
                svc.isRelayRunning().collect { running ->
                    binding.tvRelayStatus.text = if (running) "Relay: Active" else "Relay: Stopped"
                }
            }

            lifecycleScope.launch {
                svc.getConnectedClients().collect { count ->
                    binding.tvClients.text = "Clients: $count"
                }
            }
        }
    }

    private fun updateSlamStatus(controlState: Int) {
        when (controlState) {
            SmaitProtocol.STATE_MAPPING -> {
                binding.tvSlamStatus.text = "Mode: Mapping"
                binding.ivSlamIcon.visibility = View.VISIBLE
            }
            SmaitProtocol.STATE_NAVIGATION -> {
                binding.tvSlamStatus.text = "Mode: Navigating"
                binding.ivSlamIcon.visibility = View.GONE
            }
            else -> {
                if (binding.tvSlamStatus.text.toString().contains("Navigating") ||
                    binding.tvSlamStatus.text.toString().contains("Mapping")) {
                    binding.tvSlamStatus.text = "Mode: Idle"
                    binding.ivSlamIcon.visibility = View.GONE
                }
            }
        }
    }

    private fun updateSensorStatus(sensors: SensorStatus, zone: SafetyZone) {
        val warnings = mutableListOf<String>()
        if (sensors.bumperLeft) warnings.add("Bumper L")
        if (sensors.bumperCenter) warnings.add("Bumper C")
        if (sensors.bumperRight) warnings.add("Bumper R")
        if (sensors.cliffLeft) warnings.add("Cliff L")
        if (sensors.cliffCenter) warnings.add("Cliff C")
        if (sensors.cliffRight) warnings.add("Cliff R")

        if (warnings.isNotEmpty()) {
            binding.tvSensorStatus.text = "SENSORS: ${warnings.joinToString(", ")}"
            binding.tvSensorStatus.setTextColor(ContextCompat.getColor(this, R.color.status_red))
            return
        }

        when (zone) {
            SafetyZone.STOP -> {
                binding.tvSensorStatus.text = "LIDAR: STOP!"
                binding.tvSensorStatus.setTextColor(ContextCompat.getColor(this, R.color.status_red))
            }
            SafetyZone.CREEP -> {
                binding.tvSensorStatus.text = "LIDAR: Creeping"
                binding.tvSensorStatus.setTextColor(ContextCompat.getColor(this, R.color.status_yellow))
            }
            SafetyZone.WARN -> {
                binding.tvSensorStatus.text = "LIDAR: Warning"
                binding.tvSensorStatus.setTextColor(ContextCompat.getColor(this, R.color.status_yellow))
            }
            SafetyZone.CLEAR -> {
                binding.tvSensorStatus.text = "Sensors: OK"
                binding.tvSensorStatus.setTextColor(ContextCompat.getColor(this, R.color.status_green))
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
