import 'dart:convert';
import 'package:http/http.dart' as http;

/// Task types that can be performed at waypoints
enum TaskType {
  none('None', 'No task'),
  deliver('Deliver', 'Announce arrival and wait for pickup'),
  speak('Speak', 'Text-to-speech announcement'),
  display('Display', 'Show webpage or video on tablet');

  final String label;
  final String description;
  const TaskType(this.label, this.description);
}

/// A task to execute at a waypoint
class WaypointTask {
  final TaskType type;
  final String data;       // For SPEAK: text, for DISPLAY: URL, for DELIVER: message
  final int waitSeconds;   // How long to wait (for DELIVER)

  const WaypointTask({
    this.type = TaskType.none,
    this.data = '',
    this.waitSeconds = 30,
  });

  Map<String, dynamic> toJson() => {
    'type': type.name.toUpperCase(),
    'data': data,
    'wait_seconds': waitSeconds,
  };

  factory WaypointTask.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'none';
    return WaypointTask(
      type: TaskType.values.firstWhere(
        (t) => t.name.toUpperCase() == typeStr.toUpperCase(),
        orElse: () => TaskType.none,
      ),
      data: json['data'] as String? ?? '',
      waitSeconds: json['wait_seconds'] as int? ?? 30,
    );
  }

  WaypointTask copyWith({
    TaskType? type,
    String? data,
    int? waitSeconds,
  }) => WaypointTask(
    type: type ?? this.type,
    data: data ?? this.data,
    waitSeconds: waitSeconds ?? this.waitSeconds,
  );
}

/// Configuration of waypoints and their tasks
class WaypointConfig {
  final Map<String, WaypointTask> _tasks = {};

  /// Get task for a waypoint
  WaypointTask getTask(String waypoint) =>
      _tasks[waypoint] ?? const WaypointTask();

  /// Set task for a waypoint
  void setTask(String waypoint, WaypointTask task) {
    _tasks[waypoint] = task;
  }

  /// Remove task for a waypoint
  void removeTask(String waypoint) {
    _tasks.remove(waypoint);
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
