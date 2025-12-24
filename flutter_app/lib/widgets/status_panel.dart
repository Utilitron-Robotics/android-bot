import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/robot_connection.dart';

/// Displays live robot status: battery, nav state, etc.
class StatusPanel extends StatelessWidget {
  const StatusPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<RobotConnection>(
      builder: (context, robot, _) {
        final status = robot.status;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // Battery
                _StatusItem(
                  icon: _batteryIcon(status.battery),
                  label: 'Battery',
                  value: '${status.battery.toStringAsFixed(0)}%',
                  color: _batteryColor(status.battery),
                ),
                // Navigation status
                _StatusItem(
                  icon: status.isMoving ? Icons.directions_walk : Icons.pause,
                  label: 'Status',
                  value: status.navStatusText,
                  color: status.isMoving ? Colors.green : Colors.grey,
                ),
                // Velocity (if moving)
                if (status.isMoving)
                  _StatusItem(
                    icon: Icons.speed,
                    label: 'Speed',
                    value: '${status.velocity[0].toStringAsFixed(2)} m/s',
                    color: Colors.blue,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  IconData _batteryIcon(double level) {
    if (level > 80) return Icons.battery_full;
    if (level > 60) return Icons.battery_5_bar;
    if (level > 40) return Icons.battery_4_bar;
    if (level > 20) return Icons.battery_2_bar;
    return Icons.battery_alert;
  }

  Color _batteryColor(double level) {
    if (level > 50) return Colors.green;
    if (level > 20) return Colors.orange;
    return Colors.red;
  }
}

class _StatusItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatusItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }
}
