import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'robot_transport.dart';
import 'rosbridge_client.dart';

/// Network quality metrics
class NetworkMetrics {
  final Duration latency;
  final double packetLoss;
  final double jitter;
  final int bandwidth; // bytes/sec
  final DateTime timestamp;

  NetworkMetrics({
    required this.latency,
    required this.packetLoss,
    required this.jitter,
    required this.bandwidth,
  }) : timestamp = DateTime.now();

  double get qualityScore {
    // Weighted scoring: lower is better
    final latencyScore = min(latency.inMilliseconds / 1000, 1.0); // 0-1 scale
    final lossScore = packetLoss; // Already 0-1
    final jitterScore = min(jitter / 100, 1.0); // Normalize to 0-1
    final bwScore = 1.0 - min(bandwidth / 1000000, 1.0); // Inverse, normalize to 1Mbps

    // Weighted average (latency most important for control)
    return (latencyScore * 0.4) + (lossScore * 0.3) + (jitterScore * 0.2) + (bwScore * 0.1);
  }

  bool get isAcceptable => qualityScore < 0.7;
  bool get isGood => qualityScore < 0.4;
  bool get isExcellent => qualityScore < 0.2;
}

/// Adaptive quality levels
enum QualityLevel {
  excellent,  // Full quality, all features
  good,       // Normal quality
  acceptable, // Reduced quality, disable non-essentials
  poor,       // Minimum viable, safety only
  critical,   // Emergency mode, stop commands only
}

/// Command priority for queue management
enum CommandPriority {
  emergency(0),  // E-stop, safety
  critical(1),   // Navigation cancel
  high(2),       // Navigation commands
  normal(3),     // Status queries
  low(4);        // Telemetry, logs

  final int value;
  const CommandPriority(this.value);
}

/// Enhanced command with priority and compression
class AdaptiveCommand extends RobotCommand {
  final CommandPriority priority;
  final bool compressible;
  final bool droppable; // Can be dropped if network is poor

  AdaptiveCommand({
    required super.id,
    required super.type,
    required super.payload,
    this.priority = CommandPriority.normal,
    this.compressible = true,
    this.droppable = false,
    super.maxRetries,
    super.timeout,
  });
}

/// The ULTIMATE adaptive transport system
/// This beast will work over carrier pigeons if needed
class AdaptiveTransport extends ChangeNotifier {
  static const String _tag = 'AdaptiveTransport';

  // Transports in priority order
  final List<RobotTransport> _transports = [];
  RobotTransport? _activeTransport;

  // Network quality monitoring
  final Map<RobotTransport, NetworkMetrics> _metrics = {};
  final Map<RobotTransport, Queue<Duration>> _latencyHistory = {};
  Timer? _metricsTimer;

  // Command queue with priority
  final PriorityQueue<AdaptiveCommand> _commandQueue = PriorityQueue(
    (a, b) => a.priority.value.compareTo(b.priority.value)
  );

  // Circuit breaker per transport
  final Map<RobotTransport, CircuitBreaker> _circuitBreakers = {};

  // Quality adaptation
  QualityLevel _currentQuality = QualityLevel.excellent;
  final _qualityController = StreamController<QualityLevel>.broadcast();

  // Connection state
  bool _isConnected = false;
  String? _lastError;

  // Stats for monitoring
  int _commandsSent = 0;
  int _commandsFailed = 0;
  int _transportSwitches = 0;

  QualityLevel get currentQuality => _currentQuality;
  Stream<QualityLevel> get qualityStream => _qualityController.stream;
  bool get isConnected => _isConnected;
  String? get lastError => _lastError;

