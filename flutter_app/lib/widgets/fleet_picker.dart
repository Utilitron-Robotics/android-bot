import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/fleet_discovery.dart';
import '../core/robot_connection.dart';
import '../core/relay_discovery_stub.dart'
    if (dart.library.io) '../core/relay_discovery.dart' as relay_discovery;

/// Fleet picker with WiFi scanning and robot selection
class FleetPicker extends StatefulWidget {
  const FleetPicker({super.key});

  static Future<RobotBase?> show(BuildContext context) {
    return showModalBottomSheet<RobotBase>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<FleetDiscovery>(),
        child: const FleetPicker(),
      ),
    );
  }

  @override
  State<FleetPicker> createState() => _FleetPickerState();
}

class _FleetPickerState extends State<FleetPicker>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  final _ipController = TextEditingController(); // No hardcoded default
  final _portController = TextEditingController(text: '9090');
  final _nicknameController = TextEditingController();
  final _relayIpController = TextEditingController();
  bool _showAddForm = false;
  bool _scanningRelays = false;
  List<String> _discoveredRelays = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final fleet = context.read<FleetDiscovery>();
      fleet.getCurrentSsid();
      fleet.refreshRobotStatus();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _ssidController.dispose();
    _passwordController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _nicknameController.dispose();
    _relayIpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Consumer<FleetDiscovery>(
          builder: (context, fleet, _) {
            return Column(
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Current WiFi status
                if (fleet.currentSsid != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.wifi, size: 16, color: Colors.green),
                        const SizedBox(width: 8),
                        Text(
                          'WiFi: ${fleet.currentSsid}',
                          style:
                              TextStyle(color: Colors.grey[400], fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                // Tab bar
                TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(icon: Icon(Icons.router), text: 'Robots'),
                    Tab(icon: Icon(Icons.wifi_find), text: 'Scan WiFi'),
                    Tab(icon: Icon(Icons.tablet_android), text: 'Relay'),
                  ],
                ),
                // Tab content
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildRobotsTab(fleet, scrollController),
                      _buildWifiScanTab(fleet, scrollController),
                      _buildRelayTab(scrollController),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Robots tab - list known robots and add new ones
  Widget _buildRobotsTab(
      FleetDiscovery fleet, ScrollController scrollController) {
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              const Spacer(),
              if (fleet.isScanning)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => fleet.refreshRobotStatus(),
                  tooltip: 'Refresh status',
                ),
              IconButton(
                icon: Icon(_showAddForm ? Icons.close : Icons.add),
                onPressed: () => setState(() => _showAddForm = !_showAddForm),
                tooltip: _showAddForm ? 'Cancel' : 'Add robot',
              ),
            ],
          ),
        ),
        // Add form
        if (_showAddForm) _buildAddForm(fleet),
        // Robot list
        Expanded(
          child: fleet.knownRobots.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.smart_toy, size: 48, color: Colors.grey[600]),
                      const SizedBox(height: 8),
                      const Text('No robots configured'),
                      const SizedBox(height: 4),
                      Text(
                        'Tap + to add, or scan WiFi',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: scrollController,
                  itemCount: fleet.knownRobots.length,
                  itemBuilder: (context, index) {
                    final robot = fleet.knownRobots[index];
                    return _buildRobotTile(robot, fleet);
                  },
                ),
        ),
      ],
    );
  }

  /// WiFi scan tab - scan and connect to robot networks
  Widget _buildWifiScanTab(
      FleetDiscovery fleet, ScrollController scrollController) {
    return Column(
      children: [
        // Scan controls
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      fleet.isScanning ? null : () => fleet.scanWifiNetworks(),
                  icon: fleet.isScanning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_find),
                  label: Text(
                      fleet.isScanning ? 'Scanning...' : 'Scan All Networks'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: fleet.isScanning
                    ? null
                    : () => fleet.scanWifiNetworks(filterRobots: true),
                icon: const Icon(Icons.filter_alt),
                label: const Text('Robots Only'),
              ),
            ],
          ),
        ),
        // Error message
        if (fleet.lastError != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              fleet.lastError!,
              style: TextStyle(color: Colors.orange[300], fontSize: 12),
            ),
          ),
        // Scanned networks list
        Expanded(
          child: fleet.scannedNetworks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi_find, size: 48, color: Colors.grey[600]),
                      const SizedBox(height: 8),
                      const Text('No networks scanned'),
                      const SizedBox(height: 4),
                      Text(
                        'Tap "Scan" to find nearby WiFi',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: scrollController,
                  itemCount: fleet.scannedNetworks.length,
                  itemBuilder: (context, index) {
                    final network = fleet.scannedNetworks[index];
                    return _buildNetworkTile(network, fleet);
                  },
                ),
        ),
      ],
    );
  }

  /// Relay tab - connect through tablet relay
  Widget _buildRelayTab(ScrollController scrollController) {
    return Column(
      children: [
        // Scan controls
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Connect via Tablet Relay',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 4),
              Text(
                'Use a tablet running Robot Relay app as a bridge',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _relayIpController,
                      decoration: const InputDecoration(
                        labelText: 'Relay IP Address',
                        hintText: '192.168.1.100',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => _connectToRelay(_relayIpController.text),
                    child: const Text('Connect'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _scanningRelays ? null : _scanForRelays,
                icon: _scanningRelays
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: Text(_scanningRelays ? 'Scanning...' : 'Scan Network for Relays'),
              ),
            ],
          ),
        ),
        // Discovered relays list
        Expanded(
          child: _discoveredRelays.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.tablet_android, size: 48, color: Colors.grey[600]),
                      const SizedBox(height: 8),
                      const Text('No relays discovered'),
                      const SizedBox(height: 4),
                      Text(
                        'Enter IP manually or scan network',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: scrollController,
                  itemCount: _discoveredRelays.length,
                  itemBuilder: (context, index) {
                    final ip = _discoveredRelays[index];
                    return ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.green,
                        child: Icon(Icons.tablet_android, color: Colors.white),
                      ),
                      title: Text('Relay at $ip'),
                      subtitle: Text('http://$ip:8765 • ws://$ip:8766'),
                      trailing: FilledButton(
                        onPressed: () => _connectToRelay(ip),
                        child: const Text('Connect'),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _scanForRelays() async {
    setState(() => _scanningRelays = true);
    try {
      // UDP broadcast on :9999 - subnet-agnostic, the relay answers itself
      final relays = await relay_discovery.scanForRelays(
        timeout: const Duration(seconds: 2),
      );
      if (mounted) setState(() => _discoveredRelays = relays);
    } on UnsupportedError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Relay scan unavailable')),
        );
      }
    } finally {
      if (mounted) setState(() => _scanningRelays = false);
    }
  }

  void _connectToRelay(String ip) {
    if (ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter relay IP address')),
      );
      return;
    }
    // Return a special RobotBase that indicates relay mode
    Navigator.pop(context, RobotBase(
      ssid: 'RELAY:$ip',
      ip: ip,
      port: 8766, // WebSocket port
      nickname: 'Relay @ $ip',
    ));
  }

  Widget _buildAddForm(FleetDiscovery fleet) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Add Robot Manually',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _ssidController,
                    decoration: const InputDecoration(
                      labelText: 'WiFi SSID',
                      hintText: 'PUDU_XXXX',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    obscureText: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _ipController,
                    decoration: const InputDecoration(
                      labelText: 'Robot IP',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _portController,
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nicknameController,
              decoration: const InputDecoration(
                labelText: 'Nickname (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _addRobot(fleet),
              icon: const Icon(Icons.add),
              label: const Text('Add Robot'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRobotTile(RobotBase robot, FleetDiscovery fleet) {
    final isCurrentWifi = fleet.currentSsid == robot.ssid;

    return Dismissible(
      key: Key(robot.ssid),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Remove Robot?'),
            content: Text('Remove ${robot.displayName}?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Remove')),
            ],
          ),
        );
      },
      onDismissed: (_) => fleet.removeRobot(robot.ssid),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: robot.isOnline
              ? Colors.green
              : (isCurrentWifi ? Colors.blue : Colors.grey),
          child: Icon(
            robot.isOnline
                ? Icons.check
                : (isCurrentWifi ? Icons.wifi : Icons.wifi_off),
            color: Colors.white,
          ),
        ),
        title: Text(robot.displayName),
        subtitle: Text('${robot.ssid} → ${robot.wsUrl}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (robot.isOnline)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('Online',
                    style: TextStyle(fontSize: 11, color: Colors.white)),
              ),
            if (!isCurrentWifi && !robot.isOnline)
              IconButton(
                icon: const Icon(Icons.wifi),
                onPressed: () => _connectToRobotWifi(robot, fleet),
                tooltip: 'Connect WiFi',
              ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => _selectRobot(robot),
      ),
    );
  }

  Widget _buildNetworkTile(ScannedNetwork network, FleetDiscovery fleet) {
    final isCurrent = fleet.currentSsid == network.ssid;
    final signalIcon = network.rssi > -50
        ? Icons.signal_wifi_4_bar
        : network.rssi > -70
            ? Icons.network_wifi_3_bar
            : Icons.network_wifi_1_bar;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isCurrent ? Colors.green : Colors.blueGrey,
        child: Icon(signalIcon, color: Colors.white, size: 20),
      ),
      title: Text(network.ssid),
      subtitle: Text(
        '${network.rssi} dBm • ${network.signalPercent}% • ${network.isSecured ? 'Secured' : 'Open'}',
      ),
      trailing: isCurrent
          ? const Chip(label: Text('Connected'), backgroundColor: Colors.green)
          : FilledButton(
              onPressed: fleet.isConnecting
                  ? null
                  : () => _connectToNetwork(network, fleet),
              child: fleet.isConnecting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Connect'),
            ),
    );
  }

  void _addRobot(FleetDiscovery fleet) {
    final ssid = _ssidController.text.trim();
    final password = _passwordController.text;
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 9090;
    final nickname = _nicknameController.text.trim();

    if (ssid.isEmpty || ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SSID and IP are required')),
      );
      return;
    }

    final robot = RobotBase(
      ssid: ssid,
      ip: ip,
      port: port,
      nickname: nickname.isNotEmpty ? nickname : null,
      password: password.isNotEmpty ? password : null,
    );

    fleet.addRobot(robot);
    setState(() => _showAddForm = false);
    _ssidController.clear();
    _passwordController.clear();
    _ipController.clear(); // No hardcoded default
    _portController.text = '9090';
    _nicknameController.clear();
  }

  Future<void> _connectToNetwork(
      ScannedNetwork network, FleetDiscovery fleet) async {
    String? password;

    if (network.isSecured) {
      password = await showDialog<String>(
        context: context,
        builder: (context) {
          final controller = TextEditingController();
          return AlertDialog(
            title: Text('Connect to ${network.ssid}'),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              autofocus: true,
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, controller.text),
                  child: const Text('Connect')),
            ],
          );
        },
      );
      if (password == null) return;
    }

    final result = await fleet.connectToWifi(network.ssid, password: password);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: result.success ? Colors.green : Colors.red,
        ),
      );

      if (result.success) {
        // Prompt to add as robot
        _promptAddAsRobot(fleet, network.ssid, password);
      }
    }
  }

  Future<void> _connectToRobotWifi(
      RobotBase robot, FleetDiscovery fleet) async {
    final result =
        await fleet.connectToWifi(robot.ssid, password: robot.password);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: result.success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  void _promptAddAsRobot(FleetDiscovery fleet, String ssid, String? password) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add as Robot?'),
        content: Text('Connected to $ssid. Add it as a robot?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('No')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              final ip = await fleet.getGatewayIp();
              if (ip != null) {
                fleet.addRobot(RobotBase(
                  ssid: ssid,
                  ip: ip,
                  password: password,
                ));
                // Switch to robots tab
                _tabController.animateTo(0);
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Could not determine robot IP')),
                  );
                }
              }
            },
            child: const Text('Add Robot'),
          ),
        ],
      ),
    );
  }

  void _selectRobot(RobotBase robot) {
    // Warn but allow connection to offline robots (ping may have failed due to network)
    if (!robot.isOnline) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Robot Offline'),
          content: Text('${robot.displayName} appears offline. Try connecting anyway?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context, robot);
              },
              child: const Text('Try Anyway'),
            ),
          ],
        ),
      );
      return;
    }
    Navigator.pop(context, robot);
  }
}

/// Quick connect button
class FleetConnectButton extends StatelessWidget {
  const FleetConnectButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<RobotConnection>(
      builder: (context, robot, _) {
        return FilledButton.icon(
          onPressed: robot.state == RobotConnectionState.connecting
              ? null
              : () => _showFleetPicker(context, robot),
          icon: const Icon(Icons.router),
          label: const Text('Fleet'),
        );
      },
    );
  }

  Future<void> _showFleetPicker(
      BuildContext context, RobotConnection robot) async {
    final selected = await FleetPicker.show(context);
    if (selected != null && context.mounted) {
      robot.connect(selected.wsUrl);
    }
  }
}
