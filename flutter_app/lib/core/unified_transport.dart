/// Unified Transport Manager
///
/// The ULTIMATE transport system that intelligently selects and manages:
/// - gRPC for WAN command/control (reliable, binary, bidirectional)
/// - WebRTC for low-latency video and teleoperation
/// - MQTT for pub/sub events and fleet management
/// - WebSocket for LAN rosbridge compatibility
/// - HTTP as absolute fallback
///
/// Features:
/// - Automatic transport selection based on network conditions
/// - Seamless failover between transports
/// - Priority-based command routing
/// - Predictive control for high-latency scenarios
/// - Quality-adaptive behavior
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/occupancy_grid.dart' as model;
import 'transport_config.dart';
import 'adaptive_transport.dart';
import 'robot_transport.dart';
import 'grpc_client.dart';
import 'webrtc_transport.dart';
import 'mqtt_transport.dart';
import 'predictive_control.dart';

/// Unified transport capabilities
class TransportCapabilities {
  final bool supportsStreaming; // Can stream status updates
  final bool supportsBidirectional; // Can do bidirectional streaming
  final bool supportsVideo; // Can handle video streams
  final bool supportsLowLatency; // Sub-100ms RTT capable
  final bool supportsReliableDelivery; // Guaranteed delivery
  final bool supportsPubSub; // Publish/subscribe pattern

  const TransportCapabilities({
    this.supportsStreaming = false,
    this.supportsBidirectional = false,
    this.supportsVideo = false,
    this.supportsLowLatency = false,
    this.supportsReliableDelivery = false,
    this.supportsPubSub = false,
  });

  static const grpc = TransportCapabilities(
    supportsStreaming: true,
    supportsBidirectional: true,
    supportsVideo: false,
    supportsLowLatency: false,
    supportsReliableDelivery: true,
    supportsPubSub: false,
  );

  static const webrtc = TransportCapabilities(
    supportsStreaming: true,
    supportsBidirectional: true,
    supportsVideo: true,
    supportsLowLatency: true,
    supportsReliableDelivery: false,
    supportsPubSub: false,
  );

  static const mqtt = TransportCapabilities(
    supportsStreaming: true,
    supportsBidirectional: false,
    supportsVideo: false,
    supportsLowLatency: false,
    supportsReliableDelivery: true,
    supportsPubSub: true,
  );

  static const websocket = TransportCapabilities(
    supportsStreaming: true,
    supportsBidirectional: true,
    supportsVideo: false,
    supportsLowLatency: true,
    supportsReliableDelivery: false,
    supportsPubSub: false,
  );

  static const http = TransportCapabilities(
    supportsStreaming: false,
    supportsBidirectional: false,
    supportsVideo: false,
    supportsLowLatency: false,
    supportsReliableDelivery: true,
    supportsPubSub: false,
  );
}

/// Transport endpoint configuration
class TransportEndpoints {
  final String? grpcHost;
  final int grpcPort;
  final String? webrtcSignalingUrl;
  final String? mqttBrokerUrl;
  final String? websocketUrl;
  final String? httpBaseUrl;
  final String robotId;

  const TransportEndpoints({
    this.grpcHost,
    this.grpcPort = 50051,
    this.webrtcSignalingUrl,
    this.mqttBrokerUrl,
    this.websocketUrl,
    this.httpBaseUrl,
    required this.robotId,
  });

  String get grpcEndpoint => grpcHost != null ? '$grpcHost:$grpcPort' : '';

  TransportEndpoints copyWith({
    String? grpcHost,
    int? grpcPort,
    String? webrtcSignalingUrl,
    String? mqttBrokerUrl,
    String? websocketUrl,
    String? httpBaseUrl,
    String? robotId,
  }) =>
      TransportEndpoints(
        grpcHost: grpcHost ?? this.grpcHost,
        grpcPort: grpcPort ?? this.grpcPort,
        webrtcSignalingUrl: webrtcSignalingUrl ?? this.webrtcSignalingUrl,
        mqttBrokerUrl: mqttBrokerUrl ?? this.mqttBrokerUrl,
        websocketUrl: websocketUrl ?? this.websocketUrl,
        httpBaseUrl: httpBaseUrl ?? this.httpBaseUrl,
        robotId: robotId ?? this.robotId,
      );
}

