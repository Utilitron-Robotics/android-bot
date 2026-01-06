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
}

/// Current buffer state from relay
class BufferState {
  final bool paused;
  final BufferCommandStatus? current;
  final int pendingCount;
  final int completedCount;
  final RobotBufferStatus robot;
  final int timestamp;

  BufferState({
    this.paused = false,
    this.current,
    this.pendingCount = 0,
    this.completedCount = 0,
    RobotBufferStatus? robot,
    int? timestamp,
  })  : robot = robot ?? RobotBufferStatus(),
        timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  factory BufferState.fromJson(Map<String, dynamic> json) {
    final buffer = json['buffer'] as Map<String, dynamic>?;
    final robotJson = json['robot'] as Map<String, dynamic>?;

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

  RobotBufferStatus({
    this.connected = false,
    this.navStatus = 0,
    this.navGoal = '',
    this.battery = 0,
  });

  factory RobotBufferStatus.fromJson(Map<String, dynamic> json) =>
      RobotBufferStatus(
        connected: json['connected'] as bool? ?? false,
        navStatus: json['nav_status'] as int? ?? 0,
        navGoal: json['nav_goal'] as String? ?? '',
        battery: json['battery'] as int? ?? 0,
      );
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

  bool get isSuccess => result == 'success';
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
