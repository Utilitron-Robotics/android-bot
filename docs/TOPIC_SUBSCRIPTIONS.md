# ROS Topic Subscriptions & Data Flow

This document maps every ROS topic used by the system, who publishes/subscribes, and the data flow through the relay to Flutter.

---

## Architecture Reminder

```
Flutter (display/control layer)  ←── gRPC stream ──→  Relay (data/operations layer)  ←── WS :9090 ──→  Robot
```

- **Relay** subscribes to all topics, processes data, sends results via gRPC
- **Flutter** receives processed results and displays them — NO raw topic processing
- **Proto fields**: `data_age_ms` (stale detection), `min_range_meters` (actual LIDAR distance), `safety_zone` (computed zone)

---

## LIDAR Topics

### `/scan` (sensor_msgs/LaserScan) - PRIMARY
- **Publisher**: Robot base (LIDAR hardware)
- **Subscriber**: Relay app (`RobotWebSocketClient.kt:445-456`)
- **Message format**: `ranges` array of float distances (meters)
- **Processing**: Relay extracts front arc (40-60% of array), filters <5cm noise, computes `minFrontDistance`, classifies safety zone
- **Data flow**: Robot → Relay → `minFrontDistance` + `safetyZone` → gRPC `min_range_meters` + `safety_zone` → Flutter gauge
- **Throttle**: 150ms (subscription level)
- **Status**: WORKS on our robots

### `/laser_data` (yutong_assistance/point_array) - CHASSIS PROTOCOL
- **Publisher**: Robot base (chassis firmware, may not publish on all robots)
- **Subscriber**: Relay app (`RobotWebSocketClient.kt:422-443`)
- **Message format**: `px`/`py` coordinate arrays (cartesian points)
- **Processing**: Same safety zone computation via `checkLaserData()` after converting to distances
- **Status**: Referenced in chassis protocol docs, NOT available on all robots

---

## Stale Data Detection

### How It Works
- `RobotWebSocketClient._lastRobotDataTime` updated on EVERY incoming message (`parseStatusUpdate()`, line 333)
- `RobotControlServiceImpl` computes `data_age_ms = now - lastRobotDataTime` on each gRPC status update
- Flutter receives via `unified_transport.dart:525` → `status['data_age_ms']`
- Joystick gauge: `data_age_ms > 3000` or `< 0` → shows "NO DATA" (grey), blocks forward motion in SLAM Safe mode
- `CommandBuffer` heartbeat also sends `data_age_ms` via WS JSON for buffer clients

### Stale Thresholds
- `data_age_ms = -1`: Never received any data from robot
- `data_age_ms > 3000`: Joystick flags stale (stops forward motion in safe mode)
- `data_age_ms > 5000`: `buffer_client.dart` considers data fully stale

---

## Robot Status & Pose

### `/robot_status` (yutong_assistance/RobotStatus)
- **Publisher**: Robot base
- **Subscriber**: Relay app (`RobotWebSocketClient.kt:342-359`)
- **Message format**: `nav_status`, `battery`, `velocity[]`, `control_state`, `soft_estop`, `hard_estop`, `current_goal_name`
- **Data flow**: Robot → Relay → gRPC `RobotStatus` → Flutter status bar

### `/robot_pose` (geometry_msgs/Pose2D)
- **Publisher**: Robot base (SLAM/localization)
- **Subscriber**: Relay app (`RobotWebSocketClient.kt:361-368`)
- **Message format**: `x`, `y`, `theta`
- **Data flow**: Robot → Relay → gRPC `Pose2D` → Flutter map view (robot marker)

### `/navi_status`
- **Publisher**: Robot base (navigation stack)
- **Subscriber**: Relay app
- **Data flow**: Robot → Relay → `CommandBuffer.onNavStatus()` for arrival/failure detection

---

## Map

