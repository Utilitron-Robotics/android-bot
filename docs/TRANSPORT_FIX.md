# Transport Layer Fix Plan

## Problem Summary

Two communication systems are incorrectly intertwined:
1. **gRPC** - works on native (macOS, iOS, Android), has heartbeat + WAN capability
2. **WebSocket** - works everywhere including web, needed for browser

Current code mixes them in `RobotConnection` with a confusing `capabilityOnly` flag.

## Goals

1. **Separate by platform** - web uses WebSocket, native uses gRPC
2. **Remove duplicates** - `webrtc_map_client.dart` duplicates `webrtc_transport.dart`
3. **Keep transport buddy pattern** - gRPC+WebRTC for native, WebSocket+WebRTC for web
4. **Preserve WebRTC for map streaming** - already works well

## Files to Change

### DELETE (duplicate)
- `flutter_app/lib/services/webrtc_map_client.dart` - duplicate of `webrtc_transport.dart`

### CREATE (platform separation)
- `flutter_app/lib/core/platform_transport.dart` - clean interface + platform detection

### MODIFY
- `flutter_app/lib/core/robot_connection.dart` - use new `PlatformTransport`
- `flutter_app/lib/screens/hud_screen.dart` - simplify connection logic

### KEEP AS-IS (already good)
- `flutter_app/lib/core/grpc_client.dart` - solid reliability, has WebRTC signaling
- `flutter_app/lib/core/rosbridge_client.dart` - WebSocket with reconnect
- `flutter_app/lib/core/webrtc_transport.dart` - uses gRPC for signaling

---

## Step 1: Delete Duplicate

```bash
rm flutter_app/lib/services/webrtc_map_client.dart
```

Verify no imports reference it.

---

## Step 2: Create Platform Transport

Create `flutter_app/lib/core/platform_transport.dart`:

```dart
/// Platform-aware transport layer
///
/// Web (kIsWeb=true): WebSocket + WebRTC
/// Native (kIsWeb=false): gRPC + WebRTC
///
/// Transport Buddy Pattern:
/// - Primary transport handles: commands, status, heartbeat
/// - WebRTC handles: map streaming, low-latency velocity (optional)
```

Key interface:
```dart
abstract class PlatformTransport {
  bool get isConnected;
  Stream<bool> get connectionState;
  Stream<RobotStatusData> get statusStream;

  Future<void> connect(String host);
  Future<void> disconnect();

  void sendVelocity(double linear, double angular);
  Future<void> navigate(String waypoint);
  void stop();
  void cancelNavigation();

  // WebRTC buddy
  WebRtcTransport? get webrtc;
  Stream<OccupancyGrid> get mapStream;
}
```

Two implementations:
- `NativeTransport` - wraps `GrpcRobotClient`
- `WebTransport` - wraps `RosbridgeClient`

Factory:
```dart
PlatformTransport createTransport() {
  if (kIsWeb) {
    return WebTransport();
  } else {
    return NativeTransport();
  }
}
```

---

## Step 3: Update RobotConnection

Remove `capabilityOnly` flag and `RosbridgeClient` direct usage.

Before:
```dart
class RobotConnection {
  final RosbridgeClient _client = RosbridgeClient();
  // ... mixed WebSocket and gRPC logic
}
```

After:
```dart
class RobotConnection {
  late final PlatformTransport _transport;

  RobotConnection() {
    _transport = createTransport();
  }
  // ... delegates to _transport
}
```

---

## Step 4: Test

### Web Test
```bash
cd flutter_app
flutter run -d chrome
```

Expected:
- Connects via WebSocket (port 8766)
- Map loads via WebRTC
- Joystick sends velocity
- Status updates flow

### Native Test (if available)
```bash
cd flutter_app
flutter run -d macos
```

Expected:
- Connects via gRPC (port 50051)
- Map loads via WebRTC (signaling over gRPC)
- Heartbeat keeps connection alive
- Status updates flow

---

## Verification Checklist

- [ ] `webrtc_map_client.dart` deleted
- [ ] No broken imports
- [ ] `platform_transport.dart` created
- [ ] `RobotConnection` uses `PlatformTransport`
- [ ] Web connects via WebSocket
- [ ] Native connects via gRPC
- [ ] WebRTC map works on both
- [ ] No `capabilityOnly` flag

---

## Rollback

If something breaks:
```bash
git checkout -- flutter_app/lib/
```

All changes are in flutter_app, relay_app unchanged.
