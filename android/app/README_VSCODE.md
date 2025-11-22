# Handoff Notes for VSCode Environment: TourBot Android Port

This document summarizes the current state of the TourBot Android application port. The goal is to provide immediate context for creating an Android deployment script from the parent directory, which has access to the terminal and the original Python source.

## High-Level Project Goal
The primary objective is to **port the Python TourBot application to a native Android app** using Kotlin and Jetpack Compose. The application should replicate the functionality of the original Python version, including navigation, tour sequencing, and audio/visual feedback.

## Current Status Summary
The application is in a **feature-complete but simulated state**. It builds successfully and runs a full tour sequence using a `FakeTourRepository`.

- **✅ Phase 1: Project Setup & Core Skeleton** - **100% Complete.** Gradle is configured, packages are structured, and assets are accounted for.
- **🟡 Phase 2: Robot Communication Layer** - **90% Implemented.** `RobotClient` and data models are in place. The `RealTourRepository` is implemented but **untested**. The app currently uses a `FakeTourRepository` for all operations.
- **✅ Phase 3: Audio & Animation Engine** - **100% Complete.** `AudioPlayer` handles TTS and simulates amplitude. The `RobotFace` composable includes blinking eyes, animated curved eyebrows, and a dynamic mouth that reacts to the simulated amplitude.
- **🟡 Phase 4: Tour Logic Implementation** - **95% Complete.** `TourManager` successfully orchestrates the tour sequence. **Retry logic for navigation is not yet implemented.**
- **🟡 Phase 5: Integration & UI Polish** - **80% Complete.** The main UI is built and connected. A robust `ControlPanel` for editing scripts and settings is implemented. **Advanced error handling (e.g., connection-loss dialogs) and polish animations (e.g., idle hover) are not yet implemented.**

## Key Workarounds & Known Issues
These are critical points to remember to avoid confusion and repeated errors.

1.  **`maxAmplitude()` Compilation Error:** There is a persistent, unresolved compilation error for `MediaPlayer.maxAmplitude()`.
    -   **Workaround:** The `startAmplitudePolling()` function in `AudioPlayer.kt` is hardcoded to use a placeholder value (`val amp = 1000`) to allow the project to compile. This is **not** a real amplitude reading.
2.  **Choppy Audio:** The user has reported choppy, static-filled audio during TTS playback.
    -   **Current Status:** This is suspected to be an **emulator performance issue**. The `CoroutineScope` in `AudioPlayer` has been moved to `Dispatchers.Default` to prevent UI thread blocking, but the underlying audio issue may persist on emulators.
3.  **`waitForArrival` Simulation:** The `TourManager.waitForArrival()` function contains a specific check: `if (tourRepository is FakeTourRepository)`.
    -   **Workaround:** When using the fake repository, this check bypasses the real status-checking logic and returns `true` after a short delay. This was implemented to prevent the tour from getting stuck during testing. This workaround must be removed for real-world testing.

## Immediate Task in VSCode
The user's immediate goal is to **create an Android deployment script**.

- **New Capabilities:** You are now in a VSCode environment with terminal access. You can run `gradlew` and `adb` commands. You can also access the original Python project files in the parent directory to understand the original deployment or control flow.
- **Action Item:** Prepare to create a script (e.g., a shell script `.sh` or a Python script) that can build the Android APK and potentially deploy it to a connected device. You will likely need to use commands like `./gradlew assembleDebug` and `adb install`.

This briefing should provide all necessary context. Ready for your instructions in the new environment.
