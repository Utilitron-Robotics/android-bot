# Relay App — Required Timing Reference

**Updated**: 2026-02-07 (post-fix)
**Directive**: Only heartbeat "is this missing?" checks may use hardcoded intervals. Everything else is driven by task completion or signals.

---

## Category 1: Heartbeat / Liveness Checks (ALLOWED — no other signal exists)

| File | Timer | Value | Justification |
|------|-------|-------|---------------|
| `Heartbeat.kt:122` | Drummer interval | Configurable | Sends periodic heartbeat beats — no external signal to trigger |
| `Heartbeat.kt:212` | Messenger check | Adaptive EMA | Checks if heartbeats are missing — learns rhythm via SINC-style EMA |
| `RobotControlServiceImpl.kt:88` | `HEARTBEAT_INTERVAL_MS` | 1000ms | gRPC heartbeat to Flutter clients — no signal to trigger, must be periodic |
| `RobotControlServiceImpl.kt:199` | `HEARTBEAT_INTERVAL_MS` | 1000ms | Same, for streamHeartbeat() RPC |
| `GrpcServer.kt:32-33` | `KEEPALIVE_TIME_MS` / `KEEPALIVE_TIMEOUT_MS` | 10s / 5s | gRPC transport-level keepalive — protocol heartbeat |
| `GrpcServer.kt:98` | Server health monitor | 30s | Checks if gRPC server process is still alive — liveness check |
| `RelayServer.kt:171` | Forwarder liveness | 10s | Logs if message forwarder is still receiving — liveness check |
| `RelayServer.kt:736` | `PING_INTERVAL_MS` | 10s | WebSocket keepalive ping — transport heartbeat |
| `AwsIotClient.kt:210` | Command polling | 2s | REST API has no push — polling IS the only mechanism |
| `RobotWebSocketClient.kt:859` | Reconnect delay | Adaptive | Uses AdaptiveConnectionPolicy learned interval, falls back to 1s constant |
| `CommandBuffer.kt:382` | Buffer heartbeat | Configurable | Rhythm-based heartbeat to Flutter — interval set by Drummer |

## Category 2: Velocity Commands (REQUIRED — chassis protocol spec)

| File | Timer | Value | Justification |
|------|-------|-------|---------------|
| `CommandBuffer.kt:653` | smartVelocity send rate | 200ms | Chassis protocol: velocity commands expire after 0.6s. Must send at 200ms (3x within window) to maintain movement. This IS the real-time requirement. |
| `MainActivity.kt:643` | Joystick velocity send | 100ms | Same — UI joystick button held down sends velocity at 100ms intervals |

## Category 3: Audio Durations (REQUIRED — content IS the timing)

| File | Timer | Value | Justification |
|------|-------|-------|---------------|
| `RelayService.kt:969-999` | Tone note gaps | 30-100ms | Musical rests between generated tones — silence IS the content |
| `RelayService.kt:845,859` | Task wait durations | From Flutter | `task.waitSeconds` — Flutter specifies how long to show/wait |
| `CommandBuffer.kt:768,790` | Wait/display durations | From Flutter | `durationMs` — Flutter specifies the duration, it IS the task |

## Category 4: Safety Timeouts (REQUIRED — caps for signal waits)

| File | Timer | Value | Justification |
|------|-------|-------|---------------|
| `CommandBuffer.kt:521` | Nav timeout | 120s | Safety cap — if nav signals never arrive, don't wait forever |
| `CommandBuffer.kt:531` | Nav signal wait | 500ms | `withTimeoutOrNull` on navSignal.receive() — checks progress between signals |
| `CommandBuffer.kt:633` | Recovery nav-cancel wait | 2s | `withTimeoutOrNull` — waits for navStatus to leave 601, capped |
| `CommandBuffer.kt:717` | Recovery stopped confirm | 2s | `withTimeoutOrNull` — waits for velocity to reach zero, capped |
| `CommandBuffer.kt:918` | TTS finish before button | 5s | `withTimeoutOrNull` — safety cap on TTS completion signal |
| `RelayService.kt:1079` | generateTone playback | duration+500ms | `withTimeoutOrNull` — safety cap on AudioTrack completion signal |
| `RelayService.kt:1158` | Siren playback | 10s | `withTimeoutOrNull` — safety cap on AudioTrack marker signal |
| `RelayService.kt:1182` | TTS in alarm | 10s | `withTimeoutOrNull` — safety cap on TTS completion signal |
| `RobotWebSocketClient.kt:445` | Map data arrival | 5s | `withTimeoutOrNull` — waits for map data from robot, fallback to /static_map |

## Category 5: Transport / Protocol Configuration (REQUIRED — external system requirements)

