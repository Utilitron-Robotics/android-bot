/// Transport Configuration - NO MORE HARDCODED TIMES!
///
/// All timing values are configurable and adaptive based on network conditions.
/// This replaces scattered hardcoded values throughout the codebase.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Network condition classification
enum NetworkCondition {
  excellent,  // RTT < 50ms, jitter < 10ms
  good,       // RTT < 150ms, jitter < 30ms
  fair,       // RTT < 300ms, jitter < 50ms
  poor,       // RTT < 500ms, jitter < 100ms
  critical,   // RTT >= 500ms or high packet loss
}

/// Transport type for adaptive selection
enum AdaptiveTransportType {
  grpc,       // Primary WAN transport - binary, bidirectional streaming
  webrtc,     // Low-latency video + data channels
  websocket,  // LAN fallback - rosbridge compatible
  http,       // Absolute fallback - request/response only
  mqtt,       // Pub/sub for event-driven updates
}

/// Centralized transport configuration
class TransportConfig extends ChangeNotifier {
  static TransportConfig? _instance;
  static TransportConfig get instance => _instance ??= TransportConfig._();

  TransportConfig._();

  // ============================================================
  // TIMING CONFIGURATION - Previously hardcoded values
  // ============================================================

  // gRPC Settings
  Duration grpcKeepaliveInterval = const Duration(seconds: 10);
  Duration grpcKeepaliveTimeout = const Duration(seconds: 5);
  Duration grpcConnectionTimeout = const Duration(seconds: 10);
  Duration grpcIdleTimeout = const Duration(minutes: 5);
  Duration grpcMaxConnectionAge = const Duration(hours: 1);

  // Reconnection Settings
  Duration minReconnectDelay = const Duration(seconds: 1);
  Duration maxReconnectDelay = const Duration(minutes: 1);
  double reconnectBackoffMultiplier = 1.5;
  int maxReconnectAttempts = 10;

  // WebSocket Settings
  Duration wsPingInterval = const Duration(seconds: 15);
  Duration wsConnectionTimeout = const Duration(seconds: 30);
  Duration wsReconnectDelay = const Duration(seconds: 1);

  // Heartbeat Settings
  Duration heartbeatInterval = const Duration(seconds: 1);
  Duration heartbeatTimeout = const Duration(seconds: 5);
  Duration staleConnectionThreshold = const Duration(seconds: 5);

  // HTTP Polling Settings
  Duration httpPollInterval = const Duration(seconds: 2);
  Duration httpRequestTimeout = const Duration(seconds: 10);

  // Fleet Sync Settings
  Duration fleetSyncInterval = const Duration(seconds: 30);

  // Obstacle Announcement Settings
  Duration obstacleAnnounceCooldown = const Duration(seconds: 5);
  Duration anyObstacleCooldown = const Duration(seconds: 3);

  // Velocity Command Settings
  Duration velocitySendInterval = const Duration(milliseconds: 100);

  // WebRTC Settings
  Duration webrtcOfferTimeout = const Duration(seconds: 10);
  Duration webrtcIceGatheringTimeout = const Duration(seconds: 5);
  Duration webrtcDataChannelTimeout = const Duration(seconds: 10);

  // MQTT Settings
  Duration mqttKeepalive = const Duration(seconds: 30);
  Duration mqttReconnectDelay = const Duration(seconds: 5);

  // ============================================================
  // ADAPTIVE TIMING - Adjusts based on network conditions
  // ============================================================

  NetworkCondition _currentCondition = NetworkCondition.good;
  NetworkCondition get currentCondition => _currentCondition;

  double _currentRtt = 0;
  double _currentJitter = 0;
  double _packetLoss = 0;

  double get currentRtt => _currentRtt;
  double get currentJitter => _currentJitter;
  double get packetLoss => _packetLoss;