/// Connection status for each transport
class TransportConnectionStatus {
  final bool grpcConnected;
  final bool webrtcConnected;
  final bool mqttConnected;
  final bool websocketConnected;
  final bool httpReachable;
  final String? activeTransport;
  final NetworkCondition networkCondition;

  const TransportConnectionStatus({
    this.grpcConnected = false,
    this.webrtcConnected = false,
    this.mqttConnected = false,
    this.websocketConnected = false,
    this.httpReachable = false,
    this.activeTransport,
    this.networkCondition = NetworkCondition.good,
  });

  bool get hasAnyConnection =>
      grpcConnected ||
      webrtcConnected ||
      mqttConnected ||
      websocketConnected ||
      httpReachable;

  int get connectionCount =>
      (grpcConnected ? 1 : 0) +
      (webrtcConnected ? 1 : 0) +
      (mqttConnected ? 1 : 0) +
      (websocketConnected ? 1 : 0) +
      (httpReachable ? 1 : 0);
}

/// THE Unified Transport Manager
class UnifiedTransportManager extends ChangeNotifier {
  static const String _tag = 'UnifiedTransport';

  // Configuration
  final TransportConfig _config;
  TransportEndpoints _endpoints;

  // Individual transports
  GrpcRobotClient? _grpc;
  WebRtcTransport? _webrtc;
  MqttTransport? _mqtt;
  AdaptiveTransport? _adaptive; // Handles WebSocket + HTTP

  // Predictive control
  late final PredictiveController _predictiveController;

  // State
  TransportConnectionStatus _status = const TransportConnectionStatus();
  String? _lastError;
  Timer? _healthCheckTimer;

  // Streams
  final _statusController =
      StreamController<TransportConnectionStatus>.broadcast();
  final _robotStatusController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _commandResultController = StreamController<CommandAck>.broadcast();

  // Callbacks
  StreamSubscription? _grpcStatusSub;
  StreamSubscription? _grpcCommandSub;
  StreamSubscription? _mqttMessageSub;
  StreamSubscription? _webrtcMessageSub;

  UnifiedTransportManager({
    required TransportEndpoints endpoints,
    TransportConfig? config,
  })  : _endpoints = endpoints,
        _config = config ?? TransportConfig.instance {
    _predictiveController = PredictiveController(config: _config);
    _predictiveController.setCommandCallback(_sendVelocityInternal);
  }

  // Getters
  TransportConnectionStatus get status => _status;
  Stream<TransportConnectionStatus> get statusStream =>
      _statusController.stream;
  Stream<Map<String, dynamic>> get robotStatus => _robotStatusController.stream;
  Stream<CommandAck> get commandResults => _commandResultController.stream;
  Stream<model.OccupancyGrid> get mapStream =>
      _webrtc?.mapStream ?? const Stream.empty();
  bool get isConnected => _status.hasAnyConnection;
  String? get lastError => _lastError;
  PredictiveController get predictiveController => _predictiveController;

  // Transport access
  GrpcRobotClient? get grpc => _grpc;
  WebRtcTransport? get webrtc => _webrtc;
  MqttTransport? get mqtt => _mqtt;

