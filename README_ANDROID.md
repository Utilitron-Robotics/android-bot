# TourBot Android Application

This is the native Android implementation of the TourBot application, migrated from the original Python/Web version.

## Prerequisites

*   **Android Studio:** Ladybug | 2024.2.1 or newer recommended.
*   **JDK:** Java 17 or newer (usually bundled with Android Studio).

## Getting Started

1.  **Open the Project:**
    *   Launch Android Studio.
    *   Select **Open**.
    *   Navigate to the `android` folder inside the `tour-bot-main` repository (e.g., `/Users/crackerjack/dev/GitHub/tour-bot-main/android`).
    *   Click **Open**.

2.  **Sync Gradle:**
    *   Android Studio should automatically detect the Gradle build files.
    *   If it doesn't, or if you see errors, click the **Sync Project with Gradle Files** button (elephant icon) in the toolbar.
    *   Wait for the sync to complete successfully.

3.  **Run the App:**
    *   Select an emulator or connect a physical Android device.
    *   Click the **Run** button (green play icon) or press `Shift + F10`.

## Configuration

### Robot Connection

The application connects to the robot via WebSockets.

-   **Emulator Default:** `ws://10.0.2.2:9090` (Accesses the host computer's localhost)
-   **Real Device:** You **MUST** update the `ROBOT_URL` to match your robot's actual IP address on the network.

**To Change the Robot IP:**

1.  Open `app/src/main/java/com/opendroids/tourbot/logic/TourManager.kt`.
2.  Locate the constant `ROBOT_URL` near the top of the file.
3.  Update it to your robot's address (e.g., `ws://192.168.1.100:9090`).

```kotlin
// Example for a real robot connection
private const val ROBOT_URL = "ws://192.168.1.100:9090"
```

## Architecture

This app uses Modern Android Development (MAD) practices:

*   **Language:** Kotlin
*   **UI:** Jetpack Compose
*   **Architecture Pattern:** MVVM (Model-View-ViewModel)
*   **Dependency Injection:** Hilt
*   **Concurrency:** Coroutines & Flow
*   **Networking:** OkHttp (WebSockets) & Kotlinx Serialization

## Project Structure

*   `app/src/main/java/com/opendroids/tourbot/`
    *   `data/`: Data models and remote clients (RobotClient).
    *   `logic/`: Core business logic (TourManager state machine).
    *   `ui/`: Jetpack Compose UI (MainScreen, RobotFace) and AudioPlayer.
*   `app/src/main/assets/tour_scripts/`: Text files containing the speech for each waypoint.
*   `app/src/main/res/raw/`: Audio WAV files for the tour.