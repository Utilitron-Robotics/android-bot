# Hardcoded Time Values

This document lists all instances of hardcoded time values (delays, waits, timeouts) found in the codebase. These should be reviewed and potentially replaced with configurable settings to improve flexibility and maintainability.

## Android App (`relay_app` and `app`)

### `relay_app/app/src/main/java/com/chassis/robotrelay/cloud/AwsIotClient.kt`
- L163: `delay(5000)` - 5-second delay for reporting.
- L208: `delay(2000)` - 2-second delay for polling.

### `relay_app/app/src/main/java/com/chassis/robotrelay/service/CloudTtsService.kt`
- L276: `delay(500)` - 0.5-second delay for rate limiting.

### `relay_app/app/src/main/java/com/chassis/robotrelay/service/CommandBuffer.kt`
- L192: `delay(2000)` - 2-second delay.
- L225: `delay(1000)` - 1-second delay.
- L277: `delay(100)` - 0.1-second delay.
- L283: `delay(100)` - 0.1-second delay with comment "Nothing to do, wait a bit".
- L343: `delay(100)` - 0.1-second delay.
- L410: `delay(300)` - 0.3-second delay.
- L416: `delay(1500)` - 1.5-second delay.
- L425: `delay(200)` - 0.2-second delay.
- L453: `delay(200)` - 0.2-second delay.
- L474: `delay(200)` - 0.2-second delay.
- L483: `delay(300)` - 0.3-second delay.
- L577: `delay(100)` - 0.1-second delay.
- L605: `delay(500)` - 0.5-second delay for sound to play.
- L626: `delay(500)` - 0.5-second delay.

### `relay_app/app/src/main/java/com/chassis/robotrelay/service/RelayServer.kt`
- L141: `delay(1000)` - 1-second delay.
- L167: `delay(10_000)` - 10-second delay.
- L209: `delay(100)` - 0.1-second delay with comment "Reduced from 500ms for faster recovery".
- `PING_INTERVAL_MS` is a constant, but used in `delay()`.

### `relay_app/app/src/main/java/com/chassis/robotrelay/service/RobotWebSocketClient.kt`
- L35: `RECONNECT_DELAY_MS = 1000L` - constant for 1-second reconnect delay.
- L95: `delay(500)` - 0.5-second delay.
- L239: `delay(300)` - 0.3-second delay.
- L247: `delay(2000)` - 2-second delay.

### `relay_app/app/src/main/java/com/chassis/robotrelay/service/RelayService.kt`
- L204: `delay(30_000)` - 30-second delay.
- L879: `delay(100)` - 0.1-second delay.
- L881: `delay(100)` - 0.1-second delay.
- L895: `delay(50)` - 50ms delay.
- L897: `delay(50)` - 50ms delay.
- L905: `delay(30)` - 30ms delay.
- L907: `delay(30)` - 30ms delay.
- L909: `delay(30)` - 30ms delay.
- L979: `Thread.sleep(durationMs.toLong() + 50)` - blocking sleep with 50ms added.

### `relay_app/app/src/main/java/com/chassis/robotrelay/ui/MainActivity.kt`
- L555: `delay(100)` - 0.1-second delay.

### `relay_app/app/src/main/java/com/chassis/robotrelay/grpc/GrpcServer.kt`
- L92: `delay(30_000)` - 30-second delay.
- L29: `KEEPALIVE_TIMEOUT_MS = 5_000L` - 5-second timeout.

### `app/src/fake/java/com/opendroids/tourbot/robot/FakeRobot.kt`
- L16: `delay(1000)` - 1-second delay.
- L34: `delay(1000)` - 1-second delay.
- L40: `delay(3000)` - 3-second delay.
- L46: `delay(2000)` - 2-second delay.

### `app/src/prod/java/com/opendroids/tourbot/robot/RobotRobot.kt`
- L51: `delay(5000)` - 5-second delay.

## Flutter App (`flutter_app`)

### `flutter_app/lib/widgets/map_view.dart`
- L281: `Future.delayed(const Duration(seconds: 2), ...)` - 2-second delay.

### `flutter_app/lib/widgets/joystick.dart`
- L491: `Future.delayed(const Duration(milliseconds: 100), ...)` - 0.1-second delay.
- L511: `Future.delayed(const Duration(milliseconds: 100), ...)` - 0.1-second delay.

