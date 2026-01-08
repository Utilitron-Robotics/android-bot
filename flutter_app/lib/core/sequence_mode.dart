import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'task_mode.dart';
import 'sequence_task_mode.dart';
import 'buffer_sequence_executor.dart';
import 'buffer_client.dart';

/// A single stop in a tour with waypoint and associated actions
class SequenceStop {
  final String waypoint;
  final String? speakText; // TTS text at this stop
  final String? displayUrl; // URL to display (website/image)
  final int displayDuration; // How long to show display (0 = until next nav)
  final int waitSeconds; // Extra wait time at stop

  const SequenceStop({
    required this.waypoint,
    this.speakText,
    this.displayUrl,
    this.displayDuration = 0,
    this.waitSeconds = 0,
  });

  /// Has any actions configured?
  bool get hasActions =>
      (speakText != null && speakText!.isNotEmpty) ||
      (displayUrl != null && displayUrl!.isNotEmpty) ||
      waitSeconds > 0;

  Map<String, dynamic> toJson() => {
        'waypoint': waypoint,
        if (speakText != null) 'speak_text': speakText,
        if (displayUrl != null) 'display_url': displayUrl,
        'display_duration': displayDuration,
        'wait_seconds': waitSeconds,
      };

  factory SequenceStop.fromJson(Map<String, dynamic> json) => SequenceStop(
        waypoint: json['waypoint'] as String? ?? '',
        speakText: json['speak_text'] as String?,
        displayUrl: json['display_url'] as String?,
        displayDuration: json['display_duration'] as int? ?? 0,
        waitSeconds: json['wait_seconds'] as int? ?? 0,
      );

  SequenceStop copyWith({
    String? waypoint,
    String? speakText,
    String? displayUrl,
    int? displayDuration,
    int? waitSeconds,
  }) =>
      SequenceStop(
        waypoint: waypoint ?? this.waypoint,
        speakText: speakText ?? this.speakText,
        displayUrl: displayUrl ?? this.displayUrl,
        displayDuration: displayDuration ?? this.displayDuration,
        waitSeconds: waitSeconds ?? this.waitSeconds,
      );
}

/// A complete tour with ordered stops
class Sequence {
  final String id;
  final String name;
  final String description;
  final List<SequenceStop> stops;
  final bool loop; // Loop back to start after completion
  final bool announceArrival; // Say "Arrived at [waypoint]" before custom text
  final String? introText; // Speak before starting tour
  final String? outroText; // Speak after completing tour
  final String? startWaypoint; // Navigate here before starting tour
  final String? endWaypoint; // Navigate here after completing tour
  final int
      restAtEndSeconds; // Wait at end waypoint before returning to start (for loops)
  final int modifiedAt; // Timestamp for conflict resolution (ms since epoch)

  // Motion trigger settings - start tour when someone approaches
  final bool
      motionTriggerStart; // Enable motion-triggered tour start at start waypoint
  final String?
      motionGreeting; // TTS greeting when motion detected (e.g., "Hello! Would you like a tour?")
  final String?
      motionButtonText; // Button text shown on tablet (e.g., "Start Tour", "Begin Experience")
  final String?
      motionDisplayUrl; // URL to show on tablet when awaiting tour start (start button)

  Sequence({
    required this.id,
    required this.name,
    this.description = '',
    this.stops = const [],
    this.loop = false,
    this.announceArrival = false,
    this.introText,
    this.outroText,
    this.startWaypoint,
    this.endWaypoint,
    this.restAtEndSeconds = 0,
    this.motionTriggerStart = false,
    this.motionGreeting,
    this.motionButtonText,
    this.motionDisplayUrl,
    int? modifiedAt,
  }) : modifiedAt = modifiedAt ?? DateTime.now().millisecondsSinceEpoch;

  /// Create sequence from waypoint list with auto-loaded scripts
  static Sequence fromWaypointList({
    required String id,
    required String name,
    required List<String> waypoints,
    Map<String, String> scripts = const {},
    Map<String, String> displayUrls = const {},
  }) {
    return Sequence(
      id: id,
      name: name,
      stops: waypoints
          .map((wp) => SequenceStop(
                waypoint: wp,
                speakText: scripts[wp],
                displayUrl: displayUrls[wp],
              ))
          .toList(),
    );
  }

  // ================================================================
  // EXAMPLE SEQUENCE FACTORY METHODS
  // These create pre-configured sequences for common use cases
  // ================================================================

  /// Tour Sequence: Multi-stop guided tour with narration at each exhibit
  /// Use Case: Museums, offices, campus tours
  static Sequence tourExample({
    required List<String> waypoints,
    Map<String, String> narrations = const {},
    Map<String, String> mediaUrls = const {},
    String? returnWaypoint,
  }) {
    return Sequence(
      id: 'tour_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Guided Tour',
      description: 'Multi-stop guided tour with narration',
      introText: 'Welcome to the tour! Please follow me as I show you around.',
      outroText: 'This concludes our tour. Thank you for joining me!',
      announceArrival: true,
      endWaypoint: returnWaypoint,
      stops: waypoints
          .map((wp) => SequenceStop(
                waypoint: wp,
                speakText: narrations[wp] ?? 'This is $wp.',
                displayUrl: mediaUrls[wp],
                displayDuration: 15,
                waitSeconds: 5,
              ))
          .toList(),
    );
  }

  /// Comic Sequence: Go to waypoints (or people) and tell jokes
  /// Use Case: Entertainment events, parties
  static Sequence comicExample({
    required List<String> waypoints,
    required List<String> jokes,
    Map<String, String> punchlineGifs = const {},
  }) {
    final stops = <SequenceStop>[];
    for (int i = 0; i < waypoints.length; i++) {
      final wp = waypoints[i];
      final joke = i < jokes.length
          ? jokes[i]
          : 'Why did the robot cross the road? To get to the other circuit!';
      stops.add(SequenceStop(
        waypoint: wp,
        speakText: joke,
        displayUrl: punchlineGifs[wp],
        displayDuration: 5,
        waitSeconds: 3, // Wait for laughter
      ));
    }
    return Sequence(
      id: 'comic_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Comedy Tour',
      description: 'Tell jokes at each stop',
      introText: 'Get ready to laugh! I have some great jokes for you today.',
      outroText: 'Thank you, thank you! I will be here all week!',
      announceArrival: false, // Don't announce, just tell joke
      stops: stops,
    );
  }

  /// Delivery Sequence: Deliver to multiple destinations, then return
  /// Use Case: Restaurant multi-table delivery, mail/package runs
  static Sequence deliveryExample({
    required List<String> destinations,
    required String returnWaypoint,
    String deliveryMessage =
        'Your delivery has arrived. Please take your items.',
    int waitSeconds = 30,
  }) {
    return Sequence(
      id: 'delivery_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Delivery Run',
      description: 'Deliver to multiple stops and return',
      introText: 'Starting delivery run.',
      outroText: 'All deliveries complete. Returning to station.',
      announceArrival: true,
      endWaypoint: returnWaypoint,
      stops: destinations
          .map((wp) => SequenceStop(
                waypoint: wp,
                speakText: deliveryMessage,
                waitSeconds: waitSeconds,
              ))
          .toList(),
    );
  }

