import 'package:flutter/foundation.dart';
import '../core/tour_mode.dart';
import '../core/robot_connection.dart';
import 'audio_announcer.dart';

/// Executes tours by connecting TourManager to RobotConnection
class TourExecutor implements TourExecutorCallback {
  static final TourExecutor _instance = TourExecutor._internal();
  factory TourExecutor() => _instance;
  TourExecutor._internal();

  RobotConnection? _robot;
  int _lastNavStatus = 0;
  String _lastGoal = '';

  /// Initialize with robot connection
  void init(RobotConnection robot) {
    _robot = robot;
    TourManager.instance.setCallback(this);
    debugPrint('TourExecutor: Initialized');
  }

  /// Call this when nav status changes (from RobotConnection status updates)
  void onNavStatusChanged(int navStatus, String goalName) {
    if (navStatus == _lastNavStatus && goalName == _lastGoal) return;

    _lastNavStatus = navStatus;
    _lastGoal = goalName;

    // Check if we arrived at a waypoint (status 603)
    if (navStatus == 603 && goalName.isNotEmpty) {
      debugPrint('TourExecutor: Detected arrival at $goalName');
      TourManager.instance.onArrived(goalName);
    }

    // Handle tour interruptions
    if (TourManager.instance.status == TourStatus.running) {
      if (navStatus == 602) {
        // Navigation cancelled
        debugPrint('TourExecutor: Navigation cancelled during tour');
      } else if (navStatus == 604) {
        // Navigation failed
        debugPrint('TourExecutor: Navigation failed during tour');
        onTourFailed('Navigation failed - path blocked');
      }
    }
  }

  // === TourExecutorCallback Implementation ===

  @override
  void onSpeak(String text) {
    debugPrint('TourExecutor: Speaking: $text');
    AudioAnnouncer().speak(text);
  }

  @override
  void onDisplay(String url, int durationSeconds) {
    debugPrint('TourExecutor: Displaying URL for ${durationSeconds}s: $url');
    _robot?.client.tabletDisplay(url);
  }

  @override
  void onDisplayDefault(String waypoint) {
    debugPrint('TourExecutor: Displaying default branding for: $waypoint');
    // Format waypoint name nicely
    final displayName = waypoint
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isEmpty ? '' : '${word[0].toUpperCase()}${word.substring(1)}')
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
    debugPrint('TourExecutor: Closing display');
    _robot?.client.tabletCloseDisplay();
  }

  @override
  void onNavigate(String waypoint) {
    debugPrint('TourExecutor: Navigating to $waypoint');
    _robot?.goToWaypoint(waypoint);
  }

  @override
  void onTourStarted(Tour tour) {
    debugPrint('TourExecutor: Tour started: ${tour.name} with ${tour.stops.length} stops');
    AudioAnnouncer().speak('Starting tour: ${tour.name}');
  }

  @override
  void onTourStopped(TourStop? currentStop, int stopIndex) {
    debugPrint('TourExecutor: Tour stopped at stop $stopIndex');
    _robot?.cancelNavigation();
    AudioAnnouncer().speak('Tour stopped');
  }

  @override
  void onTourCompleted() {
    debugPrint('TourExecutor: Tour completed!');
    AudioAnnouncer().speak('Tour complete');
  }

  @override
  void onTourFailed(String reason) {
    debugPrint('TourExecutor: Tour failed: $reason');
    AudioAnnouncer().speak('Tour failed: $reason');
  }

  @override
  void onStopArrived(TourStop stop, int stopIndex) {
    debugPrint('TourExecutor: Arrived at stop ${stopIndex + 1}: ${stop.waypoint}');
  }
}
