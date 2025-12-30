import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../core/robot_connection.dart';

/// Audio announcement service for robot status changes
class AudioAnnouncer {
  static final AudioAnnouncer _instance = AudioAnnouncer._internal();
  factory AudioAnnouncer() => _instance;
  AudioAnnouncer._internal();

  FlutterTts? _tts;
  bool _enabled = true;
  int _lastNavStatus = 0;
  String _lastGoal = '';
  double _volume = 1.0;
  final double _rate = 0.5;
  final double _pitch = 1.0;

  // Reference to RobotConnection for tablet forwarding
  RobotConnection? _robotConnection;

  // ignore: unnecessary_getters_setters
  bool get enabled => _enabled;
  // ignore: unnecessary_getters_setters
  set enabled(bool value) => _enabled = value;

  double get volume => _volume;
  set volume(double value) {
    _volume = value;
    _tts?.setVolume(value);
  }

  /// Set the robot connection to enable tablet forwarding
  void setRobotConnection(RobotConnection robot) {
    _robotConnection = robot;
  }

  /// Initialize TTS engine
  Future<void> init() async {
    if (kIsWeb) {
      // Web TTS has limited support
      _tts = FlutterTts();
      await _tts!.setLanguage('en-US');
      return;
    }

    _tts = FlutterTts();
    await _tts!.setLanguage('en-US');
    await _tts!.setVolume(_volume);
    await _tts!.setSpeechRate(_rate);
    await _tts!.setPitch(_pitch);

    // Use a clear voice
    final voices = await _tts!.getVoices;
    debugPrint('Available voices: ${voices.length}');
  }

  /// Speak an announcement
  Future<void> speak(String text) async {
    if (!_enabled) return;

    // Reinitialize TTS if needed
    if (_tts == null) {
      try {
        await init();
      } catch (e) {
        debugPrint('AudioAnnouncer: Failed to reinit TTS: $e');
        return;
      }
    }

    debugPrint('Announcing: $text');

    // Forward to tablet if connected (check before async operations)
    final robot = _robotConnection;
    if (robot != null && robot.isConnected) {
      try {
        robot.client.tabletSpeak(text);
      } catch (e) {
        debugPrint('AudioAnnouncer: Failed to forward to tablet: $e');
      }
    }

    try {
      await _tts!.stop(); // Stop any current speech before starting new
      await _tts!.speak(text);
    } catch (e) {
      debugPrint('AudioAnnouncer: TTS error: $e');
      // Mark TTS as needing reinit on next call
      _tts = null;
    }
  }

  /// Stop current speech
  Future<void> stop() async {
    await _tts?.stop();
  }

  /// Handle navigation status change
  void onNavStatusChanged(int navStatus, String goalName) {
    if (navStatus == _lastNavStatus && goalName == _lastGoal) return;

    final previousStatus = _lastNavStatus;
    _lastNavStatus = navStatus;
    _lastGoal = goalName;

    switch (navStatus) {
      case 601: // Moving
        if (previousStatus != 601 && goalName.isNotEmpty) {
          speak('Navigating to $goalName');
        }
        break;
      case 603: // Arrived
        if (goalName.isNotEmpty) {
          speak('Arrived at $goalName');
        } else {
          speak('Destination reached');
        }
        break;
      case 602: // Cancelled
        speak('Navigation cancelled');
        break;
      case 604: // Failed
        speak('Navigation failed. Path blocked.');
        break;
      case 600: // Idle
        // Don't announce idle unless we were moving
        if (previousStatus == 601) {
          speak('Stopped');
        }
        break;
    }
  }

  /// Announce obstacle detected (for SLAM avoidance)
  void announceObstacle() {
    speak('Obstacle detected');
  }

  /// Announce battery status
  void announceBattery(int percent) {
    if (percent <= 10) {
      speak('Warning! Battery critically low at $percent percent');
    } else if (percent <= 20) {
      speak('Battery low at $percent percent');
    }
  }

  /// Announce estop status
  void announceEstop(bool hardEstop, bool softEstop) {
    if (hardEstop) {
      speak('Emergency stop engaged');
    } else if (softEstop) {
      speak('Soft stop active');
    }
  }

  /// Custom announcement
  void announce(String message) {
    speak(message);
  }

  void dispose() {
    _tts?.stop();
  }
}
