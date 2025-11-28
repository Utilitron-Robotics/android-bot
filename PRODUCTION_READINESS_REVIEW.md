# TourBot Production Readiness Review

**Date:** November 2024
**Reviewer:** Codebase Analysis
**Target Platform:** Android tablets on service droids (Tibo, Orin Nano, Raspberry Pi bases)

---

## Executive Summary

The TourBot Android app is a solid foundation with modern architecture (MVVM, Hilt DI, Jetpack Compose, Kotlin Coroutines). However, several **critical bugs** and **production-readiness gaps** need to be addressed before deployment to service droids.

### Priority Levels
- **P0 (Critical):** Blocks production deployment
- **P1 (High):** Causes significant user-facing issues
- **P2 (Medium):** Should fix before wide rollout
- **P3 (Low):** Nice to have improvements

---

## CRITICAL BUGS (P0)

### 1. Test Mode Does Not Work Properly

**File:** `TourManager.kt:369-448`
**Issue:** The `waitForArrival()` function uses `_sharedStatusFlow` which is populated by collecting from `tourRepository.observeStatus()`. In test mode, `FakeTourRepository` returns a `StateFlow` that only emits when navigation state changes.

**Root Cause:** The `FakeTourRepository.goTo()` method correctly updates status to 601 (moving) then 603 (arrived), BUT the `TourManager` calls `goTo()` and then immediately starts waiting on `_sharedStatusFlow`. Due to timing, the initial 601 emission may be missed, and more critically:

```kotlin
// FakeTourRepository.kt:46-60
override fun goTo(poi: String) {
    navigationJob?.cancel()
    navigationJob = coroutineScope.launch {
        _robotStatus.update { it.copy(navStatus = 601, ...) }  // Emits 601
        delay(2000)
        _robotStatus.update { it.copy(navStatus = 603, ...) }  // Emits 603
    }
}
```

The `observeStatus()` returns `_robotStatus.asStateFlow()`, which is a **StateFlow**. The `_sharedStatusFlow` in `TourManager` is a **SharedFlow with replay=0**. If the status collector hasn't started when the StateFlow emits, values are lost.

**Additionally:** The `waitForArrival()` logic at line 395-401 ignores stale 603 before movement started, but if the initial state is 600 (idle) and then jumps to 603, it may be treated as stale even though it's the real arrival signal in test mode.

**Fix Required:**
1. In `FakeTourRepository`, emit an initial state burst or use a proper event mechanism
2. Add delay after `goTo()` before starting to collect, OR
3. Change `FakeTourRepository` to emit 600 → 601 → 603 with proper timing that aligns with the collector startup

---

### 2. Start Script Plays Twice / Tour Repeats Introduction

**File:** `TourManager.kt:141-159`
**Issue:** The tour logic plays the "start" script at line 142, then iterates through `waypointIds` at line 145. Looking at the default waypoints:

```kotlin
// TourConfigRepository.kt:34-43
private val defaultWaypoints = listOf(
    "empty_1",
    "armin",
    "empty_2",
    "opendroids",
    "utilitron",
    "emerson",
    "avatar",
    "end"
)
```

The `playScriptAtLocation("start", ...)` is called BEFORE the waypoint loop. This is correct. However, if the user saved waypoints that include "start" in the list, it would play twice.

**More likely cause:** The `startTour()` function at line 68-76:

```kotlin
fun startTour() {
    tourJob?.cancel()
    _tourState.value = TourState.Idle  // This resets state
    // ...
    tourJob = tourScope.launch {
        runTour()
    }
}
```

If the button is double-tapped or if there's a race condition in the UI, `startTour()` could be called multiple times before the first `tourJob` properly starts.

**Additional Issue:** The tour flow plays "start" script without navigation (correct), but then navigates to each waypoint including `empty_1`. If `empty_1` is supposed to be the starting position, navigating there might trigger redundant movement.

**Fix Required:**
1. Add debouncing/guard in `startTour()` to prevent double execution
2. Consider using `tourJob?.let { if (it.isActive) return }` at the start
3. Review if "start" position should be excluded from navigation waypoints

---

### 3. MasterTourRepository Test Mode Switch is Broken

**File:** `MasterTourRepository.kt:30-48`
**Issue:** The `connect()` function wraps everything in a `scope.launch {}` which makes it asynchronous. When `setTestMode()` is called, it updates `activeRepository`, but any in-flight operations continue using the old repository reference captured in their closure.

