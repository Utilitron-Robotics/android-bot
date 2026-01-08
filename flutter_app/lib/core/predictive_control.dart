/// Predictive Control for High-Latency WAN Operations
///
/// Compensates for network latency by:
/// - Predicting robot state ahead of actual feedback
/// - Pre-sending commands based on predicted trajectory
/// - Smoothing control inputs to hide latency from user
/// - Dead reckoning during feedback gaps

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'transport_config.dart';

/// Robot state at a point in time
class RobotState {
  final double x;
  final double y;
  final double theta; // heading in radians
  final double linearVelocity;
  final double angularVelocity;
  final DateTime timestamp;

  RobotState({
    required this.x,
    required this.y,
    required this.theta,
    required this.linearVelocity,
    required this.angularVelocity,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Copy with modifications
  RobotState copyWith({
    double? x,
    double? y,
    double? theta,
    double? linearVelocity,
    double? angularVelocity,
    DateTime? timestamp,
  }) => RobotState(
    x: x ?? this.x,
    y: y ?? this.y,
    theta: theta ?? this.theta,
    linearVelocity: linearVelocity ?? this.linearVelocity,
    angularVelocity: angularVelocity ?? this.angularVelocity,
    timestamp: timestamp ?? this.timestamp,
  );

  /// Predict state after dt milliseconds using kinematics
  RobotState predictAfter(Duration dt) {
    final dtSec = dt.inMilliseconds / 1000.0;

    // Simple differential drive kinematics
    final newTheta = theta + angularVelocity * dtSec;
    final avgTheta = (theta + newTheta) / 2;
    final newX = x + linearVelocity * cos(avgTheta) * dtSec;
    final newY = y + linearVelocity * sin(avgTheta) * dtSec;

    return RobotState(
      x: newX,
      y: newY,
      theta: newTheta,
      linearVelocity: linearVelocity,
      angularVelocity: angularVelocity,
      timestamp: timestamp.add(dt),
    );
  }

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'theta': theta,
    'linear_velocity': linearVelocity,
    'angular_velocity': angularVelocity,
    'timestamp': timestamp.millisecondsSinceEpoch,
  };

  factory RobotState.fromJson(Map<String, dynamic> json) => RobotState(
    x: (json['x'] as num?)?.toDouble() ?? 0,
    y: (json['y'] as num?)?.toDouble() ?? 0,
    theta: (json['theta'] as num?)?.toDouble() ?? 0,
    linearVelocity: (json['linear_velocity'] as num?)?.toDouble() ?? 0,
    angularVelocity: (json['angular_velocity'] as num?)?.toDouble() ?? 0,
    timestamp: json['timestamp'] != null
        ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int)
        : null,
  );

  static RobotState get zero => RobotState(
    x: 0, y: 0, theta: 0, linearVelocity: 0, angularVelocity: 0,
  );
}

/// Command with timestamp for replay/prediction
class TimestampedCommand {
  final double linear;
  final double angular;
  final DateTime timestamp;
  final DateTime? acknowledgedAt;
  final DateTime? executedAt;

