import 'dart:async';
import 'package:flutter/material.dart';

/// Command status for the challenge/acknowledgment system
enum CommandStatus {
  pending,      // Queued, not yet sent
  sent,         // Sent to robot, awaiting ack
  acknowledged, // Robot received command
  executing,    // Robot is executing
  completed,    // Command completed successfully
  failed,       // Command failed
  timeout,      // No response within timeout
  retrying,     // Being retried
}

/// A tracked command with challenge/retry logic
class TrackedCommand {
  final String id;
  final String type;           // 'navigate', 'velocity', 'stop', etc.
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int maxRetries;

  CommandStatus status;
  int retryCount;
  DateTime? sentAt;
  DateTime? ackedAt;
  DateTime? completedAt;
  String? failureReason;

  TrackedCommand({
    required this.id,
    required this.type,
    required this.payload,
    this.maxRetries = 3,
  }) : createdAt = DateTime.now(),
       status = CommandStatus.pending,
       retryCount = 0;

  /// Time since command was sent
  Duration get timeSinceSent => sentAt != null
      ? DateTime.now().difference(sentAt!)
      : Duration.zero;

  /// Check if command has timed out (no ack within threshold)
  bool isTimedOut(Duration threshold) =>
      status == CommandStatus.sent && timeSinceSent > threshold;

  /// Can this command be retried?
  bool get canRetry => retryCount < maxRetries &&
      (status == CommandStatus.timeout || status == CommandStatus.failed);

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'payload': payload,
    'status': status.name,
    'retry_count': retryCount,
    'created_at': createdAt.toIso8601String(),
    'sent_at': sentAt?.toIso8601String(),
    'acked_at': ackedAt?.toIso8601String(),
    'completed_at': completedAt?.toIso8601String(),
    'failure_reason': failureReason,
  };
}

/// Callback interface for command execution
abstract class CommandExecutor {
  /// Send command to robot, returns true if sent successfully
  Future<bool> sendCommand(TrackedCommand command);

  /// Check if currently connected
  bool get isConnected;

  /// Check if data is stale (no updates recently)
  bool get isStale;
}

/// Command manager with challenge/retry system
/// Ensures commands are acknowledged and retried if connection drops
class CommandManager extends ChangeNotifier {
  static const Duration _ackTimeout = Duration(seconds: 5);
  static const Duration _checkInterval = Duration(milliseconds: 500);

  final CommandExecutor _executor;
  final Map<String, TrackedCommand> _commands = {};
  final List<TrackedCommand> _queue = [];

  Timer? _checkTimer;
  bool _processing = false;

  // Stats
  int _totalCommands = 0;
  int _successfulCommands = 0;
  int _failedCommands = 0;
  int _retryCount = 0;

  CommandManager(this._executor) {
    _startCheckTimer();
  }

  // Getters
  List<TrackedCommand> get pendingCommands =>
      _commands.values.where((c) =>
          c.status == CommandStatus.pending ||
          c.status == CommandStatus.sent ||
          c.status == CommandStatus.retrying
      ).toList();

  List<TrackedCommand> get allCommands => _commands.values.toList();
  int get queueLength => _queue.length;
  int get totalCommands => _totalCommands;
  int get successfulCommands => _successfulCommands;
  int get failedCommands => _failedCommands;
  int get retryCount => _retryCount;

  /// Queue a command for execution with tracking
  TrackedCommand queueCommand({
    required String type,
    required Map<String, dynamic> payload,
    int maxRetries = 3,
  }) {
    final id = '${type}_${DateTime.now().millisecondsSinceEpoch}';
    final command = TrackedCommand(
      id: id,
      type: type,
      payload: payload,
      maxRetries: maxRetries,
    );

    _commands[id] = command;
    _queue.add(command);
    _totalCommands++;

    debugPrint('CommandManager: Queued $type command (id=$id, queue=${_queue.length})');
    notifyListeners();

    _processQueue();
    return command;
  }

