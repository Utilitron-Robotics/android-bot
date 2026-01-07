# Frontier Tower Fleet Management

A cross-platform robot control system for Pudu/smAiT service robots. Deployed at **Frontier Tower** for multi-floor tour guide and service operations.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    House WiFi Network                       │
│                                                             │
│   ┌─────────────┐           ┌───────────────────┐          │
│   │ Flutter App │ ←───────→ │  Android Tablet   │          │
│   │ (Controller)│ WebSocket │  (Relay Server)   │          │
│   └─────────────┘  :8766    │  HTTP :8765       │          │
│                              └─────────┬─────────┘          │
└──────────────────────────────────────────────────────────────┘
                                         │
                              ┌──────────┴──────────┐
                              │   Robot WiFi        │
                              │   10.42.0.1:9090    │
                              └──────────┬──────────┘
                                         │
                              ┌──────────┴──────────┐
                              │   Pudu/smAiT Robot  │
                              └─────────────────────┘
```

### Navigation Architecture
The system uses a strict state machine and centralized command management to ensure reliable navigation:

1.  **CommandManager Centralization**: All robot commands are routed through a central `CommandManager`. This handles:
    *   **Retry Logic**: Automatically retries failed commands (up to 3 times) before declaring failure.
    *   **State Tracking**: Maintains the source of truth for command execution status (pending, running, completed, failed).
    *   **Ack Verification**: Ensures commands are received by the robot/relay.

2.  **Strict State Machine**: Navigation logic enforces strict phase transitions (e.g., `idle` -> `navigating` -> `arrived`). Events are ignored if they don't match the current phase, preventing race conditions from stray messages.

3.  **Relay Buffer**: The Relay App acts as a command buffer. The Flutter app loads a sequence of commands (navigate, speak, wait) into the Relay's buffer. The Relay executes them sequentially and reports status. This decouples the real-time execution from the network connection, allowing the robot to continue a sequence even if the Flutter controller temporarily disconnects.

## Applications

### Flutter App - `flutter_app/`
Cross-platform controller with tour management and cloud sync.

- **Tour Mode**: Multi-stop guided tours with TTS narration
- **Cloud Sync**: Push/Pull tours & waypoints between robots
- **Crowd Logic**: Smart blocked-path announcements with venue presets
- **Voice Control**: Speech-to-waypoint navigation
- **Dynamic UI**: Auto-generated from robot capabilities

```bash
cd flutter_app
flutter pub get
flutter run -d macos  # or ios, android, chrome
```

### Relay App - `relay_app/`
Android tablet bridge mounted on robot. Provides:

- **Dual Network Bridge**: House WiFi ↔ Robot WiFi
- **Tour Display**: Customer-facing WebView with countdown timer
- **Lock Screen**: Prevents customer access during tours (6-tap + PIN unlock)
- **TTS Announcements**: Blocked path warnings, arrival notices
- **HTTP API**: REST endpoints for simple integration

```bash
cd relay_app
./gradlew assembleDebug
# Install: adb install app/build/outputs/apk/debug/app-debug.apk
```

### Infrastructure - `infrastructure/`
AWS CloudFormation stack for fleet management.

```bash
cd infrastructure
./deploy.sh dev  # or prod
```

## Key Features

### Tour Mode
Automated guided tours with:
- Start/End waypoints with intro/outro speech
- Per-stop: navigation, TTS, display URL, wait time
- Loop mode for continuous operation
- Motion trigger: greet visitors and show "Start Tour" button

### Cloud Sync
Share configurations across robots on the same floor:

| Button | Function |
|--------|----------|
| **WP↑** | Push waypoints to cloud |
| **WP↓** | Pull waypoints from cloud |
| **Tours↑** | Push tour sequences to cloud |
| **Tours↓** | Pull tours (replaces local) |

Set **Map ID** to floor name (e.g., "Spaceship", "Mezzanine") for cross-robot sync.

### Crowd Logic
Smart blocked-path announcements with escalating urgency:

| Venue | Style | Safe Dist | Ramp Rate | Use Case |
|-------|-------|-----------|-----------|----------|
| **Spaceship** | Friendly, audible | 4 ft | Gentle | Event floors, crowds |
| **Adult Party** | Faster escalation | 2.5 ft | Quick | Bars, clubs |
| **Restaurant** | Balanced | 3 ft | Moderate | Dining service |
| **Kids Event** | Patient, gentle | 5 ft | Very Gentle | Family events |
| **Hospital** | Quiet, minimal | 4 ft | Very Gentle | Healthcare |

Features LIDAR intelligence to distinguish moving obstacles (people) from static objects.

#### Speed Ramping
Configurable velocity reduction as robot approaches obstacles:

- **Safe Distance**: Distance (ft/in) where slowdown begins (1-10 ft range)
- **Ramp Rate**: How aggressively speed decreases (Gentle → Aggressive)
  - Gentle (0.1-0.4): Gradual slowdown, smooth deceleration
  - Aggressive (0.7-1.0): Quick stop, slows early

Settings sync to relay tablet for real-time velocity control in WARN zone.

### Navigation Recovery
Intelligent recovery when path is blocked or navigation fails (status 604):

1. **Detect** - LIDAR zone (STOP/CREEP), ultrasonic sensors, or nav failure
2. **Backup** - Reverse slowly (5cm/s tortoise speed) to create space
3. **Spin Search** - Rotate to find clear direction (LIDAR + ultrasonic must both be clear)
4. **Nudge Forward** - Move into the clear space
5. **Retry Nav** - Re-issue navigation command
6. **Give Up** - After max attempts, play sad R2D2 sounds and ask for help

Ultrasonic sensors detect obstacles LIDAR can't see (glass, cardboard, soft objects).

## Frontier Tower Floors

| Floor | Map ID | Description |
|-------|--------|-------------|
| Spaceship | `spaceship` | Event floor (2nd floor) |
| Lobby | `lobby` | Ground floor |
| Mezzanine | `mezzanine` | Between floors |
| Rooftop | `rooftop` | Top floor events |

## Robot Configuration

| Robot | SSID | Password | Direct IP |
|-------|------|----------|-----------|
| Tibo 1 | TY126AA003F0-005878 | 123456789 | 10.42.0.1:9090 |
| Tibo 2 | TY126AA003F0-005993 | 123456789 | 10.42.0.1:9090 |

### Sensors

| Sensor | Topic | Data |
|--------|-------|------|
| LIDAR | `/laser_data` | Point cloud for SafetyZone (STOP/CREEP/WARN/CLEAR) |
| Ultrasonic | `/mobile_base/sensors/core` → `analog_input` | Distance (mm) - sees glass, cardboard |
| Battery | `/robot_status` → `battery` | Charge percentage |

### Speed Modes (Native Base)

| Mode | Name | Description |
|------|------|-------------|
| 0-2 | Safety Low/Med/High | Cautious, large stop distance |
| 3-5 | Balance Low/Med/High | Balanced speed/safety |
| 6-8 | Efficiency Low/Med/High | Speed focused |
| 60 | Smooth | Food delivery (no sudden stops) |

## Project Structure

```
.
├── flutter_app/                 # Cross-platform controller
│   ├── lib/
│   │   ├── core/               # Connection, sequences, cloud client
│   │   ├── services/           # Audio announcer, introspection
│   │   ├── screens/            # HUD, home screen
│   │   └── widgets/            # Sequence editor, crowd logic settings
│   └── pubspec.yaml
│
├── relay_app/                   # Android tablet relay
│   └── app/src/main/java/com/smait/robotrelay/
│       ├── service/            # Relay server, command buffer, WebSocket
│       ├── protocol/           # smAiT protocol messages
│       ├── ui/                 # MainActivity with tour mode
│       └── cloud/              # AWS IoT client (future)
│
├── infrastructure/              # AWS CloudFormation
│   ├── frontiertower-stack.yaml
│   └── deploy.sh
│
└── CLAUDE.md                    # Development documentation
```

## Development

See [CLAUDE.md](CLAUDE.md) for detailed protocol documentation, navigation status codes, and development notes.

### Quick Test
```bash
# Test robot connection
nc -z -w 3 10.42.0.1 9090 && echo "ROBOT ONLINE"

# Test relay API
curl http://tablet-ip:8765/status
```

## Security Note

Uses cleartext WebSocket (`ws://`) for local robot communication. For internet-exposed deployments, implement `wss://` with proper certificates.