```kotlin
override fun connect(url: String) {
    scope.launch {  // <-- This is async
        if (_isInTestMode.value) {
            activeRepository = fakeRepository
            activeRepository.connect(url)
        } else {
            // ...
        }
    }
}
```

**More critically:** When `TourManager` injects `TourRepository`, it gets `MasterTourRepository` via DI. The `TourManager` calls methods on it throughout the tour. If test mode is toggled mid-tour, subsequent calls go to the wrong repository.

**The real bug:** The `TourManager` doesn't inject `MasterTourRepository` directly - it injects `TourRepository`. So it has no way to know about test mode changes at runtime. The `setTestMode()` call from the UI only affects `MasterTourRepository.activeRepository`, but any flows/collectors already established continue pointing to the old repository's flows.

**Fix Required:**
1. The `observeStatus()` and `getBatteryLevel()` should be delegated to the active repository dynamically, not return a fixed reference
2. Consider making test mode a startup-only configuration, not runtime-switchable during tours

---

## HIGH PRIORITY BUGS (P1)

### 4. Caption Text Not Displaying for Pre-recorded Audio

**File:** `AudioPlayer.kt:59-97`
**Issue:** When playing pre-recorded audio via `play()`, the caption is set once at the start:

```kotlin
suspend fun play(resourceId: Int, caption: String = "") = suspendCoroutine<Unit> { cont ->
    stop(releaseMedia = true)
    _captionText.value = caption  // Set once, entire script
    // ... MediaPlayer setup
}
```

The entire script is shown immediately, not word-by-word as speech progresses. This is different from TTS mode which uses `onRangeStart` for word-by-word captions.

**Fix Required:**
- Implement time-synced captions for pre-recorded audio (e.g., using subtitle files or estimated WPM timing)
- Or accept this as a design choice and document it

---

### 5. Tour State Not Reset to Idle After Completion

**File:** `TourManager.kt:162-168`
**Issue:** After tour completion:

```kotlin
_tourState.value = TourState.Completed
audioPlayer.speak("Tour completed.")
// ...
cleanupAndDisconnect()
```

The state is `Completed`, not `Idle`. Looking at `MainScreen.kt:87`:

```kotlin
if (tourState is TourState.Idle || tourState is TourState.Completed || tourState is TourState.Error) {
    Button(onClick = { tourManager.startTour() }, ...) {
        Text("Start Tour")
    }
}
```

This allows starting a new tour from Completed state. However, `startTour()` resets to `Idle` before launching. The issue is if there's a delay between completion and the user wanting to restart - the UI shows "Tour Completed" indefinitely. Consider adding auto-reset after a timeout or explicit reset button.

---

### 6. Audio Amplitude for MediaPlayer is Fake

**File:** `AudioPlayer.kt:178-196`
**Issue:**

```kotlin
private fun startAmplitudePolling(isTts: Boolean) {
    amplitudeJob = scope.launch {
        while (isActive) {
            val currentAmplitude = if (isTts) {
                Random.nextInt(500, 2000)  // Fake random for TTS
            } else {
                1000  // Placeholder for MediaPlayer amplitude
            }
            // ...
        }
    }
}
```

Neither TTS nor MediaPlayer provides real amplitude. The lip sync face animation relies on `amplitude` but gets:
- TTS: Random values (500-2000) - fake animation
- MediaPlayer: Fixed 1000 - no lip sync at all

**Fix Required:**
- Use Android's `Visualizer` API (requires RECORD_AUDIO permission - already granted)
- Or use `MediaPlayer.getAudioSessionId()` with Visualizer to get real FFT/waveform data
- For TTS, the random approach is acceptable but should be documented

---

### 7. WebSocket Connection Not Thread-Safe

**File:** `RobotClient.kt:50-61`
**Issue:** The `connectionResult` is recreated each call:

```kotlin
suspend fun tryConnect(url: String): Boolean {
    if (isConnected.value) return true
    connectionResult = CompletableDeferred()  // Race condition here
    val request = Request.Builder().url(url).build()
    webSocket = client.newWebSocket(request, createListener())
    // ...
}
```

If two coroutines call `tryConnect()` simultaneously, the `connectionResult` gets overwritten and the first caller's await() may never complete or complete with wrong result.

