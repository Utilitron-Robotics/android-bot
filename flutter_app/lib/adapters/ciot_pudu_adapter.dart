/// CIOT/Pudu/smAiT Robot Adapter
/// Primary adapter for service robots using rosbridge protocol
///
/// Supports:
/// - Pudu Robotics (BellaBot, PuduBot, HolaBot, etc.)
/// - CIOT robots
/// - smAiT robots
/// - Any rosbridge-compatible service robot
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/robot_adapter.dart' as adapter;
import '../core/rosbridge_client.dart';
import '../core/robot_connection.dart' as conn;

/// Safety zones for obstacle detection (LIDAR-based)
enum SafetyZone {
  clear, // > 1.5m
  warn, // 1.0-1.5m
  creep, // 0.5-1.0m
  stop, // < 0.5m
}

/// Status for CIOT/Pudu/smAiT robots
class CiotPuduStatus extends adapter.RobotStatus {
  final bool _connected;
  final int? _battery;
  final double? _x;
  final double? _y;
  final double? _theta;
  final int navStatus;
  final String? currentGoalName;
  final bool hardEstop;
  final bool softEstop;
  final List<double>? velocity;
  final SafetyZone? safetyZone;

  CiotPuduStatus({
    required bool connected,
    required this.navStatus,
    int? battery,
    double? x,
    double? y,
    double? theta,
    this.currentGoalName,
    this.hardEstop = false,
    this.softEstop = false,
    this.velocity,
    this.safetyZone,
  })  : _connected = connected,
        _battery = battery,
        _x = x,
        _y = y,
        _theta = theta;

  @override
  bool get connected => _connected;

  @override
  int? get battery => _battery?.round();

  @override
  double? get x => _x;

  @override
  double? get y => _y;

  @override
  double? get theta => _theta;

  factory CiotPuduStatus.fromRosbridgeStatus(conn.RobotStatus status) {
    // Parse safety zone from robot status if available
    SafetyZone? zone;
    // TODO: Get safety zone from LIDAR data when available

    return CiotPuduStatus(
      connected: true, // If we got status, we're connected
      navStatus: status.navStatus,
      battery: status.battery.round(),
      x: null, // TODO: Get from pose when available
      y: null,
      theta: null,
      currentGoalName:
          status.currentGoal.isNotEmpty ? status.currentGoal : null,
      hardEstop: status.hardEstop,
      softEstop: status.softEstop,
      velocity: status.velocity,
      safetyZone: zone,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'connected': connected,
      'navStatus': navStatus,
      'battery': battery,
      'x': x,
      'y': y,
      'theta': theta,
      'currentGoalName': currentGoalName,
      'hardEstop': hardEstop,
      'softEstop': softEstop,
      'velocity': velocity,
      'safetyZone': safetyZone?.name,
    };
  }
}

/// Adapter for CIOT/Pudu/smAiT service robots
class CiotPuduAdapter extends adapter.RobotAdapter {
  final RosbridgeClient _client;
  CiotPuduStatus? _status;
  StreamSubscription? _messageSubscription;
  adapter.NavigationStatus _navStatus = adapter.NavigationStatus.idle;

  // Store latest robot status from rosbridge
  conn.RobotStatus? _rosbridgeStatus;

  CiotPuduAdapter() : _client = RosbridgeClient();

  @override
  String get robotType => 'ciot_pudu';

  @override
  String get robotName => 'CIOT/Pudu Service Robot';

  @override
  bool get isConnected => _client.isConnected;

  @override
  adapter.RobotCapabilities get capabilities => const adapter.RobotCapabilities(
        navigation: true,
        velocity: true,
        mapping: true,
        battery: true,
        estop: true,
        tts: true, // Via Android tablet
        display: true, // Via Android tablet
        camera: false, // Future
        arm: false, // Some models have arms
        lidar: true,
        ultrasonic: true,
      );

  @override
  adapter.RobotStatus? get status => _status;

  @override
  adapter.NavigationStatus get navigationStatus => _navStatus;

  @override
  Future<void> connect(String address, {int? port}) async {
    // Connect with just the URL
    final url = port != null ? 'ws://$address:$port' : 'ws://$address:9090';
    await _client.connect(url);

    // Listen for messages to parse robot status
    _messageSubscription?.cancel();
    _messageSubscription = _client.messages.listen((msg) {
      // Parse robot status messages
      if (msg['topic'] == '/robot_status') {
        _handleRobotStatusMessage(msg['msg'] as Map<String, dynamic>?);
      }
    });

    // Subscribe to robot status topic
    _client.subscribe(
      topic: '/robot_status',
      type: 'yutong_assistance/RobotStatus',
    );
  }

