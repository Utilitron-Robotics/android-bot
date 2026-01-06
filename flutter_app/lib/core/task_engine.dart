import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Individual task actions that can be performed
enum TaskAction {
  speak('Speak', 'Text-to-speech announcement'),
  display('Display', 'Show URL on tablet screen'),
  wait('Wait', 'Pause for specified duration'),
  navigate('Navigate', 'Go to a waypoint'),
  returnOrigin('Return', 'Return to starting point');

  final String label;
  final String description;
  const TaskAction(this.label, this.description);
}

/// A single step in a task mode
class TaskStep {
  final String id;
  final TaskAction action;
  final String data; // Text for speak, URL for display, waypoint for navigate
  final int durationSeconds; // How long (for wait, display timeout)
  final bool parallel; // Run with next step in parallel?

  const TaskStep({
    required this.id,
    required this.action,
    this.data = '',
    this.durationSeconds = 0,
    this.parallel = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'action': action.name,
        'data': data,
        'duration_seconds': durationSeconds,
        'parallel': parallel,
      };

  factory TaskStep.fromJson(Map<String, dynamic> json) => TaskStep(
        id: json['id'] as String? ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        action: TaskAction.values.firstWhere(
          (a) => a.name == json['action'],
          orElse: () => TaskAction.speak,
        ),
        data: json['data'] as String? ?? '',
        durationSeconds: json['duration_seconds'] as int? ?? 0,
        parallel: json['parallel'] as bool? ?? false,
      );

  TaskStep copyWith({
    String? id,
    TaskAction? action,
    String? data,
    int? durationSeconds,
    bool? parallel,
  }) =>
      TaskStep(
        id: id ?? this.id,
        action: action ?? this.action,
        data: data ?? this.data,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        parallel: parallel ?? this.parallel,
      );
}

/// Mode types - how the mode operates
enum ModeType {
  perWaypoint('Per-Waypoint', 'Executes when arriving at assigned waypoint'),
  sequence('Sequence', 'Executes through multiple waypoints in order');

  final String label;
  final String description;
  const ModeType(this.label, this.description);
}

/// A WaypointTask is a named group of ordered task steps assigned to a waypoint
/// This defines WHAT happens at a waypoint (speak, display, wait, etc.)
class WaypointTask {
  final String id;
  final String name;
  final String description;
  final List<TaskStep> steps;
  final bool announceArrival; // Say "Arrived at [waypoint]" first
  final bool isDefault; // Default tasks can't be deleted, only reset
  final ModeType modeType; // How this task operates

  const WaypointTask({
    required this.id,
    required this.name,
    this.description = '',
    this.steps = const [],
    this.announceArrival = true,
    this.isDefault = false,
    this.modeType = ModeType.perWaypoint,
  });

  // Legacy getter for compatibility
  bool get isBuiltIn => isDefault;

  /// Built-in Delivery mode: speak + display + wait + return
  static WaypointTask delivery({
    String speakText = 'Your delivery has arrived',
    String displayUrl = '',
    int waitSeconds = 30,
  }) =>
      WaypointTask(
        id: 'delivery',
        name: 'Delivery',
        description: 'Announce arrival, wait for pickup, return to origin',
        isDefault: true,
        steps: [
          if (speakText.isNotEmpty)
            TaskStep(
                id: '1',
                action: TaskAction.speak,
                data: speakText,
                parallel: displayUrl.isNotEmpty),
          if (displayUrl.isNotEmpty)
            TaskStep(
                id: '2',
                action: TaskAction.display,
                data: displayUrl,
                durationSeconds: waitSeconds),
          TaskStep(
              id: '3', action: TaskAction.wait, durationSeconds: waitSeconds),
          const TaskStep(id: '4', action: TaskAction.returnOrigin),
        ],
      );

  /// Built-in Announce mode: just speak + display (no return)
  static WaypointTask announce({
    String speakText = '',
    String displayUrl = '',
    int displayDuration = 5,
  }) =>
      WaypointTask(
        id: 'announce',
        name: 'Announce',
        description: 'Speak and/or display content',
        isDefault: true,
        steps: [
          if (speakText.isNotEmpty)
            TaskStep(
                id: '1',
                action: TaskAction.speak,
                data: speakText,
                parallel: displayUrl.isNotEmpty),
          if (displayUrl.isNotEmpty)
            TaskStep(
                id: '2',
                action: TaskAction.display,
                data: displayUrl,
                durationSeconds: displayDuration),
        ],
      );

