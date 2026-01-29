# Obstacle Avoidance & Safety Zone System

## Overview

The robot control system implements a multi-layered obstacle avoidance architecture spanning both the **Relay App** (Android tablet) and **Flutter App** (control UI). This document describes the current implementation, data flow, and known issues.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                       FLUTTER APP (Control UI)                       │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                    JOYSTICK WIDGET                           │    │
│  │  • User moves joystick → target velocity                     │    │
│  │  • SLAM Safe mode: limits velocity based on obstacle dist    │    │
│  │  • Ramping: smooth acceleration/deceleration                 │    │
│  └──────────────────────────┬──────────────────────────────────┘    │
│                             │ sendVelocity(linear, angular)          │
│                             ▼                                        │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │              UNIFIED TRANSPORT MANAGER                       │    │
│  │  • Routes via WebRTC (lowest latency) or gRPC (reliable)    │    │
│  │  • Predictive control smoothing (optional)                  │    │
│  └──────────────────────────┬──────────────────────────────────┘    │
└──────────────────────────────┼───────────────────────────────────────┘
                               │ gRPC/WebRTC
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      RELAY APP (Android Tablet)                      │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │              gRPC RobotControlServiceImpl                    │    │
│  │  • Receives velocity command                                 │    │
│  │  • Calls robotClient.sendVelocity()                         │    │
│  └──────────────────────────┬──────────────────────────────────┘    │
│                             │                                        │
│                             ▼                                        │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │              RobotWebSocketClient.sendVelocity()             │    │
│  │                                                              │    │
│  │  ┌─────────────────────────────────────────────────────┐    │    │
│  │  │           SAFETY ZONE CHECK (ALWAYS ACTIVE)          │    │    │
│  │  │                                                      │    │    │
│  │  │  if (safetyZone == STOP && linearX > 0):            │    │    │
│  │  │      adjustedLinear = 0.0  // BLOCKED               │    │    │
│  │  │  else if (safetyZone == CREEP && linearX > 0.05):   │    │    │
│  │  │      adjustedLinear = 0.05  // LIMITED              │    │    │
│  │  │  else:                                               │    │    │
│  │  │      // WARN or CLEAR - no adjustment               │    │    │
│  │  └─────────────────────────────────────────────────────┘    │    │
│  │                             │                                │    │
│  │                             ▼                                │    │
│  │            ChassisProtocol.publishVelocity()                │    │
│  └──────────────────────────┬──────────────────────────────────┘    │
│                             │                                        │
└──────────────────────────────┼───────────────────────────────────────┘
                               │ rosbridge WebSocket
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        ROBOT BASE (ROS)                              │
│  /cmd_vel_mux/input/teleop → motor controllers                      │
└─────────────────────────────────────────────────────────────────────┘
```

## Safety Zones

### Zone Definitions

| Zone   | Distance (front arc) | Behavior |
|--------|---------------------|----------|
| **STOP**  | < 0.20 m | Forward velocity blocked (set to 0) |
| **CREEP** | < 0.50 m | Forward velocity limited to 0.05 m/s |
| **WARN**  | < 0.80 m | No velocity limitation |
| **CLEAR** | ≥ 0.80 m | No velocity limitation |

**Note**: Backward velocity (negative linear) is NEVER blocked - the robot can always back up.

### Zone Detection Logic

**File**: `relay_app/.../RobotWebSocketClient.kt:399-423`

```kotlin
private fun checkLaserData(points: List<Float>) {
    if (points.isEmpty()) return  // ⚠️ No update if LIDAR empty!

    // Front arc: 40-60% of LIDAR scan (center ~60 degrees)
    val frontStartIndex = (points.size * 0.4).toInt()
    val frontEndIndex = (points.size * 0.6).toInt()
    val frontPoints = points.subList(frontStartIndex, frontEndIndex)
    val minFront = frontPoints.minOrNull() ?: Float.MAX_VALUE

    val newZone = when {
        minFront < STOP_DISTANCE -> SafetyZone.STOP
        minFront < CREEP_DISTANCE -> SafetyZone.CREEP
        minFront < WARN_DISTANCE -> SafetyZone.WARN
        else -> SafetyZone.CLEAR
    }

    if (newZone == SafetyZone.STOP) {
        stop()  // Auto-stop on STOP zone entry
    }
}
```

### Additional Safety Triggers

**Bumper/Cliff Sensors** (File: `RobotWebSocketClient.kt:331-341`):
- Bumper or cliff detection → SafetyZone.STOP + auto-stop
- **Exception**: During charger docking (waypoint contains "Pile", "Charger", or "Dock")

## Obstacle Classifier (Crowd Management)

**File**: `relay_app/.../ObstacleClassifier.kt` (589 lines)

The ObstacleClassifier provides intelligent obstacle identification:

### Obstacle Types

| Type | Description | Robot Response |
|------|-------------|----------------|
| `MOVING_PERSON` | Single moving human | Wait patiently |
| `CROWD` | Multiple moving entities | Announce "please make way" |
| `STATIC_UNEXPECTED` | Object not on map | Request help |
| `STATIC_EXPECTED` | Wall/mapped obstacle | Reroute |
| `STATIC_PERSON` | Stationary human | Wait, then speak |
| `UNKNOWN` | Can't determine | Time-based escalation |

### Detection Method

1. **Scan History**: Stores 10 recent LIDAR scans
2. **Movement Detection**: Compares current vs. previous scans
3. **Map Integration**: Checks occupancy grid for known obstacles
4. **Path Corridor**: Uses `/global_path` topic (0.6m corridor width)
5. **Cluster Analysis**: Groups LIDAR points into obstacle clusters

### Status Update

```kotlin
obstacleClassifier = ObstacleClassifier { classification ->
    _robotStatus.value = current.copy(
        obstacleInPath = classification.inPath,
        obstacleMoving = classification.isMoving,
        obstacleType = classification.type.name
    )
}
```

## Recovery Logic (When Robot Gets Stuck)

**File**: `relay_app/.../CommandBuffer.kt:489-600`

### Recovery Trigger Conditions

```kotlin
val isBlocked = safetyZone == SafetyZone.STOP || safetyZone == SafetyZone.CREEP
val shouldRecover = triggerRecovery || (stuckTime > 15000ms && isBlocked)
```

Recovery triggers when:
1. **Nav Failed (604)**: Navigation returns failure status
2. **Stuck Timer**: Robot hasn't progressed for 15+ seconds AND is in STOP/CREEP zone

### Recovery Sequence

```
1. BACK UP
   └─ smartVelocity(-0.05, 0.0, backupDurationMs)
   └─ Negative velocity bypasses STOP zone blocking

