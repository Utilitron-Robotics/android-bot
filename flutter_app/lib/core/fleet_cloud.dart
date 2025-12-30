import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Fleet Cloud Client for Flutter controller app
/// Connects to TurboTurf fleet management backend
class FleetCloudClient extends ChangeNotifier {
  // Configuration
  String _apiEndpoint = 'https://api.turboturf.smait.com';
  String? _apiKey;
  bool _isConnected = false;

  // State
  final Map<String, RobotFleetStatus> _robots = {};
  Timer? _pollTimer;

  // Getters
  bool get isConnected => _isConnected;
  String get apiEndpoint => _apiEndpoint;
  List<RobotFleetStatus> get robots => _robots.values.toList();

  /// Configure cloud connection
  void configure({
    required String apiEndpoint,
    String? apiKey,
  }) {
    _apiEndpoint = apiEndpoint;
    _apiKey = apiKey;
  }

  /// Connect to fleet management
  Future<bool> connect() async {
    try {
      final response = await _get('/fleet/status');
      if (response != null) {
        _isConnected = true;
        _parseFleetStatus(response);
        _startPolling();
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('FleetCloud: Connection failed: $e');
    }
    _isConnected = false;
    notifyListeners();
    return false;
  }

  /// Disconnect from fleet
  void disconnect() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _isConnected = false;
    _robots.clear();
    notifyListeners();
  }

  /// Send command to specific robot
  Future<bool> sendCommand(String robotId, FleetCommand command) async {
    try {
      final response = await _post('/fleet/commands', {
        'robot_id': robotId,
        'type': command.type,
        'payload': command.payload,
      });
      return response != null;
    } catch (e) {
      debugPrint('FleetCloud: Command failed: $e');
      return false;
    }
  }

  /// Navigate robot to POI
  Future<bool> navigateRobot(String robotId, String poi) async {
    return sendCommand(robotId, FleetCommand.navigate(poi));
  }

  /// Stop robot
  Future<bool> stopRobot(String robotId) async {
    return sendCommand(robotId, FleetCommand.stop());
  }

  /// Emergency stop robot
  Future<bool> estopRobot(String robotId, bool enabled) async {
    return sendCommand(robotId, FleetCommand.estop(enabled));
  }

  /// Send velocity command
  Future<bool> sendVelocity(String robotId, double linear, double angular) async {
    return sendCommand(robotId, FleetCommand.velocity(linear, angular));
  }

  /// Cancel robot navigation
  Future<bool> cancelNavigation(String robotId) async {
    return sendCommand(robotId, FleetCommand.cancelGoal());
  }

  /// Get specific robot status
  RobotFleetStatus? getRobot(String robotId) => _robots[robotId];

  /// Get robots by building
  List<RobotFleetStatus> getRobotsByBuilding(String building) {
    return _robots.values
        .where((r) => r.building == building)
        .toList();
  }

  /// Get robots by status
  List<RobotFleetStatus> getRobotsByNavStatus(int navStatus) {
    return _robots.values
        .where((r) => r.navStatus == navStatus)
        .toList();
  }

  /// Get all alerts
  Future<List<FleetAlert>> getAlerts({int limit = 50}) async {
    try {
      final response = await _get('/fleet/alerts?limit=$limit');
      if (response != null) {
        final alerts = response['alerts'] as List<dynamic>? ?? [];
        return alerts
            .map((a) => FleetAlert.fromJson(a as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('FleetCloud: Get alerts failed: $e');
    }
    return [];
  }

  // Private methods

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _refreshFleetStatus();
    });
  }

