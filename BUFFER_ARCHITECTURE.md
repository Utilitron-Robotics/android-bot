# Relay Buffer Architecture

> **Note**: This document outlines the conceptual design for the buffer system. The implementation has now been integrated into `flutter_app` (BufferClient) and `relay_app` (CommandBuffer).

## Core Principle
**Relay = BUFFER ONLY. No logic. No retries. No decisions.**

Flutter is the brain. Relay is just a command queue that executes and reports.

## Current Problems
1. THREE competing retry systems (SequenceExecutor, SequenceTaskMode, CommandManager)
2. Flutter sends individual commands with no queue concept
3. No clear status protocol between Flutter and Relay
4. Logic scattered between Flutter, Relay, and Robot

## New Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      FLUTTER (Brain)                        │
│                                                             │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────────┐   │
│  │ SequenceMode│   │ TaskEngine  │   │ RobotConnection │   │
│  │ (what/when) │   │ (waypoint)  │   │ (comm layer)    │   │
│  └──────┬──────┘   └──────┬──────┘   └────────┬────────┘   │
│         │                 │                    │            │
│         └────────────┬────┴────────────────────┘            │
│                      ▼                                      │
│            ┌─────────────────┐                              │
│            │  BufferClient   │  ← Sends commands, receives  │
│            │  (new class)    │    status, decides retries   │
│            └────────┬────────┘                              │
└─────────────────────┼───────────────────────────────────────┘
                      │ WebSocket
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                    RELAY (Buffer Only)                      │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                  CommandBuffer                       │   │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐   │   │
│  │  │ cmd 1   │ │ cmd 2   │ │ cmd 3   │ │ cmd 4   │   │   │
│  │  │(running)│ │(pending)│ │(pending)│ │(pending)│   │   │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘   │   │
│  └─────────────────────────────────────────────────────┘   │
│                          │                                  │
│                          ▼                                  │
│                   Execute & Report                          │
│                          │                                  │
└──────────────────────────┼──────────────────────────────────┘
                           │ WebSocket (to robot)
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                        ROBOT                                │
│                   (ROS/rosbridge)                           │
└─────────────────────────────────────────────────────────────┘
```

## Protocol: Flutter → Relay

### Load Commands into Buffer
```json
{
  "op": "buffer_load",
  "commands": [
    {
      "id": "uuid-1",
      "type": "navigate",
      "waypoint": "Kitchen",
      "timeout_ms": 60000
    },
    {
      "id": "uuid-2",
      "type": "speak",
      "text": "Your order has arrived",
      "timeout_ms": 10000
    },
    {
      "id": "uuid-3",
      "type": "wait",
      "duration_ms": 30000
    }
  ],
  "clear_existing": true
}
```

### Control Commands
```json
{"op": "buffer_clear"}              // Clear all pending
{"op": "buffer_pause"}              // Pause after current
{"op": "buffer_resume"}             // Resume execution
{"op": "buffer_skip"}               // Skip current command
{"op": "buffer_status"}             // Request status update
```

## Protocol: Relay → Flutter

### Heartbeat (every 1 second)
```json
{
  "op": "buffer_heartbeat",
  "timestamp": 1704292800000,
  "buffer": {
    "paused": false,
    "current": {
      "id": "uuid-1",
      "type": "navigate",
      "waypoint": "Kitchen",
      "started_at": 1704292795000,
      "elapsed_ms": 5000
    },
    "pending_count": 3,
    "completed_count": 2
  },
  "robot": {
    "connected": true,
    "nav_status": 601,
    "nav_goal": "Kitchen",
    "battery": 85
  }
}
```

### Command Events
```json
{
  "op": "buffer_cmd_started",
  "command": {"id": "uuid-1", "type": "navigate", ...},
  "timestamp": 1704292795000
}

{
  "op": "buffer_cmd_completed",
  "command_id": "uuid-1",
  "result": "success",  // or "timeout", "cancelled", "robot_failed"
  "duration_ms": 15000,
  "timestamp": 1704292810000
}
```

## Command Types

### navigate
```json
{
  "type": "navigate",
  "waypoint": "Kitchen",
  "timeout_ms": 60000
}
```
- Relay sends POI command to robot
- Completes when nav_status = 603 (arrived)
- Fails when nav_status = 604 (failed) or timeout

### speak
```json
{
  "type": "speak",
  "text": "Hello world",
  "timeout_ms": 30000
}
```
- Relay uses TTS to speak
- Completes when TTS callback fires

### display
```json
{
  "type": "display",
  "url": "https://example.com/page",
  "duration_ms": 10000  // 0 = until next command
}
```
- Shows URL on tablet screen
- Completes after duration (or immediately if 0)

### wait
```json
{
  "type": "wait",
  "duration_ms": 30000
}
```
- Simply waits for duration
- Completes after duration

### sound
```json
{
  "type": "sound",
  "sound": "arrival" | "delivery" | "horn" | "beep"
}
```
- Plays alert sound
- Completes immediately after playback

### close_display
```json
{
  "type": "close_display"
}
```
- Closes any displayed content
- Completes immediately

## Flutter Logic (moves OUT of Relay)

### Retry Logic
```dart
void onCommandCompleted(String id, String result) {
  if (result == 'robot_failed' && _retryCount < 3) {
    _retryCount++;
    _speak('Path blocked. Retrying.');
    _bufferClient.loadCommands([_currentNavCommand]);
  } else if (result == 'robot_failed') {
    _fail('Navigation failed after 3 retries');
  } else {
    _retryCount = 0;
    _advanceSequence();
  }
}
```

### Sequence Execution
```dart
void startSequence(Sequence seq) {
  final commands = <BufferCommand>[];

  for (final stop in seq.stops) {
    commands.add(BufferCommand.navigate(stop.waypoint));
    if (stop.speakText != null) {
      commands.add(BufferCommand.speak(stop.speakText!));
    }
    if (stop.displayUrl != null) {
      commands.add(BufferCommand.display(stop.displayUrl!, stop.displayDuration));
    }
    if (stop.waitSeconds > 0) {
      commands.add(BufferCommand.wait(stop.waitSeconds * 1000));
    }
  }

  _bufferClient.loadCommands(commands, clearExisting: true);
}
```

## Implementation Steps

### Phase 1: Relay Buffer
1. Create `CommandBuffer` class in Relay
2. Add buffer management WebSocket ops
3. Add heartbeat broadcast
4. Remove all retry/decision logic from Relay

### Phase 2: Flutter Client
1. Create `BufferClient` class
2. Move retry logic from SequenceTaskMode to BufferClient
3. Update SequenceMode to use BufferClient
4. Remove CommandManager (replaced by buffer)

### Phase 3: Cleanup
1. Delete SequenceExecutor (replaced by buffer protocol)
2. Simplify SequenceTaskMode (just tracks UI state)
3. Remove competing systems

## Benefits

1. **Single source of truth**: Buffer state is the only state
2. **No fighting**: Only Flutter decides retries
3. **Observable**: Heartbeat shows exactly what's happening
4. **Recoverable**: Flutter can reload buffer on reconnect
5. **Testable**: Buffer is just a queue, easy to unit test
6. **Simple Relay**: No business logic, just execute and report
