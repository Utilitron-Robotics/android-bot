import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Task types for UI selection (kept for backwards compat, but now tasks stack)
enum TaskType {
  none('None', 'No task - just announce arrival'),
  deliver('Deliver', 'Wait for pickup and return to origin'),
  speak('Speak', 'Text-to-speech announcement'),
  display('Display', 'Show webpage or video on tablet');

  final String label;
  final String description;
  const TaskType(this.label, this.description);
}

/// A task to execute at a waypoint - now supports stacking speak + display
class WaypointTask {
  final String? speakText;       // Text to speak on arrival (null = don't speak)
  final String? displayUrl;      // URL to display on tablet (null = don't display)
  final int displayDuration;     // How long to show display (0 = until next nav)
  final bool announceArrival;    // Say "Arrived at [waypoint]" before custom text
  final int waitSeconds;         // For delivery: how long to wait for pickup
  final bool returnToOrigin;     // For delivery: return to previous waypoint after
  final String? returnWaypoint;  // Specific waypoint to return to (null = previous)

  const WaypointTask({
    this.speakText,
    this.displayUrl,
    this.displayDuration = 0,
    this.announceArrival = true,
    this.waitSeconds = 30,
    this.returnToOrigin = false,
    this.returnWaypoint,
  });

  /// Legacy getter for UI compatibility
  TaskType get type {
    if (returnToOrigin) return TaskType.deliver;
    if (displayUrl != null && displayUrl!.isNotEmpty) return TaskType.display;
    if (speakText != null && speakText!.isNotEmpty) return TaskType.speak;
    return TaskType.none;
  }

  /// Legacy getter - returns speakText or displayUrl for backwards compat
  String get data => speakText ?? displayUrl ?? '';

  /// Check if this task has any actions configured
  bool get hasActions =>
      (speakText != null && speakText!.isNotEmpty) ||
      (displayUrl != null && displayUrl!.isNotEmpty) ||
      returnToOrigin;

  Map<String, dynamic> toJson() => {
    if (speakText != null) 'speak_text': speakText,
    if (displayUrl != null) 'display_url': displayUrl,
    'display_duration': displayDuration,
    'announce_arrival': announceArrival,
    'wait_seconds': waitSeconds,
    'return_to_origin': returnToOrigin,
    if (returnWaypoint != null) 'return_waypoint': returnWaypoint,
  };

  factory WaypointTask.fromJson(Map<String, dynamic> json) {
    // Handle legacy format with 'type' and 'data' fields
    if (json.containsKey('type') && !json.containsKey('speak_text')) {
      final typeStr = json['type'] as String? ?? 'none';
      final data = json['data'] as String? ?? '';
      final type = TaskType.values.firstWhere(
        (t) => t.name.toUpperCase() == typeStr.toUpperCase(),
        orElse: () => TaskType.none,
      );

      return WaypointTask(
        speakText: (type == TaskType.speak || type == TaskType.deliver) ? data : null,
        displayUrl: type == TaskType.display ? data : null,
        waitSeconds: json['wait_seconds'] as int? ?? 30,
        returnToOrigin: type == TaskType.deliver,
      );
    }

    // New format
    return WaypointTask(
      speakText: json['speak_text'] as String?,
      displayUrl: json['display_url'] as String?,
      displayDuration: json['display_duration'] as int? ?? 0,
      announceArrival: json['announce_arrival'] as bool? ?? true,
      waitSeconds: json['wait_seconds'] as int? ?? 30,
      returnToOrigin: json['return_to_origin'] as bool? ?? false,
      returnWaypoint: json['return_waypoint'] as String?,
    );
  }

  WaypointTask copyWith({
    String? speakText,
    String? displayUrl,
    int? displayDuration,
    bool? announceArrival,
    int? waitSeconds,
    bool? returnToOrigin,
    String? returnWaypoint,
  }) => WaypointTask(
    speakText: speakText ?? this.speakText,
    displayUrl: displayUrl ?? this.displayUrl,
    displayDuration: displayDuration ?? this.displayDuration,
    announceArrival: announceArrival ?? this.announceArrival,
    waitSeconds: waitSeconds ?? this.waitSeconds,
    returnToOrigin: returnToOrigin ?? this.returnToOrigin,
    returnWaypoint: returnWaypoint ?? this.returnWaypoint,
  );
}

/// Configuration of waypoints and their tasks
class WaypointConfig {
  static const String _prefsKey = 'waypoint_tasks';
  static WaypointConfig? _instance;

  final Map<String, WaypointTask> _tasks = {};
  bool _loaded = false;

  /// Get singleton instance
  static WaypointConfig get instance {
    _instance ??= WaypointConfig._();
    return _instance!;
  }

  WaypointConfig._();

  /// For backwards compatibility - creates new instance (use .instance for persistence)
  factory WaypointConfig() => WaypointConfig._();

  /// Load tasks from SharedPreferences
  Future<void> load() async {
    if (_loaded) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefsKey);
      if (jsonStr != null) {
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        loadFromJson(json);
        debugPrint('WaypointConfig: Loaded ${_tasks.length} tasks from storage');
      }
      _loaded = true;
    } catch (e) {
      debugPrint('WaypointConfig: Failed to load: $e');
    }
  }

  /// Save tasks to SharedPreferences
  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(toJson());
      await prefs.setString(_prefsKey, jsonStr);
      debugPrint('WaypointConfig: Saved ${_tasks.length} tasks to storage');
    } catch (e) {
      debugPrint('WaypointConfig: Failed to save: $e');
    }
  }

  /// Get task for a waypoint
  WaypointTask getTask(String waypoint) =>
      _tasks[waypoint] ?? const WaypointTask();

  /// Set task for a waypoint (auto-saves)
  void setTask(String waypoint, WaypointTask task) {
    _tasks[waypoint] = task;
    save(); // Auto-save on change
  }

  /// Remove task for a waypoint (auto-saves)
  void removeTask(String waypoint) {
    _tasks.remove(waypoint);
    save(); // Auto-save on change
  }

  /// Get all configured waypoints
  List<String> get configuredWaypoints => _tasks.keys.toList();

  /// Export to JSON for persistence
  Map<String, dynamic> toJson() => _tasks.map(
    (key, value) => MapEntry(key, value.toJson()),
  );

  /// Import from JSON
  void loadFromJson(Map<String, dynamic> json) {
    _tasks.clear();
    json.forEach((key, value) {
      _tasks[key] = WaypointTask.fromJson(value as Map<String, dynamic>);
    });
  }
}

/// Client to send tasks to the tablet relay
class TabletTaskClient {
  final String relayBaseUrl;

  TabletTaskClient(this.relayBaseUrl);

  /// Send a speak command to the tablet
  Future<bool> speak(String text) async {
    try {
      final response = await http.post(
        Uri.parse('$relayBaseUrl/speak'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text}),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Display a URL on the tablet
  Future<bool> display(String url) async {
    try {
      final response = await http.post(
        Uri.parse('$relayBaseUrl/display'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'url': url}),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Close displayed content
  Future<bool> closeDisplay() async {
    try {
      final response = await http.delete(
        Uri.parse('$relayBaseUrl/display'),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Execute a full waypoint task
  Future<bool> executeTask(WaypointTask task) async {
    if (task.type == TaskType.none) return true;

    try {
      final response = await http.post(
        Uri.parse('$relayBaseUrl/task'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(task.toJson()),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Cancel current task
  Future<bool> cancelTask() async {
    try {
      final response = await http.delete(
        Uri.parse('$relayBaseUrl/task'),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
