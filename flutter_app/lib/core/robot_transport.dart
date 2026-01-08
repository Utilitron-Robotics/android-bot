import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Transport type for robot communication
enum TransportType {
  websocket,  // Direct WebSocket (rosbridge) - for LAN/relay
  grpc,       // gRPC - for WAN via API Gateway
  http,       // HTTP REST - for simple commands via relay
}

/// Connection status
enum TransportStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

/// Robot command with tracking
class RobotCommand {
  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int maxRetries;
  final Duration timeout;

  int retryCount = 0;
  DateTime? sentAt;
  DateTime? ackedAt;
  DateTime? completedAt;
  String? errorMessage;

  RobotCommand({
    required this.id,
    required this.type,
    required this.payload,
    this.maxRetries = 3,
    this.timeout = const Duration(seconds: 10),
  }) : createdAt = DateTime.now();

  bool get canRetry => retryCount < maxRetries;

  Map<String, dynamic> toJson() => {
    'command_id': id,
    'type': type,
    'payload': payload,
    'max_retries': maxRetries,
    'timeout_ms': timeout.inMilliseconds,
    'retry_count': retryCount,
  };
}

/// Command acknowledgment from server
class CommandAck {
  final String commandId;
  final bool success;
  final String? errorMessage;
  final DateTime timestamp;

  CommandAck({
    required this.commandId,
    required this.success,
    this.errorMessage,
  }) : timestamp = DateTime.now();

  factory CommandAck.fromJson(Map<String, dynamic> json) => CommandAck(
    commandId: json['command_id'] as String? ?? '',
    success: json['success'] as bool? ?? false,
    errorMessage: json['error_message'] as String?,
  );
}

/// Abstract transport interface
/// Allows switching between WebSocket, gRPC, and HTTP
abstract class RobotTransport {
  TransportType get type;
  TransportStatus get status;
  Stream<TransportStatus> get statusStream;
  Stream<Map<String, dynamic>> get messages;
  bool get isConnected;
  bool get isStale;

  Future<void> connect(String endpoint);
  Future<void> disconnect();

  /// Send a command with acknowledgment tracking
  Future<CommandAck> sendCommand(RobotCommand command);

  /// Send raw message (for WebSocket compatibility)
  void sendRaw(Map<String, dynamic> message);

  /// Subscribe to a topic (WebSocket/gRPC streams)
  void subscribe(String topic, {String? messageType});

  /// Unsubscribe from a topic
  void unsubscribe(String topic);
}

/// gRPC transport for WAN communication via API Gateway/Lambda
class GrpcTransport implements RobotTransport {
  @override
  final TransportType type = TransportType.grpc;

  final String robotId;
  String? _endpoint;

  TransportStatus _status = TransportStatus.disconnected;
  final _statusController = StreamController<TransportStatus>.broadcast();
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();

  DateTime? _lastUpdate;
  Timer? _statusPollTimer;
  Timer? _staleCheckTimer;

  // Pending commands awaiting acknowledgment
  final Map<String, Completer<CommandAck>> _pendingCommands = {};

  GrpcTransport({required this.robotId});

  @override
  TransportStatus get status => _status;

  @override
  Stream<TransportStatus> get statusStream => _statusController.stream;

  @override
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  @override
  bool get isConnected => _status == TransportStatus.connected;

  @override
  bool get isStale => _lastUpdate != null &&
      DateTime.now().difference(_lastUpdate!) > const Duration(seconds: 5);

  void _setStatus(TransportStatus newStatus) {
    _status = newStatus;
    _statusController.add(newStatus);
  }