### `/map` (nav_msgs/OccupancyGrid, fragmented PNG)
- **Publisher**: Robot base (map server)
- **Subscriber**: Relay app (subscribes with `fragment_size=6000`, `compression=png`)
- **Relay processing**: Reassembles fragments (`handleMapFragment()`), caches complete message
- **Data flow**: Robot → Relay (fragment reassembly + cache) → Flutter polls HTTP `GET :8765/map`
- **Refresh**: Flutter sends `POST :8765/map/refresh` → Relay unsubscribes + resubscribes
- **Original approach**: Flutter subscribed directly via WS, processed raw OccupancyGrid locally (commit 3c15ff8)
- **Why HTTP**: Large payload (100KB+), fragmentation handling, independent of WS state, relay caches for multiple clients

---

## Command Topics (Relay Publishes)

### `/cmd_vel_mux/input/teleop` (geometry_msgs/Twist)
- **Publisher**: Relay app
- **Subscriber**: Robot base (motor controller)
- **Message format**: `linear.x` (m/s), `angular.z` (rad/s)
- **Duration**: Each command lasts 0.6 seconds per protocol spec
- **Data flow**: Flutter joystick → gRPC → Relay → publishes to robot

### `/move_base/cancel` (actionlib_msgs/GoalID)
- **Publisher**: Relay app
- **Subscriber**: Robot base (move_base action server)
- **Data flow**: Flutter cancel → gRPC → Relay → publishes empty GoalID

### `/soft_stop`
- **Publisher**: Relay app
- **Subscriber**: Robot base
- **Data flow**: Flutter e-stop → gRPC → Relay → publishes stop

---

## Safety & Sensor Topics

### `/mobile_base/sensors/core`
- **Publisher**: Robot base (bumper/cliff/ultrasonic)
- **Subscriber**: Relay app (`RobotWebSocketClient.kt:369-421`)
- **Message format**: `bumper` (bitmask), `cliff` (bitmask), `analog_input[1]` (central ultrasonic mm)
- **Behavior**: Bumper/cliff → immediate STOP + cancel nav (unless docking). Ultrasonic tracked for motion detection.
- **Data flow**: Robot → Relay → safety zone override → gRPC → Flutter

### `/people_detected`
- **Publisher**: Robot base (people detection node)
- **Subscriber**: Relay app (`RobotWebSocketClient.kt:466-473`)
- **Data flow**: Robot → Relay → obstacle classification logic

### `/global_path` (nav_msgs/Path)
- **Publisher**: Robot base (global planner)
- **Subscriber**: Relay app (`RobotWebSocketClient.kt:457-464`)
- **Data flow**: Robot → Relay → `ObstacleClassifier` path corridor for on-path/off-path detection

---

## People Detection & Depth Camera Topics

**Discovered via rosapi/topics service (2026-01-28): Robot has 294 available topics.**

### `/detected_people_array` - PEOPLE POSITIONS (NOT PUBLISHING)
- **Publisher**: Robot base (depth camera people detection node)
- **Subscriber**: Relay app (`ChassisProtocol.subscribeDetectedPeopleArray()`)
- **Message type**: UNKNOWN - guessing `yutong_assistance/PersonArray` based on other types
- **Expected format**: `px`/`py` arrays of detected person positions in robot frame
- **Status**: ⚠️ Topic EXISTS on robot but NOT ACTIVELY PUBLISHING data
- **Data flow**: Robot → Relay → `PeopleTracker` → HTTP `/people` endpoint → Flutter map
- **Throttle**: 200ms

### `/people_detected` (std_msgs/Bool)
- **Publisher**: Robot base (people detection node)
- **Subscriber**: Relay app (`ChassisProtocol.subscribePeopleDetected()`)
- **Message format**: Boolean `true` when any person detected
- **Status**: EXISTS on robot, simple presence flag
- **Data flow**: Robot → Relay → obstacle classification logic

### `/handpose` (std_msgs/Int32)
- **Publisher**: Robot base (hand gesture detection)
- **Subscriber**: Relay app (`ChassisProtocol.subscribeHandpose()`)
- **Message format**: Gesture ID integer
- **Status**: EXISTS on robot

### Depth Camera Topics (up-facing camera)
**Now subscribing to discover which provides people positions:**
- `/upcamera/depth/image_raw` - ✅ WORKS - Raw depth image (streaming via WebRTC)
- `/up_camera_points` - 🔍 TESTING - May have processed person positions (yutong_assistance/point_array)
- `/upcam_data` - 🔍 TESTING - Unknown format, logging to discover