  /// Update network metrics and adapt timing
  void updateNetworkMetrics({
    required double rttMs,
    required double jitterMs,
    double packetLossPercent = 0,
  }) {
    _currentRtt = rttMs;
    _currentJitter = jitterMs;
    _packetLoss = packetLossPercent;

    // Classify network condition
    if (rttMs < 50 && jitterMs < 10 && packetLossPercent < 1) {
      _currentCondition = NetworkCondition.excellent;
    } else if (rttMs < 150 && jitterMs < 30 && packetLossPercent < 3) {
      _currentCondition = NetworkCondition.good;
    } else if (rttMs < 300 && jitterMs < 50 && packetLossPercent < 5) {
      _currentCondition = NetworkCondition.fair;
    } else if (rttMs < 500 && jitterMs < 100 && packetLossPercent < 10) {
      _currentCondition = NetworkCondition.poor;
    } else {
      _currentCondition = NetworkCondition.critical;
    }

    _adaptTimings();
    notifyListeners();
  }

  /// Adapt timings based on network condition
  void _adaptTimings() {
    switch (_currentCondition) {
      case NetworkCondition.excellent:
        grpcKeepaliveInterval = const Duration(seconds: 15);
        heartbeatInterval = const Duration(seconds: 2);
        velocitySendInterval = const Duration(milliseconds: 50);
        break;
      case NetworkCondition.good:
        grpcKeepaliveInterval = const Duration(seconds: 10);
        heartbeatInterval = const Duration(seconds: 1);
        velocitySendInterval = const Duration(milliseconds: 100);
        break;
      case NetworkCondition.fair:
        grpcKeepaliveInterval = const Duration(seconds: 8);
        heartbeatInterval = const Duration(milliseconds: 800);
        velocitySendInterval = const Duration(milliseconds: 150);
        break;
      case NetworkCondition.poor:
        grpcKeepaliveInterval = const Duration(seconds: 5);
        heartbeatInterval = const Duration(milliseconds: 500);
        velocitySendInterval = const Duration(milliseconds: 200);
        break;
      case NetworkCondition.critical:
        grpcKeepaliveInterval = const Duration(seconds: 3);
        heartbeatInterval = const Duration(milliseconds: 300);
        velocitySendInterval = const Duration(milliseconds: 300);
        break;
    }

    debugPrint('TransportConfig: Adapted to $_currentCondition (RTT: ${_currentRtt}ms, Jitter: ${_currentJitter}ms)');
  }

  /// Get recommended transport for current conditions
  AdaptiveTransportType get recommendedTransport {
    if (_currentCondition == NetworkCondition.excellent ||
        _currentCondition == NetworkCondition.good) {
      return AdaptiveTransportType.webrtc; // Best for low-latency
    } else if (_currentCondition == NetworkCondition.fair) {
      return AdaptiveTransportType.grpc; // Reliable with some latency
    } else {
      return AdaptiveTransportType.http; // Most reliable under poor conditions
    }
  }

  /// Check if predictive control should be enabled
  bool get shouldUsePredictiveControl {
    return _currentRtt > 100 || _currentCondition == NetworkCondition.poor ||
           _currentCondition == NetworkCondition.critical;
  }

  /// Get prediction horizon based on RTT
  Duration get predictionHorizon {
    // Predict 2x RTT ahead for smooth control
    return Duration(milliseconds: (_currentRtt * 2).round().clamp(50, 500));
  }

  // ============================================================
  // PERSISTENCE
  // ============================================================

  /// Load configuration from shared preferences
  Future<void> loadFromPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      grpcKeepaliveInterval = Duration(
        milliseconds: prefs.getInt('grpc_keepalive_ms') ?? 10000,
      );
      grpcKeepaliveTimeout = Duration(
        milliseconds: prefs.getInt('grpc_keepalive_timeout_ms') ?? 5000,
      );
      minReconnectDelay = Duration(
        milliseconds: prefs.getInt('min_reconnect_ms') ?? 1000,
      );
      maxReconnectDelay = Duration(
        milliseconds: prefs.getInt('max_reconnect_ms') ?? 60000,
      );
      heartbeatInterval = Duration(
        milliseconds: prefs.getInt('heartbeat_interval_ms') ?? 1000,
      );
      fleetSyncInterval = Duration(
        milliseconds: prefs.getInt('fleet_sync_interval_ms') ?? 30000,
      );
      obstacleAnnounceCooldown = Duration(
        milliseconds: prefs.getInt('obstacle_cooldown_ms') ?? 5000,
      );