  /// Initialize with multiple transport options
  void initialize({
    String? grpcEndpoint,
    String? websocketUrl,
    String? httpEndpoint,
  }) {
    _transports.clear();

    // Add transports in priority order
    // Note: GrpcRobotClient needs to implement RobotTransport interface
    // For now, we'll comment it out and use WebSocket/HTTP
    /*
    if (grpcEndpoint != null) {
      final grpc = GrpcRobotClient();
      _transports.add(grpc as RobotTransport);
      _circuitBreakers[grpc] = CircuitBreaker(
        failureThreshold: 3,
        resetTimeout: const Duration(seconds: 30),
      );
    }
    */

    if (websocketUrl != null) {
      final ws = WebSocketTransport(RosbridgeClient());
      _transports.add(ws);
      _circuitBreakers[ws] = CircuitBreaker(
        failureThreshold: 5,
        resetTimeout: const Duration(seconds: 20),
      );
    }

    if (httpEndpoint != null) {
      final http = HttpTransport();
      _transports.add(http);
      _circuitBreakers[http] = CircuitBreaker(
        failureThreshold: 10,
        resetTimeout: const Duration(seconds: 15),
      );
    }

    debugPrint('$_tag: Initialized with ${_transports.length} transports');
  }

  /// Connect with automatic failover
  Future<void> connect() async {
    for (final transport in _transports) {
      final breaker = _circuitBreakers[transport]!;

      if (!breaker.isOpen) {
        try {
          debugPrint('$_tag: Trying ${transport.type} transport...');

          String endpoint = _getEndpointForTransport(transport);
          await transport.connect(endpoint);

          _activeTransport = transport;
          _isConnected = true;
          _lastError = null;

          breaker.recordSuccess();
          _startMetricsMonitoring();
          _startCommandProcessor();

          debugPrint('$_tag: Connected via ${transport.type}!');
          notifyListeners();
          return;

        } catch (e) {
          breaker.recordFailure();
          debugPrint('$_tag: ${transport.type} failed: $e');
          _lastError = e.toString();
        }
      } else {
        debugPrint('$_tag: ${transport.type} circuit breaker OPEN, skipping');
      }
    }

    // All transports failed
    _isConnected = false;
    debugPrint('$_tag: All transports failed! Entering resilient retry mode...');
    _startResilientRetry();
  }

  /// Send command with adaptive quality
  Future<CommandAck?> sendCommand(AdaptiveCommand command) async {
    // Emergency commands bypass queue
    if (command.priority == CommandPriority.emergency) {
      return _sendImmediate(command);
    }

    // Check if we should drop this command
    if (command.droppable && _currentQuality == QualityLevel.critical) {
      debugPrint('$_tag: Dropping low-priority command in critical mode');
      return CommandAck(
        commandId: command.id,
        success: false,
        errorMessage: 'Dropped due to poor network',
      );
    }

    // Add to priority queue
    _commandQueue.add(command);

    // Process queue if not already running
    _processCommandQueue();

    // Return async completer
    final completer = Completer<CommandAck>();
    _commandCompleters[command.id] = completer;
    return completer.future;
  }

  final Map<String, Completer<CommandAck>> _commandCompleters = {};
  bool _processingQueue = false;

  Future<void> _processCommandQueue() async {
    if (_processingQueue || !_isConnected) return;
    _processingQueue = true;

    while (_commandQueue.isNotEmpty && _isConnected) {
      final command = _commandQueue.removeFirst();

      try {
        final ack = await _sendImmediate(command);
        _commandCompleters[command.id]?.complete(ack);
      } catch (e) {
        _commandCompleters[command.id]?.completeError(e);
      } finally {
        _commandCompleters.remove(command.id);
      }

      // Adaptive delay based on quality
      await Future.delayed(_getAdaptiveDelay());
    }

    _processingQueue = false;
  }

  Duration _getAdaptiveDelay() {
    switch (_currentQuality) {
      case QualityLevel.excellent:
        return Duration.zero;
      case QualityLevel.good:
        return const Duration(milliseconds: 10);
      case QualityLevel.acceptable:
        return const Duration(milliseconds: 50);
      case QualityLevel.poor:
        return const Duration(milliseconds: 100);
      case QualityLevel.critical:
        return const Duration(milliseconds: 200);
    }
  }

