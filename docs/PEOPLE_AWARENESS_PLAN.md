# People Awareness for Tour Bot

## Overview

Use depth camera and people detection data to make the tour bot aware of humans - their count, position, orientation, and whether they're following. This enables natural tour guide behavior.

---

## Data Sources (from robot)

| Topic | Data | Use Case |
|-------|------|----------|
| `/people_detected` | Boolean | Trigger tour offer greeting |
| `/detected_people_array` | Array of people with positions | Count, tracking, following detection |
| `/upcamera/depth/points` | 3D point cloud | Body shape, facing direction |
| `/up_camera_after_to_map` | Points in map frame | Person positions on map |
| `/obstacle_region` | Obstacle shapes | Person blocking path |
| `/move_base/local_costmap/costmap` | 2D grid with obstacles | Visualize people as blocks |

---

## Feature 1: Greeting & Tour Offer

**Trigger**: `/people_detected` goes TRUE (or person appears in `/detected_people_array`)

**Behavior**:
```
1. Robot detects human approaching
2. Speaks: "Welcome to the Robotics Floor! Would you like a tour?"
3. Wait for response (hand gesture via /handpose, or timeout)
4. If yes → start tour sequence
5. If no response after 10s → "No problem, let me know if you change your mind"
```

**Implementation**: Already partially exists in `CommandBuffer.kt` motion standby mode. Extend with:
- Configurable greeting text per venue
- Gesture recognition for "yes" (wave, thumbs up)
- Timeout handling

---

## Feature 2: Tour Group Tracking

**Goal**: Know how many people are in the tour group and track them throughout

**Data needed from `/detected_people_array`**:
- Person count
- Person positions (x, y relative to robot)
- Person IDs (for tracking same person across frames)

**State to maintain**:
```kotlin
data class TourGroup(
    val peopleCount: Int,
    val people: List<TrackedPerson>,
    val startedAt: Long,
    val lastSeenAt: Long
)

data class TrackedPerson(
    val id: String,           // Tracking ID from detection
    val position: Point2D,    // Position in robot frame
    val distanceFromRobot: Double,
    val isFollowing: Boolean,
    val lastSeenAt: Long
)
```

**Logic**:
- At tour start: snapshot initial group size
- During tour: track if same people are still visible
- Alert if group size drops significantly

---

## Feature 3: Following Detection

**Goal**: Detect if people are following the robot or falling behind

**Metrics**:
- Distance from robot (from `/detected_people_array` positions)
- Movement direction (compare positions over time)
- Relative velocity (are they keeping up?)

**Thresholds**:
| Status | Distance | Action |
|--------|----------|--------|
| Close | < 1.5m | Normal, continue |
| Following | 1.5m - 3m | Normal, continue |
| Falling behind | 3m - 5m | Slow down, gentle reminder |
| Lost | > 5m | Stop, call out loudly |
| Gone | Not detected for 10s | Stop tour, announce |

**Announcements**:
- Falling behind: "Take your time, I'll wait for you!"
- Lost: "Hello? Is everyone still with me?"
- Gone: "It looks like I've lost my tour group. Tour paused."

---

## Feature 4: Facing Direction Detection

**Goal**: Know which way people are facing (toward robot or away)

**Method 1: From depth point cloud**
- Human body is not symmetric front-to-back
- Chest/face side has different depth profile than back
- Compare point cloud shape to known patterns

**Method 2: From `/detected_people_array` if it includes orientation**
- Some people trackers include facing angle
- Check message format when we get real data

**Method 3: Movement-based inference**
- If person is moving toward robot → probably facing it
- If person is moving away → probably facing away

**Use cases**:
- Don't start tour until people are facing robot (paying attention)
- Detect when people turn away (losing interest)
- Know if blocking person is facing robot (can see it) or not (might not know)

---

## Feature 5: Path Blocking Detection

**Goal**: Detect when a person is blocking the robot's intended path

**Data sources**:
- `/obstacle_region` - detected obstacles
- `/global_path` - robot's planned path
- Person positions from `/detected_people_array`

**Logic**:
```
1. Get robot's current navigation goal path
2. Get positions of detected people
3. Check if any person intersects with path corridor (within 0.5m of path)
4. If blocking:
   - First: slow down, wait 3 seconds
   - Then: politely ask to move
   - Finally: plan around if possible
```

