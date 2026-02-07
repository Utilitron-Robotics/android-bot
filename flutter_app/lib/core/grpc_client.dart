import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart';
import '../generated/robot_control.pbgrpc.dart';

/// gRPC client for WAN-ready robot communication
/// THIS is what replaces the fragile WebSocket connection!
///
/// Features:
/// - Binary protocol (15x smaller than JSON)
/// - Built-in keepalive (HTTP/2 PING frames)
/// - Automatic reconnect with exponential backoff
/// - Bidirectional streaming over one connection
/// Configuration for GrpcRobotClient timing parameters
class GrpcClientConfig {
  final Duration keepaliveInterval;
  final Duration keepaliveTimeout;
  final Duration connectionTimeout;
  final Duration idleTimeout;
  final Duration minReconnectDelay;
  final Duration maxReconnectDelay;
  final double backoffMultiplier;
  final int maxReconnectAttempts;
  final int defaultPort;

  const GrpcClientConfig({
    this.keepaliveInterval = const Duration(seconds: 10),
    this.keepaliveTimeout = const Duration(seconds: 5),
    this.connectionTimeout = const Duration(seconds: 10),
    this.idleTimeout = const Duration(minutes: 5),
    this.minReconnectDelay = const Duration(seconds: 1),
    this.maxReconnectDelay = const Duration(minutes: 1),
    this.backoffMultiplier = 1.5,
    this.maxReconnectAttempts = 10,
    this.defaultPort = 50051,
  });
}

class GrpcRobotClient extends ChangeNotifier {
  static const String _tag = 'GrpcRobotClient';

  // Configuration - injectable, not hardcoded
  final GrpcClientConfig config;

  GrpcRobotClient({GrpcClientConfig? config}) : config = config ?? const GrpcClientConfig();

  // State
  ClientChannel? _channel;
  RobotControlClient? _client;
  StreamController<ClientMessage>? _commandStream;
  StreamSubscription<ServerMessage>? _statusStream;

  bool _isConnected = false;
  bool _isReconnecting =
      false; // Track reconnection state separately from UI-visible connection state
  String _currentHost = '';
  late int _currentPort;
  String? _lastError;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  DateTime? _lastHeartbeatSent;
  double _lastRtt = 0;

  // Streams for UI updates
  final _robotStatusController = StreamController<RobotStatus>.broadcast();
  final _bufferStateController = StreamController<BufferState>.broadcast();
  final _commandResultController = StreamController<CommandResult>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();
  final _webRtcSignalController = StreamController<WebRTCSignal>.broadcast();

  Stream<RobotStatus> get robotStatus => _robotStatusController.stream;
  Stream<BufferState> get bufferState => _bufferStateController.stream;
  Stream<CommandResult> get commandResults => _commandResultController.stream;
  Stream<bool> get connectionState => _connectionStateController.stream;
  Stream<WebRTCSignal> get webrtcSignalStream => _webRtcSignalController.stream;

  bool get isConnected => _isConnected;
  String? get lastError => _lastError;
  String get connectionInfo => '$_currentHost:$_currentPort';
  double get lastRtt => _lastRtt;

  /// Connect to the gRPC server
  Future<void> connect(String host, {int? port}) async {
    port ??= config.defaultPort;
    if (_isConnected && _currentHost == host && _currentPort == port) {
      debugPrint('$_tag: Already connected to $host:$port');
      return;
    }

    await disconnect();

    _currentHost = host;
    _currentPort = port;
    _reconnectAttempts = 0;

    await _establishConnection();
  }

