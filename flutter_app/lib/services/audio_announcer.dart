import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/robot_connection.dart';
import '../core/sequence_mode.dart';

/// Preset announcement categories
enum AnnouncementCategory {
  blockedPath,
  arrival,
  departure,
  warning,
  custom,
}

/// Crowd Logic venue presets
enum CrowdLogicVenue {
  spaceship('Spaceship', 'Open event floor - friendly but audible over crowds'),
  adultParty('Adult Party', 'Aggressive - robot pushes through quickly'),
  restaurant('Restaurant', 'Balanced - polite but persistent'),
  kidsEvent('Kids Event', 'Gentle - patient and friendly'),
  hospital('Hospital', 'Quiet - minimal interruption'),
  custom('Custom', 'Configure your own timing');

  final String label;
  final String description;
  const CrowdLogicVenue(this.label, this.description);
}

/// Crowd Logic configuration for blocked path behavior
class CrowdLogicConfig {
  final CrowdLogicVenue venue;
  final int checkInterval;     // Seconds between blocked checks
  final int warning1;          // Seconds until level 1 (polite)
  final int warning2;          // Seconds until level 2 (firm)
  final int warning3;          // Seconds until level 3 (urgent)
  final int warning4;          // Seconds until level 4 (demanding + beep)
  final int warning5;          // Seconds until level 5 (aggressive + horn)
  final int warning6;          // Seconds until level 6 (emergency - repeats)
  final int repeatInterval;    // Seconds between level 6 repeats
  final bool enableSounds;     // Play beep/horn sounds
  final bool enableIntelligence; // LIDAR-based smart obstacle detection
  final bool announceMoving;     // Announce for moving obstacles
  final bool announceStatic;     // Announce for unexpected static obstacles

  // Speed ramping settings
  final double safeDistanceFeet;  // Distance in feet where speed ramping begins
  final double rampRate;          // How aggressively speed decreases (0.0-1.0, higher = faster slowdown)

  // Helpers for conversion
  double get safeDistanceMeters => safeDistanceFeet * 0.3048;

  const CrowdLogicConfig({
    this.venue = CrowdLogicVenue.restaurant,
    this.checkInterval = 3,
    this.warning1 = 30,   // Patient first warning
    this.warning2 = 45,
    this.warning3 = 60,
    this.warning4 = 90,
    this.warning5 = 120,
    this.warning6 = 180,
    this.repeatInterval = 15,
    this.enableSounds = true,
    this.enableIntelligence = true,  // Smart LIDAR detection ON by default
    this.announceMoving = true,       // Announce for moving obstacles
    this.announceStatic = true,       // Announce for static obstacles in path
    this.safeDistanceFeet = 3.0,      // 3 feet = ~0.9m default
    this.rampRate = 0.5,              // Medium aggression
  });

  /// Preset for Spaceship (Frontier Tower event floor) - open venue, crowds moving
  /// Needs to be heard over ambient noise but stay friendly and engaging
  static const spaceship = CrowdLogicConfig(
    venue: CrowdLogicVenue.spaceship,
    checkInterval: 3,
    warning1: 20,   // Friendly first ask - people are exploring
    warning2: 35,   // Polite reminder
    warning3: 50,   // Getting urgent
    warning4: 70,   // Beep to cut through crowd noise
    warning5: 90,   // Horn for stubborn blockers
    warning6: 120,  // Emergency - repeat with sounds
    repeatInterval: 12,
    enableSounds: true,  // Need sounds to cut through event noise
    enableIntelligence: true,  // Smart detection for moving crowds
    announceMoving: true,
    announceStatic: true,
    safeDistanceFeet: 4.0,  // 4 feet - give space in crowded venues
    rampRate: 0.4,          // Gentle slowdown for event floor
  );

  /// Preset for adult parties - faster escalation, but still reasonable
  static const adultParty = CrowdLogicConfig(
    venue: CrowdLogicVenue.adultParty,
    checkInterval: 2,
    warning1: 15,   // Was 5 - too aggressive
    warning2: 25,   // Was 10
    warning3: 35,   // Was 15
    warning4: 50,   // Was 20
    warning5: 70,   // Was 25
    warning6: 90,   // Was 30
    repeatInterval: 10,
    enableSounds: true,
    safeDistanceFeet: 2.5,  // Tighter space at parties
    rampRate: 0.7,          // More aggressive slowdown
  );

