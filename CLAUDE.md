# CLAUDE.md - Project Context for AI Assistants

This file contains essential project information for Claude Code sessions. Read this first.

## Quick Reference

### Debug Workflow

**Flutter App** (control UI):
```bash
cd flutter_app
flutter run -d chrome
```

**Android Relay App** (tablet bridge):
- Open `relay_app/` in Android Studio
- Hit Run
- All droids start up automatically in wifi debug mode so we can grab them anywhere

### Build Commands

**Flutter APK** (for production tablets):
```bash
cd flutter_app
flutter pub get
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

**Android Relay APK**:
```bash
cd relay_app
./gradlew assembleRelease
# Output: app/build/outputs/apk/release/app-release.apk
```

---

## Project Overview

**Name**: RobotOS Pro / Droid Controller
**Purpose**: Control system for CIOT/Chassis robots with Android tablet relay

### Two Separate Apps

| App | Location | Language | Purpose |
|-----|----------|----------|---------|
| **Relay App** | `relay_app/` | Kotlin | Runs on robot's Android tablet, bridges gRPC↔rosbridge |
| **Flutter App** | `flutter_app/` | Dart | Control UI for phones/tablets/web |

**IMPORTANT**: These are NOT the same app. Don't confuse them.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        HOUSE WIFI                                │
│                                                                   │
│   Flutter App ←──────────────→ Android Tablet (Relay)            │
│   (Phone/PC/Web)                   │                             │
│                                    │ gRPC :50051                 │
│   Protocols:                       │ WS :8766                    │
│   • gRPC (primary)                 │ HTTP :8765                  │
│   • WebSocket (fallback)           │                             │
│   • HTTP (last resort)             │                             │
│                                    │                             │
└────────────────────────────────────┼─────────────────────────────┘
                                     │
                              WIRED USB CONNECTION
                              192.168.20.22:9090
                                     │
                         ┌───────────┴───────────┐
                         │    ROBOT BASE (ROS)   │
                         │                       │
                         │  WiFi: 10.42.0.1:9090 │
                         │  (diagnostics only)   │
                         └───────────────────────┘
```

**Key Points**:
- Tablet is WIRED to robot (not WiFi)
- Flutter apps connect to the relay tablet
- Robot's WiFi hotspot is for diagnostics only
- gRPC is the primary protocol (WAN-ready, binary, reliable)

---

## Network Ports

| Port | Protocol | App | Purpose |
|------|----------|-----|---------|
| 50051 | gRPC | Relay | Primary command channel |
| 8765 | HTTP | Relay | REST API fallback |
| 8766 | WebSocket | Relay | LAN legacy support |
| 9090 | WebSocket | Robot | rosbridge (wired connection) |
| 9999 | UDP | Relay | Discovery broadcast |

---

## CIOT/Chassis Robot Specifics

### Robot Status Codes (nav_status)
- 600: Idle
- 601: Moving
- 602: Cancelled
- 603: Arrived
- 604: Failed
- 605: Standby

### Key ROS Topics
- `/robot_status` - Robot state (type: `yutong_assistance/RobotStatus`)
- `/cmd_vel_mux/input/teleop` - Velocity commands (type: `geometry_msgs/Twist`)
- `/move_base/cancel` - Cancel navigation (type: `actionlib_msgs/GoalID`)

### Key ROS Services
- `/poi` - Navigate to waypoint (args: `{poi: "waypoint_name"}`)

### Velocity Command Format
```json
{
  "linear": {"x": 0.5},
  "angular": {"z": 0.3}
}
```
Speed commands last 0.6 seconds per protocol spec.

---

## Common Issues & Fixes

### Flutter: "Xcode not found" error
```bash
flutter config --no-enable-ios
flutter config --no-enable-macos-desktop
```

### Flutter: Provider not found
Check `main.dart` has the provider in `MultiProvider.providers[]`

### Relay: "Unresolved reference: messages"
Use `incomingMessages` not `messages` for `RobotWebSocketClient`

### Relay: WebRTC sdpMLine error
Use `sdpMLineIndex` not `sdpMLine` (Stream WebRTC API)

### gRPC on Web/Chrome
gRPC doesn't work in browsers (no raw sockets). Use WebSocket fallback.

---

## File Locations

### Protocol Definitions
- `proto/robot_control.proto` - gRPC service definition

### Relay App Key Files
- `relay_app/app/src/main/java/com/utilitron/robotrelay/`
  - `service/RelayService.kt` - Main service
  - `grpc/GrpcServer.kt` - gRPC server
  - `grpc/RobotControlServiceImpl.kt` - gRPC implementation
  - `websocket/RobotWebSocketClient.kt` - Robot connection
  - `service/WebRtcManager.kt` - WebRTC handling

### Flutter App Key Files
- `flutter_app/lib/`
  - `main.dart` - App entry, providers
  - `screens/hud_screen.dart` - Main UI
  - `core/unified_transport.dart` - Transport selection
  - `core/grpc_client.dart` - gRPC client
  - `core/robot_connection.dart` - Robot state
  - `widgets/map_view.dart` - Map display

### Generated Protobuf
- `flutter_app/lib/generated/robot_control.pb.dart`
- `flutter_app/lib/generated/robot_control.pbgrpc.dart`

---

## Development Workflow

### Making Changes to Flutter App
1. Edit files in `flutter_app/lib/`
2. Run `flutter run -d chrome` (hot reload works)
3. Test functionality
4. Commit and push

### Making Changes to Relay App
1. Edit Kotlin files in `relay_app/app/src/main/`
2. Open `relay_app/` in Android Studio
3. Hit Run - droids are in wifi debug mode and can be grabbed anywhere
4. Monitor logs in Android Studio Logcat

### Updating Protocol Buffers
1. Edit `proto/robot_control.proto`
2. Flutter: Files auto-regenerate on build
3. Relay: Files auto-regenerate via Gradle plugin

---

## Testing Checklist

### Flutter App
- [ ] Connects to relay via WebSocket (ws://IP:8766)
- [ ] Map loads and displays robot position
- [ ] Joystick sends velocity commands
- [ ] Navigation to waypoints works
- [ ] Tours execute correctly

### Relay App
- [ ] gRPC server starts on :50051
- [ ] WebSocket server starts on :8766
- [ ] Connects to robot at 192.168.20.22:9090
- [ ] Commands forward to robot
- [ ] Status updates flow back to clients

---

## Don't Do These Things

1. **Don't** try to use gRPC on web/Chrome (it won't work)
2. **Don't** connect Flutter directly to robot (go through relay)
3. **Don't** assume WiFi connection to robot (it's wired USB)
4. **Don't** confuse relay_app with flutter_app
5. **Don't** push to main without testing
6. **Don't** make changes without understanding the transport layer

---

## Session Continuity Notes

When starting a new session:
1. Read this file first
2. Check `git status` for current state
3. Ask user what they're working on
4. Don't assume - ask if unclear

The user debugs with:
- Flutter: `flutter run -d chrome`
- Relay: Android Studio - open relay_app and hit Run (droids are in wifi debug mode)

---

## AI Instructions

- Never suggest workarounds that disable required functionality
- If a build/tool error occurs, the solution must preserve all features
- Think through consequences before suggesting fixes
- When in doubt, ask what features are required
- Don't repeat suggestions that have already been tried