**Not yet subscribed:**
- `/upcamera/depth/points` - Point cloud data (PointCloud2)
- `/upcamera/depth/camera_info` - Camera calibration
- `/up_camera_scan` - Processed scan data (LaserScan format)
- `/up_camera_before_to_map` / `/up_camera_after_to_map` - Map transforms

**Testing with logcat:**
```bash
adb logcat -s PEOPLE_DEBUG
```
This shows raw message structure from `/up_camera_points` and `/upcam_data` to identify which provides usable people positions.

### `/move_base/local_costmap/costmap` (nav_msgs/OccupancyGrid)
- **Publisher**: Robot base (move_base local costmap)
- **Subscriber**: Relay app (`ChassisProtocol.subscribeLocalCostmap()`)
- **Message format**: OccupancyGrid showing inflated obstacles as "blocks"
- **OEM visualization**: This is what the OEM software uses for obstacle rectangles on map
- **Throttle**: 500ms (costmap is heavy)
- **Status**: EXISTS and subscribed

### Topic Discovery

**How to discover new topics**:
1. Relay calls `ChassisProtocol.callListTopics()` on connect
2. Uses rosapi service: `/rosapi/topics`
3. Response logged with filter: `ROSAPI_TOPICS`
4. Keywords highlighted: people, person, human, body, skeleton, depth, camera, detect, track

**Logcat filters**:
- `ROSAPI_TOPICS` - One-time dump of all 294 available topics on connect
- `ROS_TOPICS` - Every incoming message's topic name
- `PEOPLE_DEBUG` - People detection data processing

---

## Navigation Service

### `/poi` (ROS service call)
- **Called by**: Relay app
- **Args**: `{poi: "waypoint_name"}`
- **Data flow**: Flutter nav request → gRPC → Relay → service call → robot navigates

---

## Safety Zone Thresholds

| Zone | Normal | Detach Mode (docking) |
|------|--------|----------------------|
| STOP | < 0.20m | < 0.08m |
| CREEP | 0.20-0.50m | 0.08-0.20m |
| WARN | 0.50-0.80m | 0.20-0.40m |
| CLEAR | > 0.80m | > 0.40m |

---

## Why LIDAR Keeps Breaking (The Pattern)

This has broken multiple times. Root causes:

### 1. Wrong topic subscription
- Chassis protocol docs say `/laser_data` — our robots publish `/scan`
- **Fix**: Subscribe to BOTH, process whichever delivers

### 2. Removed working subscription during unrelated fix
- Developer assumed `/laser_data` was correct, removed `/scan`
- **Fix**: Restored `/scan`, added to CLAUDE.md as critical lesson

### 3. Wrong message parsing
- Subscribed to `/scan` but parsed as `point_array` (px/py) instead of `LaserScan` (ranges)
- **Fix**: Parse as `sensor_msgs/LaserScan`

### 4. gRPC path never wired up (this fix)
- Relay tracked `minFrontDistance` and `_lastRobotDataTime` correctly
- `CommandBuffer` WS heartbeat sent `data_age_ms` correctly
- But `RobotControlServiceImpl` gRPC builder never set `data_age_ms` or `min_range_meters`
- Flutter gauge was reverse-engineering fake distances from zone names ("STOP"→0.15, "CREEP"→0.35)
- Stale LIDAR (after nav) showed ">2m" CLEAR instead of "NO DATA"
- **Fix**: Wire `setDataAgeMs()` and `setMinRangeMeters()` in gRPC builder, use real values in Flutter gauge

### Lessons
1. **The protocol docs describe a different firmware** — trust what the robot publishes
2. **Subscribe to BOTH** `/scan` and `/laser_data`
3. **Never remove a working subscription** until replacement is verified end-to-end
4. **When fixing a bug, grep ALL callers** (tour start in BOTH hud_screen AND sequence_editor)
5. **Test LIDAR by walking in front of robot** — gauge must show STOP/CREEP
6. **Verify the ENTIRE pipeline** — relay tracking data means nothing if gRPC doesn't send it to Flutter
