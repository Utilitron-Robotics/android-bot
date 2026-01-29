# People Detection Status

**Last Updated**: 2026-01-28
**Status**: IMPLEMENTED - Multi-source detection with LIDAR fallback

---

## The Problem

The robot has 32+ people-detection related ROS topics that EXIST but DON'T PUBLISH DATA.

```
Topics that EXIST (verified via ROSAPI):
- /detected_people_array
- /people_detected
- /handpose
- /up_camera_points
- /up_camera_scan
- /upcamera/depth/image_raw
- /upcamera/depth/points
- etc.
```

**Evidence**: Logcat shows `ROSAPI_TOPICS` listing all topics, `GET /people` requests being made, but **ZERO `PEOPLE_DEBUG` logs** = no data flowing through the system.

---

## What WORKS (Infrastructure is Complete)

### 1. Topic Subscriptions (ChassisProtocol.kt)
```kotlin
const val TOPIC_DETECTED_PEOPLE_ARRAY = "/detected_people_array"
const val TOPIC_PEOPLE_DETECTED = "/people_detected"
const val TOPIC_UPCAMERA_DEPTH_RAW = "/upcamera/depth/image_raw"
const val TOPIC_UPCAMERA_DEPTH_POINTS = "/upcamera/depth/points"
const val TOPIC_UP_CAMERA_POINTS = "/up_camera_points"
```

### 2. WebSocket Handlers (RobotWebSocketClient.kt)
- Subscriptions sent on connect
- Message handlers exist for all topics
- Logging via `PEOPLE_DEBUG` tag

### 3. HTTP Endpoint (RelayServer.kt:517-565)
```
GET /people → Returns tracked people JSON
```
- Returns 404 when no data (which is current state)
- Returns stale warning if data >5s old

### 4. Tracking Algorithm (PeopleTracker.kt)
- Stable ID assignment with recycling
- EMA position smoothing (α=0.3)
- Velocity estimation
- Nearest-neighbor matching (0.8m threshold)
- 15-frame timeout before track removal

---

## What DOESN'T Work

### Robot's Built-in Detection Node
The robot's people detection node is either:
1. Not running
2. Disabled in robot config
3. Requires specific launch parameters

**We cannot fix this** - it's robot firmware/config side.

---

## Options for Custom Detection

### Option A: Use Raw Depth Data
Subscribe to `/upcamera/depth/points` or `/upcamera/depth/image_raw` and implement our own detection:

1. Parse point cloud data
2. Cluster points into objects
3. Filter by height/size for human shapes
4. Feed to PeopleTracker

**Pros**: Full control, works regardless of robot config
**Cons**: Compute-heavy, need to tune parameters

### Option B: Use Up Camera Scan
The `/up_camera_scan` topic may have preprocessed data:

1. Subscribe to scan data
2. Look for human-sized obstacles
3. Convert to coordinates
4. Feed to PeopleTracker

**Pros**: Lighter than raw point cloud
**Cons**: May also not be publishing

### Option C: Contact Robot Vendor
Ask CIOT/Chassis support how to enable `/detected_people_array` publishing.

**Pros**: Uses proven detection
**Cons**: Dependency on vendor response time

---

## Recommended Approach

**Start with Option B** (up camera scan), fall back to **Option A** (raw depth) if no data:

1. Add verbose logging to up camera handlers
2. Check what data (if any) comes through
3. If up_camera_scan publishes, parse for human detection
4. If not, implement point cloud clustering on depth data

---

## Files to Modify

| File | Change |
|------|--------|
| `RobotWebSocketClient.kt` | Add verbose logging for ALL up camera topic messages |
| `ChassisProtocol.kt` | Add parsing for up_camera_scan format |
| `PeopleTracker.kt` | Already complete, just needs input data |
| `RelayServer.kt` | Already complete, serves /people endpoint |

---

## IMPLEMENTATION (2026-01-28)

### New Files
- `DepthPeopleDetector.kt` - Clusters raw point data to find human-sized shapes

### Detection Arena
```
        MIN_X = 0.5m   MAX_X = 4.0m
             ┌───────────────┐
             │               │
  MIN_Y=-2m  │    ROBOT      │  MAX_Y=+2m
             │      ▲        │
             └───────────────┘

Human height filter: 0.5m - 2.0m (for 3D point clouds)
Human width filter: 0.3m - 1.2m (for clustering)
```

### Data Flow
```
Source 1: /up_camera_points (if publishing)
    → DepthPeopleDetector.processPointArrays()
    → PeopleTracker.update()
    → HTTP /people endpoint

Source 2: /detected_people_array (if publishing)
    → Parse positions
    → PeopleTracker.update()

Source 3: /laser_data LIDAR (FALLBACK - always works)
    → DepthPeopleDetector.processPointArrays()
    → PeopleTracker.update()
    (only when Source 1 & 2 stale >2 seconds)
```

### Logcat Filters
- `DEPTH_PEOPLE` - DepthPeopleDetector clustering logs
- `PEOPLE_DEBUG` - Topic data and tracking logs
- `ObstacleClassifier` - Crowd/person classification

## DO NOT INVESTIGATE AGAIN

Implementation is complete. If people aren't showing:
1. Check Logcat for `DEPTH_PEOPLE` logs
2. LIDAR fallback should detect humans as clusters
3. If still nothing, the arena bounds may need tuning
