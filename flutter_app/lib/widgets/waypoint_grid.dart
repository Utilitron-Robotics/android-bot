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

    debugPrint('WaypointGrid: navStatus $previousStatus -> $navStatus, navigatingTo=$_navigatingTo, goal=$goalName');

    // Execute task on arrival (603 = Success/Arrived)
    // Allow from any moving/transitional status, not just 601
    if (_navigatingTo != null && navStatus == 603) {
      final arrivedAt = _navigatingTo!;
      debugPrint('WaypointGrid: Arrival detected at $arrivedAt, executing task...');
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

/// Result from task config dialog - supports multiple simultaneous tasks
class _TaskConfigResult {
  final String? modeId;
  final Map<String, String> params;

  _TaskConfigResult({this.modeId, this.params = const {}});
}

/// Dialog to configure waypoint tasks - allows MULTIPLE options at once
/// (deliver mode + speak text + display URL can all be enabled simultaneously)
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
  // Individual toggles for each capability
  bool _enableDelivery = false;  // Wait for pickup + return to origin
  bool _enableSpeak = false;     // TTS announcement
  bool _enableDisplay = false;   // Show website/media

  // Data controllers
  late TextEditingController _speakController;
  late TextEditingController _displayController;
  int _waitSeconds = 30;

  @override
  void initState() {
    super.initState();
    _speakController = TextEditingController();
    _displayController = TextEditingController();

    // Load existing assignment
    final assignment = widget.taskEngine.getAssignment(widget.waypoint);
    if (assignment != null && assignment.modeId != null) {
      final params = assignment.params;

      // Load speak text
      if (params['speak_text']?.isNotEmpty == true) {
        _enableSpeak = true;
        _speakController.text = params['speak_text']!;
      }

      // Load display URL
      if (params['display_url']?.isNotEmpty == true) {
        _enableDisplay = true;
        _displayController.text = params['display_url']!;
      }

      // Load delivery settings
      if (assignment.modeId == 'delivery') {
        _enableDelivery = true;
        _waitSeconds = int.tryParse(params['wait_seconds'] ?? '30') ?? 30;
      }
    }
  }

  @override
  void dispose() {
    _speakController.dispose();
    _displayController.dispose();
    super.dispose();
  }

  bool get _hasAnyTask => _enableDelivery || _enableSpeak || _enableDisplay;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 24),
          const SizedBox(width: 8),
          Expanded(child: Text('Task: ${widget.waypoint}')),
        ],
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Configure actions to perform when arriving at this waypoint. '
                'Multiple options can be enabled together.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),

              // === SPEAK SECTION ===
              _buildTaskSection(
                icon: Icons.volume_up,
                iconColor: Colors.orange,
                title: 'Speak',
                subtitle: 'Text-to-speech announcement',
                enabled: _enableSpeak,
                onToggle: (v) => setState(() => _enableSpeak = v),
                child: TextField(
                  controller: _speakController,
                  decoration: const InputDecoration(
                    hintText: 'What to say at this stop...',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  maxLines: 3,
                  enabled: _enableSpeak,
                ),
              ),

              const SizedBox(height: 12),

              // === DISPLAY SECTION ===
              _buildTaskSection(
                icon: Icons.tv,
                iconColor: Colors.purple,
                title: 'Display',
                subtitle: 'Show website, image, or video on tablet',
                enabled: _enableDisplay,
                onToggle: (v) => setState(() => _enableDisplay = v),
                child: TextField(
                  controller: _displayController,
                  decoration: const InputDecoration(
                    hintText: 'https://example.com/media.mp4',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  enabled: _enableDisplay,
                ),
              ),

              const SizedBox(height: 12),

              // === DELIVERY SECTION ===
              _buildTaskSection(
                icon: Icons.delivery_dining,
                iconColor: Colors.green,
                title: 'Delivery Mode',
                subtitle: 'Wait for pickup, then return to origin',
                enabled: _enableDelivery,
                onToggle: (v) => setState(() => _enableDelivery = v),
                child: Row(
                  children: [
                    const Text('Wait time: '),
                    Expanded(
                      child: Slider(
                        value: _waitSeconds.toDouble(),
                        min: 10,
                        max: 120,
                        divisions: 11,
                        label: '$_waitSeconds sec',
                        onChanged: _enableDelivery
                            ? (v) => setState(() => _waitSeconds = v.round())
                            : null,
                      ),
                    ),
                    Text('$_waitSeconds sec'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (_hasAnyTask)
          TextButton(
            onPressed: () => Navigator.pop(context, _TaskConfigResult()),
            child: const Text('Clear All'),
          ),
        FilledButton(
          onPressed: () {
            // Build mode and params from enabled options
            String? modeId;
            Map<String, String> params = {};

            // Collect all enabled params
            if (_enableSpeak && _speakController.text.isNotEmpty) {
              params['speak_text'] = _speakController.text;
            }
            if (_enableDisplay && _displayController.text.isNotEmpty) {
              params['display_url'] = _displayController.text;
              params['display_duration'] = '0'; // Until robot leaves
            }

            // Determine mode based on delivery toggle
            if (_enableDelivery) {
              modeId = 'delivery';
              params['wait_seconds'] = _waitSeconds.toString();
            } else if (params.isNotEmpty) {
              modeId = 'announce';
            }

            Navigator.pop(
              context,
              _TaskConfigResult(modeId: modeId, params: params),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  /// Build a collapsible task section with toggle
  Widget _buildTaskSection({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool enabled,
    required ValueChanged<bool> onToggle,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: enabled ? iconColor.withValues(alpha: 0.5) : Colors.grey.shade700,
          width: enabled ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
        color: enabled ? iconColor.withValues(alpha: 0.1) : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header row with toggle
          InkWell(
            onTap: () => onToggle(!enabled),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(icon, color: enabled ? iconColor : Colors.grey, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: enabled ? iconColor : Colors.grey,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: enabled,
                    onChanged: onToggle,
                    activeTrackColor: iconColor.withValues(alpha: 0.5),
                    activeThumbColor: iconColor,
                  ),
                ],
              ),
            ),
          ),
          // Content (shown when enabled)
          if (enabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: child,
            ),
        ],
      ),
    );
  }
}