  Future<CommandAck> _sendImmediate(AdaptiveCommand command) async {
    final transport = _activeTransport;
    if (transport == null) {
      throw Exception('No active transport');
    }

    final stopwatch = Stopwatch()..start();

    try {
      // Compress if needed
      if (command.compressible && _currentQuality.index >= QualityLevel.acceptable.index) {
        command.payload['_compressed'] = true;
        // Implement actual compression here
      }

      final ack = await transport.sendCommand(command);

      stopwatch.stop();
      _recordLatency(transport, stopwatch.elapsed);
      _commandsSent++;

      return ack;

    } catch (e) {
      _commandsFailed++;
      _circuitBreakers[transport]?.recordFailure();

      // Try failover
      if (await _tryFailover()) {
        return _sendImmediate(command); // Retry with new transport
      }

      throw e;
    }
  }

  Future<bool> _tryFailover() async {
    debugPrint('$_tag: Attempting failover from ${_activeTransport?.type}...');
    _transportSwitches++;

    for (final transport in _transports) {
      if (transport == _activeTransport) continue;

      final breaker = _circuitBreakers[transport]!;
      if (!breaker.isOpen) {
        try {
          await transport.connect(_getEndpointForTransport(transport));
          _activeTransport = transport;
          debugPrint('$_tag: Failover successful to ${transport.type}!');
          return true;
        } catch (e) {
          breaker.recordFailure();
        }
      }
    }

    return false;
  }

  void _recordLatency(RobotTransport transport, Duration latency) {
    var history = _latencyHistory[transport] ??= Queue();
    history.add(latency);

    // Keep last 100 samples
    while (history.length > 100) {
      history.removeFirst();
    }

    // Update metrics
    _updateMetrics(transport);
  }

  void _updateMetrics(RobotTransport transport) {
    final history = _latencyHistory[transport];
    if (history == null || history.isEmpty) return;

    // Calculate metrics
    final latencies = history.toList();
    final avgLatency = latencies.reduce((a, b) => a + b) ~/ latencies.length;

    // Simple jitter calculation
    double jitter = 0;
    for (int i = 1; i < latencies.length; i++) {
      jitter += (latencies[i].inMilliseconds - latencies[i-1].inMilliseconds).abs();
    }
    jitter = jitter / max(latencies.length - 1, 1);

    _metrics[transport] = NetworkMetrics(
      latency: avgLatency,
      packetLoss: _commandsFailed / max(_commandsSent, 1),
      jitter: jitter,
      bandwidth: 1000000, // TODO: Actual bandwidth measurement
    );

    // Update quality level
    _updateQualityLevel();
  }

  void _updateQualityLevel() {
    final currentMetrics = _metrics[_activeTransport];
    if (currentMetrics == null) return;

    final oldQuality = _currentQuality;

    if (currentMetrics.isExcellent) {
      _currentQuality = QualityLevel.excellent;
    } else if (currentMetrics.isGood) {
      _currentQuality = QualityLevel.good;
    } else if (currentMetrics.isAcceptable) {
      _currentQuality = QualityLevel.acceptable;
    } else if (currentMetrics.qualityScore < 0.9) {
      _currentQuality = QualityLevel.poor;
    } else {
      _currentQuality = QualityLevel.critical;
    }

    if (oldQuality != _currentQuality) {
      debugPrint('$_tag: Quality changed: $oldQuality -> $_currentQuality');
      _qualityController.add(_currentQuality);
      notifyListeners();
    }
  }

  void _startMetricsMonitoring() {
    _metricsTimer?.cancel();
    _metricsTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _updateMetrics(_activeTransport!);

      // Log stats
      debugPrint('$_tag: Stats - Sent: $_commandsSent, Failed: $_commandsFailed, '
          'Switches: $_transportSwitches, Quality: $_currentQuality');
    });
  }

  void _startCommandProcessor() {
    Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!_processingQueue && _commandQueue.isNotEmpty) {
        _processCommandQueue();
      }
    });
  }

  void _startResilientRetry() {
    Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!_isConnected) {
        debugPrint('$_tag: Resilient retry attempt...');
        await connect();
      }
    });
  }

  String _getEndpointForTransport(RobotTransport transport) {
    // TODO: Get from configuration
    switch (transport.type) {
      case TransportType.grpc:
        return '192.168.88.37:50051';
      case TransportType.websocket:
        return 'ws://192.168.88.37:8766';
      case TransportType.http:
        return 'http://192.168.88.37:8765';
    }
  }

  Map<String, dynamic> getStats() => {
    'connected': _isConnected,
    'transport': _activeTransport?.type.toString(),
    'quality': _currentQuality.toString(),
    'commands_sent': _commandsSent,
    'commands_failed': _commandsFailed,
    'transport_switches': _transportSwitches,
    'success_rate': _commandsSent > 0
        ? ((_commandsSent - _commandsFailed) / _commandsSent * 100).toStringAsFixed(1) + '%'
        : 'N/A',
  };

  @override
  void dispose() {
    _metricsTimer?.cancel();
    _qualityController.close();
    for (final transport in _transports) {
      transport.disconnect();
    }
    super.dispose();
  }
}