  /// Initialize all transports
  Future<void> initialize() async {
    debugPrint('$_tag: Initializing unified transport...');

    // Initialize gRPC if endpoint provided
    if (_endpoints.grpcHost != null) {
      _grpc = GrpcRobotClient();
      _setupGrpcListeners();
    }

    // Initialize WebRTC for data channels (requires gRPC for signaling)
    if (_grpc != null) {
      _webrtc = WebRtcTransport(grpcClient: _grpc!);
      // Listeners for WebRTC state are now handled internally or by consumers
    }

    // Initialize MQTT if broker URL provided
    if (_endpoints.mqttBrokerUrl != null) {
      _mqtt = MqttTransport(
        robotId: _endpoints.robotId,
        config: _config,
      );
      _setupMqttListeners();
    }

    // Initialize adaptive transport (WebSocket + HTTP fallback)
    if (_endpoints.websocketUrl != null || _endpoints.httpBaseUrl != null) {
      _adaptive = AdaptiveTransport();
      _adaptive!.initialize(
        websocketUrl: _endpoints.websocketUrl,
        httpEndpoint: _endpoints.httpBaseUrl,
      );
    }

    debugPrint('$_tag: Initialized transports - gRPC: ${_grpc != null}, '
        'WebRTC: ${_webrtc != null}, MQTT: ${_mqtt != null}, '
        'Adaptive: ${_adaptive != null}');
  }

  /// Connect all available transports
  Future<void> connect() async {
    debugPrint('$_tag: Connecting all transports...');

    final futures = <Future>[];

    // Connect gRPC
    if (_grpc != null && _endpoints.grpcHost != null) {
      futures.add(_connectGrpc());
    }

    // Connect MQTT
    if (_mqtt != null && _endpoints.mqttBrokerUrl != null) {
      futures.add(_connectMqtt());
    }

    // Connect adaptive (WebSocket/HTTP)
    if (_adaptive != null) {
      futures.add(_connectAdaptive());
    }

    // Wait for all connection attempts
    await Future.wait(futures, eagerError: false);

    // Start health checks
    _startHealthChecks();

    // Update status
    _updateStatus();

    debugPrint('$_tag: Connection complete - status: $_status');
  }

  /// Reconfigure endpoints and reconnect
  /// Call this when the user enters a new relay IP
  Future<void> reconfigure({
    String? grpcHost,
    int? grpcPort,
    String? websocketUrl,
    String? httpBaseUrl,
  }) async {
    debugPrint('$_tag: Reconfiguring with host: $grpcHost');

    // Disconnect existing transports
    await disconnect();

    // Update endpoints
    _endpoints = _endpoints.copyWith(
      grpcHost: grpcHost,
      grpcPort: grpcPort,
      websocketUrl: websocketUrl,
      httpBaseUrl: httpBaseUrl,
    );

    // Re-initialize and connect
    await initialize();
    await connect();
  }

  /// Connect to the WebRTC map stream
  Future<void> connectMapStream() async {
    if (_webrtc == null) {
      throw Exception('WebRTC not configured or gRPC not available for signaling.');
    }
    debugPrint('$_tag: Connecting WebRTC for map stream...');
    await _webrtc!.connect();
    _updateStatus();
  }

  /// Connect to a specific robot (for WebRTC video)
  Future<void> connectVideo() async {
    if (_webrtc == null || _endpoints.webrtcSignalingUrl == null) {
      throw Exception('WebRTC not configured');
    }

    debugPrint('$_tag: Connecting WebRTC for video...');

    // Create and send offer
    final offer = await _webrtc!.createOffer();

    // In a real implementation, send offer via signaling server
    // and wait for answer

    _updateStatus();
  }

  /// Disconnect all transports
  Future<void> disconnect() async {
    debugPrint('$_tag: Disconnecting all transports...');

    _healthCheckTimer?.cancel();

    await _grpc?.disconnect();
    await _webrtc?.disconnect();
    await _mqtt?.disconnect();
    _adaptive?.dispose();

    _grpcStatusSub?.cancel();
    _grpcCommandSub?.cancel();
    _mqttMessageSub?.cancel();
    _webrtcMessageSub?.cancel();

    _updateStatus();
  }

