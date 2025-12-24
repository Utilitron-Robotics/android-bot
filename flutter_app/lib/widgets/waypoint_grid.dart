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
  final _customWaypointController = TextEditingController();

  @override
  void dispose() {
    _customWaypointController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                Consumer<RobotConnection>(
                  builder: (context, robot, _) {
                    if (!robot.status.isMoving) return const SizedBox.shrink();
                    return FilledButton.tonalIcon(
                      onPressed: () async {
                        await robot.cancelNavigation();
                        setState(() => _navigatingTo = null);
                      },
                      icon: const Icon(Icons.stop),
                      label: const Text('STOP'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Waypoint grid
            if (widget.waypoints.isEmpty)
              _buildEmptyState()
            else
              _buildGrid(),
            const Divider(height: 32),
            // Custom waypoint input
            _buildCustomWaypointInput(),
          ],
        ),
      ),
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

  Widget _buildGrid() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: widget.waypoints.map((wp) => _buildWaypointButton(wp)).toList(),
    );
  }

  Widget _buildWaypointButton(String waypoint) {
    final isNavigating = _navigatingTo == waypoint;

    return Consumer<RobotConnection>(
      builder: (context, robot, _) {
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
      },
    );
  }

  Widget _buildCustomWaypointInput() {
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
            onSubmitted: (value) => _goToCustomWaypoint(),
          ),
        ),
        const SizedBox(width: 8),
        Consumer<RobotConnection>(
          builder: (context, robot, _) {
            return IconButton.filled(
              onPressed: robot.status.isMoving ? null : _goToCustomWaypoint,
              icon: const Icon(Icons.send),
            );
          },
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

  void _goToCustomWaypoint() {
    final waypoint = _customWaypointController.text.trim();
    if (waypoint.isEmpty) return;

    final robot = context.read<RobotConnection>();
    _goToWaypoint(robot, waypoint);
    _customWaypointController.clear();
  }
}