2. SPIN TO FIND CLEAR
   └─ Rotate at spinSpeed (rad/s)
   └─ After 90°, start checking for CLEAR/WARN zone
   └─ Stop when clear direction found (or full 360°)

3. NUDGE FORWARD (if clear found)
   └─ smartVelocity(0.05, 0.0, nudgeDurationMs)
   └─ ⚠️ May be blocked if zone changed back to STOP!

4. RETRY NAVIGATION
   └─ robotClient.navigateToPoi(waypoint)
```

### Smart Velocity Function

```kotlin
suspend fun smartVelocity(linear: Double, angular: Double, maxMs: Long): Boolean {
    var blockedCount = 0
    while (elapsed < maxMs) {
        robotClient.sendVelocity(linear, angular)
        delay(200)

        // Check if actually moving
        if (commandedMotion && !actuallyMoving) {
            blockedCount++
            if (blockedCount >= 3) {
                // Pushed 3 times, not moving - stop trying
                return false
            }
        }
    }
    return true
}
```

### Recovery Configuration

```kotlin
data class RecoveryConfig(
    val stuckThresholdMs: Long = 15000L,      // Time stuck before recovery
    val maxRecoveryAttempts: Int = 3,         // Max attempts before giving up
    val backupDurationMs: Long = 2000L,       // How long to back up
    val backupSpeed: Double = 0.05,           // Backup velocity m/s
    val spinSpeed: Double = 0.3,              // Spin velocity rad/s
    val nudgeDurationMs: Long = 1500L,        // How long to nudge forward
    val nudgeSpeed: Double = 0.05,            // Nudge velocity m/s
    val announceRecovery: Boolean = true      // TTS during recovery
)
```

## Flutter App Obstacle Handling

### SLAM Safe Mode

**File**: `flutter_app/.../joystick.dart:547-590`

When `_slamSafe` is enabled in the joystick:

```dart
if (_slamSafe && targetLinear > 0) {
    final dist = _minFrontRange;

    if (dist < stopDistance) {        // < 0.20m
        targetLinear = 0;             // Full stop
    } else if (dist < creepDistance) { // < 0.50m
        // Graduated creep: slower as closer
        targetLinear = targetLinear.clamp(-maxCreep, maxCreep);
    } else if (dist < warnDistance) {  // < 0.80m
        targetLinear = targetLinear.clamp(-maxSpeed/2, maxSpeed/2);
    }
}
```

### LIDAR Gauge Data Source

The joystick's LIDAR gauge now receives safety zone data from gRPC (commit `2602471`):

```dart
void _subscribeToGrpcStatus() {
    transport.robotStatus.listen((status) {
        final safetyZone = status['safety_zone'] as String?;
        // Convert zone to approximate distance for display
        switch (safetyZone.toUpperCase()) {
            case 'STOP':  distance = 0.15; break;
            case 'CREEP': distance = 0.35; break;
            case 'WARN':  distance = 0.65; break;
            default:      distance = double.infinity;
        }
    });
}
```

**Previous behavior** (before commit): Subscribed directly to `/laser_data` topic.

## Known Issues & Potential Causes of "Stuck" Robot

### 1. Recovery Nudge Blocked by Safety Zone

**Symptom**: Robot backs up, spins, finds clear direction, but can't nudge forward.

**Cause**: `sendVelocity()` applies safety zone filtering to ALL velocity commands, including recovery nudge. If the zone changed back to STOP between finding clear and nudging, forward motion is blocked.

**Evidence** (CommandBuffer.kt:529, RobotWebSocketClient.kt:447):
```kotlin
// In smartVelocity - calls sendVelocity
robotClient.sendVelocity(linear, angular)

