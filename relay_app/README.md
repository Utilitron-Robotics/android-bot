# Relay App - The Robot Bridge

The Relay App is the critical middleware that runs on the robot's Android tablet, bridging the gap between modern network protocols (gRPC) and the robot's internal ROS-based systems.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    FLUTTER CONTROL APP                          │
│                  (iOS/Android/Web/Desktop)                      │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                    gRPC (port 50051)
                    WebSocket (port 8766)
                    HTTP REST (port 8765)
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                      RELAY APP (This)                           │
│                   Android Tablet on Robot                       │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │  GrpcServer  │  │ RelayServer  │  │DiscoveryServ │          │
│  │  (50051)     │  │ (WS:8766)    │  │  (UDP:9999)  │          │
│  │              │  │ (HTTP:8765)  │  │              │          │
│  └──────┬───────┘  └──────┬───────┘  └──────────────┘          │
│         │                 │                                     │
│         └────────┬────────┘                                     │
│                  ▼                                              │
│  ┌──────────────────────────────────────────────────┐          │
│  │              RELAY SERVICE                        │          │
│  │  - Command routing & buffering                   │          │
│  │  - TTS (Cloud + Device fallback)                 │          │
│  │  - Task execution (SPEAK, DISPLAY, DELIVER)      │          │
│  │  - Fleet sync (AWS API Gateway)                  │          │
│  └──────────────────────┬───────────────────────────┘          │
│                         │                                       │
│  ┌──────────────────────▼───────────────────────────┐          │
│  │          RobotWebSocketClient                     │          │
│  │    rosbridge protocol → Robot base               │          │
│  └──────────────────────┬───────────────────────────┘          │
└─────────────────────────┼───────────────────────────────────────┘
                          │
                   USB/Wired Connection
                   192.168.20.22:9090
                          │
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│                    ROBOT BASE (ROS)                             │
│              rosbridge WebSocket server                         │
└─────────────────────────────────────────────────────────────────┘
```

## Key Components

| Component | File | Purpose |
|-----------|------|---------|
| **RelayService** | `RelayService.kt` | Main foreground service orchestrator |
| **GrpcServer** | `GrpcServer.kt` | gRPC server for WAN-ready control |
| **RobotControlServiceImpl** | `RobotControlServiceImpl.kt` | gRPC service implementation |
| **RelayServer** | `RelayServer.kt` | HTTP + WebSocket server for apps |
| **RobotWebSocketClient** | `RobotWebSocketClient.kt` | rosbridge WebSocket to robot |
| **CommandBuffer** | `CommandBuffer.kt` | Task queue & execution buffer |
| **CloudTtsService** | `CloudTtsService.kt` | Google Cloud TTS |
| **DiscoveryService** | `DiscoveryService.kt` | UDP broadcast for app discovery |
| **FleetApiClient** | `FleetApiClient.kt` | AWS fleet management API |

## Communication Protocols

### gRPC (Primary - WAN Ready)
- **Port:** 50051
- **Protocol:** HTTP/2 with Protobuf
- **Features:**
  - Bidirectional streaming via `ControlStream()` RPC
  - Built-in keepalive (PING/PONG every 10s)
  - Command acknowledgment & result streaming
  - Buffer control (pause/resume/skip/clear)

### WebSocket (LAN Legacy)
- **Port:** 8766
- **Protocol:** JSON over WebSocket
- **Use:** Local WiFi Flutter apps

### HTTP REST (Fallback)
- **Port:** 8765
- **Protocol:** JSON REST
- **Use:** Cloud-based remote access

## Configuration

### Robot IP (Wired Connection)
The tablet connects to the robot via a **wired USB connection**. The default IP is `192.168.20.22:9090`.

To change, set via SharedPreferences key `robot_ip` or pass via Intent extra:
```kotlin
intent.putExtra("robot_ip", "192.168.x.x")
```

### Ports
| Port | Protocol | Purpose |
|------|----------|---------|
| 50051 | gRPC | Primary command channel |
| 8765 | HTTP | REST API fallback |
| 8766 | WebSocket | LAN legacy support |
| 9999 | UDP | Discovery broadcast |
| 9090 | WebSocket | Robot rosbridge (outgoing) |

## Building

```bash
cd relay_app
./gradlew assembleDebug
```

### Dependencies
- **Android SDK:** compileSdk 34, minSdk 24, targetSdk 34
- **Kotlin:** 1.9.20
- **gRPC:** io.grpc:grpc-okhttp:1.60.0
- **Protobuf:** 3.25.1 (lite mode)
- **OkHttp:** 4.12.0

## Running

1. Install on tablet attached to robot
2. Grant required permissions (foreground service, network)
3. App auto-starts RelayService on launch
4. Service maintains connection to robot and listens for control commands

## Debugging

### Logs
All components use Android's Log class with tags:
- `RelayService`
- `GrpcServer`
- `RelayServer`
- `RobotWebSocketClient`
- `CommandBuffer`

Filter with: `adb logcat | grep -E "Relay|Grpc|Robot"`

### Health Check
HTTP endpoint: `GET http://<tablet-ip>:8765/status`

Returns:
```json
{
  "connected": true,
  "robot_id": "robot-1",
  "battery": 85,
  "nav_status": 600,
  "uptime_ms": 123456
}
```

## Important Notes

1. **The tablet is WIRED to the robot** - It does not use the robot's WiFi hotspot
2. **RelayService runs as foreground service** - Prevents Android from killing it
3. **Cloud TTS falls back to device TTS** - If Google Cloud TTS fails
4. **Fleet sync every 30 seconds** - Pushes status to AWS
5. **Obstacle announcements have cooldowns** - 5s for same-type, 3s for any
