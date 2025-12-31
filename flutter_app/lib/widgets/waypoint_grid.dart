import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/robot_connection.dart';
import '../core/task_engine.dart';

/// Grid of waypoint buttons - dynamically generated from discovered POIs
class WaypointGrid extends StatefulWidget {
  final List<String> waypoints;
  final String? relayUrl;

  const WaypointGrid({
    super.key,
    required this.waypoints,
    this.relayUrl,
  });

  @override
  State<WaypointGrid> createState() => _WaypointGridState();
}

class _WaypointGridState extends State<WaypointGrid> implements TaskExecutorCallback {
  String? _navigatingTo;
  String? _lastWaypoint;
  int? _lastNavStatus;
  final _customWaypointController = TextEditingController();
  final _taskEngine = TaskEngine.instance;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    await _taskEngine.load();
    _taskEngine.setCallback(this);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _customWaypointController.dispose();
    super.dispose();
  }

  // TaskExecutorCallback implementation
  @override
  void onSpeak(String text) {
    final robot = context.read<RobotConnection>();
    if (robot.isConnected) {
      robot.client.tabletSpeak(text);
    }
  }

  @override
  void onDisplay(String url, int durationSeconds) {
    final robot = context.read<RobotConnection>();
    if (robot.isConnected) {
      robot.client.tabletDisplay(url);
      if (durationSeconds > 0) {
        Future.delayed(Duration(seconds: durationSeconds), () {
          if (mounted) onCloseDisplay();
        });
      }
    }
  }

  @override
  void onCloseDisplay() {
    final robot = context.read<RobotConnection>();
    if (robot.isConnected) {
      robot.client.tabletCloseDisplay();
    }
  }

  @override
  void onNavigate(String waypoint) {
    final robot = context.read<RobotConnection>();
    if (robot.isConnected) {
      _goToWaypoint(robot, waypoint);
    }
  }

  @override
  void onWait(int seconds) {
    // Wait is handled by TaskEngine timer
  }

  /// Check nav status and execute task on arrival
  void _checkNavStatus(int navStatus, String goalName) {
    if (_lastNavStatus == navStatus) return;
    final previousStatus = _lastNavStatus;
    _lastNavStatus = navStatus;

    // Execute task on arrival (603 = Success/Arrived)
    if (_navigatingTo != null && navStatus == 603 && previousStatus == 601) {
      final arrivedAt = _navigatingTo!;
      _taskEngine.executeForWaypoint(arrivedAt, fromWaypoint: _lastWaypoint);
      _lastWaypoint = arrivedAt;
    }

    // Clear navigating state on terminal statuses (not 601=Moving)
    if (_navigatingTo != null && navStatus != 601) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _navigatingTo = null);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RobotConnection>(
      builder: (context, robot, _) {
        _checkNavStatus(robot.status.navStatus, robot.status.currentGoal);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_on),
                    const SizedBox(width: 8),
                    Text(
                      'Waypoints',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    // Task engine indicator
                    if (_taskEngine.isExecuting)
                      Tooltip(
                        message: 'Task running',
                        child: Icon(Icons.play_circle,
                          size: 20,
                          color: Colors.green.shade600),
                      ),
                    const SizedBox(width: 8),
                    // Cancel button
                    if (robot.status.isMoving || _taskEngine.isExecuting)
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          await robot.cancelNavigation();
                          _taskEngine.cancel();
                          setState(() => _navigatingTo = null);
                        },
                        icon: const Icon(Icons.stop),
                        label: const Text('STOP'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Long-press to configure task mode',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 8),
                // Waypoint grid
                if (widget.waypoints.isEmpty)
                  _buildEmptyState()
                else
                  _buildGrid(robot),
                const Divider(height: 32),
                // Custom waypoint input
                _buildCustomWaypointInput(robot),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(Icons.location_off, size: 48, color: Colors.grey.shade600),
          const SizedBox(height: 8),
          const Text('No waypoints discovered'),
          const Text(
            'Enter a waypoint name below or configure on the robot',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(RobotConnection robot) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: widget.waypoints.map((wp) => _buildWaypointButton(robot, wp)).toList(),
    );
  }

  Widget _buildWaypointButton(RobotConnection robot, String waypoint) {
    final isNavigating = _navigatingTo == waypoint;
    final hasMode = _taskEngine.hasMode(waypoint);

    return GestureDetector(
      onLongPress: () => _showModeConfigDialog(waypoint),
      child: FilledButton.tonal(
        onPressed: robot.status.isMoving
            ? null
            : () => _goToWaypoint(robot, waypoint),
        style: FilledButton.styleFrom(
          backgroundColor: isNavigating ? Colors.green.shade700 : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isNavigating) ...[
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 8),
            ],
            if (hasMode && !isNavigating) ...[
              const Icon(Icons.auto_awesome, size: 16),
              const SizedBox(width: 4),
            ],
            Text(_formatWaypointName(waypoint)),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomWaypointInput(RobotConnection robot) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _customWaypointController,
            decoration: const InputDecoration(
              labelText: 'Custom waypoint',
              hintText: 'Enter waypoint name',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (value) => _goToCustomWaypoint(robot),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          onPressed: robot.status.isMoving ? null : () => _goToCustomWaypoint(robot),
          icon: const Icon(Icons.send),
        ),
      ],
    );
  }

  String _formatWaypointName(String name) {
    return name
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isEmpty
            ? ''
            : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  Future<void> _goToWaypoint(RobotConnection robot, String waypoint) async {
    setState(() => _navigatingTo = waypoint);
    await robot.goToWaypoint(waypoint);

    // Quick check: if robot didn't start moving within 1.5s, assume already there
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && _navigatingTo == waypoint && robot.status.navStatus != 601) {
        setState(() => _navigatingTo = null);
      }
    });
  }

  void _goToCustomWaypoint(RobotConnection robot) {
    final waypoint = _customWaypointController.text.trim();
    if (waypoint.isEmpty) return;

    _goToWaypoint(robot, waypoint);
    _customWaypointController.clear();
  }

  /// Show dialog to configure mode for a waypoint
  Future<void> _showModeConfigDialog(String waypoint) async {
    final result = await showDialog<_ModeConfigResult>(
      context: context,
      builder: (context) => _ModeConfigDialog(
        waypoint: waypoint,
        taskEngine: _taskEngine,
        availableWaypoints: widget.waypoints,
      ),
    );

    if (result != null) {
      setState(() {
        _taskEngine.assignMode(waypoint, result.modeId, params: result.params);
      });
    }
  }
}

