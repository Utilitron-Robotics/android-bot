import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/robot_connection.dart';
import '../core/tour_mode.dart';

/// Preset announcement categories
enum AnnouncementCategory {
  blockedPath,
  arrival,
  departure,
  warning,
  custom,
}

/// A configurable announcement preset
class AnnouncementPreset {
  final String id;
  final String text;
  final AnnouncementCategory category;
  final int delaySeconds;  // Delay before this announcement (for escalation)

  const AnnouncementPreset({
    required this.id,
    required this.text,
    required this.category,
    this.delaySeconds = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'category': category.name,
    'delay_seconds': delaySeconds,
  };

  factory AnnouncementPreset.fromJson(Map<String, dynamic> json) => AnnouncementPreset(
    id: json['id'] as String,
    text: json['text'] as String,
    category: AnnouncementCategory.values.firstWhere(
      (c) => c.name == json['category'],
      orElse: () => AnnouncementCategory.custom,
    ),
    delaySeconds: json['delay_seconds'] as int? ?? 0,
  );
}

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

  // Blocked path detection
  Timer? _blockedTimer;
  DateTime? _navStartTime;
  int _blockedWarningLevel = 0;  // Escalation level (0 = none, 1 = polite, 2 = urgent, 3 = demanding)
  static const int blockedCheckInterval = 5;  // Check every 5 seconds
  static const int blockedWarning1 = 10;      // First warning after 10 seconds
  static const int blockedWarning2 = 20;      // Second warning after 20 seconds
  static const int blockedWarning3 = 35;      // Third warning after 35 seconds

  // Preset announcements (configurable)
  List<AnnouncementPreset> _presets = [];
  static const String _presetsKey = 'announcement_presets';

  // Default blocked path announcements (escalating)
  static const List<AnnouncementPreset> defaultBlockedPresets = [
    AnnouncementPreset(
      id: 'blocked_1',
      text: 'Excuse me, please clear the path.',
      category: AnnouncementCategory.blockedPath,
      delaySeconds: 10,
    ),
    AnnouncementPreset(
      id: 'blocked_2',
      text: 'Please move out of the way. I need to pass through.',
      category: AnnouncementCategory.blockedPath,
      delaySeconds: 20,
    ),
    AnnouncementPreset(
      id: 'blocked_3',
      text: 'Attention! Please step aside immediately. You are blocking my route.',
      category: AnnouncementCategory.blockedPath,
      delaySeconds: 35,
    ),
  ];

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

  /// Get all presets
  List<AnnouncementPreset> get presets => _presets;

  /// Get presets by category
  List<AnnouncementPreset> getPresetsByCategory(AnnouncementCategory category) {
    final categoryPresets = _presets.where((p) => p.category == category).toList();
    if (categoryPresets.isEmpty && category == AnnouncementCategory.blockedPath) {
      return defaultBlockedPresets.toList();
    }
    return categoryPresets;
  }

