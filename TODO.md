# Android-Bot TODO List

## Security (PRIORITY)
- [ ] Change robot WiFi hotspot passwords (currently `123456789` - cracked in 1 day)
  - SSH into robot base at `10.42.0.1`
  - Find hostapd config: `find /etc -name "*hostapd*"`
  - Update `wpa_passphrase` to strong password
  - Restart WiFi service
  - Update CLAUDE.md with new credentials

---

## Critical Architecture Issues

### 1. TaskMode Naming Collision (FIXED)
**Problem:** Two completely different classes named `TaskMode`:
- `task_engine.dart`: Data model (id, name, steps) - now renamed to `WaypointTask`
- `task_mode.dart`: Abstract executable base class - kept as `TaskMode`

**Solution Applied:**
- [x] Renamed data model class `TaskMode` → `WaypointTask` in task_engine.dart
- [x] Renamed `WaypointModeAssignment` → `WaypointTaskAssignment`
- [x] Updated mode_editor.dart to use `WaypointTask`
- [x] Abstract executable `TaskMode` in task_mode.dart kept as base class for modes

### 2. Two Parallel Systems Don't Integrate
**Problem:**
- `TaskEngine` handles per-waypoint task assignments
- `SequenceManager` handles multi-waypoint sequences
- They don't share execution infrastructure

**Fix:**
- [ ] Unify under `TaskManager` for all task execution
- [ ] Per-waypoint tasks should use `TaskManager.startTask()` with a `PerWaypointTaskMode`
- [ ] This gives per-waypoint tasks CommandManager retry support

### 3. Modes Not Running
**Symptoms:** Tasks assigned to waypoints never execute on arrival.

**Likely causes:**
- [ ] Check if `_checkNavStatus()` in HudScreen is detecting arrivals (navStatus 603)
- [ ] Verify `TaskEngine.setCallback(this)` is called after robot connects
- [ ] Confirm `executeForWaypoint()` is being invoked
- [ ] Add debug logging to trace the callback chain

**Debug steps:**
```dart
// In hud_screen.dart _checkNavStatus():
debugPrint('HUD: navStatus=$navStatus, navigatingTo=$_navigatingTo');

// In task_engine.dart executeForWaypoint():
debugPrint('TaskEngine: executeForWaypoint($waypoint) - hasMode=${hasMode(waypoint)}');
```

---

## Feature Requests

### 4. Beep Loudly on POI/Delivery Arrival
**Request:** Play a loud "beep boop" sound when robot arrives at a POI or Delivery waypoint.

**Implementation:**
- [ ] Add `announceArrival(String waypoint, {bool playBeep = true})` to AudioAnnouncer
- [ ] Call `tabletPlaySound('arrival_beep')` before TTS announcement
- [ ] Add arrival sound handling in RelayService.kt (`tablet_play_sound` with type `arrival_beep`)
- [ ] Create loud beep-boop audio asset or use Android ToneGenerator

**Files to modify:**
- `flutter_app/lib/services/audio_announcer.dart`
- `relay_app/app/src/main/java/com/smait/robotrelay/service/RelayService.kt`

### 5. Rename "Tour" to "Sequence" in Left Sidebar
**Location:** `hud_screen.dart` left panel tab label

**Fix:**
- [ ] Line 868: Change `label: 'TOUR'` to `label: 'SEQ'` or `'SEQUENCE'`
- [ ] Update any other "Tour" references in UI labels

---

## Conceptual Model Clarification

### Tasks vs Modes (Current Understanding)

**WRONG (current implementation):**
- "Modes" are assigned to waypoints
- Modes contain steps that execute

**CORRECT (target model):**

**Tasks** = What to do at a location
- Actions: Speak, Display, Wait, Navigate, Return
- Assigned to: Waypoints under conditions (arrival/departure)
- Example: "When arriving at Kitchen, speak 'Food ready'"

**Modes** = How/When to execute groups of tasks
- Timing: Sequence (serial), Parallel, Conditional
- Example: "Delivery Mode" = navigate -> speak -> wait for pickup -> return

**Waypoint Assignments** = Task + Condition + Waypoint
- Condition: OnArrival, OnDeparture, OnBlocked, Manual
- Example: Kitchen + OnArrival + SpeakTask("Food ready")

### Refactoring Plan

```
Current:
TaskMode (data) --> TaskEngine.assignMode(waypoint, modeId)
                            |
                     executeForWaypoint() --> steps execute

Target:
Task (what) + Condition (when) + Waypoint (where)
                            |
            WaypointTaskAssignment stored in TaskEngine
                            |
            On condition met -> TaskManager.startTask()
                            |
            TaskMode.onStart() -> Execute with retry support
```

---

## gRPC Resilience Consideration

### Current WebSocket Issues
- Single connection point of failure
- No automatic reconnection with state recovery
- No message acknowledgment/retry at protocol level