| File | Timer | Value | Justification |
|------|-------|-------|---------------|
| `GrpcServer.kt:34` | `MAX_CONNECTION_IDLE_MS` | 5 min | gRPC auto-close idle connections — protocol config |
| `RelayServer.kt:731` | NanoWSD socket timeout | 60s | WebSocket framework socket timeout — transport config |
| `RobotWebSocketClient.kt:163` | OkHttp read timeout | 0 (infinite) | WebSocket must stay open — transport config |
| `CloudTtsService.kt` | HTTP connect/read timeout | 10s / 30s | Google Cloud TTS API timeouts — external API config |
| `AwsIotClient.kt:302-303` | HTTP connect/read timeout | 10s / 10s | AWS API timeouts — external API config |
| `ChassisProtocol.kt` | Throttle rates | 150-5000ms | ROS subscription rates per topic — protocol config |
| `DepthPeopleDetector.kt:38` | `MIN_PROCESS_INTERVAL_MS` | 100ms | Throughput cap — don't process depth data faster than 10Hz |

## Category 6: Algorithm Parameters (NOT timers — math constants)

| File | Parameter | Value | What It Is |
|------|-----------|-------|------------|
| `ObstacleClassifier.kt` | Velocity/movement thresholds | Various | Classification math — not timing |
| `PeopleTracker.kt` | Smoothing alpha, association distance | 0.3, 1.5m | Tracking algorithm — not timing |
| `Heartbeat.kt` | EMA weights | 0.9/0.1 | Rhythm learning — algorithm parameter |
| `AdaptiveConnectionPolicy.kt` | Reliability thresholds | 0.95-0.20 | Learned retry behavior — all configurable via SharedPreferences |
| `RobotWebSocketClient.kt` | Safety distances | 0.20/0.50/0.80m | Physical robot stopping distances |

## Category 7: Remaining Startup Delays (NEEDS FUTURE WORK)

| File | Timer | Value | Issue | Fix Path |
|------|-------|-------|-------|----------|
| `MainActivity.kt:61` | IP refresh after gRPC start | 2s | Waits for gRPC server to start | Need callback from GrpcServer.start() |
| `MainActivity.kt:605` | Service rebind retry | 1s | Waits for service binding | Need ServiceConnection callback |
| `RelayService.kt:222` | Wait for robotClient init | 100ms poll | `while (!::robotClient.isInitialized)` | Need lateinit signal |
| `CommandBuffer.kt:919` | TTS speaking poll | 100ms | `while (isTtsSpeaking())` inside withTimeout | Need TTS completion CompletableDeferred plumbed through |
| `RobotWebSocketClient.kt:447` | Map cache poll | 100ms | `while (_cachedMapMessage == null)` inside withTimeout | Need onMessage to signal a CompletableDeferred |
| `CloudTtsService.kt:313` | Precache rate limit | 500ms | Sequential rate limit between API calls | Could use Semaphore or queue |

---

## What Was Fixed (This Commit)

| Before | After | File |
|--------|-------|------|
| `while(paused) delay(100)` | `_paused.first { !it }` | CommandBuffer |
| `delay(100)` idle loop | `commandAvailable.receive()` | CommandBuffer |
| `delay(100)` nav wait | `navSignal.receive()` from onNavStatus | CommandBuffer |
| `delay(300)` post-recovery | `robotStatus.first { stopped }` | CommandBuffer |
| `delay(500)` button standby poll | `externalCompletion.await()` | CommandBuffer |
| `delay(200)` people detect | `peopleDetected.first { it }` | CommandBuffer |
| 30s greeting cooldown | TTS completion signal | CommandBuffer |
| `delay(500)` after onOpen | Removed — onOpen IS readiness | RobotWebSocketClient |
| `time % 2000 < 100` log hack | Counter `% 20` | RobotWebSocketClient |
| `delay(300)` + `delay(2000)` x2 map refresh | Single 5s wait for data arrival | RobotWebSocketClient |
| Reconnect constant 1s | Defers to AdaptiveConnectionPolicy | RobotWebSocketClient |
| `Thread.sleep(ms + 50)` | AudioTrack completion listener | RelayService |
| `delay(3200)` siren | AudioTrack marker notification | RelayService |
| `delay(30_000)` fleet sync poll | `robotStatus.collect` on change | RelayService |
| Timer-based obstacle cooldown | TTS completion signal debounce | RelayService |
| `delay(1000)` post-reconnect | Removed — onOpen triggers subscriptions | RelayServer |
| `delay(100)` forwarder restart | Removed — flow completion is the signal | RelayServer |
| `delay(100)` stream stabilize | Removed — send heartbeat immediately | RobotControlServiceImpl |
| `delay(5000)` status poll | Change-driven via updateStatus() | AwsIotClient |
