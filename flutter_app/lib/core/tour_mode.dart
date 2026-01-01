import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// A single stop in a tour with waypoint and associated actions
class TourStop {
  final String waypoint;
  final String? speakText;       // TTS text at this stop
  final String? displayUrl;      // URL to display (website/image)
  final int displayDuration;     // How long to show display (0 = until next nav)
  final int waitSeconds;         // Extra wait time at stop

  const TourStop({
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

  factory TourStop.fromJson(Map<String, dynamic> json) => TourStop(
    waypoint: json['waypoint'] as String? ?? '',
    speakText: json['speak_text'] as String?,
    displayUrl: json['display_url'] as String?,
    displayDuration: json['display_duration'] as int? ?? 0,
    waitSeconds: json['wait_seconds'] as int? ?? 0,
  );

  TourStop copyWith({
    String? waypoint,
    String? speakText,
    String? displayUrl,
    int? displayDuration,
    int? waitSeconds,
  }) => TourStop(
    waypoint: waypoint ?? this.waypoint,
    speakText: speakText ?? this.speakText,
    displayUrl: displayUrl ?? this.displayUrl,
    displayDuration: displayDuration ?? this.displayDuration,
    waitSeconds: waitSeconds ?? this.waitSeconds,
  );
}

/// A complete tour with ordered stops
class Tour {
  final String id;
  final String name;
  final String description;
  final List<TourStop> stops;
  final bool loop;              // Loop back to start after completion
  final bool announceArrival;   // Say "Arrived at [waypoint]" before custom text
  final String? introText;      // Speak before starting tour
  final String? outroText;      // Speak after completing tour
  final String? startWaypoint;  // Navigate here before starting tour
  final String? endWaypoint;    // Navigate here after completing tour

  const Tour({
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
  });

  /// Create tour from waypoint list with auto-loaded scripts
  static Tour fromWaypointList({
    required String id,
    required String name,
    required List<String> waypoints,
    Map<String, String> scripts = const {},
    Map<String, String> displayUrls = const {},
  }) {
    return Tour(
      id: id,
      name: name,
      stops: waypoints.map((wp) => TourStop(
        waypoint: wp,
        speakText: scripts[wp],
        displayUrl: displayUrls[wp],
      )).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'stops': stops.map((s) => s.toJson()).toList(),
    'loop': loop,
    'announce_arrival': announceArrival,
    if (introText != null) 'intro_text': introText,
    if (outroText != null) 'outro_text': outroText,
    if (startWaypoint != null) 'start_waypoint': startWaypoint,
    if (endWaypoint != null) 'end_waypoint': endWaypoint,
  };

  factory Tour.fromJson(Map<String, dynamic> json) => Tour(
    id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
    name: json['name'] as String? ?? 'Untitled Tour',
    description: json['description'] as String? ?? '',
    stops: (json['stops'] as List<dynamic>?)
        ?.map((s) => TourStop.fromJson(s as Map<String, dynamic>))
        .toList() ?? [],
    loop: json['loop'] as bool? ?? false,
    announceArrival: json['announce_arrival'] as bool? ?? false,
    introText: json['intro_text'] as String?,
    outroText: json['outro_text'] as String?,
    startWaypoint: json['start_waypoint'] as String?,
    endWaypoint: json['end_waypoint'] as String?,
  );

  Tour copyWith({
    String? id,
    String? name,
    String? description,
    List<TourStop>? stops,
    bool? loop,
    bool? announceArrival,
    String? introText,
    String? outroText,
    String? startWaypoint,
    String? endWaypoint,
  }) => Tour(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    stops: stops ?? this.stops,
    loop: loop ?? this.loop,
    announceArrival: announceArrival ?? this.announceArrival,
    introText: introText ?? this.introText,
    outroText: outroText ?? this.outroText,
    startWaypoint: startWaypoint ?? this.startWaypoint,
    endWaypoint: endWaypoint ?? this.endWaypoint,
  );

  /// Add a stop
  Tour addStop(TourStop stop) => copyWith(
    stops: [...stops, stop],
  );

  /// Remove a stop by index
  Tour removeStop(int index) => copyWith(
    stops: [...stops]..removeAt(index),
  );

  /// Reorder stops
  Tour reorderStop(int oldIndex, int newIndex) {
    final newStops = [...stops];
    final item = newStops.removeAt(oldIndex);
    newStops.insert(newIndex, item);
    return copyWith(stops: newStops);
  }

  /// Update a stop
  Tour updateStop(int index, TourStop stop) {
    final newStops = [...stops];
    newStops[index] = stop;
    return copyWith(stops: newStops);
  }
}

/// Tour execution status
enum TourStatus {
  idle,
  running,
  paused,
  completed,
  failed,
}

/// Callback interface for tour execution
abstract class TourExecutorCallback {
  void onSpeak(String text);
  void onDisplay(String url, int durationSeconds);
  void onDisplayDefault(String waypoint);  // Show company branding when no media
  void onCloseDisplay();
  void onNavigate(String waypoint);
  void onTourStarted(Tour tour);
  void onTourStopped(TourStop? currentStop, int stopIndex);
  void onTourCompleted();
  void onTourFailed(String reason);
  void onStopArrived(TourStop stop, int stopIndex);
}

/// Tour manager - saves/loads tours and manages execution
class TourManager extends ChangeNotifier {
  static const String _toursKey = 'saved_tours';
  static TourManager? _instance;

  final Map<String, Tour> _tours = {};
  bool _loaded = false;

  // Execution state
  Tour? _currentTour;
  int _currentStopIndex = -1;
  TourStatus _status = TourStatus.idle;
  Timer? _waitTimer;
  TourExecutorCallback? _callback;

  static TourManager get instance {
    _instance ??= TourManager._();
    return _instance!;
  }

  TourManager._();

  // Getters
  TourStatus get status => _status;
  Tour? get currentTour => _currentTour;
  int get currentStopIndex => _currentStopIndex;
  TourStop? get currentStop =>
      _currentTour != null && _currentStopIndex >= 0 && _currentStopIndex < _currentTour!.stops.length
          ? _currentTour!.stops[_currentStopIndex]
          : null;
  List<Tour> get tours => _tours.values.toList();

  /// Set the callback for tour execution
  void setCallback(TourExecutorCallback callback) {
    _callback = callback;
  }

  /// Load tours from storage
  Future<void> load() async {
    if (_loaded) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final toursJson = prefs.getString(_toursKey);
      if (toursJson != null) {
        final tours = jsonDecode(toursJson) as Map<String, dynamic>;
        tours.forEach((id, data) {
          _tours[id] = Tour.fromJson(data as Map<String, dynamic>);
        });
      }
      _loaded = true;
      debugPrint('TourManager: Loaded ${_tours.length} tours');
      notifyListeners();
    } catch (e) {
      debugPrint('TourManager: Failed to load: $e');
    }
  }

  /// Save tours to storage
  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final toursJson = jsonEncode(
        _tours.map((k, v) => MapEntry(k, v.toJson())),
      );
      await prefs.setString(_toursKey, toursJson);
      debugPrint('TourManager: Saved ${_tours.length} tours');
    } catch (e) {
      debugPrint('TourManager: Failed to save: $e');
    }
  }