  void _handleRobotStatusMessage(Map<String, dynamic>? msg) {
    if (msg == null) return;

    // Create a minimal RobotStatus from the message
    _rosbridgeStatus = conn.RobotStatus(
      navStatus: msg['nav_status'] as int? ?? 0,
      battery: (msg['battery'] as num?)?.toDouble() ?? 0,
      velocity: [
        (msg['velocity_x'] as num?)?.toDouble() ?? 0,
        (msg['velocity_th'] as num?)?.toDouble() ?? 0,
      ],
      hardEstop: msg['hard_estop'] as bool? ?? false,
      softEstop: msg['soft_estop'] as bool? ?? false,
      charger: msg['charger'] as int? ?? 0,
      controlState: msg['control_state'] as int? ?? 0,
      buildingName: msg['current_building_name'] as String? ?? '',
      floorName: msg['current_floor_name'] as String? ?? '',
      currentGoal: msg['current_goal_name'] as String? ?? '',
    );

    // Update our adapter status
    _status = CiotPuduStatus.fromRosbridgeStatus(_rosbridgeStatus!);
    _navStatus = adapter.NavigationStatus.fromCode(_rosbridgeStatus!.navStatus);
    notifyListeners();
  }

  @override
  Future<void> disconnect() async {
    _messageSubscription?.cancel();
    _client.disconnect(); // disconnect() is void, not Future<void>
    _status = null;
    _rosbridgeStatus = null;
    notifyListeners();
  }

  @override
  Future<void> sendVelocity(double linear, double angular) async {
    if (!capabilities.velocity) {
      throw UnsupportedError('Velocity control not supported');
    }

    // Advertise topic first (rosbridge requirement)
    _client.advertise(
      topic: '/cmd_vel_mux/input/teleop',
      type: 'geometry_msgs/Twist',
    );

    // Send velocity command
    _client.publish(
      topic: '/cmd_vel_mux/input/teleop',
      msg: {
        'linear': {'x': linear, 'y': 0.0, 'z': 0.0},
        'angular': {'x': 0.0, 'y': 0.0, 'z': angular},
      },
    );
  }

  @override
  Future<void> navigateToWaypoint(String waypoint) async {
    if (!capabilities.navigation) {
      throw UnsupportedError('Navigation not supported');
    }

    // Call POI service to navigate
    await _client.callService(
      service: '/poi',
      args: {'poi': waypoint},
    );
  }

  @override
  Future<void> cancelNavigation() async {
    if (!capabilities.navigation) {
      throw UnsupportedError('Navigation not supported');
    }

    // Publish to cancel topic
    _client.advertise(
      topic: '/move_base/cancel',
      type: 'actionlib_msgs/GoalID',
    );

    _client.publish(
      topic: '/move_base/cancel',
      msg: {'id': ''},
    );
  }

  @override
  Future<void> emergencyStop(bool enable) async {
    if (!capabilities.estop) {
      throw UnsupportedError('Emergency stop not supported');
    }

    await _client.callService(
      service: '/soft_estop',
      args: {'data': enable},
    );
  }

  @override
  Future<List<String>> getWaypoints() async {
    if (!capabilities.navigation) {
      throw UnsupportedError('Navigation not supported');
    }

    // Call POI service with empty string to get list
    final response = await _client.callService(
      service: '/poi',
      args: {'poi': ''},
    );

    // Parse waypoint list from response
    if (response['poi_list'] != null) {
      final list = response['poi_list'] as List;
      return list.map((poi) => poi.toString()).toList();
    }

    return [];
  }

  @override
  Future<void> speak(String text) async {
    // TTS is handled by Android tablet relay, not robot base
    // Send via relay protocol
    debugPrint('CiotPuduAdapter: TTS requires tablet relay');
    throw UnsupportedError('Direct TTS not supported - use tablet relay');
  }

  @override
  Future<void> displayUrl(String url) async {
    // Display is handled by Android tablet, not robot base
    debugPrint('CiotPuduAdapter: Display requires tablet relay');
    throw UnsupportedError('Direct display not supported - use tablet relay');
  }

  @override
  Future<void> sendRawCommand(Map<String, dynamic> command) async {
    // Send raw rosbridge command
    _client.send(command);
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _client.dispose();
    super.dispose();
  }
}

/// Register CIOT/Pudu adapter with factory on app startup
void registerCiotPuduAdapter() {
  adapter.RobotAdapterFactory.registerAdapter(
    'ciot_pudu',
    () => CiotPuduAdapter(),
  );
}
