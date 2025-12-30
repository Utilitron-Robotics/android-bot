import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/robot_connection.dart';
import '../services/audio_announcer.dart';

/// Virtual joystick for manual robot control
class JoystickControl extends StatefulWidget {
  const JoystickControl({super.key});

  @override
  State<JoystickControl> createState() => _JoystickControlState();
}

class _JoystickControlState extends State<JoystickControl> {
  double _linearVel = 0;
  double _angularVel = 0;
  Timer? _sendTimer;
  bool _slamSafe = false; // SLAM-safe mode (slower, announces obstacles)
  bool _audioEnabled = true;

  // Speed limits - reduced when SLAM-safe is on
  static const double maxLinearFast = 0.5; // m/s - full speed
  static const double maxLinearSafe = 0.25; // m/s - safe mode
  static const double maxAngularFast = 1.0; // rad/s
  static const double maxAngularSafe = 0.5; // rad/s
  static const double joystickSize = 200;

  double get _maxLinear => _slamSafe ? maxLinearSafe : maxLinearFast;
  double get _maxAngular => _slamSafe ? maxAngularSafe : maxAngularFast;

  @override
  void initState() {
    super.initState();
    AudioAnnouncer().init();
  }

  @override
  void dispose() {
    _sendTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header with title
            Row(
              children: [
                Icon(Icons.gamepad,
                  color: _slamSafe ? Colors.orange : null),
                const SizedBox(width: 8),
                Text(
                  'Manual Control',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (_slamSafe)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('SAFE',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Control toggles row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // SLAM Safe toggle
                FilterChip(
                  label: const Text('SLAM Safe'),
                  avatar: Icon(_slamSafe ? Icons.shield : Icons.shield_outlined,
                    size: 18),
                  selected: _slamSafe,
                  selectedColor: Colors.orange.shade700,
                  onSelected: (value) {
                    setState(() => _slamSafe = value);
                    if (_audioEnabled) {
                      AudioAnnouncer().speak(
                        value ? 'Safe mode on. Speed reduced.' : 'Safe mode off. Full speed.');
                    }
                  },
                ),
                const SizedBox(width: 12),
                // Audio toggle
                FilterChip(
                  label: const Text('Audio'),
                  avatar: Icon(_audioEnabled ? Icons.volume_up : Icons.volume_off,
                    size: 18),
                  selected: _audioEnabled,
                  selectedColor: Colors.blue.shade700,
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
            const SizedBox(height: 16),

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

            // Velocity display
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _VelocityIndicator(
                  label: 'Linear',
                  value: _linearVel,
                  max: _maxLinear,
                  unit: 'm/s',
                ),
                const SizedBox(width: 32),
                _VelocityIndicator(
                  label: 'Angular',
                  value: _angularVel,
                  max: _maxAngular,
                  unit: 'rad/s',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _slamSafe
                ? 'Safe mode: Reduced speed (${maxLinearSafe}m/s max)'
                : 'Drag to control • Full speed (${maxLinearFast}m/s)',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: _slamSafe ? Colors.orange : Colors.grey,
              ),
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
    _sendTimer?.cancel();
    setState(() {
      _linearVel = 0;
      _angularVel = 0;
    });
    _sendVelocity(); // Send zero to stop
  }

  void _sendVelocity() {
    final robot = context.read<RobotConnection>();
    robot.sendVelocity(_linearVel, _angularVel);
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
      Paint()..color = Colors.black.withOpacity(0.3),
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