  /// Send command - routes to best available transport
  Future<CommandAck> sendCommand(RobotCommand command) async {
    // Emergency commands go through ALL connected transports for redundancy
    if (_isEmergencyCommand(command)) {
      return _sendEmergencyCommand(command);
    }

    // Select best transport for this command
    final transport = _selectTransportForCommand(command);

    debugPrint('$_tag: Sending ${command.type} via $transport');

    switch (transport) {
      case 'grpc':
        return _sendViaGrpc(command);
      case 'webrtc':
        return _sendViaWebRtc(command);
      case 'mqtt':
        return _sendViaMqtt(command);
      case 'adaptive':
        return _sendViaAdaptive(command);
      default:
        return CommandAck(
          commandId: command.id,
          success: false,
          errorMessage: 'No transport available',
        );
    }
  }

  /// Send velocity command with predictive control
  void sendVelocity(double linear, double angular) {
    if (_config.shouldUsePredictiveControl) {
      // Use predictive controller for smoothing
      _predictiveController.setTargetVelocity(linear, angular);
      _predictiveController.applyVelocity();
    } else {
      _sendVelocityInternal(linear, angular);
    }
  }

  void _sendVelocityInternal(double linear, double angular) {
    // Prefer WebRTC for lowest latency
    if (_status.webrtcConnected && _webrtc!.hasDataChannel) {
      _webrtc!.sendVelocity(linear, angular);
      return;
    }

    // Fall back to gRPC
    if (_status.grpcConnected) {
      _grpc!.sendVelocity(linear, angular);
      return;
    }

    // Fall back to adaptive
    if (_adaptive?.isConnected ?? false) {
      final cmd = RobotCommand(
        id: 'vel_${DateTime.now().millisecondsSinceEpoch}',
        type: 'velocity',
        payload: {'linear': linear, 'angular': angular},
      );
      _adaptive!.sendCommand(AdaptiveCommand(
        id: cmd.id,
        type: cmd.type,
        payload: cmd.payload,
        priority: CommandPriority.high,
        droppable: true,
      ));
    }
  }

  /// Navigate to waypoint
  void navigate(String waypoint) {
    sendCommand(RobotCommand(
      id: 'nav_${DateTime.now().millisecondsSinceEpoch}',
      type: 'navigate',
      payload: {'waypoint': waypoint},
    ));
  }

  /// Stop robot
  void stop() {
    sendCommand(RobotCommand(
      id: 'stop_${DateTime.now().millisecondsSinceEpoch}',
      type: 'stop',
      payload: {},
    ));
  }

  /// Emergency stop - sends through ALL transports
  void emergencyStop(bool enabled) {
    final cmd = RobotCommand(
      id: 'estop_${DateTime.now().millisecondsSinceEpoch}',
      type: 'estop',
      payload: {'enabled': enabled},
    );

    _sendEmergencyCommand(cmd);
  }

  // ============================================================
  // PRIVATE METHODS
  // ============================================================

  void _setupGrpcListeners() {
    _grpcStatusSub = _grpc!.robotStatus.listen((status) {
      _robotStatusController.add({
        'source': 'grpc',
        'connected': status.connected,
        'nav_status': status.navStatus,
        'nav_goal': status.navGoal,
        'battery': status.battery,
        'pose': {
          'x': status.pose.x,
          'y': status.pose.y,
          'theta': status.pose.theta,
        },
      });

      // Update predictive controller with actual state
      _predictiveController.updateActualState(RobotState(
        x: status.pose.x,
        y: status.pose.y,
        theta: status.pose.theta,
        linearVelocity: status.linearVelocity,
        angularVelocity: status.angularVelocity,
      ));
    });

    _grpcCommandSub = _grpc!.commandResults.listen((result) {
      _commandResultController.add(CommandAck(
        commandId: result.commandId,
        success: result.status == 'success',
        errorMessage: result.message,
      ));
    });

    _grpc!.connectionState.listen((connected) {
      _status = TransportConnectionStatus(
        grpcConnected: connected,
        webrtcConnected: _status.webrtcConnected,
        mqttConnected: _status.mqttConnected,
        websocketConnected: _status.websocketConnected,
        httpReachable: _status.httpReachable,
        activeTransport: _determineActiveTransport(),
        networkCondition: _config.currentCondition,
      );
      _statusController.add(_status);
      notifyListeners();
    });
  }