  @override
  Future<void> connect(String endpoint) async {
    _endpoint = endpoint;
    _setStatus(TransportStatus.connecting);

    try {
      // Test connection with a status request
      final response = await http.get(
        Uri.parse('$endpoint/fleet/status?robot_id=$robotId'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        _setStatus(TransportStatus.connected);
        _lastUpdate = DateTime.now();

        // Start polling for status updates
        _startStatusPolling();
        _startStaleCheck();

        debugPrint('GrpcTransport: Connected to $endpoint');
      } else {
        throw Exception('Failed to connect: ${response.statusCode}');
      }
    } catch (e) {
      _setStatus(TransportStatus.error);
      debugPrint('GrpcTransport: Connection failed: $e');
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _statusPollTimer?.cancel();
    _staleCheckTimer?.cancel();
    _setStatus(TransportStatus.disconnected);
    debugPrint('GrpcTransport: Disconnected');
  }

  @override
  Future<CommandAck> sendCommand(RobotCommand command) async {
    if (_endpoint == null) {
      return CommandAck(
        commandId: command.id,
        success: false,
        errorMessage: 'Not connected',
      );
    }

    command.sentAt = DateTime.now();

    // Create completer for async response
    final completer = Completer<CommandAck>();
    _pendingCommands[command.id] = completer;

    try {
      final response = await http.post(
        Uri.parse('$_endpoint/fleet/commands'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'robot_id': robotId,
          ...command.toJson(),
        }),
      ).timeout(command.timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final ack = CommandAck(
          commandId: command.id,
          success: data['success'] as bool? ?? true,
          errorMessage: data['error_message'] as String?,
        );
        command.ackedAt = DateTime.now();
        completer.complete(ack);
        return ack;
      } else {
        final ack = CommandAck(
          commandId: command.id,
          success: false,
          errorMessage: 'HTTP ${response.statusCode}: ${response.body}',
        );
        completer.complete(ack);
        return ack;
      }
    } catch (e) {
      final ack = CommandAck(
        commandId: command.id,
        success: false,
        errorMessage: e.toString(),
      );

      // Retry if possible
      if (command.canRetry) {
        command.retryCount++;
        debugPrint('GrpcTransport: Retrying command ${command.id} (${command.retryCount}/${command.maxRetries})');
        return sendCommand(command);
      }

      completer.complete(ack);
      return ack;
    } finally {
      _pendingCommands.remove(command.id);
    }
  }

  @override
  void sendRaw(Map<String, dynamic> message) {
    // Convert to command format
    final command = RobotCommand(
      id: 'raw_${DateTime.now().millisecondsSinceEpoch}',
      type: 'raw',
      payload: message,
      maxRetries: 0,
    );
    sendCommand(command);
  }

  @override
  void subscribe(String topic, {String? messageType}) {
    // gRPC uses polling, subscriptions start poll loops
    debugPrint('GrpcTransport: Subscribed to $topic (polling mode)');
  }

  @override
  void unsubscribe(String topic) {
    debugPrint('GrpcTransport: Unsubscribed from $topic');
  }

  void _startStatusPolling() {
    _statusPollTimer?.cancel();
    _statusPollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_endpoint == null || _status != TransportStatus.connected) return;

      try {
        final response = await http.get(
          Uri.parse('$_endpoint/fleet/status?robot_id=$robotId'),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          _lastUpdate = DateTime.now();

          // Emit as robot_status message
          _messageController.add({
            'topic': '/robot_status',
            'msg': data['status'] ?? data,
          });
        }
      } catch (e) {
        debugPrint('GrpcTransport: Status poll failed: $e');
      }
    });
  }

  void _startStaleCheck() {
    _staleCheckTimer?.cancel();
    _staleCheckTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isStale && _status == TransportStatus.connected) {
        _setStatus(TransportStatus.reconnecting);
        _attemptReconnect();
      }
    });
  }

  Future<void> _attemptReconnect() async {
    if (_endpoint == null) return;

    try {
      await connect(_endpoint!);
    } catch (e) {
      debugPrint('GrpcTransport: Reconnect failed: $e');
      // Will retry on next stale check
    }
  }

  void dispose() {
    _statusPollTimer?.cancel();
    _staleCheckTimer?.cancel();
    _statusController.close();
    _messageController.close();
  }
}

/// HTTP transport for simple REST commands via relay
class HttpTransport implements RobotTransport {
  @override
  final TransportType type = TransportType.http;

  String? _endpoint;
  TransportStatus _status = TransportStatus.disconnected;
  final _statusController = StreamController<TransportStatus>.broadcast();
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();

  DateTime? _lastUpdate;
  Timer? _statusPollTimer;

  @override
  TransportStatus get status => _status;

  @override
  Stream<TransportStatus> get statusStream => _statusController.stream;

  @override
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  @override
  bool get isConnected => _status == TransportStatus.connected;

  @override
  bool get isStale => _lastUpdate != null &&
      DateTime.now().difference(_lastUpdate!) > const Duration(seconds: 5);

  void _setStatus(TransportStatus newStatus) {
    _status = newStatus;
    _statusController.add(newStatus);
  }

