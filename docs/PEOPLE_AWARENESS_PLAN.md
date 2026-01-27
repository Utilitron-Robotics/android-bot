# People Awareness for Tour Bot

## Purpose

Safe, natural interaction with tour groups. The robot must:
- Know when people are present before starting
- Track the group throughout the tour
- Never leave people behind
- Communicate clearly when it needs space to move

This is a public-facing robot that will interact with children and adults. Safety and predictability are paramount.

---

## Current System Analysis

### What We Have Working

#### 1. People Detection (RobotWebSocketClient.kt)

**Topic**: `/people_detected` (std_msgs/Bool)
```kotlin
// Line 77-78
private val _peopleDetected = MutableStateFlow(false)
val peopleDetected: StateFlow<Boolean> = _peopleDetected

// Line 548-555 - parsing
ChassisProtocol.TOPIC_PEOPLE_DETECTED -> {
    val detected = msg.get("data")?.asBoolean ?: false
    if (detected != _peopleDetected.value) {
        Log.d(TAG, ">>> PEOPLE_DETECTED: $detected")
        _peopleDetected.value = detected
    }
}
```

**What it tells us**: Binary yes/no - someone is in front of the robot's depth camera.

**Limitation**: No count, no position, no distance.

#### 2. Rich People Array (RobotWebSocketClient.kt)

**Topic**: `/detected_people_array` (yutong_assistance/PersonArray)
```kotlin
// Line 556-576 - we subscribe but only log, don't parse fully yet
ChassisProtocol.TOPIC_DETECTED_PEOPLE_ARRAY -> {
    val people = msg.get("people")?.asJsonArray
        ?: msg.get("data")?.asJsonArray
        ?: msg.get("detections")?.asJsonArray
        ?: msg.get("persons")?.asJsonArray
    if (people != null && people.size() > 0) {
        Log.d(TAG, ">>> DETECTED_PEOPLE_ARRAY: ${people.size()} people detected")
    }
}
```

**What it should tell us**: Count, positions, possibly tracking IDs. Message format needs verification from live robot data.

#### 3. Obstacle Classification (ObstacleClassifier.kt)

Classifies LIDAR obstacles:
- `MOVING_PERSON` - Human-sized (0.3-1.2m width), moving
- `CROWD` - Multiple moving entities
- `STATIC_PERSON` - Person standing still
- `STATIC_EXPECTED` - Wall/mapped obstacle
- `STATIC_UNEXPECTED` - Unknown static object

**Used by**: `RobotWebSocketClient.sendVelocity()` for intelligent speed decisions.

#### 4. Crowd Control Speed Ramping (RobotWebSocketClient.kt:678-712)

```kotlin
fun sendVelocity(linearX: Double, angularZ: Double) {
    // During nav, move_base controls - don't interfere
    val isNavigating = _robotStatus.value?.navStatus == 601
    if (isNavigating) return

    var adjustedLinear = linearX

    if (linearX > 0) {
        val distance = minFrontDistance.toDouble()
        val obstacleType = _robotStatus.value?.obstacleType ?: "CLEAR"
        val peopleNearby = _peopleDetected.value

        // Wall: hard stop (don't push through)
        // Human/crowd: gradient push-through (they'll move)
        val isWall = obstacleType == "STATIC_EXPECTED"
        val isHuman = obstacleType in listOf("MOVING_PERSON", "CROWD", "STATIC_PERSON")
        val treatAsCrowd = isHuman || (peopleNearby && obstacleType == "UNKNOWN")

        if (distance < crowdSafeDistance) {
            if (isWall && !_detachMode.value) {
                adjustedLinear = 0.0  // Hard stop for walls
            } else {
                // Gradient ramp for people
                val fraction = (distance / crowdSafeDistance).coerceIn(0.0, 1.0)
                val rampedFraction = Math.pow(fraction, crowdRampRate)
                val minFraction = CREEP_SPEED / linearX.coerceAtLeast(CREEP_SPEED)
                adjustedLinear = linearX * rampedFraction.coerceAtLeast(minFraction)
            }
        }
    }
    send(ChassisProtocol.publishVelocity(adjustedLinear, angularZ))
}
```

