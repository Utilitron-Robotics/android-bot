import 'dart:async';
import 'package:flutter/foundation.dart';
import 'rosbridge_client.dart';
import 'heartbeat.dart';

/// Command to send to the relay buffer
class BufferCommand {
  final String id;
  final String type;
  final Map<String, dynamic> data;
  final int? timeoutMs;
  final ProcessingType processingType;  // Sequential or parallel execution

  BufferCommand({
    String? id,
    required this.type,
    this.data = const {},
    this.timeoutMs,
    this.processingType = ProcessingType.sequential,  // Default: wait for completion
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString();

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'processing_type': processingType.name,  // sequential, parallel, or barrier
        ...data, // Flat format for simplicity
        if (timeoutMs != null) 'timeout_ms': timeoutMs,
      };

  // Factory constructors for common commands
  factory BufferCommand.navigate(String waypoint, {int timeoutMs = 60000}) =>
      BufferCommand(
        type: 'navigate',
        data: {'waypoint': waypoint},
        timeoutMs: timeoutMs,
      );

  factory BufferCommand.speak(String text, {int timeoutMs = 30000}) =>
      BufferCommand(
        type: 'speak',
        data: {'text': text},
        timeoutMs: timeoutMs,
      );

  factory BufferCommand.display(String url, {int durationMs = 0}) =>
      BufferCommand(
        type: 'display',
        data: {'url': url, 'duration_ms': durationMs},
      );

  /// Display default content (POI name/company branding) when no custom media
  factory BufferCommand.displayDefault(String waypoint, {int durationMs = 0}) =>
      BufferCommand(
        type: 'display_default',
        data: {'waypoint': waypoint, 'duration_ms': durationMs},
      );

  factory BufferCommand.closeDisplay() => BufferCommand(type: 'close_display');

  factory BufferCommand.wait(int durationMs) => BufferCommand(
        type: 'wait',
        data: {'duration_ms': durationMs},
      );

  factory BufferCommand.sound(String sound) => BufferCommand(
        type: 'sound',
        data: {'sound': sound},
      );

  /// Loop command - tells the buffer to restart the sequence from the beginning
  factory BufferCommand.loop() => BufferCommand(
        id: 'loop_${DateTime.now().millisecondsSinceEpoch}',
        type: 'loop',
      );

  /// Enter motion standby mode - wait for motion detection to trigger tour start
  /// When motion is detected, speaks greeting and shows start button
  factory BufferCommand.motionStandby({
    required String greeting,
    required String sequenceId,
    String? buttonText,
    String? displayUrl,
  }) =>
      BufferCommand(
        id: 'motion_standby_${DateTime.now().millisecondsSinceEpoch}',
        type: 'motion_standby',
        data: {
          'greeting': greeting,
          'sequence_id': sequenceId,
          if (buttonText != null) 'button_text': buttonText,
          if (displayUrl != null) 'display_url': displayUrl,
        },
      );

  /// Enter button standby mode - show start button immediately (no motion detection)
  /// Button press triggers tour start
  factory BufferCommand.buttonStandby({
    required String sequenceId,
    String? buttonText,
    String? displayUrl,
  }) =>
      BufferCommand(
        id: 'button_standby_${DateTime.now().millisecondsSinceEpoch}',
        type: 'button_standby',
        data: {
          'sequence_id': sequenceId,
          if (buttonText != null) 'button_text': buttonText,
          if (displayUrl != null) 'display_url': displayUrl,
        },
      );

  /// Configure recovery behavior for navigation failures
  factory BufferCommand.setRecoveryConfig(RecoveryConfig config) =>
      BufferCommand(
        type: 'set_recovery_config',
        data: config.toJson(),
      );

  /// Configure crowd logic / speed ramping behavior
  factory BufferCommand.setCrowdConfig({
    required double safeDistanceMeters,
    required double rampRate,
  }) =>
      BufferCommand(
        type: 'set_crowd_config',
        data: {
          'safe_distance_meters': safeDistanceMeters,
          'ramp_rate': rampRate,
        },
      );
}

/// Recovery configuration for navigation failures
/// Sent to relay to control how it handles blocked paths and 604 failures
class RecoveryConfig {
  final int stuckThresholdMs; // Time stuck before recovery (default 15s)
  final int maxRecoveryAttempts; // Max retries before giving up (default 3)
  final int backupDurationMs; // How long to reverse (default 2000ms)
  final double backupSpeed; // Reverse speed m/s (default 0.15)
  final double spinSpeed; // Spin speed rad/s (default 0.5)
  final int nudgeDurationMs; // Forward nudge duration (default 1500ms)
  final double nudgeSpeed; // Nudge speed m/s (default 0.2)
  final bool announceRecovery; // TTS "Looking for alternative path"

