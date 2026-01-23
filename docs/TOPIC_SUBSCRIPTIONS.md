# ROS Topic Subscriptions & Data Flow

This document maps every ROS topic used by the system, who publishes/subscribes, and the data flow.

---

## LIDAR Topics

### `/scan` (sensor_msgs/LaserScan) - PRIMARY
- **Publisher**: Robot base (LIDAR hardware)
- **Subscriber**: Relay app
- **Message format**: `ranges` array of float distances (meters), `angle_min`, `angle_max`, `angle_increment`
- **Data flow**: Robot → Relay → computes safety zones (STOP/CREEP/WARN/CLEAR) → gRPC stream → Flutter joystick
- **Status**: WORKS on our robots

### `/laser_data` (yutong_assistance/point_array) - CHASSIS PROTOCOL
- **Publisher**: Robot base (chassis firmware, may not publish on all robots)
- **Subscriber**: Relay app
- **Message format**: `px`/`py` coordinate arrays (cartesian points)
- **Data flow**: Robot → Relay → same safety zone computation as `/scan`
- **Status**: Referenced in chassis protocol docs, but NOT available on all robots

---

## Robot Status & Pose

### `/robot_status` (yutong_assistance/RobotStatus)
- **Publisher**: Robot base
- **Subscriber**: Relay app
- **Message format**: `nav_status` (600=Idle, 601=Moving, 602=Cancelled, 603=Arrived, 604=Failed, 605=Standby), battery, errors
- **Data flow**: Robot → Relay → gRPC stream → Flutter UI (status bar, indicators)

### `/robot_pose` (geometry_msgs/PoseStamped)
- **Publisher**: Robot base (SLAM/localization)
- **Subscriber**: Relay app
- **Message format**: `position` (x, y, z) + `orientation` (quaternion)
- **Data flow**: Robot → Relay → gRPC stream → Flutter map view (robot marker position)

### `/navi_status`
- **Publisher**: Robot base (navigation stack)
- **Subscriber**: Relay app
- **Data flow**: Robot → Relay → forwarded to clients for navigation progress

---

## Map

### `/map` (nav_msgs/OccupancyGrid, served as fragmented PNG)
- **Publisher**: Robot base (map server)
- **Subscriber**: Relay app (subscribes, caches, serves via HTTP)
- **Data flow**: Robot → Relay (caches PNG) → Flutter polls via HTTP GET on port 8765
- **Note**: Map is a large payload; relay caches and serves it to avoid repeated ROS fetches

---

## Command Topics (Relay Publishes)

### `/cmd_vel_mux/input/teleop` (geometry_msgs/Twist)
- **Publisher**: Relay app (on joystick input from Flutter)
- **Subscriber**: Robot base (motor controller)
- **Message format**: `linear.x` (m/s), `angular.z` (rad/s)
- **Duration**: Each command lasts 0.6 seconds per protocol spec
- **Data flow**: Flutter joystick → gRPC → Relay → publishes to robot

### `/move_base/cancel` (actionlib_msgs/GoalID)
- **Publisher**: Relay app
- **Subscriber**: Robot base (move_base action server)
- **Data flow**: Flutter cancel button → gRPC → Relay → publishes empty GoalID to cancel all goals

### `/soft_stop` (std_msgs/Bool or custom)
- **Publisher**: Relay app
- **Subscriber**: Robot base
- **Data flow**: Flutter e-stop → gRPC → Relay → publishes stop command

---

## Safety & Sensor Topics

### `/mobile_base/sensors/core`
- **Publisher**: Robot base (bumper/cliff sensors)
- **Subscriber**: Relay app
- **Data flow**: Robot → Relay → safety state updates → gRPC → Flutter UI warnings

### `/people_detected`
- **Publisher**: Robot base (people detection node)
- **Subscriber**: Relay app
- **Data flow**: Robot → Relay → used in obstacle classification logic

### `/global_path` (nav_msgs/Path)
- **Publisher**: Robot base (global planner)
- **Subscriber**: Relay app
- **Data flow**: Robot → Relay → used by obstacle classifier to determine if obstacles are on-path vs off-path

---

## Navigation Service

### `/poi` (service call)
- **Type**: ROS Service (not topic)
- **Called by**: Relay app
- **Args**: `{poi: "waypoint_name"}`
- **Data flow**: Flutter nav request → gRPC → Relay → service call → robot navigates

---

## Why LIDAR Keeps Breaking (The 3-Time Failure Pattern)

This has broken three separate times. Each time the same root cause:

### Failure 1: Subscribed to wrong topic
- Code was subscribing to `/laser_data` (from chassis protocol docs)
- Our robots don't publish `/laser_data`, they publish `/scan`
- **Fix**: Subscribe to `/scan` instead

### Failure 2: Removed `/scan` subscription while "fixing" something else
- A bug fix for an unrelated issue removed the `/scan` subscription
- The developer saw `/laser_data` in the protocol docs and assumed that was correct
- Safety zones stopped working, joystick lost LIDAR protection
- **Fix**: Restored `/scan` subscription

### Failure 3: Subscribed to `/scan` but wrong message parsing
- Subscribed to the right topic but parsed it as `point_array` format instead of `LaserScan`
- `ranges` array (polar, floats) vs `px`/`py` arrays (cartesian, coordinate pairs)
- **Fix**: Parse as `sensor_msgs/LaserScan` with `ranges` array

### Lessons Learned
1. **The protocol docs lie** (or describe a different firmware version). Trust what the robot actually publishes.
2. **Subscribe to BOTH** `/scan` and `/laser_data` - process whichever delivers data.
3. **Never remove a working subscription** until the replacement is verified end-to-end with actual LIDAR data flowing to the Flutter UI.
4. **When fixing a bug, grep ALL callers** - tour start exists in BOTH `hud_screen.dart` AND `sequence_editor.dart`. Missing one means the fix is incomplete.
5. **Test LIDAR safety by walking in front of the robot** - if the joystick doesn't show STOP/CREEP zones, the subscription is broken.
