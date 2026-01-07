import 'dart:async';
import 'package:flutter/foundation.dart';
import 'rosbridge_client.dart';

/// Command to send to the relay buffer
class BufferCommand {
  final String id;
  final String type;
  final Map<String, dynamic> data;
  final int? timeoutMs;

  BufferCommand({
    String? id,
    required this.type,
    this.data = const {},
    this.timeoutMs,
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString();

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
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

  factory BufferCommand.closeDisplay() =>
      BufferCommand(type: 'close_display');

  factory BufferCommand.wait(int durationMs) => BufferCommand(
        type: 'wait',
        data: {'duration_ms': durationMs},
      );

  factory BufferCommand.sound(String sound) => BufferCommand(
        type: 'sound',
        data: {'sound': sound},
      );

  /// Enter motion standby mode - wait for motion detection to trigger tour start
  /// When motion is detected, speaks greeting and shows start button
  factory BufferCommand.motionStandby({
    required String greeting,
    required String sequenceId,
    String? buttonText,
    String? displayUrl,
  }) => BufferCommand(
        type: 'motion_standby',
        data: {
          'greeting': greeting,
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
  final int stuckThresholdMs;      // Time stuck before recovery (default 15s)
  final int maxRecoveryAttempts;   // Max retries before giving up (default 3)
  final int backupDurationMs;      // How long to reverse (default 2000ms)
  final double backupSpeed;        // Reverse speed m/s (default 0.15)
  final double spinSpeed;          // Spin speed rad/s (default 0.5)
  final int nudgeDurationMs;       // Forward nudge duration (default 1500ms)
  final double nudgeSpeed;         // Nudge speed m/s (default 0.2)
  final bool announceRecovery;     // TTS "Looking for alternative path"

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
  }) => RecoveryConfig(
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
        safeDistanceMeters: (json['safe_distance_meters'] as num?)?.toDouble() ?? 0.9,
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
      robot:
          robotJson != null ? RobotBufferStatus.fromJson(robotJson) : RobotBufferStatus(),
      crowdConfig:
          crowdJson != null ? RelayCrowdConfig.fromJson(crowdJson) : const RelayCrowdConfig(),
      timestamp: json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
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
  final String safetyZone;  // CLEAR, WARN, CREEP, STOP
  final List<double> ultrasonic;  // Distances in meters
  final bool ultrasonicBlocked;
  final double minFrontDistance;  // Min LIDAR distance in front arc (meters)

  RobotBufferStatus({
    this.connected = false,
    this.navStatus = 0,
    this.navGoal = '',
    this.battery = 0,
    this.safetyZone = 'CLEAR',
    this.ultrasonic = const [],
    this.ultrasonicBlocked = false,
    this.minFrontDistance = 99.0,
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
            .toList() ?? [],
        ultrasonicBlocked: json['ultrasonic_blocked'] as bool? ?? false,
        minFrontDistance: (json['min_front_distance'] as num?)?.toDouble() ?? 99.0,
      );

  /// Min ultrasonic distance in cm (for display), null if no valid data
  double? get minUltrasonicCm {
    if (ultrasonic.isEmpty) return null;
    final valid = ultrasonic.where((d) => d > 0).toList();
    if (valid.isEmpty) return null;
    return valid.reduce((a, b) => a < b ? a : b) * 100;
  }

  /// Whether ultrasonic data is available
  bool get hasUltrasonic => ultrasonic.isNotEmpty && ultrasonic.any((d) => d > 0);
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

  // Retry tracking (logic is HERE, not in relay)
  final Map<String, int> _retryCount = {};
  int maxRetries = 3;

  // Last heartbeat tracking
  DateTime? _lastHeartbeat;
  DateTime? get lastHeartbeat => _lastHeartbeat;
  bool get isStale =>
      _lastHeartbeat == null ||
      DateTime.now().difference(_lastHeartbeat!).inSeconds > 5;

  BufferClient(this._client) {
    _setupMessageHandler();
    _setupConnectionStateHandler();
  }

  void _setupConnectionStateHandler() {
    // Re-subscribe to messages when connection state changes
    // This handles the case where RosbridgeClient recreates stream controllers on reconnect
    _stateSubscription = _client.connectionState.listen((state) {
      if (state == WsConnectionState.connected) {
        debugPrint('BufferClient: Connection restored, re-subscribing to messages');
        _setupMessageHandler();
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
    _state = BufferState.fromJson(json);
    _lastHeartbeat = DateTime.now();
    onHeartbeat?.call('heartbeat', _state);
    notifyListeners();
  }

  void _handleCommandStarted(Map<String, dynamic> json) {
    final command = json['command'] as Map<String, dynamic>?;
    debugPrint('BufferClient: Command started: ${command?['id']} (${command?['type']})');
    onCommandStarted?.call('started', command);
    notifyListeners();
  }

  void _handleCommandCompleted(Map<String, dynamic> json) {
    final result = CommandResult.fromJson(json);
    debugPrint('BufferClient: Command completed: ${result.commandId} = ${result.result}');

    // Handle retry logic HERE (not in relay)
    if (result.isFailure) {
      final retries = _retryCount[result.commandId] ?? 0;
      if (retries < maxRetries) {
        _retryCount[result.commandId] = retries + 1;
        debugPrint('BufferClient: Will retry (${retries + 1}/$maxRetries)');
      }
    } else {
      _retryCount.remove(result.commandId);
    }

    onCommandCompleted?.call('completed', result);
    notifyListeners();
  }

  // === Buffer Control Methods ===

  /// Load commands into the relay buffer
  void loadCommands(List<BufferCommand> commands, {bool clearExisting = true}) {
    debugPrint('BufferClient: Loading ${commands.length} commands');
    _client.send({
      'op': 'buffer_load',
      'commands': commands.map((c) => c.toJson()).toList(),
      'clear_existing': clearExisting,
    });
  }

  /// Clear all pending commands
  void clear() {
    debugPrint('BufferClient: Clearing buffer');
    _client.send({'op': 'buffer_clear'});
    _retryCount.clear();
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

  /// Start tour mode - locks tablet screen to prevent access to controls
  /// @param pin Optional PIN code to unlock (default is 1234)
  void startTourMode({String? pin}) {
    debugPrint('BufferClient: Starting tour mode on tablet');
    _client.send({
      'op': 'tablet_tour_start',
      if (pin != null) 'pin': pin,
    });
  }

  /// Stop tour mode - unlocks tablet screen
  void stopTourMode() {
    debugPrint('BufferClient: Stopping tour mode on tablet');
    _client.send({'op': 'tablet_tour_stop'});
  }

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
      if (waitTimes.containsKey(waypoint) && !displayUrls.containsKey(waypoint)) {
        commands.add(BufferCommand.wait(waitTimes[waypoint]! * 1000));
      }
    }

    loadCommands(commands);
  }

  /// Retry count for a command
  int getRetryCount(String commandId) => _retryCount[commandId] ?? 0;

  /// Check if a command should be retried
  bool shouldRetry(String commandId) =>
      (_retryCount[commandId] ?? 0) < maxRetries;

  @override
  void dispose() {
    _messageSubscription?.cancel();
    _stateSubscription?.cancel();
    super.dispose();
  }
}