  /// Built-in Comic mode: attention beep, tell joke, wait for laughter
  static WaypointTask comic({
    String jokeText = 'Why did the robot go to therapy? Because it had too many bugs!',
    String punchlineUrl = '',
    int laughterWait = 3,
  }) =>
      WaypointTask(
        id: 'comic',
        name: 'Comic',
        description: 'Tell a joke and wait for laughter',
        isDefault: true,
        announceArrival: false, // Don't announce, just tell joke
        steps: [
          const TaskStep(
              id: '1',
              action: TaskAction.speak,
              data: 'beep'), // Attention beep
          TaskStep(
              id: '2',
              action: TaskAction.speak,
              data: jokeText,
              parallel: punchlineUrl.isNotEmpty),
          if (punchlineUrl.isNotEmpty)
            TaskStep(
                id: '3',
                action: TaskAction.display,
                data: punchlineUrl,
                durationSeconds: laughterWait + 2),
          TaskStep(
              id: '4',
              action: TaskAction.wait,
              durationSeconds: laughterWait),
        ],
      );

  /// Built-in Greeter mode: welcome message, display logo, wait for interaction
  static WaypointTask greeter({
    String greetingText = 'Welcome! How can I help you today?',
    String logoUrl = '',
    int waitSeconds = 30,
  }) =>
      WaypointTask(
        id: 'greeter',
        name: 'Greeter',
        description: 'Welcome visitors and wait for interaction',
        isDefault: true,
        announceArrival: false,
        steps: [
          const TaskStep(
              id: '1',
              action: TaskAction.speak,
              data: 'chime'), // Friendly chime
          TaskStep(
              id: '2',
              action: TaskAction.speak,
              data: greetingText,
              parallel: logoUrl.isNotEmpty),
          if (logoUrl.isNotEmpty)
            TaskStep(
                id: '3',
                action: TaskAction.display,
                data: logoUrl,
                durationSeconds: waitSeconds),
          TaskStep(
              id: '4',
              action: TaskAction.wait,
              durationSeconds: waitSeconds),
        ],
      );

  /// Built-in Busser mode: ask for items, wait, then return to bus station
  static WaypointTask busser({
    String askText = 'Please place any finished items on my tray',
    String loadingUrl = '',
    int waitSeconds = 20,
  }) =>
      WaypointTask(
        id: 'busser',
        name: 'Busser',
        description: 'Collect finished items from tables',
        isDefault: true,
        steps: [
          TaskStep(
              id: '1',
              action: TaskAction.speak,
              data: askText,
              parallel: loadingUrl.isNotEmpty),
          if (loadingUrl.isNotEmpty)
            TaskStep(
                id: '2',
                action: TaskAction.display,
                data: loadingUrl,
                durationSeconds: waitSeconds),
          TaskStep(
              id: '3',
              action: TaskAction.wait,
              durationSeconds: waitSeconds),
          // Note: Return to bus station handled by sequence, not here
        ],
      );

  /// Built-in Emergency mode: loud alarm, evacuation announcement
  static WaypointTask emergency({
    String alertText = 'EMERGENCY! Please evacuate immediately. Follow the exit signs.',
    String evacuationMapUrl = '',
    bool repeatAlert = true,
  }) =>
      WaypointTask(
        id: 'emergency',
        name: 'Emergency',
        description: 'Emergency alert with evacuation guidance',
        isDefault: true,
        announceArrival: false,
        steps: [
          const TaskStep(
              id: '1',
              action: TaskAction.speak,
              data: 'alarm'), // Loud alarm
          TaskStep(
              id: '2',
              action: TaskAction.speak,
              data: alertText,
              parallel: evacuationMapUrl.isNotEmpty),
          if (evacuationMapUrl.isNotEmpty)
            TaskStep(
                id: '3',
                action: TaskAction.display,
                data: evacuationMapUrl,
                durationSeconds: 0), // Keep displayed
          if (repeatAlert)
            const TaskStep(
                id: '4',
                action: TaskAction.wait,
                durationSeconds: 10), // Wait then repeat
          if (repeatAlert)
            TaskStep(
                id: '5',
                action: TaskAction.speak,
                data: alertText),
        ],
      );

