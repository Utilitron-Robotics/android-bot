import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/robot_connection.dart';
import '../services/robot_introspection.dart';
import '../widgets/widget_factory.dart';
import '../widgets/fleet_picker.dart';
import '../widgets/message_log.dart';

/// Connection mode options
enum ConnectionMode {
  direct('Direct WiFi', 'ws://10.42.0.1:9090', Icons.wifi),
  relayWs('Relay WS', 'ws://192.168.1.100:8766', Icons.router),
  relayHttp('Relay HTTP', 'http://192.168.1.100:8765', Icons.http);

  final String label;
  final String defaultUrl;
  final IconData icon;
  const ConnectionMode(this.label, this.defaultUrl, this.icon);
}

/// Main screen - dynamically generates UI based on robot capabilities
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _urlController = TextEditingController();
  ConnectionMode _connectionMode = ConnectionMode.direct;

  // Cache generated widgets to prevent recreation on every robot status update
  List<Widget>? _cachedWidgets;
  RobotCapabilities? _cachedCapabilities;
  String? _cachedRelayUrl;

  @override
  void initState() {
    super.initState();
    // Load saved URL and connection mode
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final robot = context.read<RobotConnection>();
      final savedUrl = robot.robotUrl;

      debugPrint('=== HOME PAGE INIT ===');
      debugPrint('Loaded URL from robot: $savedUrl');

      // Always display the last used URL, regardless of mode
      _urlController.text = savedUrl;
      debugPrint('Set URL controller to: ${_urlController.text}');

      // Load saved connection mode
      final hadSavedMode = await _loadConnectionMode();
      debugPrint('Had saved mode: $hadSavedMode, Current mode: ${_connectionMode.name}');

      // ONLY detect mode from URL if there was NO saved mode
      if (!hadSavedMode) {
        debugPrint('HomeScreen: No saved mode found, detecting from URL: $savedUrl');
        _detectModeFromUrl(savedUrl);
      } else {
        debugPrint('HomeScreen: Using saved mode: ${_connectionMode.name}, NOT detecting from URL');
      }
      debugPrint('Final state - URL: ${_urlController.text}, Mode: ${_connectionMode.name}');
      debugPrint('=== END INIT ===');
    });
  }

  /// Get cached widgets, regenerating only when capabilities or relay URL changes
  List<Widget> _getWidgets(RobotCapabilities capabilities, String? relayUrl) {
    // Only regenerate if capabilities or relay URL changed
    if (_cachedWidgets == null ||
        _cachedCapabilities != capabilities ||
        _cachedRelayUrl != relayUrl) {
      debugPrint('HomeScreen: Regenerating widgets (capabilities changed)');
      _cachedCapabilities = capabilities;
      _cachedRelayUrl = relayUrl;
      _cachedWidgets = WidgetFactory(
        capabilities,
        relayHttpUrl: relayUrl,
      ).generateWidgets(context);
    }
    return _cachedWidgets!;
  }

  void _detectModeFromUrl(String url) {
    if (url.contains(':8766')) {
      setState(() => _connectionMode = ConnectionMode.relayWs);
    } else if (url.contains(':8765') || url.startsWith('http')) {
      setState(() => _connectionMode = ConnectionMode.relayHttp);
    } else {
      setState(() => _connectionMode = ConnectionMode.direct);
    }
  }

  void _onModeChanged(ConnectionMode? mode) {
    if (mode == null) return;
    setState(() => _connectionMode = mode);

    // Save the connection mode immediately
    _saveConnectionMode(mode);

    // Preserve the current URL - only update protocol/port if necessary
    final currentUrl = _urlController.text.trim();
    if (currentUrl.isEmpty) {
      // Empty URL - use default for this mode
      _urlController.text = mode.defaultUrl;
      return;
    }

    final uri = Uri.tryParse(currentUrl);
    final host = uri?.host ?? '';

    if (host.isEmpty) {
      // Invalid URL - use default
      _urlController.text = mode.defaultUrl;
      return;
    }

    // Preserve the IP, just update protocol/port to match mode
    if (mode == ConnectionMode.direct) {
      _urlController.text = 'ws://$host:9090';
    } else if (mode == ConnectionMode.relayWs) {
      _urlController.text = 'ws://$host:8766';
    } else {
      _urlController.text = 'http://$host:8765';
    }
  }

  /// Save connection mode to SharedPreferences
  Future<void> _saveConnectionMode(ConnectionMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('connection_mode', mode.name);
    debugPrint('HomeScreen: Saved connection mode: ${mode.name}');
  }

  /// Load connection mode from SharedPreferences
  /// Returns true if a saved mode was found, false otherwise
  Future<bool> _loadConnectionMode() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString('connection_mode');
    if (savedMode != null) {
      final mode = ConnectionMode.values.firstWhere(
        (m) => m.name == savedMode,
        orElse: () => ConnectionMode.direct,
      );
      setState(() => _connectionMode = mode);
      debugPrint('HomeScreen: Loaded connection mode: ${mode.name}');
      return true;
    }
    debugPrint('HomeScreen: No saved connection mode found');
    return false;
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
                  _ConnectionIndicator(state: robot.state, robotUrl: robot.robotUrl),
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
              // Message log (always visible, collapsible)
              const SliverToBoxAdapter(
                child: MessageLog(),
              ),
              // Dynamic content based on connection state
              if (robot.state == RobotConnectionState.connecting)
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
              else if (robot.state == RobotConnectionState.error)
                SliverFillRemaining(
                  child: _buildErrorState(robot),
                )
              else if (robot.state == RobotConnectionState.connected &&
                  robot.capabilities != null)
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate(
                      // Use cached widgets to prevent recreation on every status update
                      _getWidgets(robot.capabilities!, _getRelayHttpUrl()),
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
            // Connection mode dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade600),
                borderRadius: BorderRadius.circular(4),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<ConnectionMode>(
                  value: _connectionMode,
                  isDense: true,
                  icon: const Icon(Icons.arrow_drop_down, size: 20),
                  items: ConnectionMode.values.map((mode) {
                    return DropdownMenuItem(
                      value: mode,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(mode.icon, size: 16),
                          const SizedBox(width: 6),
                          Text(mode.label, style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: robot.state == RobotConnectionState.connecting
                      ? null
                      : _onModeChanged,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _urlController,
                decoration: InputDecoration(
                  labelText: 'Robot URL',
                  hintText: _connectionMode.defaultUrl,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  prefixIcon: const Icon(Icons.link),
                ),
                enabled: robot.state != RobotConnectionState.connecting,
                onSubmitted: (_) => _connect(robot),
              ),
            ),
            const SizedBox(width: 8),
            // Fleet picker button
            const FleetConnectButton(),
            const SizedBox(width: 8),
            if (robot.isConnected)
              FilledButton.tonalIcon(
                onPressed: robot.disconnect,
                icon: const Icon(Icons.link_off),
                label: const Text('Disconnect'),
              )
            else
              FilledButton.icon(
                onPressed: robot.state == RobotConnectionState.connecting
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
    var url = _urlController.text.trim();
    if (url.isEmpty) return;

    // Convert HTTP URL to WebSocket URL for rosbridge connection
    // HTTP is only for REST API calls (tablet tasks), not for rosbridge protocol
    if (url.startsWith('http://')) {
      final uri = Uri.tryParse(url);
      if (uri != null) {
        // Use WebSocket on port 8766 for rosbridge
        url = 'ws://${uri.host}:8766';
        debugPrint('HomeScreen: Converted HTTP URL to WebSocket: $url');
      }
    }

    robot.connect(url);
  }

  /// Get the HTTP relay URL for tablet tasks (if using relay mode)
  String? _getRelayHttpUrl() {
    // Only provide relay URL if we're in relay mode
    if (_connectionMode == ConnectionMode.direct) return null;

    final currentUrl = _urlController.text;
    final uri = Uri.tryParse(currentUrl);
    if (uri == null) return null;

    // Return HTTP URL on port 8765
    return 'http://${uri.host}:8765';
  }
}

class _ConnectionIndicator extends StatelessWidget {
  final RobotConnectionState state;
  final String robotUrl;

  const _ConnectionIndicator({required this.state, required this.robotUrl});

  /// Extract a short name from the robot URL
  String get _robotName {
    if (state != RobotConnectionState.connected) return '';
    // Extract IP from ws://10.42.0.1:9090
    final uri = Uri.tryParse(robotUrl);
    if (uri != null) {
      return uri.host;
    }
    return robotUrl;
  }

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (state) {
      RobotConnectionState.disconnected => (Colors.grey, Icons.link_off, 'Disconnected'),
      RobotConnectionState.connecting => (Colors.orange, Icons.sync, 'Connecting...'),
      RobotConnectionState.connected => (Colors.green, Icons.check_circle, _robotName),
      RobotConnectionState.error => (Colors.red, Icons.error, 'Error'),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Chip(
        avatar: Icon(icon, size: 18, color: color),
        label: Text(label),
        backgroundColor: color.withValues(alpha: 0.2),
      ),
    );
  }
}
