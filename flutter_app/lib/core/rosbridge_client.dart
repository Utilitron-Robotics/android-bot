import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Message direction for logging
enum MessageDirection { sent, received }

/// Connection state for the WebSocket
enum WsConnectionState { disconnected, connecting, connected, reconnecting }

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
  StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();
  StreamController<RosbridgeMessage> _logController =
      StreamController<RosbridgeMessage>.broadcast();
  final Map<String, Completer<Map<String, dynamic>>> _pendingCalls = {};
  int _callId = 0;
  bool _isConnected = false;

  // Subscription tracking to prevent duplicate subscribes
  final Set<String> _subscribedTopics = {};
  final Set<String> _advertisedTopics = {};

  // Keepalive and reconnect
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  DateTime? _lastMessageTime;
  String? _lastUrl;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  static const Duration _pingInterval = Duration(seconds: 15);
  static const Duration _connectionTimeout = Duration(seconds: 30);

  // Connection state
  WsConnectionState _connectionState = WsConnectionState.disconnected;
  final StreamController<WsConnectionState> _stateController =
      StreamController<WsConnectionState>.broadcast();

  /// Stream of connection state changes
  Stream<WsConnectionState> get connectionState => _stateController.stream;

  /// Current connection state
  WsConnectionState get state => _connectionState;

  /// Stream of all incoming messages (for subscriptions)
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  /// Stream of all messages (sent & received) for logging/debugging
  Stream<RosbridgeMessage> get messageLog => _logController.stream;

  bool get isConnected => _isConnected;

  StreamSubscription? _streamSubscription;

  /// Callback when connection is lost (for triggering UI updates)
  VoidCallback? onDisconnect;

  /// Callback when reconnected (for re-subscribing to topics)
  VoidCallback? onReconnect;

  void _setState(WsConnectionState state) {
    if (_connectionState != state) {
      _connectionState = state;
      _stateController.add(state);
      debugPrint('RosbridgeClient: State changed to $state');
    }
  }

  /// Connect to rosbridge server
  Future<void> connect(String url) async {
    // CRITICAL: Close any existing connection first!
    _stopTimers();
    _closeConnection();

    _lastUrl = url;
    _setState(WsConnectionState.connecting);

    try {
      final uri = Uri.parse(url);
      _channel = WebSocketChannel.connect(uri);

      // Listen for incoming messages
      _streamSubscription = _channel!.stream.listen(
        (data) {
          _lastMessageTime = DateTime.now();
          final msg = jsonDecode(data as String) as Map<String, dynamic>;
          _handleMessage(msg);
        },
        onError: (error) {
          debugPrint('RosbridgeClient: Stream error: $error');
          _handleDisconnect();
        },
        onDone: () {
          debugPrint('RosbridgeClient: Stream done (connection closed)');
          _handleDisconnect();
        },
        cancelOnError: false,
      );

      _isConnected = true;
      _reconnectAttempts = 0;
      _lastMessageTime = DateTime.now();
      _setState(WsConnectionState.connected);
      _startPingTimer();
    } catch (e) {
      debugPrint('RosbridgeClient: Connect error: $e');
      _isConnected = false;
      _setState(WsConnectionState.disconnected);
      rethrow;
    }
  }

  /// Handle disconnection - trigger reconnect if we have a URL
  void _handleDisconnect() {
    if (!_isConnected && _connectionState == WsConnectionState.disconnected) {
      return; // Already handled
    }

    _isConnected = false;
    _stopTimers();
    _closeConnection();

    // Clear subscription tracking (server forgets on disconnect)
    _subscribedTopics.clear();
    _advertisedTopics.clear();

    // Attempt to reconnect if we have a URL
    if (_lastUrl != null && _reconnectAttempts < _maxReconnectAttempts) {
      _scheduleReconnect();
    } else {
      // Only notify after all retries exhausted
      onDisconnect?.call();
      _setState(WsConnectionState.disconnected);
    }
  }

  /// Schedule a reconnect with exponential backoff
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();

    // Only show "reconnecting" state after 2 failed attempts (silent recovery first)
    // Call onDisconnect only ONCE when we first exceed the silent threshold
    if (_reconnectAttempts == 2) {
      _setState(WsConnectionState.reconnecting);
      onDisconnect?.call(); // Notify UI only once
    }

    // Exponential backoff: 1s, 2s, 4s, 8s, 16s, max 30s
    final delay = Duration(
      seconds: (1 << _reconnectAttempts).clamp(1, 30),
    );
    _reconnectAttempts++;

    debugPrint('RosbridgeClient: Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts/$_maxReconnectAttempts)');

    _reconnectTimer = Timer(delay, () async {
      if (_lastUrl != null) {
        try {
          await connect(_lastUrl!);
          onReconnect?.call();
        } catch (e) {
          debugPrint('RosbridgeClient: Reconnect failed: $e');
          // Will trigger another reconnect via _handleDisconnect
        }
      }
    });
  }

  /// Start the ping timer to detect dead connections
  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      _checkConnection();
    });
  }

  /// Check if connection is still alive
  void _checkConnection() {
    if (!_isConnected || _channel == null) {
      return;
    }

    // Check if we've received any message recently
    final now = DateTime.now();
    if (_lastMessageTime != null &&
        now.difference(_lastMessageTime!) > _connectionTimeout) {
      debugPrint('RosbridgeClient: Connection timeout - no messages for ${_connectionTimeout.inSeconds}s');
      _handleDisconnect();
      return;
    }

    // Send a ping (rosbridge doesn't have ping, but we can send an empty subscribe)
    // This will fail if the connection is dead
    try {
      // Use a harmless operation that won't affect state
      send({'op': 'ping'}); // Rosbridge ignores unknown ops
    } catch (e) {
      debugPrint('RosbridgeClient: Ping failed: $e');
      _handleDisconnect();
    }
  }

  void _stopTimers() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _closeConnection() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
    try {
      _channel?.sink.close();
    } catch (e) {
      // Ignore close errors
    }
    _channel = null;
  }

  void _handleMessage(Map<String, dynamic> msg) {
    // Log received message
    _logController.add(RosbridgeMessage(
      direction: MessageDirection.received,
      data: msg,
    ));

    // Handle pong response (keep-alive acknowledgment)
    final op = msg['op'] as String?;
    if (op == 'pong') {
      // Connection is alive - lastMessageTime already updated by stream listener
      return;
    }

    // Check if this is a service response
    final id = msg['id'] as String?;
    if (id != null && _pendingCalls.containsKey(id)) {
      _pendingCalls[id]!.complete(msg);
      _pendingCalls.remove(id);
    }

    // Broadcast all messages to subscribers
    _messageController.add(msg);
  }

  /// Disconnect from rosbridge (manual disconnect - no auto-reconnect)
  void disconnect() {
    _stopTimers();
    _closeConnection();
    _isConnected = false;
    _lastUrl = null; // Clear URL to prevent auto-reconnect
    _reconnectAttempts = 0;

    // Clear subscription tracking (server forgets on disconnect)
    _subscribedTopics.clear();
    _advertisedTopics.clear();

    // Cancel any pending service calls
    for (final completer in _pendingCalls.values) {
      if (!completer.isCompleted) {
        completer.completeError('Connection closed');
      }
    }
    _pendingCalls.clear();

    // CRITICAL: Close and recreate stream controllers to clear old listeners
    // This prevents stale callbacks from firing on reconnect
    _messageController.close();
    _logController.close();
    _messageController = StreamController<Map<String, dynamic>>.broadcast();
    _logController = StreamController<RosbridgeMessage>.broadcast();

    _setState(WsConnectionState.disconnected);
  }

  /// Force a reconnect now (reset backoff)
  Future<void> reconnect() async {
    if (_lastUrl == null) {
      debugPrint('RosbridgeClient: Cannot reconnect - no URL');
      return;
    }
    _reconnectAttempts = 0;
    final url = _lastUrl!;
    disconnect();
    _lastUrl = url; // Restore URL after disconnect clears it
    await connect(url);
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

  /// Subscribe to a topic (skips if already subscribed)
  void subscribe({
    required String topic,
    required String type,
    String? id,
    bool force = false,
  }) {
    // Skip if already subscribed (unless forced)
    if (!force && _subscribedTopics.contains(topic)) {
      debugPrint('RosbridgeClient: Already subscribed to $topic, skipping');
      return;
    }
    _subscribedTopics.add(topic);
    send({
      'op': 'subscribe',
      'topic': topic,
      'type': type,
      'id': id ?? 'sub_$topic',
    });
  }

  /// Unsubscribe from a topic
  void unsubscribe({required String topic, String? id}) {
    _subscribedTopics.remove(topic);
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

  /// Advertise a topic for publishing (skips if already advertised)
  void advertise({
    required String topic,
    required String type,
  }) {
    // Skip if already advertised
    if (_advertisedTopics.contains(topic)) {
      return;
    }
    _advertisedTopics.add(topic);
    send({
      'op': 'advertise',
      'topic': topic,
      'type': type,
    });
  }

  /// Unadvertise a topic
  void unadvertise({required String topic}) {
    _advertisedTopics.remove(topic);
    send({
      'op': 'unadvertise',
      'topic': topic,
    });
  }

  void dispose() {
    _stopTimers();
    disconnect();
    _messageController.close();
    _logController.close();
    _stateController.close();
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

  /// Play an alert sound on the tablet (beep, horn, alarm)
  void tabletPlaySound(String soundType) {
    send({'op': 'tablet_play_sound', 'sound': soundType});
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

  /// Request map refresh from tablet
  /// This triggers the relay to re-subscribe to /map and get fresh data
  void tabletRefreshMap() {
    debugPrint('RosbridgeClient: Requesting map refresh');
    send({'op': 'tablet_refresh_map'});
  }
}
