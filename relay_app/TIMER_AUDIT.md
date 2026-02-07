# Relay App Timer & Fake Logic Audit

**Date**: 2026-02-07
**Scope**: All 21 Kotlin source files in `relay_app/app/src/main/java/com/utilitron/robotrelay/`
**Purpose**: Catalog all hardcoded timers, timeouts, arbitrary delays, magic numbers, polling loops, and logic shortcuts that substitute for proper event-driven or computed behavior.

---

## Severity Legend

- **CRITICAL**: Blocking sleep or delay that directly impacts responsiveness or masks a real bug
- **HIGH**: Arbitrary delay/timeout used where an event-driven approach should exist
- **MEDIUM**: Hardcoded magic number that should be configurable or computed
- **LOW**: Reasonable default that could benefit from centralization but isn't harmful

---

## 1. CommandBuffer.kt (~1178 lines) — MOST AFFECTED

The command execution engine is the worst offender. Nearly every operation uses polling loops with arbitrary delays instead of event-driven callbacks.

### CRITICAL

| Line(s) | Code | Issue |
|---------|------|-------|
| Execution loop | `delay(100)` | Generic poll interval used as the main execution loop tick. Every command waits in 100ms increments. Should be event-driven (Flow/Channel). |
| Pause wait | `delay(100)` | Polls `isPaused` flag every 100ms instead of using a suspend/resume mechanism (Mutex, Condition, or Flow). |
| Nav wait loop | `delay(100)` | Polls nav status every 100ms instead of collecting a StateFlow of nav status changes. |
| Recovery velocity | `delay(200)` | Sends velocity commands in a loop with 200ms sleep. Should use robot's command acknowledgment or a timer-based publisher. |
| After recovery | `delay(300)` | Arbitrary wait "for robot to settle" after recovery before retrying nav. No sensor confirmation. |

### HIGH

| Line(s) | Code | Issue |
|---------|------|-------|
| Nav status 602 | `3000` ms grace period | Ignores "cancelled" status for 3 seconds after sending a nav goal, assuming it's a stale status from the previous goal. This is a workaround for not tracking goal IDs. |
| Arrival confirm | `500L` / `300L` | Hardcoded wait times after arrival status before confirming. Should confirm via actual robot stopped + at-waypoint check. |
| Nav timeout | `120000L` (2 min) | Default navigation timeout. Not computed from distance/speed. A waypoint 1m away gets the same timeout as one 50m away. |
| Greeting cooldown | `30_000L` (30s) | Hardcoded cooldown between greeting detections. Not adaptive to environment. |
| Sensor stabilize | `1_500L` (1.5s) | Initial delay "for sensors to stabilize" before starting commands. No actual sensor readiness check. |
| Smart velocity check | `delay(400)` | Interval for checking if velocity command is still needed. Arbitrary. |
| TTS wait polling | `delay(250)` | Polls TTS completion every 250ms instead of using a completion callback. |
| Button standby poll | `delay(500)` | Polls for button presses every 500ms instead of event-driven. |

### MEDIUM

| Item | Value | Issue |
|------|-------|-------|
| RecoveryConfig defaults | Various durations | Backup/spin/nudge durations and speeds are hardcoded defaults in a data class. Should be derived from robot kinematics or configurable per-robot. |

---

## 2. RelayService.kt (~1235 lines)

The foreground service orchestrator has multiple timing hacks, especially around audio/TTS and obstacle announcements.

### CRITICAL

| Line(s) | Code | Issue |
|---------|------|-------|
| Tone generation | `Thread.sleep(durationMs.toLong() + 50)` | **Blocking the thread** with Thread.sleep on a coroutine context. The `+ 50` is a magic buffer "to ensure AudioTrack finishes." Should use AudioTrack's completion callback or a non-blocking approach. |
| Tone gap | `delay(100)` and `delay(30)` | Arbitrary gaps between generated tones. |

### HIGH

