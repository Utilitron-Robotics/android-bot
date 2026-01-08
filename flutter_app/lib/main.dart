import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/robot_connection.dart';
import 'core/fleet_discovery.dart';
import 'core/sequence_mode.dart';
import 'core/task_engine.dart';
import 'screens/hud_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load saved tours and task assignments before app starts
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