  /// Queue a navigation command
  TrackedCommand navigate(String waypoint) => queueCommand(
    type: 'navigate',
    payload: {'waypoint': waypoint},
    maxRetries: 5, // More retries for navigation
  );

  /// Queue a velocity command (no retries - real-time)
  TrackedCommand velocity(double linear, double angular) => queueCommand(
    type: 'velocity',
    payload: {'linear': linear, 'angular': angular},
    maxRetries: 0, // Velocity commands don't retry
  );

  /// Queue a stop command (high priority, more retries)
  TrackedCommand stop() => queueCommand(
    type: 'stop',
    payload: {},
    maxRetries: 5,
  );

  /// Queue a cancel navigation command
  TrackedCommand cancelNavigation() => queueCommand(
    type: 'cancel',
    payload: {},
    maxRetries: 3,
  );

  /// Acknowledge a command (robot received it)
  void acknowledgeCommand(String commandId) {
    final command = _commands[commandId];
    if (command == null) return;

    command.status = CommandStatus.acknowledged;
    command.ackedAt = DateTime.now();
    debugPrint('CommandManager: Command $commandId acknowledged');
    notifyListeners();
  }

  /// Mark command as executing
  void commandExecuting(String commandId) {
    final command = _commands[commandId];
    if (command == null) return;

    command.status = CommandStatus.executing;
    debugPrint('CommandManager: Command $commandId executing');
    notifyListeners();
  }

  /// Mark command as completed
  void commandCompleted(String commandId) {
    final command = _commands[commandId];
    if (command == null) return;

    command.status = CommandStatus.completed;
    command.completedAt = DateTime.now();
    _successfulCommands++;
    debugPrint('CommandManager: Command $commandId completed');
    notifyListeners();
  }

  /// Mark command as failed
  void commandFailed(String commandId, String reason) {
    final command = _commands[commandId];
    if (command == null) return;

    command.failureReason = reason;

    if (command.canRetry) {
      _retryCommand(command);
    } else {
      command.status = CommandStatus.failed;
      _failedCommands++;
      debugPrint('CommandManager: Command $commandId failed (no retries left): $reason');
    }
    notifyListeners();
  }

  /// Process the command queue
  Future<void> _processQueue() async {
    if (_processing || _queue.isEmpty) return;
    _processing = true;

    while (_queue.isNotEmpty) {
      final command = _queue.first;

      // Wait for connection if disconnected
      if (!_executor.isConnected) {
        debugPrint('CommandManager: Waiting for connection...');
        await Future.delayed(const Duration(seconds: 1));
        continue;
      }

      // Send the command
      command.status = CommandStatus.sent;
      command.sentAt = DateTime.now();

      try {
        final sent = await _executor.sendCommand(command);
        if (sent) {
          _queue.removeAt(0);
          debugPrint('CommandManager: Sent ${command.type} command (id=${command.id})');
        } else {
          // Failed to send, will be retried by check timer
          command.status = CommandStatus.pending;
          break;
        }
      } catch (e) {
        debugPrint('CommandManager: Error sending command: $e');
        command.status = CommandStatus.pending;
        break;
      }
    }

    _processing = false;
    notifyListeners();
  }

  /// Retry a failed/timed out command
  void _retryCommand(TrackedCommand command) {
    command.retryCount++;
    command.status = CommandStatus.retrying;
    _retryCount++;

    debugPrint('CommandManager: Retrying ${command.type} (attempt ${command.retryCount}/${command.maxRetries})');

    // Re-queue at front
    _queue.insert(0, command);
    _processQueue();
  }

  /// Start the check timer for timeouts and stale data
  void _startCheckTimer() {
    _checkTimer = Timer.periodic(_checkInterval, (_) => _checkCommands());
  }

