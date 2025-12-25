# TourBot - Multi-Platform Service Droid Application

A cross-platform application for service droids, interactive kiosks, and tour guide robots. Designed to run on Android tablets, iOS devices, and desktop platforms mounted on robot bases.

## 📱 Applications

### Flutter App (Cross-Platform) - `flutter_app/`
Universal robot controller with **dynamic UI generated from rosbridge introspection**.

- **Auto-discovery**: Connects to robot and discovers available topics, services, and parameters
- **Dynamic UI**: Generates appropriate controls based on what the robot supports
- **Waypoint Navigation**: Tap buttons or enter custom waypoints
- **Voice Control**: "Go to kitchen", "Stop" (on supported devices)
- **Manual Control**: Virtual joystick for direct velocity control
- **Cross-platform**: Android, iOS, Windows, macOS, Linux

```bash
cd flutter_app
flutter pub get
flutter run
```

### Android Native App - `app/`
Native Kotlin/Jetpack Compose application with advanced features.

- **Animated Robot Face**: Point cloud 3D face with phoneme-based lip sync
- **Tour Management**: Waypoint navigation with audio narration
- **Multi-Base Support**: Works with Tibo, robots with Orin Nano, Raspberry Pi bases
- **WebSocket Communication**: Real-time robot control via ROS bridge
- **Test Mode**: Full simulation for development without robot hardware

```bash
./deploy.sh
# Or open in Android Studio
```

### Legacy Python - `legacy_python_source/`
Original Python/FastAPI implementation with web UI.

```bash
cd legacy_python_source
pip install -r requirements.txt
python main.py
```

## 🚀 Quick Start

### Flutter (Recommended for New Development)
```bash
cd flutter_app
flutter pub get
flutter run -d chrome  # Web
flutter run -d macos   # macOS
flutter run            # Connected device/emulator
```

### Android Native
```bash
./deploy.sh
# Or open in Android Studio (Ladybug or newer)
```

## 🔧 Robot Configuration

All apps use WebSockets to communicate with the robot base (ROS bridge).

| Mode | Default URL | Description |
|------|-------------|-------------|
| Emulator | `ws://10.0.2.2:9090` | Connects to localhost on host machine |
| Real Robot | `ws://10.42.0.1:9090` | Tibo robot default IP |
| Custom | `ws://192.168.x.x:9090` | Your robot's IP address |

## 📁 Project Structure

```
.
├── flutter_app/                 # Cross-platform Flutter app
│   ├── lib/
│   │   ├── core/               # Connection & rosbridge client
│   │   ├── services/           # Robot introspection
│   │   ├── screens/            # Home screen
│   │   └── widgets/            # Dynamic UI components
│   └── pubspec.yaml
│
├── app/                         # Android native app
│   └── src/main/java/com/opendroids/tourbot/
│       ├── data/               # Repository layer, models
│       ├── di/                 # Hilt dependency injection
│       ├── logic/              # TourManager business logic
│       └── ui/                 # Compose UI, 3D face animation
│
└── legacy_python_source/        # Original Python implementation
    ├── api/                    # Base API and robot factory
    ├── adapters/               # Robot-specific adapters
    ├── apps/                   # Tour bot application
    └── ui/                     # Web interfaces
```

## 📚 Documentation

- [**Flutter App README**](flutter_app/README.md) - Cross-platform app details
- [**HANDOFF_TO_REAL.md**](HANDOFF_TO_REAL.md) - Connecting to real robot hardware
- [**ANDROID_MIGRATION_PLAN.md**](ANDROID_MIGRATION_PLAN.md) - Architecture documentation
- [**PRODUCTION_READINESS_REVIEW.md**](PRODUCTION_READINESS_REVIEW.md) - Deployment checklist

## 🔐 Security Note

These apps use cleartext WebSocket (`ws://`) for local robot communication. This is intentional for LAN-only robot control. For production deployments requiring internet connectivity, implement `wss://` with proper certificate handling.

## 🤝 Contributing

1. Choose the appropriate platform for your changes
2. Follow existing code patterns and architecture
3. Test on at least one platform before submitting
4. Update documentation if adding new features
