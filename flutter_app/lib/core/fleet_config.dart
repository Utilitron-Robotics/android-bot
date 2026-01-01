import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// AWS-backed fleet configuration - ONE config, ALL robots
///
/// No more local bullshit. Change once → every robot gets it.
/// All relays poll this config and apply it automatically.
class FleetConfig extends ChangeNotifier {
  static FleetConfig? _instance;
  static FleetConfig get instance {
    _instance ??= FleetConfig._();
    return _instance!;
  }

  FleetConfig._();

  static const String _apiUrlKey = 'fleet_api_url';
  static const String _apiKeyKey = 'fleet_api_key';

  String? _apiUrl;
  String? _apiKey;

  /// Current fleet config (cached locally)
  Map<String, dynamic> _config = {};
  Map<String, dynamic> get config => Map.unmodifiable(_config);

  /// Fleet robots status
  List<RobotInfo> _robots = [];
  List<RobotInfo> get robots => List.unmodifiable(_robots);

  /// Last sync time
  DateTime? _lastSync;
  DateTime? get lastSync => _lastSync;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  Timer? _syncTimer;

  /// Initialize with API URL (from CloudFormation output)
  Future<void> init({String? apiUrl, String? apiKey}) async {
    final prefs = await SharedPreferences.getInstance();

    _apiUrl = apiUrl ?? prefs.getString(_apiUrlKey);
    _apiKey = apiKey ?? prefs.getString(_apiKeyKey);

    if (_apiUrl != null) {
      await prefs.setString(_apiUrlKey, _apiUrl!);
    }
    if (_apiKey != null) {
      await prefs.setString(_apiKeyKey, _apiKey!);
    }

    if (_apiUrl != null) {
      await refresh();
      _startAutoSync();
    }
  }

  /// Set API endpoint
  Future<void> setApiUrl(String url) async {
    _apiUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiUrlKey, url);
    await refresh();
    _startAutoSync();
    notifyListeners();
  }

  /// Set API key (if using auth)
  Future<void> setApiKey(String key) async {
    _apiKey = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyKey, key);
    notifyListeners();
  }

  bool get isConfigured => _apiUrl != null && _apiUrl!.isNotEmpty;

  /// Start auto-sync every 30 seconds
  void _startAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      refresh();
    });
  }

  /// Refresh all data from cloud
  Future<void> refresh() async {
    if (_apiUrl == null) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await Future.wait([
        _loadConfig(),
        _loadRobots(),
      ]);
      _lastSync = DateTime.now();
    } catch (e) {
      _error = e.toString();
      debugPrint('FleetConfig: Refresh failed: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Load fleet config from cloud
  Future<void> _loadConfig() async {
    final response = await _get('/fleet/config');
    if (response.statusCode == 200) {
      _config = jsonDecode(response.body) as Map<String, dynamic>;
      debugPrint('FleetConfig: Loaded ${_config.length} config keys');
    }
  }

  /// Load fleet robots status
  Future<void> _loadRobots() async {
    final response = await _get('/fleet/status');
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final robotsList = data['robots'] as List? ?? [];
      _robots = robotsList.map((r) => RobotInfo.fromJson(r as Map<String, dynamic>)).toList();
      debugPrint('FleetConfig: Loaded ${_robots.length} robots');
    }
  }

  // === Config Operations ===

  /// Get a config value
  T? getConfigValue<T>(String key) {
    return _config[key] as T?;
  }

  /// Set a single config value (syncs to cloud immediately)
  Future<bool> setConfigValue(String key, dynamic value) async {
    try {
      final response = await _post('/fleet/config/$key', {'value': value});
      if (response.statusCode == 200) {
        _config[key] = value;
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('FleetConfig: Failed to set $key: $e');
    }
    return false;
  }

  /// Update multiple config values at once
  Future<bool> updateConfig(Map<String, dynamic> updates) async {
    try {
      final response = await _post('/fleet/config', updates);
      if (response.statusCode == 200) {
        _config.addAll(updates);
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('FleetConfig: Failed to update config: $e');
    }
    return false;
  }

  // === Task Engine Config ===

  /// Get waypoint mode assignments
  Map<String, dynamic> get waypointModes {
    return _config['waypoint_modes'] as Map<String, dynamic>? ?? {};
  }

  /// Save waypoint mode assignments to cloud
  Future<bool> saveWaypointModes(Map<String, dynamic> modes) async {
    return setConfigValue('waypoint_modes', modes);
  }

  /// Get TTS API key (shared fleet-wide)
  String? get ttsApiKey => _config['tts_api_key'] as String?;

  /// Set TTS API key for entire fleet
  Future<bool> setTtsApiKey(String key) async {
    return setConfigValue('tts_api_key', key);
  }

  // === Robot Operations ===

  /// Send command to a specific robot
  Future<String?> sendCommand(String robotId, String type, {Map<String, dynamic>? payload}) async {
    try {
      final response = await _post('/fleet/commands', {
        'robot_id': robotId,
        'type': type,
        'payload': payload ?? {},
      });
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['command_id'] as String?;
      }
    } catch (e) {
      debugPrint('FleetConfig: Failed to send command: $e');
    }
    return null;
  }

  /// Send command to ALL robots
  Future<List<String>> broadcastCommand(String type, {Map<String, dynamic>? payload}) async {
    final commandIds = <String>[];
    for (final robot in _robots.where((r) => r.online)) {
      final cmdId = await sendCommand(robot.robotId, type, payload: payload);
      if (cmdId != null) commandIds.add(cmdId);
    }
    return commandIds;
  }

  /// Register this device as a robot/relay
  Future<bool> registerRobot(String robotId, {Map<String, dynamic>? capabilities}) async {
    try {
      final response = await _post('/fleet/register', {
        'robot_id': robotId,
        'capabilities': capabilities ?? {},
        'app_version': '1.0.0',
      });
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('FleetConfig: Failed to register: $e');
    }
    return false;
  }

  /// Update robot status
  Future<bool> updateRobotStatus(String robotId, {
    int? battery,
    Map<String, double>? position,
    int? navStatus,
    String? currentGoal,
    bool? estop,
    String? building,
    String? floor,
  }) async {
    try {
      final response = await _post('/fleet/status', {
        'robot_id': robotId,
        if (battery != null) 'battery': battery,
        if (position != null) 'position': position,
        if (navStatus != null) 'nav_status': navStatus,
        if (currentGoal != null) 'current_goal': currentGoal,
        if (estop != null) 'estop': estop,
        if (building != null) 'building': building,
        if (floor != null) 'floor': floor,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('FleetConfig: Failed to update status: $e');
    }
    return false;
  }

  // === HTTP Helpers ===

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_apiKey != null) 'X-API-Key': _apiKey!,
  };

  Future<http.Response> _get(String path) async {
    return http.get(
      Uri.parse('$_apiUrl$path'),
      headers: _headers,
    ).timeout(const Duration(seconds: 10));
  }

  Future<http.Response> _post(String path, Map<String, dynamic> body) async {
    return http.post(
      Uri.parse('$_apiUrl$path'),
      headers: _headers,
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 10));
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }
}