  /// Busser Sequence: Go to tables, collect items, go to bus station
  /// Use Case: Restaurant clearing, event cleanup
  static Sequence busserExample({
    required List<String> tables,
    required String busStation,
    String askText = 'Please place any finished items on my tray.',
    int waitSeconds = 20,
  }) {
    final stops = tables
        .map((table) => SequenceStop(
              waypoint: table,
              speakText: askText,
              waitSeconds: waitSeconds,
            ))
        .toList();

    // Add bus station as final stop
    stops.add(SequenceStop(
      waypoint: busStation,
      speakText: 'Ready for unloading. Please remove all items from the tray.',
      waitSeconds: 30,
    ));

    return Sequence(
      id: 'busser_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Bussing Run',
      description: 'Collect items from tables and deliver to bus station',
      introText: 'Starting bussing run.',
      outroText: 'Bussing complete.',
      announceArrival: true,
      stops: stops,
    );
  }

  /// Emergency Sequence: Alert all areas and guide to exit
  /// Use Case: Fire drills, evacuation, safety alerts
  static Sequence emergencyExample({
    required List<String> alertWaypoints,
    required String exitWaypoint,
    String alertMessage =
        'EMERGENCY! Please evacuate immediately. Follow me to the exit.',
    String? evacuationMapUrl,
  }) {
    final stops = alertWaypoints
        .map((wp) => SequenceStop(
              waypoint: wp,
              speakText: alertMessage,
              displayUrl: evacuationMapUrl,
              displayDuration: 0, // Keep displayed until departure
              waitSeconds: 5, // Brief wait to ensure message heard
            ))
        .toList();

    // Add exit as final stop
    stops.add(SequenceStop(
      waypoint: exitWaypoint,
      speakText: 'Exit this way. Please proceed calmly.',
      displayUrl: evacuationMapUrl,
      waitSeconds: 0,
    ));

    return Sequence(
      id: 'emergency_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Emergency Evacuation',
      description: 'Alert all areas and guide to emergency exit',
      introText: 'EMERGENCY ALERT!',
      announceArrival: false, // No arrival announcements - just alert
      loop: true, // Keep looping until manually stopped
      stops: stops,
    );
  }

  /// Patrol Sequence: Loop through waypoints continuously
  /// Use Case: Security patrol, monitoring
  static Sequence patrolExample({
    required List<String> patrolPoints,
    int dwellSeconds = 10,
  }) {
    return Sequence(
      id: 'patrol_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Patrol Route',
      description: 'Continuously patrol waypoints',
      loop: true,
      announceArrival: false,
      stops: patrolPoints
          .map((wp) => SequenceStop(
                waypoint: wp,
                waitSeconds: dwellSeconds,
              ))
          .toList(),
    );
  }