  const RecoveryConfig({
    this.stuckThresholdMs = 15000,
    this.maxRecoveryAttempts = 3,
    this.backupDurationMs = 2000,
    this.backupSpeed = 0.15,
    this.spinSpeed = 0.5,
    this.nudgeDurationMs = 1500,
    this.nudgeSpeed = 0.2,
    this.announceRecovery = true,
  });

  Map<String, dynamic> toJson() => {
        'stuck_threshold_ms': stuckThresholdMs,
        'max_recovery_attempts': maxRecoveryAttempts,
        'backup_duration_ms': backupDurationMs,
        'backup_speed': backupSpeed,
        'spin_speed': spinSpeed,
        'nudge_duration_ms': nudgeDurationMs,
        'nudge_speed': nudgeSpeed,
        'announce_recovery': announceRecovery,
      };

  factory RecoveryConfig.fromJson(Map<String, dynamic> json) => RecoveryConfig(
        stuckThresholdMs: json['stuck_threshold_ms'] as int? ?? 15000,
        maxRecoveryAttempts: json['max_recovery_attempts'] as int? ?? 3,
        backupDurationMs: json['backup_duration_ms'] as int? ?? 2000,
        backupSpeed: (json['backup_speed'] as num?)?.toDouble() ?? 0.15,
        spinSpeed: (json['spin_speed'] as num?)?.toDouble() ?? 0.5,
        nudgeDurationMs: json['nudge_duration_ms'] as int? ?? 1500,
        nudgeSpeed: (json['nudge_speed'] as num?)?.toDouble() ?? 0.2,
        announceRecovery: json['announce_recovery'] as bool? ?? true,
      );

  RecoveryConfig copyWith({
    int? stuckThresholdMs,
    int? maxRecoveryAttempts,
    int? backupDurationMs,
    double? backupSpeed,
    double? spinSpeed,
    int? nudgeDurationMs,
    double? nudgeSpeed,
    bool? announceRecovery,
  }) =>
      RecoveryConfig(
        stuckThresholdMs: stuckThresholdMs ?? this.stuckThresholdMs,
        maxRecoveryAttempts: maxRecoveryAttempts ?? this.maxRecoveryAttempts,
        backupDurationMs: backupDurationMs ?? this.backupDurationMs,
        backupSpeed: backupSpeed ?? this.backupSpeed,
        spinSpeed: spinSpeed ?? this.spinSpeed,
        nudgeDurationMs: nudgeDurationMs ?? this.nudgeDurationMs,
        nudgeSpeed: nudgeSpeed ?? this.nudgeSpeed,
        announceRecovery: announceRecovery ?? this.announceRecovery,
      );
}

/// Crowd logic config from relay (for display/sync)
class RelayCrowdConfig {
  final double safeDistanceMeters;
  final double rampRate;

  const RelayCrowdConfig({
    this.safeDistanceMeters = 0.9,
    this.rampRate = 0.5,
  });

  factory RelayCrowdConfig.fromJson(Map<String, dynamic> json) =>
      RelayCrowdConfig(
        safeDistanceMeters:
            (json['safe_distance_meters'] as num?)?.toDouble() ?? 0.9,
        rampRate: (json['ramp_rate'] as num?)?.toDouble() ?? 0.5,
      );

