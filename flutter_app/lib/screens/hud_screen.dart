import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../core/robot_connection.dart';
import '../core/sequence_mode.dart'
    show SequenceManager, SequenceStatus, SequencePhase, Sequence;
import '../core/smait_protocol.dart' as protocol;
import '../core/task_engine.dart';
import '../utils/file_utils.dart';
import '../services/audio_announcer.dart';
import '../widgets/map_view.dart';
import '../widgets/joystick.dart';
import '../widgets/sequence_editor.dart';
import '../widgets/voice_control.dart';
import '../widgets/fleet_picker.dart';
import '../widgets/crowd_logic_settings.dart';
import '../widgets/announcement_presets.dart';
import '../widgets/mode_editor.dart';

/// Connection mode options for HUD
enum ConnectionMode {
  direct('Direct WiFi', 'ws://10.42.0.1:9090', Icons.wifi),
  relayWs('Relay WS', 'ws://192.168.1.100:8766', Icons.router),
  relayHttp('Relay HTTP', 'http://192.168.1.100:8765', Icons.http);

  final String label;
  final String defaultUrl;
  final IconData icon;
  const ConnectionMode(this.label, this.defaultUrl, this.icon);
}

/// HUD-style cockpit layout for landscape tablet control
/// Inspired by spaceship cockpit / video game HUD design
class HudScreen extends StatefulWidget {
  const HudScreen({super.key});

  @override
  State<HudScreen> createState() => _HudScreenState();
}