  /// Preset for restaurants - balanced (patient first warning, then escalates)
  static const restaurant = CrowdLogicConfig(
    venue: CrowdLogicVenue.restaurant,
    checkInterval: 3,
    warning1: 30,   // Was 8 - give robot time to navigate normally
    warning2: 45,   // Was 15
    warning3: 60,   // Was 22
    warning4: 90,   // Was 30
    warning5: 120,  // Was 40
    warning6: 180,  // Was 50
    repeatInterval: 15,
    enableSounds: true,
    safeDistanceFeet: 3.0,  // Standard 3 feet distance
    rampRate: 0.5,          // Balanced slowdown
  );

  /// Preset for kids events - patient and gentle
  static const kidsEvent = CrowdLogicConfig(
    venue: CrowdLogicVenue.kidsEvent,
    checkInterval: 5,
    warning1: 15,
    warning2: 30,
    warning3: 45,
    warning4: 60,
    warning5: 90,
    warning6: 120,
    repeatInterval: 15,
    enableSounds: false,  // No scary sounds for kids
    safeDistanceFeet: 5.0,  // Extra distance for kids safety
    rampRate: 0.3,          // Very gentle slowdown
  );

  /// Preset for hospitals - quiet and minimal
  static const hospital = CrowdLogicConfig(
    venue: CrowdLogicVenue.hospital,
    checkInterval: 10,
    warning1: 30,
    warning2: 60,
    warning3: 90,
    warning4: 120,
    warning5: 180,
    warning6: 240,
    repeatInterval: 30,
    enableSounds: false,
    safeDistanceFeet: 4.0,  // Safe distance in medical settings
    rampRate: 0.2,          // Very slow, cautious approach
  );

  /// Get preset by venue type
  static CrowdLogicConfig forVenue(CrowdLogicVenue venue) {
    switch (venue) {
      case CrowdLogicVenue.spaceship:
        return spaceship;
      case CrowdLogicVenue.adultParty:
        return adultParty;
      case CrowdLogicVenue.restaurant:
        return restaurant;
      case CrowdLogicVenue.kidsEvent:
        return kidsEvent;
      case CrowdLogicVenue.hospital:
        return hospital;
      case CrowdLogicVenue.custom:
        return restaurant; // Default to restaurant for custom
    }
  }

  Map<String, dynamic> toJson() => {
    'venue': venue.name,
    'check_interval': checkInterval,
    'warning1': warning1,
    'warning2': warning2,
    'warning3': warning3,
    'warning4': warning4,
    'warning5': warning5,
    'warning6': warning6,
    'repeat_interval': repeatInterval,
    'enable_sounds': enableSounds,
    'enable_intelligence': enableIntelligence,
    'announce_moving': announceMoving,
    'announce_static': announceStatic,
    'safe_distance_feet': safeDistanceFeet,
    'ramp_rate': rampRate,
  };

  factory CrowdLogicConfig.fromJson(Map<String, dynamic> json) => CrowdLogicConfig(
    venue: CrowdLogicVenue.values.firstWhere(
      (v) => v.name == json['venue'],
      orElse: () => CrowdLogicVenue.restaurant,
    ),
    checkInterval: json['check_interval'] as int? ?? 3,
    // Use patient restaurant defaults (not aggressive old defaults)
    warning1: json['warning1'] as int? ?? 30,   // Was 8 - too aggressive
    warning2: json['warning2'] as int? ?? 45,   // Was 15
    warning3: json['warning3'] as int? ?? 60,   // Was 22
    warning4: json['warning4'] as int? ?? 90,   // Was 30
    warning5: json['warning5'] as int? ?? 120,  // Was 40
    warning6: json['warning6'] as int? ?? 180,  // Was 50
    repeatInterval: json['repeat_interval'] as int? ?? 15,  // Was 8
    enableSounds: json['enable_sounds'] as bool? ?? true,
    enableIntelligence: json['enable_intelligence'] as bool? ?? true,
    announceMoving: json['announce_moving'] as bool? ?? true,
    announceStatic: json['announce_static'] as bool? ?? true,
    safeDistanceFeet: (json['safe_distance_feet'] as num?)?.toDouble() ?? 3.0,
    rampRate: (json['ramp_rate'] as num?)?.toDouble() ?? 0.5,
  );