// In sendVelocity - blocks forward motion in STOP zone
if (safetyZone.get() == SafetyZone.STOP && linearX > 0) {
    adjustedLinear = 0.0  // BLOCKED!
}
```

### 2. Empty LIDAR Data

**Symptom**: Safety zone stuck at last value (could be STOP).

**Cause**: `checkLaserData()` returns early if points list is empty:
```kotlin
if (points.isEmpty()) return  // Safety zone not updated!
```

### 3. Race Condition in Recovery

**Symptom**: Intermittent recovery failures.

**Cause**: LIDAR updates asynchronously. Between `foundClear = true` and `smartVelocity(nudgeSpeed, ...)`, a new LIDAR scan may detect obstacle in the "clear" direction.

### 4. Bumper/Cliff False Positives

**Symptom**: Robot stops unexpectedly even when path is clear.

**Cause**: Bumper or cliff sensor triggered → SafetyZone.STOP forced.

**Exception exists** for charger docking but not for other scenarios.

### 5. Double Safety Filtering

**Symptom**: Robot moves slower than expected or not at all.

**Cause**: Both Flutter (SLAM safe) AND Relay (always) filter velocity:
- Flutter SLAM safe: limits based on `/scan` or gRPC safety_zone
- Relay: limits based on internal safetyZone state

## Implemented Fixes

### Fix 1: Recovery Bypass in sendVelocity ✅ IMPLEMENTED

**File**: `relay_app/.../RobotWebSocketClient.kt`

```kotlin
fun sendVelocity(linearX: Double, angularZ: Double, bypassSafety: Boolean = false) {
    var adjustedLinear = linearX
    if (!bypassSafety) {
        when (safetyZone.get()) {
            SafetyZone.STOP -> if (linearX > 0) adjustedLinear = 0.0
            SafetyZone.CREEP -> if (linearX > CREEP_SPEED) adjustedLinear = CREEP_SPEED
            else -> { }
        }
    }
    send(ChassisProtocol.publishVelocity(adjustedLinear, angularZ))
}
```

Recovery nudge now uses `bypassSafety = true` in `CommandBuffer.kt`.

### Fix 2: LIDAR Safety Zone Timeout ✅ IMPLEMENTED

**File**: `relay_app/.../RobotWebSocketClient.kt`

```kotlin
private const val LIDAR_TIMEOUT_MS = 3000L
private var lastLidarUpdateTime = 0L

