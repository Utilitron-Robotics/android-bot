import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'smait_protocol.dart';

/// Connection mode for robot communication
enum ConnectionMode {
  /// Direct WebSocket to robot base (192.168.20.22:9090)
  direct,
  /// Through tablet relay (tablet-ip:8765/8766)
  relay,
}

/// Connection state
enum DualConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

/// Unified connection manager supporting both direct and relay modes
class DualConnectionManager extends ChangeNotifier {
  // Connection config
  ConnectionMode _mode = ConnectionMode.direct;
  String _directIp = '10.42.0.1';  // Robot's own WiFi hotspot
  int _directPort = 9090;
  String _relayIp = '';
  int _relayHttpPort = 8765;
  int _relayWsPort = 8766;

  // State
  DualConnectionState _state = DualConnectionState.disconnected;
  String? _lastError;
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  Timer? _velocityTimer;

  // Robot status
  RobotStatusData _robotStatus = RobotStatusData();
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();

  // Getters
  ConnectionMode get mode => _mode;
  DualConnectionState get state => _state;
  String? get lastError => _lastError;
  bool get isConnected => _state == DualConnectionState.connected;
  RobotStatusData get robotStatus => _robotStatus;
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  String get directIp => _directIp;
  int get directPort => _directPort;
  String get relayIp => _relayIp;
  int get relayHttpPort => _relayHttpPort;
  int get relayWsPort => _relayWsPort;

  String get currentUrl {
    if (_mode == ConnectionMode.direct) {
      return 'ws://$_directIp:$_directPort';
    } else {
      return 'ws://$_relayIp:$_relayWsPort';
    }
  }

  /// Configure direct connection
  void configureDirectConnection({
    required String ip,
    int port = 9090,
  }) {
    _directIp = ip;
    _directPort = port;
    notifyListeners();
  }

  /// Configure relay connection
  void configureRelayConnection({
    required String ip,
    int httpPort = 8765,
    int wsPort = 8766,
  }) {
    _relayIp = ip;
    _relayHttpPort = httpPort;
    _relayWsPort = wsPort;
    notifyListeners();
  }

  /// Set connection mode
  void setMode(ConnectionMode mode) {
    if (_mode != mode) {
      _mode = mode;
      notifyListeners();
      // Reconnect if currently connected
      if (_state == DualConnectionState.connected) {
        disconnect();
        connect();
      }
    }
  }

  /// Connect using current mode
  Future<void> connect() async {
    if (_state == DualConnectionState.connecting) return;

    _state = DualConnectionState.connecting;
    _lastError = null;
    notifyListeners();

    try {
      final url = currentUrl;
      debugPrint('DualConnection: Connecting to $url (mode: $_mode)');

      final uri = Uri.parse(url);
      _channel = WebSocketChannel.connect(uri);

      // Wait for connection
      await _channel!.ready.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('Connection timeout'),
      );

      _state = DualConnectionState.connected;
      _lastError = null;
      notifyListeners();

      // Listen for messages
      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDone,
      );

      // Setup subscriptions
      await _setupSubscriptions();

