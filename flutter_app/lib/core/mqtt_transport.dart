/// MQTT Transport for Event-Driven Robot Communication
///
/// MQTT excels at:
/// - Pub/sub patterns (multiple subscribers to robot events)
/// - Low overhead keep-alive
/// - QoS levels for guaranteed delivery
/// - Works well through firewalls/NAT
/// - Excellent for fleet management (many robots, one broker)

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'robot_transport.dart';
import 'transport_config.dart';

/// MQTT QoS levels
enum MqttQos {
  atMostOnce(0),   // Fire and forget
  atLeastOnce(1),  // Guaranteed delivery, may duplicate
  exactlyOnce(2);  // Guaranteed exactly once

  final int value;
  const MqttQos(this.value);
}

/// MQTT connection state
enum MqttState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

/// MQTT message
class MqttMessage {
  final String topic;
  final Map<String, dynamic> payload;
  final MqttQos qos;
  final bool retain;
  final DateTime timestamp;

  MqttMessage({
    required this.topic,
    required this.payload,
    this.qos = MqttQos.atMostOnce,
    this.retain = false,
  }) : timestamp = DateTime.now();

  factory MqttMessage.fromRaw(String topic, String payloadJson) {
    return MqttMessage(
      topic: topic,
      payload: jsonDecode(payloadJson) as Map<String, dynamic>,
    );
  }

  String get payloadJson => jsonEncode(payload);
}

/// MQTT-based robot transport
/// Perfect for fleet management and event-driven updates
class MqttTransport implements RobotTransport {
  static const String _tag = 'MqttTransport';

  final TransportConfig _config;
  final String _robotId;
  final String _clientId;

  // Connection state
  MqttState _state = MqttState.disconnected;
  String? _brokerUrl;
  Timer? _reconnectTimer;
  Timer? _keepaliveTimer;

  // Topics
  late final String _commandTopic;
  late final String _statusTopic;
  late final String _eventTopic;
  late final String _telemetryTopic;

  // Subscriptions
  final Set<String> _subscriptions = {};
  final Map<String, StreamController<MqttMessage>> _topicStreams = {};

  // Streams
  final _stateController = StreamController<MqttState>.broadcast();
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _statusController = StreamController<TransportStatus>.broadcast();

  // Pending messages for QoS 1/2
  final Map<int, Completer<void>> _pendingAcks = {};
  int _messageId = 0;

  MqttTransport({
    required String robotId,
    String? clientId,
    TransportConfig? config,
  }) : _robotId = robotId,
       _clientId = clientId ?? 'flutter_${DateTime.now().millisecondsSinceEpoch}',
       _config = config ?? TransportConfig.instance {
    // Setup topic patterns
    _commandTopic = 'robot/$_robotId/command';
    _statusTopic = 'robot/$_robotId/status';
    _eventTopic = 'robot/$_robotId/event';
    _telemetryTopic = 'robot/$_robotId/telemetry';
  }

  // RobotTransport interface
  @override
  TransportType get type => TransportType.http; // Using http as placeholder until MQTT type added

  @override
  TransportStatus get status {
    switch (_state) {
      case MqttState.connected:
        return TransportStatus.connected;
      case MqttState.connecting:
      case MqttState.reconnecting:
        return TransportStatus.connecting;
      case MqttState.disconnected:
        return TransportStatus.disconnected;
    }
  }

  @override
  Stream<TransportStatus> get statusStream => _statusController.stream;

  @override
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  @override
  bool get isConnected => _state == MqttState.connected;

  @override
  bool get isStale => false; // MQTT has built-in keepalive

  // Getters
  MqttState get mqttState => _state;
  Stream<MqttState> get stateStream => _stateController.stream;
  String get robotId => _robotId;