/// Circuit breaker for transport failure management
class CircuitBreaker {
  final int failureThreshold;
  final Duration resetTimeout;

  int _failureCount = 0;
  DateTime? _lastFailure;
  bool _isOpen = false;

  CircuitBreaker({
    required this.failureThreshold,
    required this.resetTimeout,
  });

  bool get isOpen {
    // Check if we should reset
    if (_isOpen && _lastFailure != null) {
      if (DateTime.now().difference(_lastFailure!) > resetTimeout) {
        _reset();
      }
    }
    return _isOpen;
  }

  void recordSuccess() {
    _failureCount = 0;
    _isOpen = false;
  }

  void recordFailure() {
    _failureCount++;
    _lastFailure = DateTime.now();

    if (_failureCount >= failureThreshold) {
      _isOpen = true;
      debugPrint('CircuitBreaker: OPENED after $_failureCount failures');
    }
  }

  void _reset() {
    _failureCount = 0;
    _isOpen = false;
    debugPrint('CircuitBreaker: RESET after timeout');
  }
}

/// WebSocket transport wrapper
class WebSocketTransport implements RobotTransport {
  final RosbridgeClient _client;

  WebSocketTransport(this._client);

  @override
  TransportType get type => TransportType.websocket;

  @override
  TransportStatus get status => _client.state == WsConnectionState.connected
      ? TransportStatus.connected
      : TransportStatus.disconnected;

  @override
  Stream<TransportStatus> get statusStream => _client.connectionState.map((state) {
    switch (state) {
      case WsConnectionState.connecting:
        return TransportStatus.connecting;
      case WsConnectionState.connected:
        return TransportStatus.connected;
      case WsConnectionState.disconnected:
      case WsConnectionState.reconnecting:
        return TransportStatus.disconnected;
    }
  });

  @override
  Stream<Map<String, dynamic>> get messages => _client.messages;

  @override
  bool get isConnected => _client.isConnected;

  @override
  bool get isStale => false; // WebSocket has built-in keepalive

  @override
  Future<void> connect(String endpoint) => _client.connect(endpoint);

  @override
  Future<void> disconnect() async {
    _client.disconnect();
  }

  @override
  Future<CommandAck> sendCommand(RobotCommand command) async {
    switch (command.type) {
      case 'navigate':
        await _client.callService(
          service: '/poi',
          args: {'poi': command.payload['waypoint']},
        );
        break;
      case 'velocity':
        _client.publish(
          topic: '/cmd_vel_mux/input/teleop',
          msg: {
            'linear': {'x': command.payload['linear'] ?? 0, 'y': 0, 'z': 0},
            'angular': {'x': 0, 'y': 0, 'z': command.payload['angular'] ?? 0},
          },
        );
        break;
      default:
        _client.send(command.payload);
    }

    return CommandAck(
      commandId: command.id,
      success: true,
    );
  }

  @override
  void sendRaw(Map<String, dynamic> message) => _client.send(message);

  @override
  void subscribe(String topic, {String? messageType}) =>
      _client.subscribe(topic: topic, type: messageType ?? '');

  @override
  void unsubscribe(String topic) => _client.unsubscribe(topic: topic);
}

/// Priority queue implementation
class PriorityQueue<T> {
  final List<T> _items = [];
  final Comparator<T> _comparator;

  PriorityQueue(this._comparator);

  void add(T item) {
    _items.add(item);
    _items.sort(_comparator);
  }

  T removeFirst() => _items.removeAt(0);

  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;
  int get length => _items.length;
}