      debugPrint('DualConnection: Connected successfully');
    } catch (e) {
      _state = DualConnectionState.error;
      _lastError = e.toString();
      notifyListeners();
      debugPrint('DualConnection: Connection failed: $e');
      _scheduleReconnect();
    }
  }

  /// Disconnect
  void disconnect() {
    _reconnectTimer?.cancel();
    _velocityTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _channel = null;
    _state = DualConnectionState.disconnected;
    notifyListeners();
  }

  /// Send raw message via WebSocket
  bool send(Map<String, dynamic> message) {
    if (_channel != null && _state == DualConnectionState.connected) {
      try {
        _channel!.sink.add(jsonEncode(message));
        return true;
      } catch (e) {
        debugPrint('DualConnection: Send error: $e');
        return false;
      }
    }
    return false;
  }

  /// Send velocity command
  void sendVelocity(double linear, double angular) {
    if (_mode == ConnectionMode.relay && _relayIp.isNotEmpty) {
      // Use HTTP for relay mode (more reliable for velocity)
      _sendRelayHttp('/velocity', {'linear': linear, 'angular': angular});
    } else {
      send(SmaitProtocol.publishVelocity(linear, angular));
    }
  }

  /// Start continuous velocity sending (for joystick)
  void startVelocity(double linear, double angular) {
    _velocityTimer?.cancel();
    _velocityTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      sendVelocity(linear, angular);
    });
  }

  /// Stop velocity sending
  void stopVelocity() {
    _velocityTimer?.cancel();
    _velocityTimer = null;
    sendVelocity(0, 0);
  }

  /// Stop robot
  void stop() {
    stopVelocity();
    if (_mode == ConnectionMode.relay && _relayIp.isNotEmpty) {
      _sendRelayHttp('/stop', {});
    } else {
      send(SmaitProtocol.stopRobot());
    }
  }

  /// Emergency stop
  void emergencyStop(bool enabled) {
    if (_mode == ConnectionMode.relay && _relayIp.isNotEmpty) {
      _sendRelayHttp('/estop', {'enabled': enabled});
    } else {
      send(SmaitProtocol.publishSoftStop(enabled));
    }
  }

  /// Navigate to POI
  void navigateTo(String poi) {
    if (_mode == ConnectionMode.relay && _relayIp.isNotEmpty) {
      _sendRelayHttp('/navigate', {'poi': poi});
    } else {
      send(SmaitProtocol.callNavigateToPoi(poi));
    }
  }

  /// Cancel navigation
  void cancelNavigation() {
    if (_mode == ConnectionMode.relay && _relayIp.isNotEmpty) {
      _sendRelayHttp('/cancel', {});
    } else {
      send(SmaitProtocol.publishCancelGoal());
    }
  }

  /// Set speed mode
  void setSpeedMode(int mode) {
    send(SmaitProtocol.callSetSpeedMode(mode));
  }

  /// Get robot info
  void getRobotInfo() {
    send(SmaitProtocol.callGetRobotInfo());
  }

  /// Send HTTP request to relay
  Future<void> _sendRelayHttp(String endpoint, Map<String, dynamic> body) async {
    if (_relayIp.isEmpty) return;
    try {
      final url = 'http://$_relayIp:$_relayHttpPort$endpoint';
      await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
    } catch (e) {
      debugPrint('DualConnection: HTTP relay error: $e');
    }
  }

  /// Check relay status via HTTP
  Future<Map<String, dynamic>?> getRelayStatus() async {
    if (_relayIp.isEmpty) return null;
    try {
      final url = 'http://$_relayIp:$_relayHttpPort/status';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('DualConnection: Relay status error: $e');
    }
    return null;
  }

  void _handleMessage(dynamic data) {
    try {
      final msg = jsonDecode(data as String) as Map<String, dynamic>;
      _messageController.add(msg);
      _parseStatusUpdate(msg);
    } catch (e) {
      debugPrint('DualConnection: Parse error: $e');
    }
  }

  void _handleError(dynamic error) {
    debugPrint('DualConnection: WebSocket error: $error');
    _state = DualConnectionState.error;
    _lastError = error.toString();
    notifyListeners();
    _scheduleReconnect();
  }

  void _handleDone() {
    debugPrint('DualConnection: WebSocket closed');
    _state = DualConnectionState.disconnected;
    notifyListeners();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (_state != DualConnectionState.connected) {
        debugPrint('DualConnection: Attempting reconnect...');
        connect();
      }
    });
  }

  Future<void> _setupSubscriptions() async {
    // Advertise for publishing
    send(SmaitProtocol.advertiseVelocity());
    send(SmaitProtocol.advertiseCancelGoal());
    send(SmaitProtocol.advertiseSoftStop());

    await Future.delayed(const Duration(milliseconds: 200));

    // Subscribe to status topics
    send(SmaitProtocol.subscribeRobotStatus());
    send(SmaitProtocol.subscribeRobotPose());
    send(SmaitProtocol.subscribeNaviStatus());
  }

  void _parseStatusUpdate(Map<String, dynamic> msg) {
    final topic = msg['topic'] as String?;
    final data = msg['msg'];
    if (topic == null || data == null) return;

    switch (topic) {
      case topicRobotStatus:
        _robotStatus = RobotStatusData.fromJson(data as Map<String, dynamic>);
        notifyListeners();
        break;
      case topicRobotPose:
        final pose = RobotPose.fromJson(data as Map<String, dynamic>);
        _robotStatus = _robotStatus.copyWith(pose: pose);
        notifyListeners();
        break;
    }
  }

  @override
  void dispose() {
    disconnect();
    _messageController.close();
    super.dispose();
  }
}

