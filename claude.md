# Android-Bot Project Documentation

## Development Rules (MUST FOLLOW)
- **NEVER hardcode time values** - All delays, timeouts, and intervals must be configurable constants or parameters, not magic numbers inline
- **Use Kotlin, not Java** - The relay app is 100% Kotlin

## Project Overview
Cross-platform robot control system for Robot/chassis food service robots using the chassis Upper Computer Communication Protocol. Consists of:
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
                              │   Robot/chassis Robot  │
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
| Robot Bot 1 | MobileBase003F0-005878 | 123456789 | 10.42.0.1:9090 |
| Robot Bot 2 | MobileBase003F0-005993 | 123456789 | 10.42.0.1:9090 |

### chassis Protocol Reference
Based on "chassis Upper Computer Communication Protocol" - JSON over WebSocket (rosbridge-like).

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

**Unlock:** Staff-only unlock mechanism (not documented for security reasons)

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
relay_app/app/src/main/java/com/chassis/robotrelay/
├── ui/
│   └── MainActivity.kt          # UI with joystick, tour mode, lock screen
├── service/
│   ├── RelayService.kt          # Foreground service, TTS, tour mode
│   ├── RelayServer.kt           # HTTP + WebSocket servers
│   ├── CommandBuffer.kt         # Sequence command execution
│   └── RobotWebSocketClient.kt  # Connection to robot base
├── protocol/
│   └── ChassisProtocol.kt         # Protocol message builders
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

## Navigation Recovery System

When navigation fails (status 604) or robot gets stuck, the CommandBuffer performs intelligent recovery:

### Recovery Sequence
1. **Detect Block** - LIDAR zone (STOP/CREEP), ultrasonic sensors, or nav failure (604)
2. **Cancel Nav** - Stop current navigation attempt
3. **Announce** - "Looking for an alternative path" (if enabled)
4. **Backup** - Reverse slowly (5cm/s tortoise speed) for ~3 seconds
5. **Spin Search** - Rotate to find clear direction (both LIDAR AND ultrasonic must be clear)
6. **Nudge Forward** - Move slightly into the clear space
7. **Retry Nav** - Re-issue navigation command
8. **Give Up** - After max attempts, play sad R2D2 sounds and ask for help

### Sensor Fusion
The recovery system uses multiple sensor inputs:

| Sensor | Topic | Detection |
|--------|-------|-----------|
| LIDAR | `/laser_data` | SafetyZone (STOP/CREEP/WARN/CLEAR) based on nearest obstacle |
| Ultrasonic | `/mobile_base/sensors/core` → `analog_input` | Cardboard, glass, soft objects LIDAR can't see |
| Odometry | `/robot_status` → `velocity` | Detect when pushing but not moving (invisible obstacle) |
| Bumper | `/mobile_base/sensors/core` → `bumper` | Physical contact detection |

### Smart Velocity
Raw velocity commands check actual vs commanded motion:
- If commanding motion but `velocity ≈ 0` for 3 consecutive checks (~600ms)
- Robot is blocked by something (glass window, heavy object)
- Stop pushing immediately - don't be stubborn

### Recovery Configuration
Configurable via `set_recovery_config` command from Flutter:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `stuckThresholdMs` | 15000 | Time stuck before recovery triggers |
| `maxRecoveryAttempts` | 3 | Retries before giving up |
| `backupSpeed` | 0.05 m/s | Reverse speed (tortoise - safe for wheelchairs) |
| `backupDurationMs` | 3000 | How long to reverse |
| `spinSpeed` | 0.3 rad/s | Rotation speed while searching |
| `nudgeSpeed` | 0.05 m/s | Forward nudge after finding clear |
| `nudgeDurationMs` | 2000 | How long to nudge |
| `announceRecovery` | true | TTS announcements during recovery |

### Failure Behavior
When all recovery attempts exhausted:
1. TTS: "I'm stuck. I need help please."
2. Play sad R2D2 sounds (descending woeful tones)
3. Complete command with `robot_failed` status

## Audio Announcements

The Flutter app uses TTS to announce:
- "Navigating to [waypoint]" - Nav status 601
- "Arrived at [waypoint]" - Nav status 603
- "Navigation cancelled" - Nav status 602
- "Navigation failed. Path blocked." - Nav status 604
- Low battery warnings at 20% and 10%

Toggle audio in joystick widget.

## Alert Sounds

Generated tones via AudioTrack (works on all devices):

| Sound | Pattern | Use Case |
|-------|---------|----------|
| `beep` | Single A5 (880Hz) | Attention |
| `horn` | A4→F4→D4 descending | Alarm/warning |
| `arrival` | A5→C6→A5 beep-boop | POI arrival |
| `delivery` | C5→E5→G5→C6 triumphant | Delivery complete |
| `sad` | A5→F5→C5→G4→E4→C4→A3 | Stuck/needs help (R2D2 whimper) |

## Cloud Fleet Management

### AWS Infrastructure
CloudFormation stack in `infrastructure/frontiertower-stack.yaml`:

| Resource | Purpose |
|----------|---------|
| API Gateway | HTTP API for tour sync, fleet status |
| Lambda | Request processing |
| DynamoDB | Tours, maps, floors, robots, commands, alerts |

### Tour Cloud Sync
Tours can sync to cloud for fleet-wide sharing:
1. Deploy CloudFormation stack
2. Get API endpoint from stack outputs
3. Enter URL in Cloud Sync dialog (Flutter app)
4. Push/Pull tours by map ID

### DynamoDB Tables
| Table | Key | Description |
|-------|-----|-------------|
| `frontiertower-tours-{env}` | `tour_id` | Tour sequences with stops, speak text, URLs |
| `frontiertower-maps-{env}` | `map_id` | SLAM maps, waypoints |
| `frontiertower-floors-{env}` | `floor_id` | Physical floors in buildings |
| `frontiertower-robots-{env}` | `robot_id` | Robot status, position, battery |
| `frontiertower-commands-{env}` | `robot_id + command_id` | Pending commands |
| `frontiertower-alerts-{env}` | `robot_id + timestamp` | Alerts, warnings |
| `frontiertower-fleet-config-{env}` | `config_key` | Fleet-wide settings |

## Future Development

### Planned Features
- Camera/microphone integration for video calling
- Multi-robot coordination
- Obstacle avoidance visualization on map
- Route planning interface
- IoT Core for real-time telemetry
