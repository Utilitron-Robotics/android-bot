import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/robot_connection.dart';
import '../core/chassis_protocol.dart';
import '../services/audio_announcer.dart';

/// Robot speed mode - controls built-in collision avoidance behavior
enum RobotSpeedMode {
  safetyLow(0, 'Safety Low', 'Most cautious - slow, large stop distance'),
  safetyMed(1, 'Safety Med', 'Balanced safety - moderate speed'),
  safetyHigh(2, 'Safety High', 'Less cautious - faster, shorter stop distance'),
  balanceLow(3, 'Balance Low', 'Balanced mode - conservative'),
  balanceMed(4, 'Balance Med', 'Balanced mode - moderate'),
  balanceHigh(5, 'Balance High', 'Balanced mode - aggressive'),
  efficiencyLow(6, 'Efficiency Low', 'Speed focused - conservative'),
  efficiencyMed(7, 'Efficiency Med', 'Speed focused - moderate'),
  efficiencyHigh(8, 'Efficiency High', 'Speed focused - fastest');

  final int value;
  final String label;
  final String description;
  const RobotSpeedMode(this.value, this.label, this.description);

  static RobotSpeedMode fromValue(int v) {
    return RobotSpeedMode.values.firstWhere(
      (m) => m.value == v,
      orElse: () => RobotSpeedMode.safetyMed,
    );
  }
}

/// Virtual joystick for manual robot control
class JoystickControl extends StatefulWidget {
  /// Ultrasonic distance in cm (from relay heartbeat), null if not available
  final double? ultrasonicCm;
  /// Whether ultrasonic detects blocking obstacle
  final bool ultrasonicBlocked;

  const JoystickControl({
    super.key,
    this.ultrasonicCm,
    this.ultrasonicBlocked = false,
  });

  @override
  State<JoystickControl> createState() => _JoystickControlState();
}

class _JoystickControlState extends State<JoystickControl> {
  double _linearVel = 0;       // Target velocity from joystick
  double _angularVel = 0;
  double _actualLinear = 0;    // Actual velocity being sent (for ramping)
  double _actualAngular = 0;
  Timer? _sendTimer;
  bool _slamSafe = false; // SLAM-safe mode (slower, stops on obstacles)
  bool _audioEnabled = true;
  bool _obstacleAhead = false;
  bool _obstacleLeft = false;
  bool _obstacleRight = false;
  double _minFrontRange = double.infinity;
  RobotConnection? _safetySource;
  RobotSpeedMode _robotSpeedMode = RobotSpeedMode.safetyMed;
  bool _speedModeLoading = false;

  // Speed limits
  static const double maxLinearFast = 0.5; // m/s - full speed
  static const double maxAngularFast = 1.0; // rad/s
  static const double joystickSize = 200;

  // Obstacle zones for graduated response
  static const double stopDistance = 0.20;    // meters - full stop
  static const double creepDistance = 0.50;   // meters - creep speed
  static const double warnDistance = 0.80;    // meters - warning only
  static const double creepSpeed = 0.05;      // m/s - very slow creep

  // Acceleration limits for smooth ramping (per 100ms tick)
  static const double linearAccel = 0.08;     // m/s per tick - accelerate
  static const double linearDecel = 0.12;     // m/s per tick - decelerate (faster)
  static const double angularAccel = 0.15;    // rad/s per tick

  // SLAM Safe allows full speed - obstacle avoidance handles slowing
  double get _maxLinear => maxLinearFast;
  double get _maxAngular => maxAngularFast;