| Line(s) | Code | Issue |
|---------|------|-------|
| Obstacle announce cooldown | `OBSTACLE_ANNOUNCE_COOLDOWN = 5000L` | Global cooldown between obstacle announcements. Not adaptive to speed or situation. |
| Min announce interval | `3000L` | Minimum between ANY obstacle announcement regardless of type. |
| Fleet sync interval | `delay(30_000)` | Hardcoded 30-second fleet sync loop. Should be configurable or event-driven (sync on state change). |
| Emergency alarm cycle | `delay(3200)` | Siren loop timing. Coupled to audio file duration assumption. |
| Alarm TTS timeout | `withTimeoutOrNull(5000)` | 5-second timeout for TTS during alarm. Arbitrary. |
| Alarm siren restart | `delay(300)` | Gap before siren restart. Arbitrary. |
| Safety zone cooldowns | `3000L` (WARN), `2000L` (CREEP) | Hardcoded cooldowns before re-announcing safety zone changes. Not adapted to robot speed or zone transition rate. |
| TTS precache rate | `delay(500)` | Rate limit between precache operations. Arbitrary. |

---

## 3. RobotWebSocketClient.kt (~995 lines)

Core robot connection has several timing hacks around connection setup and data processing.

### HIGH

| Line(s) | Code | Issue |
|---------|------|-------|
| Post-connect delay | `delay(500)` | Waits 500ms after WebSocket `onOpen` before setting up ROS subscriptions. Comment says "wait for connection to stabilize." Should verify connection readiness via a handshake or first message receipt. |
| Reconnect delay | `RECONNECT_DELAY_MS = 1000L` | Fixed 1-second reconnect delay. Note says "Reduced from 3000ms." AdaptiveConnectionPolicy exists but this constant overrides it in some paths. |
| Map refresh unsub wait | `delay(300)` | Waits 300ms after unsubscribing from map topic before resubscribing. Assumes server needs time to process unsubscribe. |
| Map refresh retry | `delay(2000)` x2 | Two 2-second waits in map refresh retry logic. Arbitrary. |
| Sketchy periodic log | `System.currentTimeMillis() % 2000 < 100` | Uses modular arithmetic on current time to log approximately every 2 seconds. This is a hack — should use a counter or throttle utility. |
| LIDAR people stale | `2000` ms | Threshold for considering LIDAR-based people detection data stale. Magic number, not derived from sensor update rate. |

### MEDIUM

| Item | Value | Issue |
|------|-------|-------|
| Safety distances | `STOP=0.20f, CREEP=0.50f, WARN=0.80f` | Hardcoded safety zone thresholds in meters. Should be configurable per-robot (different robots have different stopping distances). |

---

## 4. RelayServer.kt (~995 lines)

HTTP/WebSocket relay server has timing issues around reconnection and liveness monitoring.

### HIGH

| Line(s) | Code | Issue |
|---------|------|-------|
| Post-reconnect delay | `delay(1000)` | Waits 1 second after robot reconnects before restarting message forwarder. "Let connection stabilize." No actual readiness check. |
| Liveness heartbeat | `delay(10_000)` | Liveness monitor checks every 10 seconds. |
| No-message warning | `30_000` ms | Warns if no messages received in 30 seconds. Threshold is arbitrary. |
| Forwarder restart delay | `delay(100)` | Comment: "Reduced from 500ms." Still arbitrary. |

### MEDIUM

| Item | Value | Issue |
|------|-------|-------|
| Ping interval | `PING_INTERVAL_MS = 10_000L` | WebSocket ping every 10 seconds. Reasonable but hardcoded. |
| Socket timeout | `60000` ms | NanoWSD socket timeout. Hardcoded. |

---

## 5. GrpcServer.kt (~123 lines)

### MEDIUM

| Item | Value | Issue |
|------|-------|-------|
| Keepalive time | `KEEPALIVE_TIME_MS = 10_000L` | gRPC keepalive ping interval. Standard but hardcoded. |
| Keepalive timeout | `KEEPALIVE_TIMEOUT_MS = 5_000L` | Timeout waiting for keepalive response. |
| Max connection idle | `MAX_CONNECTION_IDLE_MS = 300_000L` (5 min) | Auto-close idle connections. |
| Max connection age | `MAX_CONNECTION_AGE_MS = 3_600_000L` (1 hr) | Force reconnect after 1 hour. |
| Health monitor | `delay(30_000)` | Server health check every 30 seconds. |

---

## 6. RobotControlServiceImpl.kt (~364 lines)

### HIGH

| Line(s) | Code | Issue |
|---------|------|-------|
| Stream stabilize delay | `STREAM_STABILIZE_DELAY_MS = 100L` | Delay before starting gRPC stream data. "Let stream stabilize." No actual stream readiness check. |
| LIDAR staleness | `3000` ms | LIDAR data considered stale after 3 seconds. Magic number not derived from actual scan rate. |

