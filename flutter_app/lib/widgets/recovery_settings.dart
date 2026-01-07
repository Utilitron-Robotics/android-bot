import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../core/buffer_client.dart';

/// Recovery Settings widget for configuring navigation failure recovery behavior
/// Allows tuning backup, spin, and retry parameters
class RecoverySettings extends StatefulWidget {
  final void Function(RecoveryConfig)? onConfigChanged;

  const RecoverySettings({super.key, this.onConfigChanged});

  @override
  State<RecoverySettings> createState() => _RecoverySettingsState();
}

class _RecoverySettingsState extends State<RecoverySettings> {
  late RecoveryConfig _config;
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('recovery_config');
    if (json != null) {
      try {
        setState(() => _config = RecoveryConfig.fromJson(jsonDecode(json)));
      } catch (e) {
        setState(() => _config = const RecoveryConfig());
      }
    } else {
      setState(() => _config = const RecoveryConfig());
    }
  }

  Future<void> _saveConfig(RecoveryConfig config) async {
    setState(() => _config = config);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('recovery_config', jsonEncode(config.toJson()));
    widget.onConfigChanged?.call(config);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.healing, size: 24),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Recovery Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              // Quick status
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green),
                ),
                child: Text(
                  '${_config.maxRecoveryAttempts} retries',
                  style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
        ),

        // Main controls
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              // Max Recovery Attempts
              _buildSlider(
                label: 'Max Recovery Attempts',
                value: _config.maxRecoveryAttempts.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                suffix: ' retries',
                onChanged: (v) => _saveConfig(_config.copyWith(maxRecoveryAttempts: v.round())),
              ),

              // Stuck Threshold
              _buildSlider(
                label: 'Stuck Detection Time',
                value: _config.stuckThresholdMs / 1000,
                min: 5,
                max: 60,
                divisions: 11,
                suffix: ' sec',
                onChanged: (v) => _saveConfig(_config.copyWith(stuckThresholdMs: (v * 1000).round())),
              ),

              // Announce Toggle
              SwitchListTile(
                title: const Text('Announce Recovery'),
                subtitle: const Text('Say "Looking for alternative path"'),
                value: _config.announceRecovery,
                onChanged: (v) => _saveConfig(_config.copyWith(announceRecovery: v)),
              ),
            ],
          ),
        ),

        // Advanced toggle
        ListTile(
          leading: Icon(_showAdvanced ? Icons.expand_less : Icons.expand_more),
          title: const Text('Advanced Settings'),
          subtitle: const Text('Fine-tune speeds and durations'),
          onTap: () => setState(() => _showAdvanced = !_showAdvanced),
        ),

        if (_showAdvanced) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Backup Maneuver', style: TextStyle(fontWeight: FontWeight.bold)),
                _buildSlider(
                  label: 'Duration',
                  value: _config.backupDurationMs / 1000,
                  min: 0.5,
                  max: 5,
                  suffix: ' sec',
                  onChanged: (v) => _saveConfig(_config.copyWith(backupDurationMs: (v * 1000).round())),
                ),
                _buildSlider(
                  label: 'Speed',
                  value: _config.backupSpeed,
                  min: 0.05,
                  max: 0.3,
                  suffix: ' m/s',
                  onChanged: (v) => _saveConfig(_config.copyWith(backupSpeed: v)),
                ),

                const SizedBox(height: 16),
                const Text('Spin Maneuver', style: TextStyle(fontWeight: FontWeight.bold)),
                _buildSlider(
                  label: 'Speed',
                  value: _config.spinSpeed,
                  min: 0.2,
                  max: 1.0,
                  suffix: ' rad/s',
                  onChanged: (v) => _saveConfig(_config.copyWith(spinSpeed: v)),
                ),

                const SizedBox(height: 16),
                const Text('Forward Nudge', style: TextStyle(fontWeight: FontWeight.bold)),
                _buildSlider(
                  label: 'Duration',
                  value: _config.nudgeDurationMs / 1000,
                  min: 0.5,
                  max: 3,
                  suffix: ' sec',
                  onChanged: (v) => _saveConfig(_config.copyWith(nudgeDurationMs: (v * 1000).round())),
                ),
                _buildSlider(
                  label: 'Speed',
                  value: _config.nudgeSpeed,
                  min: 0.05,
                  max: 0.3,
                  suffix: ' m/s',
                  onChanged: (v) => _saveConfig(_config.copyWith(nudgeSpeed: v)),
                ),
              ],
            ),
          ),
        ],

        // Reset button
        Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton.icon(
            onPressed: () => _saveConfig(const RecoveryConfig()),
            icon: const Icon(Icons.restore),
            label: const Text('Reset to Defaults'),
          ),
        ),
      ],
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required String suffix,
    required void Function(double) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label),
              Text('${value.toStringAsFixed(1)}$suffix', style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