  /// Check for timed out commands and stale data
  void _checkCommands() {
    bool needsNotify = false;

    for (final command in _commands.values) {
      // Check for timeout
      if (command.isTimedOut(_ackTimeout)) {
        debugPrint('CommandManager: Command ${command.id} timed out');
        command.status = CommandStatus.timeout;

        if (command.canRetry) {
          _retryCommand(command);
        } else {
          command.status = CommandStatus.failed;
          command.failureReason = 'Timeout - no acknowledgment received';
          _failedCommands++;
        }
        needsNotify = true;
      }
    }

    // If data is stale, retry any sent commands
    if (_executor.isStale) {
      for (final command in _commands.values) {
        if (command.status == CommandStatus.sent ||
            command.status == CommandStatus.acknowledged) {
          debugPrint('CommandManager: Connection stale, retrying ${command.id}');
          command.status = CommandStatus.timeout;
          if (command.canRetry) {
            _retryCommand(command);
            needsNotify = true;
          }
        }
      }
    }

    if (needsNotify) notifyListeners();
  }

  /// Clear completed commands older than threshold
  void clearOldCommands({Duration threshold = const Duration(minutes: 5)}) {
    final cutoff = DateTime.now().subtract(threshold);
    _commands.removeWhere((_, cmd) =>
        (cmd.status == CommandStatus.completed || cmd.status == CommandStatus.failed) &&
        (cmd.completedAt ?? cmd.createdAt).isBefore(cutoff)
    );
    notifyListeners();
  }

