# Android Migration Plan: TourBot

This document outlines the technical architecture and implementation plan for migrating the Python/FastAPI/Web TourBot to a native Android application using Kotlin and Jetpack Compose.

## 1. Architecture Overview

We will use a **Modern Android Development (MAD)** approach with **MVVM (Model-View-ViewModel)** architecture.

*   **Language:** Kotlin
*   **UI Toolkit:** Jetpack Compose
*   **Concurrency:** Kotlin Coroutines & Flow
*   **Networking:** OkHttp (WebSockets)
*   **DI:** Hilt (Dependency Injection)

### High-Level Layers
1.  **Data Layer (Model):** Handles robot communication and data management.
    *   `RobotConnectionManager`: Manages raw WebSocket connection.
    *   `RobotRepository`: Exposes high-level commands (`goTo`, `getBattery`) and status `Flow`s.
2.  **Domain Layer (Optional but recommended):** Encapsulates business logic.
    *   `TourManager`: The core state machine (replaces `apps/tour_bot.py`). Orchestrates the tour sequence.
3.  **UI Layer (View/ViewModel):**
    *   `TourViewModel`: Exposes UI state (Face emotion, current script, connection status) to Composable.
    *   `TourScreen`: Composable rendering the animated robot face.

## 2. Component Design

### A. Robot Communication (Porting `adapters/tibo`)
*   **Library:** `OkHttp` for WebSockets.
*   **JSON Parsing:** `Kotlinx.serialization` or `Gson`.
*   **Implementation:**
    *   `TiboClient` (Android) will implement `WebSocketListener`.
    *   Incoming messages will be emitted to a `SharedFlow<RobotMessage>`.
    *   **Status Handling:**
        *   `subscribe_status()` sends the JSON subscription payload.
        *   A `statusFlow` filters messages for topic `/robot_status`.
    *   **Navigation Logic:**
        *   `wait_until_arrival(destination)` becomes a suspend function that collects from `statusFlow` until a success/failure code (603/604 vs others) is received.

### B. Tour Logic (Porting `apps/tour_bot.py`)
*   **`TourManager` Class:** A generic class (injected as Singleton) to hold the tour state.
*   **State Machine:**
    ```kotlin
    sealed class TourState {
        object Idle : TourState()
        data class Running(val currentWaypoint: String, val progress: Int, val total: Int) : TourState()
        object Completed : TourState()
        data class Failed(val reason: String) : TourState()
    }
    ```
*   **The "Tour Loop" (Coroutine):**
    *   Instead of `asyncio.create_task`, launch a coroutine in `viewModelScope` (or a specific `Service` scope if background execution is critical).
    *   **Sequence:**
        1.  `robotRepo.connect()`
        2.  `robotRepo.getBatteryLevel()` (Check thresholds)
        3.  `playAudio("start")`
        4.  Loop through waypoints:
            *   `robotRepo.goTo(waypoint)`
            *   `robotRepo.waitUntilArrival(waypoint)`
            *   `playAudio(waypoint)` (Waits for completion)
        5.  `robotRepo.disconnect()`

### C. UI & Animation (Porting `ui/tour_display_v6.html`)
*   **Canvas & Compose:** The robot face will be drawn using Compose `Canvas`.
    *   **Face:** Rounded rect with gradient brush.
    *   **Eyes:** Custom Composables with `Animatable` offsets for "looking around".
    *   **Mouth:** A dynamic shape. Height/Width driven by audio amplitude.
*   **Animations:**
    *   **Idle:** `infiniteTransition` for floating/hovering effect.
    *   **Blink:** `LaunchedEffect` with random delays to toggle eye lid state.
    *   **Blur:** `Modifier.blur` (Android 12+) or custom render effect for "sleep" mode.
*   **Audio Visualization:**
    *   Use Android's `Visualizer` class (requires permission) OR simple amplitude monitoring from `MediaPlayer`/`ExoPlayer`.
    *   Map amplitude (0.0 - 1.0) to Mouth Height (e.g., 10dp to 50dp).

### D. Asset Management
*   **Scripts:** Move `assets/tour_scripts/*.txt` to `app/src/main/assets/tour_scripts/`. Read via `AssetManager`.
*   **Audio:** Move `assets/tour_audio/*.wav` to `app/src/main/res/raw/`.
    *   *Note:* Identifiers like `empty_1` are valid resource names in Android (`R.raw.empty_1`).

## 3. Implementation Phases

### Phase 1: Project Setup & Core Skeleton
*   [ ] Create new Android Project (Empty Compose Activity).
*   [ ] Configure Gradle (Hilt, Coroutines, OkHttp, Serialization).
*   [ ] Create package structure: `data`, `domain`, `ui`, `di`.
*   [ ] Copy audio assets to `res/raw`.
*   [ ] Copy scripts to `assets`.

### Phase 2: Robot Communication Layer
*   [ ] Implement `RobotConnectionManager` (OkHttp WebSocket wrapper).
*   [ ] Define JSON Data Models (`RobotMessage`, `NavStatus`, etc.).
*   [ ] Implement `RobotRepository` with `goTo`, `subscribeStatus`, `getBattery`.
*   [ ] **Test:** Create a simple UI with "Connect" and "Move" buttons to verify robot control.

### Phase 3: Audio & Animation Engine
*   [ ] Create `AudioManager`: Wraps `MediaPlayer`, handles playback, exposes `isSocketOpen` or `amplitudeFlow`.
*   [ ] Create `RobotFace` Composables:
    *   `Eye` (pupil movement, blinking).
    *   `Mouth` (reacts to `amplitudeFlow`).
    *   `Antenna` (idle animation).
*   [ ] **Test:** Verify face animates and moves to audio.

### Phase 4: Tour Logic Implementation
*   [ ] Implement `TourManager`.
*   [ ] Port the "Main Tour Loop" logic from Python to Kotlin Coroutines.
*   [ ] Implement retry logic for navigation failures.
*   [ ] Handle state updates (expose `TourState` to UI).

### Phase 5: Integration & UI Polish
*   [ ] Connect `TourManager` to `TourViewModel`.
*   [ ] Build the Main Screen (Face + Start/Stop controls).
*   [ ] Implement "Settings" screen (IP address configuration).
*   [ ] Add error handling (Snackbars/Dialogs for connection loss).
*   [ ] Final polish of animations and transitions.

## 4. Detailed Mapping

| Feature | Python/Web Source | Android Target |
| :--- | :--- | :--- |
| **Networking** | `websockets` (Python) | `OkHttp` (Kotlin) |
| **Async** | `asyncio` | `Kotlin Coroutines` |
| **JSON** | `json` (stdlib) | `Kotlinx.serialization` |
| **State** | `TourState` class | `StateFlow<TourState>` |
| **UI Rendering** | HTML/CSS (DOM) | Jetpack Compose (Canvas) |
| **Animations** | CSS `@keyframes` | Compose `Animatable` / `Transition` |
| **Audio** | `Audio` (JS) / `Web Audio API` | `MediaPlayer` / `ExoPlayer` |
| **Config** | `os.getenv` / `.env` | `DataStore` (Preferences) |

## 5. Dependencies (libs.versions.toml)
*   `androidx.compose.ui:ui`
*   `androidx.compose.material3:material3`
*   `com.squareup.okhttp3:okhttp`
*   `org.jetbrains.kotlinx:kotlinx-coroutines-android`
*   `com.google.dagger:hilt-android`
*   `org.jetbrains.kotlinx:kotlinx-serialization-json`
*   `androidx.lifecycle:lifecycle-viewmodel-compose`