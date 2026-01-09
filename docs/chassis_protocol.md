# Mobile Robot Communication Protocol
## WebSocket API Documentation

---

# Protocol Overview

This protocol enables data interaction with the robot chassis algorithm layer. Network communication uses WebSocket with JSON string format for data exchange.

WebSocket enables full-duplex two-way communication over persistent connections.

Advantages:
1. No frequent HTTP requests needed - single WebSocket handshake
2. Full-duplex breaks the client-only request limitation
3. Stream data as it's generated
4. Frame-based transmission with fragmentation support

---

# Common Communication Format

Operations:
- Publish information registration
- Publish specific data
- Unregister publication
- Subscribe to topic data
- Data return
- Unsubscribe from topic data
- Call service interface

---

# Publish Information Registration

```json
{
  "op": "advertise",
  "id": "<string>",        // optional
  "topic": "<string>",
  "type": "<string>"
}
```

---

# Publish Specific Data

```json
{
  "op": "publish",
  "id": "<string>",        // optional
  "topic": "<string>",
  "msg": <json>
}
```

---

# Unregistering Publication

```json
{
  "op": "unadvertise",
  "id": "<string>",        // optional
  "topic": "<string>"
}
```

---

# Subscribe to Topic Data

```json
{
  "op": "subscribe",
  "id": "<string>",                  // optional
  "topic": "<string>",
  "type": "<string>",
  "throttle_rate": <int>,            // optional, milliseconds
  "fragment_size": <int>,            // optional, split threshold
  "compression": "<string>"          // optional, "png" for map
}
```

---

# Fragmented Data Reception

```json
{
  "op": "fragment",
  "id": "<string>",
  "topic": "<string>",
  "data": "<string>",
  "num": <int>,
  "total": <int>
}
```

---

# Unsubscribe

```json
{
  "op": "unsubscribe",
  "id": "<string>",        // optional
  "topic": "<string>"
}
```

---

# Service Request

```json
{
  "op": "call_service",
  "id": "<string>",                  // optional
  "service": "<string>",
  "args": <list<json>>               // optional
}
```

---

# Service Response

```json
{
  "op": "service_response",
  "id": "<string>",                  // optional
  "service": "<string>",
  "values": <list<json>>,            // optional
  "result": <boolean>
}
```

---

# SUBSCRIPTION PROTOCOLS

## Robot Position (Timed)

Subscribe:
```json
{
  "op": "subscribe",
  "id": "get_pose",
  "topic": "/robot_pose",
  "type": "geometry_msgs/Pose2D"
}
```

Response:
```json
{
  "topic": "/robot_pose",
  "msg": {
    "x": 0.009,
    "y": -0.047,
    "theta": 0.0114
  },
  "op": "publish"
}
```
- x: Global X position (meters)
- y: Global Y position (meters)
- theta: Direction (radians)

---

## Radar Point Cloud Data

Subscribe:
```json
{
  "op": "subscribe",
  "id": "get_laser",
  "topic": "/laser_data",
  "type": "yutong_assistance/point_array"
}
```

Response:
```json
{
  "topic": "/laser_data",
  "msg": {
    "px": [-0.276, 0.399, 1.634],
    "py": [-1.197, -1.205, -1.213],
    "pt": [0, 0, 0]
  },
  "op": "publish"
}
```

---

## Navigation Path

Subscribe:
```json
{
  "op": "subscribe",
  "id": "get_path",
  "topic": "/global_path",
  "type": "yutong_assistance/point_array"
}
```

---

## Map Data

Subscribe:
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

Response:
```json
{
  "topic": "/map",
  "msg": {
    "info": {
      "origin": {
        "position": { "x": -9.6, "y": -9.6 },
        "orientation": { "x": 0, "y": 0, "z": 0, "w": 1 }
      },
      "width": 384,
      "height": 384,
      "resolution": 0.05
    },
    "data": "<base64 encoded PNG>"
  },
  "op": "png"
}
```

---

## Robot Global State

Subscribe:
```json
{
  "op": "subscribe",
  "id": "get_robot_status",
  "topic": "/robot_status",
  "type": "yutong_assistance/RobotStatus"
}
```

Response:
```json
{
  "topic": "/robot_status",
  "msg": {
    "current_building_name": "building1",
    "current_floor_name": "3",
    "soft_estop": false,
    "hard_estop": false,
    "battery": 97,
    "charger": 0,
    "nav_status": 0,
    "patrol_status": 0,
    "velocity": [0.0, 0.0],
    "control_state": 30,
    "current_goal_name": "",
    "current_goal_coordinate": { "x": 0.0, "y": 0.0, "theta": 0.0 }
  },
  "op": "publish"
}
```

Fields:
- battery: Battery percentage
- charger: 0=Not connected, 1=Charging, 2=In progress, -1=Failed
- nav_status: 600=Waiting, 601=Running, 602=Cancelled, 603=Success, 604=Failed
- control_state: 20=Mapping, 30=Navigation, 99=Error
- velocity: [linear m/s, angular rad/s]

---

## Navigation State

