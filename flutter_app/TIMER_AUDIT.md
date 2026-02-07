# Flutter App — Timer & Timing Audit

**Date**: 2026-02-07
**Scope**: All 54 Dart source files in `flutter_app/lib/` (excluding 4 generated protobuf files)
**Directive**: Only heartbeat "is this missing?" checks may use hardcoded intervals. Everything else should be driven by task completion or signals.

---

## Good News: TransportConfig Already Centralizes Most Timers

`transport_config.dart` is a centralized, configurable, SharedPreferences-backed config for nearly all timing parameters. It adapts to network conditions (LAN/WAN/SATELLITE) and persists settings. This is the right pattern — the relay should follow it.

---

## Category 1: Heartbeat / Liveness (ALLOWED)

| File | Timer | Value | Status |
|------|-------|-------|--------|
| `heartbeat.dart:119` | Drummer periodic | Configurable interval | Correct — Drummer/Messenger pattern |
| `heartbeat.dart:193` | Messenger stale check | 500ms adaptive | Correct — learns rhythm via EMA |
| `buffer_client.dart:474` | Drummer to relay | 1s (configurable) | Correct — heartbeat |
| `buffer_client.dart:539` | Messenger expected interval | 500ms default, adapts | Correct — SINC-style rhythm |
| `grpc_client.dart:279` | gRPC heartbeat | `config.keepaliveInterval` | Correct — from TransportConfig |
| `rosbridge_client.dart:206` | WS ping | 15s | Correct — keepalive |
| `unified_transport.dart:662` | Health check | 10s | Correct — liveness |
| `status_panel.dart:21` | Stale data check | 1s | Correct — UI "is data missing?" |
| `mqtt_transport.dart:381` | MQTT keepalive | From config | Correct — protocol keepalive |
| `transport_config.dart:352` | RTT measurement | 5s | Correct — network quality measurement |

## Category 2: Velocity Commands (REQUIRED — protocol)

| File | Timer | Value | Status |
|------|-------|-------|--------|
| `joystick.dart:408` | Velocity send rate | 100ms | Correct — chassis protocol continuous commands |
| `dual_connection.dart:187` | Velocity send rate | 100ms | Correct — same |
| `adaptive_transport.dart:421` | Velocity queue flush | 100ms | Correct — same |
| `joystick.dart:434,454` | Ramp-down steps | 100ms | Correct — smooth decel for safety |

## Category 3: UI Animations (REQUIRED — visual feedback)

| File | Timer | Value | What |
|------|-------|-------|------|
| `hud_screen.dart:114,119,124` | Panel animations | 200ms | AnimatedContainer transitions |
| `hud_screen.dart:555,621,630,673` | Various UI animations | 200ms | Layout transitions |
| `hud_screen.dart:1728,1885` | Panel animations | 200ms | Layout transitions |
| `hud_screen.dart:2596` | Tab switch animation | 800ms | Tab transition |
| `message_log.dart:45` | Scroll animation | 100ms | Auto-scroll to new messages |
| `start_tour_overlay.dart:33` | Overlay fade-in | 1500ms | Tour start animation |
| `tablet_control_panel.dart:44` | SnackBar duration | 2s | UI notification display |

## Category 4: Transport Timeouts (REQUIRED — safety caps)

| File | Timer | Value | Status |
|------|-------|-------|--------|
| `transport_config.dart:43` | gRPC connection timeout | 10s | From config |
| `transport_config.dart:55` | WS connection timeout | 30s | From config |
| `transport_config.dart:65` | HTTP request timeout | 10s | From config |
| `grpc_client.dart:130` | Test command timeout | 5s | Safety cap on connectivity test |
| `robot_transport.dart:155,372` | Connect timeout | 10s | Safety cap |
| `robot_transport.dart:208,434` | Command timeout | From command | Configurable per-command |
| `robot_transport.dart:282,477` | Status poll timeout | 5s | Safety cap on HTTP poll |
| `robot_introspection.dart:105-186` | ROS service call timeouts | 5s each | Safety cap on rosapi calls |
| `fleet_config.dart:279,287` | Fleet API timeouts | 10s | Safety cap on HTTP |
| `fleet_cloud.dart:190,210,421,440` | Cloud API timeouts | 10s | Safety cap on HTTP |
| `fleet_discovery.dart:163` | gRPC channel ready | 3s | Safety cap on connection |
| `dual_connection.dart:120` | gRPC channel ready | 10s | Safety cap on connection |
| `sequence_mode.dart:805,1004,1063` | Buffer command timeouts | 10s | Safety cap on relay response |
| `buffer_client.dart:690` | Command acknowledgement | 10s | Safety cap |
| `map_view.dart:184,235,313` | HTTP poll timeouts | 500ms | Safety cap on LIDAR/people/depth fetch |
| `map_view.dart:502` | Map poll timeout | 10s | Safety cap on map fetch |
| `joystick.dart:132,154` | Safety zone timeouts | 3s | Safety cap on crowd config fetch |
| `fleet_picker.dart:372` | HTTP probe timeout | 300ms | Fast discovery probe |
| `rosbridge_client.dart:382` | Service call timeout | 10s default | Safety cap |