  double get safeDistanceFeet => safeDistanceMeters / 0.3048;
}

/// Current buffer state from relay
class BufferState {
  final bool paused;
  final BufferCommandStatus? current;
  final int pendingCount;
  final int completedCount;
  final RobotBufferStatus robot;
  final RelayCrowdConfig crowdConfig;
  final int timestamp;

  BufferState({
    this.paused = false,
    this.current,
    this.pendingCount = 0,
    this.completedCount = 0,
    RobotBufferStatus? robot,
    RelayCrowdConfig? crowdConfig,
    int? timestamp,
  })  : robot = robot ?? RobotBufferStatus(),
        crowdConfig = crowdConfig ?? const RelayCrowdConfig(),
        timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  factory BufferState.fromJson(Map<String, dynamic> json) {
    final buffer = json['buffer'] as Map<String, dynamic>?;
    final robotJson = json['robot'] as Map<String, dynamic>?;
    final crowdJson = json['crowd_config'] as Map<String, dynamic>?;

    return BufferState(
      paused: buffer?['paused'] as bool? ?? false,
      current: buffer?['current'] != null
          ? BufferCommandStatus.fromJson(
              buffer!['current'] as Map<String, dynamic>)
          : null,
      pendingCount: buffer?['pending_count'] as int? ?? 0,
      completedCount: buffer?['completed_count'] as int? ?? 0,
      robot: robotJson != null
          ? RobotBufferStatus.fromJson(robotJson)
          : RobotBufferStatus(),
      crowdConfig: crowdJson != null
          ? RelayCrowdConfig.fromJson(crowdJson)
          : const RelayCrowdConfig(),
      timestamp:
          json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class BufferCommandStatus {
  final String id;
  final String type;
  final int startedAt;
  final int elapsedMs;

  BufferCommandStatus({
    required this.id,
    required this.type,
    required this.startedAt,
    required this.elapsedMs,
  });

  factory BufferCommandStatus.fromJson(Map<String, dynamic> json) =>
      BufferCommandStatus(
        id: json['id'] as String? ?? '',
        type: json['type'] as String? ?? '',
        startedAt: json['started_at'] as int? ?? 0,
        elapsedMs: json['elapsed_ms'] as int? ?? 0,
      );
}

class RobotBufferStatus {
  final bool connected;
  final int navStatus;
  final String navGoal;
  final int battery;
  final String safetyZone; // CLEAR, WARN, CREEP, STOP
  final List<double> ultrasonic; // Distances in meters
  final bool ultrasonicBlocked;
  final double minFrontDistance; // Min LIDAR distance in front arc (meters)
  // Position from heartbeat - ensures we always have position even if pose messages get lost
  final double x;
  final double y;
  final double theta;
  // How old is the robot data on the Android relay (ms)?
  // -1 means never received data, >5000 means data is stale
  final int dataAgeMs;

  RobotBufferStatus({
    this.connected = false,
    this.navStatus = 0,
    this.navGoal = '',
    this.battery = 0,
    this.safetyZone = 'CLEAR',
    this.ultrasonic = const [],
    this.ultrasonicBlocked = false,
    this.minFrontDistance = 99.0,
    this.x = 0.0,
    this.y = 0.0,
    this.theta = 0.0,
    this.dataAgeMs = -1,
  });

  factory RobotBufferStatus.fromJson(Map<String, dynamic> json) =>
      RobotBufferStatus(
        connected: json['connected'] as bool? ?? false,
        navStatus: json['nav_status'] as int? ?? 0,
        navGoal: json['nav_goal'] as String? ?? '',
        battery: json['battery'] as int? ?? 0,
        safetyZone: json['safety_zone'] as String? ?? 'CLEAR',
        ultrasonic: (json['ultrasonic'] as List<dynamic>?)
                ?.map((e) => (e as num).toDouble())
                .toList() ??
            [],
        ultrasonicBlocked: json['ultrasonic_blocked'] as bool? ?? false,
        minFrontDistance:
            (json['min_front_distance'] as num?)?.toDouble() ?? 99.0,
        x: (json['x'] as num?)?.toDouble() ?? 0.0,
        y: (json['y'] as num?)?.toDouble() ?? 0.0,
        theta: (json['theta'] as num?)?.toDouble() ?? 0.0,
        dataAgeMs: json['data_age_ms'] as int? ?? -1,
      );

  /// True if robot data is stale (>5s old or never received)
  bool get isDataStale => dataAgeMs < 0 || dataAgeMs > 5000;

  /// Min ultrasonic distance in cm (for display), null if no valid data
  double? get minUltrasonicCm {
    if (ultrasonic.isEmpty) return null;
    final valid = ultrasonic.where((d) => d > 0).toList();
    if (valid.isEmpty) return null;
    return valid.reduce((a, b) => a < b ? a : b) * 100;
  }

  /// Whether ultrasonic data is available
  bool get hasUltrasonic =>
      ultrasonic.isNotEmpty && ultrasonic.any((d) => d > 0);
}

/// Command completion result
class CommandResult {
  final String commandId;
  final String result; // success, timeout, cancelled, robot_failed, error
  final int durationMs;
  final String? error;
  final int timestamp;

  CommandResult({
    required this.commandId,
    required this.result,
    required this.durationMs,
    this.error,
    required this.timestamp,
  });

  factory CommandResult.fromJson(Map<String, dynamic> json) => CommandResult(
        commandId: json['command_id'] as String? ?? '',
        result: json['result'] as String? ?? 'unknown',
        durationMs: json['duration_ms'] as int? ?? 0,
        error: json['error'] as String?,
        timestamp: json['timestamp'] as int? ?? 0,
      );

  bool get isSuccess => result == 'success' || result == 'skipped';
  bool get isSkipped => result == 'skipped';
  bool get isFailure =>
      result == 'robot_failed' || result == 'error' || result == 'timeout';
}

/// Callback for buffer events
typedef BufferEventCallback = void Function(String event, dynamic data);

/// Client for communicating with the relay command buffer.
///
/// ALL logic lives here in Flutter. The relay is just a dumb buffer.
///
/// Bidirectional heartbeat:
/// - Drummer: Sends heartbeats TO Relay (Flutter→Relay)
/// - Messenger: Receives heartbeats FROM Relay (Relay→Flutter)
class BufferClient extends ChangeNotifier {
  final RosbridgeClient _client;
  StreamSubscription? _messageSubscription;
  StreamSubscription? _stateSubscription;

  // Current state
  BufferState _state = BufferState();
  BufferState get state => _state;

  // Event callbacks
  BufferEventCallback? onCommandStarted;
  BufferEventCallback? onCommandCompleted;
  BufferEventCallback? onHeartbeat;

  // === Bidirectional Heartbeat ===

  // Drummer: Sends heartbeats TO Relay
  late final Drummer _drummer;

  // Messenger: Receives heartbeats FROM Relay (replaces old rhythm tracking)
  late final Messenger _messenger;

  // Rhythm-based heartbeat tracking (SINC-style correlation)
  DateTime? _lastHeartbeat;
  DateTime? get lastHeartbeat => _lastHeartbeat;

  // Track the heartbeat rhythm - measured interval between beats
  Duration _expectedInterval = const Duration(milliseconds: 500); // Default, will adapt
  int _heartbeatCount = 0;
  static const int _missedBeatsThreshold = 6; // Stale after missing ~6 beats (3+ seconds at 500ms)

  /// True if connection is stale - rhythm-based detection:
  /// Instead of absolute "5 seconds since last", we check if we've missed
  /// multiple expected heartbeats based on the measured rhythm (SINC-style).
  bool get isStale {
    // No heartbeat at all - definitely stale
    if (_lastHeartbeat == null) return true;

    // Calculate how many beats we've missed based on expected rhythm
    final elapsed = DateTime.now().difference(_lastHeartbeat!);
    final expectedBeats = elapsed.inMilliseconds / _expectedInterval.inMilliseconds;

    // If we've missed more than threshold beats, connection is stale
    // This adapts to the actual heartbeat rhythm rather than fixed timeout
    if (expectedBeats >= _missedBeatsThreshold) {
      debugPrint('BufferClient: STALE - missed ${expectedBeats.toStringAsFixed(1)} beats '
          '(expected every ${_expectedInterval.inMilliseconds}ms, last seen ${elapsed.inMilliseconds}ms ago)');
      return true;
    }

    // Heartbeat coming but robot data is stale (robot connection issue)
    if (_state.robot.isDataStale) return true;

    return false;
  }

  /// Number of beats missed since last heartbeat (for UI display)
  double get missedBeats {
    if (_lastHeartbeat == null) return double.infinity;
    final elapsed = DateTime.now().difference(_lastHeartbeat!);
    return elapsed.inMilliseconds / _expectedInterval.inMilliseconds;
  }

  /// More specific: is the robot data stale even if heartbeats are flowing?
  bool get isRobotDataStale => _state.robot.isDataStale;

  BufferClient(this._client) {
    // Initialize Drummer: sends heartbeats TO Relay
    _drummer = Drummer(
      interval: const Duration(seconds: 1),
      source: 'flutter',
      onBeat: _sendHeartbeatToRelay,
      payloadBuilder: _buildHeartbeatPayload,
    );

    // Initialize Messenger: receives heartbeats FROM Relay
    _messenger = Messenger(
      expectedSource: 'relay',
      missedBeatsThreshold: 3,
      onStale: _onRelayStale,
      onRecovered: _onRelayRecovered,
    );

    _setupMessageHandler();
    _setupConnectionStateHandler();
  }

  /// Send heartbeat to Relay (Drummer callback)
  void _sendHeartbeatToRelay(HeartbeatData data) {
    _client.send({
      'op': 'flutter_heartbeat',
      ...data.toJson(),
    });
  }

  /// Build payload for outgoing heartbeat
  Map<String, dynamic> _buildHeartbeatPayload() {
    return {
      'connected': _client.state == WsConnectionState.connected,
      'pending_count': _state.pendingCount,
      'relay_stale': _messenger.isStale,
    };
  }

  /// Called when Relay connection goes stale
  void _onRelayStale() {
    debugPrint('BufferClient: Relay connection STALE');
    notifyListeners();
  }

  /// Called when Relay connection recovers
  void _onRelayRecovered() {
    debugPrint('BufferClient: Relay connection RECOVERED');
    notifyListeners();
  }

  void _setupConnectionStateHandler() {
    // Re-subscribe to messages when connection state changes
    // This handles the case where RosbridgeClient recreates stream controllers on reconnect
    _stateSubscription = _client.connectionState.listen((state) {
      if (state == WsConnectionState.connected) {
        debugPrint(
            'BufferClient: Connection restored, re-subscribing to messages');
        // Reset rhythm tracking on reconnect - start fresh
        _heartbeatCount = 0;
        _expectedInterval = const Duration(milliseconds: 500);
        _lastHeartbeat = null;
        _setupMessageHandler();

        // Start bidirectional heartbeat
        _drummer.start();
        _messenger.start();
        debugPrint('BufferClient: Bidirectional heartbeat started');
      } else if (state == WsConnectionState.disconnected) {
        // Stop heartbeat on disconnect
        _drummer.stop();
        _messenger.stop();
        debugPrint('BufferClient: Bidirectional heartbeat stopped');
      }
    });
  }

  void _setupMessageHandler() {
    // Cancel existing subscription before creating new one
    _messageSubscription?.cancel();

    // Listen for buffer messages from relay
    _messageSubscription = _client.messages.listen((json) {
      try {
        final op = json['op'] as String?;

        switch (op) {
          case 'buffer_heartbeat':
            _handleHeartbeat(json);
            break;
          case 'buffer_cmd_started':
            _handleCommandStarted(json);
            break;
          case 'buffer_cmd_completed':
            _handleCommandCompleted(json);
            break;
        }
      } catch (e) {
        // Not a buffer message, ignore
      }
    });
  }

  void _handleHeartbeat(Map<String, dynamic> json) {
    final now = DateTime.now();

    // DEBUG: Log robot data age from heartbeat
    final robotData = json['robot'] as Map<String, dynamic>?;
    final dataAgeMs = robotData?['data_age_ms'] as int? ?? -1;
    if (dataAgeMs > 3000 || dataAgeMs < 0) {
      debugPrint('BufferClient: ⚠️ Heartbeat robot data_age_ms=$dataAgeMs (stale if >5000 or <0)');
    }

    // Convert to HeartbeatData and feed to Messenger for SINC-style rhythm tracking
    final heartbeatData = HeartbeatData(
      timestamp: json['timestamp'] as int? ?? now.millisecondsSinceEpoch,
      source: 'relay',
      sequenceNumber: json['sequence'] as int? ?? _heartbeatCount,
      payload: json,
    );
    _messenger.receiveHeartbeat(heartbeatData);

    // Legacy rhythm tracking (kept for backwards compatibility with isStale getter)
    if (_lastHeartbeat != null) {
      final interval = now.difference(_lastHeartbeat!);
      if (_heartbeatCount < 5) {
        _expectedInterval = interval;
      } else {
        final oldMs = _expectedInterval.inMilliseconds * 0.9;
        final newMs = interval.inMilliseconds * 0.1;
        _expectedInterval = Duration(milliseconds: (oldMs + newMs).round());
      }
    }
    _heartbeatCount++;

    _state = BufferState.fromJson(json);
    _lastHeartbeat = now;
    onHeartbeat?.call('heartbeat', _state);
    notifyListeners();
  }

  void _handleCommandStarted(Map<String, dynamic> json) {
    final command = json['command'] as Map<String, dynamic>?;
    debugPrint(
        'BufferClient: Command started: ${command?['id']} (${command?['type']})');
    onCommandStarted?.call('started', command);
    notifyListeners();
  }

  void _handleCommandCompleted(Map<String, dynamic> json) {
    final result = CommandResult.fromJson(json);
    debugPrint(
        'BufferClient: Command completed: ${result.commandId} = ${result.result}');

    // Handle retry logic HERE (not in relay)
    // NOTE: Retry logic moved to BufferSequenceExecutor

    onCommandCompleted?.call('completed', result);
    notifyListeners();
  }

  // === Buffer Control Methods ===

  /// Load commands into the relay buffer and wait for confirmation
  /// Returns true if commands were loaded and confirmed, false on timeout
  Future<bool> loadCommands(List<BufferCommand> commands, {bool clearExisting = true}) async {
    debugPrint('BufferClient: Loading ${commands.length} commands (waiting for confirmation)');

    final expectedCount = commands.length;
    final completer = Completer<bool>();

    // Listen for heartbeat that confirms commands are loaded
    final originalCallback = onHeartbeat;
    int attempts = 0;
    const maxAttempts = 10; // 10 heartbeats = ~5 seconds at 500ms rate

    onHeartbeat = (op, data) {
      // Call original callback too
      originalCallback?.call(op, data);

      final state = data as BufferState;
      attempts++;
      debugPrint('BufferClient: Confirmation check $attempts/$maxAttempts - pending=${state.pendingCount}');

      if (state.pendingCount >= expectedCount) {
        debugPrint('BufferClient: ✓ Commands confirmed loaded (${state.pendingCount} pending)');
        onHeartbeat = originalCallback;
        if (!completer.isCompleted) completer.complete(true);
      } else if (attempts >= maxAttempts) {
        debugPrint('BufferClient: ✗ Timeout waiting for command confirmation');
        onHeartbeat = originalCallback;
        if (!completer.isCompleted) completer.complete(false);
      }
    };

    // Send the commands
    _client.send({
      'op': 'buffer_load',
      'commands': commands.map((c) => c.toJson()).toList(),
      'clear_existing': clearExisting,
    });

    // Wait for confirmation with timeout
    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        debugPrint('BufferClient: ✗ Hard timeout waiting for command confirmation');
        onHeartbeat = originalCallback;
        return false;
      },
    );
  }

  /// Clear all pending commands
  void clear() {
    debugPrint('BufferClient: Clearing buffer');
    _client.send({'op': 'buffer_clear'});
  }

  /// Pause execution after current command
  void pause() {
    debugPrint('BufferClient: Pausing buffer');
    _client.send({'op': 'buffer_pause'});
  }

  /// Resume execution
  void resume() {
    debugPrint('BufferClient: Resuming buffer');
    _client.send({'op': 'buffer_resume'});
  }

  /// Skip current command
  void skip() {
    debugPrint('BufferClient: Skipping current command');
    _client.send({'op': 'buffer_skip'});
  }

  /// Request status update
  void requestStatus() {
    _client.send({'op': 'buffer_status'});
  }

  // === Tablet Display Control ===

  /// Update countdown timer on tablet screen
  /// @param seconds Countdown seconds (0 = hide countdown)
  /// @param label Label text (e.g., "Next stop in", "Waiting...")
  void updateCountdown(int seconds, {String label = 'Next stop in'}) {
    _client.send({
      'op': 'tablet_countdown',
      'seconds': seconds,
      'label': label,
    });
  }

  /// Start sequence mode - locks tablet screen to prevent access to controls
  /// Works for ALL sequence types: Tour, Delivery, Patrol, Busser, Comic, etc.
  /// @param pin Optional PIN code to unlock (default is 1234)
  void startSequenceMode({String? pin}) {
    debugPrint('BufferClient: Starting sequence mode on tablet');
    _client.send({
      'op': 'tablet_tour_start', // Wire protocol kept for relay_app compatibility
      if (pin != null) 'pin': pin,
    });
  }

  /// Stop sequence mode - unlocks tablet screen
  void stopSequenceMode() {
    debugPrint('BufferClient: Stopping sequence mode on tablet');
    _client.send({'op': 'tablet_tour_stop'}); // Wire protocol kept for relay_app compatibility
  }

  // Legacy aliases for backwards compatibility
  @Deprecated('Use startSequenceMode instead')
  void startTourMode({String? pin}) => startSequenceMode(pin: pin);

  @Deprecated('Use stopSequenceMode instead')
  void stopTourMode() => stopSequenceMode();

  // === Convenience Methods ===

  /// Load a sequence of waypoints with actions
  void loadSequence({
    required List<String> waypoints,
    Map<String, String> speakTexts = const {},
    Map<String, String> displayUrls = const {},
    Map<String, int> waitTimes = const {},
    bool announceArrivals = true,
  }) {
    final commands = <BufferCommand>[];

    for (final waypoint in waypoints) {
      // Navigate
      commands.add(BufferCommand.navigate(waypoint));

      // Arrival sound
      if (announceArrivals) {
        commands.add(BufferCommand.sound('arrival'));
      }

      // Speak
      if (speakTexts.containsKey(waypoint)) {
        commands.add(BufferCommand.speak(speakTexts[waypoint]!));
      } else if (announceArrivals) {
        commands.add(BufferCommand.speak('Arrived at $waypoint'));
      }

      // Display
      if (displayUrls.containsKey(waypoint)) {
        final duration = waitTimes[waypoint] ?? 10;
        commands.add(BufferCommand.display(
          displayUrls[waypoint]!,
          durationMs: duration * 1000,
        ));
      }

      // Wait
      if (waitTimes.containsKey(waypoint) &&
          !displayUrls.containsKey(waypoint)) {
        commands.add(BufferCommand.wait(waitTimes[waypoint]! * 1000));
      }
    }

    loadCommands(commands);
  }

  @override
  void dispose() {
    _drummer.stop();
    _messenger.stop();
    _messageSubscription?.cancel();
    _stateSubscription?.cancel();
    super.dispose();
  }

  // === Heartbeat Accessors ===

  /// Current drummer sequence number (outgoing heartbeats)
  int get drummerSequence => _drummer.currentSequence;

  /// Current messenger learned interval (incoming heartbeat rhythm)
  Duration get messengerLearnedInterval => _messenger.learnedInterval;

  /// Whether the Messenger considers connection stale (modern SINC approach)
  bool get isMessengerStale => _messenger.isStale;
}
