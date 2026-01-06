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

| Venue | Style | Use Case |
|-------|-------|----------|
| **Spaceship** | Friendly, audible | Event floors, crowds |
| **Adult Party** | Faster escalation | Bars, clubs |
| **Restaurant** | Balanced | Dining service |
| **Kids Event** | Patient, gentle | Family events |
| **Hospital** | Quiet, minimal | Healthcare |

Features LIDAR intelligence to distinguish moving obstacles (people) from static objects.

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