Subscribe:
```json
{
  "op": "subscribe",
  "id": "get_navi_status",
  "topic": "/navi_status",
  "type": "actionlib_msgs/GoalStatus"
}
```

Status values:
- 0: Initialization wait
- 1: Running
- 2: Cancelled
- 3: Success
- 4: Failed

---

## Chassis Sensor Data

Subscribe:
```json
{
  "op": "subscribe",
  "id": "get_sensors_core",
  "topic": "/mobile_base/sensors/core",
  "type": "kobuki_msgs/SensorState"
}
```

Response includes:
- battery: Charge percentage
- charger: 0=not docked, 1=docked
- over_current: 0=not charging, 1=charging
- buttons: 0=e-stop not triggered, 1=triggered
- analog_input: Ultrasound data (mm)

---

# PUBLISH PROTOCOLS

## Speed Control

Advertise:
```json
{
  "op": "advertise",
  "id": "velocity_control",
  "topic": "/cmd_vel_mux/input/teleop",
  "type": "geometry_msgs/Twist"
}
```

Publish:
```json
{
  "op": "publish",
  "id": "velocity_control",
  "topic": "/cmd_vel_mux/input/teleop",
  "msg": {
    "linear": { "x": 0.2 },
    "angular": { "z": 0 }
  }
}
```

- linear.x positive = forward (m/s)
- linear.x negative = backward
- angular.z positive = clockwise (rad/s)
- angular.z negative = counterclockwise
- Both 0 = stop

Single command lasts 0.6 seconds. Don't continuously publish zero.

---

## Cancel Navigation

```json
{
  "op": "publish",
  "id": "cancel_goal",
  "topic": "/move_base/cancel",
  "msg": { "stamp": "", "id": "" }
}
```

---

## Soft Emergency Stop

```json
{
  "op": "publish",
  "id": "set_estop",
  "topic": "/soft_stop",
  "msg": { "data": true }
}
```

---

# SERVICE PROTOCOLS

## Program Control

```json
{
  "op": "call_service",
  "id": "service_node_manager_control",
  "service": "/node_manager_control",
  "args": {
    "building_name": "building1",
    "floor_num": "2",
    "cmd": 0,
    "args": 0
  }
}
```

cmd values:
- 0: Open mapping
- 1: Continue mapping (reserved)
- 2: Restart mapping (reserved)
- 3: Save map
- 4: Turn on navigation
- 7: Switch map

---

## Navigate to Point by Name

```json
{
  "op": "call_service",
  "id": "service_poi",
  "service": "/poi",
  "args": { "poi": "P1" }
}
```

---

## Get Map Info

```json
{
  "op": "call_service",
  "id": "service_get_map_info",
  "service": "/get_map_info",
  "args": { "cmd": 0 }
}
```

Response:
```json
{
  "values": {
    "origin_x": -9.6,
    "origin_y": -9.6,
    "width": 352,
    "height": 256,
    "resolution": 0.05,
    "building_name": "building1",
    "floor_name": "1"
  }
}
```

---

## Speed Mode

```json
{
  "op": "call_service",
  "id": "service_velocity_control",
  "service": "/velocity_control",
  "args": { "cmd": 3, "str": "" }
}
```

Speed modes (cmd):
- 0-2: Safety low/medium/high
- 3-5: Balance low/medium/high
- 6-8: Efficiency low/medium/high
- -1: Default mode
- 60: Smooth mode (food delivery)
- 61: Turn off smooth mode
- 99: Get current mode

---

# STATUS CODES

## General
- 0: Success
- 10: Processing
- 20: Mapping
- 30: Navigation
- 99: Unknown instruction

## Program Control
- 101: Error closing program
- 102: Invalid request, already running
- 104: No map available
- 105: No permission
- 106: Fatal error
- 107: Missing building/floor info
- 108: Map corrupted
- 109: Instruction not supported
- 110: Failed to save map

## Navigation
- 600: Initialization pending
- 601: Running
- 602: Cancelled
- 603: Success
- 604: Failed
- 605: Refused
- 620: Configuration failed
- 621: Emergency stop triggered

## Recharge
- 901: Success
- 902: No IR signal
- 903: Station not found
- 904: Timeout
- 905: In progress
- 906: Cancelled

---

# COORDINATE SYSTEM

## 3D Cartesian (Right-hand)
- X-axis: Forward
- Y-axis: Left
- Z-axis: Up

## Euler Angles
- Roll: X-axis rotation
- Pitch: Y-axis rotation
- Yaw: Z-axis rotation
- Positive = counterclockwise

## Radar to Global Transform
```
xw[i] = xRP + (x_laser[i] * cos(heading)) - (y_laser[i] * sin(heading))
yw[i] = yRP + (x_laser[i] * sin(heading)) + (y_laser[i] * cos(heading))
```

## Pixel to World Coordinates
```
wx = origin_x + px * resolution
wy = origin_y + py * resolution
```

## World to Pixel Coordinates
```
px = (wx - origin_x) / resolution
py = (wy - origin_y) / resolution
```
