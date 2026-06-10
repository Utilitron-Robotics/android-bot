import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'rosbridge_client.dart';
import 'task_mode.dart';
import 'transport_config.dart';
import '../services/robot_introspection.dart';
import '../services/audio_announcer.dart';
import '../services/sequence_executor.dart';

/// Robot connection state (renamed to avoid conflict with Flutter's ConnectionState)
enum RobotConnectionState { disconnected, connecting, connected, error }

/// Manages robot connection and discovered capabilities.
/// One transport everywhere: WebSocket (rosbridge protocol) via the relay.
class RobotConnection extends ChangeNotifier implements CommandExecutor {
  final RosbridgeClient _client = RosbridgeClient();
  RobotIntrospection? _introspection;

  RobotConnectionState _state = RobotConnectionState.disconnected;
  String _robotUrl = '';
  String? _errorMessage;
  RobotCapabilities? _capabilities;

  // Subscriptions for live data
  StreamSubscription? _statusSubscription;
  StreamSubscription? _rttSubscription;
  RobotStatus _status = RobotStatus();

  // Relay-computed safety intelligence from /relay/safety (LIDAR zones).
  // Staleness is client-side: no fresh message within the threshold means
  // the data cannot be trusted (relay keepalive proves LIDAR liveness).
  static const Duration safetyStaleAfter = Duration(milliseconds: 3000);
  double? _minRangeMeters;
  String _safetyZone = 'CLEAR';
  bool _obstacleInPath = false;
  String _obstacleType = 'CLEAR';
  DateTime? _lastSafetyUpdate;

  double? get minRangeMeters => _minRangeMeters;
  String get safetyZone => _safetyZone;
  bool get obstacleInPath => _obstacleInPath;
  String get obstacleType => _obstacleType;
  bool get safetyStale =>
      _lastSafetyUpdate == null ||
      DateTime.now().difference(_lastSafetyUpdate!) > safetyStaleAfter;

  // RTT from the relay_ping echo on the live socket
  int? get rttMs => _client.rttMs;
  NetworkCondition get networkCondition {
    final rtt = _client.rttMs;
    if (rtt == null) return NetworkCondition.fair;
    if (rtt < 50) return NetworkCondition.excellent;
    if (rtt < 150) return NetworkCondition.good;
    if (rtt < 300) return NetworkCondition.fair;
    if (rtt < 600) return NetworkCondition.poor;
    return NetworkCondition.critical;
  }

  // Connection health tracking
  DateTime? _lastStatusUpdate;
  DateTime? get lastStatusUpdate => _lastStatusUpdate;
  @override
  bool get isStale =>
      _lastStatusUpdate != null &&
      DateTime.now().difference(_lastStatusUpdate!) >
          const Duration(seconds: 5);

  // Nav status deduplication - only forward CHANGED status to task manager
  int _lastForwardedNavStatus = -1;

  // Command manager for retry logic
  late final CommandManager _commandManager;
  CommandManager get commandManager => _commandManager;

  // Task manager for task modes (tour, delivery, etc.)
  final TaskManager _taskManager = TaskManager.instance;
  TaskManager get taskManager => _taskManager;

  // Getters
  RobotConnectionState get state => _state;
  String get robotUrl => _robotUrl;
  String? get errorMessage => _errorMessage;
  RobotCapabilities? get capabilities => _capabilities;
  RobotStatus get status => _status;
  RosbridgeClient get client => _client;
  @override
  bool get isConnected => _state == RobotConnectionState.connected;

  RobotConnection() {
    _commandManager = CommandManager(this);
    _taskManager.setCommandManager(_commandManager);
    _loadSavedUrl();
  }

