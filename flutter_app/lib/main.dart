import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/unified_transport.dart';
import 'core/robot_connection.dart';
import 'core/fleet_discovery.dart';
import 'core/sequence_mode.dart';
import 'core/task_engine.dart';
import 'screens/hud_screen.dart';

// Global instance of the transport manager
final unifiedTransportManager = UnifiedTransportManager(
  endpoints: const TransportEndpoints(
    // gRPC host is set dynamically when user connects to a relay
    grpcHost: null,
    robotId: 'robot-1',
  ),
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Don't auto-connect - wait for user to provide the relay IP

  // Load other saved states
  await SequenceManager.instance.load();
  await TaskEngine.instance.load();

  runApp(const DroidControllerApp());
}

class DroidControllerApp extends StatelessWidget {
  const DroidControllerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Provide the single instance of the transport manager
        ChangeNotifierProvider.value(value: unifiedTransportManager),
        // Legacy WebSocket connection for direct rosbridge communication
        ChangeNotifierProvider(create: (_) => RobotConnection()),
        ChangeNotifierProvider(create: (_) => FleetDiscovery()),
        ChangeNotifierProvider.value(value: SequenceManager.instance),
      ],
      child: MaterialApp(
        title: 'Droid Controller',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF00D4FF), // Cyberpunk cyan
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const HudScreen(),
      ),
    );
  }
}


