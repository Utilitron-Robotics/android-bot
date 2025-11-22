# TourBot - Native Android Edition

🚀 **The TourBot project has migrated to a Native Android Application.**

This repository contains the source code for the TourBot application, now completely rewritten in Kotlin/Jetpack Compose to run directly on the robot's tablet. This architecture simplifies deployment, improves UI responsiveness, and removes the need for an intermediate Python server.

## 📱 Android Project

The complete Android project is located in the [`android/`](android/) directory.

**Quick Links:**
*   [**Getting Started & Architecture**](android/README.md) - How to build and run the app.
*   [**Switching to Real Robot**](android/HANDOFF_TO_REAL.md) - Instructions for moving from simulation to real hardware.
*   [**Deployment Script**](android/deploy.sh) - Automated build and install script.

## 🐍 Legacy Python Version

The original Python/FastAPI implementation has been archived. If you need to reference the original Python logic, adapters, or web UI, please access the **legacy-python** branch:

👉 **[Access Legacy Python Code (Branch: legacy-python)](../../tree/legacy-python)**

## 🛠️ Development

1.  **Open in Android Studio:**
    Open the `android` folder as an existing project in Android Studio (Ladybug or newer recommended).

2.  **Build & Deploy:**
    You can build via Android Studio or use the included helper script:
    ```bash
    ./android/deploy.sh
    ```

## 🤖 Robot Configuration

The app uses WebSockets to communicate with the robot base (ROS bridge).
By default, it is configured for the Android Emulator (`ws://10.0.2.2:9090`).

**To connect to a real robot:**
Follow the instructions in [**HANDOFF_TO_REAL.md**](android/HANDOFF_TO_REAL.md).
