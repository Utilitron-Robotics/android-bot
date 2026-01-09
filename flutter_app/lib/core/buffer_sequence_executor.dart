import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  // Persistence key for reconnect recovery
  static const String _runningSequenceKey = 'buffer_running_sequence_id';

  // Current sequence state
  Sequence? _currentSequence;
  int _currentStopIndex = -1;
  SequenceExecutorStatus _status = SequenceExecutorStatus.idle;

  // Retry tracking (logic HERE, not in relay)
  int _navRetryCount = 0;
  static const int _maxNavRetries = 3;

  // Reconnect detection - track if we need to restore state
  bool _needsStateRestore = true;

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

  SequenceStop? get currentStop => _currentSequence != null &&
          _currentStopIndex >= 0 &&
          _currentStopIndex < _currentSequence!.stops.length
      ? _currentSequence!.stops[_currentStopIndex]
      : null;

  double get progress =>
      _currentSequence == null || _currentSequence!.stops.isEmpty
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
    // RECONNECT DETECTION: If buffer is running but we have no sequence, restore state
    if (_needsStateRestore &&
        state.current != null &&
        _currentSequence == null) {
      debugPrint(
          'BufferSequenceExecutor: Detected running buffer on reconnect, restoring state...');
      _restoreFromHeartbeat(state);
      return;
    }

    // Update phase based on current command
    if (state.current != null) {
      switch (state.current!.type) {
        case 'navigate':
          _currentPhase = SequencePhase.navigating;
          _countdownSeconds = 0;
          break;
        case 'speak':
          _currentPhase = SequencePhase.speaking;
          _countdownSeconds = 0;
          break;
        case 'display':
          _currentPhase = SequencePhase.displaying;
          _countdownSeconds = 0;
          break;
        case 'wait':
          _currentPhase = SequencePhase.waiting;
          // Calculate countdown from elapsed time
          if (_currentWaitDurationMs > 0) {
            final remainingMs =
                _currentWaitDurationMs - state.current!.elapsedMs;
            final newCountdown = (remainingMs / 1000).ceil().clamp(0, 9999);
            // Only send update if countdown changed (avoid flooding)
            if (newCountdown != _countdownSeconds) {
              _countdownSeconds = newCountdown;
              // Send countdown to tablet for floating timer overlay
              _bufferClient.updateCountdown(_countdownSeconds,
                  label: 'Next stop in');
            }
          }
          break;
        default:
          debugPrint(
              'BufferSequenceExecutor: Unknown command type: ${state.current!.type}');
          break;
      }
    } else {
      if (_countdownSeconds > 0) {
        _countdownSeconds = 0;
        // Clear countdown on tablet
        _bufferClient.updateCountdown(0);
      }
    }

    // Check for paused state
    if (state.paused && _status == SequenceExecutorStatus.running) {
      _status = SequenceExecutorStatus.paused;
    } else if (!state.paused && _status == SequenceExecutorStatus.paused) {
      _status = SequenceExecutorStatus.running;
    }

    // CRITICAL: Notify listeners on EVERY heartbeat so UI updates with phase/countdown changes
    // Without this, Flutter UI goes stale during tour execution!
    notifyListeners();
  }

  /// Restore executor state from heartbeat on reconnect
  Future<void> _restoreFromHeartbeat(BufferState state) async {
    debugPrint('BufferSequenceExecutor: Restoring from heartbeat...');

    // Mark reconnect time to ignore stale completion events
    _reconnectTimestamp = DateTime.now().millisecondsSinceEpoch;

    // Sync command counts from heartbeat to avoid skip-to-next issues
    // The relay's completed_count tells us how many commands finished
    _completedCommandCount = state.completedCount;
    debugPrint(
        'BufferSequenceExecutor: Synced completed count from relay: $_completedCommandCount');

    // Try to load the running sequence ID from preferences
    try {
      final prefs = await SharedPreferences.getInstance();
      final sequenceId = prefs.getString(_runningSequenceKey);

      if (sequenceId != null) {
        // Get sequence from SequenceManager
        final sequence = SequenceManager.instance.getSequence(sequenceId);
        if (sequence != null) {
          debugPrint(
              'BufferSequenceExecutor: Restored sequence "${sequence.name}" from preferences');
          _currentSequence = sequence;
          _status = state.paused
              ? SequenceExecutorStatus.paused
              : SequenceExecutorStatus.running;
          _needsStateRestore = false;

          // Rebuild total command count so completion detection works
          final commands = _buildSequenceCommands(sequence);
          _totalCommandCount = commands.length;
          debugPrint(
              'BufferSequenceExecutor: Rebuilt total count: $_totalCommandCount, completed: $_completedCommandCount');

          // Try to determine current stop from navigate command
          if (state.current?.type == 'navigate') {
            // Request current command details - we'll get waypoint from next heartbeat
            debugPrint(
                'BufferSequenceExecutor: Currently navigating, will sync stop index from next command event');
          }

          notifyListeners();
          return;
        }
      }
    } catch (e) {
      debugPrint('BufferSequenceExecutor: Error restoring state: $e');
    }

    // If we couldn't restore, mark as running but with unknown sequence
    // This allows the UI to show "Tour Running" even without full details
    if (state.current != null || state.pendingCount > 0) {
      debugPrint(
          'BufferSequenceExecutor: Buffer is running but sequence unknown, showing running state');
      _status = state.paused
          ? SequenceExecutorStatus.paused
          : SequenceExecutorStatus.running;
      _needsStateRestore = false;
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
        // Find the stop index for this waypoint (case-insensitive match)
        final waypointNorm = waypoint.toLowerCase().trim();
        for (int i = 0; i < _currentSequence!.stops.length; i++) {
          if (_currentSequence!.stops[i].waypoint.toLowerCase().trim() == waypointNorm) {
            debugPrint(
                'BufferSequenceExecutor: Found stop index $i for $waypoint');
            _currentStopIndex = i;
            _currentPhase = SequencePhase.navigating;
            break;
          }
        }
      }
    } else if (type == 'display') {
      _currentPhase = SequencePhase.displaying;
      _currentWaitDurationMs = 0;
    } else if (type == 'speak') {
      _currentPhase = SequencePhase.speaking;
      _currentWaitDurationMs = 0;
    } else if (type == 'wait') {
      _currentPhase = SequencePhase.waiting;
      // Capture wait duration for countdown display
      int? durationMs = cmd['duration_ms'] as int?;
      if (durationMs == null) {
        final data = cmd['data'] as Map<String, dynamic>?;
        durationMs = data?['duration_ms'] as int?;
      }
      _currentWaitDurationMs = durationMs ?? 0;
      _countdownSeconds = (_currentWaitDurationMs / 1000).ceil();
      debugPrint(
          'BufferSequenceExecutor: Wait started, duration=${_currentWaitDurationMs}ms, countdown=$_countdownSeconds');
    } else if (type == 'sound') {
      // Sound command - just acknowledge it
      debugPrint('BufferSequenceExecutor: Playing sound');
      _currentPhase = SequencePhase.speaking; // Treat as speaking phase
      _currentWaitDurationMs = 0;
    } else {
      _currentWaitDurationMs = 0;
      debugPrint('BufferSequenceExecutor: Unknown command type: $type');
    }
    notifyListeners();
  }

  void _onCommandCompleted(CommandResult result) {
    // Filter out stale events from before reconnect
    // Give 2 second grace period after reconnect to avoid processing buffered events
    final timeSinceReconnect =
        DateTime.now().millisecondsSinceEpoch - _reconnectTimestamp;
    if (_reconnectTimestamp > 0 && timeSinceReconnect < 2000) {
      debugPrint(
          'BufferSequenceExecutor: Ignoring completion event within ${timeSinceReconnect}ms of reconnect');
      return;
    }

    // Prevent duplicate processing - check if we're already beyond total
    if (_totalCommandCount > 0 && _completedCommandCount >= _totalCommandCount) {
      debugPrint(
          'BufferSequenceExecutor: Ignoring duplicate completion - already at $_completedCommandCount/$_totalCommandCount');
      return;
    }

    _completedCommandCount++;

    // Clamp to prevent impossible states
    if (_completedCommandCount > _totalCommandCount && _totalCommandCount > 0) {
      debugPrint(
          'BufferSequenceExecutor: WARNING - Completed count exceeded total! Clamping $_completedCommandCount to $_totalCommandCount');
      _completedCommandCount = _totalCommandCount;
    }

    debugPrint(
        'BufferSequenceExecutor: Command completed: ${result.result} ($_completedCommandCount/$_totalCommandCount)');

    // Special handling for loop command
    if (result.commandId.contains('loop')) {
      if (result.isSuccess && _currentSequence != null && _currentSequence!.loop) {
        debugPrint('BufferSequenceExecutor: Loop command completed - restarting tour immediately');

        // Restart tour immediately - no waiting for visitors
        final commands = _buildSequenceCommands(_currentSequence!, startIndex: 0);
        _totalCommandCount = commands.length;
        _completedCommandCount = 0;
        _currentStopIndex = -1;
        _bufferClient.loadCommands(commands, clearExisting: true);

        _status = SequenceExecutorStatus.running;
        notifyListeners();
        return;
      } else {
        debugPrint('BufferSequenceExecutor: Loop command failed or loop disabled, ending tour');
        // Fall through to normal completion handling
      }
    }

    // Special handling: arrived at start, now await visitor
    if (_awaitingVisitorAtStart && result.isSuccess) {
      debugPrint('BufferSequenceExecutor: Arrived at start - entering awaitingVisitor phase');
      _currentPhase = SequencePhase.awaitingVisitor;
      // Stay in running state but don't load more commands
      // UI will show START TOUR overlay, call resumeFromVisitor() when pressed
      notifyListeners();
      return;
    }

    // Handle navigation failures with retry logic (ALL in Flutter)
    if (result.isFailure) {
      // Check if this was a navigation failure
      // Use _currentPhase as it's updated by both start events and heartbeats
      if (_currentPhase == SequencePhase.navigating) {
        _handleNavigationFailure(result);
        return;
      }
    }

    // Check for sequence completion
    if (result.isSuccess || result.result == 'cancelled') {
      _navRetryCount = 0; // Reset retry count on success/cancel
      // Check completion immediately - we track command count locally, no need to wait for heartbeat
      _checkSequenceCompletion();
    }

    notifyListeners();
  }

  /// Handle navigation failure with retry logic
  void _handleNavigationFailure(CommandResult result) {
    final currentStop = this.currentStop;
    if (currentStop == null) return;

    _navRetryCount++;

    if (_navRetryCount > _maxNavRetries) {
      debugPrint(
          'BufferSequenceExecutor: Max retries exceeded, failing sequence');
      _failSequence('Navigation failed after $_maxNavRetries retries');
      return;
    }

    debugPrint(
        'BufferSequenceExecutor: Retrying navigation ($_navRetryCount/$_maxNavRetries)');

    // Speak retry message
    _callback.onSpeak('Path blocked. Retrying navigation.');

    // Clear existing commands (which would include the "Arrived" speech for the failed nav)
    // and reload starting from current stop
    final commands = _buildSequenceCommands(_currentSequence!,
        startIndex: _currentStopIndex);
    _bufferClient.loadCommands(commands, clearExisting: true);
  }

  // Track completed commands to detect sequence end without relying on stale heartbeat
  int _completedCommandCount = 0;
  int _totalCommandCount = 0;

  // Track current wait duration for countdown display
  int _currentWaitDurationMs = 0;

  // Track reconnect to avoid processing stale events
  int _reconnectTimestamp = 0;

  /// Check if sequence is complete
  void _checkSequenceCompletion() {
    final state = _bufferClient.state;

    debugPrint(
        'BufferSequenceExecutor: Checking completion - pending=${state.pendingCount}, current=${state.current?.type}, paused=${state.paused}, status=$_status, completed=$_completedCommandCount/$_totalCommandCount');

    // Method 1: Check heartbeat state (may be stale)
    if (state.pendingCount == 0 && state.current == null && !state.paused) {
      if (_status == SequenceExecutorStatus.running) {
        debugPrint(
            'BufferSequenceExecutor: Completing via heartbeat state (pending=0, current=null)');
        _completeSequence();
        return;
      }
    }

    // Method 2: Check local command tracking (more reliable)
    if (_totalCommandCount > 0 &&
        _completedCommandCount >= _totalCommandCount) {
      if (_status == SequenceExecutorStatus.running) {
        debugPrint(
            'BufferSequenceExecutor: Completing via command count ($_completedCommandCount/$_totalCommandCount)');
        _completeSequence();
        return;
      }
    }
  }

  // Track if we're waiting for visitor at start
  bool _awaitingVisitorAtStart = false;

  /// True if currently waiting for visitor tap at start
  bool get isAwaitingVisitor => _awaitingVisitorAtStart;

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
    _needsStateRestore = false; // We have fresh state, no restore needed
    _reconnectTimestamp = 0; // Clear reconnect filter for fresh sequence
    _awaitingVisitorAtStart = false;

    // Save sequence ID for reconnect recovery
    _saveRunningSequenceId(sequence.id);

    _callback.onSequenceStarted(sequence);

    // Check if we should await visitor at start
    if (sequence.awaitVisitorAtStart &&
        sequence.startWaypoint != null &&
        sequence.startWaypoint!.isNotEmpty) {
      debugPrint('BufferSequenceExecutor: Await visitor mode - navigating to start first');

      // Phase 1: Just navigate to start waypoint
      final navCommand = BufferCommand.navigate(sequence.startWaypoint!);
      _totalCommandCount = 1; // Just the nav for now

      final loaded = await _bufferClient.loadCommands([navCommand], clearExisting: true);
      if (!loaded) {
        debugPrint('BufferSequenceExecutor: ✗ Failed to load nav command - aborting');
        _status = SequenceExecutorStatus.idle;
        _currentSequence = null;
        notifyListeners();
        return;
      }

      // Will enter awaitingVisitor phase when nav completes (in _onCommandCompleted)
      _awaitingVisitorAtStart = true;
      debugPrint('BufferSequenceExecutor: ✓ Nav to start loaded, will await visitor on arrival');
      notifyListeners();
      return;
    }

    // Normal start - load all commands at once
    final commands = _buildSequenceCommands(sequence);
    _totalCommandCount = commands.length;
    debugPrint(
        'BufferSequenceExecutor: Loading $_totalCommandCount commands into buffer');

    // Load all commands into the relay buffer and WAIT for confirmation
    final loaded = await _bufferClient.loadCommands(commands, clearExisting: true);
    if (!loaded) {
      debugPrint('BufferSequenceExecutor: ✗ Failed to confirm command load - aborting');
      _status = SequenceExecutorStatus.idle;
      _currentSequence = null;
      notifyListeners();
      return;
    }

    debugPrint('BufferSequenceExecutor: ✓ All commands confirmed - starting sequence');
    notifyListeners();
  }

  /// Resume from visitor wait - called when START TOUR button is pressed
  Future<void> resumeFromVisitor() async {
    if (!_awaitingVisitorAtStart || _currentSequence == null) {
      debugPrint('BufferSequenceExecutor: resumeFromVisitor called but not awaiting');
      return;
    }

    debugPrint('BufferSequenceExecutor: Visitor triggered! Loading tour commands...');
    _awaitingVisitorAtStart = false;
    _currentPhase = SequencePhase.navigating;

    // Load the rest of the sequence (skip nav to start since we're already there)
    final commands = _buildSequenceCommands(_currentSequence!, skipNavToStart: true);
    _totalCommandCount = commands.length;
    _completedCommandCount = 0;

    final loaded = await _bufferClient.loadCommands(commands, clearExisting: true);
    if (!loaded) {
      debugPrint('BufferSequenceExecutor: ✗ Failed to load tour commands');
      _status = SequenceExecutorStatus.failed;
      notifyListeners();
      return;
    }

    debugPrint('BufferSequenceExecutor: ✓ Tour commands loaded, starting!');
    notifyListeners();
  }

  /// Save running sequence ID for reconnect recovery
  Future<void> _saveRunningSequenceId(String? sequenceId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (sequenceId != null) {
        await prefs.setString(_runningSequenceKey, sequenceId);
        debugPrint(
            'BufferSequenceExecutor: Saved running sequence ID: $sequenceId');
      } else {
        await prefs.remove(_runningSequenceKey);
        debugPrint('BufferSequenceExecutor: Cleared running sequence ID');
      }
    } catch (e) {
      debugPrint('BufferSequenceExecutor: Error saving sequence ID: $e');
    }
  }

  /// Build buffer commands for a sequence
  ///
  /// Command execution order:
  /// 1. Navigate to start waypoint (if set, unless skipNavToStart)
  /// 2. Speak intro text (if set)
  /// 3. For each stop:
  ///    a. Navigate to waypoint
  ///    b. Display content (custom URL or default POI name) - stays up entire visit
  ///    c. Arrival sound + announcement (if enabled)
  ///    d. Custom speak text (if any)
  ///    e. Wait timer AFTER speech completes (additional dwell time)
  /// 4. Speak outro text (if set)
  /// 5. Navigate to end waypoint (if set)
  ///
  /// The display stays up from arrival until next navigation starts.
  /// Wait timer does NOT cut off speech - it waits AFTER speech completes.
  List<BufferCommand> _buildSequenceCommands(Sequence sequence,
      {int startIndex = 0, bool skipNavToStart = false}) {
    final commands = <BufferCommand>[];

    // DEBUG: Log all stops and their config
    debugPrint(
        'BufferSequenceExecutor: Building commands for ${sequence.stops.length} stops (starting from index $startIndex):');
    for (int i = startIndex; i < sequence.stops.length; i++) {
      final s = sequence.stops[i];
      debugPrint(
          '  Stop $i: ${s.waypoint} - display=${s.displayUrl?.isNotEmpty == true}, speak=${s.speakText?.isNotEmpty == true}, wait=${s.waitSeconds}s');
    }

    // START waypoint - navigate here before starting tour
    // (Robot will navigate to start even if human moved it)
    // Skip if we already navigated there (awaitVisitor mode)
    if (!skipNavToStart &&
        startIndex == 0 &&
        sequence.startWaypoint != null &&
        sequence.startWaypoint!.isNotEmpty) {
      debugPrint(
          'BufferSequenceExecutor: Adding start waypoint: ${sequence.startWaypoint}');
      commands.add(BufferCommand.navigate(sequence.startWaypoint!));
    }

    // Intro text (spoken at start position after arriving)
    // This is a regular stop - no waiting for visitors, just speak and go!
    // Relay awaits TTS completion via callback - no more guessing duration!
    if (startIndex == 0 &&
        sequence.introText != null &&
        sequence.introText!.isNotEmpty) {
      commands.add(BufferCommand.speak(sequence.introText!));
      debugPrint('BufferSequenceExecutor: Intro text queued (TTS awaits completion, no wait needed)');
    }

    // Each stop
    for (int i = startIndex; i < sequence.stops.length; i++) {
      final stop = sequence.stops[i];
      // 1. Navigate to waypoint
      commands.add(BufferCommand.navigate(stop.waypoint));

      // 2. Display content - ALWAYS show something for the entire visit
      // durationMs=0 means "show until explicitly cleared or next display command"
      if (stop.displayUrl != null && stop.displayUrl!.isNotEmpty) {
        // Custom display URL (website, image, video)
        commands.add(BufferCommand.display(stop.displayUrl!, durationMs: 0));
      } else {
        // Default display - show POI name/company branding
        commands
            .add(BufferCommand.displayDefault(stop.waypoint, durationMs: 0));
      }

      // 3. Arrival sound + announcement (if enabled)
      // Plays while display is showing - TTS awaits completion, no extra wait needed
      if (sequence.announceArrival) {
        commands.add(BufferCommand.sound('arrival'));
        // Use delivery-specific announcement if this is a delivery sequence
        final isDelivery = sequence.name.toLowerCase().contains('delivery') ||
            sequence.id.toLowerCase().contains('delivery');
        final announcement = isDelivery
            ? 'Your delivery has arrived at ${stop.waypoint}'
            : 'Arrived at ${stop.waypoint}';
        commands.add(BufferCommand.speak(announcement));
      }

      // 4. Custom speak text (plays while display is showing)
      // Speech completes fully before wait timer starts
      if (stop.speakText != null && stop.speakText!.isNotEmpty) {
        commands.add(BufferCommand.speak(stop.speakText!));
      }

      // 5. Wait timer AFTER all speech completes
      // This is ADDITIONAL dwell time after speech finishes (not concurrent)
      // Display continues showing during wait
      if (stop.waitSeconds > 0) {
        commands.add(BufferCommand.wait(stop.waitSeconds * 1000));
      } else if (stop.displayDuration > 0) {
        // Fallback to displayDuration if no explicit wait
        commands.add(BufferCommand.wait(stop.displayDuration * 1000));
      }
    }

    // Outro text (spoken before going to end)
    if (sequence.outroText != null && sequence.outroText!.isNotEmpty) {
      commands.add(BufferCommand.speak(sequence.outroText!));
    }

    // Handle looping
    if (sequence.loop) {
      debugPrint('BufferSequenceExecutor: Tour set to loop - will restart');

      // If there's an end waypoint, go there first
      if (sequence.endWaypoint != null && sequence.endWaypoint!.isNotEmpty) {
        commands.add(BufferCommand.navigate(sequence.endWaypoint!));
      }

      // Rest at end - wait AFTER arriving at end waypoint
      if (sequence.restAtEndSeconds > 0) {
        debugPrint(
            'BufferSequenceExecutor: Rest at end (after arrival): ${sequence.restAtEndSeconds}s');
        commands.add(BufferCommand.wait(sequence.restAtEndSeconds * 1000));
      } else {
        // Brief wait at end waypoint if no rest configured
        commands.add(BufferCommand.wait(5000));
      }

      // Navigate back to start to begin loop
      if (sequence.startWaypoint != null && sequence.startWaypoint!.isNotEmpty) {
        commands.add(BufferCommand.navigate(sequence.startWaypoint!));
        // Wait a moment at start position before restarting
        commands.add(BufferCommand.wait(3000));
      }

      // Add loop command to restart the sequence
      commands.add(BufferCommand.loop());
    } else {
      // Non-looping tour - navigate to end and close
      if (sequence.endWaypoint != null && sequence.endWaypoint!.isNotEmpty) {
        commands.add(BufferCommand.navigate(sequence.endWaypoint!));

        // Rest at end - wait AFTER arriving at end waypoint
        if (sequence.restAtEndSeconds > 0) {
          debugPrint(
              'BufferSequenceExecutor: Rest at end (after arrival): ${sequence.restAtEndSeconds}s');
          commands.add(BufferCommand.wait(sequence.restAtEndSeconds * 1000));
        }
      }

      // Close display at end
      commands.add(BufferCommand.closeDisplay());
    }

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

    // Stop sequence mode on tablet - unlocks screen
    _bufferClient.stopSequenceMode();

    // Clear saved sequence ID - no longer running
    _saveRunningSequenceId(null);

    _status = SequenceExecutorStatus.idle;
    _currentSequence = null;
    _currentStopIndex = -1;
    _navRetryCount = 0;
    _awaitingVisitorAtStart = false;
    _stopCountdown();
    _needsStateRestore = true; // Ready to restore on next reconnect

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

    // Stop sequence mode on tablet - unlocks screen
    _bufferClient.stopSequenceMode();

    // Clear saved sequence ID - no longer running
    _saveRunningSequenceId(null);

    notifyListeners();

    // Reset after delay
    Future.delayed(const Duration(seconds: 3), () {
      _currentSequence = null;
      _currentStopIndex = -1;
      _status = SequenceExecutorStatus.idle;
      _needsStateRestore = true; // Ready to restore on next reconnect
      notifyListeners();
    });
  }

  void _failSequence(String reason) {
    debugPrint('BufferSequenceExecutor: Sequence failed: $reason');
    _bufferClient.clear();
    _status = SequenceExecutorStatus.failed;
    _stopCountdown();
    _callback.onSequenceFailed(reason);

    // Attempt recovery to end/start waypoint if available
    // User requested: "when all fails got to Pile or last waypoint"
    if (_currentSequence != null) {
      String? recoveryWaypoint = _currentSequence!.endWaypoint;
      if (recoveryWaypoint == null || recoveryWaypoint.isEmpty) {
        recoveryWaypoint = _currentSequence!.startWaypoint;
      }

      if (recoveryWaypoint != null && recoveryWaypoint.isNotEmpty) {
        debugPrint(
            'BufferSequenceExecutor: Attempting recovery navigation to $recoveryWaypoint');
        // Load recovery commands - just go there and close display
        _bufferClient.loadCommands([
          BufferCommand.speak(
              'Sequence failed. Returning to $recoveryWaypoint.'),
          BufferCommand.navigate(recoveryWaypoint),
          BufferCommand.closeDisplay(),
        ], clearExisting: true);
      }
    }

    // Stop sequence mode on tablet - unlocks screen
    _bufferClient.stopSequenceMode();

    // Clear saved sequence ID - no longer running
    _saveRunningSequenceId(null);
    _needsStateRestore = true; // Ready to restore on next reconnect

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