  @override
  void initState() {
    super.initState();
    AudioAnnouncer().init();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _subscribeToSafetyStatus();
      _querySpeedMode();
    });
  }

  void _subscribeToSafetyStatus() {
    // Relay-computed LIDAR safety from /relay/safety over the live WebSocket
    final robot = context.read<RobotConnection>();
    _safetySource = robot;
    robot.addListener(_onSafetyUpdate);
    _onSafetyUpdate();
  }

  void _onSafetyUpdate() {
    if (!mounted) return;
    final robot = _safetySource;
    if (robot == null) return;

    final minRange = robot.minRangeMeters;

    double distance;
    if (robot.safetyStale) {
      // No fresh safety data (relay keepalive missing) - treat LIDAR as dead
      distance = -1;
    } else if (minRange != null && minRange > 0 && minRange < 100) {
      // Real LIDAR distance from relay
      distance = minRange;
    } else {
      distance = double.infinity;
    }

    if (distance == _minFrontRange) return;
    setState(() {
      _minFrontRange = distance;
      _obstacleAhead = distance > 0 && distance < creepDistance;
    });
  }

  Future<void> _querySpeedMode() async {
    final robot = context.read<RobotConnection>();
    if (!robot.isConnected) return;

    setState(() => _speedModeLoading = true);
    try {
      final result = await robot.client.callService(
        service: serviceVelocityControl,
        args: {'cmd': speedGetCurrent, 'str': ''},
        timeout: const Duration(seconds: 3),
      );
      final mode = result['values']?['cmd'] as int?;
      if (mode != null && mounted) {
        setState(() => _robotSpeedMode = RobotSpeedMode.fromValue(mode));
      }
    } catch (e) {
      // Ignore - robot may not support this
    } finally {
      if (mounted) setState(() => _speedModeLoading = false);
    }
  }

  Future<void> _setSpeedMode(RobotSpeedMode mode) async {
    final robot = context.read<RobotConnection>();
    if (!robot.isConnected) return;

    setState(() => _speedModeLoading = true);
    try {
      await robot.client.callService(
        service: serviceVelocityControl,
        args: {'cmd': mode.value, 'str': ''},
        timeout: const Duration(seconds: 3),
      );
      if (mounted) {
        setState(() => _robotSpeedMode = mode);
        if (_audioEnabled) {
          AudioAnnouncer().speak('Speed mode: ${mode.label}');
        }
      }
    } catch (e) {
      // Show error
    } finally {
      if (mounted) setState(() => _speedModeLoading = false);
    }
  }

  @override
  void dispose() {
    _sendTimer?.cancel();
    _safetySource?.removeListener(_onSafetyUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header with title (compact for narrow layouts)
            Row(
              children: [
                Icon(Icons.gamepad, size: 18,
                  color: _slamSafe ? Colors.orange : null),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Control',
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_slamSafe)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('SAFE',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Control toggles - compact for narrow layouts
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                // SLAM Safe toggle (compact)
                FilterChip(
                  label: const Text('Safe', style: TextStyle(fontSize: 11)),
                  avatar: Icon(_slamSafe ? Icons.shield : Icons.shield_outlined,
                    size: 16),
                  selected: _slamSafe,
                  selectedColor: Colors.orange.shade700,
                  visualDensity: VisualDensity.compact,
                  onSelected: (value) {
                    setState(() => _slamSafe = value);
                    if (_audioEnabled) {
                      AudioAnnouncer().speak(
                        value ? 'Safe mode on. Speed reduced.' : 'Safe mode off. Full speed.');
                    }
                  },
                ),
                // Audio toggle (compact)
                FilterChip(
                  label: const Text('Audio', style: TextStyle(fontSize: 11)),
                  avatar: Icon(_audioEnabled ? Icons.volume_up : Icons.volume_off,
                    size: 16),
                  selected: _audioEnabled,
                  selectedColor: Colors.blue.shade700,
                  visualDensity: VisualDensity.compact,
                  onSelected: (value) {
                    setState(() => _audioEnabled = value);
                    AudioAnnouncer().enabled = value;
                    if (value) {
                      AudioAnnouncer().speak('Audio enabled');
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Robot base speed mode selector (compact)
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                const Icon(Icons.speed, size: 14),
                if (_speedModeLoading)
                  const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  DropdownButton<RobotSpeedMode>(
                    value: _robotSpeedMode,
                    isDense: true,
                    underline: Container(height: 1, color: Colors.grey),
                    items: RobotSpeedMode.values.map((mode) {
                      return DropdownMenuItem(
                        value: mode,
                        child: Text(mode.label, style: const TextStyle(fontSize: 11)),
                      );
                    }).toList(),
                    onChanged: (mode) {
                      if (mode != null) _setSpeedMode(mode);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Joystick
            SizedBox(
              width: joystickSize,
              height: joystickSize,
              child: GestureDetector(
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
                child: CustomPaint(
                  painter: _JoystickPainter(
                    linearVel: _linearVel,
                    angularVel: _angularVel,
                    maxLinear: _maxLinear,
                    maxAngular: _maxAngular,
                    safeMode: _slamSafe,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Velocity and Distance display (shows actual ramped velocity)
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                _VelocityIndicator(
                  label: 'Lin',
                  value: _actualLinear,  // Show actual velocity being sent
                  max: _maxLinear,
                  unit: 'm/s',
                ),
                // LIDAR distance gauge
                _DistanceGauge(
                  distance: _minFrontRange,
                  stopDist: stopDistance,
                  creepDist: creepDistance,
                  warnDist: warnDistance,
                ),
                // Ultrasonic gauge (sees cardboard, glass, etc that LIDAR misses)
                if (widget.ultrasonicCm != null)
                  _UltrasonicGauge(
                    distanceCm: widget.ultrasonicCm!,
                    isBlocked: widget.ultrasonicBlocked,
                  ),
                _VelocityIndicator(
                  label: 'Ang',
                  value: _actualAngular,  // Show actual velocity being sent
                  max: _maxAngular,
                  unit: 'r/s',
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Obstacle zone indicator in safe mode (compact)
            if (_slamSafe && _minFrontRange > 0 && _minFrontRange < warnDistance)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: _minFrontRange < stopDistance
                      ? Colors.red.shade900
                      : _minFrontRange < creepDistance
                          ? Colors.orange.shade900
                          : Colors.yellow.shade900,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _minFrontRange < stopDistance
                        ? Colors.red
                        : _minFrontRange < creepDistance
                            ? Colors.orange
                            : Colors.yellow,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _minFrontRange < stopDistance ? Icons.block : Icons.warning,
                      color: _minFrontRange < stopDistance
                          ? Colors.red
                          : _minFrontRange < creepDistance
                              ? Colors.orange
                              : Colors.yellow,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _minFrontRange < stopDistance
                          ? 'STOP ${_minFrontRange.toStringAsFixed(1)}m'
                          : _minFrontRange < creepDistance
                              ? 'CREEP ${_minFrontRange.toStringAsFixed(1)}m'
                              : 'WARN ${_minFrontRange.toStringAsFixed(1)}m',
                      style: TextStyle(
                        color: _minFrontRange < stopDistance
                            ? Colors.red
                            : _minFrontRange < creepDistance
                                ? Colors.orange
                                : Colors.yellow,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            Text(
              _slamSafe
                ? 'Stop<${stopDistance}m Creep<${creepDistance}m'
                : 'Drag • ${maxLinearFast}m/s max',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _slamSafe ? Colors.orange : Colors.grey,
                fontSize: 10,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _onPanStart(DragStartDetails details) {
    _sendTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _sendVelocity();
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    const center = Offset(joystickSize / 2, joystickSize / 2);
    final position = details.localPosition - center;

    setState(() {
      _linearVel = (-position.dy / (joystickSize / 2)) * _maxLinear;
      _angularVel = (-position.dx / (joystickSize / 2)) * _maxAngular;

      _linearVel = _linearVel.clamp(-_maxLinear, _maxLinear);
      _angularVel = _angularVel.clamp(-_maxAngular, _maxAngular);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    // Don't cancel timer immediately - let ramping bring velocity down smoothly
    setState(() {
      _linearVel = 0;
      _angularVel = 0;
    });

    // Keep sending until velocities ramp down to zero
    Future.delayed(const Duration(milliseconds: 100), _rampDownToStop);
  }

  void _rampDownToStop() {
    if (_actualLinear.abs() < 0.01 && _actualAngular.abs() < 0.01) {
      // Fully stopped, cancel timer
      _sendTimer?.cancel();
      setState(() {
        _actualLinear = 0;
        _actualAngular = 0;
      });
      // Send final zero command
      context.read<RobotConnection>().sendVelocity(0, 0);
      return;
    }

    // Continue ramping down
    _sendVelocity();
    if (mounted) {
      setState(() {});  // Update display
      Future.delayed(const Duration(milliseconds: 100), _rampDownToStop);
    }
  }

  void _sendVelocity() {
    final robot = context.read<RobotConnection>();

    // Calculate target velocity based on joystick and obstacles
    double targetLinear = _linearVel;
    double targetAngular = _angularVel;

    // In SLAM Safe mode, graduated obstacle response
    if (_slamSafe && targetLinear > 0) {
      final dist = _minFrontRange;

      if (dist < 0) {
        // Stale LIDAR data - stop forward motion for safety
        targetLinear = 0;
      } else if (dist < stopDistance) {
        // STOP ZONE: Too close - no forward motion at all
        targetLinear = 0;
      } else if (dist < creepDistance) {
        // CREEP ZONE: Scale speed based on distance
        // At stopDistance: creepSpeed (0.05), at creepDistance: 0.15 m/s
        final t = (dist - stopDistance) / (creepDistance - stopDistance);
        final maxCreep = creepSpeed + t * (0.15 - creepSpeed);
        targetLinear = targetLinear.clamp(-maxCreep, maxCreep);
      } else if (dist < warnDistance) {
        // WARNING ZONE: Half speed max
        targetLinear = targetLinear.clamp(-maxLinearFast / 2, maxLinearFast / 2);
      }
      // Beyond warnDistance: full speed allowed
    }

    // Reduce turning towards obstacles
    if (_slamSafe) {
      if (_obstacleLeft && targetAngular > 0) {
        targetAngular = targetAngular * 0.3;
      }
      if (_obstacleRight && targetAngular < 0) {
        targetAngular = targetAngular * 0.3;
      }
    }

    // Apply velocity ramping for smooth acceleration/deceleration
    // This prevents lurching when speed limits change suddenly
    _actualLinear = _rampVelocity(_actualLinear, targetLinear, linearAccel, linearDecel);
    _actualAngular = _rampVelocity(_actualAngular, targetAngular, angularAccel, angularAccel);

    robot.sendVelocity(_actualLinear, _actualAngular);
  }

  /// Smoothly ramp velocity towards target with acceleration limits
  double _rampVelocity(double current, double target, double accel, double decel) {
    final diff = target - current;
    if (diff.abs() < 0.01) {
      // Close enough, snap to target
      return target;
    }

    // Determine if accelerating or decelerating
    // Decelerating = moving towards zero OR reducing magnitude
    final isDecelerating = target.abs() < current.abs() ||
                           (current > 0 && target < current) ||
                           (current < 0 && target > current);

    final rate = isDecelerating ? decel : accel;

    if (diff > 0) {
      return (current + rate).clamp(current, target);
    } else {
      return (current - rate).clamp(target, current);
    }
  }
}

class _JoystickPainter extends CustomPainter {
  final double linearVel;
  final double angularVel;
  final double maxLinear;
  final double maxAngular;
  final bool safeMode;

  _JoystickPainter({
    required this.linearVel,
    required this.angularVel,
    required this.maxLinear,
    required this.maxAngular,
    this.safeMode = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Background circle - orange tint in safe mode
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = safeMode ? Colors.orange.shade900 : Colors.grey.shade800
        ..style = PaintingStyle.fill,
    );

    // Border
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = safeMode ? Colors.orange.shade600 : Colors.grey.shade600
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Crosshairs
    final linePaint = Paint()
      ..color = safeMode ? Colors.orange.shade700 : Colors.grey.shade600
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(center.dx, 0),
      Offset(center.dx, size.height),
      linePaint,
    );
    canvas.drawLine(
      Offset(0, center.dy),
      Offset(size.width, center.dy),
      linePaint,
    );

    // Joystick knob position
    final knobX = center.dx - (angularVel / maxAngular) * (radius * 0.8);
    final knobY = center.dy - (linearVel / maxLinear) * (radius * 0.8);

    // Knob shadow
    canvas.drawCircle(
      Offset(knobX + 2, knobY + 2),
      30,
      Paint()..color = Colors.black.withValues(alpha: 0.3),
    );

    // Knob - orange in safe mode
    canvas.drawCircle(
      Offset(knobX, knobY),
      30,
      Paint()
        ..color = safeMode ? Colors.orange : Colors.blue
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset(knobX, knobY),
      30,
      Paint()
        ..color = safeMode ? Colors.orange.shade300 : Colors.blue.shade300
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _JoystickPainter oldDelegate) {
    return oldDelegate.linearVel != linearVel ||
        oldDelegate.angularVel != angularVel ||
        oldDelegate.safeMode != safeMode;
  }
}

class _VelocityIndicator extends StatelessWidget {
  final String label;
  final double value;
  final double max;
  final String unit;

  const _VelocityIndicator({
    required this.label,
    required this.value,
    required this.max,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(
          '${value.toStringAsFixed(2)} $unit',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontFamily: 'monospace',
              ),
        ),
      ],
    );
  }
}

/// Visual gauge showing distance to nearest obstacle
class _DistanceGauge extends StatelessWidget {
  final double distance;
  final double stopDist;
  final double creepDist;
  final double warnDist;

  const _DistanceGauge({
    required this.distance,
    required this.stopDist,
    required this.creepDist,
    required this.warnDist,
  });

  @override
  Widget build(BuildContext context) {
    // Stale/no LIDAR data sentinel
    final bool isStale = distance < 0;

    // Determine zone and color
    Color zoneColor;
    String zoneLabel;
    if (isStale) {
      zoneColor = Colors.grey;
      zoneLabel = 'NO DATA';
    } else if (distance < stopDist) {
      zoneColor = Colors.red;
      zoneLabel = 'STOP';
    } else if (distance < creepDist) {
      zoneColor = Colors.orange;
      zoneLabel = 'CREEP';
    } else if (distance < warnDist) {
      zoneColor = Colors.yellow;
      zoneLabel = 'WARN';
    } else {
      zoneColor = Colors.green;
      zoneLabel = 'CLEAR';
    }

    // Clamp display distance for gauge
    final displayDist = (isStale || distance.isInfinite) ? 2.0 : distance.clamp(0.0, 2.0);
    final gaugePercent = isStale ? 0.0 : (displayDist / 2.0).clamp(0.0, 1.0);

    return Column(
      children: [
        Text('Distance', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        // Vertical gauge bar
        Container(
          width: 24,
          height: 60,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade600),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              // Background zones
              Column(
                children: [
                  Expanded(
                    flex: ((2.0 - warnDist) / 2.0 * 100).round(),
                    child: Container(color: Colors.green.withValues(alpha: 0.2)),
                  ),
                  Expanded(
                    flex: ((warnDist - creepDist) / 2.0 * 100).round(),
                    child: Container(color: Colors.yellow.withValues(alpha: 0.2)),
                  ),
                  Expanded(
                    flex: ((creepDist - stopDist) / 2.0 * 100).round(),
                    child: Container(color: Colors.orange.withValues(alpha: 0.2)),
                  ),
                  Expanded(
                    flex: (stopDist / 2.0 * 100).round(),
                    child: Container(color: Colors.red.withValues(alpha: 0.2)),
                  ),
                ],
              ),
              // Distance indicator fill
              FractionallySizedBox(
                heightFactor: gaugePercent,
                child: Container(
                  decoration: BoxDecoration(
                    color: zoneColor.withValues(alpha: 0.7),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(3),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Distance value
        Text(
          isStale ? '---' : (distance.isInfinite ? '>2m' : '${distance.toStringAsFixed(2)}m'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            color: zoneColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          zoneLabel,
          style: TextStyle(
            fontSize: 9,
            color: zoneColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

/// Visual gauge for ultrasonic sensor (sees cardboard, glass, etc)
class _UltrasonicGauge extends StatelessWidget {
  final double distanceCm;
  final bool isBlocked;

  // Ultrasonic thresholds (in cm)
  static const double blockDist = 20.0;   // <20cm = blocked
  static const double warnDist = 50.0;    // <50cm = warning
  static const double maxDist = 100.0;    // Display max

  const _UltrasonicGauge({
    required this.distanceCm,
    required this.isBlocked,
  });

  @override
  Widget build(BuildContext context) {
    // Determine zone and color
    Color zoneColor;
    String zoneLabel;
    if (isBlocked || distanceCm < blockDist) {
      zoneColor = Colors.purple;
      zoneLabel = 'BLOCK';
    } else if (distanceCm < warnDist) {
      zoneColor = Colors.deepPurple;
      zoneLabel = 'NEAR';
    } else {
      zoneColor = Colors.indigo;
      zoneLabel = 'OK';
    }

    // Clamp display distance for gauge
    final displayDist = distanceCm.clamp(0.0, maxDist);
    final gaugePercent = (displayDist / maxDist).clamp(0.0, 1.0);

    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sensors, size: 12, color: zoneColor),
            const SizedBox(width: 2),
            Text('US', style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: zoneColor,
            )),
          ],
        ),
        const SizedBox(height: 4),
        // Vertical gauge bar (purple theme for ultrasonic)
        Container(
          width: 24,
          height: 60,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.purple.shade600),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              // Background zones
              Column(
                children: [
                  Expanded(
                    flex: 50,  // 50-100cm = OK
                    child: Container(color: Colors.indigo.withValues(alpha: 0.2)),
                  ),
                  Expanded(
                    flex: 30,  // 20-50cm = warn
                    child: Container(color: Colors.deepPurple.withValues(alpha: 0.2)),
                  ),
                  Expanded(
                    flex: 20,  // 0-20cm = block
                    child: Container(color: Colors.purple.withValues(alpha: 0.3)),
                  ),
                ],
              ),
              // Distance indicator fill
              FractionallySizedBox(
                heightFactor: gaugePercent,
                child: Container(
                  decoration: BoxDecoration(
                    color: zoneColor.withValues(alpha: 0.7),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(3),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Distance value
        Text(
          distanceCm > 99 ? '>99' : '${distanceCm.toStringAsFixed(0)}cm',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            color: zoneColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          zoneLabel,
          style: TextStyle(
            fontSize: 9,
            color: zoneColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
