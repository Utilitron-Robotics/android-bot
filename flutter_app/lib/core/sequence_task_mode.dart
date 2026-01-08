import 'dart:async';
import 'package:flutter/material.dart';
import 'task_mode.dart';
import 'sequence_mode.dart';

/// Navigation status codes from robot
class NavStatus {
  static const int idle = 600;
  static const int moving = 601;
  static const int cancelled = 602;
  static const int arrived = 603;
  static const int failed = 604;
  static const int standby = 605;
}

/// Sequence execution phase
enum SequenceTaskPhase {
  starting('Starting sequence...', Icons.play_arrow),
  intro('Playing intro...', Icons.mic),
  navigating('Navigating...', Icons.navigation),
  arriving('Arriving...', Icons.location_on),
  speaking('Speaking...', Icons.volume_up),
  displaying('Displaying...', Icons.tv),
  waiting('Waiting...', Icons.timer),
  outro('Playing outro...', Icons.mic),
  ending('Ending sequence...', Icons.flag),
  complete('Complete', Icons.check_circle);

  final String label;
  final IconData icon;
  const SequenceTaskPhase(this.label, this.icon);
}

/// Callback interface for sequence execution
abstract class SequenceTaskCallback {
  void onSpeak(String text);
  void onArrivalAnnouncement(String waypoint,
      {bool isDelivery = false}); // Beep + speak arrival
  void onDisplay(String url, int durationSeconds);
  void onDisplayDefault(String waypoint);
  void onCloseDisplay();
  Future<void> onNavigate(String waypoint);
  void onSequenceStarted(Sequence sequence);
  void onSequenceStopped(SequenceStop? currentStop, int stopIndex);
  void onSequenceCompleted();
  void onSequenceFailed(String reason);
  void onStopArrived(SequenceStop stop, int stopIndex);
}

/// Sequence implemented as a TaskMode with command retry
class SequenceTaskMode extends TaskMode {
  final Sequence sequence;
  final SequenceTaskCallback callback;

  // Current state
  int _currentStopIndex = -1;
  SequenceTaskPhase _phase = SequenceTaskPhase.starting;
  Timer? _waitTimer;
  Timer? _countdownTimer;

  // Countdown tracking
  int _countdownSeconds = 0;
  int _phaseDurationSeconds = 0;

  // Navigation retry tracking (Delegated to CommandManager)
  String? _pendingWaypoint;
  bool _waitingForArrival = false;
  // NOTE: Manual retry logic (_retryNavigation, _navRetryCount) removed.
  // We rely on CommandManager's built-in retry mechanism (maxRetries: 3)
  // to avoid fighting with the task engine's state machine.

  bool _hasStartedMoving =
      false; // Track if robot actually started moving (601)

  SequenceTaskMode({
    required this.sequence,
    required this.callback,
  }) : super(
          id: sequence.id,
          name: sequence.name,
          type: 'sequence',
        );

  /// Override to add listener for command timeouts
  @override
  void setCommandManager(CommandManager manager) {
    super.setCommandManager(manager);
    manager.addListener(_onCommandManagerChanged);
  }

  /// Handle command manager updates (timeouts, failures)
  void _onCommandManagerChanged() {
    final cmd = currentCommand;
    if (cmd == null || !_waitingForArrival) return;

    // Delegate final failure handling to CommandManager
    if (cmd.type == 'navigate' && cmd.status == CommandStatus.failed) {
      debugPrint(
          'SequenceTaskMode: Navigation command ${cmd.id} failed finally');
      fail('Navigation failed after retries');
    }
  }

  // Getters
  int get currentStopIndex => _currentStopIndex;
  SequenceTaskPhase get phase => _phase;
  int get countdownSeconds => _countdownSeconds;
  int get phaseDurationSeconds => _phaseDurationSeconds;

  SequenceStop? get currentStop =>
      _currentStopIndex >= 0 && _currentStopIndex < sequence.stops.length
          ? sequence.stops[_currentStopIndex]
          : null;

  @override
  double get progress => sequence.stops.isEmpty
      ? 0.0
      : (_currentStopIndex + 1) / sequence.stops.length;

  @override
  String get currentStepDescription {
    final stop = currentStop;
    if (stop == null) {
      return _phase.label;
    }
    return '${_phase.label} - ${stop.waypoint} (${_currentStopIndex + 1}/${sequence.stops.length})';
  }

