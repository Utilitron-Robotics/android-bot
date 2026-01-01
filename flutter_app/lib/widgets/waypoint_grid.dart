import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/robot_connection.dart';
import '../core/task_engine.dart';
import '../services/audio_announcer.dart';

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

class _WaypointGridState extends State<WaypointGrid>
    implements TaskExecutorCallback {
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
    // Use AudioAnnouncer which handles both local TTS and tablet forwarding
    AudioAnnouncer().speak(text);
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
  void onDisplayDefault(String waypoint) {
    final robot = context.read<RobotConnection>();
    if (!robot.isConnected) return;

    // Format the name nicely (convert snake_case to Title Case)
    final displayName = _formatWaypointName(waypoint);

    // Show waypoint name on tablet with dark background
    final html = 'data:text/html,<html><body style="display:flex;align-items:center;justify-content:center;height:100vh;margin:0;background:%23222;"><h1 style="color:white;font-size:72px;font-family:sans-serif;">$displayName</h1></body></html>';
    robot.client.tabletDisplay(html);
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
                            size: 20, color: Colors.green.shade600),
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
      children: widget.waypoints
          .map((wp) => _buildWaypointButton(robot, wp))
          .toList(),
    );
  }

  Widget _buildWaypointButton(RobotConnection robot, String waypoint) {
    final isNavigating = _navigatingTo == waypoint;
    final hasMode = _taskEngine.hasMode(waypoint);

    return GestureDetector(
      onLongPress: () => _showTaskConfigDialog(waypoint),
      child: FilledButton.tonal(
        onPressed:
            robot.status.isMoving ? null : () => _goToWaypoint(robot, waypoint),
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
          onPressed:
              robot.status.isMoving ? null : () => _goToCustomWaypoint(robot),
          icon: const Icon(Icons.send),
        ),
      ],
    );
  }

  String _formatWaypointName(String name) {
    return name
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) =>
            word.isEmpty ? '' : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  Future<void> _goToWaypoint(RobotConnection robot, String waypoint) async {
    setState(() => _navigatingTo = waypoint);
    await robot.goToWaypoint(waypoint);

    // Quick check: if robot didn't start moving within 1.5s, assume already there
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted &&
          _navigatingTo == waypoint &&
          robot.status.navStatus != 601) {
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

  /// Show dialog to configure task for a waypoint
  Future<void> _showTaskConfigDialog(String waypoint) async {
    final result = await showDialog<_TaskConfigResult>(
      context: context,
      builder: (context) => _TaskConfigDialog(
        waypoint: waypoint,
        taskEngine: _taskEngine,
      ),
    );

    if (result != null) {
      setState(() {
        _taskEngine.assignMode(waypoint, result.modeId, params: result.params);
      });
    }
  }
}

/// Task types for the simple waypoint task dialog
enum _TaskType {
  none('None', 'Just announce arrival'),
  deliver('Deliver', 'Wait for pickup, then return'),
  speak('Speak', 'Text-to-speech announcement'),
  display('Display', 'Show webpage or video');

  final String label;
  final String description;
  const _TaskType(this.label, this.description);
}

/// Result from task config dialog
class _TaskConfigResult {
  final String? modeId;
  final Map<String, String> params;

  _TaskConfigResult({this.modeId, this.params = const {}});
}

/// Dialog to configure a waypoint task (restored simpler UI with SegmentedButton)
class _TaskConfigDialog extends StatefulWidget {
  final String waypoint;
  final TaskEngine taskEngine;

  const _TaskConfigDialog({
    required this.waypoint,
    required this.taskEngine,
  });

  @override
  State<_TaskConfigDialog> createState() => _TaskConfigDialogState();
}

class _TaskConfigDialogState extends State<_TaskConfigDialog> {
  _TaskType _selectedType = _TaskType.none;
  late TextEditingController _dataController;
  int _waitSeconds = 30;