### MEDIUM

| Item | Value | Issue |
|------|-------|-------|
| Heartbeat interval | `HEARTBEAT_INTERVAL_MS = 1000L` | 1-second heartbeat to clients. Reasonable but hardcoded. |
| CrowdConfig defaults | safe_distance=1.5m, ramp_rate=0.2 | Hardcoded in `buildHeartbeat()`. Should come from robot config. |

---

## 7. MainActivity.kt (~883 lines)

### HIGH

| Line(s) | Code | Issue |
|---------|------|-------|
| IP refresh delay | `delay(2000)` | Waits 2 seconds after gRPC server starts to refresh IP display. Assumes server is ready by then. Should use a callback. |
| Service rebind retry | `delay(1000)` | Retries service binding after 1 second on failure. |

### MEDIUM

| Item | Value | Issue |
|------|-------|-------|
| Tap reset timeout | `tapResetTimeMs = 2000L` | Lock screen tap sequence resets after 2 seconds. |
| Wake lock timeout | `wl.acquire(5000)` | Holds wake lock for 5 seconds. |

---

## 8. AwsIotClient.kt (~415 lines)

### HIGH

| Line(s) | Code | Issue |
|---------|------|-------|
| Status report interval | `delay(5000)` | Reports robot status to cloud every 5 seconds in a loop. Should be event-driven (report on change) with a max interval. |
| Command poll interval | `delay(2000)` | Polls for cloud commands every 2 seconds. Should use push notification or long-polling. |

### MEDIUM

| Item | Value | Issue |
|------|-------|-------|
| HTTP timeouts | `connectTimeout = 10000, readTimeout = 10000` | 10-second HTTP timeouts. Reasonable but hardcoded. |

---

## 9. CloudTtsService.kt (~377 lines)

### MEDIUM

| Item | Value | Issue |
|------|-------|-------|
| Connect timeout | `10` seconds | HTTP connect timeout for TTS API. |
| Read timeout | `30` seconds | HTTP read timeout for TTS API. |
| Precache rate limit | `delay(500)` | 500ms between precache requests. |
| Cache age | `MAX_CACHE_AGE_DAYS = 30` | TTS cache files expire after 30 days. |
| Cache size | `MAX_CACHE_SIZE_MB = 50` | Max TTS cache size. |

---

## 10. Heartbeat.kt (~276 lines)

### LOW

| Item | Value | Issue |
|------|-------|-------|
| Interval sanity check | `actualInterval < 10000` | Ignores intervals over 10 seconds for rhythm learning. Reasonable guard. |
| EMA weights | `0.9 / 0.1` | Exponential moving average weights for rhythm adaptation. Could be configurable. |

---

## 11. ChassisProtocol.kt (~456 lines)

### MEDIUM

| Item | Value | Issue |
|------|-------|-------|
| Throttle rates | `150, 200, 500, 1000, 5000` ms | Different throttle rates for different ROS topic subscriptions. These control how often the relay receives updates. Hardcoded per-topic. |

---

## 12. ObstacleClassifier.kt (~599 lines)

### MEDIUM

| Item | Value | Issue |
|------|-------|-------|
| Stopped velocity threshold | `0.05` | Below this = stopped. |
| Movement threshold | `0.10` | Above this = moving. |
| Point match threshold | Various | Scan-to-scan point matching distance. |
| Scan history size | `10` | Number of scans retained for classification. |

---

## 13. PeopleTracker.kt (~203 lines)

### MEDIUM

| Item | Value | Issue |
|------|-------|-------|
| Max missing frames | `50` (~10s at 5Hz) | Tracks lost after 50 missed frames. Assumes 5Hz input but doesn't verify. |
| Association distance | `1.5` m | Max distance to associate detection with existing track. |
| Smoothing alpha | `0.3` | Position smoothing factor. |
| Velocity alpha | `0.2` | Velocity estimation smoothing factor. |
| dt sanity check | `dt < 2.0` | Ignores updates with >2 second gaps. |

---

## 14. DepthPeopleDetector.kt (~200 lines)

### MEDIUM

| Item | Value | Issue |
|------|-------|-------|
| Min process interval | `MIN_PROCESS_INTERVAL_MS = 100` | Rate limits depth processing to 10Hz max. |
| Detection arena bounds | Various | Hardcoded spatial bounds for detection region. |
| Clustering parameters | Various | DBSCAN-style clustering thresholds. |