/// Discovered relay info
class DiscoveredRelay {
  final String ip;
  final int httpPort;
  final int wsPort;
  final bool robotConnected;
  final String? robotIp;
  final String? deviceName;
  final int battery;
  final int navStatus;

  DiscoveredRelay({
    required this.ip,
    this.httpPort = 8765,
    this.wsPort = 8766,
    this.robotConnected = false,
    this.robotIp,
    this.deviceName,
    this.battery = 0,
    this.navStatus = 0,
  });

  String get httpUrl => 'http://$ip:$httpPort';
  String get wsUrl => 'ws://$ip:$wsPort';
  String get displayName => deviceName ?? 'Relay @ $ip';
}

/// Auto-discovery for relay tablets on the network
class RelayDiscovery {
  static const int defaultPort = 8765;
  static const int discoveryPort = 9999;
  static const String discoveryRequest = 'SMAIT_RELAY_DISCOVER';

  /// Scan for relays using UDP broadcast (fast) + HTTP fallback
  static Future<List<String>> scanForRelays({
    String subnet = '192.168.1',
    int startHost = 1,
    int endHost = 254,
    Duration timeout = const Duration(milliseconds: 500),
  }) async {
    // Try UDP discovery first (fast)
    final udpRelays = await discoverViaUdp(timeout: const Duration(seconds: 2));
    if (udpRelays.isNotEmpty) {
      return udpRelays.map((r) => r.ip).toList();
    }

    // Fall back to HTTP scan
    return await _scanViaHttp(subnet, startHost, endHost, timeout);
  }

  /// Discover relays via UDP broadcast (returns detailed info)
  static Future<List<DiscoveredRelay>> discoverViaUdp({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final relays = <DiscoveredRelay>[];

    if (kIsWeb) {
      debugPrint('RelayDiscovery: UDP not available on web');
      return relays;
    }

    try {
      // Create UDP socket
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      debugPrint('RelayDiscovery: Sending UDP broadcast to port $discoveryPort');

      // Send broadcast
      final request = utf8.encode(discoveryRequest);
      socket.send(request, InternetAddress('255.255.255.255'), discoveryPort);

      // Also try common subnets
      for (final subnet in ['192.168.1', '192.168.0', '10.0.0', '172.16.0']) {
        socket.send(request, InternetAddress('$subnet.255'), discoveryPort);
      }

      // Listen for responses
      final completer = Completer<void>();
      Timer(timeout, () {
        if (!completer.isCompleted) completer.complete();
      });

      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final packet = socket.receive();
          if (packet != null) {
            try {
              final response = utf8.decode(packet.data);
              final data = jsonDecode(response) as Map<String, dynamic>;

              if (data['type'] == 'SMAIT_RELAY_RESPONSE' || data['type'] == 'SMAIT_RELAY') {
                final relay = DiscoveredRelay(
                  ip: packet.address.address,
                  httpPort: data['relayHttpPort'] as int? ?? defaultPort,
                  wsPort: data['relayWsPort'] as int? ?? (defaultPort + 1),
                  robotConnected: data['robotConnected'] as bool? ?? false,
                  robotIp: data['robotIp'] as String?,
                  deviceName: data['deviceName'] as String?,
                  battery: data['battery'] as int? ?? 0,
                  navStatus: data['navStatus'] as int? ?? 0,
                );
                // Avoid duplicates
                if (!relays.any((r) => r.ip == relay.ip)) {
                  relays.add(relay);
                  debugPrint('RelayDiscovery: Found relay at ${relay.ip} (${relay.deviceName})');
                }
              }
            } catch (e) {
              debugPrint('RelayDiscovery: Error parsing response: $e');
            }
          }
        }
      });