  /// Cancel all pending commands
  void cancelAll() {
    _queue.clear();
    for (final command in _commands.values) {
      if (command.status == CommandStatus.pending ||
          command.status == CommandStatus.sent ||
          command.status == CommandStatus.retrying) {
        command.status = CommandStatus.failed;
        command.failureReason = 'Cancelled';
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    super.dispose();
  }
}

/// Task status
enum TaskStatus {
  idle,
  starting,
  running,
  paused,
  completing,
  completed,
  failed,
  cancelled,
}

/// Base class for all task modes
/// Tour, Delivery, Patrol, Follow, etc. all extend this
abstract class TaskMode extends ChangeNotifier {
  final String id;
  final String name;
  final String type; // 'tour', 'delivery', 'patrol', etc.

  TaskStatus _status = TaskStatus.idle;
  String? _failureReason;
  DateTime? _startedAt;
  DateTime? _completedAt;

  // Command tracking
  CommandManager? _commandManager;
  TrackedCommand? _currentCommand;

  TaskMode({
    required this.id,
    required this.name,
    required this.type,
  });

  // Getters
  TaskStatus get status => _status;
  String? get failureReason => _failureReason;
  DateTime? get startedAt => _startedAt;
  DateTime? get completedAt => _completedAt;
  bool get isRunning => _status == TaskStatus.running;
  bool get isPaused => _status == TaskStatus.paused;
  bool get isComplete => _status == TaskStatus.completed || _status == TaskStatus.failed || _status == TaskStatus.cancelled;

  CommandManager? get commandManager => _commandManager;
  TrackedCommand? get currentCommand => _currentCommand;

  /// Set the command manager for this task
  void setCommandManager(CommandManager manager) {
    _commandManager = manager;
  }

  /// Start the task
  Future<bool> start() async {
    if (_status != TaskStatus.idle && _status != TaskStatus.completed && _status != TaskStatus.failed) {
      debugPrint('TaskMode: Cannot start - status is $_status');
      return false;
    }

    _status = TaskStatus.starting;
    _startedAt = DateTime.now();
    _failureReason = null;
    notifyListeners();

    try {
      final success = await onStart();
      if (success) {
        _status = TaskStatus.running;
        notifyListeners();
        return true;
      } else {
        _status = TaskStatus.failed;
        _failureReason = 'Failed to start';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _status = TaskStatus.failed;
      _failureReason = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Stop the task
  Future<void> stop() async {
    if (!isRunning && !isPaused) return;

    _status = TaskStatus.cancelled;
    _commandManager?.cancelAll();
    await onStop();
    notifyListeners();
  }

  /// Pause the task
  Future<void> pause() async {
    if (!isRunning) return;
    _status = TaskStatus.paused;
    await onPause();
    notifyListeners();
  }

  /// Resume the task
  Future<void> resume() async {
    if (!isPaused) return;
    _status = TaskStatus.running;
    await onResume();
    notifyListeners();
  }

  /// Complete the task successfully
  @protected
  void complete() {
    _status = TaskStatus.completed;
    _completedAt = DateTime.now();
    onComplete();
    notifyListeners();
  }

  /// Fail the task
  @protected
  void fail(String reason) {
    _status = TaskStatus.failed;
    _failureReason = reason;
    _completedAt = DateTime.now();
    onFail(reason);
    notifyListeners();
  }

  /// Queue a command through the command manager
  @protected
  TrackedCommand? queueCommand({
    required String type,
    required Map<String, dynamic> payload,
    int maxRetries = 3,
  }) {
    if (_commandManager == null) {
      debugPrint('TaskMode: No command manager set!');
      return null;
    }

    _currentCommand = _commandManager!.queueCommand(
      type: type,
      payload: payload,
      maxRetries: maxRetries,
    );
    return _currentCommand;
  }

  /// Handle robot arrival at waypoint
  void onArrived(String waypoint) {
    // Subclasses override this
  }

  /// Handle navigation status change
  void onNavStatus(int status) {
    // Subclasses override this
  }

  // Abstract methods for subclasses
  Future<bool> onStart();
  Future<void> onStop();
  Future<void> onPause();
  Future<void> onResume();
  void onComplete();
  void onFail(String reason);

  /// Get current progress (0.0 - 1.0)
  double get progress;

  /// Get current step description
  String get currentStepDescription;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'status': _status.name,
    'failure_reason': _failureReason,
    'started_at': _startedAt?.toIso8601String(),
    'completed_at': _completedAt?.toIso8601String(),
    'progress': progress,
    'current_step': currentStepDescription,
  };
}

/// Task manager - manages the current active task
class TaskManager extends ChangeNotifier {
  static TaskManager? _instance;

  TaskMode? _activeTask;
  final List<TaskMode> _taskHistory = [];
  CommandManager? _commandManager;

  static TaskManager get instance {
    _instance ??= TaskManager._();
    return _instance!;
  }

  TaskManager._();

  // Getters
  TaskMode? get activeTask => _activeTask;
  bool get hasActiveTask => _activeTask != null && _activeTask!.isRunning;
  List<TaskMode> get taskHistory => List.unmodifiable(_taskHistory);
  CommandManager? get commandManager => _commandManager;

  /// Set the command manager
  void setCommandManager(CommandManager manager) {
    _commandManager = manager;
  }

  /// Start a new task
  Future<bool> startTask(TaskMode task) async {
    // Stop any active task first
    if (_activeTask != null && _activeTask!.isRunning) {
      await _activeTask!.stop();
    }

    _activeTask = task;

    // Give the task access to command manager
    if (_commandManager != null) {
      task.setCommandManager(_commandManager!);
    }

    // Listen for task changes
    task.addListener(_onTaskChanged);

    final success = await task.start();
    notifyListeners();
    return success;
  }

  /// Stop the active task
  Future<void> stopActiveTask() async {
    if (_activeTask == null) return;
    await _activeTask!.stop();
    notifyListeners();
  }

  /// Pause the active task
  Future<void> pauseActiveTask() async {
    if (_activeTask == null) return;
    await _activeTask!.pause();
    notifyListeners();
  }

  /// Resume the active task
  Future<void> resumeActiveTask() async {
    if (_activeTask == null) return;
    await _activeTask!.resume();
    notifyListeners();
  }

  /// Forward arrival event to active task
  void onArrived(String waypoint) {
    _activeTask?.onArrived(waypoint);
  }

  /// Forward nav status to active task
  void onNavStatus(int status) {
    _activeTask?.onNavStatus(status);
  }

  void _onTaskChanged() {
    // Archive completed tasks
    if (_activeTask != null && _activeTask!.isComplete) {
      _taskHistory.add(_activeTask!);
      _activeTask!.removeListener(_onTaskChanged);
      _activeTask = null;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _activeTask?.removeListener(_onTaskChanged);
    super.dispose();
  }
}
