# TourBot - Native Android Service Droid Application

A Kotlin/Jetpack Compose Android application for service droids, interactive kiosks, and tour guide robots. Designed to run on Android tablets mounted on robot bases like the Tibo.

## Features

- **Animated Robot Face**: Point cloud 3D face with phoneme-based lip sync
- **Tour Management**: Waypoint navigation with audio narration
- **Multi-Base Support**: Works with Tibo, robots with Orin Nano, Raspberry Pi bases
- **WebSocket Communication**: Real-time robot control via ROS bridge
- **Test Mode**: Full simulation for development without robot hardware

## Quick Start

1. **Open in Android Studio:**
   Open the project root folder in Android Studio (Ladybug or newer recommended).

2. **Build & Deploy:**
   ```bash
   ./deploy.sh
   ```
   Or use Android Studio's Run button.

3. **Test Mode:**
   The app starts in test mode by default. Use the Control Panel to toggle between test and real robot modes.

## Documentation

- [**HANDOFF_TO_REAL.md**](HANDOFF_TO_REAL.md) - Instructions for connecting to real robot hardware
- [**ANDROID_MIGRATION_PLAN.md**](ANDROID_MIGRATION_PLAN.md) - Architecture documentation
- [**PRODUCTION_READINESS_REVIEW.md**](PRODUCTION_READINESS_REVIEW.md) - Codebase review and deployment checklist

## Robot Configuration

The app uses WebSockets to communicate with the robot base (ROS bridge).

| Mode | Default URL | Description |
|------|-------------|-------------|
| Emulator | `ws://10.0.2.2:9090` | Connects to localhost on host machine |
| Real Robot | `ws://10.42.0.1:9090` | Tibo robot default IP |

Configure the robot URL in **Settings** or modify `SettingsManager.kt`.

## Project Structure

```
app/src/main/java/com/opendroids/tourbot/
├── data/           # Repository layer, models, settings
├── di/             # Hilt dependency injection modules
├── logic/          # TourManager business logic
├── ui/             # Compose UI, screens, components
│   └── components/pointcloud/  # 3D face animation
└── MainActivity.kt
```

## Security Note

This app uses cleartext WebSocket (`ws://`) for local robot communication. This is intentional for LAN-only robot control. See `network_security_config.xml`.