  /// Update phase with countdown
  void _setPhase(SequenceTaskPhase phase, int durationSeconds) {
    _phase = phase;
    _phaseDurationSeconds = durationSeconds;
    _countdownSeconds = durationSeconds;

    _countdownTimer?.cancel();
    if (durationSeconds > 0) {
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_countdownSeconds > 0) {
          _countdownSeconds--;
          notifyListeners();
        } else {
          timer.cancel();
        }
      });
    }
    notifyListeners();
  }

  void _stopCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _countdownSeconds = 0;
    _phaseDurationSeconds = 0;
  }

  @override
  Future<bool> onStart() async {
    debugPrint(
        'SequenceTaskMode: Starting sequence "${sequence.name}" with ${sequence.stops.length} stops');
    _currentStopIndex = -1;
    _waitingForArrival = false;
    _hasStartedMoving = false; // Reset moving state

    _setPhase(SequenceTaskPhase.starting, 2);
    callback.onSequenceStarted(sequence);

    // Play intro if configured
    if (sequence.introText != null && sequence.introText!.isNotEmpty) {
      _setPhase(SequenceTaskPhase.intro,
          _estimateTtsDuration(sequence.introText!).inSeconds);
      callback.onSpeak(sequence.introText!);
      await Future.delayed(_estimateTtsDuration(sequence.introText!));
    }

    // Navigate to first stop (fromStart=true since we're still in 'starting' status)
    _navigateToNextStop(fromStart: true);
    return true;
  }

  @override
  Future<void> onStop() async {
    _waitTimer?.cancel();
    _stopCountdown();
    _waitingForArrival = false;
    commandManager?.removeListener(_onCommandManagerChanged);
    callback.onCloseDisplay();
    callback.onSequenceStopped(currentStop, _currentStopIndex);
  }

  @override
  Future<void> onPause() async {
    _waitTimer?.cancel();
    _waitingForArrival = false;
    // Keep display up while paused
  }

  @override
  Future<void> onResume() async {
    // Resume navigation if we were waiting for arrival
    if (_pendingWaypoint != null) {
      _navigateToWaypoint(_pendingWaypoint!);
    }
  }

  @override
  void onComplete() {
    _setPhase(SequenceTaskPhase.complete, 0);
    commandManager?.removeListener(_onCommandManagerChanged);
    callback.onSequenceCompleted();
  }

  @override
  void onFail(String reason) {
    commandManager?.removeListener(_onCommandManagerChanged);
    callback.onSequenceFailed(reason);
  }

  /// Handle robot arrival at waypoint
  @override
  void onArrived(String waypoint) {
    debugPrint(
        'SequenceTaskMode: onArrived($waypoint) - phase=$_phase, stopIndex=$_currentStopIndex, waiting=$_waitingForArrival, isRunning=$isRunning, status=$status');

    // Check if we should process this arrival
    // We process if: (a) running and waiting, OR (b) was waiting but sequence just failed
    final wasWaiting = _waitingForArrival;
    final shouldProcess = (isRunning && wasWaiting) ||
        (wasWaiting &&
            (status == TaskStatus.failed || status == TaskStatus.cancelled));

    if (!shouldProcess) {
      debugPrint(
          'SequenceTaskMode: Ignoring arrival - shouldProcess=false (running=$isRunning, waiting=$wasWaiting, status=$status)');
      return;
    }

    final stop = currentStop;
    if (stop == null) {
      debugPrint(
          'SequenceTaskMode: No current stop at index $_currentStopIndex');
      return;
    }

    if (stop.waypoint == waypoint || _pendingWaypoint == waypoint) {
      debugPrint(
          'SequenceTaskMode: Processing arrival at ${stop.waypoint} (even if failed - still execute actions)');
      _waitingForArrival = false;
      _pendingWaypoint = null;
      _hasStartedMoving = false; // Reset for next navigation

      // Mark navigation command as completed
      if (currentCommand != null) {
        commandManager?.commandCompleted(currentCommand!.id);
      }

      // Execute stop actions even if sequence technically failed
      // This ensures user sees the content at this waypoint
      final wasFailed =
          status == TaskStatus.failed || status == TaskStatus.cancelled;
      if (wasFailed) {
        debugPrint(
            'SequenceTaskMode: Executing actions despite failed status (late arrival recovery)');
      }

      _executeStopActions();
    } else {
      debugPrint(
          'SequenceTaskMode: Waypoint mismatch - expected ${stop.waypoint} or $_pendingWaypoint, got $waypoint');
    }
  }

  /// Handle navigation status change
  @override
  void onNavStatus(int status) {
    debugPrint(
        'SequenceTaskMode: Nav status $status (waiting=$_waitingForArrival)');

    if (!isRunning) return;

    // STRICT STATE MACHINE: Only process nav status if we are actually navigating
    // This prevents stale events (e.g., from a previous task cancellation) from
    // impacting the current task state.
    if (_phase != SequenceTaskPhase.navigating &&
        _phase != SequenceTaskPhase.starting) {
      debugPrint(
          'SequenceTaskMode: Ignoring nav status $status - not in navigating/starting phase (current: $_phase)');
      return;
    }

    switch (status) {
      case NavStatus.moving:
        // Robot started moving - acknowledge the command to prevent timeout
        _hasStartedMoving = true; // NOW 602 events count as real failures
        if (currentCommand != null) {
          debugPrint(
              'SequenceTaskMode: Acknowledging nav command ${currentCommand!.id} (robot moving)');
          commandManager?.acknowledgeCommand(currentCommand!.id);
          commandManager?.commandExecuting(currentCommand!.id);
        }
        break;

      case NavStatus.arrived:
        // Use pending waypoint if set, otherwise fall back to current stop waypoint
        final arrivedAt = _pendingWaypoint ?? currentStop?.waypoint;
        if (arrivedAt != null) {
          debugPrint(
              'SequenceTaskMode: Nav 603 arrived - calling onArrived($arrivedAt)');
          onArrived(arrivedAt);
        } else {
          debugPrint(
              'SequenceTaskMode: Nav 603 but no pending waypoint or current stop!');
        }
        break;

      case NavStatus.failed:
        if (_waitingForArrival && _pendingWaypoint != null) {
          debugPrint(
              'SequenceTaskMode: Navigation reported failure (604) - delegating to CommandManager');
          // We let the CommandManager handle the retry logic based on the failed status update
          // DO NOT manually retry here
          if (currentCommand != null) {
            // This will trigger CommandManager's retry logic if retries remain
            commandManager?.commandFailed(
                currentCommand!.id, "Robot reported navigation failure (604)");
          }
        }
        break;

      case NavStatus.cancelled:
        // Only process cancellation if we are actively waiting for arrival
        // AND we are in the navigating phase (checked above)
        if (_waitingForArrival) {
          // CRITICAL: Only count 602 as a real failure if robot actually started moving (saw 601)
          // The first 602 after sending a POI command is EXPECTED - robot cancels previous task
          if (!_hasStartedMoving) {
            debugPrint(
                'SequenceTaskMode: Ignoring 602 - robot never started moving (expected cancel of previous task)');
            break;
          }
          debugPrint(
              'SequenceTaskMode: Navigation cancelled (after robot was moving)');

          if (currentCommand != null) {
            // This will trigger CommandManager's retry logic if retries remain
            commandManager?.commandFailed(currentCommand!.id,
                "Robot reported navigation cancellation (602)");
          }
        }
        break;
    }
  }

  /// Navigate to next stop
  /// [fromStart] - skip running check when called from onStart() since status is still 'starting'
  void _navigateToNextStop({bool fromStart = false}) {
    if (!fromStart && !isRunning) return;

    _currentStopIndex++;

    if (_currentStopIndex >= sequence.stops.length) {
      if (sequence.loop) {
        _currentStopIndex = 0;
      } else {
        _completeSequence();
        return;
      }
    }

    final stop = currentStop;
    if (stop != null) {
      _navigateToWaypoint(stop.waypoint);
    }
  }

  /// Navigate to a specific waypoint with tracking
  Future<void> _navigateToWaypoint(String waypoint) async {
    debugPrint('SequenceTaskMode: Navigating to $waypoint');
    _setPhase(SequenceTaskPhase.navigating, 0);
    _pendingWaypoint = waypoint;
    _waitingForArrival = true;
    _hasStartedMoving =
        false; // Reset - 602 before 601 is expected (cancelling previous task)

    // Queue the navigation command WITH retries
    // Delegate retry logic to CommandManager
    final cmd = queueCommand(
      type: 'navigate',
      payload: {'waypoint': waypoint},
      maxRetries: 3, // Allow CommandManager to retry up to 3 times
    );

    if (cmd != null) {
      debugPrint('SequenceTaskMode: Navigation command queued (id=${cmd.id})');
    }

    // Also call the callback directly for immediate execution
    await callback.onNavigate(waypoint);
    notifyListeners();
  }

  /// Execute actions at current stop
  Future<void> _executeStopActions() async {
    final stop = currentStop;
    if (stop == null) {
      debugPrint(
          'SequenceTaskMode: _executeStopActions - NO CURRENT STOP! index=$_currentStopIndex');
      return;
    }

    debugPrint(
        'SequenceTaskMode: Executing actions at ${stop.waypoint} (isRunning=$isRunning, status=$status)');

    try {
      _setPhase(SequenceTaskPhase.arriving, 1);
      callback.onStopArrived(stop, _currentStopIndex);

      // Display content first
      if (stop.displayUrl != null && stop.displayUrl!.isNotEmpty) {
        _setPhase(SequenceTaskPhase.displaying,
            stop.displayDuration > 0 ? stop.displayDuration : 10);
        callback.onDisplay(stop.displayUrl!, stop.displayDuration);
      } else {
        callback.onDisplayDefault(stop.waypoint);
      }

      await Future.delayed(const Duration(milliseconds: 500));

      // Announce arrival if enabled
      if (sequence.announceArrival) {
        final arrivalText = 'Arrived at ${stop.waypoint}';
        final duration = _estimateTtsDuration(arrivalText);
        _setPhase(SequenceTaskPhase.speaking, duration.inSeconds);
        callback.onSpeak(arrivalText);
        await Future.delayed(duration + const Duration(milliseconds: 500));
      }

      // Speak custom text
      if (stop.speakText != null && stop.speakText!.isNotEmpty) {
        final duration = _estimateTtsDuration(stop.speakText!);
        _setPhase(SequenceTaskPhase.speaking, duration.inSeconds);
        callback.onSpeak(stop.speakText!);
        await Future.delayed(duration);
      }

      // Wait time
      final minMediaTime =
          (stop.displayUrl != null && stop.displayUrl!.isNotEmpty) ? 10 : 0;
      final waitTime = stop.waitSeconds > 0
          ? stop.waitSeconds
          : (stop.displayDuration > 0 ? stop.displayDuration : minMediaTime);

      if (waitTime > 0) {
        _setPhase(SequenceTaskPhase.waiting, waitTime);
        _waitTimer = Timer(Duration(seconds: waitTime), () {
          // Continue even if status is technically failed (recovery mode)
          if (isRunning || status == TaskStatus.failed) {
            _navigateToNextStop();
          } else {
            debugPrint('SequenceTaskMode: Not continuing - status=$status');
          }
        });
      } else {
        _navigateToNextStop();
      }
    } catch (e, stack) {
      debugPrint('SequenceTaskMode: ERROR in _executeStopActions: $e');
      debugPrint('SequenceTaskMode: Stack: $stack');
      // Don't fail the whole sequence on action error - try to continue
      _navigateToNextStop();
    }
  }

  /// Complete the sequence (works for any mode: Tour, Delivery, Patrol, etc.)
  void _completeSequence() {
    _stopCountdown();

    // Play outro
    if (sequence.outroText != null && sequence.outroText!.isNotEmpty) {
      _setPhase(SequenceTaskPhase.outro,
          _estimateTtsDuration(sequence.outroText!).inSeconds);
      callback.onSpeak(sequence.outroText!);
    }

    // Navigate to end waypoint
    if (sequence.endWaypoint != null && sequence.endWaypoint!.isNotEmpty) {
      _setPhase(SequenceTaskPhase.ending, 0);
      callback.onNavigate(sequence.endWaypoint!);
    }

    // Mark complete after a delay
    Future.delayed(const Duration(seconds: 2), () {
      complete();
    });
  }

  /// Skip to next stop
  void skipToNextStop() {
    if (!isRunning && !isPaused) return;
    _waitTimer?.cancel();
    _waitingForArrival = false;
    callback.onCloseDisplay();

    if (isPaused) {
      resume();
    }

    _navigateToNextStop();
  }

  /// Estimate TTS duration
  Duration _estimateTtsDuration(String text) {
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final seconds = (words / 2.0).ceil();
    return Duration(seconds: seconds.clamp(2, 60));
  }

  @override
  void dispose() {
    _waitTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }
}