  CrowdLogicConfig copyWith({
    CrowdLogicVenue? venue,
    int? checkInterval,
    int? warning1,
    int? warning2,
    int? warning3,
    int? warning4,
    int? warning5,
    int? warning6,
    int? repeatInterval,
    bool? enableSounds,
    bool? enableIntelligence,
    bool? announceMoving,
    bool? announceStatic,
    double? safeDistanceFeet,
    double? rampRate,
  }) => CrowdLogicConfig(
    venue: venue ?? this.venue,
    checkInterval: checkInterval ?? this.checkInterval,
    warning1: warning1 ?? this.warning1,
    warning2: warning2 ?? this.warning2,
    warning3: warning3 ?? this.warning3,
    warning4: warning4 ?? this.warning4,
    warning5: warning5 ?? this.warning5,
    warning6: warning6 ?? this.warning6,
    repeatInterval: repeatInterval ?? this.repeatInterval,
    enableSounds: enableSounds ?? this.enableSounds,
    enableIntelligence: enableIntelligence ?? this.enableIntelligence,
    announceMoving: announceMoving ?? this.announceMoving,
    announceStatic: announceStatic ?? this.announceStatic,
    safeDistanceFeet: safeDistanceFeet ?? this.safeDistanceFeet,
    rampRate: rampRate ?? this.rampRate,
  );
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

  // Blocked path detection - VELOCITY-BASED (escalate only when STUCK)
  Timer? _blockedTimer;
  DateTime? _stuckSince;         // When velocity dropped to ~0 (null = moving)
  int _blockedWarningLevel = 0;  // Escalation level (0-6, increasingly aggressive)
  DateTime? _lastWarningTime;    // Track when last warning was spoken
  double _lastVelocity = 0.0;    // Track robot velocity

  // Crowd Logic configuration (replaces hardcoded timing)
  CrowdLogicConfig _crowdConfig = CrowdLogicConfig.restaurant;
  static const String _crowdConfigKey = 'crowd_logic_config';

  // Getters for timing from config
  int get blockedCheckInterval => _crowdConfig.checkInterval;
  int get blockedWarning1 => _crowdConfig.warning1;
  int get blockedWarning2 => _crowdConfig.warning2;
  int get blockedWarning3 => _crowdConfig.warning3;
  int get blockedWarning4 => _crowdConfig.warning4;
  int get blockedWarning5 => _crowdConfig.warning5;
  int get blockedWarning6 => _crowdConfig.warning6;

  // Preset announcements (configurable)
  List<AnnouncementPreset> _presets = [];
  static const String _presetsKey = 'announcement_presets';

