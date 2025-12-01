# Task Checklist

This checklist is based on the `IMPLEMENTATION_PLAN.md` file.

## Phase 1: Core Refactoring (Foundation)

-   [ ] **Build Flavor Setup**
    -   [ ] Configure `prod` and `fake` build flavors in `app/build.gradle.kts`.
    -   [ ] Create `src/fake/java` and `src/prod/java` source sets.
    -   [ ] Create `FakeRobot` class in `src/fake/java`.
    -   [ ] Create `PuduRobot` class in `src/prod/java`.
-   [ ] **Create `Robot` Interface**
    -   [ ] Define `Robot` interface in `app/src/main/java/com/opendroids/tourbot/robot/Robot.kt`.
    -   [ ] Implement `Robot` interface in `PuduRobot` and `FakeRobot`.
    -   [ ] Create a Hilt module to provide the correct `Robot` implementation.
-   [ ] **ViewModel Refactoring**
    -   [ ] Create `TourViewModel`.
    -   [ ] Create `SettingsViewModel`.
    -   [ ] Create `ConnectionViewModel`.
    -   [ ] Update `MainScreen` to use the new ViewModels.

## Phase 2: UI/UX Enhancements

-   [ ] **Destination Carousel**
    -   [ ] Create `DestinationCarousel` composable.
    -   [ ] Add carousel to `MainScreen`.
-   [ ] **Audio Visualization**
    -   [ ] Move `PointCloudFace` to a corner.
    -   [ ] Implement on-demand `RECORD_AUDIO` permission request.
-   [ ] **New Tour Controls**
    -   [ ] Add "Pause" button.
    -   [ ] Add "Repeat Last" button.
-   [ ] **Settings Control Panel**
    -   [ ] Add carousel position setting.

## Phase 3: Deprecation and Cleanup

-   [ ] **Remove `MasterTourRepository`**
-   [ ] **Remove Old Test Mode Logic**
-   [ ] **Consolidate Repositories**
    -   [ ] Delete `RealTourRepository` and `FakeTourRepository`.
    -   [ ] Decide on the fate of the `TourRepository` interface.

---
I am ready to begin with Phase 1. Please confirm to proceed.
