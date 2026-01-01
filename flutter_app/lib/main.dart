import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/robot_connection.dart';
import 'core/fleet_discovery.dart';
import 'screens/home_screen.dart';

void main() {
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
      ],
      child: MaterialApp(
        title: 'Droid Controller',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}

