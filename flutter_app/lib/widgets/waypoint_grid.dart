import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/robot_connection.dart';
import '../core/waypoint_task.dart';

/// Grid of waypoint buttons - dynamically generated from discovered POIs
class WaypointGrid extends StatefulWidget {
  final List<String> waypoints;
  final String? relayUrl;  // HTTP URL of tablet relay (e.g., http://192.168.1.100:8765)

  const WaypointGrid({
    super.key,
    required this.waypoints,
    this.relayUrl,
  });

  @override
  State<WaypointGrid> createState() => _WaypointGridState();
}

class _WaypointGridState extends State<WaypointGrid> {
  String? _navigatingTo;
  int? _lastNavStatus;
  final _customWaypointController = TextEditingController();
  final _waypointConfig = WaypointConfig();
  TabletTaskClient? _taskClient;

  @override
  void initState() {
    super.initState();
    _updateTaskClient();
  }

  @override
  void didUpdateWidget(WaypointGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.relayUrl != widget.relayUrl) {
      _updateTaskClient();
    }
  }

  void _updateTaskClient() {
    if (widget.relayUrl != null && widget.relayUrl!.isNotEmpty) {
      _taskClient = TabletTaskClient(widget.relayUrl!);
    } else {
      _taskClient = null;
    }
  }

  @override
  void dispose() {
    _customWaypointController.dispose();
    super.dispose();
  }

  /// Check nav status and execute task on arrival
  void _checkNavStatus(int navStatus) {
    // Only react to status changes
    if (_lastNavStatus == navStatus) return;
    final previousStatus = _lastNavStatus;
    _lastNavStatus = navStatus;

    // Execute task on arrival (603 = Success/Arrived)
    if (_navigatingTo != null && navStatus == 603 && previousStatus == 601) {
      _executeWaypointTask(_navigatingTo!);
    }

    // Clear navigating state on terminal statuses (not 601=Moving)
    // 600=Idle, 602=Cancelled, 603=Arrived, 604=Failed, 605=Standby
    if (_navigatingTo != null && navStatus != 601) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _navigatingTo = null);
        }
      });
    }
  }

  /// Execute the configured task for a waypoint (or default arrival behavior)
  void _executeWaypointTask(String waypoint) {
    final robot = context.read<RobotConnection>();
    if (!robot.isConnected) return;

    final task = _waypointConfig.getTask(waypoint);
    final displayName = _formatWaypointName(waypoint);

    if (task.type == TaskType.none) {
      // Default: announce arrival and display waypoint name via WebSocket
      robot.client.tabletSpeak('Arrived at $displayName');
      robot.client.tabletDisplay('data:text/html,<html><body style="display:flex;align-items:center;justify-content:center;height:100vh;margin:0;background:%23222;"><h1 style="color:white;font-size:72px;font-family:sans-serif;">$displayName</h1></body></html>');
      // Auto-close display after 5 seconds
      Future.delayed(const Duration(seconds: 5), () {
        robot.client.tabletCloseDisplay();
      });
    } else {
      // Execute configured task via WebSocket
      robot.client.tabletTask(task.type.name.toUpperCase(), task.data, task.waitSeconds);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RobotConnection>(
      builder: (context, robot, _) {
        // Check nav status on every rebuild to catch status changes
        _checkNavStatus(robot.status.navStatus);

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
                    // Task indicator
                    if (_taskClient != null)
                      Tooltip(
                        message: 'Tablet tasks enabled',
                        child: Icon(Icons.speaker_phone,
                          size: 20,
                          color: Colors.green.shade600),
                      ),
                    const SizedBox(width: 8),
                    // Cancel button
                    if (robot.status.isMoving)
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          await robot.cancelNavigation();
                          _taskClient?.cancelTask();
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
                // Hint text
                Text(
                  'Long-press to configure task',
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
    final task = _waypointConfig.getTask(waypoint);
    final hasTask = task.type != TaskType.none;

    return GestureDetector(
      onLongPress: () => _showTaskConfigDialog(waypoint),
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
            if (hasTask && !isNavigating) ...[
              Icon(_getTaskIcon(task.type), size: 16),
              const SizedBox(width: 4),
            ],
            Text(_formatWaypointName(waypoint)),
          ],
        ),
      ),
    );
  }

  IconData _getTaskIcon(TaskType type) {
    switch (type) {
      case TaskType.deliver:
        return Icons.delivery_dining;
      case TaskType.speak:
        return Icons.volume_up;
      case TaskType.display:
        return Icons.tv;
      case TaskType.none:
        return Icons.location_on;
    }
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
    // Convert snake_case to Title Case
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
    // Status updates will come through the subscription
  }

  void _goToCustomWaypoint(RobotConnection robot) {
    final waypoint = _customWaypointController.text.trim();
    if (waypoint.isEmpty) return;

    _goToWaypoint(robot, waypoint);
    _customWaypointController.clear();
  }

  /// Show dialog to configure task for a waypoint
  Future<void> _showTaskConfigDialog(String waypoint) async {
    var task = _waypointConfig.getTask(waypoint);

    final result = await showDialog<WaypointTask>(
      context: context,
      builder: (context) => _TaskConfigDialog(
        waypoint: waypoint,
        initialTask: task,
      ),
    );

    if (result != null) {
      setState(() {
        _waypointConfig.setTask(waypoint, result);
      });
    }
  }
}

