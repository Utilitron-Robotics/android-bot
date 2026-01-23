import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'grpc_client.dart';
import 'rosbridge_client.dart';
import '../generated/robot_control.pbgrpc.dart' as pb;

/// Simple transport that auto-selects gRPC (native) or WebSocket (web)
///
/// Platform detection:
/// - kIsWeb == true  → WebSocket to relay:8766
/// - kIsWeb == false → gRPC to relay:50051
class SimpleTransport extends ChangeNotifier {
  static const String _tag = 'SimpleTransport';
  static const String _prefsKey = 'relay_ip';

  // Transport instances
  GrpcRobotClient? _grpc;
  RosbridgeClient? _ws;

  // State
  String _relayIp = '';
  bool _isConnected = false;
  bool _isConnecting = false;
  String? _lastError;

  // Status from robot
  int _navStatus = 0;
  double _battery = 0;
  String _currentGoal = '';

  // Streams
  final _statusController = StreamController<RobotStatusUpdate>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  StreamSubscription? _grpcStatusSub;
  StreamSubscription? _grpcBufferSub;
  StreamSubscription? _wsMessageSub;

  // Getters
  String get relayIp => _relayIp;
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  String? get lastError => _lastError;
  int get navStatus => _navStatus;
  double get battery => _battery;
  String get currentGoal => _currentGoal;
  Stream<RobotStatusUpdate> get statusStream => _statusController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;

  /// True if running in a browser (Chrome, etc)
  bool get isWeb => kIsWeb;

  /// Current transport type
  String get transportType => kIsWeb ? 'WebSocket' : 'gRPC';

  /// Current connection URL (for display)
  String get connectionUrl {
    if (_relayIp.isEmpty) return '';
    return kIsWeb
        ? 'ws://$_relayIp:8766'
        : 'grpc://$_relayIp:50051';
  }

  SimpleTransport() {
    _loadSavedIp();
  }

  Future<void> _loadSavedIp() async {
    final prefs = await SharedPreferences.getInstance();
    _relayIp = prefs.getString(_prefsKey) ?? '';
    notifyListeners();
  }

