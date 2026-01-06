# Android-Bot Project Documentation

## Project Overview
Cross-platform robot control system for Pudu/smAiT food service robots using the smAiT Upper Computer Communication Protocol. Consists of:
1. **Flutter App** - Primary cross-platform controller (macOS/iOS/Android/Web)
2. **Relay App** - Android tablet bridge for remote control via house WiFi

## Architecture

### Network Topology
```
┌─────────────────────────────────────────────────────────────┐
│                    House WiFi Network                       │
│                                                             │
│   ┌─────────────┐           ┌───────────────────┐          │
│   │ Flutter App │ ←───────→ │  Android Tablet   │          │
│   │ (Any Device)│ WebSocket │  (Relay Server)   │          │
│   └─────────────┘  :8766    │  HTTP :8765       │          │
│                              └─────────┬─────────┘          │
└──────────────────────────────────────────────────────────────┘
                                         │
                                    WiFi Switch
                                         │
                              ┌──────────┴──────────┐
                              │   Robot WiFi        │
                              │   10.42.0.1:9090    │
                              └──────────┬──────────┘
                                         │
                              ┌──────────┴──────────┐
                              │   Pudu/smAiT Robot  │
                              │   Base Controller   │
                              └─────────────────────┘
```

### Connection Methods
| Method | Target | Use Case |
|--------|--------|----------|
| Direct WiFi | `ws://10.42.0.1:9090` | Diagnostic, local control |
| Relay HTTP | `http://tablet-ip:8765` | REST API commands |
| Relay WebSocket | `ws://tablet-ip:8766` | Full bidirectional (Flutter) |

## Robot Configuration

### WiFi Credentials
| Robot | SSID | Password | Direct IP |
|-------|------|----------|-----------|
| Pudu Bot 1 | TY126AA003F0-005878 | 123456789 | 10.42.0.1:9090 |
| Pudu Bot 2 | TY126AA003F0-005993 | 123456789 | 10.42.0.1:9090 |

### smAiT Protocol Reference
Based on "smAiT Upper Computer Communication Protocol" - JSON over WebSocket (rosbridge-like).

**Key Topics:**
| Topic | Type | Description |
|-------|------|-------------|
| `/robot_status` | `yutong_assistance/RobotStatus` | Battery, nav state, estop status |
| `/robot_pose` | `geometry_msgs/Pose2D` | x, y, theta position |
| `/cmd_vel_mux/input/teleop` | `geometry_msgs/Twist` | Velocity control (0.6s duration) |
| `/move_base/cancel` | `actionlib_msgs/GoalID` | Cancel navigation |
| `/map` | `nav_msgs/OccupancyGrid` | SLAM map data |

**Key Services:**
| Service | Args | Description |
|---------|------|-------------|
| `/poi` | `{"poi": ""}` | Empty string returns waypoint list |
| `/poi` | `{"poi": "P1"}` | Navigate to waypoint P1 |
| `/soft_estop` | `{"data": true}` | Enable/disable soft stop |

**Navigation Status Codes:**
| Code | Status |
|------|--------|
| 600 | Idle/Waiting |
| 601 | Moving |
| 602 | Cancelled |
| 603 | Arrived/Success |
| 604 | Failed |
| 605 | Standby |

**Velocity Commands:**
- Speed lasts 0.6 seconds per protocol spec
- Must advertise before publishing to `/cmd_vel_mux/input/teleop`
- Linear: max 0.5 m/s (0.25 m/s in SLAM safe mode)
- Angular: max 1.0 rad/s

## Tour Mode

The system supports automated guided tours with customer-facing tablet display.

### Tour Sequence Execution
Tours are defined as sequences of stops, each with:
- **Waypoint** - Navigation destination
- **Display URL** - Website/image shown on tablet (or default POI branding)
- **Speak Text** - TTS narration at the stop
- **Wait Time** - Dwell time AFTER speech completes

**Execution Order per Stop:**
1. Navigate to waypoint
2. Display content (custom URL or default POI name)
3. Arrival sound + announcement (if enabled)
4. Custom speak text
5. Wait timer (additional time after speech)

### Tour Configuration
| Field | Description |
|-------|-------------|
| `startWaypoint` | Navigate here before starting tour |
| `endWaypoint` | Navigate here after completing tour |
| `restAtEndSeconds` | Wait at end before returning to start (for loops) |
| `introText` | Spoken before starting tour |
| `outroText` | Spoken after completing tour |
| `announceArrival` | Say "Arrived at [waypoint]" at each stop |
| `loop` | Repeat tour continuously |

### Tablet Lock Screen (Tour Mode)
When a tour starts, the tablet enters **Tour Mode**:
- Screen is locked to prevent customer access to controls
- Displays company branding or custom URLs
- Shows floating countdown timer (bottom-right corner)

**Unlock Sequence:**
1. Tap screen 6 times within 2 seconds
2. First tap triggers TTS: "Please do not touch the screen until asked to do so"
3. After 3+ taps, shows "Tap X more times..."
4. After 6 taps, PIN entry appears (default PIN: 1234)

### Tablet WebSocket Commands
| Command | Description |
|---------|-------------|
| `tablet_countdown` | Update countdown timer overlay |
| `tablet_tour_start` | Start tour mode (lock screen) |
| `tablet_tour_stop` | Stop tour mode (unlock screen) |
| `tablet_display` | Show URL in WebView |
| `tablet_speak` | TTS announcement |

## Flutter App Structure

