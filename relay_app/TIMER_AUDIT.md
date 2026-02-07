# Relay App Timer Audit — Honest Assessment

**Date**: 2026-02-07
**Scope**: All 21 Kotlin source files in `relay_app/`
**Directive**: Only the heartbeat's "is this missing?" check should be hardcoded. Everything else should be driven by task completion or signals.

---

## The Code Already Has Event-Driven Infrastructure

Before listing what needs to change, it's important to acknowledge what's already in place. The codebase is NOT structured around timers — it's structured around events, with timers sprinkled in where the author got lazy or ran out of time.

### Patterns Already Established

| Pattern | Where It's Used | Example |
|---------|----------------|---------|
| **CompletableDeferred** | CommandBuffer TTS, sounds, stuck announcement | `val ttsComplete = CompletableDeferred<Unit>()` ... `ttsComplete.await()` |
| **StateFlow** | Paused state, connection state, robot status, people detection | `_paused = MutableStateFlow(false)` |
| **Callbacks** | TTS completion, sound completion, tour start | `speakText(text) { completion.complete(Unit) }` |
| **Flow.collect** | Robot status stream, connection state | `robotClient.robotStatus.collect { status -> ... }` |
| **Drummer/Messenger** | Bidirectional heartbeat with adaptive rhythm learning | `Heartbeat.kt` — SINC-style rhythm detection via EMA |
| **onNavStatus callback** | Navigation 601/602/603/604 events | Event-driven nav state machine in CommandBuffer |
| **AdaptiveConnectionPolicy** | Reconnection with learned reliability | SharedPreferences-backed configurable retry policy |

The heartbeat system (Drummer/Messenger) already does exactly what the directive says — it's the only place where a hardcoded interval is justified because there's no external signal to wait for. The Messenger even *learns* the rhythm via EMA and adapts its check interval.

---

## What Actually Needs to Change

These are targeted replacements, not rewrites. Each one swaps a `delay(X)` for an event wait using a pattern already used elsewhere in the same file.

### CommandBuffer.kt — 5 targeted fixes

**1. Pause wait (line 448-450)**
```kotlin
// CURRENT: Polls every 100ms
while (_paused.value && isActive) { delay(100) }

// FIX: One-liner — _paused is already a StateFlow
_paused.first { !it }
```

**2. Idle wait (line 453-455)**
```kotlin
// CURRENT: Spins at 100ms when nothing to execute
if (currentIndex < 0 || currentIndex >= commandList.size) { delay(100); continue }

// FIX: Use a signal (CompletableDeferred or Channel) that loadCommands() triggers
commandAvailable.receive()  // Suspends until loadCommands() sends
```

**3. Nav wait loop (line 517-518)**
```kotlin
// CURRENT: Polls at 100ms during navigation
while (waitingForNavArrival && ...) { delay(100) ... }

// FIX: Nav completion is ALREADY signaled via onNavStatus() callback
// Create a CompletableDeferred<String> that onNavStatus completes
// The pattern is already used for TTS (line 526-530) and sounds (line 535-541)
navCompletion.await()
```

**4. Button standby people detection (line 862-863, 938-939)**
```kotlin
// CURRENT: Polls peopleDetected every 200ms/500ms
while (currentCommand != null && !robotClient.peopleDetected.value) { delay(200) }
// and in button_standby:
while (currentCommand != null) { delay(500) ... }

// FIX: peopleDetected is already a StateFlow
robotClient.peopleDetected.first { it }
```

**5. TTS wait in button_standby (line 905-909)**
```kotlin
// CURRENT: Polls isTtsSpeaking() every 250ms
while (taskExecutor?.isTtsSpeaking() == true && waitCount < 20) { delay(250) }

// FIX: TTS already has completion callbacks — use CompletableDeferred
// (same pattern as line 731-741 in the same file)
```

**The recovery velocity loop (`delay(200)` in smartVelocity)** is actually correct — velocity commands expire after 0.6s per chassis protocol spec, so sending them at 200ms intervals (3x within the window) IS the real-time requirement. This is signal-driven in the sense that the robot needs continuous commands.

**The nav 602 grace period** was already replaced by proper layered checks — goal name matching + movement tracking + recovery state. The `timeSinceSend < 3000` is Layer 1 of 3 checks, and `hasStartedMoving` (Layer 3) is the actual signal-based guard that catches the real cases.

### RelayService.kt — 3 targeted fixes

**1. Thread.sleep in generateTone (line 1070)**
```kotlin
// CURRENT: Blocks thread
Thread.sleep(durationMs.toLong() + 50)

// FIX: AudioTrack supports setNotificationMarkerPosition + OnPlaybackPositionUpdateListener
// OR: Use MODE_STATIC with a CompletableDeferred triggered by playback position notification
```

**2. Emergency alarm siren duration (line 1149)**
```kotlin
// CURRENT: delay(3200) guessing how long 7 loops of audio take
track.setLoopPoints(0, numSamples, 7)
track.play()
delay(3200)

// FIX: setNotificationMarkerPosition(numSamples * 8) with listener that signals completion
```