class _HudScreenState extends State<HudScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver
    implements TaskExecutorCallback {
  final _urlController = TextEditingController();
  final _customSoundController = TextEditingController();

  // Edge panel states
  bool _leftPanelExpanded = true;
  bool _rightPanelExpanded = true;

  // Debug flag for verbose logging
  static const bool _enableVerboseLogging = false;
  bool _bottomPanelExpanded = false;

  // Left panel tab (0 = waypoints, 1 = tour, 2 = crowd)
  int _leftPanelTab = 0;

  // Map info from MapView callback
  MapInfo? _mapInfo;
  double _robotX = 0;
  double _robotY = 0;

  // Connection mode
  ConnectionMode _connectionMode = ConnectionMode.direct;

  // Task engine integration
  final _taskEngine = TaskEngine.instance;
  String? _navigatingTo;
  String? _lastWaypoint;
  int? _lastNavStatus;

  // Animation controllers for smooth panel transitions
  late AnimationController _leftPanelController;
  late AnimationController _rightPanelController;
  late AnimationController _bottomPanelController;

  // Wake lock state - keeps screen on during tours
  bool _wakelockEnabled = false;

  // Cyberpunk accent color
  static const _accentColor = Color(0xFF00D4FF); // Cyan glow
  static const _accentSecondary = Color(0xFF00FF88); // Green glow
  static const _dangerColor = Color(0xFFFF3366); // Red/Pink warning

  @override
  void initState() {
    super.initState();

    // Register for app lifecycle events (to handle screen lock/unlock)
    WidgetsBinding.instance.addObserver(this);

    // Force landscape on tablets
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _leftPanelController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
      value: 1.0,
    );
    _rightPanelController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
      value: 1.0,
    );
    _bottomPanelController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
      value: 0.0,
    );

    // Initialize TaskEngine
    _loadTaskEngine();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final robot = context.read<RobotConnection>();
      final savedUrl = robot.robotUrl;

      debugPrint('=== HUD SCREEN INIT ===');
      debugPrint('Loaded URL from robot: $savedUrl');

      _urlController.text = savedUrl;

      // Load saved connection mode
      final hadSavedMode = await _loadConnectionMode();
      debugPrint(
          'Had saved mode: $hadSavedMode, Current mode: ${_connectionMode.name}');

      // ONLY detect mode from URL if there was NO saved mode
      if (!hadSavedMode) {
        debugPrint('HUD: No saved mode found, detecting from URL: $savedUrl');
        _detectModeFromUrl(savedUrl);
      } else {
        debugPrint('HUD: Using saved mode: ${_connectionMode.name}');
      }
      debugPrint(
          'Final state - URL: ${_urlController.text}, Mode: ${_connectionMode.name}');
      debugPrint('=== END HUD INIT ===');
    });
  }

  Future<void> _loadTaskEngine() async {
    await _taskEngine.load();
    _taskEngine.setCallback(this);
    if (mounted) setState(() {});
  }

  // === TaskExecutorCallback Implementation ===

  @override
  void onSpeak(String text) {
    AudioAnnouncer().speak(text);
  }

  @override
  void onDisplay(String url, int durationSeconds) {
    final robot = context.read<RobotConnection>();
    if (robot.isConnected) {
      robot.client.tabletDisplay(url);
      if (durationSeconds > 0) {
        Future.delayed(Duration(seconds: durationSeconds), () {
          if (mounted) onCloseDisplay();
        });
      }
    }
  }

  @override
  void onCloseDisplay() {
    final robot = context.read<RobotConnection>();
    if (robot.isConnected) {
      robot.client.tabletCloseDisplay();
    }
  }

  @override
  void onDisplayDefault(String waypoint) {
    final robot = context.read<RobotConnection>();
    if (!robot.isConnected) return;

    final displayName = waypoint
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) =>
            word.isEmpty ? '' : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');

    final html =
        'data:text/html,<html><body style="display:flex;align-items:center;justify-content:center;height:100vh;margin:0;background:%23222;"><h1 style="color:white;font-size:72px;font-family:sans-serif;">$displayName</h1></body></html>';
    robot.client.tabletDisplay(html);
  }

  @override
  void onNavigate(String waypoint) {
    final robot = context.read<RobotConnection>();
    if (robot.isConnected) {
      _goToWaypointInternal(robot, waypoint);
    }
  }

  @override
  void onWait(int seconds) {
    // Wait is handled by TaskEngine timer
  }

  /// Check nav status and execute task on arrival
  void _checkNavStatus(int navStatus, String goalName) {
    if (_lastNavStatus == navStatus) return;
    final previousStatus = _lastNavStatus;
    _lastNavStatus = navStatus;

    debugPrint(
        'HUD: navStatus $previousStatus -> $navStatus, navigatingTo=$_navigatingTo, goal=$goalName');

    // Execute task on arrival (603 = Success/Arrived)
    if (_navigatingTo != null && navStatus == 603) {
      final arrivedAt = _navigatingTo!;
      debugPrint('HUD: Arrival detected at $arrivedAt, executing task...');
      _taskEngine.executeForWaypoint(arrivedAt, fromWaypoint: _lastWaypoint);
      _lastWaypoint = arrivedAt;
    }

    // Clear navigating state on terminal statuses (not 601=Moving)
    if (_navigatingTo != null && navStatus != 601) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _navigatingTo = null);
        }
      });
    }
  }

  Future<void> _goToWaypointInternal(
      RobotConnection robot, String waypoint) async {
    setState(() => _navigatingTo = waypoint);
    await robot.goToWaypoint(waypoint);

    // Quick check: if robot didn't start moving within 1.5s, assume already there
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted &&
          _navigatingTo == waypoint &&
          robot.status.navStatus != 601) {
        setState(() => _navigatingTo = null);
      }
    });
  }

  @override
  void dispose() {
    // Unregister lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    // Release wake lock if active
    if (_wakelockEnabled) {
      WakelockPlus.disable();
      _wakelockEnabled = false;
    }

    _urlController.dispose();
    _customSoundController.dispose();
    _leftPanelController.dispose();
    _rightPanelController.dispose();
    _bottomPanelController.dispose();
    // Restore orientation
    SystemChrome.setPreferredOrientations([]);
    super.dispose();
  }

  /// Handle app lifecycle changes - reconnect when returning from background/lock screen
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('HUD: App lifecycle state changed to: $state');

    if (state == AppLifecycleState.resumed) {
      debugPrint('HUD: App resumed from background - checking connections');
      _onAppResumed();
    } else if (state == AppLifecycleState.paused) {
      debugPrint('HUD: App paused (going to background/lock)');
    }
  }

  /// Called when app returns from background/lock screen
  void _onAppResumed() {
    // Check if robot connection is still alive
    final robot = context.read<RobotConnection>();

    if (robot.state == RobotConnectionState.connected) {
      // Connection might be stale - force a ping/reconnect check
      debugPrint('HUD: Connection appears alive, forcing state refresh');

      // Re-subscribe to topics in case they were dropped
      // The MapView and other widgets will handle their own resubscription
      // via their WebSocket state listeners, but we trigger a check here
      robot.notifyListeners();
    } else if (robot.state == RobotConnectionState.disconnected ||
               robot.state == RobotConnectionState.error) {
      // Connection was lost during background - auto-reconnect
      debugPrint('HUD: Connection lost during background, attempting reconnect');
      final savedUrl = robot.robotUrl;
      if (savedUrl.isNotEmpty) {
        robot.connect(savedUrl);
      }
    }

    // Re-enable wake lock if tour is still running
    final tourManager = context.read<SequenceManager>();
    if (tourManager.status == SequenceStatus.running && !_wakelockEnabled) {
      debugPrint('HUD: Tour still running, re-enabling wake lock');
      _enableWakelock();
    }
  }

  /// Enable wake lock to keep screen on during tours
  void _enableWakelock() {
    if (!_wakelockEnabled) {
      WakelockPlus.enable();
      _wakelockEnabled = true;
      debugPrint('HUD: Wake lock ENABLED - screen will stay on');
    }
  }

  /// Disable wake lock when tour stops
  void _disableWakelock() {
    if (_wakelockEnabled) {
      WakelockPlus.disable();
      _wakelockEnabled = false;
      debugPrint('HUD: Wake lock DISABLED - screen can turn off');
    }
  }

  void _toggleLeftPanel() {
    setState(() => _leftPanelExpanded = !_leftPanelExpanded);
    if (_leftPanelExpanded) {
      _leftPanelController.forward();
    } else {
      _leftPanelController.reverse();
    }
  }

  void _toggleRightPanel() {
    setState(() => _rightPanelExpanded = !_rightPanelExpanded);
    if (_rightPanelExpanded) {
      _rightPanelController.forward();
    } else {
      _rightPanelController.reverse();
    }
  }

  void _toggleBottomPanel() {
    setState(() => _bottomPanelExpanded = !_bottomPanelExpanded);
    if (_bottomPanelExpanded) {
      _bottomPanelController.forward();
    } else {
      _bottomPanelController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E14), // Deep dark blue-black
      body: Consumer<RobotConnection>(
        builder: (context, robot, _) {
          // Check nav status for task execution on arrival
          _checkNavStatus(robot.status.navStatus, robot.status.currentGoal);

          // Check if tour is running to adjust layout
          final tourManager = context.watch<SequenceManager>();
          final tourRunning = tourManager.status == SequenceStatus.running;

          // WAKE LOCK: Keep screen on during tours to prevent connection drops
          // (Update via post-frame callback to avoid setState during build)
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (tourRunning && !_wakelockEnabled) {
              _enableWakelock();
            } else if (!tourRunning && _wakelockEnabled) {
              _disableWakelock();
            }
          });

          // Debug: Log when sequence status changes
          if (_enableVerboseLogging &&
              (tourRunning || tourManager.status != SequenceStatus.idle)) {
            debugPrint(
                'HUD: Sequence status=${tourManager.status}, tourRunning=$tourRunning, phase=${tourManager.currentPhase}, countdown=${tourManager.countdownSeconds}');
          }

          if (robot.state == RobotConnectionState.disconnected ||
              robot.state == RobotConnectionState.error) {
            return _buildConnectionScreen(robot);
          }

          if (robot.state == RobotConnectionState.connecting) {
            return _buildConnectingScreen();
          }

          // Main HUD layout - Map is FULL SCREEN background, panels float on top
          return Stack(
            children: [
              // === LAYER 0: Map with frame (90% - "glass on the table" with bezel) ===
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                top: 60,
                left: _leftPanelExpanded ? 420 : 68,
                right: _rightPanelExpanded ? 276 : 68,
                bottom: 54,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _accentColor.withValues(alpha: 0.4),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: _accentColor.withValues(alpha: 0.15),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: MapView(
                      fullscreen: true,
                      onMapUpdate: (info, x, y) {
                        if (mounted &&
                            (info != _mapInfo ||
                                x != _robotX ||
                                y != _robotY)) {
                          setState(() {
                            _mapInfo = info;
                            _robotX = x;
                            _robotY = y;
                          });
                        }
                      },
                    ),
                  ),
                ),
              ),

              // === LAYER 1: Corner brackets (HUD aesthetic) ===
              ..._buildCornerBrackets(),

              // === LAYER 2: Map info overlay (top center) - hide when tour running ===
              if (_mapInfo != null && !tourRunning)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 200),
                  top: 64,
                  left: _leftPanelExpanded ? 424 : 72,
                  child: _buildMapInfoOverlay(),
                ),

              // === LAYER 2b: Tour overlay when running (prominent, replaces map info) ===
              if (tourRunning)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 200),
                  top: 64,
                  left: _leftPanelExpanded ? 424 : 72,
                  right: _rightPanelExpanded ? 280 : 72,
                  child: _buildTourOverlay(tourManager),
                ),

              // === LAYER 3: Glass panels on top ===
              // Top Status Bar
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildTopStatusBar(robot),
              ),

              // Left Edge Panel (Waypoints / Tour)
              Positioned(
                top: 56,
                left: 0,
                bottom: 50,
                child: _buildLeftPanel(robot, tourRunning, tourManager),
              ),

              // Right Edge Panel (Joystick / Controls)
              Positioned(
                top: 56,
                right: 0,
                bottom: 50,
                child: _buildRightPanel(robot),
              ),

              // Bottom Quick Actions Bar
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildBottomBar(robot),
              ),

              // === LAYER 4: Countdown timer (must be above glass panels) ===
              if (tourRunning && tourManager.countdownSeconds > 0)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 200),
                  bottom: 60,
                  right: _rightPanelExpanded ? 280 : 72,
                  child: _buildLargeCountdownTimer(tourManager),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildConnectionScreen(RobotConnection robot) {
    return Center(
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: const Color(0xFF151A22),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _accentColor.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: _accentColor.withValues(alpha: 0.1),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              robot.state == RobotConnectionState.error
                  ? Icons.error_outline
                  : Icons.precision_manufacturing,
              size: 64,
              color: robot.state == RobotConnectionState.error
                  ? _dangerColor
                  : _accentColor,
            ),
            const SizedBox(height: 16),
            Text(
              robot.state == RobotConnectionState.error
                  ? 'CONNECTION FAILED'
                  : 'DROID CONTROLLER',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: robot.state == RobotConnectionState.error
                    ? _dangerColor
                    : _accentColor,
                letterSpacing: 2,
              ),
            ),
            if (robot.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                robot.errorMessage!,
                style: TextStyle(color: Colors.grey.shade400),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            // Connection mode selector
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: _accentColor.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<ConnectionMode>(
                  value: _connectionMode,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1A1F28),
                  icon: const Icon(Icons.arrow_drop_down, color: _accentColor),
                  items: ConnectionMode.values.map((mode) {
                    return DropdownMenuItem(
                      value: mode,
                      child: Row(
                        children: [
                          Icon(mode.icon, size: 18, color: _accentColor),
                          const SizedBox(width: 10),
                          Text(mode.label,
                              style: const TextStyle(color: _accentColor)),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (mode) {
                    if (mode != null) {
                      setState(() => _connectionMode = mode);

                      // Save the connection mode immediately
                      _saveConnectionMode(mode);

                      // Preserve the current IP, just update protocol/port
                      // NEVER use hardcoded default IPs!
                      final currentUrl = _urlController.text.trim();
                      if (currentUrl.isEmpty) {
                        // Leave empty - user must enter their IP
                        return;
                      }

                      final uri = Uri.tryParse(currentUrl);
                      final host = uri?.host ?? '';
                      if (host.isNotEmpty) {
                        // Preserve IP, update protocol/port to match mode
                        if (mode == ConnectionMode.direct) {
                          _urlController.text = 'ws://$host:9090';
                        } else if (mode == ConnectionMode.relayWs) {
                          _urlController.text = 'ws://$host:8766';
                        } else {
                          _urlController.text = 'http://$host:8765';
                        }
                      }
                      // If host is empty, leave URL as-is (don't replace with hardcoded)
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    decoration: InputDecoration(
                      labelText: 'Robot URL',
                      hintText: 'Enter robot IP (e.g., 192.168.x.x)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                            color: _accentColor.withValues(alpha: 0.3)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                            color: _accentColor.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: _accentColor),
                      ),
                      prefixIcon: const Icon(Icons.link, color: _accentColor),
                    ),
                    style: const TextStyle(fontFamily: 'monospace'),
                    onSubmitted: (_) => _connect(robot),
                  ),
                ),
                const SizedBox(width: 12),
                const FleetConnectButton(),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _connect(robot),
                icon: const Icon(Icons.power_settings_new),
                label: const Text('CONNECT'),
                style: FilledButton.styleFrom(
                  backgroundColor: _accentColor,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectingScreen() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 80,
            height: 80,
            child: CircularProgressIndicator(
              color: _accentColor,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'INITIALIZING LINK...',
            style: TextStyle(
              fontSize: 18,
              color: _accentColor,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Discovering robot capabilities',
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCornerBrackets() {
    const bracketSize = 24.0;
    const bracketThickness = 2.0;
    final bracketColor = _accentColor.withValues(alpha: 0.4);

    Widget bracket(bool top, bool left) {
      return Positioned(
        top: top ? 8 : null,
        bottom: top ? null : 8,
        left: left ? 8 : null,
        right: left ? null : 8,
        child: CustomPaint(
          size: const Size(bracketSize, bracketSize),
          painter: _BracketPainter(
            color: bracketColor,
            thickness: bracketThickness,
            top: top,
            left: left,
          ),
        ),
      );
    }

    return [
      bracket(true, true),
      bracket(true, false),
      bracket(false, true),
      bracket(false, false),
    ];
  }

  Widget _buildMapInfoOverlay() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _accentColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.map, color: _accentColor, size: 14),
          const SizedBox(width: 6),
          Text(
            '${_mapInfo!.width}x${_mapInfo!.height}',
            style: const TextStyle(
              color: _accentColor,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.location_on, color: _accentSecondary, size: 14),
          const SizedBox(width: 4),
          Text(
            '(${_robotX.toStringAsFixed(1)}, ${_robotY.toStringAsFixed(1)})',
            style: const TextStyle(
              color: _accentSecondary,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTourOverlay(SequenceManager tourManager) {
    final seq = tourManager.currentSequence;
    final phase = tourManager.currentPhase;
    final countdown = tourManager.countdownSeconds;
    final phaseDuration = tourManager.phaseDurationSeconds;
    final stopIndex = tourManager.currentStopIndex;
    final stop = tourManager.currentStop;
    final status = tourManager.status;

    if (_enableVerboseLogging) {
      debugPrint(
          'HUD._buildTourOverlay: seq=${seq?.name}, phase=$phase, countdown=$countdown, stopIndex=$stopIndex, status=$status');
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: _accentSecondary.withValues(alpha: 0.6), width: 2),
        boxShadow: [
          BoxShadow(
            color: _accentSecondary.withValues(alpha: 0.2),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top row: Tour name + controls
          Row(
            children: [
              // Countdown circle with phase icon
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: _getPhaseColor(phase).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: _getPhaseColor(phase), width: 2),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (countdown > 0 && phaseDuration > 0)
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: CircularProgressIndicator(
                          value: countdown / phaseDuration,
                          strokeWidth: 4,
                          backgroundColor: Colors.grey.shade800,
                          color: _getPhaseColor(phase),
                        ),
                      ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(phase.icon,
                            size: 16, color: _getPhaseColor(phase)),
                        if (countdown > 0)
                          Text(
                            '${countdown}s',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: _getPhaseColor(phase),
                              fontFamily: 'monospace',
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Tour info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getPhaseColor(phase),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            phase.label.replaceAll('...', ''),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            seq?.name ?? 'Mode',
                            style: const TextStyle(
                              color: _accentSecondary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (stop != null)
                      Row(
                        children: [
                          Icon(Icons.location_on,
                              size: 12, color: Colors.grey.shade400),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              stop.waypoint,
                              style: TextStyle(
                                  color: Colors.grey.shade300, fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${stopIndex + 1}/${seq?.stops.length ?? 0}',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Control buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // START TOUR button - only shows when idle (not started yet)
                  if (seq?.startWaypoint != null &&
                      status == SequenceStatus.idle) ...[
                    _MiniControlButton(
                      icon: Icons.rocket_launch,
                      color: Colors.green,
                      onTap: () {
                        debugPrint('START TOUR - trigger welcome screen');
                        // Enable motion trigger to show welcome screen
                        final motionSequence = seq!.copyWith(
                          motionTriggerStart: true,
                          motionGreeting: 'Hello! Would you like a tour?',
                          motionButtonText: 'START TOUR',
                        );
                        tourManager.startSequence(motionSequence);
                      },
                      tooltip: 'Start Tour',
                    ),
                    const SizedBox(width: 4),
                  ],
                  // Skip button
                  _MiniControlButton(
                    icon: Icons.skip_next,
                    color: _accentColor,
                    onTap: tourManager.skipToNextStop,
                    tooltip: 'Skip',
                  ),
                  const SizedBox(width: 4),
                  // Pause/Resume button
                  _MiniControlButton(
                    icon: status == SequenceStatus.paused
                        ? Icons.play_arrow
                        : Icons.pause,
                    color: Colors.orange,
                    onTap: status == SequenceStatus.paused
                        ? tourManager.resumeSequence
                        : tourManager.pauseSequence,
                    tooltip:
                        status == SequenceStatus.paused ? 'Resume' : 'Pause',
                  ),
                  const SizedBox(width: 4),
                  // Stop button
                  _MiniControlButton(
                    icon: Icons.stop,
                    color: _dangerColor,
                    onTap: tourManager.stopSequence,
                    tooltip: 'Stop',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Stop progress bar
          _buildStopProgressBar(seq, stopIndex),
        ],
      ),
    );
  }

  /// Build large countdown timer for bottom right corner
  /// Visible from a distance so people know the robot is waiting
  Widget _buildLargeCountdownTimer(SequenceManager tourManager) {
    final countdown = tourManager.countdownSeconds;
    final phase = tourManager.currentPhase;
    final stop = tourManager.currentStop;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _getPhaseColor(phase).withValues(alpha: 0.8),
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: _getPhaseColor(phase).withValues(alpha: 0.4),
            blurRadius: 20,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Large countdown number
          Text(
            '$countdown',
            style: TextStyle(
              fontSize: 56,
              fontWeight: FontWeight.bold,
              color: _getPhaseColor(phase),
              fontFamily: 'monospace',
              height: 1,
            ),
          ),
          const SizedBox(width: 12),
          // Phase info
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(phase.icon, size: 20, color: _getPhaseColor(phase)),
                  const SizedBox(width: 6),
                  Text(
                    phase.label.replaceAll('...', ''),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _getPhaseColor(phase),
                    ),
                  ),
                ],
              ),
              if (stop != null) ...[
                const SizedBox(height: 2),
                Text(
                  'at ${stop.waypoint}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade400,
                  ),
                ),
              ],
              Text(
                'seconds',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build stop progress bar showing completed/current/pending stops
  Widget _buildStopProgressBar(Sequence? seq, int currentIndex) {
    if (seq == null || seq.stops.isEmpty) return const SizedBox.shrink();

    return Row(
      children: List.generate(seq.stops.length, (index) {
        final isCompleted = index < currentIndex;
        final isCurrent = index == currentIndex;
        return Expanded(
          child: Container(
            height: 4,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: isCompleted
                  ? _accentSecondary
                  : isCurrent
                      ? _accentSecondary.withValues(alpha: 0.5)
                      : Colors.grey.shade700,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }

  /// Get color for sequence phase
  Color _getPhaseColor(SequencePhase phase) {
    switch (phase) {
      case SequencePhase.navigating:
        return Colors.blue;
      case SequencePhase.arriving:
        return _accentSecondary;
      case SequencePhase.speaking:
        return Colors.orange;
      case SequencePhase.displaying:
        return Colors.purple;
      case SequencePhase.waiting:
        return Colors.teal;
      case SequencePhase.awaitingVisitor:
        return Colors.amber;
    }
  }

  // Frontier Tower floors (to be populated from cloud)
  static const List<String> _floors = [
    'Robotics Floor', // 4th floor - current working floor
    'Spaceship', // Event floor - 2nd floor (large, stored in base)
    'Lobby', // Ground floor
    'Mezzanine', // Between floors
    'Rooftop', // Top floor events
  ];
  String _selectedFloor = 'Robotics Floor';

  void _showFloorsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F2E),
        title: Row(
          children: [
            Image.asset(
              'assets/frontiertowerlogo.jpeg',
              height: 32,
              width: 32,
              errorBuilder: (ctx, err, stack) =>
                  const Icon(Icons.business, color: Color(0xFF9333EA)),
            ),
            const SizedBox(width: 12),
            const Text('Frontier Tower',
                style: TextStyle(color: Color(0xFF9333EA))),
          ],
        ),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select Floor',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 8),
              ...List.generate(_floors.length, (i) {
                final floor = _floors[i];
                final isSelected = floor == _selectedFloor;
                return ListTile(
                  leading: Icon(
                    floor == 'Robotics Floor'
                        ? Icons.precision_manufacturing
                        : floor == 'Spaceship'
                            ? Icons.rocket_launch
                            : floor == 'Lobby'
                                ? Icons.door_front_door
                                : floor == 'Mezzanine'
                                    ? Icons.stairs
                                    : Icons.roofing,
                    color: isSelected ? const Color(0xFF9333EA) : Colors.grey,
                  ),
                  title: Text(floor,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      )),
                  trailing: isSelected
                      ? const Icon(Icons.check, color: Color(0xFF9333EA))
                      : null,
                  selected: isSelected,
                  selectedTileColor:
                      const Color(0xFF9333EA).withValues(alpha: 0.1),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  onTap: () {
                    setState(() => _selectedFloor = floor);
                    Navigator.pop(ctx);
                  },
                );
              }),
              const SizedBox(height: 16),
              Text(
                'More floors coming soon as we scan them!',
                style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 11,
                    fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildTopStatusBar(RobotConnection robot) {
    final status = robot.status;
    final tourManager = context.watch<SequenceManager>();
    final tourRunning = tourManager.status == SequenceStatus.running;
    final tourPaused = tourManager.status == SequenceStatus.paused;
    final currentSequence = tourManager.currentSequence;

    return Container(
      height: 52,
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E14).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _accentColor.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8),
        ],
      ),
      child: Row(
        children: [
          // Frontier Tower Logo
          GestureDetector(
            onTap: () => _showFloorsDialog(),
            child: Row(
              children: [
                Image.asset(
                  'assets/frontiertowerlogo.jpeg',
                  height: 36,
                  width: 36,
                  errorBuilder: (ctx, err, stack) => Container(
                    height: 36,
                    width: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6B21A8), // Purple
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Center(
                      child: Text('FT',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          )),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'FRONTIER TOWER',
                      style: TextStyle(
                        color: Color(0xFF9333EA), // Purple
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        letterSpacing: 1.2,
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.layers, size: 12, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          _selectedFloor,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11),
                        ),
                        const Icon(Icons.arrow_drop_down,
                            size: 14, color: Colors.grey),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
              width: 1, height: 32, color: Colors.grey.withValues(alpha: 0.3)),
          const SizedBox(width: 12),

          // Connection status - tap to open fleet picker
          GestureDetector(
            onTap: () => _showFleetPicker(robot),
            child: _HudChip(
              icon: Icons.router,
              label: robot.robotUrl.contains('10.42.0.1') ? 'DIRECT' : 'RELAY',
              color: _accentSecondary,
            ),
          ),
          const SizedBox(width: 12),

          // Battery
          _HudChip(
            icon: _batteryIcon(status.battery),
            label: '${status.battery.toStringAsFixed(0)}%',
            color: _batteryColor(status.battery),
          ),

          // Charging indicator
          if (status.isCharging) ...[
            const SizedBox(width: 8),
            const _HudChip(
              icon: Icons.bolt,
              label: 'CHG',
              color: Colors.yellow,
              pulse: true,
            ),
          ],
          const SizedBox(width: 12),

          // Nav status
          _HudChip(
            icon: status.isMoving ? Icons.directions_walk : Icons.pause,
            label: status.navStatusText,
            color: status.isMoving ? _accentSecondary : Colors.grey,
          ),

          // Speed (when moving)
          if (status.isMoving && status.velocity.isNotEmpty) ...[
            const SizedBox(width: 8),
            _HudChip(
              icon: Icons.speed,
              label: '${status.velocity[0].abs().toStringAsFixed(2)} m/s',
              color: _accentColor,
            ),
          ],

          // E-stop warning
          if (status.hasEstop) ...[
            const SizedBox(width: 12),
            _HudChip(
              icon: Icons.emergency,
              label: status.hardEstop ? 'HARD STOP' : 'SOFT STOP',
              color: _dangerColor,
              pulse: true,
            ),
          ],

          // Stale data warning - check BOTH RobotConnection AND BufferClient
          // robot.isStale: WebSocket status updates not received
          // bufferClient.isStale: Relay heartbeats not received OR robot data old
          Builder(builder: (context) {
            final bufferStale = tourManager.bufferClient?.isStale ?? false;
            final isStale = robot.isStale || bufferStale;
            if (!isStale) return const SizedBox.shrink();
            return const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 12),
                _HudChip(
                  icon: Icons.warning_amber,
                  label: 'DATA STALE',
                  color: Colors.amber,
                  pulse: true,
                ),
              ],
            );
          }),

          // Tour Status in Center
          if (currentSequence != null) ...[
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: tourRunning
                    ? Colors.green.withValues(alpha: 0.2)
                    : tourPaused
                        ? Colors.orange.withValues(alpha: 0.2)
                        : Colors.grey.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: tourRunning
                      ? Colors.green
                      : tourPaused
                          ? Colors.orange
                          : Colors.grey,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    tourRunning
                        ? Icons.tour
                        : tourPaused
                            ? Icons.pause_circle
                            : Icons.tour_outlined,
                    size: 18,
                    color: tourRunning
                        ? Colors.green
                        : tourPaused
                            ? Colors.orange
                            : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentSequence.name,
                        style: TextStyle(
                          color: tourRunning ? Colors.green : Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (tourManager.currentStop != null)
                        Text(
                          'Stop ${tourManager.currentStopIndex + 1}/${currentSequence.stops.length}: ${tourManager.currentStop!.waypoint}',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 9,
                          ),
                        ),
                    ],
                  ),
                  if (tourManager.countdownSeconds > 0) ...[
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${tourManager.countdownSeconds}s',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],

          const Spacer(),

          // Current goal
          if (status.currentGoal.isNotEmpty) ...[
            const Icon(Icons.flag, size: 16, color: _accentColor),
            const SizedBox(width: 4),
            Text(
              status.currentGoal,
              style: const TextStyle(
                  color: _accentColor, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 16),
          ],

          // Fleet picker button
          IconButton(
            icon: const Icon(Icons.router),
            color: _accentColor,
            tooltip: 'Switch Robot',
            onPressed: () => _showFleetPicker(robot),
          ),
          // Disconnect button
          IconButton(
            icon: const Icon(Icons.power_settings_new),
            color: _dangerColor,
            tooltip: 'Disconnect',
            onPressed: robot.disconnect,
          ),
        ],
      ),
    );
  }

  Widget _buildLeftPanel(
      RobotConnection robot, bool tourRunning, SequenceManager tourManager) {
    final capabilities = robot.capabilities;
    final waypoints = capabilities?.waypoints ?? [];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: _leftPanelExpanded ? 400 : 48,
      child: Container(
        margin: const EdgeInsets.only(left: 4, top: 4, bottom: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0E14).withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _accentColor.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.3), blurRadius: 8),
          ],
        ),
        child: Column(
          children: [
            // Panel toggle & tabs
            _buildLeftPanelHeader(),

            // Panel content
            if (_leftPanelExpanded)
              Expanded(
                child: _leftPanelTab == 0
                    ? _buildWaypointsContent(waypoints)
                    : _leftPanelTab == 1
                        ? _buildSequenceContent(waypoints, tourManager)
                        : _buildCrowdContent(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeftPanelHeader() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: _accentColor.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          // Collapse/expand button
          IconButton(
            icon: Icon(
              _leftPanelExpanded ? Icons.chevron_left : Icons.chevron_right,
              color: _accentColor,
            ),
            onPressed: _toggleLeftPanel,
            tooltip: _leftPanelExpanded ? 'Collapse' : 'Expand',
            iconSize: 20,
          ),
          if (_leftPanelExpanded) ...[
            const SizedBox(width: 4),
            // Tab buttons
            _PanelTabButton(
              icon: Icons.location_on,
              label: 'POI',
              selected: _leftPanelTab == 0,
              color: _accentColor,
              onTap: () => setState(() => _leftPanelTab = 0),
            ),
            const SizedBox(width: 4),
            _PanelTabButton(
              icon: Icons.route,
              label: 'SEQ',
              selected: _leftPanelTab == 1,
              color: _accentSecondary,
              onTap: () => setState(() => _leftPanelTab = 1),
            ),
            const SizedBox(width: 4),
            _PanelTabButton(
              icon: Icons.people,
              label: 'CROWD',
              selected: _leftPanelTab == 2,
              color: Colors.orange,
              onTap: () => setState(() => _leftPanelTab = 2),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWaypointsContent(List<String> waypoints) {
    if (waypoints.isEmpty) {
      return Center(
        child: Text(
          'No waypoints',
          style: TextStyle(color: Colors.grey.shade500),
        ),
      );
    }

    return Column(
      children: [
        // Hint text
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            'Long-press to configure task mode',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
          ),
        ),
        // Voice control
        Padding(
          padding: const EdgeInsets.all(8),
          child: VoiceControl(availableWaypoints: waypoints),
        ),
        Divider(color: _accentColor.withValues(alpha: 0.2), height: 1),
        // Waypoint list (compact)
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: waypoints.length,
            itemBuilder: (context, index) {
              final wp = waypoints[index];
              final hasMode = _taskEngine.hasMode(wp);
              final isNavigating = _navigatingTo == wp;
              return _WaypointButton(
                name: wp,
                color: _accentColor,
                onTap: () => _navigateTo(wp),
                onLongPress: () => _showTaskConfigDialog(wp),
                hasMode: hasMode,
                isNavigating: isNavigating,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSequenceContent(
      List<String> waypoints, SequenceManager tourManager) {
    final currentSequence = tourManager.currentSequence;
    final hasStartWaypoint = currentSequence?.startWaypoint != null &&
        currentSequence!.startWaypoint!.isNotEmpty;

    return Column(
      children: [
        // Add START TOUR button at the top if there's a startWaypoint
        if (hasStartWaypoint &&
            tourManager.status != SequenceStatus.running) ...[
          Padding(
            padding: const EdgeInsets.all(8),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.rocket_launch, size: 24),
              label: Text(
                'START TOUR FROM ${currentSequence.startWaypoint!.toUpperCase()}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () {
                debugPrint(
                    'START TOUR pressed - setting up motion standby at ${currentSequence.startWaypoint}');
                // Enable motion trigger to show welcome screen
                final motionSequence = currentSequence.copyWith(
                  motionTriggerStart: true,
                  motionGreeting: 'Hello! Would you like a tour?',
                  motionButtonText: 'START TOUR',
                );
                SequenceManager.instance.startSequence(motionSequence);
                // This will navigate to startWaypoint, then show welcome screen
                // When visitor taps button -> "Follow me!" -> Tour begins!
              },
            ),
          ),
        ],
        // The existing sequence editor
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: SequenceEditor(availableWaypoints: waypoints),
          ),
        ),
      ],
    );
  }

  Widget _buildCrowdContent() {
    return const CrowdLogicSettings();
  }

  Widget _buildRightPanel(RobotConnection robot) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: _rightPanelExpanded ? 260 : 48,
      child: Container(
        margin: const EdgeInsets.only(right: 4, top: 4, bottom: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0E14).withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _accentColor.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.3), blurRadius: 8),
          ],
        ),
        child: Column(
          children: [
            // Panel toggle
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                border: Border(
                  bottom:
                      BorderSide(color: _accentColor.withValues(alpha: 0.2)),
                ),
              ),
              child: Row(
                mainAxisAlignment: _rightPanelExpanded
                    ? MainAxisAlignment.spaceBetween
                    : MainAxisAlignment.center,
                children: [
                  if (_rightPanelExpanded)
                    const Expanded(
                      child: Text(
                        'MANUAL CONTROL',
                        style: TextStyle(
                          color: _accentColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  IconButton(
                    icon: Icon(
                      _rightPanelExpanded
                          ? Icons.chevron_right
                          : Icons.chevron_left,
                      color: _accentColor,
                    ),
                    onPressed: _toggleRightPanel,
                    tooltip: _rightPanelExpanded ? 'Collapse' : 'Expand',
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                ],
              ),
            ),

            // Joystick
            if (_rightPanelExpanded)
              const Expanded(
                child: JoystickControl(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(RobotConnection robot) {
    return Container(
      height: 46,
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0E14).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _accentColor.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8),
        ],
      ),
      child: Row(
        children: [
          // Quick action buttons
          _QuickActionButton(
            icon: Icons.stop_circle,
            label: 'STOP',
            color: _dangerColor,
            onTap: () {
              debugPrint(
                  'HUD: STOP pressed - cancelling nav and stopping movement');
              // Stop velocity immediately
              robot.sendVelocity(0, 0);
              // Cancel any active navigation
              robot.cancelNavigation();
              // Stop any running tour
              if (SequenceManager.instance.status == SequenceStatus.running ||
                  SequenceManager.instance.status == SequenceStatus.paused) {
                debugPrint('HUD: STOP - also stopping tour');
                SequenceManager.instance.stopSequence();
              }
            },
          ),
          const SizedBox(width: 8),
          _QuickActionButton(
            icon: Icons.cancel,
            label: 'CANCEL NAV',
            color: Colors.orange,
            onTap: () {
              debugPrint('HUD: CANCEL NAV pressed');
              robot.cancelNavigation();
            },
          ),
          const SizedBox(width: 8),
          _QuickActionButton(
            icon: Icons.emergency,
            label: robot.status.softEstop ? 'RELEASE' : 'E-STOP',
            color: robot.status.softEstop ? _accentSecondary : _dangerColor,
            onTap: () {
              debugPrint(
                  'HUD: E-STOP pressed, current=${robot.status.softEstop}');
              // Advertise first, then publish
              robot.client.send(protocol.SmaitProtocol.advertiseSoftStop());
              Future.delayed(const Duration(milliseconds: 100), () {
                robot.client.send(protocol.SmaitProtocol.publishSoftStop(
                    !robot.status.softEstop));
              });
            },
          ),

          const SizedBox(width: 16),

          // Expandable feature pills
          _FeaturePill(
            icon: Icons.volume_up,
            label: 'SND',
            color: Colors.purple,
            onTap: () => _showFeaturePanel('sound', robot),
          ),
          const SizedBox(width: 4),
          _FeaturePill(
            icon: Icons.campaign,
            label: 'ANN',
            color: Colors.teal,
            onTap: () => _showFeaturePanel('announcements', robot),
          ),
          const SizedBox(width: 4),
          _FeaturePill(
            icon: Icons.science,
            label: 'TEST',
            color: Colors.amber,
            onTap: () => _showFeaturePanel('testing', robot),
          ),
          const SizedBox(width: 4),
          _FeaturePill(
            icon: Icons.settings,
            label: 'SET',
            color: Colors.blueGrey,
            onTap: () => _showFeaturePanel('settings', robot),
          ),
          const SizedBox(width: 4),
          _FeaturePill(
            icon: Icons.tune,
            label: 'PRM',
            color: Colors.indigo,
            onTap: () => _showFeaturePanel('params', robot),
          ),
          const SizedBox(width: 4),
          _FeaturePill(
            icon: Icons.psychology,
            label: 'CAP',
            color: Colors.deepPurple,
            onTap: () => _showFeaturePanel('capabilities', robot),
          ),
          const SizedBox(width: 4),
          _FeaturePill(
            icon: Icons.auto_fix_high,
            label: 'MODE',
            color: Colors.pink,
            onTap: () => _showFeaturePanel('modes', robot),
          ),

          const Spacer(),

          // Messages toggle
          IconButton(
            icon: const Icon(Icons.message_outlined),
            color: _bottomPanelExpanded ? _accentColor : Colors.grey,
            onPressed: _toggleBottomPanel,
            tooltip: 'Toggle message log',
          ),
        ],
      ),
    );
  }

  void _showFeaturePanel(String feature, RobotConnection robot) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF151A22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: _accentColor.withValues(alpha: 0.4)),
        ),
        child: Container(
          width: 500,
          height: 500,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Header
              Row(
                children: [
                  Icon(_getFeatureIcon(feature), color: _accentColor),
                  const SizedBox(width: 8),
                  Text(
                    _getFeatureTitle(feature),
                    style: const TextStyle(
                      color: _accentColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    color: Colors.grey,
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(color: Colors.grey),
              // Content
              Expanded(child: _buildFeatureContent(feature, robot)),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getFeatureIcon(String feature) {
    switch (feature) {
      case 'sound':
        return Icons.volume_up;
      case 'announcements':
        return Icons.campaign;
      case 'testing':
        return Icons.science;
      case 'settings':
        return Icons.settings;
      case 'params':
        return Icons.tune;
      case 'capabilities':
        return Icons.psychology;
      case 'modes':
        return Icons.auto_fix_high;
      default:
        return Icons.help;
    }
  }

  String _getFeatureTitle(String feature) {
    switch (feature) {
      case 'sound':
        return 'SOUND CONTROL';
      case 'announcements':
        return 'ANNOUNCEMENTS';
      case 'testing':
        return 'TESTING';
      case 'settings':
        return 'SETTINGS';
      case 'params':
        return 'ROBOT PARAMS';
      case 'capabilities':
        return 'CAPABILITIES';
      case 'modes':
        return 'TASK MODES';
      default:
        return feature.toUpperCase();
    }
  }

  Widget _buildFeatureContent(String feature, RobotConnection robot) {
    final waypoints = robot.capabilities?.waypoints ?? [];
    switch (feature) {
      case 'sound':
        return _buildSoundControl(robot);
      case 'announcements':
        return const AnnouncementPresetsEditor();
      case 'testing':
        return _buildTestingPanel(robot);
      case 'settings':
        return _buildSettingsPanel(robot);
      case 'params':
        return _buildParamsPanel(robot);
      case 'capabilities':
        return _buildCapabilitiesPanel(robot);
      case 'modes':
        return ModeEditor(availableWaypoints: waypoints);
      default:
        return const Center(child: Text('Coming soon...'));
    }
  }

  Widget _buildSoundControl(RobotConnection robot) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Audio Announcements', style: TextStyle(color: Colors.grey[400])),
        const SizedBox(height: 12),
        // Custom text input
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _customSoundController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Type custom announcement...',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  filled: true,
                  fillColor: Colors.grey[850],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onSubmitted: (text) {
                  if (text.trim().isNotEmpty) {
                    robot.client.tabletSpeak(text.trim());
                    _customSoundController.clear();
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.send, color: Color(0xFF00D4FF)),
              onPressed: () {
                final text = _customSoundController.text.trim();
                if (text.isNotEmpty) {
                  robot.client.tabletSpeak(text);
                  _customSoundController.clear();
                }
              },
              tooltip: 'Speak',
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Quick Phrases',
            style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _SoundButton(
                label: 'Excuse Me',
                text: 'Excuse me, please make way.',
                robot: robot),
            _SoundButton(
                label: 'Thank You',
                text: 'Thank you! Have a great day.',
                robot: robot),
            _SoundButton(
                label: 'Arriving',
                text: 'I am arriving at my destination.',
                robot: robot),
            _SoundButton(
                label: 'Following',
                text: 'I am following you. Please walk slowly.',
                robot: robot),
            _SoundButton(
                label: 'Low Battery',
                text: 'Warning: Battery is running low.',
                robot: robot),
            _SoundButton(
                label: 'Emergency',
                text: 'Emergency stop activated.',
                robot: robot),
          ],
        ),
      ],
    );
  }

  Widget _buildTestingPanel(RobotConnection robot) {
    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.navigation, color: Colors.blue),
          title: const Text('Test Navigation'),
          subtitle: const Text('Send robot to home position'),
          onTap: () =>
              robot.client.callService(service: '/poi', args: {'poi': 'home'}),
        ),
        ListTile(
          leading: const Icon(Icons.rotate_right, color: Colors.green),
          title: const Text('Spin Test'),
          subtitle: const Text('Rotate robot 360°'),
          onTap: () => robot.sendVelocity(0, 0.5),
        ),
        ListTile(
          leading: const Icon(Icons.speaker, color: Colors.orange),
          title: const Text('Audio Test'),
          subtitle: const Text('Test tablet TTS'),
          onTap: () => robot.client.tabletSpeak('Audio test successful.'),
        ),
      ],
    );
  }

  Widget _buildSettingsPanel(RobotConnection robot) {
    final announcer = AudioAnnouncer();
    return StatefulBuilder(
      builder: (context, setLocalState) => ListView(
        children: [
          // Audio enabled toggle
          SwitchListTile(
            title: const Text('Audio Enabled'),
            subtitle: const Text('Enable/disable robot announcements'),
            value: announcer.enabled,
            onChanged: (v) {
              setLocalState(() => announcer.enabled = v);
            },
          ),
          // Volume slider
          ListTile(
            leading: const Icon(Icons.volume_up),
            title: const Text('Volume'),
            subtitle: Slider(
              value: announcer.volume,
              min: 0.0,
              max: 1.0,
              divisions: 10,
              label: '${(announcer.volume * 100).round()}%',
              onChanged: (v) {
                setLocalState(() => announcer.volume = v);
              },
            ),
            trailing: Text('${(announcer.volume * 100).round()}%'),
          ),
          const Divider(),
          // Test TTS
          ListTile(
            leading: const Icon(Icons.speaker, color: Colors.orange),
            title: const Text('Test Audio'),
            subtitle: const Text('Test TTS on tablet'),
            onTap: () => robot.client.tabletSpeak('Audio test successful.'),
          ),
          // Crowd Logic link
          ListTile(
            leading: const Icon(Icons.people, color: Colors.blue),
            title: const Text('Crowd Logic'),
            subtitle: Text('Current: ${announcer.crowdConfig.venue.label}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showFeaturePanel('crowd', robot),
          ),
        ],
      ),
    );
  }

  Widget _buildParamsPanel(RobotConnection robot) {
    final params = robot.capabilities?.parameters ?? [];
    if (params.isEmpty) {
      return const Center(
          child: Text('No parameters discovered',
              style: TextStyle(color: Colors.grey)));
    }

    // LOG ALL PARAMETERS TO CONSOLE
    debugPrint('=== ROBOT PARAMETERS (${params.length}) ===');

    // Also write to file for analysis of large lists
    _writeLogToFile('robot_parameters.txt', params.join('\n'));

    for (var p in params) {
      debugPrint(p);
    }
    debugPrint('==========================================');

    return ListView.builder(
      itemCount: params.length,
      itemBuilder: (ctx, i) {
        final param = params[i];
        return ListTile(
          dense: true,
          title: Text(param,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        );
      },
    );
  }

  Widget _buildCapabilitiesPanel(RobotConnection robot) {
    final caps = robot.capabilities;
    if (caps == null) {
      return const Center(
          child: Text('Not connected', style: TextStyle(color: Colors.grey)));
    }

    // Build log buffer
    final buffer = StringBuffer();
    buffer.writeln('TOPICS (${caps.topics.length}):');
    for (final topic in caps.topics) {
      buffer.writeln('${topic.name}|${topic.type}');
    }
    buffer.writeln('\nSERVICES (${caps.services.length}):');
    for (final service in caps.services) {
      buffer.writeln('${service.name}|${service.type}');
    }
    buffer.writeln('\nWAYPOINTS (${caps.waypoints.length}):');
    for (final wp in caps.waypoints) {
      buffer.writeln(wp);
    }

    // LOG ALL CAPABILITIES TO CONSOLE
    debugPrint(
        '=== ROBOT CAPABILITIES (${caps.topics.length} topics, ${caps.services.length} services) ===');

    // Also write to file for analysis
    _writeLogToFile('robot_capabilities.txt', buffer.toString());

    debugPrint(buffer.toString());
    debugPrint('================================================');

    return ListView(
      children: [
        _CapabilityTile(
            icon: Icons.topic, label: 'Topics', count: caps.topics.length),
        _CapabilityTile(
            icon: Icons.miscellaneous_services,
            label: 'Services',
            count: caps.services.length),
        _CapabilityTile(
            icon: Icons.tune,
            label: 'Parameters',
            count: caps.parameters.length),
        _CapabilityTile(
            icon: Icons.location_on,
            label: 'Waypoints',
            count: caps.waypoints.length),
        const Divider(),
        _CapabilityRow(label: 'Navigation', enabled: caps.hasNavigation),
        _CapabilityRow(
            label: 'Velocity Control', enabled: caps.hasVelocityControl),
        _CapabilityRow(label: 'Status', enabled: caps.hasStatus),
        _CapabilityRow(label: 'Battery', enabled: caps.hasBattery),
        _CapabilityRow(label: 'Map', enabled: caps.hasMap),
      ],
    );
  }

  void _connect(RobotConnection robot) {
    var url = _urlController.text.trim();
    if (url.isEmpty) return;

    // Convert HTTP to WS for rosbridge
    if (url.startsWith('http://')) {
      final uri = Uri.tryParse(url);
      if (uri != null) {
        url = 'ws://${uri.host}:8766';
      }
    }
    robot.connect(url);
  }

  /// Open fleet picker to switch robots
  Future<void> _showFleetPicker(RobotConnection robot) async {
    final selected = await FleetPicker.show(context);
    if (selected != null && mounted) {
      robot.connect(selected.wsUrl);
    }
  }

  void _detectModeFromUrl(String url) {
    if (url.contains(':8766')) {
      setState(() => _connectionMode = ConnectionMode.relayWs);
    } else if (url.contains(':8765') || url.startsWith('http')) {
      setState(() => _connectionMode = ConnectionMode.relayHttp);
    } else {
      setState(() => _connectionMode = ConnectionMode.direct);
    }
  }

  /// Save connection mode to SharedPreferences
  Future<void> _saveConnectionMode(ConnectionMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('connection_mode', mode.name);
    debugPrint('HUD: Saved connection mode: ${mode.name}');
  }

  /// Load connection mode from SharedPreferences
  /// Returns true if a saved mode was found, false otherwise
  Future<bool> _loadConnectionMode() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString('connection_mode');
    if (savedMode != null) {
      final mode = ConnectionMode.values.firstWhere(
        (m) => m.name == savedMode,
        orElse: () => ConnectionMode.direct,
      );
      setState(() => _connectionMode = mode);
      debugPrint('HUD: Loaded connection mode: ${mode.name}');
      return true;
    }
    debugPrint('HUD: No saved connection mode found');
    return false;
  }

  /// Write log data to file for debugging large datasets
  Future<void> _writeLogToFile(String filename, String content) async {
    // Delegate to cross-platform utility
    await FileUtils.saveFile(context, filename, content);
  }

  void _navigateTo(String waypoint) {
    debugPrint('HUD: Navigate to $waypoint');
    final robot = context.read<RobotConnection>();
    _goToWaypointInternal(robot, waypoint);
  }

  /// Show dialog to configure task mode for a waypoint
  Future<void> _showTaskConfigDialog(String waypoint) async {
    final result = await showDialog<_TaskConfigResult>(
      context: context,
      builder: (context) => _TaskConfigDialog(
        waypoint: waypoint,
        taskEngine: _taskEngine,
      ),
    );

    if (result != null) {
      setState(() {
        _taskEngine.assignMode(waypoint, result.modeId, params: result.params);
      });
    }
  }

  IconData _batteryIcon(double level) {
    if (level > 80) return Icons.battery_full;
    if (level > 60) return Icons.battery_5_bar;
    if (level > 40) return Icons.battery_4_bar;
    if (level > 20) return Icons.battery_2_bar;
    return Icons.battery_alert;
  }

  Color _batteryColor(double level) {
    if (level > 50) return _accentSecondary;
    if (level > 20) return Colors.orange;
    return _dangerColor;
  }
}

/// HUD-style status chip
class _HudChip extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool pulse;

  const _HudChip({
    required this.icon,
    required this.label,
    required this.color,
    this.pulse = false,
  });

  @override
  State<_HudChip> createState() => _HudChipState();
}

class _HudChipState extends State<_HudChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    if (widget.pulse) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_HudChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.pulse && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: widget.color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(widget.icon, size: 14, color: widget.color),
          const SizedBox(width: 4),
          Text(
            widget.label,
            style: TextStyle(
              color: widget.color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );

    if (widget.pulse) {
      return AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return Opacity(
            opacity: 0.5 + (_pulseController.value * 0.5),
            child: content,
          );
        },
      );
    }

    return content;
  }
}

/// Panel tab button
class _PanelTabButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _PanelTabButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? color.withValues(alpha: 0.5) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: selected ? color : Colors.grey),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: selected ? color : Colors.grey,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact waypoint button for HUD with long-press for task config
class _WaypointButton extends StatelessWidget {
  final String name;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool hasMode;
  final bool isNavigating;

  const _WaypointButton({
    required this.name,
    required this.color,
    required this.onTap,
    this.onLongPress,
    this.hasMode = false,
    this.isNavigating = false,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = isNavigating ? const Color(0xFF00FF88) : color;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isNavigating ? activeColor.withValues(alpha: 0.15) : null,
              border: Border.all(
                  color:
                      activeColor.withValues(alpha: isNavigating ? 0.6 : 0.3)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                if (isNavigating)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF00FF88)),
                  )
                else if (hasMode)
                  Icon(Icons.auto_awesome,
                      size: 14, color: Colors.amber.shade400)
                else
                  Icon(Icons.location_on, size: 16, color: activeColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(color: activeColor, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.play_arrow, size: 18, color: activeColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Quick action button for bottom bar
class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Corner bracket painter for HUD aesthetic
class _BracketPainter extends CustomPainter {
  final Color color;
  final double thickness;
  final bool top;
  final bool left;

  _BracketPainter({
    required this.color,
    required this.thickness,
    required this.top,
    required this.left,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    final path = Path();

    if (top && left) {
      path.moveTo(0, size.height);
      path.lineTo(0, 0);
      path.lineTo(size.width, 0);
    } else if (top && !left) {
      path.moveTo(size.width, size.height);
      path.lineTo(size.width, 0);
      path.lineTo(0, 0);
    } else if (!top && left) {
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(size.width, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BracketPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.thickness != thickness ||
        oldDelegate.top != top ||
        oldDelegate.left != left;
  }
}

/// Feature pill button for bottom bar expandable panels
class _FeaturePill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _FeaturePill({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sound preset button
class _SoundButton extends StatelessWidget {
  final String label;
  final String text;
  final RobotConnection robot;

  const _SoundButton({
    required this.label,
    required this.text,
    required this.robot,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: const Icon(Icons.play_arrow, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.grey.shade800,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      onPressed: () => robot.client.tabletSpeak(text),
    );
  }
}

/// Capability count tile
class _CapabilityTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;

  const _CapabilityTile({
    required this.icon,
    required this.label,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20, color: Colors.grey),
      title: Text(label),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.blue.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          count.toString(),
          style:
              const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

/// Capability boolean row
class _CapabilityRow extends StatelessWidget {
  final String label;
  final bool enabled;

  const _CapabilityRow({
    required this.label,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(label),
      trailing: Icon(
        enabled ? Icons.check_circle : Icons.cancel,
        color: enabled ? Colors.green : Colors.red,
        size: 20,
      ),
    );
  }
}

/// Result from task config dialog
class _TaskConfigResult {
  final String? modeId;
  final Map<String, String> params;

  _TaskConfigResult({this.modeId, this.params = const {}});
}

/// Dialog to configure waypoint tasks (supports multiple simultaneous tasks)
class _TaskConfigDialog extends StatefulWidget {
  final String waypoint;
  final TaskEngine taskEngine;

  const _TaskConfigDialog({
    required this.waypoint,
    required this.taskEngine,
  });

  @override
  State<_TaskConfigDialog> createState() => _TaskConfigDialogState();
}

class _TaskConfigDialogState extends State<_TaskConfigDialog> {
  // Individual toggles for each capability
  bool _enableDelivery = false; // Wait for pickup + return to origin
  bool _enableSpeak = false; // TTS announcement
  bool _enableDisplay = false; // Show website/media

  // Data controllers
  late TextEditingController _speakController;
  late TextEditingController _displayController;
  int _waitSeconds = 30;

  @override
  void initState() {
    super.initState();
    _speakController = TextEditingController();
    _displayController = TextEditingController();

    // Load existing assignment
    final assignment = widget.taskEngine.getAssignment(widget.waypoint);
    if (assignment != null && assignment.modeId != null) {
      final params = assignment.params;

      // Load speak text
      if (params['speak_text']?.isNotEmpty == true) {
        _enableSpeak = true;
        _speakController.text = params['speak_text']!;
      }

      // Load display URL
      if (params['display_url']?.isNotEmpty == true) {
        _enableDisplay = true;
        _displayController.text = params['display_url']!;
      }

      // Load delivery settings
      if (assignment.modeId == 'delivery') {
        _enableDelivery = true;
        _waitSeconds = int.tryParse(params['wait_seconds'] ?? '30') ?? 30;
      }
    }
  }

  @override
  void dispose() {
    _speakController.dispose();
    _displayController.dispose();
    super.dispose();
  }

  bool get _hasAnyTask => _enableDelivery || _enableSpeak || _enableDisplay;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF151A22),
      title: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 24, color: Color(0xFF00D4FF)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Task: ${widget.waypoint}',
              style: const TextStyle(color: Color(0xFF00D4FF)),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Configure actions to perform when arriving at this waypoint. '
                'Multiple options can be enabled together.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
              ),
              const SizedBox(height: 16),

              // === SPEAK SECTION ===
              _buildTaskSection(
                icon: Icons.volume_up,
                iconColor: Colors.orange,
                title: 'Speak',
                subtitle: 'Text-to-speech announcement',
                enabled: _enableSpeak,
                onToggle: (v) => setState(() => _enableSpeak = v),
                child: TextField(
                  controller: _speakController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'What to say at this stop...',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    hintStyle: TextStyle(color: Colors.grey.shade600),
                  ),
                  maxLines: 3,
                  enabled: _enableSpeak,
                ),
              ),

              const SizedBox(height: 12),

              // === DISPLAY SECTION ===
              _buildTaskSection(
                icon: Icons.tv,
                iconColor: Colors.purple,
                title: 'Display',
                subtitle: 'Show website, image, or video on tablet',
                enabled: _enableDisplay,
                onToggle: (v) => setState(() => _enableDisplay = v),
                child: TextField(
                  controller: _displayController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'https://example.com/media.mp4',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    hintStyle: TextStyle(color: Colors.grey.shade600),
                  ),
                  enabled: _enableDisplay,
                ),
              ),

              const SizedBox(height: 12),

              // === DELIVERY SECTION ===
              _buildTaskSection(
                icon: Icons.delivery_dining,
                iconColor: Colors.green,
                title: 'Delivery Mode',
                subtitle: 'Wait for pickup, then return to origin',
                enabled: _enableDelivery,
                onToggle: (v) => setState(() => _enableDelivery = v),
                child: Row(
                  children: [
                    const Text('Wait: ',
                        style: TextStyle(color: Colors.white70)),
                    Expanded(
                      child: Slider(
                        value: _waitSeconds.toDouble(),
                        min: 10,
                        max: 120,
                        divisions: 11,
                        label: '$_waitSeconds sec',
                        onChanged: _enableDelivery
                            ? (v) => setState(() => _waitSeconds = v.round())
                            : null,
                      ),
                    ),
                    Text('$_waitSeconds s',
                        style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (_hasAnyTask)
          TextButton(
            onPressed: () => Navigator.pop(context, _TaskConfigResult()),
            child: const Text('Clear All'),
          ),
        FilledButton(
          onPressed: () {
            // Build mode and params from enabled options
            String? modeId;
            Map<String, String> params = {};

            // Collect all enabled params
            if (_enableSpeak && _speakController.text.isNotEmpty) {
              params['speak_text'] = _speakController.text;
            }
            if (_enableDisplay && _displayController.text.isNotEmpty) {
              params['display_url'] = _displayController.text;
              params['display_duration'] = '0'; // Until robot leaves
            }

            // Determine mode based on delivery toggle
            if (_enableDelivery) {
              modeId = 'delivery';
              params['wait_seconds'] = _waitSeconds.toString();
            } else if (params.isNotEmpty) {
              modeId = 'announce';
            }

            Navigator.pop(
              context,
              _TaskConfigResult(modeId: modeId, params: params),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  /// Build a collapsible task section with toggle
  Widget _buildTaskSection({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool enabled,
    required ValueChanged<bool> onToggle,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color:
              enabled ? iconColor.withValues(alpha: 0.5) : Colors.grey.shade700,
          width: enabled ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
        color: enabled ? iconColor.withValues(alpha: 0.1) : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header row with toggle
          InkWell(
            onTap: () => onToggle(!enabled),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(icon,
                      color: enabled ? iconColor : Colors.grey, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: enabled ? iconColor : Colors.grey,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: enabled,
                    onChanged: onToggle,
                    activeTrackColor: iconColor.withValues(alpha: 0.5),
                    activeThumbColor: iconColor,
                  ),
                ],
              ),
            ),
          ),
          // Content (shown when enabled)
          if (enabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: child,
            ),
        ],
      ),
    );
  }
}

/// Mini control button for sequence overlay
class _MiniControlButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;

  const _MiniControlButton({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
        ),
      ),
    );
  }
}