### `flutter_app/lib/widgets/waypoint_grid.dart`
- L297: `Future.delayed(const Duration(milliseconds: 1500), ...)` - 1.5-second delay.
- L364: `int _waitSeconds = 30;` - default 30-second wait.

### `flutter_app/lib/services/audio_announcer.dart`
- L330: `delaySeconds: 30`
- L337: `delaySeconds: 45`
- L344: `delaySeconds: 60`
- L351: `delaySeconds: 90`
- L358: `delaySeconds: 120`
- L365: `delaySeconds: 180`

### `flutter_app/lib/screens/hud_screen.dart`
- L235: `Future.delayed(const Duration(milliseconds: 1500), ...)` - 1.5-second delay.
- L1716: `Future.delayed(const Duration(milliseconds: 100), ...)` - 0.1-second delay.
- L2727: `int _waitSeconds = 30;` - default 30-second wait.

### `flutter_app/lib/core/dual_connection.dart`
- L317: `await Future.delayed(const Duration(milliseconds: 200));` - 0.2-second delay.

### `flutter_app/lib/core/task_engine.dart`
- L668: `await Future.delayed(const Duration(milliseconds: 500));` - 0.5-second delay.
- L110: `int waitSeconds = 30`
- L167: `int laughterWait = 3`
- L202: `int waitSeconds = 30`
- L237: `int waitSeconds = 20`
- L296: `durationSeconds: 10`

### `flutter_app/lib/core/sequence_mode.dart`
- L1272: `Future.delayed(const Duration(seconds: 3), ...)` - 3-second delay.
- L1374: `await Future.delayed(const Duration(milliseconds: 500));` - 0.5-second delay.
- L1507: `Future.delayed(const Duration(seconds: 3), ...)` - 3-second delay.
- L158: `waitSeconds: 5`
- L182: `waitSeconds: 3`
- L217: `waitSeconds: 30`
- L235: `waitSeconds: 20`
- L272: `waitSeconds: 5`
- L310: `waitSeconds: dwellSeconds` (from parameter)
- L323: `int waitSeconds = 60`
- L342: `waitSeconds: 10`

### `flutter_app/lib/core/fleet_discovery.dart`
- L373: `await Future.delayed(const Duration(seconds: 2));` - 2-second delay.
- L406: `await Future.delayed(const Duration(milliseconds: 500));` - 0.5-second delay.

### `flutter_app/lib/core/buffer_sequence_executor.dart`
- L381: `Future.delayed(const Duration(milliseconds: 500), ...)` - 0.5-second delay.
- L737: `Future.delayed(const Duration(seconds: 3), ...)` - 3-second delay.
- L572: `final waitMs = ((wordCount / 2.5) * 1000).round() + 1000;` - calculation with hardcoded values.
- L601: `commands.add(BufferCommand.wait(500));` - 0.5-second pause.
- L642: `commands.add(BufferCommand.wait(5000));` - 5-second wait.
- L649: `commands.add(BufferCommand.wait(3000));` - 3-second wait.

### `flutter_app/lib/core/task_mode.dart`
- L231: `await Future.delayed(const Duration(seconds: 1));` - 1-second delay.

### `flutter_app/lib/core/sequence_task_mode.dart`
- L426: `await Future.delayed(const Duration(milliseconds: 500));` - 0.5-second delay.

## Legacy Python (`legacy_python_source`)

### `legacy_python_source/tests/test_battery_reading.py`
- L129: `await asyncio.sleep(1)` - 1-second sleep in a test.

### `legacy_python_source/tests/conftest.py`
- L76: `await asyncio.sleep(0.01)` - 10ms sleep in a test fixture.
- L59: `message = await asyncio.wait_for(websocket.recv(), timeout=0.1)` - 0.1s timeout in test fixture.

### `legacy_python_source/adapters/tibo/tibo_client.py`
- L45: `close_timeout=10` - 10-second timeout for websocket closing.

### `legacy_python_source/adapters/tibo/tibo_commands.py`
- L218: `max_idle_messages = 50` - not a time value, but a hardcoded limit to prevent infinite waiting.

## Scripts

### `push_tour_to_dynamo.py`
- L66: `"wait_seconds": 15 if waypoint_name != "start" and waypoint_name != "end" else 5` - hardcoded 15 or 5 seconds.

### `push_waypoints_and_tour.py`
- L117: `"wait_seconds": 15 if waypoint_name not in ["start", "end"] else 5` - hardcoded 15 or 5 seconds.