  /// Establish the actual gRPC connection
  Future<void> _establishConnection() async {
    try {
      debugPrint('$_tag: Connecting to $_currentHost:$_currentPort...');

      // Create channel with keepalive options for WAN stability
      _channel = ClientChannel(
        _currentHost,
        port: _currentPort,
        options: ChannelOptions(
          credentials: const ChannelCredentials.insecure(),
          connectionTimeout: config.connectionTimeout,
          idleTimeout: config.idleTimeout,
          // These are the KEY settings for WAN stability!
          keepAlive: ClientKeepAliveOptions(
            pingInterval: config.keepaliveInterval,
            timeout: config.keepaliveTimeout,
            permitWithoutCalls: true, // Keep alive even when idle
          ),
        ),
      );

      _client = RobotControlClient(_channel!);

      // Test connection with a simple unary call first
      try {
        debugPrint('$_tag: Testing connection with unary sendCommand...');
        final testCmd = Command()
          ..id = 'test_${DateTime.now().millisecondsSinceEpoch}'
          ..type = 'ping';
        await _client!.sendCommand(testCmd).timeout(const Duration(seconds: 5));
        debugPrint('$_tag: Unary call succeeded - connection verified!');
      } catch (e) {
        debugPrint('$_tag: Unary call failed: $e');
        // Check if this is a connection refused error - server isn't running
        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains('connection refused') ||
            errorStr.contains('unavailable') ||
            errorStr.contains('errno = 61')) {
          debugPrint('$_tag: Server unreachable - will retry');
          rethrow; // Re-throw to trigger reconnect logic
        }
        // For other errors (e.g., method not found), continue - server might be running but missing endpoint
      }

      // Create bidirectional stream
      _commandStream = StreamController<ClientMessage>();

      // Start the stream
      try {
        debugPrint('$_tag: Starting bidirectional stream...');
        final responseStream = _client!.controlStream(_commandStream!.stream);

        _statusStream = responseStream.listen(
          _handleServerMessage,
          onError: _handleStreamError,
          onDone: _handleStreamDone,
        );

        // Send heartbeat immediately — stream is ready after listen()
        _sendHeartbeatRequest();

        // Start periodic heartbeat
        _startHeartbeat();
        debugPrint('$_tag: Bidirectional stream started');
      } catch (e) {
        debugPrint('$_tag: Stream setup failed: $e');
      }

      _isConnected = true;
      _lastError = null;
      // Don't reset _reconnectAttempts here - only reset on successful heartbeat
      // This prevents infinite reconnect loops when connection succeeds but stream fails
      _connectionStateController.add(true);
      notifyListeners();

      debugPrint(
          '$_tag: ✅ Connected to $_currentHost:$_currentPort - WAN READY!');
    } catch (e) {
      _lastError = e.toString();
      debugPrint('$_tag: Connection failed: $e');
      _scheduleReconnect();
    }
  }

  /// Handle incoming server messages
  void _handleServerMessage(ServerMessage message) {
    switch (message.whichMessage()) {
      case ServerMessage_Message.heartbeat:
        _handleHeartbeat(message.heartbeat);
        break;
      case ServerMessage_Message.robotStatus:
        _robotStatusController.add(message.robotStatus);
        break;
      case ServerMessage_Message.bufferState:
        _bufferStateController.add(message.bufferState);
        break;
      case ServerMessage_Message.commandResult:
        _commandResultController.add(message.commandResult);
        break;
      case ServerMessage_Message.webrtcSignal:
        _webRtcSignalController.add(message.webrtcSignal);
        break;
      default:
        debugPrint('$_tag: Unknown message type');
    }
  }

  /// Handle heartbeat messages
  void _handleHeartbeat(Heartbeat heartbeat) {
    // Calculate RTT from heartbeat round-trip - only once per request
    // Clear _lastHeartbeatSent after calculating so pushed heartbeats don't
    // keep recalculating against the stale timestamp
    if (_lastHeartbeatSent != null) {
      _lastRtt = DateTime.now().difference(_lastHeartbeatSent!).inMilliseconds.toDouble();
      _lastHeartbeatSent = null; // Only measure RTT on first response
      notifyListeners(); // Notify UI of RTT update
    }

    // Update all states from heartbeat
    if (heartbeat.hasRobot()) {
      _robotStatusController.add(heartbeat.robot);
    }
    if (heartbeat.hasBuffer()) {
      _bufferStateController.add(heartbeat.buffer);
    }
    // Reset reconnect attempts on successful heartbeat
    _reconnectAttempts = 0;
  }

  /// Handle stream errors - soft reset without changing connection state
  void _handleStreamError(error) {
    debugPrint('$_tag: Stream error: $error');
    _lastError = error.toString();

    // Check if we've exceeded max reconnect attempts
    if (_reconnectAttempts >= config.maxReconnectAttempts) {
      debugPrint('$_tag: Max reconnect attempts reached, giving up');
      _disconnect();
      return;
    }

    // Don't change _isConnected state - just clean up streams and reconnect
    // This prevents UI from flashing between login and HUD
    _isReconnecting = true;
    _softReset();
    _scheduleReconnect();
  }

  /// Handle stream closure
  void _handleStreamDone() {
    debugPrint('$_tag: Stream closed');
    if (_isConnected && !_isReconnecting) {
      _isReconnecting = true;
      _softReset();
      _scheduleReconnect();
    }
  }

  /// Soft reset - clean up streams but keep connection state
  /// Used during reconnection to avoid UI flashing
  Future<void> _softReset() async {
    _heartbeatTimer?.cancel();
    await _statusStream?.cancel();
    await _commandStream?.close();
    await _channel?.shutdown();
    _statusStream = null;
    _commandStream = null;
    _channel = null;
    _client = null;
    // Note: deliberately NOT changing _isConnected or notifying listeners
  }

  /// Start periodic heartbeat
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(config.keepaliveInterval, (_) {
      if (_isConnected) {
        _sendHeartbeatRequest();
      }
    });
  }

  /// Send heartbeat request
  void _sendHeartbeatRequest() {
    _lastHeartbeatSent = DateTime.now();
    final message = ClientMessage()..heartbeatRequest = HeartbeatRequest();
    _sendMessage(message);
  }

  /// Schedule reconnection with exponential backoff
  void _scheduleReconnect() {
    if (_reconnectTimer?.isActive ?? false) return;

    _reconnectAttempts++;

    // Calculate delay with exponential backoff
    final delayMs = (config.minReconnectDelay.inMilliseconds *
            (config.backoffMultiplier * _reconnectAttempts))
        .round();
    final delay = Duration(
      milliseconds: delayMs.clamp(
        config.minReconnectDelay.inMilliseconds,
        config.maxReconnectDelay.inMilliseconds,
      ),
    );

    debugPrint(
        '$_tag: Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts)');

    _reconnectTimer = Timer(delay, () async {
      // Check if we should reconnect (either not connected or actively reconnecting)
      if (_currentHost.isNotEmpty && (_isReconnecting || !_isConnected)) {
        _isReconnecting = false; // Clear flag before attempting
        await _establishConnection();
      }
    });
  }

  /// Send a command to the robot
  Future<void> sendCommand(String type, Map<String, String> data) async {
    if (!_isConnected) {
      throw Exception('Not connected to gRPC server');
    }

    final command = Command()
      ..id = DateTime.now().millisecondsSinceEpoch.toString()
      ..type = type
      ..data.addAll(data);

    final message = ClientMessage()..command = command;
    _sendMessage(message);
  }

  /// Send velocity command
  void sendVelocity(double linear, double angular) {
    sendCommand('velocity', {
      'linear': linear.toString(),
      'angular': angular.toString(),
    });
  }

  /// Navigate to waypoint
  void navigate(String waypoint) {
    sendCommand('navigate', {'waypoint': waypoint});
  }

  /// Stop robot
  void stop() {
    sendCommand('stop', {});
  }

  /// Cancel navigation
  void cancelNavigation() {
    sendCommand('cancel', {});
  }

  /// Load commands into buffer
  void loadBufferCommands(List<BufferCommand> commands,
      {bool clearExisting = true}) {
    final load = LoadCommands()
      ..commands.addAll(commands)
      ..clearExisting = clearExisting;

    final control = BufferControl()..load = load;
    final message = ClientMessage()..bufferControl = control;
    _sendMessage(message);
  }

  /// Pause buffer execution
  void pauseBuffer() {
    final control = BufferControl()..pause = true;
    final message = ClientMessage()..bufferControl = control;
    _sendMessage(message);
  }

  /// Resume buffer execution
  void resumeBuffer() {
    final control = BufferControl()..resume = true;
    final message = ClientMessage()..bufferControl = control;
    _sendMessage(message);
  }

  /// Skip current buffer command
  void skipBufferCommand() {
    final control = BufferControl()..skip = true;
    final message = ClientMessage()..bufferControl = control;
    _sendMessage(message);
  }

  /// Clear buffer
  void clearBuffer() {
    final control = BufferControl()..clear_5 = true;
    final message = ClientMessage()..bufferControl = control;
    _sendMessage(message);
  }

  /// Request the WebRTC map stream from the server
  void requestMapStream() {
    final message = ClientMessage()..requestMapStream = RequestMapStream();
    _sendMessage(message);
  }

  /// Send a WebRTC signaling message (SDP or ICE candidate) to the server
  void sendWebRtcSignal(WebRTCSignal signal) {
    final message = ClientMessage()..webrtcSignal = signal;
    _sendMessage(message);
  }

  /// Send message to server
  void _sendMessage(ClientMessage message) {
    if (_commandStream?.isClosed ?? true) {
      debugPrint('$_tag: Cannot send - stream closed');
      return;
    }
    try {
      _commandStream!.add(message);
    } catch (e) {
      debugPrint('$_tag: Failed to send message: $e');
    }
  }

  /// Disconnect from server
  Future<void> disconnect() async {
    await _disconnect();
    _currentHost = '';
    _currentPort = config.defaultPort;
  }

  /// Internal disconnect
  Future<void> _disconnect() async {
    _isConnected = false;
    _isReconnecting = false;
    _connectionStateController.add(false);

    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();

    await _statusStream?.cancel();
    await _commandStream?.close();
    await _channel?.shutdown();

    _statusStream = null;
    _commandStream = null;
    _channel = null;
    _client = null;

    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    _robotStatusController.close();
    _bufferStateController.close();
    _commandResultController.close();
    _connectionStateController.close();
    _webRtcSignalController.close();
    super.dispose();
  }
}
