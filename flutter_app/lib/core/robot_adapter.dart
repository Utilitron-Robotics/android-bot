/// Abstract base classes for robot adapters
/// Allows supporting multiple robot platforms beyond CIOT/Pudu/Chassis
///
/// Architecture:
/// - RobotAdapter: Abstract interface for robot communication
/// - CiotPuduAdapter: Implementation for CIOT/Pudu/Chassis service robots (primary)
/// - Future: TurtleBotAdapter, Spot adapter, custom robot adapters
library;

import 'dart:async';
import 'package:flutter/foundation.dart';

/// Robot capabilities that adapters can support
class RobotCapabilities {
  final bool navigation;
  final bool velocity;
  final bool mapping;
  final bool battery;
  final bool estop;
  final bool tts;
  final bool display;
  final bool camera;
  final bool arm;
  final bool lidar;
  final bool ultrasonic;

  const RobotCapabilities({
    this.navigation = false,
    this.velocity = false,
    this.mapping = false,
    this.battery = false,
    this.estop = false,
    this.tts = false,
    this.display = false,
    this.camera = false,
    this.arm = false,
    this.lidar = false,
    this.ultrasonic = false,
  });
}

/// Robot status common to all platforms
abstract class RobotStatus {
  bool get connected;
  int? get battery;
  double? get x;
  double? get y;
  double? get theta;

  Map<String, dynamic> toJson();
}

/// Navigation status codes (standardized across adapters)
enum NavigationStatus {
  idle(600),
  moving(601),
  cancelled(602),
  arrived(603),
  failed(604),
  standby(605);

  final int code;
  const NavigationStatus(this.code);

  static NavigationStatus fromCode(int code) {
    return NavigationStatus.values.firstWhere(
      (s) => s.code == code,
      orElse: () => NavigationStatus.idle,
    );
  }
}

/// Abstract robot adapter interface
/// All robot platforms must implement this interface
abstract class RobotAdapter extends ChangeNotifier {
  /// Robot type identifier (e.g., "ciot_pudu", "turtlebot", "spot")
  String get robotType;

  /// Human-readable robot name
  String get robotName;

  /// Current connection state
  bool get isConnected;

  /// Robot capabilities
  RobotCapabilities get capabilities;

  /// Current robot status
  RobotStatus? get status;

  /// Navigation status
  NavigationStatus get navigationStatus;

  /// Connect to the robot
  Future<void> connect(String address, {int? port});

  /// Disconnect from the robot
  Future<void> disconnect();

  /// Send velocity command (if supported)
  Future<void> sendVelocity(double linear, double angular);

  /// Navigate to waypoint (if supported)
  Future<void> navigateToWaypoint(String waypoint);

  /// Cancel navigation (if supported)
  Future<void> cancelNavigation();

  /// Emergency stop (if supported)
  Future<void> emergencyStop(bool enable);

  /// Get list of waypoints/POIs (if supported)
  Future<List<String>> getWaypoints();

  /// Speak text via TTS (if supported)
  Future<void> speak(String text);

  /// Display URL on screen (if supported)
  Future<void> displayUrl(String url);

  /// Send raw command (adapter-specific)
  Future<void> sendRawCommand(Map<String, dynamic> command);

  /// Dispose resources
  @override
  void dispose();
}

/// Factory for creating robot adapters
class RobotAdapterFactory {
  static final Map<String, RobotAdapter Function()> _adapters = {};

  /// Register an adapter type
  static void registerAdapter(String type, RobotAdapter Function() factory) {
    _adapters[type] = factory;
  }

  /// Create an adapter by type
  static RobotAdapter? createAdapter(String type) {
    final factory = _adapters[type];
    if (factory != null) {
      return factory();
    }
    debugPrint('RobotAdapterFactory: Unknown adapter type: $type');
    return null;
  }

  /// Get list of available adapter types
  static List<String> get availableAdapters => _adapters.keys.toList();

  /// Check if adapter type is registered
  static bool hasAdapter(String type) => _adapters.containsKey(type);
}