  /// CommandExecutor implementation - send command to robot
  @override
  Future<bool> sendCommand(TrackedCommand command) async {
    if (!isConnected) return false;

    try {
      switch (command.type) {
        case 'navigate':
          final waypoint = command.payload['waypoint'] as String?;
          if (waypoint != null) {
            await _client.callService(
              service: '/poi',
              args: {'poi': waypoint},
            );
            return true;
          }
          return false;

        case 'velocity':
          final linear = command.payload['linear'] as double? ?? 0.0;
          final angular = command.payload['angular'] as double? ?? 0.0;
          sendVelocity(linear, angular);
          // Velocity commands are fire-and-forget, mark as completed immediately
          _commandManager.commandCompleted(command.id);
          return true;

        case 'stop':
          sendVelocity(0, 0);
          _commandManager.commandCompleted(command.id);
          return true;

        case 'cancel':
          await cancelNavigation();
          _commandManager.commandCompleted(command.id);
          return true;

        default:
          debugPrint('RobotConnection: Unknown command type: ${command.type}');
          return false;
      }
    } catch (e) {
      debugPrint('RobotConnection: Error sending command: $e');
      return false;
    }
  }

  Future<void> _loadSavedUrl() async {
    final prefs = await SharedPreferences.getInstance();
    // No hardcoded default - user must enter relay IP
    _robotUrl = prefs.getString('robot_url') ?? '';
    notifyListeners();
  }

