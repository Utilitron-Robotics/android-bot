# TourBot - Multi-Platform Service Droid Application

A cross-platform application for service droids, interactive kiosks, and tour guide robots. Designed to run on Android tablets, iOS devices, and desktop platforms mounted on robot bases.

## 📱 Applications

### Flutter App (Cross-Platform) - `flutter_app/`
Universal robot controller with **dynamic UI generated from rosbridge introspection**.

- **Auto-discovery**: Connects to robot and discovers available topics, services, and parameters
- **Dynamic UI**: Generates appropriate controls based on what the robot supports
- **Waypoint Navigation**: Tap buttons or enter custom waypoints
- **Voice Control**: "Go to kitchen", "Stop" (on supported devices)
- **Manual Control**: Virtual joystick for direct velocity control
- **Cross-platform**: Android, iOS, Windows, macOS, Linux

```bash
cd flutter_app
flutter pub get
flutter run
```

### Android Native App - `app/`
Native Kotlin/Jetpack Compose application with advanced features.

- **Animated Robot Face**: Point cloud 3D face with phoneme-based lip sync
- **Tour Management**: Waypoint navigation with audio narration
- **Multi-Base Support**: Works with Tibo, robots with Orin Nano, Raspberry Pi bases
- **WebSocket Communication**: Real-time robot control via ROS bridge
- **Test Mode**: Full simulation for development without robot hardware

```bash
./deploy.sh
# Or open in Android Studio
```

### Legacy Python - `legacy_python_source/`
Original Python/FastAPI implementation with web UI.

```bash
cd legacy_python_source
pip install -r requirements.txt
python main.py
```

## 🚀 Quick Start

### Flutter (Recommended for New Development)
```bash
cd flutter_app
flutter pub get
flutter run -d chrome  # Web
flutter run -d macos   # macOS
flutter run            # Connected device/emulator
```

### Android Native
```bash
./deploy.sh
# Or open in Android Studio (Ladybug or newer)
```

## 🤖 Task & Mode Architecture

The robot operates on a **Task + Mode** paradigm that separates WHAT happens from HOW it's executed.

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          CONCEPTUAL MODEL                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   TASKS (What to do)              MODES (How to execute)                │
│   ─────────────────               ──────────────────────                │
│   • Speak text                    • Per-Waypoint Mode                   │
│   • Display content                 └─ Execute on arrival               │
│   • Wait for pickup               • Sequence Mode                       │
│   • Navigate to point               └─ Multi-waypoint tour              │
│   • Return to origin              • Patrol Mode (future)                │
│                                     └─ Loop through waypoints           │
│                                   • Follow Mode (future)                │
│                                     └─ Track person/object              │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   WAYPOINT TASK ASSIGNMENT                                              │
│   ────────────────────────                                              │
│   Waypoint + Condition + Task = Behavior                                │
│                                                                         │
│   Example: "Kitchen" + OnArrival + DeliveryTask                         │
│            → Robot arrives at Kitchen, announces delivery, waits        │
│                                                                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   EXECUTION FLOW                                                        │
│   ──────────────                                                        │
│                                                                         │
│   ┌─────────┐    ┌──────────────┐    ┌─────────────┐                   │
│   │ Trigger │───▶│ TaskManager  │───▶│ TaskMode    │                   │
│   │ (arrival│    │ (orchestrate)│    │ (execute)   │                   │
│   │  button)│    │              │    │             │                   │
│   └─────────┘    └──────────────┘    └─────────────┘                   │
│                         │                   │                           │
│                         ▼                   ▼                           │
│                  ┌──────────────┐    ┌─────────────┐                   │
│                  │CommandManager│    │  Callbacks  │                   │
│                  │ (retry/ack)  │    │ (TTS,screen)│                   │
│                  └──────────────┘    └─────────────┘                   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Built-in Mode Examples

| Mode | Description | Use Case |
|------|-------------|----------|
| **Delivery** | Announce → Wait → Return | Food delivery, package drops |
| **Announce** | Speak + Display | Greetings, information |
| **Comic** | Tell jokes at stops | Entertainment, events |
| **Busser** | Collect items → Bus station | Restaurant clearing |
| **Tour** | Multi-stop guided tour | Museums, offices |
| **Emergency** | Alert + Evacuation route | Safety, fire drills |
| **Teleop** | Manual joystick control | Setup, debugging |

---

## 📖 User Stories & Mode Definitions

### 1. 🍕 Delivery Mode
**Story**: "As a restaurant server, I want the robot to deliver food to tables and return, so customers get hot food quickly."

```
TRIGGER: Assign delivery task to waypoint
FLOW:
  1. Navigate to destination
  2. Announce "Your delivery has arrived"
  3. Display pickup instructions
  4. Wait 30 seconds for pickup
  5. Return to origin (kitchen/bar)
```

### 2. 🎭 Comic Mode
**Story**: "As an event planner, I want the robot to roam and tell jokes, so guests are entertained."

