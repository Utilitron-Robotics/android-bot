import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Message direction for logging
enum MessageDirection { sent, received }

/// A logged rosbridge message with metadata
class RosbridgeMessage {
  final MessageDirection direction;
  final Map<String, dynamic> data;
  final DateTime timestamp;

  RosbridgeMessage({
    required this.direction,
    required this.data,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  String get op => data['op'] as String? ?? 'unknown';
  String? get topic => data['topic'] as String?;
  String? get service => data['service'] as String?;

  @override
  String toString() {
    final arrow = direction == MessageDirection.sent ? '→' : '←';
    return '$arrow $op ${topic ?? service ?? ''}';
  }
}

/// Low-level rosbridge WebSocket client
/// Handles connection, message sending/receiving, and protocol details
class RosbridgeClient {
  WebSocketChannel? _channel;
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _logController = StreamController<RosbridgeMessage>.broadcast();
  final Map<String, Completer<Map<String, dynamic>>> _pendingCalls = {};
  int _callId = 0;
  bool _isConnected = false;

  /// Stream of all incoming messages (for subscriptions)
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  /// Stream of all messages (sent & received) for logging/debugging
  Stream<RosbridgeMessage> get messageLog => _logController.stream;

  bool get isConnected => _isConnected;

  StreamSubscription? _streamSubscription;

  /// Connect to rosbridge server
  Future<void> connect(String url) async {
    // CRITICAL: Close any existing connection first!
    disconnect();

    try {
      final uri = Uri.parse(url);
      _channel = WebSocketChannel.connect(uri);

      // Listen for incoming messages
      _streamSubscription = _channel!.stream.listen(
        (data) {
          final msg = jsonDecode(data as String) as Map<String, dynamic>;
          _handleMessage(msg);
        },
        onError: (error) {
          _isConnected = false;
          _messageController.addError(error);
        },
        onDone: () {
          _isConnected = false;
        },
      );

      _isConnected = true;
    } catch (e) {
      _isConnected = false;
      rethrow;
    }
  }

  void _handleMessage(Map<String, dynamic> msg) {
    // Log received message
    _logController.add(RosbridgeMessage(
      direction: MessageDirection.received,
      data: msg,
    ));

    // Check if this is a service response
    final id = msg['id'] as String?;
    if (id != null && _pendingCalls.containsKey(id)) {
      _pendingCalls[id]!.complete(msg);
      _pendingCalls.remove(id);
    }

    // Broadcast all messages to subscribers
    _messageController.add(msg);
  }

  /// Disconnect from rosbridge
  void disconnect() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    // Cancel any pending service calls
    for (final completer in _pendingCalls.values) {
      if (!completer.isCompleted) {
        completer.completeError('Connection closed');
      }
    }
    _pendingCalls.clear();
  }

  /// Send raw message
  void send(Map<String, dynamic> message) {
    if (_channel != null) {
      // Log sent message
      _logController.add(RosbridgeMessage(
        direction: MessageDirection.sent,
        data: message,
      ));
      _channel!.sink.add(jsonEncode(message));
    }
  }

  /// Subscribe to a topic
  void subscribe({
    required String topic,
    required String type,
    String? id,
  }) {
    send({
      'op': 'subscribe',
      'topic': topic,
      'type': type,
      'id': id ?? 'sub_$topic',
    });
  }

  /// Unsubscribe from a topic
  void unsubscribe({required String topic, String? id}) {
    send({
      'op': 'unsubscribe',
      'topic': topic,
      'id': id ?? 'sub_$topic',
    });
  }

  /// Publish to a topic
  void publish({
    required String topic,
    required Map<String, dynamic> msg,
  }) {
    send({
      'op': 'publish',
      'topic': topic,
      'msg': msg,
    });
  }

  /// Call a service and wait for response
  Future<Map<String, dynamic>> callService({
    required String service,
    Map<String, dynamic>? args,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final id = 'call_${_callId++}';
    final completer = Completer<Map<String, dynamic>>();
    _pendingCalls[id] = completer;

    send({
      'op': 'call_service',
      'service': service,
      'id': id,
      if (args != null) 'args': args,
    });

    return completer.future.timeout(timeout, onTimeout: () {
      _pendingCalls.remove(id);
      throw TimeoutException('Service call to $service timed out');
    });
  }

  /// Advertise a topic for publishing
  void advertise({
    required String topic,
    required String type,
  }) {
    send({
      'op': 'advertise',
      'topic': topic,
      'type': type,
    });
  }

  /// Unadvertise a topic
  void unadvertise({required String topic}) {
    send({
      'op': 'unadvertise',
      'topic': topic,
    });
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _logController.close();
  }

  // === Tablet Commands (intercepted by relay, not forwarded to robot) ===

  /// Speak text on the tablet via TTS
  void tabletSpeak(String text) {
    send({'op': 'tablet_speak', 'text': text});
  }

  /// Display URL on tablet screen
  void tabletDisplay(String url) {
    send({'op': 'tablet_display', 'url': url});
  }

  /// Close tablet display
  void tabletCloseDisplay() {
    send({'op': 'tablet_close_display'});
  }

  /// Run a task on the tablet (SPEAK, DISPLAY, DELIVER)
  void tabletTask(String type, String data, int waitSeconds) {
    send({
      'op': 'tablet_task',
      'type': type,
      'data': data,
      'wait_seconds': waitSeconds,
    });
  }

  /// Cancel current tablet task
  void tabletCancelTask() {
    send({'op': 'tablet_cancel'});
  }
}