  /// Built-in Tour Stop mode: narrate exhibit, display media
  static WaypointTask tourStop({
    String narrationText = '',
    String mediaUrl = '',
    int displayDuration = 15,
  }) =>
      WaypointTask(
        id: 'tour_stop',
        name: 'Tour Stop',
        description: 'Narrate and display content at tour stop',
        isDefault: true,
        steps: [
          if (narrationText.isNotEmpty)
            TaskStep(
                id: '1',
                action: TaskAction.speak,
                data: narrationText,
                parallel: mediaUrl.isNotEmpty),
          if (mediaUrl.isNotEmpty)
            TaskStep(
                id: '2',
                action: TaskAction.display,
                data: mediaUrl,
                durationSeconds: displayDuration),
          TaskStep(
              id: '3',
              action: TaskAction.wait,
              durationSeconds: displayDuration),
        ],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'steps': steps.map((s) => s.toJson()).toList(),
        'announce_arrival': announceArrival,
        'is_default': isDefault,
        'mode_type': modeType.name,
      };

  factory WaypointTask.fromJson(Map<String, dynamic> json) => WaypointTask(
        id: json['id'] as String? ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        name: json['name'] as String? ?? 'Custom',
        description: json['description'] as String? ?? '',
        steps: (json['steps'] as List<dynamic>?)
                ?.map((s) => TaskStep.fromJson(s as Map<String, dynamic>))
                .toList() ??
            [],
        announceArrival: json['announce_arrival'] as bool? ?? true,
        isDefault: json['is_default'] as bool? ?? json['is_built_in'] as bool? ?? false,
        modeType: ModeType.values.firstWhere(
          (t) => t.name == json['mode_type'],
          orElse: () => ModeType.perWaypoint,
        ),
      );

  WaypointTask copyWith({
    String? id,
    String? name,
    String? description,
    List<TaskStep>? steps,
    bool? announceArrival,
    bool? isDefault,
    ModeType? modeType,
  }) =>
      WaypointTask(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        steps: steps ?? this.steps,
        announceArrival: announceArrival ?? this.announceArrival,
        isDefault: isDefault ?? this.isDefault,
        modeType: modeType ?? this.modeType,
      );
}

/// Waypoint task assignment - links a waypoint to a mode
class WaypointTaskAssignment {
  final String waypointId;
  final String? modeId; // null = no task (just announce arrival)
  final Map<String, String>
      params; // Mode-specific params (speakText, displayUrl, etc)

  const WaypointTaskAssignment({
    required this.waypointId,
    this.modeId,
    this.params = const {},
  });

  Map<String, dynamic> toJson() => {
        'waypoint_id': waypointId,
        if (modeId != null) 'mode_id': modeId,
        if (params.isNotEmpty) 'params': params,
      };

  factory WaypointTaskAssignment.fromJson(Map<String, dynamic> json) =>
      WaypointTaskAssignment(
        waypointId: json['waypoint_id'] as String? ?? '',
        modeId: json['mode_id'] as String?,
        params: (json['params'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, v.toString()),
            ) ??
            {},
      );
}

/// Callback interface for task execution
abstract class TaskExecutorCallback {
  void onSpeak(String text);
  void onDisplay(String url, int durationSeconds);
  void onDisplayDefault(String waypoint); // Show default waypoint display
  void onCloseDisplay();
  void onNavigate(String waypoint);
  void onWait(int seconds);
}

/// Task execution engine - runs modes step by step
class TaskEngine extends ChangeNotifier {
  static const String _modesKey = 'task_modes';
  static const String _assignmentsKey = 'waypoint_mode_assignments';
  static TaskEngine? _instance;

  final Map<String, WaypointTask> _modes = {};
  final Map<String, WaypointTaskAssignment> _assignments = {};
  bool _loaded = false;

  // Execution state
  String? _currentWaypoint;
  WaypointTask? _currentMode;
  int _currentStepIndex = 0;
  bool _isExecuting = false;
  String? _originWaypoint; // For return-to-origin
  Timer? _waitTimer;
  TaskExecutorCallback? _callback;

  static TaskEngine get instance {
    _instance ??= TaskEngine._();
    return _instance!;
  }

  TaskEngine._();

  bool get isExecuting => _isExecuting;
  String? get currentWaypoint => _currentWaypoint;
  WaypointTask? get currentMode => _currentMode;