  /// Greeter Sequence: Wait at entrance, greet, then idle
  /// Use Case: Reception, lobby greeting
  static Sequence greeterExample({
    required String entranceWaypoint,
    required String idleWaypoint,
    String greetingText = 'Welcome! How can I help you today?',
    String? logoUrl,
    int waitSeconds = 60,
  }) {
    return Sequence(
      id: 'greeter_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Greeter Duty',
      description: 'Greet visitors at entrance',
      loop: true, // Keep greeting until stopped
      announceArrival: false,
      stops: [
        SequenceStop(
          waypoint: entranceWaypoint,
          speakText: greetingText,
          displayUrl: logoUrl,
          displayDuration: waitSeconds,
          waitSeconds: waitSeconds,
        ),
        SequenceStop(
          waypoint: idleWaypoint,
          speakText: 'Returning to standby.',
          waitSeconds: 10,
        ),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'stops': stops.map((s) => s.toJson()).toList(),
        'loop': loop,
        'announce_arrival': announceArrival,
        'rest_at_end_seconds': restAtEndSeconds,
        'modified_at': modifiedAt,
        'motion_trigger_start': motionTriggerStart,
        if (introText != null) 'intro_text': introText,
        if (outroText != null) 'outro_text': outroText,
        if (startWaypoint != null) 'start_waypoint': startWaypoint,
        if (endWaypoint != null) 'end_waypoint': endWaypoint,
        if (motionGreeting != null) 'motion_greeting': motionGreeting,
        if (motionButtonText != null) 'motion_button_text': motionButtonText,
        if (motionDisplayUrl != null) 'motion_display_url': motionDisplayUrl,
      };

  factory Sequence.fromJson(Map<String, dynamic> json) => Sequence(
        id: json['id'] as String? ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        name: json['name'] as String? ?? 'Untitled Sequence',
        description: json['description'] as String? ?? '',
        stops: (json['stops'] as List<dynamic>?)
                ?.map((s) => SequenceStop.fromJson(s as Map<String, dynamic>))
                .toList() ??
            [],
        loop: json['loop'] as bool? ?? false,
        announceArrival: json['announce_arrival'] as bool? ?? false,
        restAtEndSeconds: json['rest_at_end_seconds'] as int? ?? 0,
        introText: json['intro_text'] as String?,
        outroText: json['outro_text'] as String?,
        startWaypoint: json['start_waypoint'] as String?,
        endWaypoint: json['end_waypoint'] as String?,
        modifiedAt: json['modified_at'] as int?,
        motionTriggerStart: json['motion_trigger_start'] as bool? ?? false,
        motionGreeting: json['motion_greeting'] as String?,
        motionButtonText: json['motion_button_text'] as String?,
        motionDisplayUrl: json['motion_display_url'] as String?,
      );

  Sequence copyWith({
    String? id,
    String? name,
    String? description,
    List<SequenceStop>? stops,
    bool? loop,
    bool? announceArrival,
    String? introText,
    String? outroText,
    String? startWaypoint,
    String? endWaypoint,
    int? restAtEndSeconds,
    int? modifiedAt,
    bool? motionTriggerStart,
    String? motionGreeting,
    String? motionButtonText,
    String? motionDisplayUrl,
  }) =>
      Sequence(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        stops: stops ?? this.stops,
        loop: loop ?? this.loop,
        announceArrival: announceArrival ?? this.announceArrival,
        restAtEndSeconds: restAtEndSeconds ?? this.restAtEndSeconds,
        introText: introText ?? this.introText,
        outroText: outroText ?? this.outroText,
        startWaypoint: startWaypoint ?? this.startWaypoint,
        endWaypoint: endWaypoint ?? this.endWaypoint,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        motionTriggerStart: motionTriggerStart ?? this.motionTriggerStart,
        motionGreeting: motionGreeting ?? this.motionGreeting,
        motionButtonText: motionButtonText ?? this.motionButtonText,
        motionDisplayUrl: motionDisplayUrl ?? this.motionDisplayUrl,
      );

  /// Add a stop
  Sequence addStop(SequenceStop stop) => copyWith(
        stops: [...stops, stop],
      );

  /// Remove a stop by index
  Sequence removeStop(int index) => copyWith(
        stops: [...stops]..removeAt(index),
      );

  /// Reorder stops
  Sequence reorderStop(int oldIndex, int newIndex) {
    final newStops = [...stops];
    final item = newStops.removeAt(oldIndex);
    newStops.insert(newIndex, item);
    return copyWith(stops: newStops);
  }

  /// Update a stop
  Sequence updateStop(int index, SequenceStop stop) {
    final newStops = [...stops];
    newStops[index] = stop;
    return copyWith(stops: newStops);
  }
}

/// Sequence execution status
enum SequenceStatus {
  idle,
  running,
  paused,
  completed,
  failed,
}

/// Sequence execution phase (what it's currently doing)
enum SequencePhase {
  navigating('Navigating...', Icons.navigation),
  arriving('Arriving...', Icons.location_on),
  speaking('Speaking...', Icons.volume_up),
  displaying('Displaying...', Icons.tv),
  waiting('Waiting...', Icons.timer),
  awaitingVisitor('Waiting for visitor...', Icons.pan_tool);

  final String label;
  final IconData icon;
  const SequencePhase(this.label, this.icon);
}

/// Callback interface for tour execution
abstract class SequenceExecutorCallback {
  void onSpeak(String text);
  void onArrivalAnnouncement(String waypoint,
      {bool isDelivery = false}); // Beep + speak arrival
  void onDisplay(String url, int durationSeconds);
  void onDisplayDefault(String waypoint); // Show company branding when no media
  void onCloseDisplay();
  void onNavigate(String waypoint);
  void onSequenceStarted(Sequence sequence);
  void onSequenceStopped(SequenceStop? currentStop, int stopIndex);
  void onSequenceCompleted();
  void onSequenceFailed(String reason);
  void onStopArrived(SequenceStop stop, int stopIndex);
}

/// Sequence manager - saves/loads sequences and manages execution
/// Supports both local storage (SharedPreferences) and cloud sync (DynamoDB)
class SequenceManager extends ChangeNotifier {
  static const String _sequencesKey = 'saved_sequences';
  static const String _cloudUrlKey = 'tour_cloud_api_url';
  static const String _currentMapKey = 'tour_current_map_id';
  static const String _deletedToursKey = 'deleted_tour_ids'; // Tombstones
  static SequenceManager? _instance;

  final Map<String, Sequence> _sequences = {};
  final Set<String> _deletedTourIds = {}; // Tombstones for deleted tours
  bool _loaded = false;
  bool _cloudSyncEnabled = false;
  String? _cloudApiUrl;
  String? _currentMapId;

  // Execution state
  Sequence? _currentSequence;
  int _currentStopIndex = -1;
  SequenceStatus _status = SequenceStatus.idle;
  Timer? _waitTimer;
  SequenceExecutorCallback? _callback;

  // NEW: SequenceTaskMode for command queue/retry support
  SequenceTaskMode? _activeSequenceTask;

  // NEW: Buffer-based executor (preferred when available)
  BufferSequenceExecutor? _bufferExecutor;
  bool _useBufferExecutor = false;

  // Phase tracking for UI countdown
  SequencePhase _currentPhase = SequencePhase.navigating;
  int _countdownSeconds = 0;
  int _phaseDurationSeconds = 0;
  Timer? _countdownTimer;

  static SequenceManager get instance {
    _instance ??= SequenceManager._();
    return _instance!;
  }

  SequenceManager._();

  // Cloud sync getters
  bool get cloudSyncEnabled => _cloudSyncEnabled;
  String? get cloudApiUrl => _cloudApiUrl;
  String? get currentMapId => _currentMapId;

  // Getters
  SequenceStatus get status => _status;
  Sequence? get currentSequence => _currentSequence;
  int get currentStopIndex => _currentStopIndex;
  SequenceStop? get currentStop => _currentSequence != null &&
          _currentStopIndex >= 0 &&
          _currentStopIndex < _currentSequence!.stops.length
      ? _currentSequence!.stops[_currentStopIndex]
      : null;
  List<Sequence> get sequences => _sequences.values.toList();

  // Phase tracking getters
  SequencePhase get currentPhase => _currentPhase;
  int get countdownSeconds => _countdownSeconds;
  int get phaseDurationSeconds => _phaseDurationSeconds;

  /// Update the current phase and start countdown
  void _setPhase(SequencePhase phase, int durationSeconds) {
    _currentPhase = phase;
    _phaseDurationSeconds = durationSeconds;
    _countdownSeconds = durationSeconds;

    // Cancel existing countdown timer
    _countdownTimer?.cancel();

    // Start countdown timer that ticks every second
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

  /// Stop countdown timer
  void _stopCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _countdownSeconds = 0;
    _phaseDurationSeconds = 0;
  }

  /// Set the callback for tour execution
  void setCallback(SequenceExecutorCallback callback) {
    _callback = callback;
  }

  /// Configure buffer-based executor (preferred for relay connection)
  /// When set, sequences are loaded into the relay buffer for execution
  ///
  /// CRITICAL: This is called on every connect() - must handle re-initialization properly
  void setBufferExecutor(BufferClient bufferClient) {
    if (_callback == null) {
      debugPrint(
          'SequenceManager: Cannot set buffer executor - no callback set');
      return;
    }

    // CLEANUP: Dispose old executor before creating new one
    // This is CRITICAL to prevent duplicate listeners and event handlers!
    if (_bufferExecutor != null) {
      debugPrint('SequenceManager: Disposing old buffer executor before creating new');
      _bufferExecutor!.removeListener(_onBufferExecutorChanged);
      _bufferExecutor!.dispose();
    }

    _bufferExecutor = BufferSequenceExecutor.withClient(
      bufferClient: bufferClient,
      callback: _callback!,
    );
    _bufferExecutor!.addListener(_onBufferExecutorChanged);
    _useBufferExecutor = true;
    debugPrint('SequenceManager: Buffer executor configured (hash=${_bufferExecutor.hashCode})');
  }

  /// Clear buffer executor (fall back to old system)
  void clearBufferExecutor() {
    _bufferExecutor?.removeListener(_onBufferExecutorChanged);
    _bufferExecutor?.dispose();
    _bufferExecutor = null;
    _useBufferExecutor = false;
  }

  /// Get buffer client for sensor data access (ultrasonic, etc)
  BufferClient? get bufferClient => _bufferExecutor?.bufferClient;

  /// Get current buffer state (includes ultrasonic sensor data)
  BufferState? get bufferState => _bufferExecutor?.bufferClient.state;

  /// Mirror buffer executor state to SequenceManager
  void _onBufferExecutorChanged() {
    final executor = _bufferExecutor;
    if (executor == null) return;

    _currentStopIndex = executor.currentStopIndex;
    _currentPhase = executor.currentPhase;
    _countdownSeconds = executor.countdownSeconds;

    // CRITICAL: Sync current sequence from buffer executor (for reconnect restore)
    _currentSequence = executor.currentSequence;

    // Map buffer executor status to sequence status
    switch (executor.status) {
      case SequenceExecutorStatus.idle:
        _status = SequenceStatus.idle;
        _currentSequence = null;
        break;
      case SequenceExecutorStatus.running:
        _status = SequenceStatus.running;
        break;
      case SequenceExecutorStatus.paused:
        _status = SequenceStatus.paused;
        break;
      case SequenceExecutorStatus.completed:
        _status = SequenceStatus.completed;
        break;
      case SequenceExecutorStatus.failed:
        _status = SequenceStatus.failed;
        break;
    }

    notifyListeners();
  }

  /// Configure cloud sync
  Future<void> configureCloud({
    required String apiUrl,
    String? mapId,
  }) async {
    _cloudApiUrl = apiUrl;
    _currentMapId = mapId;
    _cloudSyncEnabled = apiUrl.isNotEmpty;

    // Persist settings
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cloudUrlKey, apiUrl);
    if (mapId != null) {
      await prefs.setString(_currentMapKey, mapId);
    }

    debugPrint(
        'SequenceManager: Cloud sync configured - API: $apiUrl, Map: $mapId');
    notifyListeners();
  }

  /// Set the current map ID for tour filtering
  Future<void> setCurrentMap(String mapId) async {
    _currentMapId = mapId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentMapKey, mapId);

    // Reload tours for this map
    if (_cloudSyncEnabled) {
      await loadFromCloud(mapId: mapId);
    }
    notifyListeners();
  }