  // Default blocked path announcements (escalating, but patient at first)
  static const List<AnnouncementPreset> defaultBlockedPresets = [
    // Level 1: Polite (30s - give robot time to navigate)
    AnnouncementPreset(
      id: 'blocked_1',
      text: 'Excuse me, please clear the path.',
      category: AnnouncementCategory.blockedPath,
      delaySeconds: 30,
    ),
    // Level 2: Firm
    AnnouncementPreset(
      id: 'blocked_2',
      text: 'Please move out of the way. I need to pass through.',
      category: AnnouncementCategory.blockedPath,
      delaySeconds: 45,
    ),
    // Level 3: Urgent
    AnnouncementPreset(
      id: 'blocked_3',
      text: 'Attention! You are blocking my route. Please step aside now.',
      category: AnnouncementCategory.blockedPath,
      delaySeconds: 60,
    ),
    // Level 4: Demanding
    AnnouncementPreset(
      id: 'blocked_4',
      text: 'Warning! I must pass through immediately. Clear the path now!',
      category: AnnouncementCategory.blockedPath,
      delaySeconds: 90,
    ),
    // Level 5: Aggressive
    AnnouncementPreset(
      id: 'blocked_5',
      text: 'ALERT! You are obstructing robot movement! Move immediately!',
      category: AnnouncementCategory.blockedPath,
      delaySeconds: 120,
    ),
    // Level 6: Emergency (repeats)
    AnnouncementPreset(
      id: 'blocked_6',
      text: 'EMERGENCY! Path blocked! This is your final warning! MOVE NOW!',
      category: AnnouncementCategory.blockedPath,
      delaySeconds: 180,
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

  /// Get/set crowd logic configuration
  CrowdLogicConfig get crowdConfig => _crowdConfig;
  set crowdConfig(CrowdLogicConfig config) {
    _crowdConfig = config;
    _saveCrowdConfig();
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

  /// Initialize TTS engine and load presets/config
  Future<void> init() async {
    // Load saved configuration first
    await _loadCrowdConfig();
    await _loadPresets();

    if (kIsWeb) {
      // Web TTS has limited support and requires user interaction
      _tts = FlutterTts();
      try {
        await _tts!.setLanguage('en-US');
        // Web TTS may fail silently or throw - we handle errors in speak()
        _tts!.setErrorHandler((msg) {
          debugPrint('AudioAnnouncer: Web TTS error: $msg');
        });
      } catch (e) {
        debugPrint('AudioAnnouncer: Web TTS init error: $e');
      }
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

  /// Load crowd logic config from storage
  Future<void> _loadCrowdConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_crowdConfigKey);
      if (json != null) {
        _crowdConfig = CrowdLogicConfig.fromJson(jsonDecode(json));
        debugPrint('AudioAnnouncer: Loaded crowd config: ${_crowdConfig.venue.label}');
      }
    } catch (e) {
      debugPrint('AudioAnnouncer: Failed to load crowd config: $e');
    }
  }

  /// Save crowd logic config to storage
  Future<void> _saveCrowdConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_crowdConfig.toJson());
      await prefs.setString(_crowdConfigKey, json);
      debugPrint('AudioAnnouncer: Saved crowd config: ${_crowdConfig.venue.label}');
    } catch (e) {
      debugPrint('AudioAnnouncer: Failed to save crowd config: $e');
    }
  }

  /// Apply a venue preset
  void applyVenuePreset(CrowdLogicVenue venue) {
    crowdConfig = CrowdLogicConfig.forVenue(venue);
  }

  /// Speak an announcement
  Future<void> speak(String text) async {
    if (!_enabled) return;

    debugPrint('Announcing: $text');

    // Forward to tablet if connected - this is the PRIMARY TTS for web
    // since browser TTS often fails due to user interaction requirements
    final robot = _robotConnection;
    if (robot != null && robot.isConnected) {
      try {
        robot.client.tabletSpeak(text);
        // On web, tablet TTS is preferred - skip local TTS attempt
        if (kIsWeb) return;
      } catch (e) {
        debugPrint('AudioAnnouncer: Failed to forward to tablet: $e');
      }
    }

    // Reinitialize TTS if needed
    if (_tts == null) {
      try {
        await init();
      } catch (e) {
        debugPrint('AudioAnnouncer: Failed to reinit TTS: $e');
        return;
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
    final previousGoal = _lastGoal;
    _lastNavStatus = navStatus;
    _lastGoal = goalName;

    debugPrint('AudioAnnouncer: Nav status $previousStatus -> $navStatus, goal: $previousGoal -> $goalName');

    // Check if a sequence is running - if so, let SequenceManager handle most announcements
    final tourRunning = SequenceManager.instance.status == SequenceStatus.running;

    switch (navStatus) {
      case 601: // Moving
        // Close any existing display when leaving a waypoint
        if (previousStatus == 603) {
          _closeTabletDisplay();
        }
        // Check if this is a new navigation goal (different from what we were tracking)
        final isNewGoal = goalName.isNotEmpty && goalName != previousGoal;
        if (previousStatus != 601 || isNewGoal) {
          // Only announce navigation start if not in tour mode
          if (!tourRunning && goalName.isNotEmpty) {
            speak('Navigating to $goalName');
          }
          // Start/restart blocked path detection (always, even during tours)
          // This resets the timer when chaining to a new waypoint
          // BUT: Skip for charger-related waypoints (docking is supposed to be tight)
          final goalLower = goalName.toLowerCase();
          final isChargingRelated = goalLower.contains('pile') ||
                                   goalLower.contains('charger') ||
                                   goalLower.contains('dock') ||
                                   goalLower.contains('charging');

          if (!isChargingRelated) {
            debugPrint('AudioAnnouncer: Starting blocked detection for $goalName');
            _startBlockedDetection();
          } else {
            debugPrint('AudioAnnouncer: Skipping blocked detection for charger waypoint $goalName');
          }
        }
        break;
      case 603: // Arrived
        _stopBlockedDetection();  // Successfully arrived, stop checking
        // Announce arrival if:
        // 1. No sequence is running (normal waypoint navigation)
        // 2. Sequence failed (robot arrived but sequence died - still tell user!)
        // 3. Sequence completed (edge case)
        // Do NOT announce if sequence is actively running - it handles its own announcements
        final seqStatus = SequenceManager.instance.status;
        if (!tourRunning || seqStatus == SequenceStatus.failed || seqStatus == SequenceStatus.completed) {
          if (goalName.isNotEmpty) {
            debugPrint('AudioAnnouncer: Announcing arrival at $goalName (seqStatus=$seqStatus)');
            announceArrival(goalName);
          }
        }
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

  /// Called by RobotConnection when velocity updates
  void onVelocityChanged(double linearVelocity, [double angularVelocity = 0.0]) {
    _lastVelocity = linearVelocity;

    // Only track stuck state during active navigation
    if (_lastNavStatus != 601) return;

    const stuckThreshold = 0.05; // Less than 5cm/s = stuck
    const rotationThreshold = 0.1; // Less than 0.1 rad/s = not rotating

    // Robot is moving if EITHER linear OR angular velocity is above threshold
    // This prevents false stuck detection when robot rotates in place at start of nav
    final isMoving = linearVelocity.abs() >= stuckThreshold ||
                     angularVelocity.abs() >= rotationThreshold;

    if (!isMoving) {
      // Robot stopped - start tracking stuck time
      _stuckSince ??= DateTime.now();
    } else {
      // Robot moving (forward or rotating) - reset stuck tracking and warning level
      if (_stuckSince != null) {
        debugPrint('AudioAnnouncer: Robot moving again (lin: ${linearVelocity.toStringAsFixed(2)}, ang: ${angularVelocity.toStringAsFixed(2)}), resetting stuck timer');
        _stuckSince = null;
        _blockedWarningLevel = 0;
      }
    }
  }

  /// Start blocked path detection timer
  void _startBlockedDetection() {
    _stopBlockedDetection();  // Clear any existing timer
    _stuckSince = null;  // Not stuck yet
    _blockedWarningLevel = 0;

    // Check periodically for blocked path (only announces when STUCK)
    _blockedTimer = Timer.periodic(
      Duration(seconds: blockedCheckInterval),
      (_) => _checkBlockedPath(),
    );
  }

  /// Stop blocked path detection
  void _stopBlockedDetection() {
    _blockedTimer?.cancel();
    _blockedTimer = null;
    _stuckSince = null;
    _blockedWarningLevel = 0;
    _lastWarningTime = null;
  }

  /// Check if path has been blocked too long and announce with escalating aggression
  void _checkBlockedPath() {
    if (_lastNavStatus != 601) {
      // No longer navigating, stop checking
      _stopBlockedDetection();
      return;
    }

    // Only escalate warnings when robot is STUCK (velocity ~0)
    if (_stuckSince == null) {
      return; // Robot is moving, don't warn
    }

    final now = DateTime.now();
    final elapsed = now.difference(_stuckSince!).inSeconds;
    final blockedPresets = getPresetsByCategory(AnnouncementCategory.blockedPath);

    // Helper to get preset or default
    AnnouncementPreset getPreset(int level) {
      final idx = level - 1;
      if (blockedPresets.length > idx) return blockedPresets[idx];
      if (defaultBlockedPresets.length > idx) return defaultBlockedPresets[idx];
      return defaultBlockedPresets.last;
    }

    // Helper to speak with optional horn sound at higher levels
    void speakWithUrgency(int level, String text) {
      // Double-check we're still blocked before announcing
      if (_blockedTimer == null || _lastNavStatus != 601) {
        debugPrint('AudioAnnouncer: Skipping warning - no longer blocked');
        return;
      }

      _lastWarningTime = now;
      debugPrint('AudioAnnouncer: Blocked path warning level $level (${elapsed}s)');

      // At level 4+, play a beep/horn sound first via tablet (if sounds enabled)
      if (level >= 4 && _crowdConfig.enableSounds) {
        _playAlertSound(level);
        // Wait for sound to play before speaking (beep=500ms, horn=1500ms)
        final soundDuration = level >= 5 ? 1500 : 500;
        Future.delayed(Duration(milliseconds: soundDuration), () {
          // Re-check we're still blocked after delay (robot may have cleared)
          if (_blockedTimer == null || _lastNavStatus != 601) {
            debugPrint('AudioAnnouncer: Skipping delayed speech - no longer blocked');
            return;
          }
          speak(text);
        });
      } else {
        speak(text);
      }
    }

    // Escalate warnings based on elapsed time
    if (elapsed >= blockedWarning6 && _blockedWarningLevel >= 6) {
      // Level 6+: Repeat at configured interval with horn
      final timeSinceLast = _lastWarningTime != null
          ? now.difference(_lastWarningTime!).inSeconds
          : 999;
      if (timeSinceLast >= _crowdConfig.repeatInterval) {
        speakWithUrgency(6, getPreset(6).text);
      }
    } else if (elapsed >= blockedWarning6 && _blockedWarningLevel < 6) {
      _blockedWarningLevel = 6;
      speakWithUrgency(6, getPreset(6).text);
    } else if (elapsed >= blockedWarning5 && _blockedWarningLevel < 5) {
      _blockedWarningLevel = 5;
      speakWithUrgency(5, getPreset(5).text);
    } else if (elapsed >= blockedWarning4 && _blockedWarningLevel < 4) {
      _blockedWarningLevel = 4;
      speakWithUrgency(4, getPreset(4).text);
    } else if (elapsed >= blockedWarning3 && _blockedWarningLevel < 3) {
      _blockedWarningLevel = 3;
      speakWithUrgency(3, getPreset(3).text);
    } else if (elapsed >= blockedWarning2 && _blockedWarningLevel < 2) {
      _blockedWarningLevel = 2;
      speakWithUrgency(2, getPreset(2).text);
    } else if (elapsed >= blockedWarning1 && _blockedWarningLevel < 1) {
      _blockedWarningLevel = 1;
      speakWithUrgency(1, getPreset(1).text);
    }
  }

  /// Play an alert sound on the tablet (beep at level 4, horn at level 5+)
  void _playAlertSound(int level) {
    final robot = _robotConnection;
    if (robot == null || !robot.isConnected) return;

    try {
      if (level >= 5) {
        // Aggressive horn sound - play a loud warning tone
        robot.client.tabletPlaySound('horn');
      } else {
        // Beep sound for level 4
        robot.client.tabletPlaySound('beep');
      }
    } catch (e) {
      debugPrint('AudioAnnouncer: Failed to play alert sound: $e');
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

  /// Announce arrival at a waypoint with optional beep sound
  /// [waypoint] - the waypoint name
  /// [isDelivery] - if true, plays a celebratory delivery sound instead of standard beep
  void announceArrival(String waypoint, {bool isDelivery = false}) {
    if (!_enabled) return;

    final robot = _robotConnection;
    if (robot != null && robot.isConnected) {
      // Play arrival beep first
      final soundType = isDelivery ? 'delivery' : 'arrival';
      robot.client.tabletPlaySound(soundType);

      // Wait for sound to complete before speaking (arrival=500ms, delivery=460ms)
      final soundDuration = isDelivery ? 460 : 500;
      Future.delayed(Duration(milliseconds: soundDuration), () {
        speak('Arrived at $waypoint');
      });
    } else {
      // No robot connection, just speak
      speak('Arrived at $waypoint');
    }
  }

  void dispose() {
    _stopBlockedDetection();
    _tts?.stop();
  }
}
