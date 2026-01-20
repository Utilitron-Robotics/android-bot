# Robot/chassis Robot Communication Protocol
## WebSocket JSON Protocol - Field-Tested Implementation

**Last Updated:** January 2026
**Based On:** Robot MobileBase robots running chassis firmware
**Protocol:** WebSocket (`ws://10.42.0.1:9090`) with JSON messages

> **Related Documentation:**
> - [`docs/chassis_protocol.md`](docs/chassis_protocol.md) - Original vendor protocol specification
> - [`docs/chassis_specification.md`](docs/chassis_specification.md) - Hardware specifications
> - [`NETWORKING.md`](NETWORKING.md) - Network topology and connection types

This document describes the **actual working protocol** as implemented and tested in our Frontier Tower deployment. Unlike the vendor manual, this reflects real-world behavior, including undocumented quirks and field-tested solutions.

---

## Connection

```javascript
// Direct robot connection
ws://10.42.0.1:9090

// Relay connection (tablet on house WiFi)
ws://tablet-ip:8766
```

**Connection Notes:**
- Robot WebSocket is **cleartext only** - no TLS/SSL
- Must complete handshake before sending messages
- Connection timeout: ~30 seconds idle
- Recommend heartbeat/keepalive via periodic subscriptions

---

## Message Format

All messages are **JSON strings** exchanged via WebSocket frames.

### Basic Structure

```json
{
  "op": "operation_type",
  "id": "unique_identifier",
  "topic": "/topic_name",
  "type": "msg_type/MessageName"
}
```

### Operations

| Operation | Direction | Purpose |
|-----------|-----------|---------|
| `advertise` | Client → Robot | Register intent to publish to topic |
| `publish` | Client → Robot | Send data to topic |
| `unadvertise` | Client → Robot | Stop publishing to topic |
| `subscribe` | Client → Robot | Request topic data |
| `publish` | Robot → Client | Topic data response |
| `unsubscribe` | Client → Robot | Stop receiving topic data |
| `call_service` | Client → Robot | Call ROS service |
| `service_response` | Robot → Client | Service call result |
| `fragment` | Robot → Client | Large data chunk (maps) |
| `png` | Robot → Client | Compressed map image |

---

## CRITICAL BEHAVIORS

### 1. Velocity Command Duration
**IMPORTANT:** Each velocity command lasts **0.6 seconds only**.

```json
// This command expires after 600ms
{"op": "publish", "topic": "/cmd_vel_mux/input/teleop",
 "msg": {"linear": {"x": 0.2}, "angular": {"z": 0}}}
```

**Implications:**
- Must republish every ~500ms for continuous motion
- Do NOT spam zero velocity - robot stops automatically
- Use for smooth control loops, not one-shot commands

### 2. Advertise Before Publish
**REQUIRED:** Must advertise topic before first publish

```javascript
// 1. Advertise first
send({"op": "advertise", "id": "vel", "topic": "/cmd_vel_mux/input/teleop",
      "type": "geometry_msgs/Twist"})

// 2. Then publish
send({"op": "publish", "id": "vel", "topic": "/cmd_vel_mux/input/teleop",
      "msg": {"linear": {"x": 0.2}, "angular": {"z": 0}}})
```

### 3. Navigation Status vs Nav Status
**There are TWO navigation status sources:**

| Source | Topic | Update | Use Case |
|--------|-------|--------|----------|
| `/robot_status` → `nav_status` | Robot status message | Continuous (10Hz) | **Primary** - Use this for UI |
| `/navi_status` | Separate topic | On state change only | Debug/verification |

**Always use `/robot_status` → `nav_status` field** for navigation monitoring.

### 4. POI List Typo
**API has intentional(?) typo:**

```json
// Request waypoint list
{"op": "call_service", "service": "/poi", "args": {"poi": ""}}

// Response - note "avaliable" not "available"
{"values": {"avaliable_list": ["P1", "P2", "P3"]}}
```

Use `avaliable_list` (not `available_list`) to parse waypoints.

---

## TOPICS (Subscribe)

### Robot Position `/robot_pose`
Real-time global position in map coordinates.