fun checkLidarTimeout() {
    if (lastLidarUpdateTime == 0L) return
    val elapsed = System.currentTimeMillis() - lastLidarUpdateTime
    if (elapsed > LIDAR_TIMEOUT_MS) {
        safetyZone.set(SafetyZone.CLEAR)
        Log.w(TAG, "LIDAR timeout - safety zone reset to CLEAR")
    }
}
```

Called from gRPC heartbeat in `RobotControlServiceImpl.kt`.

### Fix 3: Dual Transport Conflict ✅ IMPLEMENTED

**Problem**: Both gRPC and WebSocket subscribed to robot status, causing duplicate processing.

**Fix**: `RobotConnection.connectWithDisplayUrl()` now accepts `capabilityOnly: true`:
- When true, skips `/robot_status` subscription (gRPC handles status)
- WebSocket only used for capability discovery (waypoints)

**File**: `flutter_app/lib/core/robot_connection.dart`

### Fix 4: Flutter/Relay Recovery Race ✅ IMPLEMENTED

**Problem**: Both Flutter CommandManager AND Relay CommandBuffer tried to recover from nav failures (604).

**Fix**: `SequenceTaskMode.relayHandlesRecovery` flag:
- When true (gRPC mode), Flutter does NOT retry navigate commands on 604/602
- Relay handles recovery (backup/spin/nudge/retry)
- Prevents racing between two recovery systems

**Files**:
- `flutter_app/lib/core/sequence_task_mode.dart`
- `flutter_app/lib/core/sequence_mode.dart`

### Fix 5: LIDAR Gauge Dual Subscription ✅ IMPLEMENTED

**Problem**: Joystick widget subscribed to BOTH gRPC safety_zone AND raw `/scan` topic, causing gauge to jump between values.

**Fix**: Platform-specific subscription in `initState()`:
- **Web**: Subscribe to raw `/scan` via WebSocket (no gRPC available)
- **Native**: Subscribe to gRPC safety_zone only (single source of truth)

**File**: `flutter_app/lib/widgets/joystick.dart`

### Proposed Fix: Atomic Recovery Nudge

Capture safety zone BEFORE spinning, verify still valid:
```kotlin
val clearedZone = robotClient.robotStatus.value?.safetyZone
if (clearedZone == SafetyZone.CLEAR || clearedZone == SafetyZone.WARN) {
    // Nudge with short timeout, verify zone still clear
    smartVelocity(nudgeSpeed, 0.0, nudgeDurationMs, requireZone = clearedZone)
}
```

## Key Files Reference

| File | Purpose |
|------|---------|
| `relay_app/.../RobotWebSocketClient.kt` | LIDAR processing, safety zones, velocity blocking |
| `relay_app/.../ObstacleClassifier.kt` | Intelligent obstacle classification |
| `relay_app/.../CommandBuffer.kt` | Navigation, recovery logic |
| `relay_app/.../RobotControlServiceImpl.kt` | gRPC service, status streaming |
| `flutter_app/.../joystick.dart` | Joystick UI, SLAM safe mode |
| `flutter_app/.../unified_transport.dart` | Transport layer, status aggregation |
| `proto/robot_control.proto` | gRPC protocol definition |

## Data Flow Summary

```
LIDAR Scan
    │
    ▼
RobotWebSocketClient.checkLaserData()
    │
    ├──► SafetyZone enum (STOP/CREEP/WARN/CLEAR)
    │
    ├──► ObstacleClassifier.processLidarScan()
    │        │
    │        ▼
    │    ObstacleClassification (type, inPath, moving)
    │
    ▼
RobotStatusData (combined state)
    │
    ├──► gRPC stream to Flutter (safety_zone, obstacle info)
    │
    └──► CommandBuffer recovery logic (isBlocked check)

Velocity Command (from Flutter)
    │
    ▼
RobotControlServiceImpl (gRPC)
    │
    ▼
RobotWebSocketClient.sendVelocity()
    │
    ├── IF STOP zone AND forward: BLOCK
    ├── IF CREEP zone AND forward > 0.05: LIMIT
    │
    ▼
ChassisProtocol.publishVelocity()
    │
    ▼
Robot Base (ROS)
```
