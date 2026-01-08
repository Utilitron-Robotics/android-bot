import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/adaptive_transport.dart';
import '../core/robot_transport.dart';

/// Demo widget showing the POWER of adaptive multi-protocol transport
/// This bad boy will maintain connection through apocalyptic network conditions
class AdaptiveTransportDemo extends StatefulWidget {
  const AdaptiveTransportDemo({super.key});

  @override
  State<AdaptiveTransportDemo> createState() => _AdaptiveTransportDemoState();
}

class _AdaptiveTransportDemoState extends State<AdaptiveTransportDemo>
    with SingleTickerProviderStateMixin {
  late AdaptiveTransport _transport;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final List<String> _eventLog = [];
  QualityLevel _currentQuality = QualityLevel.excellent;
  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();

    _transport = AdaptiveTransport();

    // Initialize with multiple fallback options
    _transport.initialize(
      websocketUrl: 'ws://192.168.88.37:8766', // Primary
      httpEndpoint: 'http://192.168.88.37:8765', // Fallback
      // grpcEndpoint: '192.168.88.37:50051',    // Future WAN option
    );

    // Listen to quality changes
    _transport.qualityStream.listen((quality) {
      setState(() {
        _currentQuality = quality;
        _addEvent('📡 Quality: ${quality.name}');
      });
    });

    // Setup pulse animation for connection indicator
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    // Auto-connect on start
    _connect();
  }

  Future<void> _connect() async {
    _addEvent('🔌 Initiating multi-protocol connection...');
    try {
      await _transport.connect();
      _addEvent('✅ Connected via ${_transport.getStats()['transport']}');
      _updateStats();
    } catch (e) {
      _addEvent('❌ Connection failed: $e');
    }
  }

  void _updateStats() {
    setState(() {
      _stats = _transport.getStats();
    });
  }

  void _addEvent(String event) {
    setState(() {
      _eventLog.insert(
          0, '${DateTime.now().toLocal().toString().substring(11, 19)} $event');
      if (_eventLog.length > 20) {
        _eventLog.removeLast();
      }
    });
  }

  Color _getQualityColor() {
    switch (_currentQuality) {
      case QualityLevel.excellent:
        return Colors.green;
      case QualityLevel.good:
        return Colors.lightGreen;
      case QualityLevel.acceptable:
        return Colors.yellow;
      case QualityLevel.poor:
        return Colors.orange;
      case QualityLevel.critical:
        return Colors.red;
    }
  }

  IconData _getQualityIcon() {
    switch (_currentQuality) {
      case QualityLevel.excellent:
        return Icons.signal_cellular_4_bar;
      case QualityLevel.good:
        return Icons.signal_cellular_alt;
      case QualityLevel.acceptable:
        return Icons.network_cell;
      case QualityLevel.poor:
        return Icons.signal_cellular_1_bar;
      case QualityLevel.critical:
        return Icons.signal_cellular_0_bar;
    }
  }

  Future<void> _sendTestCommand(String type) async {
    final command = AdaptiveCommand(
      id: 'test_${DateTime.now().millisecondsSinceEpoch}',
      type: type,
      payload: type == 'velocity'
          ? {'linear': 0.1, 'angular': 0.0}
          : {'waypoint': 'P1'},
      priority:
          type == 'stop' ? CommandPriority.emergency : CommandPriority.normal,
    );

    _addEvent('📤 Sending $type command...');

    try {
      final ack = await _transport.sendCommand(command);
      if (ack != null && ack.success) {
        _addEvent('✅ $type command acknowledged');
      } else {
        _addEvent('⚠️ $type command failed: ${ack?.errorMessage}');
      }
    } catch (e) {
      _addEvent('❌ $type command error: $e');
    }

    _updateStats();
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _transport.isConnected;

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with connection status
            Row(
              children: [
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: isConnected ? _pulseAnimation.value : 1.0,
                      child: Icon(
                        isConnected ? Icons.wifi : Icons.wifi_off,
                        color: isConnected ? _getQualityColor() : Colors.grey,
                        size: 32,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Adaptive Transport System',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        isConnected
                            ? 'Connected via ${_stats['transport'] ?? 'unknown'}'
                            : 'Disconnected',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: isConnected ? Colors.green : Colors.red,
                            ),
                      ),
                    ],
                  ),
                ),
                // Quality indicator
                if (isConnected) ...[
                  Icon(
                    _getQualityIcon(),
                    color: _getQualityColor(),
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _currentQuality.name.toUpperCase(),
                    style: TextStyle(
                      color: _getQualityColor(),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 16),
            const Divider(),

            // Statistics
            if (_stats.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'STATISTICS',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _buildStatChip('Commands Sent',
                      _stats['commands_sent']?.toString() ?? '0'),
                  _buildStatChip(
                      'Failed', _stats['commands_failed']?.toString() ?? '0'),
                  _buildStatChip('Success Rate',
                      _stats['success_rate']?.toString() ?? 'N/A'),
                  _buildStatChip('Transport Switches',
                      _stats['transport_switches']?.toString() ?? '0'),
                ],
              ),
            ],

            const SizedBox(height: 16),
            const Divider(),

            // Test controls
            const SizedBox(height: 8),
            Text(
              'TEST COMMANDS',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed:
                      isConnected ? () => _sendTestCommand('velocity') : null,
                  icon: const Icon(Icons.speed),
                  label: const Text('Velocity'),
                ),
                ElevatedButton.icon(
                  onPressed:
                      isConnected ? () => _sendTestCommand('navigate') : null,
                  icon: const Icon(Icons.location_on),
                  label: const Text('Navigate'),
                ),
                ElevatedButton.icon(
                  onPressed:
                      isConnected ? () => _sendTestCommand('stop') : null,
                  icon: const Icon(Icons.stop),
                  label: const Text('E-STOP'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _connect,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reconnect'),
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(),

            // Event log
            const SizedBox(height: 8),
            Text(
              'EVENT LOG',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey),
              ),
              child: ListView.builder(
                reverse: false,
                padding: const EdgeInsets.all(8),
                itemCount: _eventLog.length,
                itemBuilder: (context, index) {
                  return Text(
                    _eventLog[index],
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.greenAccent,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _transport.dispose();
    super.dispose();
  }
}