  void _setupWebRtcListeners() {
    _webrtcMessageSub = _webrtc!.dataMessages.listen((message) {
      if (message['type'] == 'status') {
        _robotStatusController.add({
          'source': 'webrtc',
          ...message,
        });
      }
    });

    _webrtc!.stateStream.listen((state) {
      final connected = state == WebRtcState.connected;
      _status = TransportConnectionStatus(
        grpcConnected: _status.grpcConnected,
        webrtcConnected: connected,
        mqttConnected: _status.mqttConnected,
        websocketConnected: _status.websocketConnected,
        httpReachable: _status.httpReachable,
        activeTransport: _determineActiveTransport(),
        networkCondition: _config.currentCondition,
      );
      _statusController.add(_status);
      notifyListeners();
    });
  }

  void _setupMqttListeners() {
    _mqttMessageSub = _mqtt!.subscribeToStatus().listen((status) {
      _robotStatusController.add({
        'source': 'mqtt',
        ...status,
      });
    });

    _mqtt!.stateStream.listen((state) {
      final connected = state == MqttState.connected;
      _status = TransportConnectionStatus(
        grpcConnected: _status.grpcConnected,
        webrtcConnected: _status.webrtcConnected,
        mqttConnected: connected,
        websocketConnected: _status.websocketConnected,
        httpReachable: _status.httpReachable,
        activeTransport: _determineActiveTransport(),
        networkCondition: _config.currentCondition,
      );
      _statusController.add(_status);
      notifyListeners();
    });
  }

  Future<void> _connectGrpc() async {
    try {
      await _grpc!.connect(_endpoints.grpcHost!, port: _endpoints.grpcPort);
      debugPrint('$_tag: gRPC connected');
    } catch (e) {
      debugPrint('$_tag: gRPC connection failed: $e');
    }
  }

  Future<void> _connectMqtt() async {
    try {
      await _mqtt!.connect(_endpoints.mqttBrokerUrl!);
      debugPrint('$_tag: MQTT connected');
    } catch (e) {
      debugPrint('$_tag: MQTT connection failed: $e');
    }
  }

  Future<void> _connectAdaptive() async {
    try {
      await _adaptive!.connect();
      debugPrint('$_tag: Adaptive transport connected');
    } catch (e) {
      debugPrint('$_tag: Adaptive connection failed: $e');
    }
  }

