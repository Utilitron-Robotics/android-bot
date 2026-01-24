import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Fleet Cloud Client for Flutter controller app
/// Connects to Frontier Tower fleet management backend
class FleetCloudClient extends ChangeNotifier {
  // Singleton
  static final FleetCloudClient _instance = FleetCloudClient._internal();
  factory FleetCloudClient() => _instance;
  FleetCloudClient._internal();

  // Configuration - deployed CloudFormation stack endpoint
  static const String defaultEndpoint = 'https://e536dpa128.execute-api.us-west-1.amazonaws.com/dev';
  String _apiEndpoint = defaultEndpoint;
  String? _apiKey;
  bool _isConnected = false;
  String? _currentMapId;  // Selected map for tour sync

  // State
  final Map<String, RobotFleetStatus> _robots = {};
  Timer? _pollTimer;

  // Getters
  bool get isConnected => _isConnected;
  String get apiEndpoint => _apiEndpoint;
  String? get currentMapId => _currentMapId;
  List<RobotFleetStatus> get robots => _robots.values.toList();

  /// Set the current map ID (auto-detected from robot or manually set)
  void setMapId(String? mapId) {
    _currentMapId = mapId;
    notifyListeners();
  }

  /// Auto-detect map ID from robot status (building_floor format)
  void autoDetectMapId(String? buildingName, String? floorName) {
    if (buildingName != null && floorName != null) {
      _currentMapId = '${buildingName}_$floorName';
      debugPrint('FleetCloud: Auto-detected map ID: $_currentMapId');
      notifyListeners();
    }
  }

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

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.body.isNotEmpty) {
          return jsonDecode(response.body) as Map<String, dynamic>;
        }
        return {}; // Success but no body (201/204)
      }
      debugPrint('FleetCloud: POST $path status=${response.statusCode}: ${response.body}');
    } catch (e) {
      debugPrint('FleetCloud: POST $path failed: $e');
    }
    return null;
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_apiKey != null) 'X-API-Key': _apiKey!,
  };

  // ============================================
  // TOUR SYNC API - Shared across all robots on a map
  // ============================================

  /// Get all tours for the current map
  Future<List<Map<String, dynamic>>> getTours() async {
    if (_currentMapId == null) {
      debugPrint('FleetCloud: No map ID set, cannot fetch tours');
      return [];
    }
    try {
      final response = await _get('/tours?map_id=$_currentMapId');
      if (response != null) {
        final tours = response['tours'] as List<dynamic>? ?? [];
        debugPrint('FleetCloud: Fetched ${tours.length} tours for map $_currentMapId');
        return tours.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('FleetCloud: Get tours failed: $e');
    }
    return [];
  }

  /// Get a specific tour by ID
  Future<Map<String, dynamic>?> getTour(String tourId) async {
    try {
      final response = await _get('/tours/$tourId');
      return response;
    } catch (e) {
      debugPrint('FleetCloud: Get tour $tourId failed: $e');
      return null;
    }
  }

  /// Save/update a tour (creates if new, updates if exists)
  Future<bool> saveTour(Map<String, dynamic> tourData) async {
    if (_currentMapId == null) {
      debugPrint('FleetCloud: No map ID set, cannot save tour');
      return false;
    }
    try {
      // Ensure map_id is set
      final data = Map<String, dynamic>.from(tourData);
      data['map_id'] = _currentMapId;

      final tourId = data['tour_id'] ?? data['id'];
      if (tourId != null) {
        // Update existing tour
        data['tour_id'] = tourId;
        final response = await _put('/tours/$tourId', data);
        if (response != null) {
          debugPrint('FleetCloud: Updated tour $tourId');
          return true;
        }
      } else {
        // Create new tour
        final response = await _post('/tours', data);
        if (response != null) {
          debugPrint('FleetCloud: Created tour ${response['tour_id']}');
          return true;
        }
      }
    } catch (e) {
      debugPrint('FleetCloud: Save tour failed: $e');
    }
    return false;
  }

  /// Delete a tour
  Future<bool> deleteTour(String tourId) async {
    try {
      final response = await _delete('/tours/$tourId');
      if (response != null) {
        debugPrint('FleetCloud: Deleted tour $tourId');
        return true;
      }
    } catch (e) {
      debugPrint('FleetCloud: Delete tour failed: $e');
    }
    return false;
  }

  /// Sync local tours with cloud (pull + push)
  /// Returns list of cloud tours after sync
  Future<List<Map<String, dynamic>>> syncTours(List<Map<String, dynamic>> localTours) async {
    if (_currentMapId == null) {
      debugPrint('FleetCloud: No map ID set, cannot sync');
      return localTours;
    }

    try {
      // Get cloud tours
      final cloudTours = await getTours();
      final cloudById = {for (var t in cloudTours) t['tour_id'] as String: t};

      // Merge: cloud wins if newer, push local if newer
      for (final local in localTours) {
        final localId = (local['id'] ?? local['tour_id']) as String;
        final localModified = local['modified_at'] as int? ?? 0;
        final cloud = cloudById[localId];

        if (cloud == null) {
          // Local only - push to cloud
          debugPrint('FleetCloud: Pushing new tour $localId to cloud');
          await saveTour({...local, 'tour_id': localId});
        } else {
          final cloudModified = cloud['modified_at'] as int? ?? 0;
          if (localModified > cloudModified) {
            // Local is newer - push
            debugPrint('FleetCloud: Pushing updated tour $localId (local: $localModified > cloud: $cloudModified)');
            await saveTour({...local, 'tour_id': localId});
          }
        }
      }

      // Fetch final state from cloud
      return await getTours();
    } catch (e) {
      debugPrint('FleetCloud: Sync failed: $e');
      return localTours;
    }
  }

  // ============================================
  // WAYPOINT SYNC API - Shared waypoint lists across robots
  // ============================================

  /// Get waypoints for a map from cloud
  Future<List<String>> getWaypoints({String? mapId}) async {
    final targetMapId = mapId ?? _currentMapId;
    if (targetMapId == null) {
      debugPrint('FleetCloud: No map ID set, cannot fetch waypoints');
      return [];
    }
    try {
      final response = await _get('/maps/$targetMapId');
      if (response != null) {
        final waypoints = response['waypoints'] as List<dynamic>? ?? [];
        debugPrint('FleetCloud: Fetched ${waypoints.length} waypoints for map $targetMapId');
        return waypoints.cast<String>();
      }
    } catch (e) {
      debugPrint('FleetCloud: Get waypoints failed: $e');
    }
    return [];
  }

  /// Push waypoints to cloud for a map
  Future<bool> pushWaypoints(List<String> waypoints, {String? mapId}) async {
    final targetMapId = mapId ?? _currentMapId;
    if (targetMapId == null) {
      debugPrint('FleetCloud: No map ID set, cannot push waypoints');
      return false;
    }
    try {
      // First try to get existing map
      final existing = await _get('/maps/$targetMapId');
      if (existing != null) {
        // Update existing map
        final response = await _put('/maps/$targetMapId', {
          'waypoints': waypoints,
        });
        if (response != null) {
          debugPrint('FleetCloud: Updated waypoints for map $targetMapId');
          return true;
        }
      } else {
        // Create new map entry
        final response = await _post('/maps', {
          'map_id': targetMapId,
          'name': targetMapId,
          'waypoints': waypoints,
        });
        if (response != null) {
          debugPrint('FleetCloud: Created map $targetMapId with ${waypoints.length} waypoints');
          return true;
        }
      }
    } catch (e) {
      debugPrint('FleetCloud: Push waypoints failed: $e');
    }
    return false;
  }

  // HTTP helpers
  Future<Map<String, dynamic>?> _put(String path, Map<String, dynamic> body) async {
    try {
      final response = await http.put(
        Uri.parse('$_apiEndpoint$path'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.body.isNotEmpty) {
          return jsonDecode(response.body) as Map<String, dynamic>;
        }
        return {}; // Success but no body (204)
      }
      debugPrint('FleetCloud: PUT $path status=${response.statusCode}: ${response.body}');
    } catch (e) {
      debugPrint('FleetCloud: PUT $path failed: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> _delete(String path) async {
    try {
      final response = await http.delete(
        Uri.parse('$_apiEndpoint$path'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('FleetCloud: DELETE $path failed: $e');
    }
    return null;
  }

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