**Subscribe:**
```json
{
  "op": "subscribe",
  "id": "get_pose",
  "topic": "/robot_pose",
  "type": "geometry_msgs/Pose2D"
}
```

**Response (10Hz):**
```json
{
  "op": "publish",
  "topic": "/robot_pose",
  "msg": {
    "x": 1.234,          // meters in global frame
    "y": -0.567,         // meters in global frame
    "theta": 1.5708      // radians (0 = east, π/2 = north, π = west, 3π/2 = south)
  }
}
```

**Units:**
- `x`, `y`: meters (origin at map origin)
- `theta`: radians, **counterclockwise from east** (standard ROS convention)

---

### Robot Status `/robot_status` ⭐ MOST IMPORTANT
Primary source of truth for robot state.

**Subscribe:**
```json
{
  "op": "subscribe",
  "id": "get_robot_status",
  "topic": "/robot_status",
  "type": "yutong_assistance/RobotStatus"
}
```

**Response (10Hz):**
```json
{
  "op": "publish",
  "topic": "/robot_status",
  "msg": {
    "current_building_name": "FrontierTower",
    "current_floor_name": "Spaceship",
    "soft_estop": false,           // Software stop (via /soft_stop topic)
    "hard_estop": false,           // Physical e-stop button pressed
    "battery": 87,                 // Percentage 0-100
    "charger": 0,                  // 0=not charging, 1=on charger, 2=charging
    "nav_status": 601,             // ⭐ 600=idle, 601=moving, 602=cancelled, 603=arrived, 604=failed
    "patrol_status": 0,            // Patrol mode (unused in our deployment)
    "velocity": [0.15, 0.02],      // [linear m/s, angular rad/s] - ACTUAL measured velocity
    "control_state": 30,           // 20=mapping, 30=navigation, 99=error
    "current_goal_name": "P5",     // Active waypoint name or ""
    "current_goal_coordinate": {
      "x": 5.2,
      "y": -1.8,
      "theta": 0.0
    }
  }
}
```

**Navigation Status Codes:**
| Code | Name | Meaning | Next Action |
|------|------|---------|-------------|
| 600 | Idle | No active goal | Ready for new command |
| 601 | Running | Navigating to waypoint | Wait for arrival |
| 602 | Cancelled | User cancelled | Ready for new command |
| 603 | Success | Arrived at waypoint | Ready for new command |
| 604 | Failed | Path blocked/unreachable | **Trigger recovery** or retry |
| 605 | Standby | Reserved | Treat as idle |

