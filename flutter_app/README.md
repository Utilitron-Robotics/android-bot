# Droid Controller

Universal robot control app with **dynamic UI generated from rosbridge introspection**.

## Features

- **Auto-discovery**: Connects to robot and discovers available topics, services, and parameters
- **Dynamic UI**: Generates appropriate controls based on what the robot supports
- **Waypoint Navigation**: Tap buttons or enter custom waypoints
- **Voice Control**: "Go to kitchen", "Stop" (on supported devices)
- **Manual Control**: Virtual joystick for direct velocity control
- **Parameter Editor**: View and modify robot parameters
- **Cross-platform**: Android, iOS, Windows, macOS, Linux

## How It Works

1. Connect to robot's rosbridge WebSocket (e.g., `ws://192.168.1.100:9090`)
2. App introspects available capabilities via `/rosapi/*` services
3. UI widgets are generated dynamically based on discoveries:
   - `/poi` service found → Waypoint button grid
   - `/cmd_vel` topic found → Virtual joystick
   - `/robot_status` topic → Status panel
   - Parameters discovered → Settings editor

## Setup

```bash
# Install Flutter: https://flutter.dev/docs/get-started/install

cd flutter_app
flutter pub get
flutter run
```

## Target Robots

Designed for rosbridge-compatible robots, particularly:
- Robot restaurant/delivery robots
- Any robot with rosbridge_server running

## Protocol

Uses standard rosbridge WebSocket protocol:
- `subscribe`/`unsubscribe` for topics
- `call_service` for services (navigation, introspection)
- `publish` for velocity commands

## Project Structure

```
lib/
├── main.dart                    # Entry point
├── core/
│   ├── rosbridge_client.dart    # WebSocket communication
│   └── robot_connection.dart    # State management
├── services/
│   └── robot_introspection.dart # Capability discovery
├── screens/
│   └── home_screen.dart         # Main dynamic screen
└── widgets/
    ├── widget_factory.dart      # Maps discoveries → UI
    ├── waypoint_grid.dart       # Navigation buttons
    ├── joystick.dart            # Manual control
    ├── status_panel.dart        # Battery, nav state
    ├── voice_control.dart       # Speech input
    └── parameter_list.dart      # Robot settings
```

## Zero Maintenance Philosophy

The UI adapts automatically to:
- Different robot models
- Firmware updates that add/remove features
- New waypoints added on the robot

No app updates needed when robot capabilities change.
