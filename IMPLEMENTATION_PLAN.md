# Implementation and Refactoring Plan

This document outlines the plan to refactor the TourBot application to be more modular, robust, and feature-rich. The work is divided into three main phases.

---

## Phase 1: Core Refactoring (Foundation)

This phase focuses on strengthening the app's architecture, making it easier to test, maintain, and extend.

1.  **Build Flavor Setup:**
    *   Configure two build flavors in `app/build.gradle.kts`:
        *   `prod`: For the real robot implementation.
        *   `fake`: For a simulated robot, where all actions are logged and return success immediately. This will be the default for debugging and UI testing.
    *   Create `src/fake/java` and `src/prod/java` source sets.
    *   Move the `FakeTourRepository` logic into a new `FakeRobot` class in the `fake` source set.
    *   Move the `RealTourRepository` logic into a `PuduRobot` class in the `prod` source set.

2.  **Create `Robot` Interface:**
    *   Define a `Robot` interface in the `main` source set (`app/src/main/java/com/opendroids/tourbot/robot/Robot.kt`).
    *   This interface will define all possible robot actions and data flows:
        *   `fun connect(url: String): Flow<ConnectionStatus>`
        *   `fun disconnect()`
        *   `fun getStatus(): Flow<RobotStatusMessage>`
        *   `fun navigateTo(waypointId: String): Flow<NavigationStatus>`
        *   `fun speak(text: String): Flow<SpeechStatus>`
        *   `fun pause()`
        *   `fun resume()`
        *   `fun getWaypoints(): Flow<List<Waypoint>>`
    *   The `PuduRobot` and `FakeRobot` classes will implement this interface.
    *   A Hilt module will provide the correct `Robot` implementation based on the build flavor.

3.  **ViewModel Refactoring:**
    *   Break down the monolithic `MainViewModel` into smaller, more focused ViewModels:
        *   `TourViewModel`: Manages tour state, starting, pausing, and aborting tours. Depends on the `Robot` interface and `TourManager`.
        *   `SettingsViewModel`: Manages user settings, such as `robotUrl` and `showNerdData`. Depends on `SettingsManager`.
        *   `ConnectionViewModel`: Manages the connection status to the robot. Depends on the `Robot` interface.
    *   The `MainScreen` will be updated to use these new ViewModels.

---

## Phase 2: UI/UX Enhancements

This phase focuses on implementing the new user interface and experience features.

1.  **Destination Carousel:**
    *   Create a new composable, `DestinationCarousel`, that displays a horizontally scrollable list of waypoints.
    *   Each item in the carousel will be tappable, triggering a navigation command to the selected waypoint.
    *   The carousel will be placed at the bottom of the `MainScreen`.

2.  **Audio Visualization:**
    *   The `PointCloudFace` composable will be moved to a smaller box in the top-right corner of the screen.
    *   The `RECORD_AUDIO` permission request will be triggered only when this visualization is about to be displayed for the first time.

3.  **New Tour Controls:**
    *   Add "Pause" and "Repeat Last" buttons to the main screen's control area.
    *   The "Pause" button will call `tourViewModel.pauseTour()`.
    *   The "Repeat Last" button will re-trigger the last completed action (e.g., navigate to the last waypoint or repeat the last speech).

4.  **Settings Control Panel:**
    *   Add an option to the `ControlPanel` to configure the position of the `DestinationCarousel` (Top/Bottom).
    *   This setting will be saved using the `SettingsManager`.

---

## Phase 3: Deprecation and Cleanup

This phase focuses on removing old, now-redundant code.

1.  **Remove `MasterTourRepository`:**
    *   With the build flavor setup, the `MasterTourRepository` is no longer needed. All references to it will be removed.

2.  **Remove Old Test Mode Logic:**
    *   Remove the `isInTestMode` flow from the `MainViewModel`.
    *   Remove the test mode dialog (`showTestModeDialog`).
    *   Remove the `setTestMode` function.

3.  **Consolidate Repositories:**
    *   The `RealTourRepository` and `FakeTourRepository` will be fully replaced by the `PuduRobot` and `FakeRobot` classes. The old repository files will be deleted.
    *   The `TourRepository` interface may be absorbed into the new `Robot` interface, or it may be kept as a higher-level abstraction if needed. This will be decided during implementation.

---
This plan will be executed sequentially. I will start with Phase 1 to build a solid foundation, then move on to the UI/UX enhancements in Phase 2, and finally, clean up the old code in Phase 3.

I am ready to begin with Phase 1. Please confirm to proceed.