  @override
  Future<void> connect(String brokerUrl) async {
    _brokerUrl = brokerUrl;
    _setState(MqttState.connecting);

    try {
      debugPrint('$_tag: Connecting to $brokerUrl...');

      // In real implementation, use mqtt_client package
      // For now, simulate connection
      await _simulateConnection(brokerUrl);

      _setState(MqttState.connected);
      _startKeepalive();

      // Subscribe to robot status by default
      subscribe(_statusTopic);
      subscribe(_eventTopic);

      debugPrint('$_tag: Connected to broker');

    } catch (e) {
      debugPrint('$_tag: Connection failed: $e');
      _setState(MqttState.disconnected);
      _scheduleReconnect();
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _keepaliveTimer?.cancel();

    // Unsubscribe from all topics
    for (final topic in _subscriptions.toList()) {
      unsubscribe(topic);
    }

    _setState(MqttState.disconnected);
    debugPrint('$_tag: Disconnected');
  }

  @override
  Future<CommandAck> sendCommand(RobotCommand command) async {
    if (!isConnected) {
      return CommandAck(
        commandId: command.id,
        success: false,
        errorMessage: 'Not connected to MQTT broker',
      );
    }

    try {
      final message = MqttMessage(
        topic: _commandTopic,
        payload: {
          'command_id': command.id,
          'type': command.type,
          ...command.payload,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        },
        qos: _getQosForCommand(command),
      );

      await publish(message);

      return CommandAck(
        commandId: command.id,
        success: true,
      );
    } catch (e) {
      return CommandAck(
        commandId: command.id,
        success: false,
        errorMessage: e.toString(),
      );
    }
  }

  @override
  void sendRaw(Map<String, dynamic> message) {
    final topic = message['topic'] as String? ?? _commandTopic;
    publish(MqttMessage(
      topic: topic,
      payload: message,
    ));
  }

  @override
  void subscribe(String topic, {String? messageType}) {
    if (_subscriptions.contains(topic)) return;

    _subscriptions.add(topic);
    _topicStreams[topic] = StreamController<MqttMessage>.broadcast();

    debugPrint('$_tag: Subscribed to $topic');

    // In real implementation, send SUBSCRIBE packet
  }

  @override
  void unsubscribe(String topic) {
    if (!_subscriptions.contains(topic)) return;

    _subscriptions.remove(topic);
    _topicStreams[topic]?.close();
    _topicStreams.remove(topic);

    debugPrint('$_tag: Unsubscribed from $topic');

    // In real implementation, send UNSUBSCRIBE packet
  }

  /// Publish a message
  Future<void> publish(MqttMessage message) async {
    if (!isConnected) {
      throw Exception('Not connected');
    }

    debugPrint('$_tag: Publishing to ${message.topic}');

    // Handle QoS
    if (message.qos == MqttQos.atLeastOnce || message.qos == MqttQos.exactlyOnce) {
      final msgId = ++_messageId;
      final completer = Completer<void>();
      _pendingAcks[msgId] = completer;

      // In real implementation, send PUBLISH packet with message ID
      // Wait for PUBACK/PUBREC

      // For now, complete immediately
      completer.complete();
      _pendingAcks.remove(msgId);
    }

    // In real implementation, send PUBLISH packet
  }

  /// Get stream for a specific topic
  Stream<MqttMessage> topicStream(String topic) {
    if (!_subscriptions.contains(topic)) {
      subscribe(topic);
    }
    return _topicStreams[topic]!.stream;
  }

  // MQTT-specific convenience methods

  /// Publish robot velocity
  void publishVelocity(double linear, double angular) {
    publish(MqttMessage(
      topic: '$_commandTopic/velocity',
      payload: {
        'linear': linear,
        'angular': angular,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      qos: MqttQos.atMostOnce, // Low latency over reliability for velocity
    ));
  }

  /// Publish navigation command
  void publishNavigate(String waypoint) {
    publish(MqttMessage(
      topic: '$_commandTopic/navigate',
      payload: {
        'waypoint': waypoint,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      qos: MqttQos.atLeastOnce, // Ensure navigation commands arrive
    ));
  }

  /// Publish emergency stop
  void publishEmergencyStop(bool enabled) {
    publish(MqttMessage(
      topic: '$_commandTopic/estop',
      payload: {
        'enabled': enabled,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      },
      qos: MqttQos.exactlyOnce, // Critical - must arrive exactly once
      retain: true, // Retain so new subscribers know the state
    ));
  }

  /// Subscribe to robot status updates
  Stream<Map<String, dynamic>> subscribeToStatus() {
    subscribe(_statusTopic);
    return topicStream(_statusTopic).map((msg) => msg.payload);
  }

  /// Subscribe to robot events
  Stream<Map<String, dynamic>> subscribeToEvents() {
    subscribe(_eventTopic);
    return topicStream(_eventTopic).map((msg) => msg.payload);
  }

  /// Subscribe to telemetry data
  Stream<Map<String, dynamic>> subscribeToTelemetry() {
    subscribe(_telemetryTopic);
    return topicStream(_telemetryTopic).map((msg) => msg.payload);
  }

  // Private methods

  void _setState(MqttState state) {
    _state = state;
    _stateController.add(state);

    // Map to TransportStatus
    TransportStatus transportStatus;
    switch (state) {
      case MqttState.connected:
        transportStatus = TransportStatus.connected;
      case MqttState.connecting:
      case MqttState.reconnecting:
        transportStatus = TransportStatus.connecting;
      case MqttState.disconnected:
        transportStatus = TransportStatus.disconnected;
    }
    _statusController.add(transportStatus);
  }

  Future<void> _simulateConnection(String brokerUrl) async {
    // Simulate connection delay
    await Future.delayed(const Duration(milliseconds: 100));

    // Simulate potential failure
    if (brokerUrl.isEmpty) {
      throw Exception('Invalid broker URL');
    }
  }

  void _startKeepalive() {
    _keepaliveTimer?.cancel();
    _keepaliveTimer = Timer.periodic(_config.mqttKeepalive, (_) {
      if (isConnected) {
        _sendPing();
      }
    });
  }

  void _sendPing() {
    // In real implementation, send PINGREQ packet
    debugPrint('$_tag: Sending PING');
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_config.mqttReconnectDelay, () async {
      if (_state == MqttState.disconnected && _brokerUrl != null) {
        debugPrint('$_tag: Attempting reconnect...');
        _setState(MqttState.reconnecting);
        try {
          await connect(_brokerUrl!);
        } catch (e) {
          debugPrint('$_tag: Reconnect failed: $e');
          _scheduleReconnect();
        }
      }
    });
  }

  void _handleIncomingMessage(String topic, String payloadJson) {
    try {
      final message = MqttMessage.fromRaw(topic, payloadJson);

      // Emit to topic-specific stream
      if (_topicStreams.containsKey(topic)) {
        _topicStreams[topic]!.add(message);
      }

      // Also emit to general message stream (for RobotTransport interface)
      _messageController.add({
        'topic': topic,
        'msg': message.payload,
      });
    } catch (e) {
      debugPrint('$_tag: Failed to parse message: $e');
    }
  }

  MqttQos _getQosForCommand(RobotCommand command) {
    // Emergency commands need guaranteed delivery
    if (command.type == 'estop' || command.type == 'stop') {
      return MqttQos.exactlyOnce;
    }
    // Navigation needs at-least-once
    if (command.type == 'navigate') {
      return MqttQos.atLeastOnce;
    }
    // Velocity commands are fire-and-forget (low latency)
    if (command.type == 'velocity') {
      return MqttQos.atMostOnce;
    }
    // Default
    return MqttQos.atLeastOnce;
  }

  void dispose() {
    disconnect();
    _stateController.close();
    _messageController.close();
    _statusController.close();
    for (final controller in _topicStreams.values) {
      controller.close();
    }
  }
}

/// MQTT Fleet Manager - manage multiple robots via single broker
class MqttFleetManager {
  static const String _tag = 'MqttFleetManager';

  final String brokerUrl;
  final Map<String, MqttTransport> _robots = {};
  MqttState _state = MqttState.disconnected;

  // Fleet-wide topics
  static const String fleetStatusTopic = 'fleet/status';
  static const String fleetCommandTopic = 'fleet/command';
  static const String fleetAlertTopic = 'fleet/alert';

  final _fleetStatusController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get fleetStatus => _fleetStatusController.stream;

  MqttFleetManager({required this.brokerUrl});

  bool get isConnected => _state == MqttState.connected;
  List<String> get connectedRobots => _robots.keys.toList();

  /// Connect a robot to the fleet
  Future<MqttTransport> connectRobot(String robotId) async {
    if (_robots.containsKey(robotId)) {
      return _robots[robotId]!;
    }

    final transport = MqttTransport(robotId: robotId);
    await transport.connect(brokerUrl);

    _robots[robotId] = transport;
    debugPrint('$_tag: Robot $robotId joined fleet');

    return transport;
  }

  /// Disconnect a robot from the fleet
  Future<void> disconnectRobot(String robotId) async {
    final transport = _robots.remove(robotId);
    if (transport != null) {
      await transport.disconnect();
      debugPrint('$_tag: Robot $robotId left fleet');
    }
  }

  /// Send command to all robots
  void broadcastCommand(RobotCommand command) {
    for (final transport in _robots.values) {
      transport.sendCommand(command);
    }
  }

  /// Send command to specific robot
  Future<CommandAck> sendCommandToRobot(String robotId, RobotCommand command) async {
    final transport = _robots[robotId];
    if (transport == null) {
      return CommandAck(
        commandId: command.id,
        success: false,
        errorMessage: 'Robot $robotId not connected',
      );
    }
    return transport.sendCommand(command);
  }

  /// Emergency stop all robots
  void emergencyStopAll() {
    for (final transport in _robots.values) {
      transport.publishEmergencyStop(true);
    }
  }

  /// Get fleet status
  Map<String, Map<String, dynamic>> getFleetStatus() {
    final status = <String, Map<String, dynamic>>{};
    for (final entry in _robots.entries) {
      status[entry.key] = {
        'connected': entry.value.isConnected,
        'state': entry.value.mqttState.name,
      };
    }
    return status;
  }

  void dispose() {
    for (final transport in _robots.values) {
      transport.dispose();
    }
    _robots.clear();
    _fleetStatusController.close();
  }
}
