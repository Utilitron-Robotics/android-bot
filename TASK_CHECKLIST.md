# Task Checklist (Re-ordered)

This checklist is based on the `IMPLEMENTATION_PLAN.md` file, with tasks re-ordered by complexity and inter-dependency.

## Phase 1: Core Refactoring (Foundation)

-   [ ] **Build Flavor Setup**
    -   [ ] Configure `prod` and `fake` build flavors in `app/build.gradle.kts`.
    -   [ ] Create `src/fake/java` and `src/prod/java` source sets.
-   [ ] **Create `Robot` Interface**
    -   [ ] Define `Robot` interface in `app/src/main/java/com/opendroids/tourbot/robot/Robot.kt`.
-   [ ] **Implement `Robot` Interface**
    -   [ ] Create `FakeRobot` class in `src/fake/java` and implement `Robot`.
    -   [ ] Create `RobotRobot` class in `src/prod/java` and implement `Robot`.
-   [ ] **Hilt Module for `Robot`**
    -   [ ] Create a Hilt module to provide the correct `Robot` implementation based on the build flavor.
-   [ ] **ViewModel Refactoring**
    -   [ ] Create `ConnectionViewModel`.
    -   [ ] Create `SettingsViewModel`.
    -   [ ] Create `TourViewModel`.
    -   [ ] Update `MainScreen` to use the new ViewModels.

## Phase 2: Deprecation and Cleanup

-   [ ] **Remove Old Test Mode Logic**
    -   [ ] Remove the `isInTestMode` flow from `MainViewModel`.
    -   [ ] Remove the test mode dialog (`showTestModeDialog`).
    -   [ ] Remove the `setTestMode` function.
-   [ ] **Remove `MasterTourRepository`**
-   [ ] **Consolidate Repositories**
    -   [ ] Delete `RealTourRepository` and `FakeTourRepository`.
    -   [ ] Decide on the fate of the `TourRepository` interface.

## Phase 3: UI/UX Enhancements

-   [ ] **Audio Visualization**
    -   [ ] Move `PointCloudFace` to a corner.
    -   [ ] Implement on-demand `RECORD_AUDIO` permission request.
-   [ ] **Settings Control Panel**
    -   [ ] Add carousel position setting.
-   [ ] **Destination Carousel**
    -   [ ] Create `DestinationCarousel` composable.
    -   [ ] Add carousel to `MainScreen`.
-   [ ] **New Tour Controls**
    -   [ ] Add "Pause" button.
    -   [ ] Add "Repeat Last" button.

---
I am ready to begin with the re-ordered Phase 1. Please confirm to proceed.