/// Result from mode config dialog
class _ModeConfigResult {
  final String? modeId;
  final Map<String, String> params;

  _ModeConfigResult({this.modeId, this.params = const {}});
}

/// Dialog to configure mode for a waypoint
class _ModeConfigDialog extends StatefulWidget {
  final String waypoint;
  final TaskEngine taskEngine;
  final List<String> availableWaypoints;

  const _ModeConfigDialog({
    required this.waypoint,
    required this.taskEngine,
    required this.availableWaypoints,
  });

  @override
  State<_ModeConfigDialog> createState() => _ModeConfigDialogState();
}

class _ModeConfigDialogState extends State<_ModeConfigDialog> {
  String? _selectedModeId;
  final _speakController = TextEditingController();
  final _displayController = TextEditingController();
  int _waitSeconds = 30;
  int _displayDuration = 5;

  @override
  void initState() {
    super.initState();
    final assignment = widget.taskEngine.getAssignment(widget.waypoint);
    if (assignment != null) {
      _selectedModeId = assignment.modeId;
      _speakController.text = assignment.params['speak_text'] ?? '';
      _displayController.text = assignment.params['display_url'] ?? '';
      _waitSeconds = int.tryParse(assignment.params['wait_seconds'] ?? '30') ?? 30;
      _displayDuration = int.tryParse(assignment.params['display_duration'] ?? '5') ?? 5;
    }
  }

  @override
  void dispose() {
    _speakController.dispose();
    _displayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final modes = widget.taskEngine.allModes;

    return AlertDialog(
      title: Text('Mode: ${widget.waypoint}'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Mode selector
              const Text('Select Mode:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                value: _selectedModeId,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('None (just announce arrival)'),
                  ),
                  ...modes.map((m) => DropdownMenuItem(
                    value: m.id,
                    child: Row(
                      children: [
                        Icon(_getModeIcon(m.id), size: 18),
                        const SizedBox(width: 8),
                        Text(m.name),
                      ],
                    ),
                  )),
                ],
                onChanged: (v) => setState(() => _selectedModeId = v),
              ),
              if (_selectedModeId != null) ...[
                const SizedBox(height: 8),
                Text(
                  modes.firstWhere((m) => m.id == _selectedModeId).description,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
              const Divider(height: 24),

              // Mode-specific parameters
              if (_selectedModeId == 'delivery' || _selectedModeId == 'announce') ...[
                // Speak text
                Row(
                  children: [
                    const Icon(Icons.volume_up, size: 20),
                    const SizedBox(width: 8),
                    const Text('Speak', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _speakController,
                  decoration: const InputDecoration(
                    hintText: 'Your order is ready!',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),

                // Display URL
                Row(
                  children: [
                    const Icon(Icons.tv, size: 20),
                    const SizedBox(width: 8),
                    const Text('Display', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _displayController,
                  decoration: const InputDecoration(
                    hintText: 'https://example.com/video.mp4',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],

              // Delivery-specific options
              if (_selectedModeId == 'delivery') ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Wait time: '),
                    Expanded(
                      child: Slider(
                        value: _waitSeconds.toDouble(),
                        min: 10,
                        max: 120,
                        divisions: 11,
                        onChanged: (v) => setState(() => _waitSeconds = v.round()),
                      ),
                    ),
                    Text('${_waitSeconds}s'),
                  ],
                ),
                Text(
                  'Robot will return to origin after this time',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],

              // Announce-specific options
              if (_selectedModeId == 'announce' && _displayController.text.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Display duration: '),
                    Expanded(
                      child: Slider(
                        value: _displayDuration.toDouble(),
                        min: 0,
                        max: 60,
                        divisions: 12,
                        onChanged: (v) => setState(() => _displayDuration = v.round()),
                      ),
                    ),
                    Text(_displayDuration == 0 ? 'Until leave' : '${_displayDuration}s'),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (_selectedModeId != null)
          TextButton(
            onPressed: () => Navigator.pop(context, _ModeConfigResult()),
            child: const Text('Clear'),
          ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context, _ModeConfigResult(
              modeId: _selectedModeId,
              params: {
                if (_speakController.text.isNotEmpty) 'speak_text': _speakController.text,
                if (_displayController.text.isNotEmpty) 'display_url': _displayController.text,
                'wait_seconds': _waitSeconds.toString(),
                'display_duration': _displayDuration.toString(),
              },
            ));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  IconData _getModeIcon(String modeId) {
    switch (modeId) {
      case 'delivery':
        return Icons.delivery_dining;
      case 'announce':
        return Icons.campaign;
      default:
        return Icons.auto_awesome;
    }
  }
}
