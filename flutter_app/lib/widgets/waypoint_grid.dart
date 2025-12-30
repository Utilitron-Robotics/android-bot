import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/robot_connection.dart';

/// Grid of waypoint buttons - dynamically generated from discovered POIs
class WaypointGrid extends StatefulWidget {
  final List<String> waypoints;

  const WaypointGrid({super.key, required this.waypoints});

  @override
  State<WaypointGrid> createState() => _WaypointGridState();
}

class _WaypointGridState extends State<WaypointGrid> {
  String? _navigatingTo;
  int? _lastNavStatus;
  final _customWaypointController = TextEditingController();

  @override
  void dispose() {
    _customWaypointController.dispose();
    super.dispose();
  }

  /// Check nav status and clear _navigatingTo when navigation ends
  void _checkNavStatus(int navStatus) {
    // Only react to status changes
    if (_lastNavStatus == navStatus) return;
    _lastNavStatus = navStatus;

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
                    // Cancel button
                    if (robot.status.isMoving)
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          await robot.cancelNavigation();
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
                const SizedBox(height: 16),
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

    return FilledButton.tonal(
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
          Text(_formatWaypointName(waypoint)),
        ],
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
}
