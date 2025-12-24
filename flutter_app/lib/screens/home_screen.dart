import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/robot_connection.dart';
import '../widgets/widget_factory.dart';

/// Main screen - dynamically generates UI based on robot capabilities
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Load saved URL
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final robot = context.read<RobotConnection>();
      _urlController.text = robot.robotUrl;
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Droid Controller'),
        actions: [
          Consumer<RobotConnection>(
            builder: (context, robot, _) {
              return Row(
                children: [
                  _ConnectionIndicator(state: robot.state),
                  if (robot.isConnected)
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: () => robot.connect(robot.robotUrl),
                      tooltip: 'Refresh capabilities',
                    ),
                ],
              );
            },
          ),
        ],
      ),
      body: Consumer<RobotConnection>(
        builder: (context, robot, _) {
          return CustomScrollView(
            slivers: [
              // Connection bar (always visible)
              SliverToBoxAdapter(
                child: _buildConnectionBar(robot),
              ),
              // Dynamic content based on connection state
              if (robot.state == ConnectionState.connecting)
                const SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Discovering robot capabilities...'),
                      ],
                    ),
                  ),
                )
              else if (robot.state == ConnectionState.error)
                SliverFillRemaining(
                  child: _buildErrorState(robot),
                )
              else if (robot.state == ConnectionState.connected &&
                  robot.capabilities != null)
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate(
                      WidgetFactory(robot.capabilities!)
                          .generateWidgets(context),
                    ),
                  ),
                )
              else
                const SliverFillRemaining(
                  child: Center(
                    child: Text('Enter robot URL and tap Connect'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildConnectionBar(RobotConnection robot) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'Robot URL',
                  hintText: 'ws://192.168.1.100:9090',
                  border: OutlineInputBorder(),
                  isDense: true,
                  prefixIcon: Icon(Icons.link),
                ),
                enabled: robot.state != ConnectionState.connecting,
                onSubmitted: (_) => _connect(robot),
              ),
            ),
            const SizedBox(width: 12),
            if (robot.isConnected)
              FilledButton.tonalIcon(
                onPressed: robot.disconnect,
                icon: const Icon(Icons.link_off),
                label: const Text('Disconnect'),
              )
            else
              FilledButton.icon(
                onPressed: robot.state == ConnectionState.connecting
                    ? null
                    : () => _connect(robot),
                icon: const Icon(Icons.link),
                label: const Text('Connect'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(RobotConnection robot) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
            const SizedBox(height: 16),
            const Text(
              'Connection Failed',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              robot.errorMessage ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade400),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _connect(robot),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  void _connect(RobotConnection robot) {
    final url = _urlController.text.trim();
    if (url.isNotEmpty) {
      robot.connect(url);
    }
  }
}

class _ConnectionIndicator extends StatelessWidget {
  final ConnectionState state;

  const _ConnectionIndicator({required this.state});

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (state) {
      ConnectionState.disconnected => (Colors.grey, Icons.link_off, 'Disconnected'),
      ConnectionState.connecting => (Colors.orange, Icons.sync, 'Connecting'),
      ConnectionState.connected => (Colors.green, Icons.check_circle, 'Connected'),
      ConnectionState.error => (Colors.red, Icons.error, 'Error'),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Chip(
        avatar: Icon(icon, size: 18, color: color),
        label: Text(label),
        backgroundColor: color.withOpacity(0.2),
      ),
    );
  }
}
