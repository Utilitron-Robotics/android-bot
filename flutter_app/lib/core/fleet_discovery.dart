import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Represents a scanned WiFi network
class ScannedNetwork {
  final String ssid;
  final int rssi;  // Signal strength
  final bool isSecured;

  ScannedNetwork({
    required this.ssid,
    required this.rssi,
    this.isSecured = true,
  });

  /// Signal quality as percentage (roughly)
  int get signalPercent => ((rssi + 100) * 2).clamp(0, 100);
}

/// Represents a discovered or known Pudu robot base
class RobotBase {
  final String ssid;        // WiFi SSID (e.g., "PUDU_ABC123")
  final String ip;          // Robot IP when connected to its network
  final int port;           // Rosbridge port (default 9090)
  final String? nickname;   // User-friendly name
  final String? password;   // WiFi password (if known)
  final DateTime? lastSeen; // Last successful connection
  bool isOnline;            // Currently reachable

  RobotBase({
    required this.ssid,
    this.ip = '192.168.20.22',  // Pudu default
    this.port = 9090,
    this.nickname,
    this.password,
    this.lastSeen,
    this.isOnline = false,
  });

  String get wsUrl => 'ws://$ip:$port';
  String get displayName => nickname ?? ssid;

  Map<String, dynamic> toJson() => {
    'ssid': ssid,
    'ip': ip,
    'port': port,
    'nickname': nickname,
    'password': password,
    'lastSeen': lastSeen?.toIso8601String(),
  };

  factory RobotBase.fromJson(Map<String, dynamic> json) => RobotBase(
    ssid: json['ssid'] as String,
    ip: json['ip'] as String? ?? '192.168.20.22',
    port: json['port'] as int? ?? 9090,
    nickname: json['nickname'] as String?,
    password: json['password'] as String?,
    lastSeen: json['lastSeen'] != null
        ? DateTime.tryParse(json['lastSeen'] as String)
        : null,
  );
}

/// WiFi connection result
class WifiConnectResult {
  final bool success;
  final String message;

  WifiConnectResult({required this.success, required this.message});
}

/// Fleet discovery and management with real WiFi scanning
class FleetDiscovery extends ChangeNotifier {
  final List<RobotBase> _knownRobots = [];
  final List<ScannedNetwork> _scannedNetworks = [];
  bool _isScanning = false;
  bool _isConnecting = false;
  String? _currentSsid;
  String? _lastError;

  List<RobotBase> get knownRobots => List.unmodifiable(_knownRobots);
  List<ScannedNetwork> get scannedNetworks => List.unmodifiable(_scannedNetworks);
  bool get isScanning => _isScanning;
  bool get isConnecting => _isConnecting;
  String? get currentSsid => _currentSsid;
  String? get lastError => _lastError;

  FleetDiscovery() {
    _loadKnownRobots();
    // Get current SSID on init
    getCurrentSsid();
  }

  /// Load known robots from storage
  Future<void> _loadKnownRobots() async {
    final prefs = await SharedPreferences.getInstance();
    final robotsJson = prefs.getStringList('known_robots') ?? [];

    _knownRobots.clear();
    for (final json in robotsJson) {
      try {
        final map = Map<String, dynamic>.from(
          Uri.splitQueryString(json).map((k, v) => MapEntry(k, v))
        );
        final robot = RobotBase(
          ssid: map['ssid'] ?? 'Unknown',
          ip: map['ip'] ?? '192.168.20.22',
          port: int.tryParse(map['port'] ?? '9090') ?? 9090,
          nickname: map['nickname']?.isNotEmpty == true ? map['nickname'] : null,
          password: map['password']?.isNotEmpty == true ? map['password'] : null,
        );
        _knownRobots.add(robot);
      } catch (e) {
        debugPrint('Failed to parse robot: $e');
      }
    }

    // Add known Pudu bases if list is empty
    if (_knownRobots.isEmpty) {
      _knownRobots.addAll([
        RobotBase(ssid: 'TY126AA003F0-005878', nickname: 'Pudu Bot 1'),
        RobotBase(ssid: 'TY126AA003F0-005993', nickname: 'Pudu Bot 2'),
      ]);
    }

    notifyListeners();
  }

