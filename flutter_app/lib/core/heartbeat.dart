/// Heartbeat infrastructure for reliable WAN communication
///
/// Drummer: Sends heartbeats at regular intervals
/// Messenger: Receives heartbeats and detects connection staleness
///
/// Both Flutter and Relay use this pattern for bidirectional health monitoring.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';

/// Processing type for command groups
enum ProcessingType {
  /// Commands execute one at a time, each waits for completion
  sequential,

  /// Commands in group can execute simultaneously
  parallel,

  /// Wait for specific condition before proceeding
  barrier,
}

/// A command group with its processing type
class CommandGroup {
  final ProcessingType type;
  final List<String> commandIds;
  final String? barrierCondition; // For barrier type

  const CommandGroup({
    required this.type,
    required this.commandIds,
    this.barrierCondition,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'command_ids': commandIds,
        if (barrierCondition != null) 'barrier_condition': barrierCondition,
      };

  factory CommandGroup.fromJson(Map<String, dynamic> json) => CommandGroup(
        type: ProcessingType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => ProcessingType.sequential,
        ),
        commandIds: List<String>.from(json['command_ids'] ?? []),
        barrierCondition: json['barrier_condition'] as String?,
      );
}

/// Heartbeat data sent between Flutter and Relay
class HeartbeatData {
  final int timestamp;
  final String source; // 'flutter' or 'relay'
  final int sequenceNumber;
  final Map<String, dynamic>? payload;

  const HeartbeatData({
    required this.timestamp,
    required this.source,
    required this.sequenceNumber,
    this.payload,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp,
        'source': source,
        'sequence': sequenceNumber,
        if (payload != null) 'payload': payload,
      };

  factory HeartbeatData.fromJson(Map<String, dynamic> json) => HeartbeatData(
        timestamp: json['timestamp'] as int? ?? 0,
        source: json['source'] as String? ?? 'unknown',
        sequenceNumber: json['sequence'] as int? ?? 0,
        payload: json['payload'] as Map<String, dynamic>?,
      );
}

/// Drummer - Sends heartbeats at regular intervals
///
/// Usage:
/// ```dart
/// final drummer = Drummer(
///   interval: Duration(seconds: 1),
///   source: 'flutter',
///   onBeat: (data) => sendToRelay(data),
/// );
/// drummer.start();
/// ```
class Drummer {
  final Duration interval;
  final String source;
  final void Function(HeartbeatData data) onBeat;
  final Map<String, dynamic> Function()? payloadBuilder;

  Timer? _timer;
  int _sequenceNumber = 0;
  bool _isRunning = false;

  Drummer({
    required this.interval,
    required this.source,
    required this.onBeat,
    this.payloadBuilder,
  });

  /// Start sending heartbeats
  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _sequenceNumber = 0;

    // Send first beat immediately
    _sendBeat();

    // Then at regular intervals
    _timer = Timer.periodic(interval, (_) => _sendBeat());
    debugPrint(
        'Drummer[$source]: Started with ${interval.inMilliseconds}ms interval');
  }

  /// Stop sending heartbeats
  void stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    debugPrint('Drummer[$source]: Stopped at sequence $_sequenceNumber');
  }

  /// Send a single heartbeat
  void _sendBeat() {
    _sequenceNumber++;
    final data = HeartbeatData(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      source: source,
      sequenceNumber: _sequenceNumber,
      payload: payloadBuilder?.call(),
    );
    onBeat(data);
  }

  bool get isRunning => _isRunning;
  int get currentSequence => _sequenceNumber;
}

/// Messenger - Receives heartbeats and detects staleness
///
/// Uses SINC-style rhythm detection - learns the actual heartbeat interval
/// and adapts its staleness threshold accordingly.
///
/// Usage:
/// ```dart
/// final messenger = Messenger(
///   expectedSource: 'relay',
///   missedBeatsThreshold: 3,
///   onStale: () => handleDisconnect(),
///   onRecovered: () => handleReconnect(),
/// );
/// messenger.receiveHeartbeat(data);
/// ```
class Messenger {
  final String expectedSource;
  final int missedBeatsThreshold;
  final VoidCallback? onStale;
  final VoidCallback? onRecovered;
  final void Function(HeartbeatData data)? onHeartbeat;

  // SINC-style rhythm learning
  Duration _expectedInterval = const Duration(seconds: 1);
  int _lastSequence = 0;
  int _lastTimestamp = 0;
  bool _isStale = true; // Start as stale until first heartbeat
  Timer? _staleCheckTimer;

  Messenger({
    required this.expectedSource,
    this.missedBeatsThreshold = 3,
    this.onStale,
    this.onRecovered,
    this.onHeartbeat,
  });

  /// Start monitoring for staleness
  void start() {
    _staleCheckTimer?.cancel();
    _staleCheckTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _checkStaleness(),
    );
    debugPrint('Messenger[$expectedSource]: Started monitoring');
  }

  /// Stop monitoring
  void stop() {
    _staleCheckTimer?.cancel();
    _staleCheckTimer = null;
    debugPrint('Messenger[$expectedSource]: Stopped monitoring');
  }

  /// Process incoming heartbeat
  void receiveHeartbeat(HeartbeatData data) {
    if (data.source != expectedSource) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    // Learn the rhythm (exponential moving average)
    if (_lastTimestamp > 0) {
      final actualInterval = now - _lastTimestamp;
      if (actualInterval > 0 && actualInterval < 10000) {
        // Sanity check
        final oldMs = _expectedInterval.inMilliseconds * 0.9;
        final newMs = actualInterval * 0.1;
        _expectedInterval = Duration(milliseconds: (oldMs + newMs).round());
      }
    }

    _lastTimestamp = now;
    _lastSequence = data.sequenceNumber;

    // Check for recovery
    final wasStale = _isStale;
    _isStale = false;

    if (wasStale) {
      debugPrint(
          'Messenger[$expectedSource]: Connection recovered at seq $_lastSequence');
      onRecovered?.call();
    }

    onHeartbeat?.call(data);
  }

  /// Check if connection has gone stale
  void _checkStaleness() {
    if (_lastTimestamp == 0) return; // Never received a heartbeat

    final now = DateTime.now().millisecondsSinceEpoch;
    final elapsed = now - _lastTimestamp;
    final expectedBeats = elapsed / _expectedInterval.inMilliseconds;

    if (expectedBeats >= missedBeatsThreshold && !_isStale) {
      _isStale = true;
      debugPrint(
          'Messenger[$expectedSource]: Connection STALE - missed ${expectedBeats.toStringAsFixed(1)} beats');
      onStale?.call();
    }
  }

  bool get isStale => _isStale;
  bool get isConnected => !_isStale && _lastTimestamp > 0;
  Duration get learnedInterval => _expectedInterval;
  int get lastSequence => _lastSequence;
}
