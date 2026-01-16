# Transport Architecture

## Current Problem
The transport layer is overcomplicated with gRPC, WebRTC, MQTT, WebSocket, and HTTP all mixed together,
but the actual connection still goes through `RobotConnection` which uses `RosbridgeClient` (WebSocket).
The `GrpcRobotClient` exists but is disconnected from the main connection flow.

## Simplified Architecture

### Platform Detection
```
kIsWeb == true  → Chrome/Browser → WebSocket ONLY
kIsWeb == false → Native (macOS, iOS, Android) → gRPC ONLY
```

### Connection Modes

#### Chrome/Web (WebSocket)
- **Transport**: WebSocket to relay tablet
- **URL Format**: `ws://{relay_ip}:8766`
- **Why**: gRPC doesn't work in browsers (no raw socket access)
- **Example**: `ws://192.168.88.39:8766`

#### Native Apps (gRPC)
- **Transport**: gRPC to relay tablet
- **URL Format**: `grpc://{relay_ip}:50051`
- **Why**: Binary protocol, reliable, bidirectional streaming
- **Example**: `grpc://192.168.88.37:50051`

### No More:
- ❌ HTTP fallback (unnecessary complexity)
- ❌ WebRTC for commands (only for video if needed later)
- ❌ MQTT (not used)
- ❌ Direct robot connection (always through relay tablet)
- ❌ Mixing transports

### Configuration

User enters ONE IP address for the relay tablet. The app automatically:
1. Detects platform (web vs native)
2. Uses correct transport (WebSocket vs gRPC)
3. Uses correct port (8766 vs 50051)

```dart
// User enters: 192.168.88.37

// Chrome → ws://192.168.88.37:8766
// macOS  → grpc://192.168.88.37:50051
```

### Files to Modify

1. **`hud_screen.dart`**: Remove ConnectionMode enum complexity, just use relay IP
2. **`robot_connection.dart`**: Platform-aware connection logic
3. **`unified_transport.dart`**: Simplify or remove
4. **`dual_connection.dart`**: Remove (redundant)
5. **`fleet_picker.dart`**: Single IP input, no mode confusion

### Data Flow

```
┌─────────────────────────────────────────────────────────┐
│                     FLUTTER APP                          │
│                                                          │
│   ┌─────────────────────────────────────────────────┐   │
│   │           SimpleRobotTransport                   │   │
│   │  - Platform detection (kIsWeb)                   │   │
│   │  - Single IP configuration                       │   │
│   │  - Auto port selection                           │   │
│   └─────────────┬───────────────────────────────────┘   │
│                 │                                        │
│     ┌───────────┴───────────┐                           │
│     │                       │                           │
│     ▼                       ▼                           │
│ ┌──────────┐         ┌────────────┐                     │
│ │ WebSocket│         │   gRPC     │                     │
│ │ :8766    │         │   :50051   │                     │
│ │ (Chrome) │         │  (Native)  │                     │
│ └────┬─────┘         └─────┬──────┘                     │
│      │                     │                            │
└──────┼─────────────────────┼────────────────────────────┘
       │                     │
       └──────────┬──────────┘
                  │
                  ▼
       ┌──────────────────────┐
       │   RELAY TABLET       │
       │   (Android App)      │
       │                      │
       │  gRPC Server :50051  │
       │  WS Server   :8766   │
       │  HTTP Server :8765   │
       └──────────┬───────────┘
                  │
                  │ USB/Wired
                  ▼
       ┌──────────────────────┐
       │     ROBOT (ROS)      │
       │  rosbridge :9090     │
       └──────────────────────┘
```

### Implementation Steps

1. Create `SimpleRobotTransport` class with clean interface
2. Use `kIsWeb` for platform detection
3. Remove all hardcoded IPs - single configurable relay IP
4. Simplify HUD screen - just relay IP input
5. Remove unused transport code