**Fix Required:**
- Use a `Mutex` or synchronized block around connection logic
- Or use `compareAndSet` patterns for thread safety

---

## MEDIUM PRIORITY ISSUES (P2)

### 8. Waypoint Order Lost on Save

**File:** `TourConfigRepository.kt:85-89`
**Issue:**

```kotlin
suspend fun saveWaypoints(waypoints: List<String>) {
    context.dataStore.edit { settings ->
        settings[waypointListKey] = waypoints.toSet()  // ORDER LOST!
    }
}
```

Converting a `List` to `Set` loses ordering. When loaded back via `waypointIds` flow, the order is undefined:

```kotlin
savedWaypoints.toList()  // Set.toList() - no guaranteed order
```

**Fix Required:**
- Use `stringPreferencesKey` with JSON serialization for ordered list
- Or use comma-separated string and split/join

---

### 9. No Error Handling for Missing Audio Resources

**File:** `TourManager.kt:450-459`
**Issue:**

```kotlin
private suspend fun createWaypoint(id: String): Waypoint? {
    val resId = context.resources.getIdentifier(id.lowercase(), "raw", context.packageName)
    if (resId == 0) Log.w(TAG, "Audio resource not found for: $id")
    Waypoint(id, script.trim(), resId)  // Still creates waypoint with resId=0
}
```

The waypoint is created even with `resId = 0`. Then in `playScriptAtLocation`:

```kotlin
if (waypoint.audioResId != 0) {
    audioPlayer.play(waypoint.audioResId, waypoint.scriptContent)
} else {
    audioPlayer.speak(waypoint.scriptContent)  // Falls back to TTS
}
```

This is actually handled gracefully - TTS fallback. But for production, missing audio should be flagged as a deployment error, not silent fallback.

---

### 10. Pre-Speak Delay Not Used

**File:** `TourConfigRepository.kt:31` and `SettingsViewModel.kt`
**Issue:** The `preSpeakDelay` setting exists in settings but is never used in `TourManager` or `AudioPlayer`. This is dead code.

**Fix Required:**
- Implement the delay in `playScriptAtLocation()` before audio playback
- Or remove the setting if not needed

---

### 11. OkHttpClient Created Twice

**Files:** `NetworkModule.kt` and `RobotClient.kt`
**Issue:** NetworkModule provides a singleton `OkHttpClient`, but `RobotClient` creates its own:

```kotlin
// RobotClient.kt:36-39
private val client = OkHttpClient.Builder()
    .readTimeout(0, TimeUnit.MILLISECONDS)
    .pingInterval(20, TimeUnit.SECONDS)
    .build()
```

The injected client from NetworkModule is never used.

**Fix Required:**
- Inject the OkHttpClient into RobotClient
- Or remove the unused provider from NetworkModule

---

### 12. Unit Test Broken

**File:** `RealTourRepositoryTest.kt:53-67`
**Issue:**

```kotlin
@Test
fun `observeStatus sends subscribe and returns status flow`() = runTest {
    // ...
    val result = tourRepository.observeStatus().first()

    coVerify { robotClient.sendCommand(match {
        it.op == "subscribe" && it.topic == "/robot_status"
    }) }
}
```

The test expects `observeStatus()` to send a subscribe command, but looking at `RealTourRepository.observeStatus()`:

```kotlin
override fun observeStatus(): Flow<RobotStatusMessage> {
    return robotClient.messages
        .filter { it.topic == "/robot_status" && it.msg != null }
        .map { it.msg!! }
}
```

It does NOT send any command - that's done in `subscribeStatus()`. The test is incorrect.

---

### 13. PointCloudRenderer OpenGL Constants Magic Numbers

**File:** `PointCloudRenderer.kt:136-137`
**Issue:**

```kotlin
GLES20.glEnable(0x8861)  // GL_POINT_SPRITE_OES - not available in GLES20 constants
GLES20.glEnable(0x8642)  // GL_VERTEX_PROGRAM_POINT_SIZE
```

Using magic numbers instead of constants. These are OpenGL extensions that may not be available on all devices.

**Fix Required:**
- Check extension availability before use
- Use named constants or document the values

---

## LOW PRIORITY / IMPROVEMENTS (P3)

### 14. No Proguard/R8 Rules

**File:** `build.gradle.kts:27-29`
**Issue:**

```kotlin
release {
    isMinifyEnabled = false  // Should be true for production
    proguardFiles(...)
}
```

