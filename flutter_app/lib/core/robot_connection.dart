import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'rosbridge_client.dart';
import '../services/robot_introspection.dart';

/// Robot connection state (renamed to avoid conflict with Flutter's ConnectionState)
enum RobotConnectionState { disconnected, connecting, connected, error }

/// Manages robot connection and discovered capabilities
class RobotConnection extends ChangeNotifier {
  final RosbridgeClient _client = RosbridgeClient();
  RobotIntrospection? _introspection;

  RobotConnectionState _state = RobotConnectionState.disconnected;
  String _robotUrl = '';
  String? _errorMessage;
  RobotCapabilities? _capabilities;

  // Subscriptions for live data
  StreamSubscription? _statusSubscription;
  RobotStatus _status = RobotStatus();

  // Getters
  RobotConnectionState get state => _state;
  String get robotUrl => _robotUrl;
  String? get errorMessage => _errorMessage;
  RobotCapabilities? get capabilities => _capabilities;
  RobotStatus get status => _status;
  RosbridgeClient get client => _client;
  bool get isConnected => _state == RobotConnectionState.connected;

  RobotConnection() {
    _loadSavedUrl();
  }

  Future<void> _loadSavedUrl() async {
    final prefs = await SharedPreferences.getInstance();
    _robotUrl = prefs.getString('robot_url') ?? 'ws://192.168.1.100:9090';
    notifyListeners();
  }

  Future<void> _saveUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('robot_url', url);
  }

  /// Connect to robot and discover capabilities
  Future<void> connect(String url) async {
    if (_state == RobotConnectionState.connecting) return;

    _state = RobotConnectionState.connecting;
    _errorMessage = null;
    _robotUrl = url;
    notifyListeners();

    try {
      await _client.connect(url);
      await _saveUrl(url);

      // Discover robot capabilities
      _introspection = RobotIntrospection(_client);
      _capabilities = await _introspection!.discover();

      // Subscribe to status updates if available
      _subscribeToStatus();

      _state = RobotConnectionState.connected;
      notifyListeners();
    } catch (e) {
      _state = RobotConnectionState.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  void _subscribeToStatus() {
    if (_capabilities == null) return;

    // Subscribe to robot_status if available
    if (_capabilities!.topics.any((t) => t.name == '/robot_status')) {
      _client.subscribe(
        topic: '/robot_status',
        type: 'yutong_assistance/RobotStatus',
      );
    }

    // Listen for status updates
    _statusSubscription = _client.messages.listen((msg) {
      if (msg['topic'] == '/robot_status') {
        final data = msg['msg'] as Map<String, dynamic>?;
        if (data != null) {
          _status = RobotStatus(
            navStatus: data['nav_status'] as int? ?? 0,
            battery: (data['battery'] as num?)?.toDouble() ?? 0,
            velocity: (data['velocity'] as List?)?.cast<double>() ?? [0, 0],
          );
          notifyListeners();
        }
      }
    });
  }

  /// Navigate to a waypoint (POI)
  Future<void> goToWaypoint(String poi) async {
    if (!isConnected) return;

    await _client.callService(
      service: '/poi',
      args: {'poi': poi},
    );
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
  void sendVelocity(double linear, double angular) {
    if (!isConnected) return;

    _client.publish(
      topic: '/cmd_vel',
      msg: {
        'linear': {'x': linear, 'y': 0.0, 'z': 0.0},
        'angular': {'x': 0.0, 'y': 0.0, 'z': angular},
      },
    );
  }

  /// Disconnect from robot
  void disconnect() {
    _statusSubscription?.cancel();
    _client.disconnect();
    _state = RobotConnectionState.disconnected;
    _capabilities = null;
    _status = RobotStatus();
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    _client.dispose();
    super.dispose();
  }
}

/// Live robot status
class RobotStatus {
  final int navStatus;
  final double battery;
  final List<double> velocity;

  RobotStatus({
    this.navStatus = 0,
    this.battery = 0,
    this.velocity = const [0, 0],
  });

  String get navStatusText {
    switch (navStatus) {
      case 600: return 'Idle';
      case 601: return 'Moving';
      case 602: return 'Paused';
      case 603: return 'Arrived';
      case 604: return 'At destination';
      case 605: return 'Standby';
      default: return 'Unknown ($navStatus)';
    }
  }

  bool get isMoving => navStatus == 601;
}