      debugPrint('TransportConfig: Loaded from preferences');
      notifyListeners();
    } catch (e) {
      debugPrint('TransportConfig: Failed to load preferences: $e');
    }
  }

  /// Save configuration to shared preferences
  Future<void> saveToPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setInt('grpc_keepalive_ms', grpcKeepaliveInterval.inMilliseconds);
      await prefs.setInt('grpc_keepalive_timeout_ms', grpcKeepaliveTimeout.inMilliseconds);
      await prefs.setInt('min_reconnect_ms', minReconnectDelay.inMilliseconds);
      await prefs.setInt('max_reconnect_ms', maxReconnectDelay.inMilliseconds);
      await prefs.setInt('heartbeat_interval_ms', heartbeatInterval.inMilliseconds);
      await prefs.setInt('fleet_sync_interval_ms', fleetSyncInterval.inMilliseconds);
      await prefs.setInt('obstacle_cooldown_ms', obstacleAnnounceCooldown.inMilliseconds);

      debugPrint('TransportConfig: Saved to preferences');
    } catch (e) {
      debugPrint('TransportConfig: Failed to save preferences: $e');
    }
  }

  /// Reset to defaults
  void resetToDefaults() {
    grpcKeepaliveInterval = const Duration(seconds: 10);
    grpcKeepaliveTimeout = const Duration(seconds: 5);
    grpcConnectionTimeout = const Duration(seconds: 10);
    grpcIdleTimeout = const Duration(minutes: 5);
    grpcMaxConnectionAge = const Duration(hours: 1);
    minReconnectDelay = const Duration(seconds: 1);
    maxReconnectDelay = const Duration(minutes: 1);
    reconnectBackoffMultiplier = 1.5;
    maxReconnectAttempts = 10;
    wsPingInterval = const Duration(seconds: 15);
    wsConnectionTimeout = const Duration(seconds: 30);
    wsReconnectDelay = const Duration(seconds: 1);
    heartbeatInterval = const Duration(seconds: 1);
    heartbeatTimeout = const Duration(seconds: 5);
    staleConnectionThreshold = const Duration(seconds: 5);
    httpPollInterval = const Duration(seconds: 2);
    httpRequestTimeout = const Duration(seconds: 10);
    fleetSyncInterval = const Duration(seconds: 30);
    obstacleAnnounceCooldown = const Duration(seconds: 5);
    anyObstacleCooldown = const Duration(seconds: 3);
    velocitySendInterval = const Duration(milliseconds: 100);

    notifyListeners();
    debugPrint('TransportConfig: Reset to defaults');
  }

  /// Export configuration as JSON
  Map<String, dynamic> toJson() => {
    'grpc_keepalive_ms': grpcKeepaliveInterval.inMilliseconds,
    'grpc_keepalive_timeout_ms': grpcKeepaliveTimeout.inMilliseconds,
    'grpc_connection_timeout_ms': grpcConnectionTimeout.inMilliseconds,
    'grpc_idle_timeout_ms': grpcIdleTimeout.inMilliseconds,
    'min_reconnect_ms': minReconnectDelay.inMilliseconds,
    'max_reconnect_ms': maxReconnectDelay.inMilliseconds,
    'reconnect_backoff_multiplier': reconnectBackoffMultiplier,
    'max_reconnect_attempts': maxReconnectAttempts,
    'ws_ping_interval_ms': wsPingInterval.inMilliseconds,
    'ws_connection_timeout_ms': wsConnectionTimeout.inMilliseconds,
    'heartbeat_interval_ms': heartbeatInterval.inMilliseconds,
    'heartbeat_timeout_ms': heartbeatTimeout.inMilliseconds,
    'http_poll_interval_ms': httpPollInterval.inMilliseconds,
    'fleet_sync_interval_ms': fleetSyncInterval.inMilliseconds,
    'obstacle_cooldown_ms': obstacleAnnounceCooldown.inMilliseconds,
    'velocity_send_interval_ms': velocitySendInterval.inMilliseconds,
    'network_condition': _currentCondition.name,
    'current_rtt_ms': _currentRtt,
    'current_jitter_ms': _currentJitter,
    'packet_loss_percent': _packetLoss,
  };

  /// Import configuration from JSON
  void fromJson(Map<String, dynamic> json) {
    if (json['grpc_keepalive_ms'] != null) {
      grpcKeepaliveInterval = Duration(milliseconds: json['grpc_keepalive_ms'] as int);
    }
    if (json['grpc_keepalive_timeout_ms'] != null) {
      grpcKeepaliveTimeout = Duration(milliseconds: json['grpc_keepalive_timeout_ms'] as int);
    }
    if (json['min_reconnect_ms'] != null) {
      minReconnectDelay = Duration(milliseconds: json['min_reconnect_ms'] as int);
    }
    if (json['max_reconnect_ms'] != null) {
      maxReconnectDelay = Duration(milliseconds: json['max_reconnect_ms'] as int);
    }
    if (json['heartbeat_interval_ms'] != null) {
      heartbeatInterval = Duration(milliseconds: json['heartbeat_interval_ms'] as int);
    }
    if (json['fleet_sync_interval_ms'] != null) {
      fleetSyncInterval = Duration(milliseconds: json['fleet_sync_interval_ms'] as int);
    }
    if (json['obstacle_cooldown_ms'] != null) {
      obstacleAnnounceCooldown = Duration(milliseconds: json['obstacle_cooldown_ms'] as int);
    }
    if (json['velocity_send_interval_ms'] != null) {
      velocitySendInterval = Duration(milliseconds: json['velocity_send_interval_ms'] as int);
    }
    notifyListeners();
  }
}

