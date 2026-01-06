import 'dart:async';
import 'package:flutter/material.dart';
import 'buffer_client.dart';
import 'rosbridge_client.dart';
import 'sequence_mode.dart';

/// Simplified sequence executor using the buffer-only relay architecture.
///
/// This replaces the complex SequenceTaskMode/CommandManager system.
/// ALL logic lives here in Flutter. The relay just buffers and executes.
class BufferSequenceExecutor extends ChangeNotifier {
  final BufferClient _bufferClient;
  final SequenceExecutorCallback _callback;

  // Current sequence state
  Sequence? _currentSequence;
  int _currentStopIndex = -1;
  SequenceExecutorStatus _status = SequenceExecutorStatus.idle;

  // Retry tracking (logic HERE, not in relay)
  int _navRetryCount = 0;
  static const int _maxNavRetries = 3;

  // Phase tracking for UI
  SequencePhase _currentPhase = SequencePhase.navigating;
  int _countdownSeconds = 0;
  Timer? _countdownTimer;

  BufferSequenceExecutor({
    required RosbridgeClient client,
    required SequenceExecutorCallback callback,
  })  : _bufferClient = BufferClient(client),
        _callback = callback {
    _setupBufferListeners();
  }

  /// Use existing BufferClient
  BufferSequenceExecutor.withClient({
    required BufferClient bufferClient,
    required SequenceExecutorCallback callback,
  })  : _bufferClient = bufferClient,
        _callback = callback {
    _setupBufferListeners();
  }

  // Getters
  Sequence? get currentSequence => _currentSequence;
  int get currentStopIndex => _currentStopIndex;
  SequenceExecutorStatus get status => _status;
  SequencePhase get currentPhase => _currentPhase;
  int get countdownSeconds => _countdownSeconds;
  BufferClient get bufferClient => _bufferClient;
  BufferState get bufferState => _bufferClient.state;

  SequenceStop? get currentStop =>
      _currentSequence != null &&
              _currentStopIndex >= 0 &&
              _currentStopIndex < _currentSequence!.stops.length
          ? _currentSequence!.stops[_currentStopIndex]
          : null;

  double get progress => _currentSequence == null || _currentSequence!.stops.isEmpty
      ? 0.0
      : (_currentStopIndex + 1) / _currentSequence!.stops.length;

  void _setupBufferListeners() {
    // Handle heartbeat updates
    _bufferClient.onHeartbeat = (event, data) {
      _updateFromHeartbeat(data as BufferState);
    };

    // Handle command started
    _bufferClient.onCommandStarted = (event, data) {
      final cmd = data as Map<String, dynamic>?;
      if (cmd != null) {
        _onCommandStarted(cmd);
      }
    };

    // Handle command completed
    _bufferClient.onCommandCompleted = (event, data) {
      final result = data as CommandResult;
      _onCommandCompleted(result);
    };

    // Listen for buffer client changes
    _bufferClient.addListener(_onBufferChanged);
  }

  void _onBufferChanged() {
    // Mirror buffer state to UI
    notifyListeners();
  }

  /// Update state from buffer heartbeat
  void _updateFromHeartbeat(BufferState state) {
    // Update phase based on current command
    if (state.current != null) {
      switch (state.current!.type) {
        case 'navigate':
          _currentPhase = SequencePhase.navigating;
          break;
        case 'speak':
          _currentPhase = SequencePhase.speaking;
          break;
        case 'display':
          _currentPhase = SequencePhase.displaying;
          break;
        case 'wait':
          _currentPhase = SequencePhase.waiting;
          break;
        default:
          break;
      }
    }

    // Check for paused state
    if (state.paused && _status == SequenceExecutorStatus.running) {
      _status = SequenceExecutorStatus.paused;
      notifyListeners();
    } else if (!state.paused && _status == SequenceExecutorStatus.paused) {
      _status = SequenceExecutorStatus.running;
      notifyListeners();
    }
  }