  /// Save known robots to storage
  Future<void> _saveKnownRobots() async {
    final prefs = await SharedPreferences.getInstance();
    final robotsJson = _knownRobots.map((r) =>
      'ssid=${r.ssid}&ip=${r.ip}&port=${r.port}&nickname=${r.nickname ?? ""}&password=${r.password ?? ""}'
    ).toList();
    await prefs.setStringList('known_robots', robotsJson);
  }

  /// Add a new robot to known list
  Future<void> addRobot(RobotBase robot) async {
    _knownRobots.removeWhere((r) => r.ssid == robot.ssid);
    _knownRobots.insert(0, robot);
    await _saveKnownRobots();
    notifyListeners();
  }

  /// Remove a robot from known list
  Future<void> removeRobot(String ssid) async {
    _knownRobots.removeWhere((r) => r.ssid == ssid);
    await _saveKnownRobots();
    notifyListeners();
  }

  /// Ping a robot to check if it's online (via WebSocket)
  Future<bool> pingRobot(RobotBase robot) async {
    try {
      final uri = Uri.parse(robot.wsUrl);
      final channel = WebSocketChannel.connect(uri);

      await channel.ready.timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw TimeoutException('Connection timeout'),
      );

      await channel.sink.close();
      robot.isOnline = true;
      notifyListeners();
      return true;
    } catch (e) {
      robot.isOnline = false;
      notifyListeners();
      return false;
    }
  }

  /// Check all known robots for connectivity
  Future<void> refreshRobotStatus() async {
    _isScanning = true;
    notifyListeners();

    final futures = _knownRobots.map((robot) => pingRobot(robot));
    await Future.wait(futures);

    _isScanning = false;
    notifyListeners();
  }

  /// Scan for nearby WiFi networks
  Future<List<ScannedNetwork>> scanWifiNetworks({bool filterRobots = false}) async {
    _isScanning = true;
    _scannedNetworks.clear();
    _lastError = null;
    notifyListeners();

    try {
      if (kIsWeb) {
        _lastError = 'WiFi scanning not available in browser';
      } else if (Platform.isMacOS) {
        await _scanMacOsWifi(filterRobots: filterRobots);
      } else if (Platform.isAndroid) {
        _lastError = 'Android: Use system WiFi settings to connect';
      } else if (Platform.isIOS) {
        _lastError = 'iOS: Use system WiFi settings to connect';
      }
    } catch (e) {
      _lastError = 'Scan error: $e';
      debugPrint('WiFi scan error: $e');
    }

    _isScanning = false;
    notifyListeners();
    return _scannedNetworks;
  }

  /// Scan WiFi on macOS
  Future<void> _scanMacOsWifi({bool filterRobots = false}) async {
    // Use airport to scan - note: may require WiFi to be on
    final result = await Process.run(
      '/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport',
      ['-s'],
    );

    debugPrint('Airport scan exit code: ${result.exitCode}');
    debugPrint('Airport scan stdout: ${result.stdout}');
    debugPrint('Airport scan stderr: ${result.stderr}');

    if (result.exitCode == 0) {
      final output = result.stdout as String;
      final lines = output.split('\n');

      // Skip header line, parse each network
      for (final line in lines.skip(1)) {
        if (line.trim().isEmpty) continue;

        // Airport output format: SSID BSSID RSSI CHANNEL HT CC SECURITY
        // SSID can have spaces, so we parse from the end
        final trimmed = line.trimLeft();
        if (trimmed.isEmpty) continue;

        // Find RSSI (negative number like -67)
        final rssiMatch = RegExp(r'\s(-\d+)\s').firstMatch(line);
        if (rssiMatch == null) continue;

        final rssi = int.tryParse(rssiMatch.group(1) ?? '-100') ?? -100;
        final ssidEnd = rssiMatch.start;
        final ssid = line.substring(0, ssidEnd).trim();

        if (ssid.isEmpty) continue;

        // Check if secured (look for WPA, WEP, etc. at end of line)
        final isSecured = line.contains('WPA') || line.contains('WEP');

        // Filter for robot networks if requested
        if (filterRobots) {
          final upper = ssid.toUpperCase();
          if (!upper.contains('PUDU') &&
              !upper.contains('ROBOT') &&
              !upper.contains('TIBO') &&
              !upper.contains('TY126') &&  // Pudu base pattern
              !upper.contains('ROS')) {
            continue;
          }
        }

        _scannedNetworks.add(ScannedNetwork(
          ssid: ssid,
          rssi: rssi,
          isSecured: isSecured,
        ));
      }

      // Sort by signal strength
      _scannedNetworks.sort((a, b) => b.rssi.compareTo(a.rssi));
    } else {
      _lastError = 'Airport scan failed: ${result.stderr}';
    }
  }

  /// Get current WiFi SSID
  Future<String?> getCurrentSsid() async {
    try {
      if (kIsWeb) return null;

      if (Platform.isMacOS) {
        final result = await Process.run(
          '/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport',
          ['-I'],
        );

        if (result.exitCode == 0) {
          final match = RegExp(r'^\s*SSID:\s*(.+)$', multiLine: true)
              .firstMatch(result.stdout as String);
          _currentSsid = match?.group(1)?.trim();
          notifyListeners();
          return _currentSsid;
        }
      }
    } catch (e) {
      debugPrint('Failed to get current SSID: $e');
    }
    return null;
  }

  /// Connect to a WiFi network (macOS)
  Future<WifiConnectResult> connectToWifi(String ssid, {String? password}) async {
    if (kIsWeb) {
      return WifiConnectResult(
        success: false,
        message: 'Cannot connect to WiFi from browser',
      );
    }

    _isConnecting = true;
    _lastError = null;
    notifyListeners();

    try {
      if (Platform.isMacOS) {
        return await _connectMacOsWifi(ssid, password: password);
      } else {
        return WifiConnectResult(
          success: false,
          message: 'Use system WiFi settings on this platform',
        );
      }
    } finally {
      _isConnecting = false;
      notifyListeners();
    }
  }

  /// Connect to WiFi on macOS using networksetup
  Future<WifiConnectResult> _connectMacOsWifi(String ssid, {String? password}) async {
    // Get WiFi interface name (usually en0 or en1)
    final interfaceResult = await Process.run('networksetup', ['-listallhardwareports']);
    String wifiInterface = 'en1'; // Default

    if (interfaceResult.exitCode == 0) {
      final output = interfaceResult.stdout as String;
      // Find the line after "Hardware Port: Wi-Fi"
      final lines = output.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('Hardware Port: Wi-Fi')) {
          if (i + 1 < lines.length) {
            final match = RegExp(r'Device:\s*(\w+)').firstMatch(lines[i + 1]);
            if (match != null) {
              wifiInterface = match.group(1)!;
            }
          }
          break;
        }
      }
    }

    debugPrint('Using WiFi interface: $wifiInterface');

    // Connect to the network
    final args = ['-setairportnetwork', wifiInterface, ssid];
    if (password != null && password.isNotEmpty) {
      args.add(password);
    }

    final result = await Process.run('networksetup', args);

    debugPrint('networksetup exit code: ${result.exitCode}');
    debugPrint('networksetup stdout: ${result.stdout}');
    debugPrint('networksetup stderr: ${result.stderr}');

    if (result.exitCode == 0) {
      // Wait a moment for connection to establish
      await Future.delayed(const Duration(seconds: 2));

      // Verify connection
      final currentSsid = await getCurrentSsid();
      if (currentSsid == ssid) {
        return WifiConnectResult(
          success: true,
          message: 'Connected to $ssid',
        );
      } else {
        return WifiConnectResult(
          success: false,
          message: 'Connection attempt completed but not connected to $ssid (current: $currentSsid)',
        );
      }
    } else {
      final error = (result.stderr as String).isNotEmpty
          ? result.stderr as String
          : 'Connection failed';
      _lastError = error;
      return WifiConnectResult(
        success: false,
        message: error,
      );
    }
  }

  /// Disconnect from current WiFi (macOS)
  Future<void> disconnectWifi() async {
    if (kIsWeb || !Platform.isMacOS) return;

    try {
      await Process.run('networksetup', ['-setairportpower', 'en1', 'off']);
      await Future.delayed(const Duration(milliseconds: 500));
      await Process.run('networksetup', ['-setairportpower', 'en1', 'on']);
      _currentSsid = null;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to disconnect WiFi: $e');
    }
  }
}