  @override
  void initState() {
    super.initState();
    _dataController = TextEditingController();

    // Load existing assignment
    final assignment = widget.taskEngine.getAssignment(widget.waypoint);
    if (assignment != null && assignment.modeId != null) {
      // Map modeId to TaskType
      if (assignment.modeId == 'delivery') {
        _selectedType = _TaskType.deliver;
        _dataController.text = assignment.params['speak_text'] ?? '';
        _waitSeconds =
            int.tryParse(assignment.params['wait_seconds'] ?? '30') ?? 30;
      } else if (assignment.modeId == 'announce') {
        // Check if it's speak or display based on params
        if (assignment.params['display_url']?.isNotEmpty == true) {
          _selectedType = _TaskType.display;
          _dataController.text = assignment.params['display_url'] ?? '';
        } else {
          _selectedType = _TaskType.speak;
          _dataController.text = assignment.params['speak_text'] ?? '';
        }
      }
    }
  }

  @override
  void dispose() {
    _dataController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Task: ${widget.waypoint}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Task type selector with SegmentedButton
            const Text('Task Type:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SegmentedButton<_TaskType>(
              segments: _TaskType.values
                  .map((t) => ButtonSegment(
                        value: t,
                        label: Text(t.label, style: const TextStyle(fontSize: 11)),
                        icon: Icon(_getTaskIcon(t), size: 16),
                      ))
                  .toList(),
              selected: {_selectedType},
              onSelectionChanged: (selected) {
                setState(() => _selectedType = selected.first);
              },
            ),
            const SizedBox(height: 8),
            Text(
              _selectedType.description,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),

            // Data input (only for non-none types)
            if (_selectedType != _TaskType.none) ...[
              TextField(
                controller: _dataController,
                decoration: InputDecoration(
                  labelText: _getDataLabel(),
                  hintText: _getDataHint(),
                  border: const OutlineInputBorder(),
                ),
                maxLines: _selectedType == _TaskType.speak ? 3 : 1,
              ),
              const SizedBox(height: 16),
            ],

            // Wait seconds (for deliver)
            if (_selectedType == _TaskType.deliver) ...[
              Row(
                children: [
                  const Text('Wait time: '),
                  Expanded(
                    child: Slider(
                      value: _waitSeconds.toDouble(),
                      min: 10,
                      max: 120,
                      divisions: 11,
                      label: '$_waitSeconds sec',
                      onChanged: (value) {
                        setState(() => _waitSeconds = value.round());
                      },
                    ),
                  ),
                  Text('$_waitSeconds sec'),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (_selectedType != _TaskType.none)
          TextButton(
            onPressed: () => Navigator.pop(context, _TaskConfigResult()),
            child: const Text('Clear Task'),
          ),
        FilledButton(
          onPressed: () {
            // Convert TaskType to TaskEngine mode and params
            String? modeId;
            Map<String, String> params = {};

            switch (_selectedType) {
              case _TaskType.none:
                modeId = null;
                break;
              case _TaskType.deliver:
                modeId = 'delivery';
                params = {
                  if (_dataController.text.isNotEmpty)
                    'speak_text': _dataController.text,
                  'wait_seconds': _waitSeconds.toString(),
                };
                break;
              case _TaskType.speak:
                modeId = 'announce';
                params = {
                  'speak_text': _dataController.text,
                };
                break;
              case _TaskType.display:
                modeId = 'announce';
                params = {
                  'display_url': _dataController.text,
                  'display_duration': '0', // Until leave
                };
                break;
            }

            Navigator.pop(
                context, _TaskConfigResult(modeId: modeId, params: params));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  String _getDataLabel() {
    switch (_selectedType) {
      case _TaskType.speak:
        return 'Speech Text';
      case _TaskType.display:
        return 'URL';
      case _TaskType.deliver:
        return 'Arrival Message';
      case _TaskType.none:
        return '';
    }
  }

  String _getDataHint() {
    switch (_selectedType) {
      case _TaskType.speak:
        return 'Your order is ready!';
      case _TaskType.display:
        return 'https://example.com/video.mp4';
      case _TaskType.deliver:
        return 'Please collect your items';
      case _TaskType.none:
        return '';
    }
  }

  IconData _getTaskIcon(_TaskType type) {
    switch (type) {
      case _TaskType.deliver:
        return Icons.delivery_dining;
      case _TaskType.speak:
        return Icons.volume_up;
      case _TaskType.display:
        return Icons.tv;
      case _TaskType.none:
        return Icons.block;
    }
  }
}