  TimestampedCommand({
    required this.linear,
    required this.angular,
    DateTime? timestamp,
    this.acknowledgedAt,
    this.executedAt,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get isAcknowledged => acknowledgedAt != null;
  bool get isExecuted => executedAt != null;
}

/// Predictive Control System
class PredictiveController extends ChangeNotifier {
  static const String _tag = 'PredictiveController';

  final TransportConfig _config;

  // State tracking
  RobotState _lastKnownState = RobotState.zero;
  RobotState _predictedState = RobotState.zero;
  DateTime _lastStateUpdate = DateTime.now();

  // Command history for replay/prediction
  final List<TimestampedCommand> _commandHistory = [];
  static const int _maxHistorySize = 100;

  // Prediction state
  bool _isEnabled = true;
  Timer? _predictionTimer;

  // Control smoothing
  double _targetLinear = 0;
  double _targetAngular = 0;
  double _smoothedLinear = 0;
  double _smoothedAngular = 0;
  static const double _smoothingFactor = 0.3; // 0-1, higher = more responsive

  // Callbacks
  Function(double linear, double angular)? _onSendCommand;

  // Streams
  final _stateController = StreamController<RobotState>.broadcast();
  final _predictedStateController = StreamController<RobotState>.broadcast();

  Stream<RobotState> get actualState => _stateController.stream;
  Stream<RobotState> get predictedState => _predictedStateController.stream;

  PredictiveController({
    TransportConfig? config,
  }) : _config = config ?? TransportConfig.instance;

  // Getters
  bool get isEnabled => _isEnabled;
  RobotState get lastKnownState => _lastKnownState;
  RobotState get currentPredictedState => _predictedState;
  double get smoothedLinear => _smoothedLinear;
  double get smoothedAngular => _smoothedAngular;

  /// Enable/disable predictive control
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    if (enabled) {
      _startPredictionLoop();
    } else {
      _stopPredictionLoop();
    }
    notifyListeners();
  }

  /// Set command callback
  void setCommandCallback(Function(double, double) callback) {
    _onSendCommand = callback;
  }

  /// Start the prediction loop
  void start() {
    if (_isEnabled) {
      _startPredictionLoop();
    }
  }

  /// Stop the prediction loop
  void stop() {
    _stopPredictionLoop();
    _targetLinear = 0;
    _targetAngular = 0;
    _smoothedLinear = 0;
    _smoothedAngular = 0;
  }

  /// Update with actual robot state from server
  void updateActualState(RobotState state) {
    final now = DateTime.now();

    // Calculate how stale the state is (server delay)
    final stateAge = now.difference(state.timestamp);

    debugPrint('$_tag: Received state (age: ${stateAge.inMilliseconds}ms)');

    _lastKnownState = state;
    _lastStateUpdate = now;
    _stateController.add(state);

    // If predictive control is enabled, reconcile with prediction
    if (_isEnabled && _config.shouldUsePredictiveControl) {
      _reconcilePrediction(state, stateAge);
    } else {
      _predictedState = state;
      _predictedStateController.add(state);
    }

    notifyListeners();
  }

  /// Set target velocity (user input)
  void setTargetVelocity(double linear, double angular) {
    _targetLinear = linear;
    _targetAngular = angular;
  }

  /// Apply velocity with smoothing and send command
  void applyVelocity() {
    // Smooth the velocity transition
    _smoothedLinear = _smoothedLinear + (_targetLinear - _smoothedLinear) * _smoothingFactor;
    _smoothedAngular = _smoothedAngular + (_targetAngular - _smoothedAngular) * _smoothingFactor;

    // Deadband to prevent drift
    final effectiveLinear = _smoothedLinear.abs() < 0.01 ? 0.0 : _smoothedLinear;
    final effectiveAngular = _smoothedAngular.abs() < 0.01 ? 0.0 : _smoothedAngular;

    // Record command
    final cmd = TimestampedCommand(
      linear: effectiveLinear,
      angular: effectiveAngular,
    );
    _addToHistory(cmd);

    // Update predicted state immediately
    if (_isEnabled) {
      _predictedState = _predictedState.copyWith(
        linearVelocity: effectiveLinear,
        angularVelocity: effectiveAngular,
      );
    }

    // Send to robot
    _onSendCommand?.call(effectiveLinear, effectiveAngular);
  }

  void _startPredictionLoop() {
    _stopPredictionLoop();

    // Run prediction at high frequency
    _predictionTimer = Timer.periodic(
      const Duration(milliseconds: 16), // ~60Hz
      (_) => _runPredictionStep(),
    );
  }

  void _stopPredictionLoop() {
    _predictionTimer?.cancel();
    _predictionTimer = null;
  }

  /// Run one step of prediction
  void _runPredictionStep() {
    if (!_isEnabled) return;

    final now = DateTime.now();
    final timeSinceUpdate = now.difference(_lastStateUpdate);

    // If we have recent data, use it
    if (timeSinceUpdate < _config.staleConnectionThreshold) {
      // Predict ahead by the network RTT
      final predictionHorizon = _config.predictionHorizon;
      _predictedState = _lastKnownState.predictAfter(predictionHorizon);
    } else {
      // Dead reckoning - predict based on last known state
      _predictedState = _predictedState.predictAfter(const Duration(milliseconds: 16));
    }

    _predictedStateController.add(_predictedState);
  }

  /// Reconcile prediction with actual state
  void _reconcilePrediction(RobotState actual, Duration stateAge) {
    // Calculate prediction error
    final errorX = actual.x - _predictedState.x;
    final errorY = actual.y - _predictedState.y;
    final errorTheta = actual.theta - _predictedState.theta;
    final positionError = sqrt(errorX * errorX + errorY * errorY);

    // If error is small, smoothly correct
    if (positionError < 0.5) { // 0.5 meters
      // Blend prediction with actual
      const blendFactor = 0.5;
      _predictedState = RobotState(
        x: _predictedState.x + errorX * blendFactor,
        y: _predictedState.y + errorY * blendFactor,
        theta: _predictedState.theta + errorTheta * blendFactor,
        linearVelocity: actual.linearVelocity,
        angularVelocity: actual.angularVelocity,
      );
    } else {
      // Large error - snap to actual (prediction was wrong)
      debugPrint('$_tag: Large prediction error (${positionError.toStringAsFixed(2)}m) - resetting');
      _predictedState = actual;
    }

    // Re-apply commands that were sent after the actual state's timestamp
    _replayCommandsSince(actual.timestamp);
  }

  /// Replay commands sent after a timestamp
  void _replayCommandsSince(DateTime since) {
    // Get commands that were sent after the state timestamp
    final pendingCommands = _commandHistory.where(
      (cmd) => cmd.timestamp.isAfter(since),
    ).toList();

    // Apply each command's effect on prediction
    for (final cmd in pendingCommands) {
      final cmdAge = DateTime.now().difference(cmd.timestamp);
      final effect = Duration(milliseconds: min(cmdAge.inMilliseconds, 100));

      _predictedState = _predictedState.copyWith(
        linearVelocity: cmd.linear,
        angularVelocity: cmd.angular,
      ).predictAfter(effect);
    }
  }

  void _addToHistory(TimestampedCommand cmd) {
    _commandHistory.add(cmd);
    if (_commandHistory.length > _maxHistorySize) {
      _commandHistory.removeAt(0);
    }
  }

  /// Get prediction quality metrics
  Map<String, dynamic> getMetrics() {
    final timeSinceUpdate = DateTime.now().difference(_lastStateUpdate);
    return {
      'enabled': _isEnabled,
      'time_since_update_ms': timeSinceUpdate.inMilliseconds,
      'prediction_horizon_ms': _config.predictionHorizon.inMilliseconds,
      'command_history_size': _commandHistory.length,
      'smoothed_linear': _smoothedLinear,
      'smoothed_angular': _smoothedAngular,
      'predicted_x': _predictedState.x,
      'predicted_y': _predictedState.y,
      'predicted_theta': _predictedState.theta,
    };
  }

  @override
  void dispose() {
    stop();
    _stateController.close();
    _predictedStateController.close();
    super.dispose();
  }
}

/// Latency Compensation Filter
/// Smooths out jittery state updates caused by variable network latency
class LatencyCompensationFilter {
  final int _windowSize;
  final List<RobotState> _stateBuffer = [];

  LatencyCompensationFilter({int windowSize = 5}) : _windowSize = windowSize;

  /// Add a state sample and get filtered output
  RobotState filter(RobotState state) {
    _stateBuffer.add(state);
    if (_stateBuffer.length > _windowSize) {
      _stateBuffer.removeAt(0);
    }

    if (_stateBuffer.length < 2) {
      return state;
    }

    // Simple moving average filter
    double sumX = 0, sumY = 0, sumTheta = 0;
    double sumLinear = 0, sumAngular = 0;

    for (final s in _stateBuffer) {
      sumX += s.x;
      sumY += s.y;
      sumTheta += s.theta;
      sumLinear += s.linearVelocity;
      sumAngular += s.angularVelocity;
    }

    final n = _stateBuffer.length;
    return RobotState(
      x: sumX / n,
      y: sumY / n,
      theta: sumTheta / n,
      linearVelocity: sumLinear / n,
      angularVelocity: sumAngular / n,
      timestamp: state.timestamp,
    );
  }

  void reset() {
    _stateBuffer.clear();
  }
}