  Future<void> _saveUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('robot_url', url);
  }

  /// Connect to robot and discover capabilities
  /// Automatically handles HTTP→WebSocket conversion for relay mode
  Future<void> connect(String url) async {
    // If URL is HTTP, convert to WebSocket for rosbridge but keep HTTP for display
    String connectUrl = url;
    if (url.startsWith('http://')) {
      final uri = Uri.tryParse(url);
      if (uri != null) {
        connectUrl = 'ws://${uri.host}:8766';
        debugPrint('RobotConnection: Converting HTTP to WS for rosbridge: $connectUrl');
      }
    }
    return connectWithDisplayUrl(connectUrl, url);
  }

  /// Connect to robot using connectUrl, but save displayUrl for the UI
  /// This allows HTTP mode to connect via WebSocket but show HTTP URL to user
  Future<void> connectWithDisplayUrl(String connectUrl, String displayUrl) async {
    debugPrint('RobotConnection: connectWithDisplayUrl called - connectUrl=$connectUrl, displayUrl=$displayUrl');
    if (_state == RobotConnectionState.connecting) {
      debugPrint('RobotConnection: Already connecting, skipping');
      return;
    }

    // CRITICAL: Disconnect from any existing robot first!
    if (_state == RobotConnectionState.connected) {
      debugPrint('RobotConnection: Disconnecting from existing connection');
      disconnect();
    }

    _state = RobotConnectionState.connecting;
    _errorMessage = null;
    _robotUrl = displayUrl; // Save the display URL for the UI
    notifyListeners();

    // Save display URL so user sees what they entered
    await _saveUrl(displayUrl);

    // Set up reconnect callbacks
    _client.onDisconnect = _onClientDisconnect;
    _client.onReconnect = _onClientReconnect;

    try {
      debugPrint('RobotConnection: Connecting WebSocket to $connectUrl...');
      await _client.connect(connectUrl);
      debugPrint('RobotConnection: WebSocket connected!');

      // Inject dependency for audio announcements
      AudioAnnouncer().setRobotConnection(this);

      // Initialize sequence executor
      SequenceExecutor().init(this);

      // Discover robot capabilities
      debugPrint('RobotConnection: Starting capability discovery...');
      _introspection = RobotIntrospection(_client);
      _capabilities = await _introspection!.discover();
      debugPrint('RobotConnection: Discovery complete - waypoints: ${_capabilities?.waypoints.length ?? 0}');

      // Subscribe to status updates if available
      _subscribeToStatus();

      _state = RobotConnectionState.connected;
      debugPrint('RobotConnection: State set to connected');
      notifyListeners();
    } catch (e, stack) {
      debugPrint('RobotConnection: Connection failed: $e');
      debugPrint('RobotConnection: Stack: $stack');
      _state = RobotConnectionState.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  /// Set display URL without connecting (for gRPC relay mode)
  Future<void> setDisplayUrl(String url) async {
    _robotUrl = url;
    await _saveUrl(url);
    notifyListeners();
  }

  /// Refresh capabilities (re-run discovery)
  Future<void> refreshCapabilities() async {
    if (_introspection != null && isConnected) {
      try {
        _capabilities = await _introspection!.discover();
        notifyListeners();
      } catch (e) {
        debugPrint('RobotConnection: Error refreshing capabilities: $e');
      }
    }
  }

  /// Called when the WebSocket connection is lost (only after silent retries fail)
  void _onClientDisconnect() {
    debugPrint('RobotConnection: Connection lost after silent retries');
    _state = RobotConnectionState.error;
    _errorMessage = 'Connection lost - reconnecting...';
    notifyListeners();
  }

  /// Called when the WebSocket reconnects successfully
  void _onClientReconnect() {
    debugPrint('RobotConnection: Reconnected! Re-subscribing to topics...');
    _state = RobotConnectionState.connected;
    _errorMessage = null;

    // Re-subscribe to robot status
    _statusSubscription?.cancel();
    _subscribeToStatus();

    notifyListeners();
  }

  void _subscribeToStatus() {
    // Always subscribe to robot_status - Chassis robots always have this
    // This is the reliable source for nav status, battery, etc.
    _client.subscribe(
      topic: '/robot_status',
      type: 'yutong_assistance/RobotStatus',
    );

    // Surface RTT updates (relay_ping echo arrives every ping interval)
    _rttSubscription?.cancel();
    _rttSubscription = _client.rtt.listen((_) => notifyListeners());

    // Listen for status updates
    _statusSubscription = _client.messages.listen((msg) {
      // Relay-synthesized safety topic (broadcast by relay, no subscribe needed)
      if (msg['topic'] == '/relay/safety') {
        final data = msg['msg'] as Map<String, dynamic>?;
        if (data != null) {
          _minRangeMeters = (data['min_range_m'] as num?)?.toDouble();
          _safetyZone = data['safety_zone'] as String? ?? 'CLEAR';
          _obstacleInPath = data['obstacle_in_path'] as bool? ?? false;
          _obstacleType = data['obstacle_type'] as String? ?? 'CLEAR';
          _lastSafetyUpdate = DateTime.now();
          notifyListeners();
        }
        return;
      }
      if (msg['topic'] == '/robot_status') {
        final data = msg['msg'] as Map<String, dynamic>?;
        if (data != null) {
          final newStatus = RobotStatus(
            navStatus: data['nav_status'] as int? ?? 0,
            battery: (data['battery'] as num?)?.toDouble() ?? 0,
            velocity: _parseVelocity(data['velocity']),
            hardEstop: data['hard_estop'] as bool? ?? false,
            softEstop: data['soft_estop'] as bool? ?? false,
            charger: data['charger'] as int? ?? 0,
            controlState: data['control_state'] as int? ?? 0,
            buildingName: data['current_building_name'] as String? ?? '',
            floorName: data['current_floor_name'] as String? ?? '',
            currentGoal: data['current_goal_name'] as String? ?? '',
          );

          // Trigger audio announcements on status changes
          AudioAnnouncer().onNavStatusChanged(
            newStatus.navStatus,
            newStatus.currentGoal,
          );

          // Send velocity for stuck detection (both linear and angular)
          if (newStatus.velocity.isNotEmpty) {
            final linear = newStatus.velocity[0];
            final angular = newStatus.velocity.length > 1 ? newStatus.velocity[1] : 0.0;
            AudioAnnouncer().onVelocityChanged(linear, angular);
          }

          // Forward to sequence executor for sequence mode (legacy)
          SequenceExecutor().onNavStatusChanged(
            newStatus.navStatus,
            newStatus.currentGoal,
          );

          // Forward to task manager for new task mode system
          // DEDUPLICATE: Only forward if nav status actually changed
          if (newStatus.navStatus != _lastForwardedNavStatus) {
            _lastForwardedNavStatus = newStatus.navStatus;
            _taskManager.onNavStatus(newStatus.navStatus);
            if (newStatus.navStatus == 603 &&
                newStatus.currentGoal.isNotEmpty) {
              // Arrived at waypoint
              _taskManager.onArrived(newStatus.currentGoal);
            }
          }

          _status = newStatus;
          _lastStatusUpdate = DateTime.now();
          notifyListeners();
        }
      }
    });
  }

  List<double> _parseVelocity(dynamic vel) {
    if (vel is List) {
      return vel.map((v) => (v as num).toDouble()).toList();
    }
    return [0.0, 0.0];
  }

  /// Navigate to a waypoint (POI)
  Future<void> goToWaypoint(String poi) async {
    debugPrint(
        'RobotConnection.goToWaypoint: poi=$poi, isConnected=$isConnected');
    if (!isConnected) {
      debugPrint('RobotConnection.goToWaypoint: NOT CONNECTED - aborting!');
      return;
    }

    debugPrint('RobotConnection.goToWaypoint: Calling service /poi');
    await _client.callService(
      service: '/poi',
      args: {'poi': poi},
    );
    debugPrint('RobotConnection.goToWaypoint: Service call complete');
  }

  /// Cancel current navigation
  Future<void> cancelNavigation() async {
    if (!isConnected) return;

    // Advertise, publish cancel, unadvertise
    _client.advertise(
      topic: '/move_base/cancel',
      type: 'actionlib_msgs/GoalID',
    );

    _client.publish(
      topic: '/move_base/cancel',
      msg: {'stamp': '', 'id': ''},
    );

    _client.unadvertise(topic: '/move_base/cancel');
  }

  /// Send velocity command (joystick)
  /// Chassis protocol: advertise then publish to /cmd_vel_mux/input/teleop
  /// Speed command lasts 0.6 seconds per the protocol spec
  void sendVelocity(double linear, double angular) {
    if (!isConnected) return;

    _client.advertise(
      topic: '/cmd_vel_mux/input/teleop',
      type: 'geometry_msgs/Twist',
    );

    _client.publish(
      topic: '/cmd_vel_mux/input/teleop',
      msg: {
        'linear': {'x': linear},
        'angular': {'z': angular},
      },
    );
  }

  /// Disconnect from robot
  void disconnect() {
    // Clean up SequenceExecutor first (before client disconnect)
    // This disposes BufferClient and prevents duplicate subscriptions on reconnect
    SequenceExecutor().cleanup();

    // Unsubscribe from robot topics before disconnecting
    if (_statusSubscription != null) {
      _client.unsubscribe(topic: '/robot_status');
      _statusSubscription!.cancel();
      _statusSubscription = null;
    }
    _rttSubscription?.cancel();
    _rttSubscription = null;
    _client.disconnect();
    _state = RobotConnectionState.disconnected;
    _capabilities = null;
    _status = RobotStatus();
    _lastStatusUpdate = null;
    _minRangeMeters = null;
    _lastSafetyUpdate = null;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    _commandManager.dispose();
    _client.dispose();
    super.dispose();
  }
}

/// Live robot status from /robot_status topic
class RobotStatus {
  final int navStatus;
  final double battery;
  final List<double> velocity;
  final bool hardEstop;
  final bool softEstop;
  final int charger;
  final int controlState;
  final String buildingName;
  final String floorName;
  final String currentGoal;

  RobotStatus({
    this.navStatus = 0,
    this.battery = 0,
    this.velocity = const [0, 0],
    this.hardEstop = false,
    this.softEstop = false,
    this.charger = 0,
    this.controlState = 0,
    this.buildingName = '',
    this.floorName = '',
    this.currentGoal = '',
  });

  String get navStatusText {
    switch (navStatus) {
      case 600:
        return 'Idle';
      case 601:
        return 'Moving';
      case 602:
        return 'Cancelled';
      case 603:
        return 'Arrived';
      case 604:
        return 'Failed';
      case 605:
        return 'Standby';
      default:
        return 'Unknown ($navStatus)';
    }
  }

  String get chargerText {
    switch (charger) {
      case 0:
        return 'Not charging';
      case 1:
        return 'Charging';
      case 2:
        return 'Recharging';
      case -1:
        return 'Charge failed';
      default:
        return 'Unknown';
    }
  }

  String get controlStateText {
    switch (controlState) {
      case 20:
        return 'Mapping';
      case 30:
        return 'Navigation';
      case 99:
        return 'Error';
      default:
        return 'Unknown';
    }
  }

  bool get isMoving => navStatus == 601;
  bool get hasEstop => hardEstop || softEstop;
  bool get isCharging => charger == 1 || charger == 2;
}
