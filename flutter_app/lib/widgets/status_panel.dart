import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/robot_connection.dart';

/// Displays live robot status: battery, nav state, etc.
class StatusPanel extends StatefulWidget {
  const StatusPanel({super.key});

  @override
  State<StatusPanel> createState() => _StatusPanelState();
}

class _StatusPanelState extends State<StatusPanel> {
  Timer? _staleCheckTimer;

  @override
  void initState() {
    super.initState();
    // Check for stale data every second
    _staleCheckTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _staleCheckTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RobotConnection>(
      builder: (context, robot, _) {
        final status = robot.status;
        final isStale = robot.isStale;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // STALE DATA Warning banner - critical for safety
                if (isStale)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade900,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber, width: 2),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.warning_amber, color: Colors.amber, size: 24),
                        SizedBox(width: 8),
                        Text(
                          'DATA STALE - Status not updating!',
                          style: TextStyle(
                            color: Colors.amber,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(Icons.warning_amber, color: Colors.amber, size: 24),
                      ],
                    ),
                  ),
                // E-STOP Warning banner
                if (status.hasEstop)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: status.hardEstop ? Colors.red.shade900 : Colors.orange.shade900,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: status.hardEstop ? Colors.red : Colors.orange,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.emergency,
                          color: status.hardEstop ? Colors.red : Colors.orange,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          status.hardEstop ? 'HARD E-STOP ACTIVE' : 'SOFT STOP ACTIVE',
                          style: TextStyle(
                            color: status.hardEstop ? Colors.red : Colors.orange,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.emergency,
                          color: status.hardEstop ? Colors.red : Colors.orange,
                          size: 24,
                        ),
                      ],
                    ),
                  ),
                Row(
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
                    // Charging status
                    if (status.isCharging)
                      _StatusItem(
                        icon: Icons.bolt,
                        label: 'Charger',
                        value: status.chargerText,
                        color: Colors.yellow.shade700,
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
