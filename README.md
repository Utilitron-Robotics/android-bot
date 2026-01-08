# RoboTour Pro

**Enterprise-grade autonomous tour and service robot management platform**

[![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)]()
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android%20%7C%20Web%20%7C%20macOS-lightgrey.svg)]()
[![Protocol](https://img.shields.io/badge/protocol-gRPC%20%7C%20WebSocket-green.svg)]()
[![License](https://img.shields.io/badge/license-MIT-orange.svg)]()

## Overview

RoboTour Pro is a comprehensive fleet management system for autonomous service robots. Built for Pudu, smAiT, and compatible platforms using the rosbridge protocol, it enables sophisticated tour operations, delivery services, and remote robot control across multiple venues.

### Key Features

- 🤖 **Universal Compatibility** - Works with any rosbridge-compatible robot
- 🌐 **WAN-Ready Architecture** - gRPC protocol for reliable internet-scale operation
- 🎯 **Smart Navigation** - Automatic path recovery with obstacle avoidance
- 🗣️ **Dynamic Tours** - Multi-stop tours with TTS narration and media display
- ☁️ **Cloud Fleet Management** - AWS-powered multi-robot coordination
- 📱 **Cross-Platform Control** - Flutter apps for iOS, Android, Web, and Desktop

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    INTERNET / WAN                           │
│                                                             │
│   Flutter Apps          Cloud               Android Relay   │
│   ┌──────────┐         ┌──────┐            ┌──────────┐   │
│   │Controller│ ←gRPC→  │ AWS  │  ←gRPC→    │  Tablet  │   │
│   └──────────┘ :443    │ IoT  │   :50051   │  Bridge  │   │
│                        └──────┘             └────┬─────┘   │
└─────────────────────────────────────────────────│──────────┘
                                                   │
                                        WebSocket  │ :9090
                                                   ▼
                                          ┌──────────────┐
                                          │ Robot Base   │
                                          │ Controller   │
                                          └──────────────┘
```

## Components

### 1. Flutter Control App (`flutter_app/`)
Universal controller with adaptive UI based on robot capabilities.

**Features:**
- Dynamic UI generation from robot introspection
- Tour creation and management
- Real-time status monitoring
- Voice command support
- Cloud synchronization

**Supported Platforms:**
- iOS 12.0+
- Android 7.0+ (API 24)
- Web (Chrome, Safari, Firefox)
- macOS 10.14+
- Windows (coming soon)
- Linux (coming soon)

### 2. Android Relay Bridge (`relay_app/`)
Tablet-based bridge providing WAN connectivity and customer interaction.

**Features:**
- gRPC server (port 50051) for WAN communication
- WebSocket relay to robot base
- Customer-facing tour display
- Command buffering for reliability
- TTS announcements
- Recovery logic for navigation failures

**Requirements:**
- Android 7.0+ (API 24)
- Tablet with 10"+ screen recommended

### 3. Cloud Infrastructure (`infrastructure/`)
AWS-based fleet management and tour synchronization.

**Services:**
- API Gateway for REST endpoints
- Lambda functions for business logic
- DynamoDB for tours, maps, and waypoints
- IoT Core for real-time telemetry (planned)

## Quick Start

### 1. Deploy Cloud Infrastructure (Optional)
```bash
cd infrastructure
aws cloudformation deploy \
  --template-file frontiertower-stack.yaml \
  --stack-name robotour-stack \
  --capabilities CAPABILITY_NAMED_IAM
```

### 2. Install Android Relay on Tablet
```bash
cd relay_app
./gradlew assembleDebug
adb install app/build/outputs/apk/debug/app-debug.apk
```

### 3. Run Flutter Controller
```bash
cd flutter_app
flutter pub get
flutter run -d [platform]  # ios, android, chrome, macos
```

### 4. Connect to Robot
1. Connect tablet to robot via USB or robot WiFi
2. Start relay service on tablet
3. Enter tablet IP in Flutter app
4. Begin controlling robot!

## Tour Management

### Creating Tours
Tours consist of waypoints with:
- **Navigation targets** - POI names the robot knows
- **Narration scripts** - Text-to-speech at each stop
- **Media display** - URLs for tablet display
- **Wait timings** - Dwell time at each location

### Tour Execution
1. Load tour from cloud or create locally
2. Robot navigates to each waypoint sequentially
3. At each stop:
   - Display media on tablet
   - Play arrival sound
   - Announce narration
   - Wait specified duration
4. Return to start or end position

### Recovery Behavior
When navigation fails:
1. Announce "Looking for alternative path"
2. Backup slowly (5cm/s)
3. Rotate to find clear direction
4. Attempt alternate route
5. After 3 failures: Request human assistance

## Protocol Support

### Primary: gRPC (WAN-Ready)
- Binary protobuf encoding (15x smaller than JSON)
- Built-in keepalive (HTTP/2 PING)
- Automatic reconnection
- Bidirectional streaming

### Legacy: WebSocket (LAN)
- JSON rosbridge protocol
- Direct robot connection
- Real-time telemetry
- Map visualization

## Development

### Requirements
- Flutter 3.0+
- Android Studio 2023.1+ (for relay app)
- Python 3.8+ (for cloud deployment)
- protoc 3.20+ (for gRPC generation)

### Building from Source

**Flutter App:**
```bash
cd flutter_app
flutter pub get
flutter build [ios|android|web|macos]
```

**Android Relay:**
```bash
cd relay_app
./gradlew build
```

**Generate Protobuf:**
```bash
cd flutter_app
./generate_protos.sh

cd relay_app
./gradlew generateProto
```

## Configuration

### Robot Connection
Default IPs can be modified in:
- Flutter: `lib/core/robot_connection.dart`
- Relay: `res/values/strings.xml`

### Tour Scripts
Place narration scripts in:
- Cloud: DynamoDB `tours` table
- Local: `assets/tour_scripts/`

### Recovery Settings
Adjust in `RecoveryConfig`:
- Stuck threshold: 15s
- Max attempts: 3
- Backup speed: 0.05 m/s
- Spin speed: 0.3 rad/s

## API Reference

### REST Endpoints
```
GET  /tours              - List all tours
POST /tours              - Create tour
PUT  /tours/{id}         - Update tour
GET  /maps/{id}/waypoints - Get waypoints for map
POST /fleet/commands     - Send command to robot
```

### gRPC Services
```protobuf
service RobotControl {
  rpc ControlStream(stream ClientMessage) returns (stream ServerMessage);
  rpc SendCommand(Command) returns (CommandResponse);
}
```

## Deployment Scenarios

### Single Robot (Local)
- Tablet connected via USB to robot
- Flutter app on same WiFi network
- No cloud required

### Multi-Robot Facility
- Each robot has dedicated tablet
- Central Flutter controller
- Cloud sync for shared tours

### Remote Management
- Robots anywhere with internet
- Control from anywhere
- Full telemetry and monitoring

## Troubleshooting

### Connection Issues
- Verify tablet and controller on same network
- Check firewall allows ports 50051 (gRPC) and 8766 (WebSocket)
- Ensure robot WiFi credentials are correct

### Navigation Problems
- Confirm waypoints exist in robot's map
- Check battery level > 20%
- Verify no emergency stop active

### Tour Issues
- Validate all waypoint names match robot POIs
- Ensure TTS language matches script language
- Check tablet volume for announcements

## Contributing

Contributions welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Support

- Documentation: [docs/](docs/)
- Issues: [GitHub Issues](https://github.com/yourusername/robotour-pro/issues)
- Email: support@robotour.pro

---

**RoboTour Pro** - *Making robots work for you, not the other way around*