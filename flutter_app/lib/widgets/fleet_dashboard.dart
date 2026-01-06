import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/fleet_cloud.dart';

/// Fleet Dashboard - Shows all robots in the fleet
class FleetDashboard extends StatefulWidget {
  final Function(String robotId)? onRobotSelected;

  const FleetDashboard({super.key, this.onRobotSelected});

  @override
  State<FleetDashboard> createState() => _FleetDashboardState();
}

class _FleetDashboardState extends State<FleetDashboard> {
  final _endpointController = TextEditingController();
  final _apiKeyController = TextEditingController();
  bool _isConfiguring = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<FleetCloudClient>(
      builder: (context, fleet, _) {
        if (!fleet.isConnected) {
          return _buildConnectionPanel(fleet);
        }
        return _buildDashboard(fleet);
      },
    );
  }

  Widget _buildConnectionPanel(FleetCloudClient fleet) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Fleet Management',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Connect to Frontier Tower cloud to manage your robot fleet',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            if (_isConfiguring) ...[
              TextField(
                controller: _endpointController,
                decoration: const InputDecoration(
                  labelText: 'API Endpoint',
                  hintText: 'https://api.frontiertower.io',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _apiKeyController,
                decoration: const InputDecoration(
                  labelText: 'API Key (optional)',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _isConfiguring = false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _connect(fleet),
                      child: const Text('Connect'),
                    ),
                  ),
                ],
              ),
            ] else ...[
              ElevatedButton.icon(
                onPressed: () => setState(() => _isConfiguring = true),
                icon: const Icon(Icons.cloud),
                label: const Text('Connect to Fleet'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDashboard(FleetCloudClient fleet) {
    final robots = fleet.robots;

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.green.shade50,
          child: Row(
            children: [
              const Icon(Icons.cloud_done, color: Colors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Fleet Connected',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${robots.length} robot${robots.length != 1 ? 's' : ''} online',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {}, // Auto-refreshes via polling
                tooltip: 'Refresh',
              ),
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: () => fleet.disconnect(),
                tooltip: 'Disconnect',
              ),
            ],
          ),
        ),

        // Robot list
        Expanded(
          child: robots.isEmpty
              ? const Center(
                  child: Text('No robots connected'),
                )
              : ListView.builder(
                  itemCount: robots.length,
                  padding: const EdgeInsets.all(8),
                  itemBuilder: (context, index) {
                    return _buildRobotCard(robots[index], fleet);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildRobotCard(RobotFleetStatus robot, FleetCloudClient fleet) {
    final isOnline = robot.online;
    final isNavigating = robot.isNavigating;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: InkWell(
        onTap: widget.onRobotSelected != null
            ? () => widget.onRobotSelected!(robot.robotId)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  // Status indicator
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: robot.estop
                          ? Colors.red
                          : isOnline
                              ? (isNavigating ? Colors.blue : Colors.green)
                              : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Robot ID
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          robot.robotId,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (robot.building != null)
                          Text(
                            '${robot.building}${robot.floor != null ? ' - ${robot.floor}' : ''}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Battery
                  _buildBatteryIndicator(robot.battery),
                ],
              ),

              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),

              // Status row
              Row(
                children: [
                  // Nav status
                  _buildStatusChip(
                    robot.navStatusText,
                    isNavigating ? Colors.blue : Colors.grey,
                  ),
                  const SizedBox(width: 8),

                  // Current goal
                  if (robot.currentGoal != null && robot.currentGoal!.isNotEmpty)
                    _buildStatusChip(
                      robot.currentGoal!,
                      Colors.orange,
                    ),

                  const Spacer(),

                  // E-stop indicator
                  if (robot.estop)
                    _buildStatusChip('E-STOP', Colors.red),
                ],
              ),

              const SizedBox(height: 8),

              // Quick actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (isOnline && isNavigating)
                    TextButton.icon(
                      onPressed: () => fleet.stopRobot(robot.robotId),
                      icon: const Icon(Icons.stop, size: 18),
                      label: const Text('Stop'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.orange,
                      ),
                    ),
                  if (isOnline)
                    TextButton.icon(
                      onPressed: () => fleet.estopRobot(robot.robotId, !robot.estop),
                      icon: Icon(
                        robot.estop ? Icons.play_arrow : Icons.warning,
                        size: 18,
                      ),
                      label: Text(robot.estop ? 'Release' : 'E-Stop'),
                      style: TextButton.styleFrom(
                        foregroundColor: robot.estop ? Colors.green : Colors.red,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBatteryIndicator(int battery) {
    final color = battery > 50
        ? Colors.green
        : battery > 20
            ? Colors.orange
            : Colors.red;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          battery > 80
              ? Icons.battery_full
              : battery > 50
                  ? Icons.battery_5_bar
                  : battery > 20
                      ? Icons.battery_3_bar
                      : Icons.battery_1_bar,
          color: color,
          size: 20,
        ),
        const SizedBox(width: 4),
        Text(
          '$battery%',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Future<void> _connect(FleetCloudClient fleet) async {
    final endpoint = _endpointController.text.trim();
    if (endpoint.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter API endpoint')),
      );
      return;
    }

    fleet.configure(
      apiEndpoint: endpoint,
      apiKey: _apiKeyController.text.trim().isEmpty
          ? null
          : _apiKeyController.text.trim(),
    );

    final success = await fleet.connect();
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to connect to fleet'),
          backgroundColor: Colors.red,
        ),
      );
    }

    setState(() => _isConfiguring = false);
  }

  @override
  void dispose() {
    _endpointController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }
}

/// Compact fleet status bar for embedding in other screens
class FleetStatusBar extends StatelessWidget {
  const FleetStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<FleetCloudClient>(
      builder: (context, fleet, _) {
        if (!fleet.isConnected) {
          return const SizedBox.shrink();
        }

        final robots = fleet.robots;
        final online = robots.where((r) => r.online).length;
        final navigating = robots.where((r) => r.isNavigating).length;
        final estopped = robots.where((r) => r.estop).length;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: estopped > 0 ? Colors.red.shade50 : Colors.green.shade50,
            border: Border(
              bottom: BorderSide(
                color: estopped > 0 ? Colors.red.shade200 : Colors.green.shade200,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.cloud_done,
                size: 16,
                color: estopped > 0 ? Colors.red : Colors.green,
              ),
              const SizedBox(width: 8),
              Text(
                '$online online',
                style: const TextStyle(fontSize: 12),
              ),
              if (navigating > 0) ...[
                const SizedBox(width: 12),
                const Icon(Icons.navigation, size: 14, color: Colors.blue),
                const SizedBox(width: 4),
                Text(
                  '$navigating moving',
                  style: const TextStyle(fontSize: 12, color: Colors.blue),
                ),
              ],
              if (estopped > 0) ...[
                const SizedBox(width: 12),
                const Icon(Icons.warning, size: 14, color: Colors.red),
                const SizedBox(width: 4),
                Text(
                  '$estopped stopped',
                  style: const TextStyle(fontSize: 12, color: Colors.red),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
