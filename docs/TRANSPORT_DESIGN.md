# Transport Layer Design

## Problem Statement

Current implementation has gRPC, WebRTC, MQTT, WebSocket, and HTTP intertwined in a single `UnifiedTransportManager`. This causes:

1. **Platform confusion** - gRPC doesn't work on web (no raw sockets), but code tries to use it everywhere
2. **Responsibility blur** - WebSocket handles both rosbridge protocol AND acts as gRPC fallback
3. **Quirky WebSocket** - No proper heartbeat, reconnection with backoff, or message buffering

## Alan's Requirements

- gRPC for **heartbeat only** with WAN capability (teleop stacks need this)
- WebSocket needs a **reliable wrapper** (it's quirky and unreliable by nature)
- **Transport buddy** - paired transports that complement each other
- **Platform separation** - web vs native have different capabilities

---

## Research Findings

### WebSocket Reliability Patterns

From [Ably best practices](https://ably.com/topic/websocket-architecture-best-practices) and [websocket-heartbeat-js](https://github.com/zimv/websocket-heartbeat-js):

| Problem | Solution |
|---------|----------|
| Silent disconnection | Application-level heartbeat (ping/pong every 20-30s) |
| Network drop | Reconnection with exponential backoff + jitter |
| Message loss | Message queue with persistence until ACK |
| Burst overload | Backpressure management, rate limiting |
| State desync | Sequence numbers, resync on reconnect |

**Key insight**: WebSocket doesn't inherently offer message persistence. If client disconnects, data in transit is lost unless custom recovery is implemented.

### gRPC + WebRTC Hybrid (Industry Standard)

From [Viam's architecture](https://www.viam.com/post/real-time-robot-control-grpc-webrtc) and [gRPC robotics blog](https://grpc.io/blog/robotics/):

```
┌─────────────────────────────────────────────────────────┐
│                    ROBOT CONTROL                         │
├─────────────────────────────────────────────────────────┤
│                                                          │
│   gRPC (HTTP/2)              WebRTC (P2P)               │
│   ├── Structured RPCs        ├── Low-latency streaming  │
│   ├── Reliable delivery      ├── Video/sensor data      │
│   ├── TLS built-in           ├── NAT traversal          │
│   ├── Auto-gen clients       └── Unreliable but fast    │
│   └── WAN-ready                                         │
│                                                          │
│   Use for:                   Use for:                   │
│   - Heartbeat/health         - Velocity commands        │
│   - Navigation commands      - Telemetry streaming      │
│   - Configuration            - Video feed               │
│   - Authentication           - Map data                 │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

**Protocol switching**: "If robot operates in stable network with precision tasks, use gRPC. If entering area with latency risk, transition to WebRTC." - [Cogniteam](https://www.cogniteam.com/resources/blogs/cloud-based-teleoperation-in-robotics-2/)

### Message Queue as Buffer

From [Medium article on MQ vs WebSocket](https://medium.com/@chisomokafor038/understanding-message-queues-and-websockets-architecting-reliable-real-time-and-asynchronous-cb93e1e774f5):

> "Message queues store messages until consumer confirms processing. This durability protects against data loss if receiving component fails or is temporarily offline."

**Pattern**: WebSocket for real-time + Message Queue for durability = best of both worlds.

---

## Proposed Architecture

### Two Platform Targets

```
┌─────────────────────────────────────────────────────────┐
│                    PLATFORM: NATIVE                      │
│                    (macOS, iOS, Android)                 │
├─────────────────────────────────────────────────────────┤
│                                                          │
│   PRIMARY: gRPC                                         │
│   ├── Heartbeat/health monitoring                       │
│   ├── Command delivery (reliable)                       │
│   ├── Status streaming                                  │
│   └── WAN-ready, TLS built-in                           │
│                                                          │
│   BUDDY: WebRTC                                         │
│   ├── Low-latency velocity (when < 100ms needed)        │
│   ├── Video streaming                                   │
│   ├── Map data streaming                                │
│   └── Uses gRPC for signaling                           │
│                                                          │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│                    PLATFORM: WEB                         │
│                    (Chrome, Firefox, Safari)             │
├─────────────────────────────────────────────────────────┤
│                                                          │
│   PRIMARY: ReliableWebSocket (wrapped)                  │
│   ├── Heartbeat (app-level ping/pong)                   │
│   ├── Auto-reconnect (exp backoff + jitter)             │
│   ├── Message buffer (queue until ACK)                  │
│   ├── Sequence tracking (detect gaps)                   │
│   └── Circuit breaker (prevent storm)                   │
│                                                          │
│   BUDDY: WebRTC                                         │
│   ├── Low-latency velocity                              │
│   ├── Video streaming                                   │
│   └── Uses WebSocket for signaling                      │
│                                                          │
│   FALLBACK: HTTP polling                                │
│   └── Last resort when WS fails repeatedly              │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### ReliableWebSocket Wrapper

The "good wrapper" for quirky WebSocket:

```dart
class ReliableWebSocket {
  // Connection management
  - autoReconnect: bool
  - maxReconnectAttempts: int
  - reconnectBackoff: ExponentialBackoff (with jitter)

  // Heartbeat
  - heartbeatInterval: Duration (default 20s)
  - heartbeatTimeout: Duration (default 20s)
  - onHeartbeatMissed: callback

  // Message reliability
  - outboundQueue: PersistentQueue<Message>
  - inboundSequence: int (track gaps)
  - pendingAcks: Map<id, Message>
  - retryUnacked: bool

  // Circuit breaker
  - failureThreshold: int
  - resetTimeout: Duration
  - state: closed | open | half-open

  // Quality metrics
  - latencyHistory: CircularBuffer<Duration>
  - packetLoss: double
  - jitter: double
}
```

### Transport Buddy Pattern

```
┌─────────────────────────────────────────────────────────┐
│                  TRANSPORT BUDDY                         │
├─────────────────────────────────────────────────────────┤
│                                                          │
│   "Transport buddy" = paired transports that             │
│   complement each other's weaknesses                     │
│                                                          │
│   NATIVE BUDDY PAIR:                                    │
│   ┌──────────┐     ┌──────────┐                         │
│   │   gRPC   │◄───►│  WebRTC  │                         │
│   │ reliable │     │   fast   │                         │
│   └──────────┘     └──────────┘                         │
│        │                 │                               │
│        │   gRPC does     │   WebRTC does                │
│        │   signaling     │   data channels              │
│        │                 │                               │
│                                                          │
│   WEB BUDDY PAIR:                                       │
│   ┌──────────┐     ┌──────────┐                         │
│   │ Reliable │◄───►│  WebRTC  │                         │
│   │    WS    │     │   fast   │                         │
│   └──────────┘     └──────────┘                         │
│        │                 │                               │
│        │   WS does       │   WebRTC does                │
│        │   signaling +   │   data channels              │
│        │   commands      │                               │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

### Command Routing

```
COMMAND TYPE          NATIVE ROUTE        WEB ROUTE
─────────────────────────────────────────────────────
emergency_stop        gRPC + WebRTC       WS + WebRTC (both!)
navigate              gRPC                WS
velocity (< 100ms)    WebRTC              WebRTC
velocity (fallback)   gRPC                WS
status_subscribe      gRPC stream         WS
video                 WebRTC              WebRTC
map_data              WebRTC              WebRTC
heartbeat             gRPC                WS (app-level)
```

---

## File Structure (Proposed)

```
flutter_app/lib/core/
├── transport/
│   ├── transport_interface.dart      # Abstract interface
│   ├── transport_buddy.dart          # Buddy pairing logic
│   │
│   ├── native/                       # Native platform
│   │   ├── grpc_transport.dart       # gRPC implementation
│   │   └── native_buddy.dart         # gRPC + WebRTC pair
│   │
│   ├── web/                          # Web platform
│   │   ├── reliable_websocket.dart   # The good wrapper
│   │   └── web_buddy.dart            # WS + WebRTC pair
│   │
│   └── shared/                       # Cross-platform
│       ├── webrtc_transport.dart     # WebRTC (works everywhere)
│       ├── message_buffer.dart       # Persistent queue
│       └── circuit_breaker.dart      # Failure management
│
├── robot_connection.dart             # Uses TransportBuddy
└── unified_transport.dart            # DEPRECATED or thin wrapper
```

---

## Current State (What Exists)

### WebRTC Already Implemented

Found in `webrtc_transport.dart`:
- **gRPC for signaling** (SDP offer/answer, ICE candidates)
- **WebRTC data channel** `map_data_channel` for receiving map data
- **`sendVelocity()`** for low-latency teleoperation commands
- This IS the transport buddy pattern!

```
gRPC (signaling)
    │
    └──► WebRTC
            ├── map_data_channel (receive compressed OccupancyGrid)
            └── sendVelocity() (send velocity commands)
```

### Duplicate Code

| File | Lines | Notes |
|------|-------|-------|
| `webrtc_transport.dart` | 239 | Full implementation, note says "being replaced" |
| `webrtc_map_client.dart` | 133 | Nearly identical subset |

These should be **consolidated**.

### Contradiction with Docs

`TRANSPORT_ARCHITECTURE.md` says:
> ❌ WebRTC for commands (only for video if needed later)

But actual code DOES use WebRTC for velocity commands. Docs are stale.

---

## Questions for Discussion

1. **Message persistence**: Local storage (Hive/SQLite) or in-memory only?
2. **Heartbeat ownership**: Should gRPC heartbeat also monitor WebRTC health?
3. **Sequence tracking**: Full sequence numbers or just "last seen" timestamp?
4. **Platform detection**: Compile-time (`kIsWeb`) or runtime capability probe?
5. **WebRTC consolidation**: Keep `webrtc_transport.dart`, delete `webrtc_map_client.dart`?

---

## Sources

- [Ably WebSocket Best Practices](https://ably.com/topic/websocket-architecture-best-practices)
- [websocket-heartbeat-js](https://github.com/zimv/websocket-heartbeat-js)
- [Viam: Real-time robot control](https://www.viam.com/post/real-time-robot-control-grpc-webrtc)
- [gRPC Robotics Blog](https://grpc.io/blog/robotics/)
- [Cogniteam: Cloud Teleoperation](https://www.cogniteam.com/resources/blogs/cloud-based-teleoperation-in-robotics-2/)
- [WebSocket vs Message Queue](https://medium.com/@chisomokafor038/understanding-message-queues-and-websockets-architecting-reliable-real-time-and-asynchronous-cb93e1e774f5)