  /// Initialize TTS engine and load presets
  Future<void> init() async {
    if (kIsWeb) {
      // Web TTS has limited support
      _tts = FlutterTts();
      await _tts!.setLanguage('en-US');
      await _loadPresets();
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

    await _loadPresets();
  }

  /// Load presets from storage
  Future<void> _loadPresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_presetsKey);
      if (json != null) {
        final list = jsonDecode(json) as List;
        _presets = list.map((p) => AnnouncementPreset.fromJson(p)).toList();
        debugPrint('AudioAnnouncer: Loaded ${_presets.length} presets');
      }
    } catch (e) {
      debugPrint('AudioAnnouncer: Failed to load presets: $e');
    }
  }

  /// Save presets to storage
  Future<void> _savePresets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_presets.map((p) => p.toJson()).toList());
      await prefs.setString(_presetsKey, json);
    } catch (e) {
      debugPrint('AudioAnnouncer: Failed to save presets: $e');
    }
  }

  /// Add a preset
  void addPreset(AnnouncementPreset preset) {
    _presets.add(preset);
    _savePresets();
  }

  /// Remove a preset by id
  void removePreset(String id) {
    _presets.removeWhere((p) => p.id == id);
    _savePresets();
  }

  /// Update a preset
  void updatePreset(AnnouncementPreset preset) {
    final index = _presets.indexWhere((p) => p.id == preset.id);
    if (index >= 0) {
      _presets[index] = preset;
      _savePresets();
    }
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
  /// NOTE: Arrival announcements are handled by TaskEngine/WaypointGrid to avoid duplicates
  /// This method only handles: navigation start, blocked path detection, cancellation, failure
  void onNavStatusChanged(int navStatus, String goalName) {
    if (navStatus == _lastNavStatus && goalName == _lastGoal) return;

    final previousStatus = _lastNavStatus;
    _lastNavStatus = navStatus;
    _lastGoal = goalName;

    // Check if a tour is running - if so, let TourManager handle most announcements
    final tourRunning = TourManager.instance.status == TourStatus.running;

    switch (navStatus) {
      case 601: // Moving
        // Close any existing display when leaving a waypoint
        if (previousStatus == 603) {
          _closeTabletDisplay();
        }
        if (previousStatus != 601 && goalName.isNotEmpty) {
          // Only announce navigation start if not in tour mode
          if (!tourRunning) {
            speak('Navigating to $goalName');
          }
          // Start blocked path detection (always, even during tours)
          _startBlockedDetection();
        }
        break;
      case 603: // Arrived
        _stopBlockedDetection();  // Successfully arrived, stop checking
        // NOTE: Arrival announcements are now handled by TaskEngine via WaypointGrid callback
        // to avoid duplicate announcements. Don't announce here.
        break;
      case 602: // Cancelled
        _stopBlockedDetection();  // Navigation cancelled
        _closeTabletDisplay(); // Close display on cancel
        if (!tourRunning) {
          speak('Navigation cancelled');
        }
        break;
      case 604: // Failed
        _stopBlockedDetection();  // Navigation failed
        _closeTabletDisplay(); // Close display on failure
        if (!tourRunning) {
          speak('Navigation failed. Path blocked.');
        }
        break;
      case 600: // Idle
        _stopBlockedDetection();  // No longer navigating
        // Don't announce idle - too noisy
        break;
    }
  }

  /// Start blocked path detection timer
  void _startBlockedDetection() {
    _stopBlockedDetection();  // Clear any existing timer
    _navStartTime = DateTime.now();
    _blockedWarningLevel = 0;

    // Check periodically for blocked path
    _blockedTimer = Timer.periodic(
      const Duration(seconds: blockedCheckInterval),
      (_) => _checkBlockedPath(),
    );
  }

  /// Stop blocked path detection
  void _stopBlockedDetection() {
    _blockedTimer?.cancel();
    _blockedTimer = null;
    _navStartTime = null;
    _blockedWarningLevel = 0;
  }

  /// Check if path has been blocked too long and announce
  void _checkBlockedPath() {
    if (_navStartTime == null) return;
    if (_lastNavStatus != 601) {
      // No longer moving, stop checking
      _stopBlockedDetection();
      return;
    }

    final elapsed = DateTime.now().difference(_navStartTime!).inSeconds;
    final blockedPresets = getPresetsByCategory(AnnouncementCategory.blockedPath);

    // Escalate warnings based on elapsed time
    if (elapsed >= blockedWarning3 && _blockedWarningLevel < 3) {
      _blockedWarningLevel = 3;
      final preset = blockedPresets.length > 2 ? blockedPresets[2] : defaultBlockedPresets[2];
      speak(preset.text);
      debugPrint('AudioAnnouncer: Blocked path warning level 3 (${elapsed}s)');
    } else if (elapsed >= blockedWarning2 && _blockedWarningLevel < 2) {
      _blockedWarningLevel = 2;
      final preset = blockedPresets.length > 1 ? blockedPresets[1] : defaultBlockedPresets[1];
      speak(preset.text);
      debugPrint('AudioAnnouncer: Blocked path warning level 2 (${elapsed}s)');
    } else if (elapsed >= blockedWarning1 && _blockedWarningLevel < 1) {
      _blockedWarningLevel = 1;
      final preset = blockedPresets.isNotEmpty ? blockedPresets[0] : defaultBlockedPresets[0];
      speak(preset.text);
      debugPrint('AudioAnnouncer: Blocked path warning level 1 (${elapsed}s)');
    }

    // Reset warning level after level 3 to allow repeat if still blocked
    if (_blockedWarningLevel >= 3 && elapsed >= blockedWarning3 + 15) {
      _navStartTime = DateTime.now().subtract(const Duration(seconds: blockedWarning2));
      _blockedWarningLevel = 2;  // Will trigger level 3 again in 15 seconds
    }
  }

  /// Close any displayed content on the tablet
  void _closeTabletDisplay() {
    final robot = _robotConnection;
    if (robot == null || !robot.isConnected) return;

    try {
      robot.client.tabletCloseDisplay();
    } catch (e) {
      debugPrint('AudioAnnouncer: Failed to close tablet display: $e');
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
    _stopBlockedDetection();
    _tts?.stop();
  }
}