**3. Fleet sync (line 216)**
```kotlin
// CURRENT: Polls every 30 seconds regardless
while (isActive) { delay(30_000); fleetClient.fetchConfig() }

// FIX: Sync on state change (robotStatus.collect) with a coalescing window
// Report when status actually changes, not on a blind timer
```

The tone gaps between notes (`delay(100)`, `delay(30)`) are intentional musical rests — silence between notes IS the requirement. These aren't "waiting for something to happen," they're "play silence for this duration." Same category as the `wait` command's `durationMs`.

The obstacle cooldowns are debounce logic, not fake timers. They prevent spamming "excuse me" 10 times per second. Debounce inherently requires a time window — but the window should be derived from the TTS completion signal (don't announce again until the last announcement finished playing).

### RobotWebSocketClient.kt — 3 targeted fixes

**1. Post-connect delay (delay(500) after onOpen)**
Remove it. Send subscriptions immediately. The WebSocket `onOpen` IS the readiness signal — that's literally what it means.

**2. Map refresh unsub/resub (delay(300) + delay(2000))**
Rosbridge sends a confirmation message for unsubscribe. Wait for that, then resubscribe.

**3. Modular time logging hack**
Replace `System.currentTimeMillis() % 2000 < 100` with a simple counter: `if (logCounter++ % 20 == 0)`.

The reconnect delay (`RECONNECT_DELAY_MS = 1000L`) should defer to AdaptiveConnectionPolicy, which already exists and already handles this correctly with learned reliability.

### RobotControlServiceImpl.kt — 1 targeted fix

**STREAM_STABILIZE_DELAY_MS = 100L** — Remove it. The gRPC stream is ready when `controlStream()` is called. Send the first heartbeat immediately (the Drummer pattern already does this — "Send first beat immediately" on line 118 of Heartbeat.kt).

The `HEARTBEAT_INTERVAL_MS = 1000L` stays — this IS the heartbeat check. The LIDAR staleness threshold (`3000ms`) is a "is this data missing?" check — same category as heartbeat, stays.

### AwsIotClient.kt — 1 targeted fix

**Status reporting** should fire on `robotClient.robotStatus` changes (collect the flow), not poll every 5 seconds. The `delay(5000)` becomes a coalescing window — "don't report more than once per 5 seconds" — which is a debounce, not a poll.

Command polling (`delay(2000)`) is genuinely polling a REST API. Without WebSocket push from AWS, polling IS the mechanism. The interval stays but should be configurable.

### Other Files — No Changes Needed

| File | Status | Reason |
|------|--------|--------|
| Heartbeat.kt | **Stays as-is** | This IS the heartbeat. Hardcoded interval is the directive's exception. |
| AdaptiveConnectionPolicy.kt | **Stays as-is** | Already configurable via SharedPreferences. Well-designed. |
| ChassisProtocol.kt | **Stays as-is** | Throttle rates control ROS subscription frequency — these are protocol-level. |
| ObstacleClassifier.kt | **Stays as-is** | Algorithm parameters (velocity thresholds, scan history) — not timers. |
| PeopleTracker.kt | **Stays as-is** | Tracking algorithm parameters (EMA weights, association distance) — not timers. |
| DepthPeopleDetector.kt | **Stays as-is** | Rate limiting input processing to 10Hz — this is throughput control. |
| GrpcServer.kt | **Stays as-is** | gRPC keepalive IS a heartbeat mechanism. Health monitor is a liveness check. |
| CloudTtsService.kt | **Stays as-is** | HTTP timeouts are transport-level requirements. Cache limits are policy. |
| DiscoveryService.kt | **Already clean** | No timing issues. |
| WebRtcManager.kt | **Already clean** | No timing issues. |

---

## Summary

| Category | Count | Actual Work |
|----------|-------|-------------|
| Polling loops → Flow.first{} / CompletableDeferred | 5 | Mechanical one-line replacements using existing patterns |
| Thread.sleep → AudioTrack completion listener | 2 | Use Android's built-in playback notification API |
| Stabilization delays → remove or use existing signals | 3 | Delete the delay; the signal (onOpen, stream ready) already exists |
| Timer polling → StateFlow.collect | 2 | Fleet sync and cloud status: collect flow instead of poll |
| Logging hack → counter | 1 | One-line fix |
| **Total targeted changes** | **13** | |

### What Stays (Correctly)

- **Heartbeat intervals** (Drummer/Messenger) — the directive's explicit exception
- **gRPC keepalive** — transport-level heartbeat
- **Liveness monitors** — "is this thing missing?" checks
- **LIDAR staleness threshold** — "is this data missing?" check
- **Velocity command rate** (200ms in smartVelocity) — chassis protocol requires continuous commands at this rate
- **Musical note durations and rests** — these are the actual content being played
- **Wait command durations** — these come from Flutter, they ARE the task
- **Display durations** — same, Flutter specifies how long to show content
- **Algorithm parameters** (EMA weights, tracking thresholds) — math, not timers
- **HTTP timeouts** — transport-level requirements
- **Debounce windows** — should be derived from completion signals but the concept is valid

The infrastructure is already there. The fixes are targeted swaps, not a rewrite.