  /// Load tours from local storage
  Future<void> load() async {
    if (_loaded) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      // Load cloud settings
      _cloudApiUrl = prefs.getString(_cloudUrlKey);

      // BUGFIX: Remove invalid frontiertower.io URL (was accidentally hardcoded)
      // Replace with correct AWS CloudFormation endpoint
      if (_cloudApiUrl != null && _cloudApiUrl!.contains('frontiertower.io')) {
        debugPrint('SequenceManager: Fixing invalid cloud URL: $_cloudApiUrl');
        _cloudApiUrl = 'https://e536dpa128.execute-api.us-west-1.amazonaws.com/dev';
        await prefs.setString(_cloudUrlKey, _cloudApiUrl!);
        debugPrint('SequenceManager: Cloud URL fixed to: $_cloudApiUrl');
      }

      _currentMapId = prefs.getString(_currentMapKey);
      _cloudSyncEnabled = _cloudApiUrl != null && _cloudApiUrl!.isNotEmpty;

      // Load deleted tour IDs (tombstones) - prevents cloud from re-adding deleted tours
      final deletedJson = prefs.getStringList(_deletedToursKey);
      if (deletedJson != null) {
        _deletedTourIds.addAll(deletedJson);
      }
      debugPrint(
          'SequenceManager: Loaded ${_deletedTourIds.length} tombstones');

      // Load local tours
      final toursJson = prefs.getString(_sequencesKey);
      final jsonLen = toursJson?.length ?? 0;
      debugPrint(
          'SequenceManager.load(): Raw JSON from prefs: ${jsonLen > 0 ? toursJson!.substring(0, jsonLen.clamp(0, 200)) : "(null)"}...');
      debugPrint('SequenceManager.load(): JSON length: $jsonLen chars');

      if (toursJson != null && toursJson.isNotEmpty) {
        try {
          final tours = jsonDecode(toursJson) as Map<String, dynamic>;
          debugPrint(
              'SequenceManager.load(): Decoded ${tours.length} tour entries');
          tours.forEach((id, data) {
            debugPrint('SequenceManager.load(): Loading tour id=$id');
            _sequences[id] = Sequence.fromJson(data as Map<String, dynamic>);
          });
        } catch (e) {
          debugPrint('SequenceManager.load(): JSON decode error: $e');
        }
      } else {
        debugPrint(
            'SequenceManager.load(): No tours JSON found in prefs (null or empty)');
      }
      _loaded = true;
      debugPrint('SequenceManager: Loaded ${_sequences.length} local tours');

      // Also load from cloud if configured
      if (_cloudSyncEnabled && _currentMapId != null) {
        await loadFromCloud(mapId: _currentMapId!);
      }

      notifyListeners();
    } catch (e) {
      debugPrint('SequenceManager: Failed to load: $e');
    }
  }

  /// Load tours from cloud (DynamoDB via API Gateway)
  /// Only overwrites local tours if cloud version is newer (based on modified_at timestamp)
  Future<bool> loadFromCloud({String? mapId}) async {
    debugPrint('SequenceManager.loadFromCloud(): CALLED');
    debugPrint(
        'SequenceManager.loadFromCloud(): Current local tours BEFORE cloud load: ${_sequences.keys.toList()}');

    if (_cloudApiUrl == null || _cloudApiUrl!.isEmpty) {
      debugPrint(
          'SequenceManager.loadFromCloud(): SKIP - Cloud API URL not configured');
      return false;
    }

    try {
      final targetMapId = mapId ?? _currentMapId;
      final url = targetMapId != null
          ? '$_cloudApiUrl/tours?map_id=$targetMapId'
          : '$_cloudApiUrl/tours';

      debugPrint('SequenceManager.loadFromCloud(): GET $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final cloudTours = data['tours'] as List<dynamic>? ?? [];

        debugPrint(
            'SequenceManager: Received ${cloudTours.length} tours from cloud');

        int merged = 0;
        int skipped = 0;
        int added = 0;

        for (final tourData in cloudTours) {
          final cloudSeq =
              _parseSequenceFromCloud(tourData as Map<String, dynamic>);

          // Skip tours that were deleted locally (tombstoned)
          if (_deletedTourIds.contains(cloudSeq.id)) {
            skipped++;
            debugPrint(
                'SequenceManager: Skipping tombstoned tour: ${cloudSeq.name}');
            continue;
          }

          final localSeq = _sequences[cloudSeq.id];

          if (localSeq == null) {
            // New tour from cloud - add it
            _sequences[cloudSeq.id] = cloudSeq;
            added++;
            debugPrint(
                'SequenceManager: Added new tour from cloud: ${cloudSeq.name}');
          } else if (cloudSeq.modifiedAt > localSeq.modifiedAt) {
            // Cloud is newer - use cloud version
            _sequences[cloudSeq.id] = cloudSeq;
            merged++;
            debugPrint(
                'SequenceManager: Cloud tour "${cloudSeq.name}" is newer (cloud=${cloudSeq.modifiedAt}, local=${localSeq.modifiedAt}) - updated');
          } else {
            // Local is newer or same - keep local
            skipped++;
            debugPrint(
                'SequenceManager: Local tour "${localSeq.name}" is newer/same (cloud=${cloudSeq.modifiedAt}, local=${localSeq.modifiedAt}) - kept local');
          }
        }

        debugPrint(
            'SequenceManager.loadFromCloud(): Cloud sync - added=$added, updated=$merged, kept_local=$skipped');
        debugPrint(
            'SequenceManager.loadFromCloud(): Local tours AFTER cloud merge: ${_sequences.keys.toList()}');

        // Save to local storage for offline access
        debugPrint(
            'SequenceManager.loadFromCloud(): About to call save() with ${_sequences.length} tours');
        await save();
        debugPrint('SequenceManager.loadFromCloud(): save() completed');
        notifyListeners();
        return true;
      } else {
        debugPrint(
            'SequenceManager.loadFromCloud(): FAILED - status ${response.statusCode}, body=${response.body}');
        return false;
      }
    } catch (e, stack) {
      debugPrint('SequenceManager.loadFromCloud(): ERROR: $e');
      debugPrint('SequenceManager.loadFromCloud(): Stack: $stack');
      return false;
    }
  }

  /// Parse a tour from cloud format (DynamoDB JSON)
  Sequence _parseSequenceFromCloud(Map<String, dynamic> cloudData) {
    // Convert cloud format (tour_id, map_id) to local format (id)
    final tourId = cloudData['tour_id'] as String? ??
        cloudData['id'] as String? ??
        DateTime.now().millisecondsSinceEpoch.toString();

    // Parse waypoints array into SequenceStops
    final waypoints = cloudData['waypoints'] as List<dynamic>? ?? [];
    final dwellTimes = cloudData['dwell_times'] as Map<String, dynamic>? ?? {};

    final stops = waypoints.map((wp) {
      final waypointName = wp is String
          ? wp
          : (wp as Map<String, dynamic>)['name'] as String? ?? '';
      final dwellTime = dwellTimes[waypointName] as int? ?? 0;

      // Check if waypoint has additional data
      if (wp is Map<String, dynamic>) {
        return SequenceStop(
          waypoint: waypointName,
          speakText: wp['speak_text'] as String?,
          displayUrl: wp['display_url'] as String?,
          displayDuration: wp['display_duration'] as int? ?? 0,
          waitSeconds:
              dwellTime > 0 ? dwellTime : (wp['wait_seconds'] as int? ?? 0),
        );
      }
      return SequenceStop(
        waypoint: waypointName,
        waitSeconds: dwellTime,
      );
    }).toList();

    return Sequence(
      id: tourId,
      name: cloudData['name'] as String? ?? 'Cloud Tour',
      description: cloudData['description'] as String? ?? '',
      stops: stops,
      loop: cloudData['loop'] as bool? ?? false,
      announceArrival: cloudData['announce_arrival'] as bool? ?? false,
      restAtEndSeconds: cloudData['rest_at_end_seconds'] as int? ?? 0,
      introText: cloudData['intro_text'] as String?,
      outroText: cloudData['outro_text'] as String?,
      startWaypoint: cloudData['start_waypoint'] as String?,
      endWaypoint: cloudData['end_waypoint'] as String?,
      modifiedAt: cloudData['modified_at'] as int?,
      motionTriggerStart: cloudData['motion_trigger_start'] as bool? ?? false,
      motionGreeting: cloudData['motion_greeting'] as String?,
      motionButtonText: cloudData['motion_button_text'] as String?,
      motionDisplayUrl: cloudData['motion_display_url'] as String?,
    );
  }

  /// Save a tour to cloud (DynamoDB via API Gateway)
  Future<bool> saveToCloud(Sequence sequence, {String? mapId}) async {
    debugPrint(
        'SequenceManager.saveToCloud(): CALLED for "${sequence.name}" id=${sequence.id}');

    if (_cloudApiUrl == null || _cloudApiUrl!.isEmpty) {
      debugPrint(
          'SequenceManager.saveToCloud(): SKIP - Cloud API URL not configured');
      return false;
    }

    try {
      final targetMapId = mapId ?? _currentMapId ?? '';
      debugPrint(
          'SequenceManager.saveToCloud(): Saving to map: $targetMapId, API: $_cloudApiUrl');

      // Convert to cloud format
      final cloudData = {
        'tour_id': sequence.id,
        'map_id': targetMapId,
        'name': sequence.name,
        'description': sequence.description,
        'waypoints': sequence.stops
            .map((s) => {
                  'name': s.waypoint,
                  'speak_text': s.speakText,
                  'display_url': s.displayUrl,
                  'display_duration': s.displayDuration,
                  'wait_seconds': s.waitSeconds,
                })
            .toList(),
        'dwell_times': {
          for (var s in sequence.stops) s.waypoint: s.waitSeconds
        },
        'loop': sequence.loop,
        'announce_arrival': sequence.announceArrival,
        'rest_at_end_seconds': sequence.restAtEndSeconds,
        'intro_text': sequence.introText,
        'outro_text': sequence.outroText,
        'start_waypoint': sequence.startWaypoint,
        'end_waypoint': sequence.endWaypoint,
        'modified_at': sequence.modifiedAt,
      };

      debugPrint('SequenceManager.saveToCloud(): POST to $_cloudApiUrl/tours');
      debugPrint(
          'SequenceManager.saveToCloud(): Body: ${jsonEncode(cloudData)}');

      final response = await http
          .post(
            Uri.parse('$_cloudApiUrl/tours'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(cloudData),
          )
          .timeout(const Duration(seconds: 10));

      debugPrint(
          'SequenceManager.saveToCloud(): Response status=${response.statusCode}');
      debugPrint(
          'SequenceManager.saveToCloud(): Response body=${response.body}');

      if (response.statusCode == 200) {
        debugPrint(
            'SequenceManager.saveToCloud(): SUCCESS - Tour saved to cloud');
        return true;
      } else {
        debugPrint(
            'SequenceManager.saveToCloud(): FAILED - status ${response.statusCode}');
        return false;
      }
    } catch (e, stack) {
      debugPrint('SequenceManager.saveToCloud(): ERROR: $e');
      debugPrint('SequenceManager.saveToCloud(): Stack: $stack');
      return false;
    }
  }

  /// Push ALL local tours to cloud (for seeding)
  Future<int> pushAllToCloud({String? mapId}) async {
    if (_cloudApiUrl == null || _cloudApiUrl!.isEmpty) {
      debugPrint('SequenceManager.pushAllToCloud(): No cloud URL configured');
      return 0;
    }

    final targetMapId = mapId ?? _currentMapId ?? '';
    int pushed = 0;

    debugPrint(
        'SequenceManager.pushAllToCloud(): Pushing ${_sequences.length} tours to cloud');

    for (final seq in _sequences.values) {
      final success = await saveToCloud(seq, mapId: targetMapId);
      if (success) pushed++;
    }

    debugPrint(
        'SequenceManager.pushAllToCloud(): Pushed $pushed/${_sequences.length} tours');

    // Notify listeners to refresh UI
    notifyListeners();
    return pushed;
  }

  /// Delete a tour from cloud
  Future<bool> deleteFromCloud(String tourId) async {
    if (_cloudApiUrl == null || _cloudApiUrl!.isEmpty) {
      return false;
    }

    try {
      final response = await http.delete(
        Uri.parse('$_cloudApiUrl/tours/$tourId'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('SequenceManager: Failed to delete from cloud: $e');
      return false;
    }
  }

  /// Sync tours with cloud (two-way)
  Future<void> syncWithCloud({String? mapId}) async {
    if (!_cloudSyncEnabled) return;

    final targetMapId = mapId ?? _currentMapId;

    // First, load from cloud to get latest
    await loadFromCloud(mapId: targetMapId);

    // Then upload any local-only tours
    for (final seq in _sequences.values) {
      await saveToCloud(seq, mapId: targetMapId);
    }

    debugPrint('SequenceManager: Cloud sync complete');
  }

  /// Save tours to storage
  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final toursMap = _sequences.map((k, v) => MapEntry(k, v.toJson()));
      final toursJson = jsonEncode(toursMap);

      debugPrint('SequenceManager.save(): Saving ${_sequences.length} tours');
      debugPrint(
          'SequenceManager.save(): Tours map keys: ${_sequences.keys.toList()}');
      debugPrint(
          'SequenceManager.save(): JSON length: ${toursJson.length} chars');

      final setResult = await prefs.setString(_sequencesKey, toursJson);
      debugPrint('SequenceManager.save(): setString result: $setResult');

      // Save tombstones (deleted tour IDs)
      await prefs.setStringList(_deletedToursKey, _deletedTourIds.toList());

      // VERIFY it was saved by reading it back
      final verifyJson = prefs.getString(_sequencesKey);
      debugPrint(
          'SequenceManager.save(): Verify - read back ${verifyJson?.length ?? 0} chars');

      debugPrint(
          'SequenceManager: Saved ${_sequences.length} tours, ${_deletedTourIds.length} tombstones');
    } catch (e, stack) {
      debugPrint('SequenceManager: Failed to save: $e');
      debugPrint('SequenceManager: Stack: $stack');
    }
  }

  /// Get a tour by ID
  Sequence? getSequence(String id) => _sequences[id];

  /// Save a sequence (local + cloud if enabled)
  /// Updates modified_at timestamp to prevent cloud from overwriting this edit
  Future<void> saveSequence(Sequence sequence) async {
    debugPrint(
        'SequenceManager.saveSequence(): CALLED with "${sequence.name}" id=${sequence.id}');
    debugPrint(
        'SequenceManager.saveSequence(): Before save - _sequences has ${_sequences.length} tours');

    // Update modified_at timestamp to mark this as the newest version
    final updatedSequence = sequence.copyWith(
      modifiedAt: DateTime.now().millisecondsSinceEpoch,
    );

    // Remove from tombstones in case user is re-creating a deleted tour
    _deletedTourIds.remove(updatedSequence.id);

    _sequences[updatedSequence.id] = updatedSequence;
    debugPrint(
        'SequenceManager.saveSequence(): After adding - _sequences has ${_sequences.length} tours');
    debugPrint(
        'SequenceManager.saveSequence(): Tour IDs: ${_sequences.keys.toList()}');

    await save();
    debugPrint(
        'SequenceManager.saveSequence(): save() completed for "${updatedSequence.name}" with modifiedAt=${updatedSequence.modifiedAt}');

    // VERIFY PERSISTENCE: Read back immediately to confirm save worked
    final prefs = await SharedPreferences.getInstance();
    final verifyJson = prefs.getString(_sequencesKey);
    debugPrint(
        'SequenceManager.saveSequence(): VERIFY - stored JSON length: ${verifyJson?.length ?? 0}');
    if (verifyJson != null && verifyJson.isNotEmpty) {
      final verifyMap = jsonDecode(verifyJson) as Map<String, dynamic>;
      debugPrint(
          'SequenceManager.saveSequence(): VERIFY - stored ${verifyMap.length} tours: ${verifyMap.keys.toList()}');
    } else {
      debugPrint(
          'SequenceManager.saveSequence(): VERIFY FAILED - no data stored!');
    }

    // Also save to cloud if enabled
    if (_cloudSyncEnabled) {
      await saveToCloud(updatedSequence);
    }

    notifyListeners();
  }

  /// Delete a tour (local + cloud if enabled)
  Future<void> deleteSequence(String tourId) async {
    _sequences.remove(tourId);

    // Add to tombstones to prevent cloud from re-adding on next sync
    _deletedTourIds.add(tourId);
    debugPrint('SequenceManager: Added tombstone for tour $tourId');

    await save();

    // Also delete from cloud if enabled
    if (_cloudSyncEnabled) {
      await deleteFromCloud(tourId);
    }

    notifyListeners();
  }

  /// Start a sequence using buffer executor (preferred) or SequenceTaskMode fallback
  Future<void> startSequence(Sequence sequence) async {
    debugPrint(
        'SequenceManager.startSequence: CALLED with sequence="${sequence.name}" (${sequence.stops.length} stops)');
    debugPrint(
        'SequenceManager.startSequence: Current status=$_status, useBuffer=$_useBufferExecutor');
    // DEBUG: Print stack trace to find what's calling startSequence unexpectedly
    debugPrint('SequenceManager.startSequence: CALL STACK:\n${StackTrace.current.toString().split('\n').take(10).join('\n')}');

    if (_status == SequenceStatus.running) {
      debugPrint(
          'SequenceManager.startSequence: ABORT - sequence already running');
      return;
    }

    if (_callback == null) {
      debugPrint('SequenceManager.startSequence: ERROR - no callback set!');
      return;
    }

    // Clean up any previous sequence task
    if (_activeSequenceTask != null) {
      _activeSequenceTask!.removeListener(_onSequenceTaskChanged);
      _activeSequenceTask = null;
    }

    // Set initial state
    _currentSequence = sequence;
    _currentStopIndex = -1;
    _status = SequenceStatus.running;
    notifyListeners();

    // PREFER buffer executor when available AND relay is actively sending heartbeats
    // If buffer is stale (no heartbeats), the relay isn't connected or doesn't have buffer support
    if (_useBufferExecutor && _bufferExecutor != null) {
      final bufferClient = _bufferExecutor!.bufferClient;
      if (!bufferClient.isStale) {
        debugPrint(
            'SequenceManager.startSequence: Using BufferSequenceExecutor (relay buffer alive, last heartbeat ${DateTime.now().difference(bufferClient.lastHeartbeat!).inMilliseconds}ms ago)');
        await _bufferExecutor!.startSequence(sequence);
        return;
      } else {
        debugPrint(
            'SequenceManager.startSequence: Buffer is stale (no heartbeats) - falling back to SequenceTaskMode');
      }
    }

    // FALLBACK to old SequenceTaskMode system
    debugPrint(
        'SequenceManager.startSequence: Falling back to SequenceTaskMode');
    _activeSequenceTask = SequenceTaskMode(
      sequence: sequence,
      callback: SequenceCallbackAdapter(_callback!),
    );

    _activeSequenceTask!.addListener(_onSequenceTaskChanged);

    final success = await TaskManager.instance.startTask(_activeSequenceTask!);

    if (!success) {
      debugPrint(
          'SequenceManager.startSequence: TaskManager.startTask failed!');
      _status = SequenceStatus.failed;
      _activeSequenceTask?.removeListener(_onSequenceTaskChanged);
      _activeSequenceTask = null;
      notifyListeners();
    } else {
      debugPrint('SequenceManager.startSequence: Started via TaskManager');
    }
  }

  /// Mirror SequenceTaskMode state changes to SequenceManager for UI
  void _onSequenceTaskChanged() {
    final task = _activeSequenceTask;
    if (task == null) return;

    // Mirror state
    _currentStopIndex = task.currentStopIndex;
    _currentPhase = _mapTaskPhaseToSequencePhase(task.phase);
    _countdownSeconds = task.countdownSeconds;
    _phaseDurationSeconds = task.phaseDurationSeconds;

    // Mirror status
    if (task.status == TaskStatus.completed) {
      _status = SequenceStatus.completed;
      _cleanupSequenceTask();
    } else if (task.status == TaskStatus.failed ||
        task.status == TaskStatus.cancelled) {
      _status = SequenceStatus.failed;
      _cleanupSequenceTask();
    } else if (task.status == TaskStatus.paused) {
      _status = SequenceStatus.paused;
    } else if (task.status == TaskStatus.running) {
      _status = SequenceStatus.running;
    }

    notifyListeners();
  }

  /// Map SequenceTaskPhase to SequencePhase for UI compatibility
  SequencePhase _mapTaskPhaseToSequencePhase(SequenceTaskPhase taskPhase) {
    switch (taskPhase) {
      case SequenceTaskPhase.starting:
      case SequenceTaskPhase.intro:
        return SequencePhase.navigating;
      case SequenceTaskPhase.navigating:
        return SequencePhase.navigating;
      case SequenceTaskPhase.arriving:
        return SequencePhase.arriving;
      case SequenceTaskPhase.speaking:
        return SequencePhase.speaking;
      case SequenceTaskPhase.displaying:
        return SequencePhase.displaying;
      case SequenceTaskPhase.waiting:
        return SequencePhase.waiting;
      case SequenceTaskPhase.outro:
      case SequenceTaskPhase.ending:
      case SequenceTaskPhase.complete:
        return SequencePhase.waiting;
    }
  }

  /// Clean up SequenceTaskMode after completion
  void _cleanupSequenceTask() {
    _activeSequenceTask?.removeListener(_onSequenceTaskChanged);
    _activeSequenceTask = null;
    Future.delayed(const Duration(seconds: 3), () {
      _currentSequence = null;
      _currentStopIndex = -1;
      _status = SequenceStatus.idle;
      notifyListeners();
    });
  }

  /// Called when robot arrives at a waypoint
  /// NOTE: When SequenceTaskMode or BufferSequenceExecutor is active, they handle arrivals
  void onArrived(String waypoint) {
    debugPrint(
        'SequenceManager: onArrived($waypoint) - status=$_status, tour=${_currentSequence?.name}, stopIndex=$_currentStopIndex');

    // If SequenceTaskMode is handling execution, let IT handle arrivals.
    // SequenceTaskMode uses CommandManager for reliable navigation with retries.
    // Handling arrival here would cause duplicate events and race conditions.
    if (_activeSequenceTask != null) {
      debugPrint(
          'SequenceManager: Ignoring arrival - SequenceTaskMode is handling it');
      return;
    }

    // If BufferSequenceExecutor is handling execution, let IT handle arrivals
    if (_useBufferExecutor && _bufferExecutor != null) {
      debugPrint(
          'SequenceManager: Ignoring arrival - BufferSequenceExecutor is handling it');
      return;
    }

    if (_status != SequenceStatus.running) {
      debugPrint('SequenceManager: Ignoring arrival - tour not running');
      return;
    }
    if (_currentSequence == null) {
      debugPrint('SequenceManager: Ignoring arrival - no current tour');
      return;
    }

    final stop = currentStop;
    if (stop == null) {
      debugPrint(
          'SequenceManager: Ignoring arrival - no current stop (index=$_currentStopIndex, stops=${_currentSequence!.stops.length})');
      return;
    }

    debugPrint(
        'SequenceManager: Checking arrival - expected="${stop.waypoint}", got="$waypoint"');
    // Case-insensitive, trimmed comparison for robustness
    if (stop.waypoint.toLowerCase().trim() == waypoint.toLowerCase().trim()) {
      debugPrint('SequenceManager: Arrived at ${stop.waypoint}');
      _executeStopActions().catchError((e, stack) {
        debugPrint('SequenceManager: ERROR in _executeStopActions: $e');
        debugPrint('SequenceManager: Stack: $stack');
      });
    } else {
      debugPrint(
          'SequenceManager: Waypoint mismatch - expected="${stop.waypoint}" got="$waypoint" - ignoring');
    }
  }

  /// Estimate TTS duration based on text length
  /// Uses conservative estimate: ~2 words/sec (120 words/min) to account for pauses
  Duration _estimateTtsDuration(String text) {
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final seconds =
        (words / 2.0).ceil(); // ~120 words/min = 2 words/sec (conservative)
    return Duration(seconds: seconds.clamp(2, 60)); // Min 2 sec, max 60 sec
  }

  /// Execute actions at current stop - properly sequenced to avoid race conditions
  ///
  /// DEPRECATED: This method uses hardcoded TTS duration estimates.
  /// It should NOT be reached in normal operation - SequenceTaskMode or
  /// BufferSequenceExecutor should handle all arrivals. If you see this
  /// warning in logs, investigate why the executor is not active.
  Future<void> _executeStopActions() async {
    final stop = currentStop;
    if (stop == null) {
      debugPrint('SequenceManager: _executeStopActions - no current stop!');
      return;
    }

    // WARNING: This is legacy code path - should not be reached!
    debugPrint('⚠️ WARNING: SequenceManager._executeStopActions called directly!');
    debugPrint('⚠️ This uses hardcoded TTS duration guessing - investigate why executor is not active');
    debugPrint('SequenceManager: Executing actions at ${stop.waypoint}');
    debugPrint(
        '  - speakText: ${stop.speakText?.substring(0, (stop.speakText?.length ?? 0).clamp(0, 50))}...');
    debugPrint('  - displayUrl: ${stop.displayUrl}');
    debugPrint('  - announceArrival: ${_currentSequence?.announceArrival}');

    // Set phase to arriving
    _setPhase(SequencePhase.arriving, 1);
    _callback?.onStopArrived(stop, _currentStopIndex);

    // Step 1: Display content FIRST (so user sees it while TTS plays)
    if (stop.displayUrl != null && stop.displayUrl!.isNotEmpty) {
      debugPrint('SequenceManager: Showing display URL: ${stop.displayUrl}');
      _setPhase(SequencePhase.displaying,
          stop.displayDuration > 0 ? stop.displayDuration : 10);
      _callback?.onDisplay(stop.displayUrl!, stop.displayDuration);
    } else {
      // Default: Show company name when no media configured
      debugPrint(
          'SequenceManager: Showing default branding for ${stop.waypoint}');
      _callback?.onDisplayDefault(stop.waypoint);
    }

    // Brief pause for display to render
    await Future.delayed(const Duration(milliseconds: 500));

    // Step 2: Announce arrival if enabled (beep + speak, wait for TTS to finish)
    if (_currentSequence?.announceArrival == true) {
      debugPrint(
          'SequenceManager: Announcing arrival at ${stop.waypoint} with beep');
      final arrivalText = 'Arrived at ${stop.waypoint}';
      final arrivalDuration = _estimateTtsDuration(arrivalText);
      // Add 500ms for beep sound before TTS
      _setPhase(SequencePhase.speaking, arrivalDuration.inSeconds + 1);
      _callback?.onArrivalAnnouncement(stop.waypoint);
      debugPrint(
          'SequenceManager: Waiting ${arrivalDuration.inSeconds + 1}s for beep + arrival TTS');
      await Future.delayed(
          arrivalDuration + const Duration(milliseconds: 1000));
    }

    // Step 3: Speak custom text (wait for it to finish)
    if (stop.speakText != null && stop.speakText!.isNotEmpty) {
      debugPrint(
          'SequenceManager: Speaking tour text (${stop.speakText!.split(' ').length} words)');
      final ttsDuration = _estimateTtsDuration(stop.speakText!);
      _setPhase(SequencePhase.speaking, ttsDuration.inSeconds);
      _callback?.onSpeak(stop.speakText!);
      debugPrint(
          'SequenceManager: Waiting ${ttsDuration.inSeconds}s for tour TTS');
      await Future.delayed(ttsDuration);
    }

    // Step 4: Wait at stop then continue
    // Wait time is ADDITIONAL time after TTS - media stays until robot leaves
    // Minimum wait: 10 seconds for media to play, or displayDuration if specified
    final minMediaTime =
        (stop.displayUrl != null && stop.displayUrl!.isNotEmpty) ? 10 : 0;
    final waitTime = stop.waitSeconds > 0
        ? stop.waitSeconds
        : (stop.displayDuration > 0 ? stop.displayDuration : minMediaTime);

    debugPrint(
        'SequenceManager: Extra wait time: ${waitTime}s before next stop (media plays until departure)');
    _setPhase(SequencePhase.waiting, waitTime);
    _waitTimer = Timer(Duration(seconds: waitTime), () {
      try {
        debugPrint(
            'SequenceManager: Wait complete, navigating to next stop (display stays until departure)');
        // NOTE: Do NOT close display here - it stays until robot leaves (AudioAnnouncer handles that)
        _navigateToNextStop();
      } catch (e, stack) {
        debugPrint('SequenceManager: ERROR in timer callback: $e');
        debugPrint('SequenceManager: Stack: $stack');
      }
    });
  }

  /// Navigate to next stop
  void _navigateToNextStop() {
    debugPrint('SequenceManager._navigateToNextStop: ENTERED');
    debugPrint(
        'SequenceManager._navigateToNextStop: _currentSequence=${_currentSequence?.name}, _currentStopIndex=$_currentStopIndex');

    if (_currentSequence == null) {
      debugPrint(
          'SequenceManager._navigateToNextStop: ABORT - _currentSequence is null');
      return;
    }

    _currentStopIndex++;
    debugPrint(
        'SequenceManager._navigateToNextStop: Incremented index to $_currentStopIndex (tour has ${_currentSequence!.stops.length} stops)');

    if (_currentStopIndex >= _currentSequence!.stops.length) {
      // Tour complete
      if (_currentSequence!.loop) {
        debugPrint(
            'SequenceManager._navigateToNextStop: End of tour, looping back to start');
        _currentStopIndex = 0;
      } else {
        debugPrint(
            'SequenceManager._navigateToNextStop: End of tour, completing');
        _completeSequence();
        return;
      }
    }

    final stop = currentStop;
    if (stop != null) {
      debugPrint(
          'SequenceManager._navigateToNextStop: Got stop waypoint="${stop.waypoint}"');
      _setPhase(SequencePhase.navigating, 0); // No countdown while navigating
      debugPrint(
          'SequenceManager._navigateToNextStop: Phase set to navigating');
      debugPrint(
          'SequenceManager._navigateToNextStop: _callback is ${_callback == null ? "NULL!" : "set (${_callback.runtimeType})"}');

      if (_callback != null) {
        debugPrint(
            'SequenceManager._navigateToNextStop: CALLING onNavigate("${stop.waypoint}")');
        _callback!.onNavigate(stop.waypoint);
        debugPrint('SequenceManager._navigateToNextStop: onNavigate returned');
      } else {
        debugPrint(
            'SequenceManager._navigateToNextStop: ERROR - callback is null, cannot navigate!');
      }
      notifyListeners();
    } else {
      debugPrint(
          'SequenceManager._navigateToNextStop: ERROR - currentStop is null! index=$_currentStopIndex, stops=${_currentSequence?.stops.length}');
    }
  }

  /// Complete the tour
  void _completeSequence() {
    _stopCountdown();

    // Play outro if configured
    if (_currentSequence?.outroText != null &&
        _currentSequence!.outroText!.isNotEmpty) {
      _callback?.onSpeak(_currentSequence!.outroText!);
    }

    // Navigate to end waypoint if configured (e.g., return to charging station)
    if (_currentSequence?.endWaypoint != null &&
        _currentSequence!.endWaypoint!.isNotEmpty) {
      debugPrint(
          'SequenceManager: Navigating to end waypoint: ${_currentSequence!.endWaypoint}');
      _callback?.onNavigate(_currentSequence!.endWaypoint!);
    }

    _status = SequenceStatus.completed;
    _callback?.onSequenceCompleted();
    notifyListeners();

    // Reset after a delay
    Future.delayed(const Duration(seconds: 3), () {
      _currentSequence = null;
      _currentStopIndex = -1;
      _status = SequenceStatus.idle;
      notifyListeners();
    });
  }

  /// Stop the current tour
  void stopSequence() {
    if (_status != SequenceStatus.running && _status != SequenceStatus.paused) {
      return;
    }

    // Use buffer executor if active
    if (_useBufferExecutor && _bufferExecutor != null) {
      debugPrint(
          'SequenceManager.stopSequence: Stopping via BufferSequenceExecutor');
      _bufferExecutor!.stopSequence();
      return;
    }

    // Stop via SequenceTaskMode if active
    if (_activeSequenceTask != null) {
      debugPrint('SequenceManager.stopSequence: Stopping via SequenceTaskMode');
      _activeSequenceTask!.stop();
      _activeSequenceTask!.removeListener(_onSequenceTaskChanged);
      _activeSequenceTask = null;
    }

    _waitTimer?.cancel();
    _waitTimer = null;
    _stopCountdown();
    _callback?.onCloseDisplay();
    _callback?.onSequenceStopped(currentStop, _currentStopIndex);

    _status = SequenceStatus.idle;
    _currentSequence = null;
    _currentStopIndex = -1;
    notifyListeners();
  }

  /// Pause the current tour
  void pauseSequence() {
    if (_status != SequenceStatus.running) return;

    // Use buffer executor if active
    if (_useBufferExecutor && _bufferExecutor != null) {
      debugPrint(
          'SequenceManager.pauseSequence: Pausing via BufferSequenceExecutor');
      _bufferExecutor!.pauseSequence();
      return;
    }

    // Delegate to SequenceTaskMode if active
    if (_activeSequenceTask != null) {
      _activeSequenceTask!.pause();
    }

    _waitTimer?.cancel();
    _status = SequenceStatus.paused;
    notifyListeners();
  }

  /// Resume a paused tour
  void resumeSequence() {
    if (_status != SequenceStatus.paused) return;

    // Use buffer executor if active
    if (_useBufferExecutor && _bufferExecutor != null) {
      debugPrint(
          'SequenceManager.resumeSequence: Resuming via BufferSequenceExecutor');
      _bufferExecutor!.resumeSequence();
      return;
    }

    // Delegate to SequenceTaskMode if active
    if (_activeSequenceTask != null) {
      _activeSequenceTask!.resume();
      _status = SequenceStatus.running;
      notifyListeners();
      return;
    }

    // Fallback to old system
    _status = SequenceStatus.running;
    _navigateToNextStop();
    notifyListeners();
  }

  /// Skip to next stop
  void skipToNextStop() {
    if (_status != SequenceStatus.running && _status != SequenceStatus.paused) {
      return;
    }

    // Use buffer executor if active
    if (_useBufferExecutor && _bufferExecutor != null) {
      debugPrint(
          'SequenceManager.skipToNextStop: Skipping via BufferSequenceExecutor');
      _bufferExecutor!.skipCurrentCommand();
      return;
    }

    // Delegate to SequenceTaskMode if active
    if (_activeSequenceTask != null) {
      debugPrint(
          'SequenceManager.skipToNextStop: Delegating to SequenceTaskMode');
      _activeSequenceTask!.skipToNextStop();
      return;
    }

    // Fallback to old system
    _waitTimer?.cancel();
    _callback?.onCloseDisplay();
    _status = SequenceStatus.running;
    _navigateToNextStop();
  }

  /// Sync tours to relay
  Future<bool> syncToRelay(String relayUrl) async {
    try {
      final response = await http.post(
        Uri.parse('$relayUrl/tours'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'tours': _sequences.map((k, v) => MapEntry(k, v.toJson())),
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('SequenceManager: Failed to sync to relay: $e');
      return false;
    }
  }

  /// Export tours as JSON
  String exportTours() => jsonEncode(
        _sequences.map((k, v) => MapEntry(k, v.toJson())),
      );

  /// Import tours from JSON
  void importTours(String json) {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      data.forEach((id, tourData) {
        _sequences[id] = Sequence.fromJson(tourData as Map<String, dynamic>);
      });
      save();
      notifyListeners();
    } catch (e) {
      debugPrint('SequenceManager: Failed to import: $e');
    }
  }

  @override
  void dispose() {
    _waitTimer?.cancel();
    _bufferExecutor?.removeListener(_onBufferExecutorChanged);
    _bufferExecutor?.dispose();
    super.dispose();
  }
}