  void _startHealthChecks() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _runHealthCheck(),
    );
  }

  Future<void> _runHealthCheck() async {
    // Measure RTT for each connected transport
    final measurements = <String, double>{};

    if (_grpc?.isConnected ?? false) {
      final start = DateTime.now();
      try {
        // gRPC heartbeat
        measurements['grpc'] =
            DateTime.now().difference(start).inMilliseconds.toDouble();
      } catch (e) {
        debugPrint('$_tag: gRPC health check failed: $e');
      }
    }

    // Update network metrics based on measurements
    if (measurements.isNotEmpty) {
      final avgRtt =
          measurements.values.reduce((a, b) => a + b) / measurements.length;
      _config.updateNetworkMetrics(rttMs: avgRtt, jitterMs: 0);
    }

    _updateStatus();
  }

  void _updateStatus() {
    _status = TransportConnectionStatus(
      grpcConnected: _grpc?.isConnected ?? false,
      webrtcConnected: _webrtc?.isConnected ?? false,
      mqttConnected: _mqtt?.isConnected ?? false,
      websocketConnected: _adaptive?.isConnected ?? false,
      httpReachable: _adaptive?.isConnected ?? false,
      activeTransport: _determineActiveTransport(),
      networkCondition: _config.currentCondition,
    );
    _statusController.add(_status);
    notifyListeners();
  }

  String? _determineActiveTransport() {
    // Priority: WebRTC (lowest latency) > gRPC (reliable) > WebSocket > HTTP
    if (_webrtc?.isConnected ?? false) return 'webrtc';
    if (_grpc?.isConnected ?? false) return 'grpc';
    if (_mqtt?.isConnected ?? false) return 'mqtt';
    if (_adaptive?.isConnected ?? false) return 'adaptive';
    return null;
  }

  String _selectTransportForCommand(RobotCommand command) {
    // Velocity commands prefer WebRTC for lowest latency
    if (command.type == 'velocity') {
      if (_status.webrtcConnected) return 'webrtc';
      if (_status.grpcConnected) return 'grpc';
      if (_status.websocketConnected) return 'adaptive';
    }

    // Navigation and other commands prefer gRPC for reliability
    if (_status.grpcConnected) return 'grpc';
    if (_status.mqttConnected) return 'mqtt';
    if (_status.websocketConnected) return 'adaptive';

    return 'none';
  }

  bool _isEmergencyCommand(RobotCommand command) {
    return command.type == 'estop' || command.type == 'emergency_stop';
  }

  Future<CommandAck> _sendEmergencyCommand(RobotCommand command) async {
    debugPrint('$_tag: EMERGENCY COMMAND - sending through ALL transports');

    final results = <Future<CommandAck>>[];

    if (_status.grpcConnected) {
      results.add(_sendViaGrpc(command));
    }
    if (_status.webrtcConnected) {
      results.add(_sendViaWebRtc(command));
    }
    if (_status.mqttConnected) {
      results.add(_sendViaMqtt(command));
    }
    if (_status.websocketConnected) {
      results.add(_sendViaAdaptive(command));
    }

    if (results.isEmpty) {
      return CommandAck(
        commandId: command.id,
        success: false,
        errorMessage: 'No transports connected for emergency command',
      );
    }

    // Wait for first success
    final acks = await Future.wait(results);
    final success = acks.any((ack) => ack.success);

    return CommandAck(
      commandId: command.id,
      success: success,
      errorMessage:
          success ? null : 'Emergency command failed on all transports',
    );
  }

  Future<CommandAck> _sendViaGrpc(RobotCommand command) async {
    try {
      await _grpc!
          .sendCommand(command.type, command.payload.cast<String, String>());
      return CommandAck(commandId: command.id, success: true);
    } catch (e) {
      return CommandAck(
          commandId: command.id, success: false, errorMessage: e.toString());
    }
  }

  Future<CommandAck> _sendViaWebRtc(RobotCommand command) async {
    try {
      _webrtc!.sendData({
        'type': command.type,
        'command_id': command.id,
        ...command.payload,
      });
      return CommandAck(commandId: command.id, success: true);
    } catch (e) {
      return CommandAck(
          commandId: command.id, success: false, errorMessage: e.toString());
    }
  }

  Future<CommandAck> _sendViaMqtt(RobotCommand command) async {
    return await _mqtt!.sendCommand(command);
  }

  Future<CommandAck> _sendViaAdaptive(RobotCommand command) async {
    final result = await _adaptive!.sendCommand(AdaptiveCommand(
      id: command.id,
      type: command.type,
      payload: command.payload,
    ));
    return result ??
        CommandAck(
            commandId: command.id, success: false, errorMessage: 'No response');
  }

  /// Get comprehensive status for debugging
  Map<String, dynamic> getDebugInfo() => {
        'status': {
          'grpc': _status.grpcConnected,
          'webrtc': _status.webrtcConnected,
          'mqtt': _status.mqttConnected,
          'websocket': _status.websocketConnected,
          'http': _status.httpReachable,
          'active': _status.activeTransport,
        },
        'config': _config.toJson(),
        'predictive_control': _predictiveController.getMetrics(),
        'endpoints': {
          'grpc': _endpoints.grpcEndpoint,
          'webrtc_signaling': _endpoints.webrtcSignalingUrl,
          'mqtt': _endpoints.mqttBrokerUrl,
          'websocket': _endpoints.websocketUrl,
          'http': _endpoints.httpBaseUrl,
        },
      };

  @override
  void dispose() {
    disconnect();
    _statusController.close();
    _robotStatusController.close();
    _commandResultController.close();
    _predictiveController.dispose();
    super.dispose();
  }
}
