# Gemini Suggestions - Task List

## Status Key
- [x] Completed
- [~] Skipped / Not Applicable
- [ ] Still TODO

---

## Completed

### [x] **1.1** Add API authentication to AWS endpoints
- Added `ApiKeyValue` parameter to CloudFormation template
- Lambda now validates `X-API-Key` header for POST/PUT/DELETE operations
- Updated `push_tour_to_dynamo.py` and `push_waypoints_and_tour.py` to use `FLEET_API_KEY` env var
- Flutter client already sends `X-API-Key` header when configured

### [x] **4.1** Externalize hardcoded robot IP configuration
- Added config values to `relay_app/app/src/main/res/values/strings.xml`
- Updated `RelayService.kt` to read from SharedPreferences with fallback to string resources
- Added `updateRobotConnection()` method for runtime configuration
- Added `getRobotConnectionSettings()` to query current config

### [x] **4.2** Add ProGuard/R8 rules for release builds
- Expanded `relay_app/app/proguard-rules.pro` with rules for:
  - gRPC / Protobuf
  - Kotlin Coroutines
  - OkHttp / WebSocket
  - Gson serialization
  - AWS SDK
- Enabled `minifyEnabled true` and `shrinkResources true` in release build

---

## Skipped / Not Applicable

### [~] **WiFi Cracker** - Keeping as developer tool
- Located at: `scripts/wifi_cracker.sh` (assumed)
- **TODO:** SSH into robot base and change default password from `123456789`
- User decision: Keep for development purposes

### [~] **P0 Bugs from PRODUCTION_READINESS_REVIEW.md**
The following files don't exist in this codebase:
- `FakeTourRepository` - **Does not exist**
- `MasterTourRepository` - **Does not exist**
- `TourManager.kt` - **Does not exist**
- `RealTourRepositoryTest.kt` - **Does not exist**

**Actual architecture uses:**
- `SequenceManager` singleton (lib/core/sequence_mode.dart)
- `BufferSequenceExecutor` for relay-based tour execution
- `SequenceTaskMode` as fallback executor
- `CommandBuffer.kt` for relay-side command queue

These classes don't have the bugs described in the Gemini review.

### [~] **Waypoint order lost on save (List to Set)**
- Investigated `sequence_editor.dart:1700` - uses `.toSet()` only for membership checking (`.contains()`)
- Dart's default Set is LinkedHashSet which preserves insertion order
- No ordering bug found in current codebase

---

## Still TODO (Lower Priority)

### [ ] **Architecture: Refactor RelayService God Object**
- `RelayService.kt` handles: gRPC, WebSocket, TTS, cloud sync, obstacle detection
- **Recommendation:** Split into separate services when time permits
- **Impact:** Code maintainability, not functionality

### [ ] **Architecture: Add Dependency Injection**
- Currently uses manual instantiation
- **Recommendation:** Add Koin or Hilt for better testability
- **Impact:** Code maintainability, not functionality

### [ ] **Security: SSH into robot base and change default WiFi password**
- Default password `123456789` is well-known for Chinese robot bases
- **Priority:** Do when physically at the robot location

---

## Summary

**3 tasks completed:**
1. API Key authentication for AWS endpoints
2. Externalized robot IP configuration
3. Comprehensive ProGuard rules for release builds

**Several Gemini suggestions were not applicable:**
- Referenced files that don't exist in codebase (FakeTourRepository, MasterTourRepository, TourManager)
- Current architecture uses different patterns (SequenceManager, BufferSequenceExecutor)
- Code quality is already good - no race conditions found in CommandBuffer

**README Status:** Already comprehensive and accurate.
