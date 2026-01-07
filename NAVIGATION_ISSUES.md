# Navigation Reliability Issues Analysis

## 1. Split-Brain Retry Logic
Currently, retry logic is split between `CommandManager` and `SequenceTaskMode`:
- `CommandManager`: General-purpose command queue with `maxRetries` logic
- `SequenceTaskMode`: Implements its own `_retryNavigation` logic with `_navRetryCount` and `_maxNavRetries`
- **Conflict**: `SequenceTaskMode` explicitly queues commands with `maxRetries: 0` to bypass `CommandManager` logic, but then implements a redundant and potentially conflicting retry mechanism. `onNavStatus` logic manually acknowledges/completes commands in `CommandManager` while handling its own retries.

## 2. Loose State Machine
The navigation state machine in `SequenceTaskMode.onNavStatus` is too permissive:
- It relies on debouncing (`_retryDebounce`) rather than strict state transitions.
- It attempts to differentiate "real" failures from "expected" failures (like the initial 602 when cancelling a previous task) using loose boolean flags like `_hasStartedMoving`.
- There is no explicit state verification (e.g., verifying we are in `navigating` phase before processing nav events).

## 3. Event Routing Confusion
Navigation events (especially arrival `603`) are being routed through multiple paths:
- `SequenceExecutor.onNavStatusChanged` listens to `RobotConnection` and calls `SequenceManager.onArrived`.
- `SequenceTaskMode.onNavStatus` receives updates and calls `onArrived` internally.
- This dual-path routing causes race conditions where an arrival event might trigger logic in `SequenceExecutor` (which might advance the sequence) *and* in `SequenceTaskMode` (which might also try to advance or complete a step), leading to double-execution or skipped stops.

## 4. Proposed Fixes

### A. Centralize Retry Logic in `CommandManager`
- Refactor `SequenceTaskMode` to use `CommandManager`'s native retry capability.
- Remove `_retryNavigation`, `_navRetryCount`, and `_lastRetryTime` from `SequenceTaskMode`.
- Configure the `navigate` command with `maxRetries: 3` and let `CommandManager` handle the re-queueing on failure.
- `SequenceTaskMode` should only listen for `CommandStatus.failed` (final failure) to abort the sequence, or `CommandStatus.completed` (success) to proceed.

### B. Strict State Machine
- Implement a strict state check in `onNavStatus`:
  ```dart
  if (_phase != SequenceTaskPhase.navigating) {
    debugPrint('Ignoring nav status $status - not in navigating phase');
    return;
  }
  ```
- Use `CommandManager`'s state as the source of truth for command execution status.

### C. Unified Event Routing
- Disable `SequenceExecutor`'s direct handling of navigation status for sequence progression.
- `SequenceTaskMode` should be the *sole* authority for sequence progression based on navigation events when a sequence is active.
- `SequenceExecutor` should only act as a bridge to pass events to the active `TaskMode`.

## Implementation Plan
**RESOLVED: The following plan has been implemented as of Jan 7, 2026.**

1. **Refactor `SequenceTaskMode.dart`**:
   - [x] Remove manual retry logic.
   - [x] Update `_navigateToWaypoint` to use `maxRetries: 3` in `queueCommand`.
   - [x] Update `_onCommandManagerChanged` to handle command completion/failure instead of implementing retry logic.
   - [x] simplify `onNavStatus` to just update the command status (which `CommandManager` will then use to trigger retries or completion).

2. **Fix `SequenceExecutor.dart`**:
   - [x] Remove `onNavStatusChanged` logic that directly calls `SequenceManager.onArrived`.
   - [x] Ensure it purely forwards events if necessary, or relies on `TaskMode` listening directly to `RobotConnection` (which it already does via `onNavStatus`).

3. **Verify `SequenceManager.dart`**:
   - [x] Ensure it correctly delegates to the active `TaskMode`.

**Note:** This file is kept as a historical record of the navigation reliability fixes.