**Key insight**: Robot already distinguishes people from walls. Slows down for people (they'll move), hard stops for walls.

#### 5. Motion Standby (CommandBuffer.kt:817-861)

```kotlin
"motion_standby" -> {
    val greeting = cmd.data["greeting"] as? String ?: "Hello! Would you like a tour?"

    // Wait for person detected
    while (currentCommand != null && !robotClient.peopleDetected.value) {
        delay(200)
    }

    // Speak greeting
    taskExecutor?.speakText(greeting) { ttsComplete.complete(Unit) }
    ttsComplete.await()

    // Auto-start tour
    taskExecutor?.startTourMode(pin)
    completeCommand(cmd.id, "success")
}
```

**What it does**: Waits for `/people_detected` to go true, speaks greeting, auto-starts tour.

#### 6. Button Standby with Greeting (CommandBuffer.kt:863-950)

```kotlin
"button_standby" -> {
    // Show button immediately
    taskExecutor?.notifyTourStandby(sequenceId, buttonText)

    // RISING EDGE detection - greet on approach, not departure
    var wasDetectedLastCycle = false

    while (currentCommand != null) {
        delay(500)
        val peopleDetected = robotClient.peopleDetected.value
        val risingEdge = peopleDetected && !wasDetectedLastCycle

        if (risingEdge && timeSinceStart > initialDelayMs) {
            if (lastGreetingTime == 0L || now - lastGreetingTime > greetingCooldownMs) {
                taskExecutor?.speakText(greetingText) { }
                lastGreetingTime = now
            }
        }
        wasDetectedLastCycle = peopleDetected
    }
}
```

**Key insight**: Already uses rising-edge detection to greet people approaching, not leaving. 30-second cooldown prevents spam.

---

## What We Need to Add

### 1. People Count

**Current**: Binary (someone/no one)
**Need**: Actual count from `/detected_people_array`

**Where to add**: `RobotWebSocketClient.kt`
```kotlin
// Add state
private val _peopleCount = MutableStateFlow(0)
val peopleCount: StateFlow<Int> = _peopleCount

// In TOPIC_DETECTED_PEOPLE_ARRAY handler
val people = msg.get("people")?.asJsonArray ?: ...
_peopleCount.value = people?.size() ?: 0
```

**Use case**: "I see 3 people. Follow me!" vs "I see someone approaching."

### 2. Group Distance Tracking

**Current**: `minFrontDistance` - closest obstacle
**Need**: Average/median distance of detected people

**Where to add**: `RobotWebSocketClient.kt`
```kotlin
// Add state
@Volatile
var avgPeopleDistance: Float = Float.MAX_VALUE
    private set

// In TOPIC_DETECTED_PEOPLE_ARRAY handler
// Parse person positions, calculate distances, average them
```

**Use case**: Know if group is close (< 2m), following (2-4m), or falling behind (> 4m).

### 3. Tour Group State Machine

**Add to**: `CommandBuffer.kt`

```kotlin
enum class TourGroupState {
    WAITING_FOR_PEOPLE,  // No one detected yet
    GROUP_PRESENT,       // People detected, ready to start
    GROUP_FOLLOWING,     // Tour active, group keeping up
    GROUP_FALLING_BEHIND,// Group > 4m away, slow down
    GROUP_LOST,          // No detection for 10s, stop
    BLOCKING_PATH        // Person in front during nav
}
```

### 4. Following Detection During Navigation

**Modify**: `CommandBuffer.kt` navigate command (line 455-699)

```kotlin
// Inside navigation while loop, add:
val peopleCount = robotClient.peopleCount.value
val groupDistance = robotClient.avgPeopleDistance

when {
    groupDistance > 5.0 && peopleCount > 0 -> {
        // Group falling way behind - stop and call out
        if (!calledOutRecently) {
            robotClient.stop()
            taskExecutor?.speakText("Hello? Is everyone still with me?")
            calledOutRecently = true
            delay(5000)  // Wait for them to catch up
        }
    }
    groupDistance > 3.0 && peopleCount > 0 -> {
        // Group falling behind - slow down
        // (handled by crowd control, but announce once)
        if (!slowedDownAnnounced) {
            taskExecutor?.speakText("Take your time, I'll wait for you!")
            slowedDownAnnounced = true
        }
    }
    peopleCount == 0 && wasTrackingGroup -> {
        // Lost the group entirely
        lostGroupTime = lostGroupTime ?: System.currentTimeMillis()
        if (System.currentTimeMillis() - lostGroupTime > 10_000) {
            robotClient.cancelNavigation()
            taskExecutor?.speakText("I seem to have lost my tour group. Tour paused.")
            // Wait for people to return or manual intervention
        }
    }
}
```

### 5. Path Blocking Communication

**Current**: Robot slows/stops for people in path (crowd control handles this)
**Need**: Verbal communication when blocked during tour

**Modify**: `RobotWebSocketClient.kt` or `CommandBuffer.kt`

```kotlin
// When obstacle classifier detects MOVING_PERSON or STATIC_PERSON in path
// AND robot is navigating AND velocity is near zero for > 3 seconds:
if (blockedByPerson && blockedDuration > 3000 && !askedToMoveRecently) {
    taskExecutor?.speakText("Excuse me, may I pass through?")
    askedToMoveRecently = true
    askedToMoveAt = System.currentTimeMillis()
}

// If still blocked after 10 more seconds:
if (blockedByPerson && blockedDuration > 13000 && askedToMoveRecently) {
    taskExecutor?.speakText("I need to get to our next stop. Could you please step aside?")
}
```

---

## Safety Considerations

### 1. Never Surprise People
- Always announce before moving
- "Follow me to our next stop!" before navigation starts
- Don't start moving until people have had time to hear and react

### 2. Never Leave People Behind
- Track group distance continuously
- Stop and call out if group > 5m away
- Pause tour if group lost for > 10 seconds

### 3. Never Push Through
- Crowd control already handles this (gradient slowdown)
- Add verbal communication so people understand why robot stopped
- Robot should never feel aggressive or pushy

### 4. Clear Communication
- Use simple, friendly language
- Don't talk too much (annoying)
- Speak loud enough to be heard
- Give people time to respond

### 5. Predictable Behavior
- Same stimulus = same response
- Don't make sudden movements
- Telegraph intentions before acting

---

## Implementation Priority

### Phase 1: Parse People Data (Required First)
1. Parse `/detected_people_array` to get count and positions
2. Expose `peopleCount` and `avgPeopleDistance` from RobotWebSocketClient
3. Verify message format with live robot data

### Phase 2: Following Detection
1. Add distance tracking during navigate command
2. Add "falling behind" slowdown + announcement
3. Add "group lost" stop + announcement

### Phase 3: Blocking Communication
1. Detect when stopped by person (not wall)
2. Add polite "excuse me" after 3 seconds
3. Add more direct request after 10+ seconds

### Phase 4: Tour Start Enhancement
1. Announce group count: "I see 3 people ready for the tour!"
2. "Follow me!" announcement before first movement
3. Brief pause after announcement before moving

---

## File Locations

| Feature | File | Lines |
|---------|------|-------|
| People detection state | `RobotWebSocketClient.kt` | 77-78, 548-555 |
| Rich people array parsing | `RobotWebSocketClient.kt` | 556-576 |
| Obstacle classifier | `ObstacleClassifier.kt` | Full file |
| Crowd control speed ramping | `RobotWebSocketClient.kt` | 678-712 |
| Motion standby | `CommandBuffer.kt` | 817-861 |
| Button standby with greeting | `CommandBuffer.kt` | 863-950 |
| Navigation execution | `CommandBuffer.kt` | 455-699 |
| TTS output | `RelayServer.TaskExecutor` | `speakText()` |

---

## Testing Checklist

- [ ] Robot announces group count before tour starts
- [ ] Robot announces "Follow me!" before moving
- [ ] Robot slows down when group falls behind (3-4m)
- [ ] Robot stops and calls out when group far behind (>5m)
- [ ] Robot pauses tour if group lost for 10+ seconds
- [ ] Robot says "Excuse me" when blocked by person
- [ ] Robot never pushes through people
- [ ] Robot never starts moving without warning
- [ ] Announcements are audible but not too frequent
- [ ] Works with 1 person, 3 people, 10 people