/// Network quality monitor - measures RTT, jitter, packet loss
class NetworkQualityMonitor {
  final TransportConfig _config;
  Timer? _measurementTimer;
  final List<double> _rttSamples = [];
  final List<int> _pingSequence = [];
  int _lastSequence = 0;

  NetworkQualityMonitor(this._config);

  /// Start monitoring with a ping function
  void startMonitoring(Future<double> Function() pingFn) {
    _measurementTimer?.cancel();
    _measurementTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _measureQuality(pingFn),
    );
  }

  /// Stop monitoring
  void stopMonitoring() {
    _measurementTimer?.cancel();
    _measurementTimer = null;
  }

  Future<void> _measureQuality(Future<double> Function() pingFn) async {
    try {
      _lastSequence++;
      final seq = _lastSequence;
      final start = DateTime.now();

      final rtt = await pingFn();

      // Record RTT sample
      _rttSamples.add(rtt);
      if (_rttSamples.length > 20) _rttSamples.removeAt(0);

      // Record sequence for packet loss calculation
      _pingSequence.add(seq);
      if (_pingSequence.length > 20) _pingSequence.removeAt(0);

      // Calculate metrics
      final avgRtt = _rttSamples.reduce((a, b) => a + b) / _rttSamples.length;

      // Calculate jitter (variation in RTT)
      double jitter = 0;
      if (_rttSamples.length > 1) {
        for (int i = 1; i < _rttSamples.length; i++) {
          jitter += (_rttSamples[i] - _rttSamples[i - 1]).abs();
        }
        jitter /= (_rttSamples.length - 1);
      }

      // Calculate packet loss
      double packetLoss = 0;
      if (_pingSequence.length > 1) {
        final expected = _pingSequence.last - _pingSequence.first + 1;
        final received = _pingSequence.length;
        packetLoss = ((expected - received) / expected) * 100;
      }

      _config.updateNetworkMetrics(
        rttMs: avgRtt,
        jitterMs: jitter,
        packetLossPercent: packetLoss.clamp(0, 100),
      );
    } catch (e) {
      debugPrint('NetworkQualityMonitor: Measurement failed: $e');
      // On failure, assume poor conditions
      _config.updateNetworkMetrics(
        rttMs: 500,
        jitterMs: 100,
        packetLossPercent: 50,
      );
    }
  }

  void dispose() {
    stopMonitoring();
  }
}