  void _onCommandStarted(Map<String, dynamic> cmd) {
    final type = cmd['type'] as String?;
    debugPrint('BufferSequenceExecutor: Command started: $type (cmd=$cmd)');

    // Update stop index when navigation starts
    if (type == 'navigate') {
      // Waypoint can be in cmd['waypoint'] (flat) or cmd['data']['waypoint'] (nested)
      String? waypoint = cmd['waypoint'] as String?;
      if (waypoint == null) {
        final data = cmd['data'] as Map<String, dynamic>?;
        waypoint = data?['waypoint'] as String?;
      }

      debugPrint('BufferSequenceExecutor: Navigate waypoint=$waypoint');

      if (waypoint != null && _currentSequence != null) {
        // Find the stop index for this waypoint
        for (int i = 0; i < _currentSequence!.stops.length; i++) {
          if (_currentSequence!.stops[i].waypoint == waypoint) {
            debugPrint('BufferSequenceExecutor: Found stop index $i for $waypoint');
            _currentStopIndex = i;
            _currentPhase = SequencePhase.navigating;
            break;
          }
        }
      }
    } else if (type == 'display') {
      _currentPhase = SequencePhase.displaying;
    } else if (type == 'speak') {
      _currentPhase = SequencePhase.speaking;
    } else if (type == 'wait') {
      _currentPhase = SequencePhase.waiting;
    }
    notifyListeners();
  }

  void _onCommandCompleted(CommandResult result) {
    _completedCommandCount++;
    debugPrint('BufferSequenceExecutor: Command completed: ${result.result} ($_completedCommandCount/$_totalCommandCount)');

    // Handle navigation failures with retry logic (ALL in Flutter)
    if (result.isFailure) {
      // Check if this was a navigation failure
      final state = _bufferClient.state;
      if (state.current?.type == 'navigate') {
        _handleNavigationFailure(result);
        return;
      }
    }

    // Check for sequence completion
    if (result.isSuccess) {
      _navRetryCount = 0; // Reset retry count on success
      // Give heartbeat a moment to update, then check completion
      Future.delayed(const Duration(milliseconds: 500), () {
        _checkSequenceCompletion();
      });
    }

    notifyListeners();
  }

  /// Handle navigation failure with retry logic
  void _handleNavigationFailure(CommandResult result) {
    final currentStop = this.currentStop;
    if (currentStop == null) return;

    _navRetryCount++;

    if (_navRetryCount > _maxNavRetries) {
      debugPrint('BufferSequenceExecutor: Max retries exceeded, failing sequence');
      _failSequence('Navigation failed after $_maxNavRetries retries');
      return;
    }

    debugPrint('BufferSequenceExecutor: Retrying navigation ($_navRetryCount/$_maxNavRetries)');

    // Speak retry message
    _callback.onSpeak('Path blocked. Retrying navigation.');

    // Load retry command into buffer
    _bufferClient.loadCommands([
      BufferCommand.navigate(currentStop.waypoint),
    ], clearExisting: false);
  }

  // Track completed commands to detect sequence end without relying on stale heartbeat
  int _completedCommandCount = 0;
  int _totalCommandCount = 0;

  /// Check if sequence is complete
  void _checkSequenceCompletion() {
    final state = _bufferClient.state;

    debugPrint('BufferSequenceExecutor: Checking completion - pending=${state.pendingCount}, current=${state.current?.type}, paused=${state.paused}, status=$_status, completed=$_completedCommandCount/$_totalCommandCount');

    // Method 1: Check heartbeat state (may be stale)
    if (state.pendingCount == 0 && state.current == null && !state.paused) {
      if (_status == SequenceExecutorStatus.running) {
        debugPrint('BufferSequenceExecutor: Completing via heartbeat state (pending=0, current=null)');
        _completeSequence();
        return;
      }
    }

    // Method 2: Check local command tracking (more reliable)
    if (_totalCommandCount > 0 && _completedCommandCount >= _totalCommandCount) {
      if (_status == SequenceExecutorStatus.running) {
        debugPrint('BufferSequenceExecutor: Completing via command count ($_completedCommandCount/$_totalCommandCount)');
        _completeSequence();
        return;
      }
    }
  }

  /// Start a sequence
  Future<void> startSequence(Sequence sequence) async {
    if (_status == SequenceExecutorStatus.running) {
      debugPrint('BufferSequenceExecutor: Sequence already running');
      return;
    }

    debugPrint('BufferSequenceExecutor: Starting sequence "${sequence.name}"');

    _currentSequence = sequence;
    _currentStopIndex = -1;
    _navRetryCount = 0;
    _completedCommandCount = 0;
    _status = SequenceExecutorStatus.running;

    _callback.onSequenceStarted(sequence);

    // Build command list for the entire sequence
    final commands = _buildSequenceCommands(sequence);
    _totalCommandCount = commands.length;
    debugPrint('BufferSequenceExecutor: Loading $_totalCommandCount commands into buffer');

    // Load all commands into the relay buffer
    _bufferClient.loadCommands(commands, clearExisting: true);

    notifyListeners();
  }