### gRPC Benefits
- Built-in streaming with flow control
- Automatic retries with exponential backoff
- Protobuf message serialization (type-safe, smaller)
- Bidirectional streaming for real-time updates
- Health checks and keepalives

### Implementation Plan
- [ ] Define `.proto` files for robot commands and status
- [ ] Generate Dart/Kotlin code from protos
- [ ] Create `GrpcRobotClient` alongside `RosbridgeClient`
- [ ] Add gRPC server to relay app
- [ ] Implement connection recovery with state sync

**Proto structure:**
```protobuf
service RobotControl {
  rpc Navigate(NavigateRequest) returns (NavigateResponse);
  rpc SendVelocity(VelocityCommand) returns (Empty);
  rpc StreamStatus(Empty) returns (stream RobotStatus);
  rpc StreamMap(Empty) returns (stream MapData);
}
```

---

## UI Fixes

### 6. Left Panel Tab Labels
- [ ] "TOUR" -> "SEQ" (Sequence)
- [ ] Consider icon-only tabs if space constrained

### 7. Sequence Editor Cleanup
- [ ] Rename `TourRunnerWidget` to `SequenceRunnerWidget`
- [ ] Update comments referencing "tour"

---

## Immediate Action Items (Priority Order)

1. ~~**Fix TaskMode naming collision**~~ ✅ DONE - Renamed to WaypointTask
2. **Add debug logging to trace why modes don't run** - Logging added
3. ~~**Add arrival beep sound**~~ ✅ DONE - `announceArrival()` in AudioAnnouncer
4. ~~**Rename Tour -> Sequence in sidebar**~~ ✅ DONE - Changed to "SEQ"
5. **Test mode execution end-to-end**
6. ~~**Add built-in WaypointTask examples**~~ ✅ DONE - Comic, Greeter, Busser, Emergency, TourStop
7. ~~**Add example Sequence factories**~~ ✅ DONE - Tour, Comic, Delivery, Busser, Emergency, Patrol, Greeter

---

## Files Reference

| File | Purpose | Issues |
|------|---------|--------|
| `task_mode.dart` | Task definitions + execution base | **TWO CLASSES SAME NAME** |
| `task_engine.dart` | Per-waypoint assignments | No TaskManager integration |
| `sequence_mode.dart` | Multi-waypoint sequences | Has both old/new execution paths |
| `sequence_task_mode.dart` | Sequence execution with retry | Good - uses CommandManager |
| `hud_screen.dart` | Main UI | "Tour" labels need rename |
| `audio_announcer.dart` | TTS and sounds | Needs arrival beep |
| `rosbridge_client.dart` | WebSocket client | Add tablet arrival sound |
| `RelayService.kt` | Android relay | Handle arrival_beep sound |

---

## Testing Checklist

- [ ] Create a new waypoint task assignment
- [ ] Navigate to that waypoint
- [ ] Verify task executes on arrival (check debug logs)
- [ ] Test sequence with multiple stops
- [ ] Verify countdown timer shows correctly
- [ ] Test pause/resume/stop controls
- [ ] Verify beep plays on arrival
- [ ] Test blocked path escalation still works

---

## In Progress
- [ ] Fix Flutter <-> Relay WebSocket connection bouncing
  - Added 60s socket timeout
  - Added server-side ping every 10s
  - Added ping/pong message handling
  - Testing...

## Completed
- [x] AWS Fleet Config backend deployed
- [x] Fleet API client in relay app
- [x] Fleet API client in Flutter app
- [x] Google Cloud TTS integration with caching
- [x] Tour/Sequence Mode implementation
  - SequenceMode data model with Sequence and SequenceStop classes
  - SequenceManager for saving/loading/executing sequences
  - SequenceEditor UI widget for creating and editing sequences
  - SequenceTaskMode with CommandManager for reliable navigation
  - Supports: speak text, display URL/image at each stop
  - Reorderable stops with drag-and-drop
- [x] Enhanced sequence progress overlay in HUD
  - Circular countdown timer with phase colors
  - Phase badge (Navigating/Arriving/Speaking/Displaying/Waiting)
  - Stop progress bar
  - Pause/Resume/Stop/Skip controls
- [x] Task/Mode Architecture Documentation
  - Architecture chart in README.md
  - 7 user stories with detailed flows (Delivery, Comic, Tour, Busser, Emergency, Teleop, Greeter)
  - Built-in WaypointTask examples in task_engine.dart
  - Example Sequence factories in sequence_mode.dart
- [x] TaskMode naming collision fix
  - Renamed data model TaskMode → WaypointTask
  - Renamed WaypointModeAssignment → WaypointTaskAssignment
  - Abstract TaskMode kept as execution base class
- [x] Arrival beep sounds
  - Added `announceArrival()` to AudioAnnouncer
  - Added `onArrivalAnnouncement` callback to sequence execution
  - Added arrival/delivery tones in RelayService.kt
- [x] Renamed Tour → Sequence in sidebar (SEQ)
