/// Platform-aware transport layer
///
/// Transport Buddy Pattern:
/// - Web (kIsWeb=true): WebSocket (primary) + WebRTC (buddy)
/// - Native (kIsWeb=false): gRPC (primary) + WebRTC (buddy)
///
/// Primary transport handles: commands, status, heartbeat
/// WebRTC buddy handles: map streaming, low-latency velocity (optional)
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'grpc_client.dart';
import 'rosbridge_client.dart';
import 'webrtc_transport.dart';
import '../models/occupancy_grid.dart' as model;
import '../generated/robot_control.pb.dart' as pb;

/// Unified robot status data (normalized from both transports)
class RobotStatusData {
  final int navStatus;
  final String navGoal;
  final double battery;
  final double linearVelocity;
  final double angularVelocity;
  final bool connected;

  const RobotStatusData({
    this.navStatus = 0,
    this.navGoal = '',
    this.battery = 0,
    this.linearVelocity = 0,
    this.angularVelocity = 0,
    this.connected = false,
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
}

/// Abstract transport interface
/// Implemented by NativeTransport (gRPC) and WebTransport (WebSocket)
abstract class PlatformTransport extends ChangeNotifier {
  bool get isConnected;
  Stream<bool> get connectionState;
  Stream<RobotStatusData> get statusStream;

  Future<void> connect(String host, {int? port});
  Future<void> disconnect();

  void sendVelocity(double linear, double angular);
  Future<void> navigate(String waypoint);
  void stop();
  Future<void> cancelNavigation();

  /// WebRTC buddy for map streaming
  WebRtcTransport? get webrtc;
  Stream<model.OccupancyGrid> get mapStream;

  /// Connect WebRTC for map streaming
  Future<void> connectMapStream();
}

/// Factory function - creates appropriate transport for platform
PlatformTransport createPlatformTransport() {
  if (kIsWeb) {
    debugPrint('PlatformTransport: Web detected, using WebSocket');
    return WebTransport();
  } else {
    debugPrint('PlatformTransport: Native detected, using gRPC');
    return NativeTransport();
  }
}

// ============================================================
// NATIVE TRANSPORT (gRPC + WebRTC)
// ============================================================

/// Native transport using gRPC with WebRTC buddy
/// Used on macOS, iOS, Android
class NativeTransport extends PlatformTransport {
  static const String _tag = 'NativeTransport';

  final GrpcRobotClient _grpc = GrpcRobotClient();
  WebRtcTransport? _webrtc;

  final _statusController = StreamController<RobotStatusData>.broadcast();
  StreamSubscription? _grpcStatusSub;

  @override
  bool get isConnected => _grpc.isConnected;

  @override
  Stream<bool> get connectionState => _grpc.connectionState;

  @override
  Stream<RobotStatusData> get statusStream => _statusController.stream;

  @override
  WebRtcTransport? get webrtc => _webrtc;

  @override
  Stream<model.OccupancyGrid> get mapStream =>
      _webrtc?.mapStream ?? const Stream.empty();

  @override
  Future<void> connect(String host, {int? port}) async {
    debugPrint('$_tag: Connecting to $host:${port ?? 50051}');

    // Connect gRPC
    await _grpc.connect(host, port: port ?? 50051);

    // Set up status listener
    _grpcStatusSub = _grpc.robotStatus.listen((status) {
      _statusController.add(RobotStatusData(
        navStatus: status.navStatus,
        navGoal: status.navGoal,
        battery: status.battery.toDouble(),
        linearVelocity: status.linearVelocity,
        angularVelocity: status.angularVelocity,
        connected: true,
      ));
    });

    // Initialize WebRTC buddy (uses gRPC for signaling)
    _webrtc = WebRtcTransport(grpcClient: _grpc);

    notifyListeners();
  }

  @override
  Future<void> connectMapStream() async {
    if (_webrtc == null) {
      throw Exception('WebRTC not initialized - connect first');
    }
    debugPrint('$_tag: Connecting WebRTC map stream');
    await _webrtc!.connect();
  }

  @override
  Future<void> disconnect() async {
    debugPrint('$_tag: Disconnecting');
    await _grpcStatusSub?.cancel();
    await _webrtc?.disconnect();
    await _grpc.disconnect();
    _webrtc = null;
    notifyListeners();
  }

  @override
  void sendVelocity(double linear, double angular) {
    // Prefer WebRTC for lowest latency if connected
    if (_webrtc?.isConnected ?? false) {
      _webrtc!.sendVelocity(linear, angular);
    } else {
      _grpc.sendVelocity(linear, angular);
    }
  }

  @override
  Future<void> navigate(String waypoint) async {
    _grpc.navigate(waypoint);
  }

  @override
  void stop() {
    _grpc.stop();
  }

  @override
  Future<void> cancelNavigation() async {
    _grpc.cancelNavigation();
  }

  @override
  void dispose() {
    disconnect();
    _statusController.close();
    super.dispose();
  }
}

// ============================================================
// WEB TRANSPORT (WebSocket + WebRTC)
// ============================================================

/// Web transport using WebSocket with WebRTC buddy
/// Used in Chrome/browsers where gRPC doesn't work
class WebTransport extends PlatformTransport {
  static const String _tag = 'WebTransport';

  final RosbridgeClient _ws = RosbridgeClient();
  WebRtcTransport? _webrtc;
  GrpcRobotClient? _grpcForSignaling; // Only for WebRTC signaling, not commands

  final _statusController = StreamController<RobotStatusData>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  StreamSubscription? _wsMessageSub;

  @override
  bool get isConnected => _ws.isConnected;

  @override
  Stream<bool> get connectionState => _connectionController.stream;

  @override
  Stream<RobotStatusData> get statusStream => _statusController.stream;

  @override
  WebRtcTransport? get webrtc => _webrtc;

  @override
  Stream<model.OccupancyGrid> get mapStream =>
      _webrtc?.mapStream ?? const Stream.empty();

  @override
  Future<void> connect(String host, {int? port}) async {
    final wsPort = port ?? 8766;
    final wsUrl = 'ws://$host:$wsPort';
    debugPrint('$_tag: Connecting to $wsUrl');

    // Connect WebSocket
    await _ws.connect(wsUrl);

    // Subscribe to robot status
    _ws.subscribe(
      topic: '/robot_status',
      type: 'yutong_assistance/RobotStatus',
    );

    // Listen for status messages
    _wsMessageSub = _ws.messages.listen((msg) {
      if (msg['topic'] == '/robot_status') {
        final data = msg['msg'] as Map<String, dynamic>?;
        if (data != null) {
          _statusController.add(RobotStatusData(
            navStatus: data['nav_status'] as int? ?? 0,
            navGoal: data['current_goal_name'] as String? ?? '',
            battery: (data['battery'] as num?)?.toDouble() ?? 0,
            linearVelocity: _parseVelocity(data['velocity'], 0),
            angularVelocity: _parseVelocity(data['velocity'], 1),
            connected: true,
          ));
        }
      }
    });

    // Set up connection state forwarding
    _ws.connectionState.listen((state) {
      _connectionController.add(state == WsConnectionState.connected);
    });

    _connectionController.add(true);
    notifyListeners();
  }

  double _parseVelocity(dynamic vel, int index) {
    if (vel is List && vel.length > index) {
      return (vel[index] as num).toDouble();
    }
    return 0.0;
  }

  @override
  Future<void> connectMapStream() async {
    // WebRTC on web needs WebSocket for signaling (can't use gRPC)
    // For now, map streaming on web is not supported via WebRTC
    // The relay can send map data over WebSocket instead
    debugPrint('$_tag: WebRTC map not yet supported on web - use WS map');
  }

  @override
  Future<void> disconnect() async {
    debugPrint('$_tag: Disconnecting');
    await _wsMessageSub?.cancel();
    _ws.disconnect();
    _webrtc = null;
    _connectionController.add(false);
    notifyListeners();
  }

  @override
  void sendVelocity(double linear, double angular) {
    _ws.advertise(
      topic: '/cmd_vel_mux/input/teleop',
      type: 'geometry_msgs/Twist',
    );
    _ws.publish(
      topic: '/cmd_vel_mux/input/teleop',
      msg: {
        'linear': {'x': linear, 'y': 0, 'z': 0},
        'angular': {'x': 0, 'y': 0, 'z': angular},
      },
    );
  }

  @override
  Future<void> navigate(String waypoint) async {
    await _ws.callService(
      service: '/poi',
      args: {'poi': waypoint},
    );
  }

  @override
  void stop() {
    sendVelocity(0, 0);
  }

  @override
  Future<void> cancelNavigation() async {
    _ws.advertise(
      topic: '/move_base/cancel',
      type: 'actionlib_msgs/GoalID',
    );
    _ws.publish(
      topic: '/move_base/cancel',
      msg: {'stamp': '', 'id': ''},
    );
    _ws.unadvertise(topic: '/move_base/cancel');
  }

  @override
  void dispose() {
    disconnect();
    _statusController.close();
    _connectionController.close();
    _ws.dispose();
    super.dispose();
  }
}