### Key Files
```
flutter_app/lib/
├── main.dart                    # App entry, Provider setup
├── core/
│   ├── robot_connection.dart    # RobotConnection ChangeNotifier
│   ├── rosbridge_client.dart    # Low-level WebSocket client
│   ├── fleet_discovery.dart     # Robot fleet management
│   ├── dual_connection.dart     # Direct + relay mode switching
│   ├── sequence_mode.dart       # Tour/sequence definitions & SequenceManager
│   ├── buffer_client.dart       # Command buffer client for relay
│   └── buffer_sequence_executor.dart  # Tour execution via buffer
├── screens/
│   ├── home_screen.dart         # Main UI with connection bar
│   └── hud_screen.dart          # HUD with tour controls & countdown
├── services/
│   ├── robot_introspection.dart # Capability discovery
│   ├── audio_announcer.dart     # TTS singleton for announcements
│   └── sequence_executor.dart   # Tour execution service
└── widgets/
    ├── widget_factory.dart      # Dynamic UI based on capabilities
    ├── waypoint_grid.dart       # POI navigation buttons
    ├── joystick.dart            # Manual velocity control
    ├── voice_control.dart       # Speech-to-text waypoint selection
    ├── map_view.dart            # Real-time SLAM map display
    ├── status_panel.dart        # Battery, nav status display
    ├── fleet_picker.dart        # Robot selection dialog
    └── sequence_editor.dart     # Tour creation/editing UI
```

### State Management
- Provider pattern with `RobotConnection` as main ChangeNotifier
- `Consumer<RobotConnection>` widgets react to status updates
- `RobotStatus` class holds live data from `/robot_status`

### Critical Bug Fixes Applied
1. **Robot Switching**: Must call `disconnect()` before `connect()` to avoid sending commands to wrong robot
2. **Waypoint Button State**: Uses `_checkNavStatus()` in Consumer to clear navigating state on arrival
3. **Default IPs**: Use `10.42.0.1` (direct WiFi) not `192.168.20.22` (tablet relay)

## Relay App (Android)

### Overview
Runs on Android tablet mounted on robot. Bridges house WiFi to robot WiFi.
Provides both technician controls and customer-facing tour display.

### Ports
| Port | Protocol | Description |
|------|----------|-------------|
| 8765 | HTTP | REST API for simple commands |
| 8766 | WebSocket | Full bidirectional relay |

### HTTP Endpoints
```
GET  /         - Server info page
GET  /status   - Robot status JSON
GET  /info     - Request robot info
POST /cmd      - Raw rosbridge JSON
POST /velocity - {"linear": 0.2, "angular": 0.0}
POST /navigate - {"poi": "P1"}
POST /stop     - Zero velocity
POST /estop    - {"enabled": true/false}
POST /cancel   - Cancel navigation
```

### UI Layers
The tablet UI has multiple overlays:
1. **Main Layout** - Technician controls (joystick, status, waypoint buttons)
2. **WebView** - Customer-facing display (URLs, company branding)
3. **Countdown Overlay** - Floating timer (bottom-right, above WebView)
4. **Lock Overlay** - Tour mode lock screen (full screen, above all)

### Key Files
```
relay_app/app/src/main/java/com/smait/robotrelay/
├── ui/
│   └── MainActivity.kt          # UI with joystick, tour mode, lock screen
├── service/
│   ├── RelayService.kt          # Foreground service, TTS, tour mode
│   ├── RelayServer.kt           # HTTP + WebSocket servers
│   ├── CommandBuffer.kt         # Sequence command execution
│   └── RobotWebSocketClient.kt  # Connection to robot base
├── protocol/
│   └── SmaitProtocol.kt         # Protocol message builders
└── cloud/
    ├── AwsIotClient.kt          # Future: AWS IoT integration
    └── FleetManager.kt          # Future: Fleet management
```

### Build Requirements
- Android SDK 34
- Kotlin
- Min SDK 24 (Android 7.0)
- Java 17

### Dependencies
- OkHttp 4.12.0 (WebSocket client)
- NanoHTTPD 2.3.1 (HTTP/WebSocket server)
- Gson 2.10.1 (JSON parsing)
- Kotlin Coroutines 1.7.3

## Development Setup

### Flutter App
```bash
cd flutter_app
flutter pub get
flutter run -d macos  # or ios, android, chrome
```

### Relay App
```bash
cd relay_app
./gradlew assembleDebug
# Install APK on tablet: relay_app/app/build/outputs/apk/debug/app-debug.apk
```

Or open in Android Studio and run directly on tablet.

## Testing

### Direct Connection Test
```bash
# Test robot WebSocket
nc -z -w 3 10.42.0.1 9090 && echo "ROBOT ONLINE"

# Basic WebSocket handshake
(echo -e "GET / HTTP/1.1\r\nHost: 10.42.0.1:9090\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n"; sleep 1) | nc 10.42.0.1 9090
```

### Relay Test
```bash
# Check relay status
curl http://tablet-ip:8765/status

# Send velocity command
curl -X POST http://tablet-ip:8765/velocity -H "Content-Type: application/json" -d '{"linear":0.1,"angular":0}'

# Navigate to POI
curl -X POST http://tablet-ip:8765/navigate -H "Content-Type: application/json" -d '{"poi":"P1"}'
```

## Audio Announcements

The Flutter app uses TTS to announce:
- "Navigating to [waypoint]" - Nav status 601
- "Arrived at [waypoint]" - Nav status 603
- "Navigation cancelled" - Nav status 602
- "Navigation failed. Path blocked." - Nav status 604
- Low battery warnings at 20% and 10%

Toggle audio in joystick widget.

## Future Development

### Planned Features
- Camera/microphone integration for video calling
- AWS IoT cloud fleet management
- Multi-robot coordination
- Obstacle avoidance visualization
- Route planning interface

### Infrastructure
AWS CloudFormation stack defined in `infrastructure/turboturf-stack.yaml` for:
- IoT Core for robot fleet
- Lambda for command processing
- DynamoDB for telemetry storage
