import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/robot_connection.dart';

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

  static const double maxLinear = 0.5; // m/s
  static const double maxAngular = 1.0; // rad/s
  static const double joystickSize = 200;

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
            Row(
              children: [
                const Icon(Icons.gamepad),
                const SizedBox(width: 8),
                Text(
                  'Manual Control',
                  style: Theme.of(context).textTheme.titleLarge,
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
                    maxLinear: maxLinear,
                    maxAngular: maxAngular,
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
                  max: maxLinear,
                  unit: 'm/s',
                ),
                const SizedBox(width: 32),
                _VelocityIndicator(
                  label: 'Angular',
                  value: _angularVel,
                  max: maxAngular,
                  unit: 'rad/s',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Drag to control robot movement',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
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

    // Calculate velocities from joystick position
    // Forward/backward from Y axis, rotation from X axis
    setState(() {
      _linearVel = (-position.dy / (joystickSize / 2)) * maxLinear;
      _angularVel = (-position.dx / (joystickSize / 2)) * maxAngular;

      // Clamp values
      _linearVel = _linearVel.clamp(-maxLinear, maxLinear);
      _angularVel = _angularVel.clamp(-maxAngular, maxAngular);
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

  _JoystickPainter({
    required this.linearVel,
    required this.angularVel,
    required this.maxLinear,
    required this.maxAngular,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Background circle
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.grey.shade800
        ..style = PaintingStyle.fill,
    );

    // Border
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.grey.shade600
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Crosshairs
    final linePaint = Paint()
      ..color = Colors.grey.shade600
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

    // Knob
    canvas.drawCircle(
      Offset(knobX, knobY),
      30,
      Paint()
        ..color = Colors.blue
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      Offset(knobX, knobY),
      30,
      Paint()
        ..color = Colors.blue.shade300
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _JoystickPainter oldDelegate) {
    return oldDelegate.linearVel != linearVel ||
        oldDelegate.angularVel != angularVel;
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
