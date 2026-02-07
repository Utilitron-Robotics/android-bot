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

## PROBLEMS FOUND AND FIXED

### FIXED: Fake TTS Duration Estimation

| File | What Was Fixed |
|------|---------------|
| `task_engine.dart:668` | Removed 500ms post-announce delay — fire-and-forget, relay handles timing |
| `task_engine.dart:698-699` | Removed 2s "rough TTS duration" guess — advance immediately, relay signals completion |

**Remaining (legacy path, guarded by deprecation warnings):**
| `sequence_mode.dart:1387-1391` | `_estimateTtsDuration()` — only used in deprecated `_executeStopActions()` fallback path, guarded by SequenceTaskMode/BufferSequenceExecutor checks |

### FIXED: Stabilization Delays

| File | What Was Fixed |
|------|---------------|
| `grpc_client.dart:160` | Removed 100ms "stream stabilize" delay — send heartbeat immediately after listen() |
| `hud_screen.dart:386,392` | Removed 500ms disconnect-then-reconnect delays — connect immediately, onOpen IS readiness |
| `hud_screen.dart:415` | Replaced Timer.periodic(500ms) polling with ChangeNotifier listener on BufferClient |
| `dual_connection.dart:317` | Removed 200ms delay between advertise and subscribe — rosbridge processes sequentially |
| `mqtt_transport.dart:371` | Removed simulated 100ms connection delay |

**Remaining (acceptable):**
| `hud_screen.dart:247` | 1.5s nav-start check — UI timeout safety net, not stabilization |
| `fleet_discovery.dart:341,375` | WiFi connect delays — OS-level WiFi handshake timing, can't be signal-driven |

### FIXED: Post-Action UI Resets

| File | What Was Fixed |
|------|---------------|
| `sequence_mode.dart:1324` | `_cleanupSequenceTask()` — reset immediately instead of 3s Future.delayed |
| `sequence_mode.dart:1567` | `_completeSequence()` — reset immediately instead of 3s Future.delayed |
| `buffer_sequence_executor.dart:916` | `_completeSequence()` — reset immediately instead of 3s Future.delayed |
| `map_view.dart:597` | Map refresh — fetch immediately instead of 2s delay after refresh request |

**Remaining (acceptable):**
| `waypoint_grid.dart:297` | 1.5s nav-start check — same UI timeout pattern as hud_screen |
| `sequence_editor.dart:734` | SnackBar duration — UI notification display, not a delay |

### FIXED: Reconnection Backoff

| File | What Was Fixed |
|------|---------------|
| `dual_connection.dart:303` | Fixed 3s reconnect replaced with exponential backoff (1s-30s), resets on success |

### Remaining (NEEDS FUTURE WORK)

| File | Line | Code | Issue |
|------|------|------|-------|
| `adaptive_transport.dart:262-263` | `_getAdaptiveDelay()` | 10-200ms velocity queue | Adaptive but still a guess — acceptable for now |
| `adaptive_transport.dart:148,158,167` | `resetTimeout` | 15-30s circuit breaker | Should reset on successful connection |
| `task_mode.dart:231` | `Future.delayed(Duration(seconds: 1))` | Command queue poll | Polling for connection — needs connection stream |
| `task_mode.dart:275` | `Timer.periodic(Duration(milliseconds: 500))` | Timeout check | Heartbeat-style "is this missing?" — acceptable |
| `hud_screen.dart:169` | `Future.delayed(Duration(seconds: durationSeconds))` | Auto-close display | Duration from config — this IS the task |
| `hud_screen.dart:2012` | `Future.delayed(Duration(milliseconds: 100))` | Scroll after build | Should use addPostFrameCallback |

---

## Summary

| Category | Count | Status |
|----------|-------|--------|
| Heartbeat / Liveness | 10 | Correct |
| Velocity commands | 4 | Correct — protocol requirement |
| UI animations | 7 | Correct — visual feedback |
| Transport timeouts | 19 | Correct — safety caps |
| Reconnection | 4 | **Fixed** — backoff added |
| Task/sequence durations | 6 | Correct — content IS timing |
| HTTP polling (no push) | 10 | Acceptable — no signal available |
| **Fake TTS estimation** | **2 fixed, 1 legacy** | **Fixed — relay signals completion** |
| **Stabilization delays** | **5 fixed, 2 acceptable** | **Fixed — readiness signals** |
| **Post-action timer resets** | **4 fixed, 2 acceptable** | **Fixed — reset immediately** |
| **Task engine waits** | **2 fixed, 2 remaining** | **Mostly fixed** |

## What Was Fixed (This Commit)

| Before | After | File |
|--------|-------|------|
| `Future.delayed(Duration(seconds: 2))` TTS guess | Advance immediately — relay signals completion | task_engine.dart |
| `Future.delayed(Duration(milliseconds: 500))` post-announce | Fire-and-forget | task_engine.dart |
| `Future.delayed(Duration(milliseconds: 100))` stream stabilize | Send heartbeat immediately | grpc_client.dart |
| `Future.delayed(Duration(milliseconds: 500))` x2 reconnect | Connect immediately after disconnect | hud_screen.dart |
| `Timer.periodic(500ms)` button standby poll | ChangeNotifier listener | hud_screen.dart |
| Fixed 3s reconnect | Exponential backoff 1s-30s | dual_connection.dart |
| `Future.delayed(200ms)` advertise/subscribe gap | No delay — sequential processing | dual_connection.dart |
| `Future.delayed(100ms)` simulated delay | Removed | mqtt_transport.dart |
| `Future.delayed(3s)` cleanup reset | Reset immediately | sequence_mode.dart x2 |
| `Future.delayed(3s)` complete reset | Reset immediately | buffer_sequence_executor.dart |
| `Future.delayed(2s)` map refresh | Fetch immediately | map_view.dart |