      await completer.future;
      socket.close();
    } catch (e) {
      debugPrint('RelayDiscovery: UDP error: $e');
    }

    return relays;
  }

  /// Discover relays via HTTP (detailed info)
  static Future<List<DiscoveredRelay>> discoverViaHttp({
    String? subnet,
    int startHost = 1,
    int endHost = 254,
    Duration timeout = const Duration(milliseconds: 500),
  }) async {
    // Auto-detect subnet if not provided
    final scanSubnet = subnet ?? await _detectSubnet() ?? '192.168.1';

    final relays = <DiscoveredRelay>[];
    final futures = <Future<DiscoveredRelay?>>[];

    for (var i = startHost; i <= endHost; i++) {
      final ip = '$scanSubnet.$i';
      futures.add(_checkRelayDetailed(ip, timeout));
    }

    final results = await Future.wait(futures);
    for (final result in results) {
      if (result != null) {
        relays.add(result);
      }
    }

    return relays;
  }

  /// HTTP scan returning just IPs (for backwards compatibility)
  static Future<List<String>> _scanViaHttp(
    String subnet,
    int startHost,
    int endHost,
    Duration timeout,
  ) async {
    final relays = <String>[];
    final futures = <Future<String?>>[];

    for (var i = startHost; i <= endHost; i++) {
      final ip = '$subnet.$i';
      futures.add(_checkRelay(ip, timeout));
    }

    final results = await Future.wait(futures);
    for (final result in results) {
      if (result != null) {
        relays.add(result);
      }
    }

    return relays;
  }

  static Future<String?> _checkRelay(String ip, Duration timeout) async {
    try {
      final url = 'http://$ip:$defaultPort/discovery';
      final response = await http.get(Uri.parse(url)).timeout(timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data['type'] == 'SMAIT_RELAY') {
          return ip;
        }
      }
    } catch (_) {
      // Try fallback to /status
      try {
        final url = 'http://$ip:$defaultPort/status';
        final response = await http.get(Uri.parse(url)).timeout(timeout);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data is Map && data.containsKey('connected')) {
            return ip;
          }
        }
      } catch (_) {
        // Not a relay
      }
    }
    return null;
  }

  static Future<DiscoveredRelay?> _checkRelayDetailed(String ip, Duration timeout) async {
    try {
      final url = 'http://$ip:$defaultPort/discovery';
      final response = await http.get(Uri.parse(url)).timeout(timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['type'] == 'SMAIT_RELAY') {
          return DiscoveredRelay(
            ip: ip,
            httpPort: data['relayHttpPort'] as int? ?? defaultPort,
            wsPort: data['relayWsPort'] as int? ?? (defaultPort + 1),
            robotConnected: data['robotConnected'] as bool? ?? false,
            robotIp: data['robotIp'] as String?,
            deviceName: data['deviceName'] as String?,
            battery: data['battery'] as int? ?? 0,
            navStatus: data['navStatus'] as int? ?? 0,
          );
        }
      }
    } catch (_) {
      // Not a relay
    }
    return null;
  }

  /// Auto-detect local subnet
  static Future<String?> _detectSubnet() async {
    if (kIsWeb) return null;

    try {
      final interfaces = await NetworkInterface.list();
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            final parts = addr.address.split('.');
            if (parts.length == 4) {
              return '${parts[0]}.${parts[1]}.${parts[2]}';
            }
          }
        }
      }
    } catch (e) {
      debugPrint('RelayDiscovery: Error detecting subnet: $e');
    }
    return null;
  }
}
