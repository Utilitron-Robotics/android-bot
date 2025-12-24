import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../core/robot_connection.dart';

/// Voice command input for hands-free robot control
class VoiceControl extends StatefulWidget {
  final List<String> availableWaypoints;

  const VoiceControl({super.key, required this.availableWaypoints});

  @override
  State<VoiceControl> createState() => _VoiceControlState();
}

class _VoiceControlState extends State<VoiceControl> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _isAvailable = false;
  String _lastWords = '';
  String? _recognizedCommand;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    _isAvailable = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          setState(() => _isListening = false);
          _processCommand(_lastWords);
        }
      },
      onError: (error) {
        setState(() => _isListening = false);
      },
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAvailable) {
      return const SizedBox.shrink(); // Hide if speech not available
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.mic),
                const SizedBox(width: 8),
                Text(
                  'Voice Control',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Mic button
            GestureDetector(
              onTapDown: (_) => _startListening(),
              onTapUp: (_) => _stopListening(),
              onTapCancel: _stopListening,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _isListening ? 100 : 80,
                height: _isListening ? 100 : 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isListening ? Colors.red : Colors.blue,
                  boxShadow: _isListening
                      ? [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.5),
                            blurRadius: 20,
                            spreadRadius: 5,
                          )
                        ]
                      : null,
                ),
                child: Icon(
                  _isListening ? Icons.mic : Icons.mic_none,
                  size: 40,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Status text
            Text(
              _isListening
                  ? 'Listening...'
                  : 'Hold to speak',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey,
                  ),
            ),
            if (_lastWords.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '"$_lastWords"',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
              ),
            ],
            if (_recognizedCommand != null) ...[
              const SizedBox(height: 8),
              Chip(
                avatar: const Icon(Icons.check, size: 18),
                label: Text(_recognizedCommand!),
                backgroundColor: Colors.green.withOpacity(0.2),
              ),
            ],
            const SizedBox(height: 16),
            // Example commands
            Text(
              'Try: "Go to kitchen" or "Stop"',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  void _startListening() {
    if (!_isAvailable || _isListening) return;

    setState(() {
      _isListening = true;
      _lastWords = '';
      _recognizedCommand = null;
    });

    _speech.listen(
      onResult: (result) {
        setState(() {
          _lastWords = result.recognizedWords;
        });
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
    );
  }

  void _stopListening() {
    if (!_isListening) return;
    _speech.stop();
  }

  void _processCommand(String text) {
    if (text.isEmpty) return;

    final lower = text.toLowerCase();
    final robot = context.read<RobotConnection>();

    // Check for stop command
    if (lower.contains('stop') || lower.contains('cancel')) {
      robot.cancelNavigation();
      setState(() => _recognizedCommand = 'Stopping robot');
      return;
    }

    // Check for "go to" commands
    if (lower.contains('go to') || lower.contains('goto')) {
      final destination = _extractDestination(lower);
      if (destination != null) {
        robot.goToWaypoint(destination);
        setState(() => _recognizedCommand = 'Going to $destination');
        return;
      }
    }

    // Try to match any waypoint name directly
    for (final wp in widget.availableWaypoints) {
      if (lower.contains(wp.toLowerCase().replaceAll('_', ' '))) {
        robot.goToWaypoint(wp);
        setState(() => _recognizedCommand = 'Going to $wp');
        return;
      }
    }

    setState(() => _recognizedCommand = null);
  }

  String? _extractDestination(String text) {
    // Extract destination after "go to"
    final patterns = ['go to', 'goto', 'navigate to', 'take me to'];
    for (final pattern in patterns) {
      final index = text.indexOf(pattern);
      if (index != -1) {
        final destination = text.substring(index + pattern.length).trim();
        if (destination.isNotEmpty) {
          // Try to match with available waypoints
          for (final wp in widget.availableWaypoints) {
            final wpNormalized = wp.toLowerCase().replaceAll('_', ' ');
            if (destination.contains(wpNormalized) ||
                wpNormalized.contains(destination)) {
              return wp;
            }
          }
          // Return as-is if no match (robot might know it)
          return destination.replaceAll(' ', '_');
        }
      }
    }
    return null;
  }
}
