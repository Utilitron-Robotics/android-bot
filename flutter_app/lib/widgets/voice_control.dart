import 'package:flutter/material.dart';

/// Voice command input - temporarily disabled (speech_to_text Kotlin compat issue)
/// TODO: Re-enable when speech_to_text plugin is updated
class VoiceControl extends StatelessWidget {
  final List<String> availableWaypoints;

  const VoiceControl({super.key, required this.availableWaypoints});

  @override
  Widget build(BuildContext context) {
    // Disabled for now - return empty widget
    return const SizedBox.shrink();
  }
}