Minification disabled means larger APK and no obfuscation. For production:
- Enable minification
- Add rules for OkHttp, kotlinx.serialization, Hilt

---

### 15. No Offline/Airplane Mode Handling

The app doesn't gracefully handle network unavailability. For service droids that may temporarily lose connectivity, consider:
- Cached tour data
- Queue commands for retry
- Visual indicator of connection state

---

### 16. No Wake Lock for Long Tours

If the tablet screen turns off mid-tour, audio continues but face animation stops. Consider:
- Acquire `PARTIAL_WAKE_LOCK` during active tour
- Use `FLAG_KEEP_SCREEN_ON` in MainActivity

---

### 17. Memory Leak Potential in TourManager

**File:** `TourManager.kt:55`
**Issue:**

```kotlin
private val tourScope = CoroutineScope(Dispatchers.Main)
```

This scope is never cancelled. If `TourManager` is somehow recreated (shouldn't happen with @Singleton, but defensive coding), the old scope leaks.

**Fix Required:**
- Add cleanup method that cancels scope
- Or use `viewModelScope` pattern with proper lifecycle

---

### 18. No Instrumentation Tests

The project has unit tests but no Android instrumentation tests (`androidTest/`). For UI-heavy app with OpenGL rendering, consider:
- Compose UI tests
- Screenshot tests for face rendering
- Integration tests for WebSocket communication

---

### 19. README Documentation Outdated

**File:** `README.md`
**Issue:** References `android/` directory but the project structure is flat (files are at root, not in `android/` subfolder). Quick links are broken.

---

### 20. Hardcoded Default Robot URL

**File:** `SettingsManager.kt:24`
**Issue:**

```kotlin
preferences[KEY_ROBOT_URL] ?: "ws://10.42.0.1:9090"
```

This default is for Tibo robot. Consider:
- Build flavors for different robot bases
- First-run wizard to configure robot IP
- mDNS/Bonjour discovery for robots on network

---

## SECURITY CONSIDERATIONS

### 21. Cleartext Traffic Permitted

**File:** `network_security_config.xml`
**Issue:**

```xml
<base-config cleartextTrafficPermitted="true" />
```

WebSocket uses `ws://` (unencrypted). This is acceptable for local robot communication but:
- Document this is intentional for local network only
- Consider `wss://` support for future remote monitoring scenarios

### 22. No Certificate Pinning

For production deployments where the robot connects to cloud services, consider certificate pinning.

---

## DEPLOYMENT CHECKLIST

Before production deployment:

- [ ] Fix P0 bugs (Test mode, Start repeat, Test mode switch)
- [ ] Fix P1 bugs (Audio amplitude, WebSocket thread safety)
- [ ] Fix waypoint ordering (P2)
- [ ] Enable ProGuard/R8 minification
- [ ] Add proper error logging to remote service (Crashlytics, etc.)
- [ ] Test on actual hardware (Tibo base with Android tablet)
- [ ] Test with real robot WebSocket connection
- [ ] Verify all audio files load correctly
- [ ] Test tour flow end-to-end multiple times
- [ ] Add wake lock for long tours
- [ ] Create automated integration tests

---

## RECOMMENDED ARCHITECTURE IMPROVEMENTS

### Short Term (Before Production)
1. Fix the `FakeTourRepository` timing issues with explicit state machine
2. Add proper thread synchronization in `RobotClient`
3. Use JSON string for waypoint list to preserve order
4. Implement real audio amplitude visualization

### Medium Term (First Maintenance Release)
1. Add offline mode support
2. Implement proper error recovery and retry UI
3. Add telemetry/analytics for tour completion rates
4. Create admin mode for on-device configuration

### Long Term (Future Versions)
1. Support multiple robot bases via abstraction layer
2. Add multi-language tour support
3. Implement voice command activation ("Hey Robot, start tour")
4. Add obstacle detection UI feedback from robot sensors

---

## CONCLUSION

The codebase demonstrates solid Kotlin/Android engineering practices. The main blocking issues are:

1. **Test mode broken** - FakeTourRepository timing
2. **Start script repeat** - Possible race condition or waypoint list issue
3. **Test mode runtime switching** - Flow subscription doesn't update

These are fixable with targeted changes. The app is approximately **75% production-ready** and could be deployed after addressing P0/P1 issues.