  @override
  Future<void> connect(String endpoint) async {
    _endpoint = endpoint;
    _setStatus(TransportStatus.connecting);

    try {
      final response = await http.get(
        Uri.parse('$endpoint/status'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        _setStatus(TransportStatus.connected);
        _lastUpdate = DateTime.now();
        _startStatusPolling();
        debugPrint('HttpTransport: Connected to $endpoint');
      } else {
        throw Exception('Failed to connect: ${response.statusCode}');
      }
    } catch (e) {
      _setStatus(TransportStatus.error);
      debugPrint('HttpTransport: Connection failed: $e');
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _statusPollTimer?.cancel();
    _setStatus(TransportStatus.disconnected);
  }

  @override
  Future<CommandAck> sendCommand(RobotCommand command) async {
    if (_endpoint == null) {
      return CommandAck(commandId: command.id, success: false, errorMessage: 'Not connected');
    }

    try {
      String path;
      Map<String, dynamic> body;

      switch (command.type) {
        case 'navigate':
          path = '/navigate';
          body = {'poi': command.payload['waypoint']};
          break;
        case 'velocity':
          path = '/velocity';
          body = {
            'linear': command.payload['linear'],
            'angular': command.payload['angular'],
          };
          break;
        case 'stop':
          path = '/stop';
          body = {};
          break;
        case 'cancel':
          path = '/cancel';
          body = {};
          break;
        default:
          path = '/cmd';
          body = command.payload;
      }

      final response = await http.post(
        Uri.parse('$_endpoint$path'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(command.timeout);

      return CommandAck(
        commandId: command.id,
        success: response.statusCode == 200,
        errorMessage: response.statusCode != 200 ? response.body : null,
      );
    } catch (e) {
      if (command.canRetry) {
        command.retryCount++;
        return sendCommand(command);
      }
      return CommandAck(commandId: command.id, success: false, errorMessage: e.toString());
    }
  }

  @override
  void sendRaw(Map<String, dynamic> message) {
    final command = RobotCommand(
      id: 'raw_${DateTime.now().millisecondsSinceEpoch}',
      type: 'raw',
      payload: message,
      maxRetries: 0,
    );
    sendCommand(command);
  }

  @override
  void subscribe(String topic, {String? messageType}) {
    // HTTP uses polling
  }

  @override
  void unsubscribe(String topic) {}

  void _startStatusPolling() {
    _statusPollTimer?.cancel();
    _statusPollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_endpoint == null) return;

      try {
        final response = await http.get(
          Uri.parse('$_endpoint/status'),
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          _lastUpdate = DateTime.now();
          _messageController.add({
            'topic': '/robot_status',
            'msg': data,
          });
        }
      } catch (e) {
        debugPrint('HttpTransport: Poll failed: $e');
      }
    });
  }

  void dispose() {
    _statusPollTimer?.cancel();
    _statusController.close();
    _messageController.close();
  }
}

/// Transport manager - handles transport selection and failover
class TransportManager extends ChangeNotifier {
  RobotTransport? _primary;
  RobotTransport? _fallback;

  RobotTransport? get activeTransport => _primary?.isConnected == true
      ? _primary
      : (_fallback?.isConnected == true ? _fallback : null);

  bool get isConnected => activeTransport != null;

  /// Configure primary and fallback transports
  void configure({
    required RobotTransport primary,
    RobotTransport? fallback,
  }) {
    _primary = primary;
    _fallback = fallback;
    notifyListeners();
  }

  /// Connect using configured transports
  Future<void> connect({
    required String primaryEndpoint,
    String? fallbackEndpoint,
  }) async {
    // Try primary first
    if (_primary != null) {
      try {
        await _primary!.connect(primaryEndpoint);
        debugPrint('TransportManager: Primary transport connected');
        notifyListeners();
        return;
      } catch (e) {
        debugPrint('TransportManager: Primary failed, trying fallback: $e');
      }
    }

    // Try fallback
    if (_fallback != null && fallbackEndpoint != null) {
      try {
        await _fallback!.connect(fallbackEndpoint);
        debugPrint('TransportManager: Fallback transport connected');
        notifyListeners();
        return;
      } catch (e) {
        debugPrint('TransportManager: Fallback also failed: $e');
        rethrow;
      }
    }

    throw Exception('All transports failed to connect');
  }

  /// Send command through active transport
  Future<CommandAck?> sendCommand(RobotCommand command) async {
    final transport = activeTransport;
    if (transport == null) {
      return CommandAck(
        commandId: command.id,
        success: false,
        errorMessage: 'No active transport',
      );
    }
    return transport.sendCommand(command);
  }

  Future<void> disconnect() async {
    await _primary?.disconnect();
    await _fallback?.disconnect();
    notifyListeners();
  }
}