/// Dialog to configure a waypoint task
class _TaskConfigDialog extends StatefulWidget {
  final String waypoint;
  final WaypointTask initialTask;

  const _TaskConfigDialog({
    required this.waypoint,
    required this.initialTask,
  });

  @override
  State<_TaskConfigDialog> createState() => _TaskConfigDialogState();
}

class _TaskConfigDialogState extends State<_TaskConfigDialog> {
  late TaskType _selectedType;
  late TextEditingController _dataController;
  late int _waitSeconds;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialTask.type;
    _dataController = TextEditingController(text: widget.initialTask.data);
    _waitSeconds = widget.initialTask.waitSeconds;
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
            // Task type selector
            const Text('Task Type:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SegmentedButton<TaskType>(
              segments: TaskType.values.map((t) => ButtonSegment(
                value: t,
                label: Text(t.label, style: const TextStyle(fontSize: 11)),
                icon: Icon(_getTaskIcon(t), size: 16),
              )).toList(),
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
            if (_selectedType != TaskType.none) ...[
              TextField(
                controller: _dataController,
                decoration: InputDecoration(
                  labelText: _getDataLabel(),
                  hintText: _getDataHint(),
                  border: const OutlineInputBorder(),
                ),
                maxLines: _selectedType == TaskType.speak ? 3 : 1,
              ),
              const SizedBox(height: 16),
            ],

            // Wait seconds (for deliver)
            if (_selectedType == TaskType.deliver) ...[
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
        if (_selectedType != TaskType.none)
          TextButton(
            onPressed: () => Navigator.pop(context, const WaypointTask()),
            child: const Text('Clear Task'),
          ),
        FilledButton(
          onPressed: () {
            Navigator.pop(context, WaypointTask(
              type: _selectedType,
              data: _dataController.text,
              waitSeconds: _waitSeconds,
            ));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  String _getDataLabel() {
    switch (_selectedType) {
      case TaskType.speak:
        return 'Speech Text';
      case TaskType.display:
        return 'URL';
      case TaskType.deliver:
        return 'Arrival Message';
      case TaskType.none:
        return '';
    }
  }

  String _getDataHint() {
    switch (_selectedType) {
      case TaskType.speak:
        return 'Your order is ready!';
      case TaskType.display:
        return 'https://example.com/video.mp4';
      case TaskType.deliver:
        return 'Please collect your items';
      case TaskType.none:
        return '';
    }
  }

  IconData _getTaskIcon(TaskType type) {
    switch (type) {
      case TaskType.deliver:
        return Icons.delivery_dining;
      case TaskType.speak:
        return Icons.volume_up;
      case TaskType.display:
        return Icons.tv;
      case TaskType.none:
        return Icons.block;
    }
  }
}
