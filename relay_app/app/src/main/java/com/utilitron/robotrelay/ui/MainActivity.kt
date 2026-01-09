package com.utilitron.robotrelay.ui

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
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import com.utilitron.robotrelay.R
import com.utilitron.robotrelay.databinding.ActivityMainBinding
import com.utilitron.robotrelay.protocol.ChassisProtocol
import com.utilitron.robotrelay.service.ConnectionState
import com.utilitron.robotrelay.service.RelayService
import com.utilitron.robotrelay.service.SafetyZone
import com.utilitron.robotrelay.service.SensorStatus
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

    // Tour mode state
    private var isTourModeActive = false
    private var tourUnlockPin = "1234"  // Default PIN, can be configured
    private var standbySequenceId: String? = null
    private var standbyButtonText: String? = "Start Tour"


    // Multi-tap unlock sequence
    private val requiredTaps = 6
    private var tapCount = 0
    private var lastTapTime = 0L
    private val tapResetTimeMs = 2000L  // Reset tap count if no tap within 2 seconds
    private var warningSaid = false  // Prevent repeated warnings

    // Motion standby state
    private var currentMotionSequenceId: String? = null

    private val displayReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val url = intent?.getStringExtra(RelayService.EXTRA_URL)
            Log.i(TAG, ">>> displayReceiver.onReceive: url='${url?.take(100) ?: "null"}...'")
            if (url.isNullOrEmpty()) {
                Log.i(TAG, "Hiding WebView and motion overlay, showing main layout")
                binding.webView.visibility = View.GONE
                binding.motionOverlay.visibility = View.GONE
                binding.mainLayout.visibility = View.VISIBLE
            } else if (url.startsWith("motion://")) {
                // Handle motion standby URLs
                handleMotionUrl(url)
            } else if (url.startsWith("default://")) {
                // Handle default POI display (could be custom branding)
                handleDefaultDisplay(url)
            } else {
                Log.i(TAG, "Showing WebView, loading URL")
                binding.mainLayout.visibility = View.GONE
                binding.motionOverlay.visibility = View.GONE
                binding.webView.visibility = View.VISIBLE
                binding.webView.loadUrl(url)
            }
        }
    }

    private fun handleMotionUrl(url: String) {
        Log.i(TAG, "Handling motion URL: $url")
        binding.mainLayout.visibility = View.GONE
        binding.webView.visibility = View.GONE
        binding.motionOverlay.visibility = View.VISIBLE

        when {
            url.startsWith("motion://standby") -> {
                // Extract sequence ID from URL
                val sequenceId = url.substringAfter("sequence=", "")
                currentMotionSequenceId = sequenceId
                Log.i(TAG, "Motion standby mode for sequence: $sequenceId")

                // Show waiting state
                binding.motionWaitingLayout.visibility = View.VISIBLE
                binding.motionStartLayout.visibility = View.GONE
            }
            url.startsWith("motion://start_tour") -> {
                // Extract sequence ID and button text from URL
                // Format: motion://start_tour?sequence=xxx&button=Start%20Tour
                val params = url.substringAfter("?").split("&").associate {
                    val parts = it.split("=", limit = 2)
                    if (parts.size == 2) parts[0] to parts[1] else parts[0] to ""
                }
                val sequenceId = params["sequence"] ?: ""
                val buttonText = try {
                    java.net.URLDecoder.decode(params["button"] ?: "Start Tour", "UTF-8")
                } catch (e: Exception) {
                    "Start Tour"
                }
                currentMotionSequenceId = sequenceId
                Log.i(TAG, "Motion start_tour mode for sequence: $sequenceId, button: $buttonText")

                // Show start tour button with custom text
                binding.motionWaitingLayout.visibility = View.GONE
                binding.motionStartLayout.visibility = View.VISIBLE
                binding.btnStartTour.text = buttonText
            }
        }
    }

    private fun handleDefaultDisplay(url: String) {
        // default://waypoint/KitchenArea -> show POI name with branding
        val waypoint = url.substringAfter("default://waypoint/", "Unknown")
        Log.i(TAG, "Default display for waypoint: $waypoint")

        // For now, use WebView with a simple data URL showing the waypoint name
        // In production, this could load a company branding page
        val html = """
            <!DOCTYPE html>
            <html>
            <head>
                <style>
                    body {
                        background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
                        color: white;
                        font-family: Arial, sans-serif;
                        display: flex;
                        justify-content: center;
                        align-items: center;
                        height: 100vh;
                        margin: 0;
                        text-align: center;
                    }
                    .container {
                        padding: 48px;
                    }
                    .icon { font-size: 128px; }
                    .waypoint {
                        font-size: 64px;
                        font-weight: bold;
                        margin-top: 32px;
                    }
                    .subtitle {
                        font-size: 24px;
                        color: #888;
                        margin-top: 16px;
                    }
                </style>
            </head>
            <body>
                <div class="container">
                    <div class="icon">📍</div>
                    <div class="waypoint">$waypoint</div>
                    <div class="subtitle">Welcome to this location</div>
                </div>
            </body>
            </html>
        """.trimIndent()

        binding.mainLayout.visibility = View.GONE
        binding.motionOverlay.visibility = View.GONE
        binding.webView.visibility = View.VISIBLE
        binding.webView.loadDataWithBaseURL(null, html, "text/html", "UTF-8", null)
    }

    private val countdownReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val seconds = intent?.getIntExtra(RelayService.EXTRA_COUNTDOWN_SECONDS, 0) ?: 0
            val label = intent?.getStringExtra(RelayService.EXTRA_COUNTDOWN_LABEL) ?: "Next stop in"

            Log.i(TAG, ">>> countdownReceiver: seconds=$seconds, label=$label")

            if (seconds > 0) {
                binding.countdownOverlay.visibility = View.VISIBLE
                binding.tvCountdownLabel.text = label
                binding.tvCountdownTimer.text = formatTime(seconds)
            } else {
                binding.countdownOverlay.visibility = View.GONE
            }
        }
    }

    private val tourModeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val action = intent?.getStringExtra(RelayService.EXTRA_TOUR_ACTION)
            val pin = intent?.getStringExtra(RelayService.EXTRA_TOUR_PIN)

            Log.i(TAG, ">>> tourModeReceiver: action=$action")

            when (action) {
                "start" -> {
                    isTourModeActive = true
                    if (!pin.isNullOrEmpty()) {
                        tourUnlockPin = pin
                    }
                    showLockScreen()
                }
                "stop" -> {
                    isTourModeActive = false
                    hideLockScreen()
                }
            }
        }
    }

    private val tourStandbyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            standbySequenceId = intent?.getStringExtra(RelayService.EXTRA_TOUR_SEQUENCE_ID)
            standbyButtonText = intent?.getStringExtra(RelayService.EXTRA_TOUR_BUTTON_TEXT) ?: "Start Tour"
            Log.i(TAG, ">>> tourStandbyReceiver: sequenceId=$standbySequenceId, buttonText=$standbyButtonText")

            // Show the START TOUR button overlay for visitors
            // This works whether or not tour mode lock is active
            if (standbySequenceId != null) {
                isTourModeActive = true  // Enable tour mode to show lock screen with button
                showLockScreen()
                Log.i(TAG, "Showing START TOUR button for visitor")
            }
        }
    }


    private fun formatTime(seconds: Int): String {
        val mins = seconds / 60
        val secs = seconds % 60
        return if (mins > 0) {
            String.format("%d:%02d", mins, secs)
        } else {
            String.format("0:%02d", secs)
        }
    }

    private fun handleLockScreenTap() {
        val now = System.currentTimeMillis()

        // Reset tap count if too much time passed
        if (now - lastTapTime > tapResetTimeMs) {
            tapCount = 0
            warningSaid = false
            // Hide lock content if it was showing progress
            binding.lockContentLayout.visibility = View.GONE
        }

        lastTapTime = now
        tapCount++

        Log.d(TAG, "Lock screen tap: $tapCount / $requiredTaps")

        when {
            tapCount >= requiredTaps -> {
                // Enough taps - show PIN entry
                Log.i(TAG, "Multi-tap sequence complete, showing PIN entry")
                tapCount = 0
                warningSaid = false
                showPinEntry()
            }
            tapCount == 1 && !warningSaid -> {
                // First tap - speak warning
                warningSaid = true
                service?.speak("Please do not touch the screen until asked to do so. Thank you!")
            }
            tapCount >= 3 -> {
                // Show lock content and give feedback they're getting close
                binding.lockContentLayout.visibility = View.VISIBLE
                binding.tvLockMessage.text = "Tap ${requiredTaps - tapCount} more times..."
            }
        }
    }

    private fun showLockScreen() {
        binding.lockOverlay.visibility = View.VISIBLE
        binding.lockContentLayout.visibility = View.GONE  // Start invisible - only show after 3+ taps
        binding.pinEntryLayout.visibility = View.GONE
        binding.etPinCode.text?.clear()
        binding.tvLockMessage.text = "Tour Mode Active"
        tapCount = 0
        warningSaid = false

        // Show START TOUR button for visitors if a sequence is in standby
        if (standbySequenceId != null) {
            binding.lockStartTourLayout.visibility = View.VISIBLE
            binding.btnLockStartTour.text = standbyButtonText
        } else {
            binding.lockStartTourLayout.visibility = View.GONE
        }
    }

    private fun hideLockScreen() {
        binding.lockOverlay.visibility = View.GONE
        binding.lockContentLayout.visibility = View.GONE
        binding.pinEntryLayout.visibility = View.GONE
        binding.lockStartTourLayout.visibility = View.GONE
        // Clear standby state when screen is unlocked/hidden
        standbySequenceId = null
        standbyButtonText = "Start Tour"
    }


    private fun showPinEntry() {
        binding.lockContentLayout.visibility = View.VISIBLE
        binding.pinEntryLayout.visibility = View.VISIBLE
        binding.tvLockMessage.text = "Enter Unlock PIN"
        binding.etPinCode.requestFocus()
    }

    private fun attemptUnlock() {
        val enteredPin = binding.etPinCode.text?.toString() ?: ""
        if (enteredPin == tourUnlockPin) {
            Log.i(TAG, "Tour mode unlocked with correct PIN")
            hideLockScreen()
            isTourModeActive = false
            // Notify Flutter that tour mode was unlocked
            service?.notifyTourUnlocked()
        } else {
            Log.w(TAG, "Incorrect PIN entered")
            Toast.makeText(this, "Incorrect PIN", Toast.LENGTH_SHORT).show()
            binding.etPinCode.text?.clear()
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
        val localBroadcastManager = LocalBroadcastManager.getInstance(this)
        localBroadcastManager.registerReceiver(displayReceiver, IntentFilter(RelayService.ACTION_DISPLAY))
        localBroadcastManager.registerReceiver(countdownReceiver, IntentFilter(RelayService.ACTION_COUNTDOWN))
        localBroadcastManager.registerReceiver(tourModeReceiver, IntentFilter(RelayService.ACTION_TOUR_MODE))
        localBroadcastManager.registerReceiver(tourStandbyReceiver, IntentFilter(RelayService.ACTION_TOUR_STANDBY))
    }

    override fun onStop() {
        super.onStop()
        if (bound) {
            unbindService(connection)
            bound = false
        }
        val localBroadcastManager = LocalBroadcastManager.getInstance(this)
        localBroadcastManager.unregisterReceiver(displayReceiver)
        localBroadcastManager.unregisterReceiver(countdownReceiver)
        localBroadcastManager.unregisterReceiver(tourModeReceiver)
        localBroadcastManager.unregisterReceiver(tourStandbyReceiver)
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

        // btnStop removed - joystick auto-stops when released
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

        // Setup circular joystick
        binding.joystickView.onMoveListener = { x, y ->
            // x and y are -1.0 to 1.0
            // Y-axis: negative = up (reverse away from operator), positive = down (forward toward operator)
            // X-axis: negative = left, positive = right
            // When moving FORWARD (toward operator), left/right are inverted (you're facing the robot)
            // When moving BACKWARD (away from operator), left/right are normal

            val maxLinearSpeed = 0.4 * speedMultiplier
            val maxAngularSpeed = 0.8 * speedMultiplier

            // Convert joystick position to robot velocities
            val linearVel = y * maxLinearSpeed  // y positive = down = forward toward operator

            // Invert angular when moving forward (linearVel > 0), normal when reversing
            val angularVel = if (linearVel > 0) {
                x * maxAngularSpeed  // Forward: joystick left = robot turns right (from your perspective)
            } else {
                -x * maxAngularSpeed  // Reverse: joystick left = robot turns left (normal)
            }

            if (x == 0f && y == 0f) {
                // Joystick centered - stop robot
                service?.stop()
            } else {
                // Send velocity command
                service?.sendVelocity(linearVel.toDouble(), angularVel.toDouble())
            }
        }

        binding.btnGoPoi.setOnClickListener {
            val poi = binding.etPoi.text.toString()
            if (poi.isNotBlank()) {
                service?.navigateTo(poi)
            }
        }

        // Lock screen handlers - multi-tap sequence to unlock
        binding.lockOverlay.setOnClickListener {
            handleLockScreenTap()
        }

        binding.btnPinCancel.setOnClickListener {
            binding.pinEntryLayout.visibility = View.GONE
            binding.lockContentLayout.visibility = View.GONE
            tapCount = 0
            warningSaid = false
        }

        binding.btnPinSubmit.setOnClickListener {
            attemptUnlock()
        }

        // Motion standby "Start Tour" button handler
        binding.btnStartTour.setOnClickListener {
            Log.i(TAG, "Start Tour button pressed for sequence: $currentMotionSequenceId")
            // Notify the service that the tour was started by button press
            service?.notifyTourStarted(currentMotionSequenceId ?: "")
            // Hide motion overlay
            binding.motionOverlay.visibility = View.GONE
            // Engage tour mode lock screen to prevent tampering during tour
            service?.startTourMode(null)
        }

        // Lock screen START TOUR button - for visitors to manually start tour
        binding.btnLockStartTour.setOnClickListener {
            Log.i(TAG, "Lock screen START TOUR pressed - starting sequence: $standbySequenceId")
            standbySequenceId?.let { seqId ->
                // Start the sequence - greeting comes from buffer (motion_standby or intro text)
                // DON'T speak here - it would overlap with the buffer's intro text!
                service?.notifyTourStarted(seqId)
            }
            // Hide the start button after pressing, tour is now active
            binding.lockStartTourLayout.visibility = View.GONE
            // Also clear the standby state
            standbySequenceId = null
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
        lifecycleScope.launch {
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
                var announcedThisNav = SafetyZone.CLEAR  // Track highest announced this nav session
                var lastNavStatus = 0
                var lastWarningTime = 0L  // Cooldown timer to prevent rapid-fire warnings

                svc.getRobotStatus()
                    .collect { status ->
                        val zone = status?.safetyZone ?: SafetyZone.CLEAR
                        val navStatus = status?.navStatus ?: 0
                        val now = System.currentTimeMillis()

                        // Reset when nav starts fresh
                        if (navStatus == ChassisProtocol.NAV_RUNNING && lastNavStatus != ChassisProtocol.NAV_RUNNING) {
                            announcedThisNav = SafetyZone.CLEAR
                            lastWarningTime = 0L  // Reset cooldown on new navigation
                        }
                        lastNavStatus = navStatus

                        // Only announce during active navigation
                        if (navStatus != ChassisProtocol.NAV_RUNNING) return@collect

                        // Severity: CLEAR(0) < WARN(1) < CREEP(2) < STOP(3)
                        val zoneSeverity = when (zone) {
                            SafetyZone.STOP -> 3
                            SafetyZone.CREEP -> 2
                            SafetyZone.WARN -> 1
                            else -> 0
                        }
                        val announcedSeverity = when (announcedThisNav) {
                            SafetyZone.STOP -> 3
                            SafetyZone.CREEP -> 2
                            SafetyZone.WARN -> 1
                            else -> 0
                        }

                        // Skip if not more severe than already announced
                        if (zoneSeverity <= announcedSeverity) return@collect

                        // Cooldown: 3s for WARN, 2s for CREEP, 0 for STOP (always immediate)
                        val cooldownMs = when (zone) {
                            SafetyZone.WARN -> 3000L
                            SafetyZone.CREEP -> 2000L
                            else -> 0L
                        }
                        if (now - lastWarningTime < cooldownMs) return@collect

                        // Skip WARN level entirely during active navigation - too noisy
                        // Only CREEP and STOP matter when robot is moving/turning
                        if (zone == SafetyZone.WARN) return@collect

                        announcedThisNav = zone
                        lastWarningTime = now
                        when (zone) {
                            SafetyZone.STOP -> speak("Stop. Obstacle too close.")
                            SafetyZone.CREEP -> speak("Make way please.")
                            else -> {}
                        }
                    }
            }

            lifecycleScope.launch {
                svc.getRobotStatus().map { it?.navStatus }.distinctUntilChanged().collect { navStatus ->
                    when (navStatus) {
                        ChassisProtocol.NAV_SUCCESS -> speak("Navigation successful.")
                        ChassisProtocol.NAV_FAILED -> speak("Navigation failed.")
                        ChassisProtocol.NAV_CANCELLED -> speak("Navigation cancelled.")
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
            ChassisProtocol.STATE_MAPPING -> {
                binding.tvSlamStatus.text = "Mode: Mapping"
                binding.ivSlamIcon.visibility = View.VISIBLE
            }
            ChassisProtocol.STATE_NAVIGATION -> {
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
