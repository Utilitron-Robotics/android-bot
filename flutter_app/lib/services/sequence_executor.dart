import 'package:flutter/foundation.dart';
import '../core/sequence_mode.dart';
import '../core/robot_connection.dart';
import '../core/buffer_client.dart';
import 'audio_announcer.dart';

/// Executes sequences by connecting SequenceManager to RobotConnection
///
/// Supports two execution modes:
/// 1. BufferSequenceExecutor (preferred) - Commands sent to relay buffer, relay executes
/// 2. SequenceTaskMode (fallback) - Direct execution when no relay buffer available
class SequenceExecutor implements SequenceExecutorCallback {
  static final SequenceExecutor _instance = SequenceExecutor._internal();
  factory SequenceExecutor() => _instance;
  SequenceExecutor._internal();

  RobotConnection? _robot;
  BufferClient? _bufferClient;
  int _lastNavStatus = 0;
  String _lastGoal = '';

  // Waypoint tracking (retries handled by SequenceTaskMode or BufferSequenceExecutor)
  String? _pendingWaypoint;

  /// Initialize with robot connection
  void init(RobotConnection robot) {
    debugPrint(
        'SequenceExecutor.init: CALLED with robot=${robot.hashCode}, isConnected=${robot.isConnected}');
    _robot = robot;
    debugPrint('SequenceExecutor.init: _robot is now set');

    // Set callback first
    SequenceManager.instance.setCallback(this);
    debugPrint('SequenceExecutor.init: Callback set on SequenceManager');

    // Create BufferClient for relay buffer support
    // The buffer will receive heartbeats from relay if connected via relay
    _bufferClient = BufferClient(robot.client);
    debugPrint('SequenceExecutor.init: BufferClient created');

    // Enable buffer executor on SequenceManager
    // When sequences start, they'll use the buffer if available (heartbeats coming)
    SequenceManager.instance.setBufferExecutor(_bufferClient!);
    debugPrint('SequenceExecutor.init: BufferSequenceExecutor enabled');

    debugPrint(
        'SequenceExecutor.init: Verifying - SequenceManager._callback is ${SequenceManager.instance.status}');
  }

  /// Get the buffer client for external monitoring
  BufferClient? get bufferClient => _bufferClient;

  /// Check if executor is properly initialized
  bool get isInitialized => _robot != null;

  /// Call this when nav status changes (from RobotConnection status updates)
  void onNavStatusChanged(int navStatus, String goalName) {
    if (navStatus == _lastNavStatus && goalName == _lastGoal) return;

    _lastNavStatus = navStatus;
    _lastGoal = goalName;

    // Only process sequence-related nav changes if a sequence is actually running
    if (SequenceManager.instance.status != SequenceStatus.running) return;

    // Check if we arrived at a waypoint (status 603)
    // NOTE: Arrival events are routed through SequenceTaskMode via onNavStatus
    // We do NOT want to trigger SequenceManager.onArrived here, as it may conflict
    // with the active TaskMode logic. The TaskMode is responsible for sequence progression.
    /*
    if (navStatus == 603 && goalName.isNotEmpty) {
      debugPrint('SequenceExecutor: Detected arrival at $goalName');
      _pendingWaypoint = null;
      SequenceManager.instance.onArrived(goalName);
    }
    */

    // NOTE: Navigation retries are handled by SequenceTaskMode (via CommandManager), NOT here.
    // We defer all arrival handling to SequenceTaskMode to prevent duplicate event handling
    // and race conditions. The TaskMode is responsible for sequence progression.
  }

  // NOTE: _attemptRetry() removed - SequenceTaskMode handles all navigation retries

  /// Check if connection is stale and handle accordingly
  void checkStaleConnection() {
    final robot = _robot;
    if (robot == null) return;

    if (robot.isStale && _pendingWaypoint != null) {
      debugPrint(
          'SequenceExecutor: Connection stale, will retry when restored');
      // The retry will happen when connection comes back and we get nav status
    }
  }

  // === SequenceExecutorCallback Implementation ===

  @override
  void onSpeak(String text) {
    debugPrint('SequenceExecutor: Speaking: $text');
    AudioAnnouncer().speak(text);
  }

  @override
  void onArrivalAnnouncement(String waypoint, {bool isDelivery = false}) {
    debugPrint(
        'SequenceExecutor: Arrival announcement at $waypoint (delivery=$isDelivery)');
    AudioAnnouncer().announceArrival(waypoint, isDelivery: isDelivery);
  }

  @override
  void onDisplay(String url, int durationSeconds) {
    debugPrint(
        'SequenceExecutor: Displaying URL for ${durationSeconds}s: $url');
    _robot?.client.tabletDisplay(url);
  }

  @override
  void onDisplayDefault(String waypoint) {
    debugPrint('SequenceExecutor: Displaying default branding for: $waypoint');
    // Format waypoint name nicely
    final displayName = waypoint
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) =>
            word.isEmpty ? '' : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');

    // Show company branding with waypoint name
    // TODO: Make company name configurable
    const companyName = 'Welcome';
    final html = '''data:text/html,<html>
<head><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>
<body style="display:flex;flex-direction:column;align-items:center;justify-content:center;height:100vh;margin:0;background:linear-gradient(135deg,%231a1a2e 0%,%2316213e 100%);">
  <h1 style="color:white;font-size:48px;font-family:sans-serif;margin-bottom:20px;">$companyName</h1>
  <h2 style="color:%2300d9ff;font-size:64px;font-family:sans-serif;text-shadow:0 0 20px %2300d9ff;">$displayName</h2>
</body></html>''';

    _robot?.client.tabletDisplay(html.replaceAll('\n', ''));
  }

  @override
  void onCloseDisplay() {
    debugPrint('SequenceExecutor: Closing display');
    _robot?.client.tabletCloseDisplay();
  }

  @override
  void onNavigate(String waypoint) {
    debugPrint('SequenceExecutor: onNavigate called with waypoint=$waypoint');
    debugPrint(
        'SequenceExecutor: _robot=${_robot != null}, isConnected=${_robot?.isConnected}');
    _pendingWaypoint = waypoint;
    if (_robot != null) {
      debugPrint('SequenceExecutor: Calling goToWaypoint($waypoint)');
      _robot!.goToWaypoint(waypoint);
      debugPrint('SequenceExecutor: goToWaypoint returned');
    } else {
      debugPrint('SequenceExecutor: ERROR - _robot is null! Cannot navigate.');
    }
  }

  @override
  void onSequenceStarted(Sequence sequence) {
    debugPrint(
        'SequenceExecutor: Sequence started: ${sequence.name} with ${sequence.stops.length} stops');
    AudioAnnouncer().speak('Starting sequence: ${sequence.name}');
  }

  @override
  void onSequenceStopped(SequenceStop? currentStop, int stopIndex) {
    debugPrint('SequenceExecutor: Sequence stopped at stop $stopIndex');
    _pendingWaypoint = null;
    _robot?.cancelNavigation();
    AudioAnnouncer().speak('Sequence stopped');
  }

  @override
  void onSequenceCompleted() {
    debugPrint('SequenceExecutor: Sequence completed!');
    AudioAnnouncer().speak('Sequence complete');
  }

  @override
  void onSequenceFailed(String reason) {
    debugPrint('SequenceExecutor: Sequence failed: $reason');
    AudioAnnouncer().speak('Sequence failed: $reason');
  }

  @override
  void onStopArrived(SequenceStop stop, int stopIndex) {
    debugPrint(
        'SequenceExecutor: Arrived at stop ${stopIndex + 1}: ${stop.waypoint}');
  }
}