/// Info about a robot in the fleet
class RobotInfo {
  final String robotId;
  final String? building;
  final String? floor;
  final int battery;
  final bool online;
  final bool estop;
  final int navStatus;
  final String? currentGoal;
  final Map<String, double> position;
  final DateTime lastSeen;

  RobotInfo({
    required this.robotId,
    this.building,
    this.floor,
    this.battery = 0,
    this.online = false,
    this.estop = false,
    this.navStatus = 0,
    this.currentGoal,
    this.position = const {'x': 0, 'y': 0, 'theta': 0},
    required this.lastSeen,
  });

  factory RobotInfo.fromJson(Map<String, dynamic> json) {
    return RobotInfo(
      robotId: json['robot_id'] as String? ?? '',
      building: json['building'] as String?,
      floor: json['floor'] as String?,
      battery: (json['battery'] as num?)?.toInt() ?? 0,
      online: json['online'] as bool? ?? false,
      estop: json['estop'] as bool? ?? false,
      navStatus: (json['nav_status'] as num?)?.toInt() ?? 0,
      currentGoal: json['current_goal'] as String?,
      position: (json['position'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, (v as num).toDouble()),
      ) ?? {'x': 0, 'y': 0, 'theta': 0},
      lastSeen: DateTime.fromMillisecondsSinceEpoch(
        (json['last_seen'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  /// Navigation status as human-readable string
  String get navStatusText {
    switch (navStatus) {
      case 600: return 'Idle';
      case 601: return 'Moving';
      case 602: return 'Cancelled';
      case 603: return 'Arrived';
      case 604: return 'Failed';
      case 605: return 'Standby';
      default: return 'Unknown';
    }
  }

  /// Is robot currently moving?
  bool get isMoving => navStatus == 601;

  /// Time since last seen
  Duration get timeSinceLastSeen => DateTime.now().difference(lastSeen);

  /// Is robot recently active (seen within 2 minutes)?
  bool get isActive => timeSinceLastSeen.inMinutes < 2;
}