---

## 15. AdaptiveConnectionPolicy.kt (~300 lines)

### LOW

This file is actually well-designed — uses SharedPreferences for runtime configurability. Defaults are reasonable.

| Item | Value | Issue |
|------|-------|-------|
| Base delay | `2000L` ms | Default base retry delay. Configurable via prefs. |
| Max delay | `60000L` ms | Default max retry delay. Configurable via prefs. |
| Reliability thresholds | `0.95, 0.80, 0.50, 0.20` | Hardcoded breakpoints for reliability classification. |

---

## 16. Minor Files (Few/No Issues)

- **DiscoveryService.kt** — Clean. UDP discovery protocol with no timing hacks.
- **WebRtcManager.kt** — Minimal timing issues.
- **FleetManager.kt** — Delegates to FleetApiClient. No direct timing.
- **FleetApiClient.kt** — HTTP client with standard timeouts.
- **JoystickView.kt** — UI component. No timing issues.
- **RelayServiceImpl.kt** — 13-line interface. Clean.

---

## Summary by Severity

| Severity | Count | Primary Pattern |
|----------|-------|-----------------|
| CRITICAL | 7 | Thread.sleep, polling loops as main execution mechanism |
| HIGH | 25 | Arbitrary delays substituting for event-driven logic |
| MEDIUM | 30+ | Hardcoded magic numbers that should be configurable |
| LOW | 5 | Reasonable defaults that could be centralized |

## Top Patterns to Fix

### Pattern 1: Polling Loops Instead of Event-Driven (CRITICAL)
**Files**: CommandBuffer.kt, RelayService.kt
**Issue**: Core execution loop uses `while(true) { delay(100) }` pattern to poll state changes. This adds up to 100ms latency on every state transition and wastes CPU cycles.
**Fix**: Replace with Flow collection, Channel receives, or Mutex/Condition-based suspend points.

### Pattern 2: Arbitrary "Stabilization" Delays (HIGH)
**Files**: RobotWebSocketClient.kt, RelayServer.kt, RobotControlServiceImpl.kt, MainActivity.kt
**Issue**: `delay(500)` / `delay(1000)` / `delay(2000)` scattered throughout with comments like "wait for connection to stabilize" or "let stream settle." These mask race conditions instead of fixing them.
**Fix**: Use proper readiness signals — first message received, handshake complete, state flow emission.

### Pattern 3: Hardcoded Timeouts Not Derived from Context (HIGH)
**Files**: CommandBuffer.kt, RelayService.kt, AwsIotClient.kt
**Issue**: Navigation timeout is flat 2 minutes regardless of distance. Obstacle cooldowns don't adapt to speed. Cloud polling doesn't respond to activity.
**Fix**: Compute timeouts from context (distance/speed for nav, robot velocity for cooldowns) or make configurable via AdaptiveConnectionPolicy-style SharedPreferences.

### Pattern 4: Magic Numbers Scattered Across Files (MEDIUM)
**Files**: All
**Issue**: Safety distances, throttle rates, smoothing factors, staleness thresholds — all hardcoded as local constants in individual files with no central configuration.
**Fix**: Centralize into a `RobotConfig` object or SharedPreferences (following AdaptiveConnectionPolicy's pattern, which already does this well).

### Pattern 5: Modular Time Hack for Logging (HIGH)
**Files**: RobotWebSocketClient.kt
**Issue**: `System.currentTimeMillis() % 2000 < 100` used to throttle logging. This is unreliable (depends on when the code runs relative to the clock) and obfuscates intent.
**Fix**: Use a simple counter, `System.currentTimeMillis()` comparison with a last-logged timestamp, or a logging throttle utility.

---

## Recommended Fix Order

1. **CommandBuffer polling loops** — Highest impact on responsiveness and reliability
2. **"Stabilization" delays** — Remove race conditions properly
3. **Thread.sleep in RelayService** — Blocking coroutine thread is a correctness bug
4. **Centralize magic numbers** — Create RobotConfig for all tunable parameters
5. **Replace cloud polling with event-driven** — AwsIotClient status/command loops
6. **Compute context-aware timeouts** — Nav timeout from distance, cooldowns from speed
7. **Fix modular time logging hack** — Simple cleanup