  /// Get a tour by ID
  Tour? getTour(String id) => _tours[id];

  /// Save a tour
  void saveTour(Tour tour) {
    _tours[tour.id] = tour;
    save();
    notifyListeners();
  }

  /// Delete a tour
  void deleteTour(String tourId) {
    _tours.remove(tourId);
    save();
    notifyListeners();
  }

  /// Start a tour
  Future<void> startTour(Tour tour) async {
    if (_status == TourStatus.running) {
      debugPrint('TourManager: Cannot start - tour already running');
      return;
    }

    _currentTour = tour;
    _currentStopIndex = -1;
    _status = TourStatus.running;
    notifyListeners();

    _callback?.onTourStarted(tour);

    // Play intro if configured
    if (tour.introText != null && tour.introText!.isNotEmpty) {
      _callback?.onSpeak(tour.introText!);
      await Future.delayed(const Duration(seconds: 2)); // Wait for TTS
    }

    // Navigate to first stop
    _navigateToNextStop();
  }

  /// Called when robot arrives at a waypoint
  void onArrived(String waypoint) {
    debugPrint('TourManager: onArrived($waypoint) - status=$_status, tour=${_currentTour?.name}, stopIndex=$_currentStopIndex');

    if (_status != TourStatus.running) {
      debugPrint('TourManager: Ignoring arrival - tour not running');
      return;
    }
    if (_currentTour == null) {
      debugPrint('TourManager: Ignoring arrival - no current tour');
      return;
    }

    final stop = currentStop;
    if (stop == null) {
      debugPrint('TourManager: Ignoring arrival - no current stop (index=$_currentStopIndex, stops=${_currentTour!.stops.length})');
      return;
    }

    debugPrint('TourManager: Checking arrival - expected="${stop.waypoint}", got="$waypoint"');
    if (stop.waypoint == waypoint) {
      debugPrint('TourManager: Arrived at ${stop.waypoint}');
      _executeStopActions();
    } else {
      debugPrint('TourManager: Waypoint mismatch - ignoring');
    }
  }