**Control State Codes:**
| Code | Name | Description |
|------|------|-------------|
| 20 | Mapping | SLAM mapping mode (can't navigate) |
| 30 | Navigation | Normal operation (can navigate) |
| 99 | Error | System error |

**Battery Notes:**
- Robot warns at 20%, returns to charge at 15%
- Charging takes ~2.5 hours from 15% → 95%
- `charger` field: 0=disconnected, 1=on dock but not charging, 2=actively charging

---

### LIDAR Scan `/scan` (Standard ROS Format)
Standard ROS LaserScan format - preferred for most applications.

**Subscribe:**
```json
{
  "op": "subscribe",
  "id": "get_scan",
  "topic": "/scan",
  "type": "sensor_msgs/LaserScan",
  "throttle_rate": 150,  // ~6Hz for responsive safety
  "queue_length": 1
}
```

**Response (10-30Hz):**
```json
{
  "op": "publish",
  "topic": "/scan",
  "msg": {
    "header": {
      "stamp": {"secs": 1704672345, "nsecs": 123456789},
      "frame_id": "base_scan"
    },
    "angle_min": -2.356194,      // radians (~-135°)
    "angle_max": 2.356194,       // radians (~135°)
    "angle_increment": 0.006135, // radians (~0.35°)
    "time_increment": 0.0,
    "scan_time": 0.1,            // 10Hz scan rate
    "range_min": 0.06,           // meters
    "range_max": 12.0,           // meters
    "ranges": [0.5, 0.52, 0.48, ...],      // Distance array (meters)
    "intensities": [100, 95, 105, ...]     // Signal strength (optional)
  }
}
```

**Key Fields:**
- `ranges`: Array of distances in **meters** (typical 720-1440 points)
- Invalid readings: `inf` or value > `range_max`
- `angle_min/max`: Front-facing arc (robot doesn't scan behind)
- `angle_increment`: Angular resolution between points

**Finding Nearest Obstacle:**
```javascript
const ranges = scanMsg.ranges;
let minDistance = Infinity;
let minAngle = 0;

for (let i = 0; i < ranges.length; i++) {
  const range = ranges[i];
  if (range > 0.05 && range < 12 && range < minDistance) {
    minDistance = range;
    minAngle = scanMsg.angle_min + (i * scanMsg.angle_increment);
  }
}

console.log(`Nearest obstacle: ${minDistance}m at angle ${minAngle}rad`);
```

**Front Arc Detection (For Joystick Safety):**
```javascript
// Divide scan into zones
const numRanges = ranges.length;
const frontStart = Math.floor(numRanges * 0.4);  // ~60° front arc
const frontEnd = Math.floor(numRanges * 0.6);

let minFrontDistance = Infinity;
for (let i = frontStart; i < frontEnd; i++) {
  if (ranges[i] > 0 && ranges[i] < minFrontDistance) {
    minFrontDistance = ranges[i];
  }
}

// Apply safety logic
if (minFrontDistance < 0.3) {
  // STOP zone - immediate halt
} else if (minFrontDistance < 0.6) {
  // CREEP zone - slow to 0.05 m/s
} else if (minFrontDistance < 1.2) {
  // WARN zone - reduce speed proportionally
}
```

---

### LIDAR Point Cloud `/laser_data` (Legacy Format)
Alternative LIDAR format - point cloud instead of scan array.

**Subscribe:**
```json
{
  "op": "subscribe",
  "id": "get_laser",
  "topic": "/laser_data",
  "type": "yutong_assistance/point_array"
}
```

**Response (5-10Hz):**
```json
{
  "op": "publish",
  "topic": "/laser_data",
  "msg": {
    "px": [-0.276, 0.399, 1.634, ...],  // X coordinates (meters, robot frame)
    "py": [-1.197, -1.205, -1.213, ...], // Y coordinates (meters, robot frame)
    "pt": [0, 0, 0, ...]                 // Point types (0=normal, other=reserved)
  }
}
```

**Coordinate Frame:**
- Robot-centric: (0,0) is robot center
- X-axis: forward
- Y-axis: left
- Range: ~0.1m to 12m
- Resolution: ~0.5° angular, typical 720 points/scan

**Transform to Global:**
```javascript
// Given robot pose (xRobot, yRobot, thetaRobot)
for (let i = 0; i < px.length; i++) {
  const xGlobal = xRobot + (px[i] * Math.cos(thetaRobot)) - (py[i] * Math.sin(thetaRobot));
  const yGlobal = yRobot + (px[i] * Math.sin(thetaRobot)) + (py[i] * Math.cos(thetaRobot));
}
```

**Our Safety Zone Logic:**
Uses nearest LIDAR point to classify zones:
- **STOP** (< 0.3m): Full stop immediately
- **CREEP** (0.3-0.6m): 0.05 m/s tortoise speed
- **WARN** (0.6-1.2m): Reduce speed (configurable ramp rate)
- **CLEAR** (> 1.2m): Full speed allowed

---

### Global Path `/global_path`
Planned navigation path from robot to current goal.

**Subscribe:**
```json
{
  "op": "subscribe",
  "id": "get_global_path",
  "topic": "/global_path",
  "type": "yutong_assistance/point_array"
}
```

**Response (On path change):**
```json
{
  "op": "publish",
  "topic": "/global_path",
  "msg": {
    "px": [0.0, 0.5, 1.2, 2.5, 5.0],  // X coordinates (meters, global frame)
    "py": [0.0, 0.1, 0.3, -0.5, -1.0], // Y coordinates (meters, global frame)
    "pt": [0, 0, 0, 0, 0]              // Point types
  }
}
```

**Use Cases:**
- Visualize planned route on map
- Predict robot path for obstacle avoidance
- Estimate time to arrival (path length / velocity)
- Detect when robot recalculates path (stuck recovery)

**Path Updates:**
- Published when navigation starts
- Updated when path is recalculated (obstacles detected)
- Empty when no active navigation goal

---

### Sensor Data `/mobile_base/sensors/core`
Ultrasonic sensors, battery, bumpers.

**Subscribe:**
```json
{
  "op": "subscribe",
  "id": "get_sensors_core",
  "topic": "/mobile_base/sensors/core",
  "type": "kobuki_msgs/SensorState"
}
```

**Response (10Hz):**
```json
{
  "op": "publish",
  "topic": "/mobile_base/sensors/core",
  "msg": {
    "battery": 87,              // Same as /robot_status
    "charger": 0,               // 0=not on dock, 1=on dock
    "over_current": 0,          // 0=not charging, 1=charging
    "buttons": 0,               // 0=normal, 1=physical e-stop pressed
    "analog_input": [450, 520, 380, 610]  // Ultrasonic distances in MILLIMETERS
  }
}
```

**Ultrasonic Sensors:**
- **4 sensors** around base (front-left, front-right, rear-left, rear-right)
- Units: **millimeters** (not meters!)
- Range: ~50mm to ~800mm
- Detect objects LIDAR can't see: glass, cardboard, soft fabric
- Use for **sensor fusion** with LIDAR for robust obstacle detection

---

### Map `/map`
SLAM-generated occupancy grid.

**Subscribe (Simple - No Compression):**
```json
{
  "op": "subscribe",
  "id": "get_map_simple",
  "topic": "/map",
  "type": "nav_msgs/OccupancyGrid",
  "throttle_rate": 5000  // Only send updates every 5 seconds
}
```

**Response:**
```json
{
  "op": "publish",
  "topic": "/map",
  "msg": {
    "info": {
      "resolution": 0.05,        // meters per pixel
      "width": 384,              // pixels
      "height": 384,             // pixels
      "origin": {
        "position": {"x": -9.6, "y": -9.6, "z": 0.0},
        "orientation": {"x": 0, "y": 0, "z": 0, "w": 1}
      }
    },
    "data": [0, 0, 100, -1, ...]  // Flattened array: row-major order
  }
}
```

**Occupancy Values:**
- `0` = Free space (navigable)
- `100` = Occupied (wall/obstacle)
- `-1` = Unknown (unexplored)

**Coordinate Transforms:**
```javascript
// World → Pixel
const px = Math.floor((worldX - originX) / resolution);
const py = Math.floor((worldY - originY) / resolution);

// Pixel → World
const worldX = originX + (px * resolution);
const worldY = originY + (py * resolution);

// Array index
const index = py * width + px;  // Row-major
```

**Subscribe (Compressed - PNG):**
```json
{
  "op": "subscribe",
  "id": "get_map",
  "topic": "/map",
  "type": "nav_msgs/OccupancyGrid",
  "fragment_size": 6000,
  "compression": "png"
}
```

**Response (PNG Mode):**
```json
{
  "op": "png",
  "topic": "/map",
  "msg": {
    "info": { ... },  // Same as above
    "data": "iVBORw0KGgoAAAANSUhEUgAA..."  // Base64-encoded PNG
  }
}
```

PNG encoding:
- Grayscale image
- Pixel value 0 (black) = occupied
- Pixel value 255 (white) = free
- Pixel value 127 (gray) = unknown

---

## TOPICS (Publish)

### Velocity Control `/cmd_vel_mux/input/teleop`

**1. Advertise (once):**
```json
{
  "op": "advertise",
  "id": "velocity_control",
  "topic": "/cmd_vel_mux/input/teleop",
  "type": "geometry_msgs/Twist"
}
```

**2. Publish (every ~500ms for continuous motion):**
```json
{
  "op": "publish",
  "id": "velocity_control",
  "topic": "/cmd_vel_mux/input/teleop",
  "msg": {
    "linear": {
      "x": 0.2,   // m/s forward (positive) or backward (negative)
      "y": 0.0,   // Not used (differential drive)
      "z": 0.0    // Not used
    },
    "angular": {
      "x": 0.0,   // Not used
      "y": 0.0,   // Not used
      "z": 0.3    // rad/s rotation: positive=counterclockwise, negative=clockwise
    }
  }
}
```

**Speed Limits (firmware enforced):**
- Linear: `-0.5` to `0.5` m/s (max ~1.1 mph)
- Angular: `-1.0` to `1.0` rad/s (max ~57°/s)
- In SLAM/Smooth mode: linear max `0.25` m/s

**Direction Convention:**
- `linear.x > 0`: Forward
- `linear.x < 0`: Backward
- `angular.z > 0`: Rotate left (counterclockwise)
- `angular.z < 0`: Rotate right (clockwise)

**Stop:**
```json
{"op": "publish", "id": "velocity_control", "topic": "/cmd_vel_mux/input/teleop",
 "msg": {"linear": {"x": 0}, "angular": {"z": 0}}}
```

---

### Cancel Navigation `/move_base/cancel`

**1. Advertise:**
```json
{
  "op": "advertise",
  "id": "cancel_goal",
  "topic": "/move_base/cancel",
  "type": "actionlib_msgs/GoalID"
}
```

**2. Publish:**
```json
{
  "op": "publish",
  "id": "cancel_goal",
  "topic": "/move_base/cancel",
  "msg": {
    "stamp": "",  // Empty string cancels current goal
    "id": ""      // Empty string cancels current goal
  }
}
```

**Effect:**
- Stops robot immediately
- Sets `nav_status` → 602 (cancelled)
- Clears `current_goal_name`

---

### Soft Emergency Stop `/soft_stop`

**1. Advertise:**
```json
{
  "op": "advertise",
  "id": "set_estop",
  "topic": "/soft_stop",
  "type": "std_msgs/Bool"
}
```

**2. Enable E-Stop:**
```json
{
  "op": "publish",
  "id": "set_estop",
  "topic": "/soft_stop",
  "msg": {"data": true}
}
```

**3. Disable E-Stop:**
```json
{
  "op": "publish",
  "id": "set_estop",
  "topic": "/soft_stop",
  "msg": {"data": false}
}
```

**Effect:**
- When enabled: Robot stops all motion, rejects navigation commands
- `/robot_status` → `soft_estop` becomes `true`
- Must disable before robot can move again

---

## SERVICES (Call)

### Navigate to Waypoint `/poi`

**Call:**
```json
{
  "op": "call_service",
  "id": "service_poi",
  "service": "/poi",
  "args": {"poi": "P5"}
}
```

**Response:**
```json
{
  "op": "service_response",
  "id": "service_poi",
  "service": "/poi",
  "result": true,
  "values": {
    "success": true,
    "avaliable_list": ["P1", "P2", "P3", "P4", "P5"]
  }
}
```

**Get Waypoint List (empty string):**
```json
{
  "op": "call_service",
  "service": "/poi",
  "args": {"poi": ""}
}
```

**Response when POI doesn't exist:**
```json
{
  "result": false,
  "values": {
    "success": false,
    "avaliable_list": ["P1", "P2", ...]
  }
}
```

**Behavior:**
- Robot plans path and starts navigation
- Monitor `/robot_status` → `nav_status` for progress
- Returns immediately (async operation)
- Navigation can take 10 seconds to 5+ minutes depending on distance

---

### Set Speed Mode `/velocity_control`

**Call:**
```json
{
  "op": "call_service",
  "id": "service_velocity_control",
  "service": "/velocity_control",
  "args": {
    "cmd": 4,    // Speed mode
    "str": ""    // Reserved (always empty string)
  }
}
```

**Speed Modes:**
| Mode | Name | Max Linear | Use Case |
|------|------|-----------|----------|
| 0 | Safety Low | ~0.15 m/s | Crowded, high-traffic |
| 1 | Safety Med | ~0.20 m/s | Normal service |
| 2 | Safety High | ~0.25 m/s | Light traffic |
| 3 | Balance Low | ~0.25 m/s | **Default** - Good general use |
| 4 | Balance Med | ~0.30 m/s | Open spaces |
| 5 | Balance High | ~0.35 m/s | Large open areas |
| 6 | Efficiency Low | ~0.35 m/s | Faster service |
| 7 | Efficiency Med | ~0.40 m/s | Delivery mode |
| 8 | Efficiency High | ~0.50 m/s | Max speed |
| 60 | Smooth | ~0.25 m/s | **Food delivery** - no sudden stops |
| 61 | Smooth Off | - | Disable smooth mode |
| 99 | Get Current | - | Query current mode |
| -1 | Default | ~0.25 m/s | Reset to factory default |

**Our Recommendation:**
- Public tours: Mode 3 (Balance Low)
- Food delivery: Mode 60 (Smooth)
- Recovery/tight spaces: Mode 0 (Safety Low)

**Response:**
```json
{
  "op": "service_response",
  "service": "/velocity_control",
  "result": true,
  "values": {}
}
```

---

### Robot Info `/robot_info`

**Call:**
```json
{
  "op": "call_service",
  "id": "service_robot_info",
  "service": "/robot_info",
  "args": {"cmd": 0}
}
```

**Response:**
```json
{
  "op": "service_response",
  "service": "/robot_info",
  "result": true,
  "values": {
    "robot_id": "MobileBase003F0-005878",
    "robot_type": "MOBILE_BASE",
    "software_version": "4.1.0-alpha",
    "firmware_version": "1.0.2",
    "hardware_version": "2.0.0"
  }
}
```

**Use:** Get robot serial number for fleet management, version diagnostics.

---

### Map Info `/get_map_info`

**Call:**
```json
{
  "op": "call_service",
  "id": "service_get_map_info",
  "service": "/get_map_info",
  "args": {"cmd": 0}
}
```

**Response:**
```json
{
  "op": "service_response",
  "service": "/get_map_info",
  "result": true,
  "values": {
    "origin_x": -9.6,
    "origin_y": -9.6,
    "width": 384,
    "height": 384,
    "resolution": 0.05,
    "building_name": "FrontierTower",
    "floor_name": "Spaceship",
    "free_space": 245.8,      // Square meters of navigable area
    "occ_space": 52.3,        // Square meters of obstacles
    "unknown_space": 12.1     // Square meters unexplored
  }
}
```

---

### ROS Introspection Services `/rosapi/*`
Discover robot capabilities at runtime.

#### Get All Topics `/rosapi/topics`
**Call:**
```json
{
  "op": "call_service",
  "service": "/rosapi/topics",
  "args": {}
}
```

**Response:**
```json
{
  "op": "service_response",
  "service": "/rosapi/topics",
  "result": true,
  "values": {
    "topics": ["/robot_status", "/robot_pose", "/scan", "/cmd_vel_mux/input/teleop", ...]
  }
}
```

#### Get Topic Types `/rosapi/topics_types`
**Call:**
```json
{
  "op": "call_service",
  "service": "/rosapi/topics_types",
  "args": {}
}
```

**Response:**
```json
{
  "op": "service_response",
  "service": "/rosapi/topics_types",
  "result": true,
  "values": {
    "types": ["yutong_assistance/RobotStatus", "geometry_msgs/Pose2D", "sensor_msgs/LaserScan", ...]
  }
}
```

#### Get All Services `/rosapi/services`
**Call:**
```json
{
  "op": "call_service",
  "service": "/rosapi/services",
  "args": {}
}
```

**Response:**
```json
{
  "op": "service_response",
  "service": "/rosapi/services",
  "result": true,
  "values": {
    "services": ["/poi", "/robot_info", "/get_map_info", "/velocity_control", ...]
  }
}
```

#### Get ROS Parameters `/rosapi/get_param_names`
**Call:**
```json
{
  "op": "call_service",
  "service": "/rosapi/get_param_names",
  "args": {}
}
```

**Response:**
```json
{
  "op": "service_response",
  "service": "/rosapi/get_param_names",
  "result": true,
  "values": {
    "names": ["/robot_description", "/move_base/global_costmap/resolution", ...]
  }
}
```

#### Get Parameter Value `/rosapi/get_param`
**Call:**
```json
{
  "op": "call_service",
  "service": "/rosapi/get_param",
  "args": {"name": "/move_base/global_costmap/resolution"}
}
```

**Response:**
```json
{
  "op": "service_response",
  "service": "/rosapi/get_param",
  "result": true,
  "values": {
    "value": 0.05
  }
}
```

#### Set Parameter Value `/rosapi/set_param`
**Call:**
```json
{
  "op": "call_service",
  "service": "/rosapi/set_param",
  "args": {
    "name": "/move_base/local_costmap/inflation_radius",
    "value": 0.5
  }
}
```

**Response:**
```json
{
  "op": "service_response",
  "service": "/rosapi/set_param",
  "result": true
}
```

**Use Case - Dynamic Capability Discovery:**
```javascript
// Discover what robot can do
const topicsResult = await callService('/rosapi/topics');
const servicesResult = await callService('/rosapi/services');

// Check for specific capabilities
const hasNavigation = servicesResult.values.services.includes('/poi');
const hasLidar = topicsResult.values.topics.includes('/scan');
const hasCamera = topicsResult.values.topics.includes('/camera/rgb/image_raw');

// Adapt UI dynamically
if (hasNavigation) showWaypointButtons();
if (hasLidar) enableObstacleDetection();
if (hasCamera) enableVideoStream();
```

---

## REAL-WORLD PATTERNS

### Connection Sequence
```javascript
// 1. Connect WebSocket
const ws = new WebSocket('ws://10.42.0.1:9090');

ws.onopen = () => {
  // 2. Subscribe to essential topics
  ws.send(JSON.stringify({
    op: "subscribe",
    id: "get_robot_status",
    topic: "/robot_status",
    type: "yutong_assistance/RobotStatus"
  }));

  ws.send(JSON.stringify({
    op: "subscribe",
    id: "get_pose",
    topic: "/robot_pose",
    type: "geometry_msgs/Pose2D"
  }));

  // 3. Advertise control topics
  ws.send(JSON.stringify({
    op: "advertise",
    id: "velocity_control",
    topic: "/cmd_vel_mux/input/teleop",
    type: "geometry_msgs/Twist"
  }));

  // 4. Get robot info
  ws.send(JSON.stringify({
    op: "call_service",
    service: "/robot_info",
    args: {cmd: 0}
  }));

  // 5. Get waypoint list
  ws.send(JSON.stringify({
    op: "call_service",
    service: "/poi",
    args: {poi: ""}
  }));
};
```

### Navigation Flow
```javascript
// 1. Ensure not e-stopped
if (robotStatus.soft_estop || robotStatus.hard_estop) {
  console.error("Robot is e-stopped!");
  return;
}

// 2. Cancel any existing navigation
ws.send(JSON.stringify({
  op: "publish",
  id: "cancel_goal",
  topic: "/move_base/cancel",
  msg: {stamp: "", id: ""}
}));

// 3. Wait brief moment for cancel to take effect
await sleep(200);

// 4. Start navigation
ws.send(JSON.stringify({
  op: "call_service",
  service: "/poi",
  args: {poi: "P5"}
}));

// 5. Monitor status
ws.onmessage = (event) => {
  const msg = JSON.parse(event.data);
  if (msg.topic === "/robot_status") {
    const status = msg.msg.nav_status;
    if (status === 603) {
      console.log("Arrived!");
    } else if (status === 604) {
      console.log("Navigation failed - path blocked");
      // Trigger recovery sequence
    }
  }
};
```

### Joystick Control
```javascript
// Publish velocity every 500ms while joystick active
const controlLoop = setInterval(() => {
  if (joystickActive) {
    ws.send(JSON.stringify({
      op: "publish",
      id: "velocity_control",
      topic: "/cmd_vel_mux/input/teleop",
      msg: {
        linear: {x: linearSpeed},
        angular: {z: angularSpeed}
      }
    }));
  }
}, 500);

// On joystick release, stop immediately
function onJoystickRelease() {
  ws.send(JSON.stringify({
    op: "publish",
    id: "velocity_control",
    topic: "/cmd_vel_mux/input/teleop",
    msg: {
      linear: {x: 0},
      angular: {z: 0}
    }
  }));
}
```

---

## GOTCHAS & DEBUGGING

### 1. Robot Doesn't Move
**Check:**
- E-stop status: `soft_estop` or `hard_estop` true?
- Control state: Must be 30 (navigation), not 20 (mapping)
- Did you advertise before publish?
- Are you sending velocity every 500ms?

### 2. Navigation Fails Immediately
**Check:**
- Waypoint exists: Call `/poi` with `""` to get list
- Robot localized: `control_state` should be 30
- Not already navigating: Cancel first if `nav_status` is 601

### 3. WebSocket Disconnects
**Check:**
- Robot WiFi: `10.42.0.1` only works when connected to robot AP
- Tablet relay: Ensure relay app running and ports 8765/8766 open
- Network switching: iOS/macOS may auto-switch to house WiFi

### 4. Map Not Loading
**Check:**
- Map mode: Use `throttle_rate: 5000` to avoid flooding
- PNG mode: Requires `fragment_size` and `compression: "png"`
- Simple mode: Remove fragmentation for direct data access

### 5. Velocity Commands Ignored
**Check:**
- Control state: Can't teleop while auto-navigating (nav_status 601)
- Speed limits: Firmware caps linear at ±0.5, angular at ±1.0
- Advertise: Must advertise topic first
- Frequency: Publish every 500ms, not just once

---

## APPENDIX: Message Type Reference

### geometry_msgs/Twist
```json
{
  "linear": {"x": 0.0, "y": 0.0, "z": 0.0},
  "angular": {"x": 0.0, "y": 0.0, "z": 0.0}
}
```

### geometry_msgs/Pose2D
```json
{
  "x": 0.0,      // meters
  "y": 0.0,      // meters
  "theta": 0.0   // radians
}
```

### actionlib_msgs/GoalID
```json
{
  "stamp": "",  // ROS timestamp or "" for current
  "id": ""      // Goal ID or "" for current/all
}
```

### std_msgs/Bool
```json
{
  "data": true
}
```

### yutong_assistance/RobotStatus
See [Robot Status `/robot_status`](#robot-status-robot_status--most-important) section above.

### yutong_assistance/point_array
```json
{
  "px": [1.0, 2.0, 3.0],  // X coordinates
  "py": [0.5, 1.0, 1.5],  // Y coordinates
  "pt": [0, 0, 0]         // Point types
}
```

### nav_msgs/OccupancyGrid
See [Map `/map`](#map-map) section above.

---

## TESTING TOOLS

### netcat Test (Connection)
```bash
# Test robot WebSocket port
nc -z -w 3 10.42.0.1 9090 && echo "ONLINE" || echo "OFFLINE"

# Manual WebSocket handshake
(echo -e "GET / HTTP/1.1\r\nHost: 10.42.0.1:9090\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n"; sleep 1) | nc 10.42.0.1 9090
```

### Browser Console Test
```javascript
const ws = new WebSocket('ws://10.42.0.1:9090');
ws.onmessage = (e) => console.log(JSON.parse(e.data));
ws.onopen = () => ws.send(JSON.stringify({
  op: "subscribe",
  topic: "/robot_status",
  type: "yutong_assistance/RobotStatus"
}));
```

---

## CHANGELOG

**2026-01-07**
- Document created from field deployment experience
- Based on Robot MobileBase robots, chassis firmware 4.1.0-alpha
- Tested at Frontier Tower (Spaceship floor, Mezzanine floor)
- Includes undocumented behaviors: velocity timeout, typo in POI list, dual nav status sources

---

**For Implementation Examples:**
- See `flutter_app/lib/core/rosbridge_client.dart` - WebSocket client
- See `flutter_app/lib/core/chassis_protocol.dart` - Message builders
- See `relay_app/.../ChassisProtocol.kt` - Kotlin implementation