## Category 5: Reconnection (REQUIRED — backoff)

| File | Timer | Value | Status |
|------|-------|-------|--------|
| `grpc_client.dart:299-313` | Reconnect with backoff | 1s-60s exponential | Correct — adaptive |
| `rosbridge_client.dart:180-190` | Reconnect with backoff | 1s-30s exponential | Correct — adaptive |
| `dual_connection.dart:303` | Reconnect timer | 3s | Fixed — should use backoff |
| `transport_config.dart:48-49` | Reconnect bounds | 1s-60s | Configurable |

## Category 6: Task/Sequence Durations (REQUIRED — content IS the timing)

| File | Timer | Value | What |
|------|-------|-------|------|
| `sequence_task_mode.dart:160` | Countdown display | 1s periodic | Shows countdown timer — 1Hz IS the tick rate |
| `sequence_task_mode.dart:543` | Wait step timer | From config | User-configured wait at waypoint |
| `sequence_mode.dart:575` | Countdown display | 1s periodic | Same |
| `sequence_mode.dart:1475` | Wait step timer | From config | User-configured wait |
| `task_engine.dart:712,724` | Wait step timer | From config | User-configured wait |
| `waypoint_grid.dart:61` | Manual nav wait | From config | Display duration at waypoint |

## Category 7: Polling Where Push Is Unavailable (ACCEPTABLE — no signal)

| File | Timer | Value | Status |
|------|-------|-------|--------|
| `robot_transport.dart:275,471` | HTTP status poll | 2s | No WebSocket on HTTP transport — polling IS the mechanism |
| `robot_transport.dart:302` | Stale check | 1s | "Is data missing?" |
| `fleet_config.dart:89` | Fleet config sync | 30s | From TransportConfig, could be event-driven on relay |
| `fleet_cloud.dart:160` | Cloud command poll | 3s | REST API has no push |
| `map_view.dart:173` | LIDAR poll | 200ms | HTTP polling for visualization — correct rate for real-time display |
| `map_view.dart:224` | People poll | 200ms | Same |
| `map_view.dart:302` | Depth poll | 500ms | Same, lower rate for large payload |
| `map_view.dart:485` | Map poll | 5s | Map doesn't change often |
| `adaptive_transport.dart:410` | Metrics logging | 5s | Debug logging |
| `adaptive_transport.dart:429` | Connection quality check | 10s | Network adaptation |

---

## PROBLEMS FOUND

### HIGH: Fake TTS Duration Estimation

| File | Line | Code | Issue |
|------|------|------|-------|
| `sequence_mode.dart:1387-1391` | `_estimateTtsDuration()` | `Duration(seconds: (words / 2.5).ceil().clamp(2, 60))` | **Guesses** TTS duration from word count. Should wait for relay's TTS completion signal. |
| `sequence_mode.dart:1447-1448` | `arrivalDuration + Duration(milliseconds: 1000)` | Estimated TTS + 1 second padding | Guesses when TTS is done, then adds arbitrary 1s buffer |
| `sequence_mode.dart:1460` | `await Future.delayed(ttsDuration)` | Waits estimated TTS duration | Sleeps for guessed duration instead of waiting for completion |
| `sequence_mode.dart:1434` | `Future.delayed(Duration(milliseconds: 500))` | Pre-arrival delay | Arbitrary 500ms "settling" delay before speaking |
| `task_engine.dart:698-699` | `Future.delayed(Duration(seconds: 2))` | "Rough TTS duration" | Comment literally says it's a rough guess |

**Fix**: The relay already sends `buffer_cmd_completed` when TTS finishes. Use that signal instead of guessing word count.

### HIGH: Stabilization Delays