/// Adapter to convert old SequenceExecutorCallback to new SequenceTaskCallback
class SequenceCallbackAdapter implements SequenceTaskCallback {
  final SequenceExecutorCallback _oldCallback;

  SequenceCallbackAdapter(this._oldCallback);

  @override
  void onSpeak(String text) => _oldCallback.onSpeak(text);

  @override
  void onArrivalAnnouncement(String waypoint, {bool isDelivery = false}) =>
      _oldCallback.onArrivalAnnouncement(waypoint, isDelivery: isDelivery);

  @override
  void onDisplay(String url, int durationSeconds) =>
      _oldCallback.onDisplay(url, durationSeconds);

  @override
  void onDisplayDefault(String waypoint) =>
      _oldCallback.onDisplayDefault(waypoint);

  @override
  void onCloseDisplay() => _oldCallback.onCloseDisplay();

  @override
  Future<void> onNavigate(String waypoint) async =>
      _oldCallback.onNavigate(waypoint);

  @override
  void onSequenceStarted(Sequence sequence) =>
      _oldCallback.onSequenceStarted(sequence);

  @override
  void onSequenceStopped(SequenceStop? currentStop, int stopIndex) =>
      _oldCallback.onSequenceStopped(currentStop, stopIndex);

  @override
  void onSequenceCompleted() => _oldCallback.onSequenceCompleted();

  @override
  void onSequenceFailed(String reason) => _oldCallback.onSequenceFailed(reason);

  @override
  void onStopArrived(SequenceStop stop, int stopIndex) =>
      _oldCallback.onStopArrived(stop, stopIndex);
}