  /// Build buffer commands for a sequence
  List<BufferCommand> _buildSequenceCommands(Sequence sequence) {
    final commands = <BufferCommand>[];

    // START waypoint - navigate here before starting tour
    if (sequence.startWaypoint != null && sequence.startWaypoint!.isNotEmpty) {
      debugPrint('BufferSequenceExecutor: Adding start waypoint: ${sequence.startWaypoint}');
      commands.add(BufferCommand.navigate(sequence.startWaypoint!));
    }

    // Intro text
    if (sequence.introText != null && sequence.introText!.isNotEmpty) {
      commands.add(BufferCommand.speak(sequence.introText!));
    }

    // Each stop
    for (final stop in sequence.stops) {
      // Navigate to waypoint
      commands.add(BufferCommand.navigate(stop.waypoint));

      // Arrival sound + announcement
      if (sequence.announceArrival) {
        commands.add(BufferCommand.sound('arrival'));
        commands.add(BufferCommand.speak('Arrived at ${stop.waypoint}'));
      }

      // Custom speak text
      if (stop.speakText != null && stop.speakText!.isNotEmpty) {
        commands.add(BufferCommand.speak(stop.speakText!));
      }

      // Display content
      if (stop.displayUrl != null && stop.displayUrl!.isNotEmpty) {
        commands.add(BufferCommand.display(
          stop.displayUrl!,
          durationMs: stop.displayDuration > 0 ? stop.displayDuration * 1000 : 0,
        ));
      }

      // Wait time
      if (stop.waitSeconds > 0) {
        commands.add(BufferCommand.wait(stop.waitSeconds * 1000));
      } else if (stop.displayDuration > 0) {
        commands.add(BufferCommand.wait(stop.displayDuration * 1000));
      }
    }

    // Outro text
    if (sequence.outroText != null && sequence.outroText!.isNotEmpty) {
      commands.add(BufferCommand.speak(sequence.outroText!));
    }

    // End waypoint
    if (sequence.endWaypoint != null && sequence.endWaypoint!.isNotEmpty) {
      commands.add(BufferCommand.navigate(sequence.endWaypoint!));
    }

    // Close display at end
    commands.add(BufferCommand.closeDisplay());

    return commands;
  }

  /// Stop the sequence
  void stopSequence() {
    if (_status != SequenceExecutorStatus.running &&
        _status != SequenceExecutorStatus.paused) {
      return;
    }

    debugPrint('BufferSequenceExecutor: Stopping sequence');

    _bufferClient.clear();
    _callback.onCloseDisplay();
    _callback.onSequenceStopped(currentStop, _currentStopIndex);

    _status = SequenceExecutorStatus.idle;
    _currentSequence = null;
    _currentStopIndex = -1;
    _navRetryCount = 0;
    _stopCountdown();

    notifyListeners();
  }

  /// Pause the sequence
  void pauseSequence() {
    if (_status != SequenceExecutorStatus.running) return;

    debugPrint('BufferSequenceExecutor: Pausing sequence');
    _bufferClient.pause();
    _status = SequenceExecutorStatus.paused;
    notifyListeners();
  }

  /// Resume the sequence
  void resumeSequence() {
    if (_status != SequenceExecutorStatus.paused) return;

    debugPrint('BufferSequenceExecutor: Resuming sequence');
    _bufferClient.resume();
    _status = SequenceExecutorStatus.running;
    notifyListeners();
  }

  /// Skip current command
  void skipCurrentCommand() {
    debugPrint('BufferSequenceExecutor: Skipping current command');
    _bufferClient.skip();
  }

  void _completeSequence() {
    debugPrint('BufferSequenceExecutor: Sequence completed');
    _status = SequenceExecutorStatus.completed;
    _stopCountdown();
    _callback.onSequenceCompleted();
    notifyListeners();

    // Reset after delay
    Future.delayed(const Duration(seconds: 3), () {
      _currentSequence = null;
      _currentStopIndex = -1;
      _status = SequenceExecutorStatus.idle;
      notifyListeners();
    });
  }

  void _failSequence(String reason) {
    debugPrint('BufferSequenceExecutor: Sequence failed: $reason');
    _bufferClient.clear();
    _status = SequenceExecutorStatus.failed;
    _stopCountdown();
    _callback.onSequenceFailed(reason);
    notifyListeners();
  }

  void _stopCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _countdownSeconds = 0;
  }

  @override
  void dispose() {
    _bufferClient.removeListener(_onBufferChanged);
    _countdownTimer?.cancel();
    super.dispose();
  }
}

/// Simplified sequence executor status
enum SequenceExecutorStatus {
  idle,
  running,
  paused,
  completed,
  failed,
}