  /// Set the callback for task execution
  void setCallback(TaskExecutorCallback callback) {
    _callback = callback;
  }

  /// Load modes and assignments from storage
  Future<void> load() async {
    if (_loaded) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      // Load custom modes
      final modesJson = prefs.getString(_modesKey);
      if (modesJson != null) {
        final modes = jsonDecode(modesJson) as Map<String, dynamic>;
        modes.forEach((id, data) {
          _modes[id] = WaypointTask.fromJson(data as Map<String, dynamic>);
        });
      }

      // Load waypoint assignments
      final assignJson = prefs.getString(_assignmentsKey);
      if (assignJson != null) {
        final assigns = jsonDecode(assignJson) as Map<String, dynamic>;
        assigns.forEach((wp, data) {
          _assignments[wp] =
              WaypointTaskAssignment.fromJson(data as Map<String, dynamic>);
        });
      }

      _loaded = true;
      debugPrint(
          'TaskEngine: Loaded ${_modes.length} modes, ${_assignments.length} assignments');
    } catch (e) {
      debugPrint('TaskEngine: Failed to load: $e');
    }
  }

  /// Save modes and assignments to storage
  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Save custom modes (not built-in)
      final modesJson = jsonEncode(
        Map.fromEntries(_modes.entries
            .where((e) => !e.value.isBuiltIn)
            .map((e) => MapEntry(e.key, e.value.toJson()))),
      );
      await prefs.setString(_modesKey, modesJson);

      // Save assignments
      final assignJson = jsonEncode(
        _assignments.map((k, v) => MapEntry(k, v.toJson())),
      );
      await prefs.setString(_assignmentsKey, assignJson);