  /// Estimate TTS duration based on text length
  /// Uses conservative estimate: ~2 words/sec (120 words/min) to account for pauses
  Duration _estimateTtsDuration(String text) {
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final seconds = (words / 2.0).ceil(); // ~120 words/min = 2 words/sec (conservative)
    return Duration(seconds: seconds.clamp(2, 60)); // Min 2 sec, max 60 sec
  }

  /// Execute actions at current stop - properly sequenced to avoid race conditions
  Future<void> _executeStopActions() async {
    final stop = currentStop;
    if (stop == null) {
      debugPrint('TourManager: _executeStopActions - no current stop!');
      return;
    }

    debugPrint('TourManager: Executing actions at ${stop.waypoint}');
    debugPrint('  - speakText: ${stop.speakText?.substring(0, (stop.speakText?.length ?? 0).clamp(0, 50))}...');
    debugPrint('  - displayUrl: ${stop.displayUrl}');
    debugPrint('  - announceArrival: ${_currentTour?.announceArrival}');

    _callback?.onStopArrived(stop, _currentStopIndex);

    // Step 1: Display content FIRST (so user sees it while TTS plays)
    if (stop.displayUrl != null && stop.displayUrl!.isNotEmpty) {
      debugPrint('TourManager: Showing display URL: ${stop.displayUrl}');
      _callback?.onDisplay(stop.displayUrl!, stop.displayDuration);
    } else {
      // Default: Show company name when no media configured
      debugPrint('TourManager: Showing default branding for ${stop.waypoint}');
      _callback?.onDisplayDefault(stop.waypoint);
    }

    // Brief pause for display to render
    await Future.delayed(const Duration(milliseconds: 500));

    // Step 2: Announce arrival if enabled (wait for TTS to finish)
    if (_currentTour?.announceArrival == true) {
      final arrivalText = 'Arrived at ${stop.waypoint}';
      debugPrint('TourManager: Speaking arrival: $arrivalText');
      _callback?.onSpeak(arrivalText);
      final arrivalDuration = _estimateTtsDuration(arrivalText);
      debugPrint('TourManager: Waiting ${arrivalDuration.inSeconds}s for arrival TTS');
      await Future.delayed(arrivalDuration + const Duration(milliseconds: 500));
    }

    // Step 3: Speak custom text (wait for it to finish)
    if (stop.speakText != null && stop.speakText!.isNotEmpty) {
      debugPrint('TourManager: Speaking tour text (${stop.speakText!.split(' ').length} words)');
      _callback?.onSpeak(stop.speakText!);
      final ttsDuration = _estimateTtsDuration(stop.speakText!);
      debugPrint('TourManager: Waiting ${ttsDuration.inSeconds}s for tour TTS');
      await Future.delayed(ttsDuration);
    }

    // Step 4: Wait at stop then continue
    // Wait time is ADDITIONAL time after TTS - media stays until robot leaves
    // Minimum wait: 10 seconds for media to play, or displayDuration if specified
    final minMediaTime = (stop.displayUrl != null && stop.displayUrl!.isNotEmpty) ? 10 : 0;
    final waitTime = stop.waitSeconds > 0
        ? stop.waitSeconds
        : (stop.displayDuration > 0 ? stop.displayDuration : minMediaTime);

    debugPrint('TourManager: Extra wait time: ${waitTime}s before next stop (media plays until departure)');
    _waitTimer = Timer(Duration(seconds: waitTime), () {
      debugPrint('TourManager: Wait complete, navigating to next stop (display stays until departure)');
      // NOTE: Do NOT close display here - it stays until robot leaves (AudioAnnouncer handles that)
      _navigateToNextStop();
    });
  }

