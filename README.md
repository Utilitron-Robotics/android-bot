# 🤖 Android TourBot

This repository hosts the **Android Native** implementation of the TourBot application.

> **Note:** The original Python implementation (FastAPI + WebSockets) has been moved to the [`legacy-python`](../tree/legacy-python) branch. Please check that branch for the legacy backend, API adapters, and web UI code.

## 📱 About This Project

TourBot is a modular robot tour application designed to run directly on Android-based robot platforms (or Android tablets attached to robots). It guides robots through predefined waypoints with audio narration, leveraging the Android SDK for native performance and UI integration.

## 📂 Project Structure

- **`android/`**: Contains the complete Android Studio project.
  - `app/`: Main application module.
  - `deploy.sh`: Deployment script for installing the APK on connected devices.
  - `HANDOFF_TO_REAL.md`: Instructions for transitioning from emulators/mock data to real robot hardware.

## 🚀 Getting Started

1. Open the `android/` directory in **Android Studio**.
2. Sync Gradle project.
3. Build and run on an emulator or connected Android device.

For detailed Android development instructions, see [`android/README.md`](android/README.md).

## 🔗 Legacy Python Code

If you are looking for the previous Python-based architecture (BaseRobotApplication, API adapters, etc.), please switch to the `legacy-python` branch:

```bash
git checkout legacy-python
