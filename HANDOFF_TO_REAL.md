# 🤖 Handoff to Real Robot Mode

> **Note**: This document describes an older process for the initial Android migration. While the principles of switching between simulation and real robot environments are still relevant, the specific code paths (especially DI modules) may have evolved in the `flutter_app` and `relay_app`. Refer to `README.md` for current configuration instructions.

## Executive Summary

The Android application is currently configured in **Simulation Mode**. This allows developers to run the app on an emulator or device without connecting to physical robot hardware, using a `FakeTourRepository` to simulate robot responses and navigation updates.

To deploy this application to control a **real robot**, you must reconfigure the dependency injection and network settings. Follow the steps below to switch to **Real Robot Mode**.

---

## Step 1: Dependency Injection Switch

We need to swap the data source implementation from the fake simulation to the real network repository.

1.  Open the following file:
    [`app/src/main/java/com/opendroids/tourbot/di/RepositoryModule.kt`](app/src/main/java/com/opendroids/tourbot/di/RepositoryModule.kt)

2.  **Comment out** the `FakeTourRepository` binding.
3.  **Uncomment** the `RealTourRepository` binding.

**Current Code (Simulation):**
```kotlin
// Temporarily bind the FakeTourRepository for testing
@Binds
@Singleton
abstract fun bindTourRepository(
    fakeTourRepository: FakeTourRepository
): TourRepository

// The RealTourRepository binding is commented out for now
// @Binds
// @Singleton
// ...
```

**Updated Code (Real Robot):**
```kotlin
// Temporarily bind the FakeTourRepository for testing
// @Binds
// @Singleton
// abstract fun bindTourRepository(
//    fakeTourRepository: FakeTourRepository
// ): TourRepository

// The RealTourRepository binding is commented out for now
@Binds
@Singleton
abstract fun bindRealTourRepository(
    realTourRepository: RealTourRepository
): TourRepository
```

---

## Step 2: Network Configuration

Ensure the application points to the correct WebSocket URL for your physical robot.

*Note: The network configuration is managed by `SettingsManager`, not `TourManager`.*

1.  Open the settings manager:
    [`app/src/main/java/com/opendroids/tourbot/data/settings/SettingsManager.kt`](app/src/main/java/com/opendroids/tourbot/data/settings/SettingsManager.kt)

2.  Locate the default value in the `robotUrl` flow mapping.

3.  Update the IP address and port to match your robot's configuration.
    *   **Emulator Default:** `ws://10.0.2.2:9090` (connects to localhost of the host machine)
    *   **Real Robot Example:** `ws://192.168.1.100:9090` (replace with actual static IP)

```kotlin
// In SettingsManager.kt
val robotUrl: Flow<String> = settingsDataStore.data
    .map { preferences ->
        // CHANGE THIS VALUE
        preferences[KEY_ROBOT_URL] ?: "ws://192.168.1.100:9090" 
    }
```

> **Tip:** This value can also be changed at runtime in the app's Settings screen, but updating the default ensures it works immediately upon fresh install.

---

## Step 3: Optional Logic Cleanup

The `TourManager` contains a safety check that auto-completes navigation when using the fake repository. While safe to keep (as it checks `is FakeTourRepository`), removing it keeps the code clean.

1.  Open `TourManager`:
    [`app/src/main/java/com/opendroids/tourbot/logic/TourManager.kt`](app/src/main/java/com/opendroids/tourbot/logic/TourManager.kt)

2.  Locate the `waitForArrival` function and the following block:

```kotlin
// Temporary workaround for FakeTourRepository to immediately simulate arrival
if (tourRepository is FakeTourRepository) {
    Log.d(TAG, "waitForArrival: Using FakeTourRepository, simulating immediate arrival for $destinationName")
    delay(500) // Small delay to simulate some "travel" time
    return true
}
```

3.  You may delete this block entirely once you have confirmed Step 1 is working.

---

## Step 4: Deploying

Use the included deployment script to build and install the application on your device.

1.  Connect your Android device via USB.
2.  Ensure USB Debugging is enabled on the device.
3.  Run the deployment script from the project root:

```bash
./deploy.sh
```

This script will:
*   Verify your environment (Java, ADB).
*   Build the Debug APK.
*   Install it on the connected device.
*   Launch the main activity.