  /// Navigate to next stop
  void _navigateToNextStop() {
    if (_currentTour == null) return;

    _currentStopIndex++;

    if (_currentStopIndex >= _currentTour!.stops.length) {
      // Tour complete
      if (_currentTour!.loop) {
        _currentStopIndex = 0;
      } else {
        _completeTour();
        return;
      }
    }

    final stop = currentStop;
    if (stop != null) {
      debugPrint('TourManager: Navigating to ${stop.waypoint}');
      _callback?.onNavigate(stop.waypoint);
      notifyListeners();
    }
  }

  /// Complete the tour
  void _completeTour() {
    // Play outro if configured
    if (_currentTour?.outroText != null && _currentTour!.outroText!.isNotEmpty) {
      _callback?.onSpeak(_currentTour!.outroText!);
    }

    // Navigate to end waypoint if configured (e.g., return to charging station)
    if (_currentTour?.endWaypoint != null && _currentTour!.endWaypoint!.isNotEmpty) {
      debugPrint('TourManager: Navigating to end waypoint: ${_currentTour!.endWaypoint}');
      _callback?.onNavigate(_currentTour!.endWaypoint!);
    }

    _status = TourStatus.completed;
    _callback?.onTourCompleted();
    notifyListeners();

    // Reset after a delay
    Future.delayed(const Duration(seconds: 3), () {
      _currentTour = null;
      _currentStopIndex = -1;
      _status = TourStatus.idle;
      notifyListeners();
    });
  }

  /// Stop the current tour
  void stopTour() {
    if (_status != TourStatus.running) return;

    _waitTimer?.cancel();
    _waitTimer = null;
    _callback?.onCloseDisplay();
    _callback?.onTourStopped(currentStop, _currentStopIndex);

    _status = TourStatus.idle;
    _currentTour = null;
    _currentStopIndex = -1;
    notifyListeners();
  }

  /// Pause the current tour
  void pauseTour() {
    if (_status != TourStatus.running) return;
    _waitTimer?.cancel();
    _status = TourStatus.paused;
    notifyListeners();
  }

  /// Resume a paused tour
  void resumeTour() {
    if (_status != TourStatus.paused) return;
    _status = TourStatus.running;
    _navigateToNextStop();
    notifyListeners();
  }

  /// Skip to next stop
  void skipToNextStop() {
    if (_status != TourStatus.running && _status != TourStatus.paused) return;
    _waitTimer?.cancel();
    _callback?.onCloseDisplay();
    _status = TourStatus.running;
    _navigateToNextStop();
  }

  /// Sync tours to relay
  Future<bool> syncToRelay(String relayUrl) async {
    try {
      final response = await http.post(
        Uri.parse('$relayUrl/tours'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'tours': _tours.map((k, v) => MapEntry(k, v.toJson())),
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('TourManager: Failed to sync to relay: $e');
      return false;
    }
  }

  /// Export tours as JSON
  String exportTours() => jsonEncode(
    _tours.map((k, v) => MapEntry(k, v.toJson())),
  );

  /// Import tours from JSON
  void importTours(String json) {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      data.forEach((id, tourData) {
        _tours[id] = Tour.fromJson(tourData as Map<String, dynamic>);
      });
      save();
      notifyListeners();
    } catch (e) {
      debugPrint('TourManager: Failed to import: $e');
    }
  }

  @override
  void dispose() {
    _waitTimer?.cancel();
    super.dispose();
  }
}