```
TRIGGER: Start Comic sequence
FLOW:
  1. Navigate to waypoint (or detected person group)
  2. Play attention beep
  3. Tell joke from joke database
  4. Wait for laughter (3 seconds)
  5. Display punchline GIF
  6. Move to next stop
  7. Repeat until sequence complete
```

### 3. 🏛️ Tour Guide Mode
**Story**: "As a museum visitor, I want a guided tour with narration at each exhibit, so I learn about the collection."

```
TRIGGER: Start Tour sequence
FLOW:
  1. Announce tour start
  2. Navigate to Stop 1
  3. Play arrival beep
  4. Speak exhibit description
  5. Display related media
  6. Wait for configured time
  7. Navigate to Stop 2...N
  8. Announce tour complete
```

### 4. 🍽️ Busser Mode
**Story**: "As a restaurant manager, I want the robot to collect dishes from tables, so staff can focus on service."

```
TRIGGER: Start Busser sequence
FLOW:
  1. Navigate to Table 1
  2. Announce "Place finished items on my tray"
  3. Display loading animation
  4. Wait 20 seconds
  5. Navigate to Table 2...N
  6. Navigate to Bus Station
  7. Announce "Ready for unloading"
  8. Wait for tray clear
  9. Return to starting position
```

### 5. 🚨 Emergency Mode
**Story**: "As a building safety officer, I want the robot to alert occupants and guide evacuation, so everyone exits safely."

```
TRIGGER: Emergency button / fire alarm integration
FLOW:
  1. STOP all other tasks immediately
  2. Play loud alarm sound
  3. Announce "EMERGENCY - Please evacuate"
  4. Display evacuation map
  5. Navigate toward exit, repeating alerts
  6. At exit: "Exit this way" with arrow
  7. Loop until manually stopped
```

### 6. 🕹️ Teleop Mode
**Story**: "As a technician, I want manual control of the robot, so I can test movement and calibrate sensors."

```
TRIGGER: Enable Teleop in app
FLOW:
  1. Disable autonomous navigation
  2. Enable joystick control
  3. Forward velocity commands directly
  4. Display live camera feed (if available)
  5. Show sensor readings
  6. Exit on disable or timeout
```

### 7. 👋 Greeter Mode
**Story**: "As a receptionist, I want the robot to greet visitors at the entrance, so they feel welcomed."

```
TRIGGER: Assign Greeter task to Entrance waypoint
FLOW:
  1. Wait at entrance waypoint
  2. On person detection (future: vision)
  3. Play friendly chime
  4. Announce "Welcome! How can I help you?"
  5. Display company logo
  6. Wait for interaction
  7. Return to idle position
```

---

## 🔧 Robot Configuration

All apps use WebSockets to communicate with the robot base (ROS bridge).

| Mode | Default URL | Description |
|------|-------------|-------------|
| Emulator | `ws://10.0.2.2:9090` | Connects to localhost on host machine |
| Real Robot | `ws://10.42.0.1:9090` | Tibo robot default IP |
| Custom | `ws://192.168.x.x:9090` | Your robot's IP address |

## 📁 Project Structure

```
.
├── flutter_app/                 # Cross-platform Flutter app
│   ├── lib/
│   │   ├── core/               # Connection & rosbridge client
│   │   ├── services/           # Robot introspection
│   │   ├── screens/            # Home screen
│   │   └── widgets/            # Dynamic UI components
│   └── pubspec.yaml
│
├── app/                         # Android native app
│   └── src/main/java/com/opendroids/tourbot/
│       ├── data/               # Repository layer, models
│       ├── di/                 # Hilt dependency injection
│       ├── logic/              # TourManager business logic
│       └── ui/                 # Compose UI, 3D face animation
│
└── legacy_python_source/        # Original Python implementation
    ├── api/                    # Base API and robot factory
    ├── adapters/               # Robot-specific adapters
    ├── apps/                   # Tour bot application
    └── ui/                     # Web interfaces
```

## 📚 Documentation

- [**Flutter App README**](flutter_app/README.md) - Cross-platform app details
- [**HANDOFF_TO_REAL.md**](HANDOFF_TO_REAL.md) - Connecting to real robot hardware
- [**ANDROID_MIGRATION_PLAN.md**](ANDROID_MIGRATION_PLAN.md) - Architecture documentation
- [**PRODUCTION_READINESS_REVIEW.md**](PRODUCTION_READINESS_REVIEW.md) - Deployment checklist

## 🔐 Security Note

These apps use cleartext WebSocket (`ws://`) for local robot communication. This is intentional for LAN-only robot control. For production deployments requiring internet connectivity, implement `wss://` with proper certificate handling.

## 🤝 Contributing

1. Choose the appropriate platform for your changes
2. Follow existing code patterns and architecture
3. Test on at least one platform before submitting
4. Update documentation if adding new features
