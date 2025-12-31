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