  Future<void> _refreshFleetStatus() async {
    try {
      final response = await _get('/fleet/status');
      if (response != null) {
        _parseFleetStatus(response);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('FleetCloud: Refresh failed: $e');
    }
  }

  void _parseFleetStatus(Map<String, dynamic> response) {
    final robotsData = response['robots'] as List<dynamic>? ?? [];
    for (final data in robotsData) {
      final status = RobotFleetStatus.fromJson(data as Map<String, dynamic>);
      _robots[status.robotId] = status;
    }
  }

  Future<Map<String, dynamic>?> _get(String path) async {
    try {
      final response = await http.get(
        Uri.parse('$_apiEndpoint$path'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('FleetCloud: GET $path failed: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$_apiEndpoint$path'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('FleetCloud: POST $path failed: $e');
    }
    return null;
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_apiKey != null) 'X-API-Key': _apiKey!,
  };

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}

/// Robot status from fleet management
class RobotFleetStatus {
  final String robotId;
  final int battery;
  final double x;
  final double y;
  final double theta;
  final int navStatus;
  final String? currentGoal;
  final bool estop;
  final bool online;
  final String? building;
  final String? floor;
  final DateTime lastSeen;

  RobotFleetStatus({
    required this.robotId,
    this.battery = 0,
    this.x = 0,
    this.y = 0,
    this.theta = 0,
    this.navStatus = 0,
    this.currentGoal,
    this.estop = false,
    this.online = false,
    this.building,
    this.floor,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  factory RobotFleetStatus.fromJson(Map<String, dynamic> json) {
    return RobotFleetStatus(
      robotId: json['robot_id'] as String? ?? '',
      battery: json['battery'] as int? ?? 0,
      x: (json['position']?['x'] as num?)?.toDouble() ?? 0,
      y: (json['position']?['y'] as num?)?.toDouble() ?? 0,
      theta: (json['position']?['theta'] as num?)?.toDouble() ?? 0,
      navStatus: json['nav_status'] as int? ?? 0,
      currentGoal: json['current_goal'] as String?,
      estop: json['estop'] as bool? ?? false,
      online: json['online'] as bool? ?? false,
      building: json['building'] as String?,
      floor: json['floor'] as String?,
      lastSeen: json['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int)
          : null,
    );
  }

  String get navStatusText {
    switch (navStatus) {
      case 600: return 'Waiting';
      case 601: return 'Running';
      case 602: return 'Cancelled';
      case 603: return 'Success';
      case 604: return 'Failed';
      default: return 'Unknown';
    }
  }

  bool get isNavigating => navStatus == 601;
  bool get isIdle => navStatus == 600 || navStatus == 603;
}

/// Command to send to robot via fleet
class FleetCommand {
  final String type;
  final Map<String, dynamic> payload;

  FleetCommand({required this.type, this.payload = const {}});

  factory FleetCommand.navigate(String poi) => FleetCommand(
    type: 'navigate',
    payload: {'poi': poi},
  );

  factory FleetCommand.stop() => FleetCommand(type: 'stop');

  factory FleetCommand.estop(bool enabled) => FleetCommand(
    type: 'estop',
    payload: {'enabled': enabled},
  );

  factory FleetCommand.velocity(double linear, double angular) => FleetCommand(
    type: 'velocity',
    payload: {'linear': linear, 'angular': angular},
  );

  factory FleetCommand.cancelGoal() => FleetCommand(type: 'cancel_goal');

  factory FleetCommand.setSpeedMode(int mode) => FleetCommand(
    type: 'set_speed_mode',
    payload: {'speed_mode': mode},
  );
}

/// Alert from fleet management
class FleetAlert {
  final String robotId;
  final String alertType;
  final String message;
  final String severity;
  final DateTime timestamp;

  FleetAlert({
    required this.robotId,
    required this.alertType,
    required this.message,
    this.severity = 'info',
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory FleetAlert.fromJson(Map<String, dynamic> json) {
    return FleetAlert(
      robotId: json['robot_id'] as String? ?? '',
      alertType: json['alert_type'] as String? ?? '',
      message: json['message'] as String? ?? '',
      severity: json['severity'] as String? ?? 'info',
      timestamp: json['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int)
          : null,
    );
  }

  bool get isCritical => severity == 'critical';
  bool get isError => severity == 'error';
  bool get isWarning => severity == 'warning';
}