**Announcements**:
- Polite: "Excuse me, may I pass through?"
- Informative: "I need to get to [destination], could you step aside?"
- Urgent: "Please clear the path, I need to move through"

---

## Feature 6: Smart Tour Pacing

**Goal**: Adjust tour speed based on group behavior

**Factors**:
- Group distance from robot
- Group movement speed
- Number of people still following
- Whether anyone is struggling to keep up

**Speed adjustments**:
```
base_speed = 0.4 m/s (comfortable walking)

if (avg_group_distance > 3m):
    speed = 0.2  # slow down
if (anyone_falling_behind):
    speed = 0.1  # crawl
if (group_lost):
    speed = 0    # stop

if (group_close && all_following):
    speed = base_speed  # normal
```

---

## Feature 7: Tour Narration Timing

**Goal**: Only speak when people are paying attention

**Checks before speaking**:
- Are people still detected?
- Are they facing the robot (or the point of interest)?
- Are they within hearing distance?
- Has the group settled (not still walking)?

**Logic**:
```
fun shouldSpeak(): Boolean {
    val peopleDetected = peopleCount > 0
    val peopleClose = avgDistance < 4m
    val groupSettled = groupVelocity < 0.1 m/s
    val facingCorrectly = anyoneFacingRobot || anyoneFacingPOI

    return peopleDetected && peopleClose && groupSettled
}
```

---

## Implementation Phases

### Phase 1: Data Collection (NOW)
- [x] Subscribe to all depth camera topics
- [ ] Log actual message formats
- [ ] Understand `/detected_people_array` structure
- [ ] Determine which topics have useful data

### Phase 2: Basic Awareness
- [ ] Parse people positions from detection array
- [ ] Calculate distance from robot
- [ ] Expose people count to CommandBuffer
- [ ] Simple "people nearby" boolean

### Phase 3: Tour Integration
- [ ] Greeting trigger on person detection
- [ ] Group count at tour start
- [ ] Following detection during tour
- [ ] Speed adjustment based on group distance

### Phase 4: Advanced Features
- [ ] Facing direction detection
- [ ] Path blocking detection
- [ ] Individual person tracking (IDs)
- [ ] Narration timing based on attention

### Phase 5: Polish
- [ ] Configurable thresholds per venue
- [ ] Natural language variations
- [ ] Learn typical group behavior
- [ ] Handle edge cases (person leaves, new person joins)

---

## Message Format Discovery

When we get real data, document the actual formats here:

### `/detected_people_array`
```json
// TODO: Log actual message and paste here
{
    "people": [
        {
            "id": "?",
            "position": { "x": ?, "y": ?, "z": ? },
            "velocity": { "x": ?, "y": ?, "z": ? },
            "orientation": ?
        }
    ]
}
```

### `/obstacle_region`
```json
// TODO: Log actual message and paste here
```

### `/upcamera/depth/points`
```json
// PointCloud2 format
{
    "height": ?,
    "width": ?,
    "fields": [...],
    "point_step": ?,
    "data": "base64..."
}
```

---

## Announcements Library

### Greetings
- "Welcome to the Robotics Floor! Would you like a tour?"
- "Hello there! I'm your tour guide robot. Ready for a tour?"
- "Hi! I can show you around if you'd like."

### Following
- "Take your time, I'll wait!"
- "No rush, I'm right here."
- "Hello? Still with me?"
- "I seem to have lost my tour group. I'll wait here."

### Blocking
- "Excuse me, may I pass through?"
- "Pardon me, I need to get by."
- "Could you step aside please? I need to move that way."

### Tour Progress
- "Follow me to our next stop!"
- "Right this way, everyone."
- "We're heading to [destination] next."
- "Almost there!"

### Attention
- "Over here, everyone!"
- "If I could have your attention..."
- "Take a look at this..."

---

## Open Questions

1. **What's in `/detected_people_array`?** - Need real data to know format
2. **Does it include facing direction?** - Or do we need to infer?
3. **How reliable is person tracking?** - Do IDs persist across frames?
4. **What's `/obstacle_region` format?** - Polygons? Bounding boxes?
5. **Can we distinguish people from other obstacles?** - Or just "obstacle near path"?

---

## Related Files

- `relay_app/.../RobotWebSocketClient.kt` - Topic subscriptions
- `relay_app/.../CommandBuffer.kt` - Tour execution, motion standby
- `relay_app/.../ChassisProtocol.kt` - Topic constants
- `flutter_app/.../audio_announcer.dart` - Speech output
