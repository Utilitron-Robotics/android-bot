import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/robot_connection.dart';

/// Panel for testing tablet TTS and display features via WebSocket relay
class TabletControlPanel extends StatefulWidget {
  final String? relayHttpUrl;  // Kept for compatibility, but we use WebSocket now

  const TabletControlPanel({super.key, this.relayHttpUrl});

  @override
  State<TabletControlPanel> createState() => _TabletControlPanelState();
}

class _TabletControlPanelState extends State<TabletControlPanel> {
  String _customText = '';
  final _textController = TextEditingController();

  // Preset sounds/announcements
  static const _presetSounds = [
    ('Welcome', 'Welcome! How can I help you today?'),
    ('Delivery', 'Your order has arrived. Please collect your items.'),
    ('Thank You', 'Thank you! Have a great day.'),
    ('Excuse Me', 'Excuse me, please make way.'),
    ('Low Battery', 'Warning: Battery is running low. Please recharge soon.'),
    ('Following', 'I am following you. Please walk slowly.'),
    ('Arrived', 'I have arrived at my destination.'),
    ('Emergency', 'Emergency stop activated. Please clear the area.'),
  ];

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _speak(String text) {
    final robot = context.read<RobotConnection>();
    if (!robot.isConnected) return;
    robot.client.tabletSpeak(text);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Speaking: $text'),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _testDisplay(String name) {
    final robot = context.read<RobotConnection>();
    if (!robot.isConnected) return;
    final html = 'data:text/html,<html><body style="display:flex;align-items:center;justify-content:center;height:100vh;margin:0;background:%23222;"><h1 style="color:white;font-size:72px;font-family:sans-serif;">$name</h1></body></html>';
    robot.client.tabletDisplay(html);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Displaying: $name'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _closeDisplay() {
    final robot = context.read<RobotConnection>();
    if (!robot.isConnected) return;
    robot.client.tabletCloseDisplay();
  }

  void _testDeliver() {
    final robot = context.read<RobotConnection>();
    if (!robot.isConnected) return;
    robot.client.tabletTask('DELIVER', 'Your order has arrived. Please collect your items.', 5);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Delivery task started'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _cancelTask() {
    final robot = context.read<RobotConnection>();
    if (!robot.isConnected) return;
    robot.client.tabletCancelTask();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RobotConnection>(
      builder: (context, robot, _) {
        final isAvailable = robot.isConnected && widget.relayHttpUrl != null;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Icon(
                      Icons.volume_up,
                      color: isAvailable ? Colors.blue : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Tablet Sound Control',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    if (isAvailable)
                      const Chip(
                        label: Text('WebSocket', style: TextStyle(fontSize: 10)),
                        backgroundColor: Colors.green,
                        padding: EdgeInsets.zero,
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                if (!isAvailable) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning, color: Colors.orange),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Connect via Relay mode to control tablet sounds',
                            style: TextStyle(color: Colors.orange),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // Custom text input
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          decoration: const InputDecoration(
                            hintText: 'Enter custom text to speak...',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) => setState(() => _customText = v),
                          onSubmitted: (v) {
                            if (v.isNotEmpty) _speak(v);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _customText.isEmpty ? null : () => _speak(_customText),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Speak'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Preset sounds grid
                  const Text(
                    'Preset Announcements:',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _presetSounds.map((preset) {
                      return ActionChip(
                        avatar: const Icon(Icons.volume_up, size: 18),
                        label: Text(preset.$1),
                        onPressed: () => _speak(preset.$2),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Display test
                  const Text(
                    'Display Test:',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _testDisplay('Test Waypoint'),
                        icon: const Icon(Icons.tv),
                        label: const Text('Show Panel'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _closeDisplay,
                        icon: const Icon(Icons.close),
                        label: const Text('Close'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Task controls
                  const Text(
                    'Task Tests:',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _testDeliver,
                        icon: const Icon(Icons.delivery_dining),
                        label: const Text('Test Delivery'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _cancelTask,
                        icon: const Icon(Icons.stop),
                        label: const Text('Cancel Task'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