      debugPrint(
          'TaskEngine: Saved ${_modes.length} modes, ${_assignments.length} assignments');
    } catch (e) {
      debugPrint('TaskEngine: Failed to save: $e');
    }
  }

  /// Get all available modes (built-in + custom)
  List<WaypointTask> get allModes {
    final builtIn = [
      WaypointTask.delivery(),
      WaypointTask.announce(),
      WaypointTask.comic(),
      WaypointTask.greeter(),
      WaypointTask.busser(),
      WaypointTask.emergency(),
      WaypointTask.tourStop(),
    ];
    return [...builtIn, ..._modes.values.where((m) => !m.isBuiltIn)];
  }

  /// Add or update a custom mode
  void saveMode(WaypointTask mode) {
    _modes[mode.id] = mode;
    save();
    notifyListeners();
  }

  /// Delete a custom mode
  void deleteMode(String modeId) {
    _modes.remove(modeId);
    // Clear any assignments using this mode
    _assignments.removeWhere((_, v) => v.modeId == modeId);
    save();
    notifyListeners();
  }

  /// Assign a mode to a waypoint
  void assignMode(String waypoint, String? modeId,
      {Map<String, String> params = const {}}) {
    if (modeId == null) {
      _assignments.remove(waypoint);
    } else {
      _assignments[waypoint] = WaypointTaskAssignment(
        waypointId: waypoint,
        modeId: modeId,
        params: params,
      );
    }
    save();
    notifyListeners();
  }

  /// Get the mode assignment for a waypoint
  WaypointTaskAssignment? getAssignment(String waypoint) =>
      _assignments[waypoint];

  /// Get a mode by ID (with parameter substitution)
  WaypointTask? getMode(String modeId, {Map<String, String> params = const {}}) {
    // Check built-in modes first
    switch (modeId) {
      case 'delivery':
        return WaypointTask.delivery(
          speakText: params['speak_text'] ?? 'Your delivery has arrived',
          displayUrl: params['display_url'] ?? '',
          waitSeconds: int.tryParse(params['wait_seconds'] ?? '30') ?? 30,
        );

      case 'announce':
        return WaypointTask.announce(
          speakText: params['speak_text'] ?? '',
          displayUrl: params['display_url'] ?? '',
          displayDuration: int.tryParse(params['display_duration'] ?? '5') ?? 5,
        );

      case 'comic':
        return WaypointTask.comic(
          jokeText: params['joke_text'] ?? 'Why did the robot go to therapy? Because it had too many bugs!',
          punchlineUrl: params['punchline_url'] ?? '',
          laughterWait: int.tryParse(params['laughter_wait'] ?? '3') ?? 3,
        );

      case 'greeter':
        return WaypointTask.greeter(
          greetingText: params['greeting_text'] ?? 'Welcome! How can I help you today?',
          logoUrl: params['logo_url'] ?? '',
          waitSeconds: int.tryParse(params['wait_seconds'] ?? '30') ?? 30,
        );

      case 'busser':
        return WaypointTask.busser(
          askText: params['ask_text'] ?? 'Please place any finished items on my tray',
          loadingUrl: params['loading_url'] ?? '',
          waitSeconds: int.tryParse(params['wait_seconds'] ?? '20') ?? 20,
        );

      case 'emergency':
        return WaypointTask.emergency(
          alertText: params['alert_text'] ?? 'EMERGENCY! Please evacuate immediately. Follow the exit signs.',
          evacuationMapUrl: params['evacuation_map_url'] ?? '',
          repeatAlert: params['repeat_alert'] != 'false',
        );

      case 'tour_stop':
        return WaypointTask.tourStop(
          narrationText: params['narration_text'] ?? '',
          mediaUrl: params['media_url'] ?? '',
          displayDuration: int.tryParse(params['display_duration'] ?? '15') ?? 15,
        );

      default:
        return _modes[modeId];
    }
  }

  /// Check if waypoint has a mode assigned
  bool hasMode(String waypoint) => _assignments.containsKey(waypoint);

  /// Execute the mode assigned to a waypoint
  Future<void> executeForWaypoint(String waypoint,
      {String? fromWaypoint}) async {
    debugPrint('TaskEngine: executeForWaypoint($waypoint) called');
    debugPrint('TaskEngine: callback=${_callback != null ? "set" : "NULL"}, assignments=${_assignments.length}');

    final assignment = _assignments[waypoint];
    debugPrint('TaskEngine: assignment for $waypoint = ${assignment?.modeId ?? "NONE"}, params=${assignment?.params}');

    if (assignment == null || assignment.modeId == null) {
      // No mode - announce arrival and show default display
      // NOTE: Display stays until robot leaves (AudioAnnouncer closes it on nav start)
      debugPrint('TaskEngine: No mode assigned, showing default display');
      if (_callback != null) {
        _callback!.onDisplayDefault(waypoint);
        _callback!.onSpeak('Arrived at $waypoint');
      } else {
        debugPrint('TaskEngine: ERROR - callback is null!');
      }
      return;
    }

    final mode = getMode(assignment.modeId!, params: assignment.params);
    debugPrint('TaskEngine: mode=${mode?.name ?? "NULL"}, steps=${mode?.steps.length ?? 0}');
    if (mode == null) {
      debugPrint('TaskEngine: ERROR - mode is null for modeId=${assignment.modeId}');
      return;
    }

    _currentWaypoint = waypoint;
    _currentMode = mode;
    _originWaypoint = fromWaypoint;
    _currentStepIndex = 0;
    _isExecuting = true;
    notifyListeners();

    // Announce arrival first if enabled
    if (mode.announceArrival && _callback != null) {
      _callback!.onSpeak('Arrived at $waypoint');
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // Execute steps
    await _executeNextStep();
  }

  /// Execute current step and proceed to next
  Future<void> _executeNextStep() async {
    if (!_isExecuting || _currentMode == null) return;
    if (_currentStepIndex >= _currentMode!.steps.length) {
      _finishExecution();
      return;
    }

    final step = _currentMode!.steps[_currentStepIndex];
    final nextStep = _currentStepIndex + 1 < _currentMode!.steps.length
        ? _currentMode!.steps[_currentStepIndex + 1]
        : null;

    debugPrint(
        'TaskEngine: Executing step ${_currentStepIndex + 1}/${_currentMode!.steps.length}: ${step.action.name}');

    switch (step.action) {
      case TaskAction.speak:
        _callback?.onSpeak(step.data);
        if (step.parallel && nextStep != null) {
          _currentStepIndex++;
          _executeNextStep(); // Run next in parallel
        } else {
          await Future.delayed(
              const Duration(seconds: 2)); // Rough TTS duration
          _currentStepIndex++;
          _executeNextStep();
        }
        break;

      case TaskAction.display:
        debugPrint('TaskEngine: Displaying URL: ${step.data} for ${step.durationSeconds}s');
        _callback?.onDisplay(step.data, step.durationSeconds);
        if (step.parallel && nextStep != null) {
          _currentStepIndex++;
          _executeNextStep();
        } else if (step.durationSeconds > 0) {
          _waitTimer = Timer(Duration(seconds: step.durationSeconds), () {
            _callback?.onCloseDisplay();
            _currentStepIndex++;
            _executeNextStep();
          });
        } else {
          _currentStepIndex++;
          _executeNextStep();
        }
        break;

      case TaskAction.wait:
        _waitTimer = Timer(Duration(seconds: step.durationSeconds), () {
          _currentStepIndex++;
          _executeNextStep();
        });
        break;

      case TaskAction.navigate:
        _callback?.onNavigate(step.data);
        // Navigation is async - will be resumed when arrival detected
        _currentStepIndex++;
        break;

      case TaskAction.returnOrigin:
        if (_originWaypoint != null) {
          _callback?.onNavigate(_originWaypoint!);
        }
        _finishExecution();
        break;
    }
  }

  /// Cancel current execution
  void cancel() {
    _waitTimer?.cancel();
    _waitTimer = null;
    _callback?.onCloseDisplay();
    _finishExecution();
  }

  void _finishExecution() {
    _isExecuting = false;
    _currentWaypoint = null;
    _currentMode = null;
    _currentStepIndex = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _waitTimer?.cancel();
    super.dispose();
  }

  // === Config Sync with Relay ===

  /// Sync config from relay server (download)
  Future<bool> syncFromRelay(String relayUrl) async {
    try {
      final response = await http.get(Uri.parse('$relayUrl/config'));
      if (response.statusCode == 200 &&
          response.body.isNotEmpty &&
          response.body != '{}') {
        final json = jsonDecode(response.body) as Map<String, dynamic>;

        // Load assignments
        if (json.containsKey('assignments')) {
          _assignments.clear();
          final assigns = json['assignments'] as Map<String, dynamic>;
          assigns.forEach((wp, data) {
            _assignments[wp] =
                WaypointTaskAssignment.fromJson(data as Map<String, dynamic>);
          });
        }

        // Load custom modes
        if (json.containsKey('modes')) {
          final modes = json['modes'] as Map<String, dynamic>;
          modes.forEach((id, data) {
            final mode = WaypointTask.fromJson(data as Map<String, dynamic>);
            if (!mode.isBuiltIn) {
              _modes[id] = mode;
            }
          });
        }

        await save();
        notifyListeners();
        debugPrint(
            'TaskEngine: Synced ${_assignments.length} assignments from relay');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('TaskEngine: Failed to sync from relay: $e');
      return false;
    }
  }

  /// Sync config to relay server (upload)
  Future<bool> syncToRelay(String relayUrl) async {
    try {
      final config = {
        'assignments': _assignments.map((k, v) => MapEntry(k, v.toJson())),
        'modes': Map.fromEntries(_modes.entries
            .where((e) => !e.value.isBuiltIn)
            .map((e) => MapEntry(e.key, e.value.toJson()))),
      };

      final response = await http.post(
        Uri.parse('$relayUrl/config'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(config),
      );

      if (response.statusCode == 200) {
        debugPrint(
            'TaskEngine: Synced ${_assignments.length} assignments to relay');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('TaskEngine: Failed to sync to relay: $e');
      return false;
    }
  }

  /// Export config as JSON string
  String exportConfig() {
    return jsonEncode({
      'assignments': _assignments.map((k, v) => MapEntry(k, v.toJson())),
      'modes': Map.fromEntries(_modes.entries
          .where((e) => !e.value.isBuiltIn)
          .map((e) => MapEntry(e.key, e.value.toJson()))),
    });
  }

  /// Import config from JSON string
  void importConfig(String json) {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;

      if (data.containsKey('assignments')) {
        _assignments.clear();
        final assigns = data['assignments'] as Map<String, dynamic>;
        assigns.forEach((wp, d) {
          _assignments[wp] =
              WaypointTaskAssignment.fromJson(d as Map<String, dynamic>);
        });
      }

      if (data.containsKey('modes')) {
        final modes = data['modes'] as Map<String, dynamic>;
        modes.forEach((id, d) {
          final mode = WaypointTask.fromJson(d as Map<String, dynamic>);
          if (!mode.isBuiltIn) {
            _modes[id] = mode;
          }
        });
      }

      save();
      notifyListeners();
    } catch (e) {
      debugPrint('TaskEngine: Failed to import config: $e');
    }
  }
}