| File | Line | Code | Issue |
|------|------|------|-------|
| `grpc_client.dart:160` | `Future.delayed(Duration(milliseconds: 100))` | "Let stream stabilize" | Same pattern as relay's removed stream stabilize delay |
| `hud_screen.dart:247` | `Future.delayed(Duration(milliseconds: 1500))` | Post-init delay | Waits 1.5s after initState for "connection to establish" |
| `hud_screen.dart:386,392` | `Future.delayed(Duration(milliseconds: 500))` x2 | After tour start/stop | Arbitrary delays before UI state changes |
| `hud_screen.dart:415` | `Timer.periodic(Duration(milliseconds: 500))` | Polling connection status after connect | Should listen to connection state stream |
| `dual_connection.dart:317` | `Future.delayed(Duration(milliseconds: 200))` | Post-disconnect delay | "Let cleanup complete" before reconnect |
| `fleet_discovery.dart:341` | `Future.delayed(Duration(seconds: 2))` | Between discovery scan rounds | Arbitrary pause between scans |
| `fleet_discovery.dart:375` | `Future.delayed(Duration(milliseconds: 500))` | Between gRPC probes | Rate limiting — should use a semaphore |
| `mqtt_transport.dart:371` | `Future.delayed(Duration(milliseconds: 100))` | "Simulate connection delay" | Comment says it's simulated! |

### HIGH: Post-Action UI Resets

| File | Line | Code | Issue |
|------|------|------|-------|
| `sequence_mode.dart:1324` | `Future.delayed(Duration(seconds: 3))` | Reset after sequence complete | Should reset on next user action, not timer |
| `sequence_mode.dart:1567` | `Future.delayed(Duration(seconds: 3))` | Reset after abort | Same |
| `buffer_sequence_executor.dart:916` | `Future.delayed(Duration(seconds: 3))` | Reset after complete | Same |
| `map_view.dart:597` | `Future.delayed(Duration(seconds: 2))` | Reset after map refresh | Should reset when map data arrives |
| `waypoint_grid.dart:297` | `Future.delayed(Duration(milliseconds: 1500))` | Reset waypoint state | Should reset on next nav command |
| `sequence_editor.dart:734` | `Duration(seconds: pushed == totalTours ? 2 : 5)` | SnackBar duration | Different durations based on push count — UI notification, acceptable |

### MEDIUM: Hardcoded Adaptive Transport Delays

| File | Line | Code | Issue |
|------|------|------|-------|
| `adaptive_transport.dart:262-263` | `Future.delayed(_getAdaptiveDelay())` | Velocity queue processing | 10-200ms based on connection quality — adaptive but still a guess |
| `adaptive_transport.dart:148,158,167` | `resetTimeout` | 15-30s | Circuit breaker reset timeouts — should reset on successful connection |

### MEDIUM: Task Engine TTS Wait

| File | Line | Code | Issue |
|------|------|------|-------|
| `task_engine.dart:668` | `Future.delayed(Duration(milliseconds: 500))` | Wait after speak step | Arbitrary post-TTS delay. Relay already signals completion. |
| `task_mode.dart:231` | `Future.delayed(Duration(seconds: 1))` | Between command checks | Polling instead of event-driven |
| `task_mode.dart:275` | `Timer.periodic(Duration(milliseconds: 500))` | Command status polling | Should use completion streams |

### LOW: Display Duration at HUD

| File | Line | Code | Issue |
|------|------|------|-------|
| `hud_screen.dart:169` | `Future.delayed(Duration(seconds: durationSeconds))` | Auto-close display after N seconds | Duration comes from Flutter config — this IS the task |
| `hud_screen.dart:2012` | `Future.delayed(Duration(milliseconds: 100))` | Scroll after build | `WidgetsBinding.instance.addPostFrameCallback` would be better |

---

## Summary

| Category | Count | Status |
|----------|-------|--------|
| Heartbeat / Liveness | 10 | Correct |
| Velocity commands | 4 | Correct — protocol requirement |
| UI animations | 7 | Correct — visual feedback |
| Transport timeouts | 19 | Correct — safety caps |
| Reconnection | 4 | Mostly correct, 1 needs backoff |
| Task/sequence durations | 6 | Correct — content IS timing |
| HTTP polling (no push) | 10 | Acceptable — no signal available |
| **Fake TTS estimation** | **5** | **FIX — relay signals completion** |
| **Stabilization delays** | **8** | **FIX — use readiness signals** |
| **Post-action timer resets** | **6** | **FIX — reset on next action** |
| **Task engine waits** | **3** | **FIX — use completion streams** |

### Key Difference from Relay

Flutter already has `TransportConfig` centralizing most timing parameters with SharedPreferences persistence and network adaptation. The main problems are:

1. **`sequence_mode.dart` guesses TTS duration from word count** instead of waiting for the relay's `buffer_cmd_completed` signal — this is the biggest fake logic issue
2. **Stabilization delays** (`Future.delayed` after connect/disconnect) — same pattern we just fixed in the relay
3. **Post-action UI resets** using `Future.delayed(3s)` instead of resetting on the next user action
4. **`task_engine.dart` comments literally say "rough TTS duration"** — honest about the hack at least