  Future<void> _saveIp(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, ip);
  }

  /// Connect to relay tablet
  /// [ip] - Just the IP address (e.g., "192.168.88.37")
  Future<void> connect(String ip) async {
    if (_isConnecting) return;

    _isConnecting = true;
    _lastError = null;
    _relayIp = ip;
    await _saveIp(ip);
    notifyListeners();

    try {
      if (kIsWeb) {
        await _connectWebSocket(ip);
      } else {
        await _connectGrpc(ip);
      }

      _isConnected = true;
      _isConnecting = false;
      _connectionController.add(true);
      notifyListeners();

      debugPrint('$_tag: ✅ Connected via $transportType to $connectionUrl');
    } catch (e) {
      _isConnected = false;
      _isConnecting = false;
      _lastError = e.toString();
      _connectionController.add(false);
      notifyListeners();

      debugPrint('$_tag: ❌ Connection failed: $e');
      rethrow;
    }
  }

  Future<void> _connectGrpc(String ip) async {
    debugPrint('$_tag: Connecting gRPC to $ip:50051...');

    // Clean up any existing connection
    await _grpc?.disconnect();
    _grpcStatusSub?.cancel();
    _grpcBufferSub?.cancel();

    _grpc = GrpcRobotClient();

    // Listen for status updates
    _grpcStatusSub = _grpc!.robotStatus.listen((status) {
      _navStatus = status.navStatus;
      _battery = status.battery.toDouble();
      _currentGoal = status.navGoal;

      _statusController.add(RobotStatusUpdate(
        navStatus: status.navStatus,
        battery: status.battery.toDouble(),
        currentGoal: status.navGoal,
        x: status.pose.x,
        y: status.pose.y,
        theta: status.pose.theta,
        connected: status.connected,
      ));
      notifyListeners();
    });

    // Listen for connection state
    _grpc!.connectionState.listen((connected) {
      if (_isConnected != connected) {
        _isConnected = connected;
        _connectionController.add(connected);
        notifyListeners();
      }
    });

    // Connect
    await _grpc!.connect(ip, port: 50051);
  }

  Future<void> _connectWebSocket(String ip) async {
    final url = 'ws://$ip:8766';
    debugPrint('$_tag: Connecting WebSocket to $url...');

    // Clean up any existing connection
    _ws?.disconnect();
    _wsMessageSub?.cancel();

    _ws = RosbridgeClient();

    // Listen for messages
    _wsMessageSub = _ws!.messages.listen((msg) {
      if (msg['topic'] == '/robot_status') {
        final data = msg['msg'] as Map<String, dynamic>?;
        if (data != null) {
          _navStatus = data['nav_status'] as int? ?? 0;
          _battery = (data['battery'] as num?)?.toDouble() ?? 0;
          _currentGoal = data['current_goal_name'] as String? ?? '';

          _statusController.add(RobotStatusUpdate(
            navStatus: _navStatus,
            battery: _battery,
            currentGoal: _currentGoal,
            x: 0, y: 0, theta: 0, // WS doesn't provide pose in status
            connected: true,
          ));
          notifyListeners();
        }
      }
    });

    // Connect and subscribe
    await _ws!.connect(url);

    // Subscribe to robot status
    _ws!.subscribe(
      topic: '/robot_status',
      type: 'yutong_assistance/RobotStatus',
    );
  }

  /// Disconnect from relay
  void disconnect() {
    _grpcStatusSub?.cancel();
    _grpcBufferSub?.cancel();
    _wsMessageSub?.cancel();

    _grpc?.disconnect();
    _ws?.disconnect();

    _isConnected = false;
    _connectionController.add(false);
    notifyListeners();

    debugPrint('$_tag: Disconnected');
  }

  /// Navigate to waypoint
  Future<void> navigate(String waypoint) async {
    if (!_isConnected) throw StateError('Not connected');

    debugPrint('$_tag: Navigate to $waypoint');

    if (kIsWeb) {
      await _ws!.callService(
        service: '/poi',
        args: {'poi': waypoint},
      );
    } else {
      _grpc!.navigate(waypoint);
    }
  }

  /// Send velocity command
  void sendVelocity(double linear, double angular) {
    if (!_isConnected) return;

    if (kIsWeb) {
      _ws!.advertise(
        topic: '/cmd_vel_mux/input/teleop',
        type: 'geometry_msgs/Twist',
      );
      _ws!.publish(
        topic: '/cmd_vel_mux/input/teleop',
        msg: {
          'linear': {'x': linear},
          'angular': {'z': angular},
        },
      );
    } else {
      _grpc!.sendVelocity(linear, angular);
    }
  }

  /// Stop robot
  void stop() {
    sendVelocity(0, 0);
    if (!kIsWeb && _grpc != null) {
      _grpc!.stop();
    }
  }

  /// Cancel navigation
  Future<void> cancelNavigation() async {
    if (!_isConnected) return;

    if (kIsWeb) {
      _ws!.advertise(
        topic: '/move_base/cancel',
        type: 'actionlib_msgs/GoalID',
      );
      _ws!.publish(
        topic: '/move_base/cancel',
        msg: {'stamp': '', 'id': ''},
      );
      _ws!.unadvertise(topic: '/move_base/cancel');
    } else {
      _grpc!.cancelNavigation();
    }
  }

  /// Load buffer commands (gRPC only)
  void loadBufferCommands(List<pb.BufferCommand> commands, {bool clearExisting = true}) {
    if (kIsWeb) {
      debugPrint('$_tag: Buffer commands not supported on web');
      return;
    }
    _grpc?.loadBufferCommands(commands, clearExisting: clearExisting);
  }

  /// Pause buffer (gRPC only)
  void pauseBuffer() {
    if (!kIsWeb) _grpc?.pauseBuffer();
  }

  /// Resume buffer (gRPC only)
  void resumeBuffer() {
    if (!kIsWeb) _grpc?.resumeBuffer();
  }

  /// Skip buffer command (gRPC only)
  void skipBufferCommand() {
    if (!kIsWeb) _grpc?.skipBufferCommand();
  }

  /// Clear buffer (gRPC only)
  void clearBuffer() {
    if (!kIsWeb) _grpc?.clearBuffer();
  }

  /// Get gRPC client for advanced operations (native only)
  GrpcRobotClient? get grpcClient => _grpc;

  /// Get WS client for advanced operations (web only)
  RosbridgeClient? get wsClient => _ws;

  @override
  void dispose() {
    disconnect();
    _statusController.close();
    _connectionController.close();
    super.dispose();
  }
}

/// Robot status update from either transport
class RobotStatusUpdate {
  final int navStatus;
  final double battery;
  final String currentGoal;
  final double x;
  final double y;
  final double theta;
  final bool connected;

  RobotStatusUpdate({
    required this.navStatus,
    required this.battery,
    required this.currentGoal,
    required this.x,
    required this.y,
    required this.theta,
    required this.connected,
  });

  String get navStatusText {
    switch (navStatus) {
      case 600: return 'Idle';
      case 601: return 'Moving';
      case 602: return 'Cancelled';
      case 603: return 'Arrived';
      case 604: return 'Failed';
      case 605: return 'Standby';
      default: return 'Unknown ($navStatus)';
    }
  }
}
