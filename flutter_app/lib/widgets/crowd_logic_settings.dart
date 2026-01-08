import 'package:flutter/material.dart';
import '../core/buffer_client.dart';
import '../core/sequence_mode.dart';
import '../services/audio_announcer.dart';

/// Crowd Logic Settings widget for configuring blocked path behavior
/// Allows venue presets and custom timing adjustments
class CrowdLogicSettings extends StatefulWidget {
  const CrowdLogicSettings({super.key});

  @override
  State<CrowdLogicSettings> createState() => _CrowdLogicSettingsState();
}

class _CrowdLogicSettingsState extends State<CrowdLogicSettings> {
  late CrowdLogicConfig _config;
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    _config = AudioAnnouncer().crowdConfig;
  }

  void _applyConfig(CrowdLogicConfig config) {
    setState(() => _config = config);
    AudioAnnouncer().crowdConfig = config;

    // Send to relay for velocity ramping (if connected)
    final bufferClient = SequenceManager.instance.bufferClient;
    if (bufferClient != null) {
      bufferClient.loadCommands([
        BufferCommand.setCrowdConfig(
          safeDistanceMeters: config.safeDistanceMeters,
          rampRate: config.rampRate,
        ),
      ], clearExisting: false);
      debugPrint('CrowdLogicSettings: Sent config to relay - ${config.safeDistanceMeters}m, ramp=${config.rampRate}');
    }
  }

  void _applyVenuePreset(CrowdLogicVenue venue) {
    final config = CrowdLogicConfig.forVenue(venue).copyWith(venue: venue);
    _applyConfig(config);
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
              const Icon(Icons.people, size: 24),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Crowd Logic', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              // Current venue indicator
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getVenueColor(_config.venue).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _getVenueColor(_config.venue)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_getVenueIcon(_config.venue), size: 14, color: _getVenueColor(_config.venue)),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _config.venue.label,
                          style: TextStyle(
                            color: _getVenueColor(_config.venue),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Description
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Configure how aggressively the robot asks people to move when blocked.',
            style: TextStyle(color: Colors.grey[400], fontSize: 12),
          ),
        ),

        const SizedBox(height: 16),

        // Venue preset buttons
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Venue Preset', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: CrowdLogicVenue.values.map((venue) {
                  final isSelected = _config.venue == venue;
                  return ChoiceChip(
                    label: Text(venue.label),
                    selected: isSelected,
                    avatar: Icon(
                      _getVenueIcon(venue),
                      size: 18,
                      color: isSelected ? Colors.white : _getVenueColor(venue),
                    ),
                    selectedColor: _getVenueColor(venue),
                    onSelected: (selected) {
                      if (selected) _applyVenuePreset(venue);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Venue description
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            _config.venue.description,
            style: TextStyle(color: Colors.grey[500], fontSize: 12, fontStyle: FontStyle.italic),
          ),
        ),

        const SizedBox(height: 16),

        // Smart Intelligence Toggle (THE KEY FEATURE!)
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _config.enableIntelligence ? Colors.green.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _config.enableIntelligence ? Colors.green : Colors.grey,
              width: 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _config.enableIntelligence ? Icons.psychology : Icons.psychology_outlined,
                    color: _config.enableIntelligence ? Colors.green : Colors.grey,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'LIDAR Intelligence',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          _config.enableIntelligence
                              ? 'Smart: Only announces for moving/unexpected obstacles'
                              : 'Disabled: Uses time-based escalation only',
                          style: TextStyle(color: Colors.grey[400], fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _config.enableIntelligence,
                    activeTrackColor: Colors.green,
                    onChanged: (value) {
                      _applyConfig(_config.copyWith(enableIntelligence: value));
                    },
                  ),
                ],
              ),
              if (_config.enableIntelligence) ...[
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: CheckboxListTile(
                        title: const Text('Moving', style: TextStyle(fontSize: 12)),
                        subtitle: const Text('People, robots', style: TextStyle(fontSize: 10)),
                        value: _config.announceMoving,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (value) {
                          _applyConfig(_config.copyWith(announceMoving: value ?? true));
                        },
                      ),
                    ),
                    Expanded(
                      child: CheckboxListTile(
                        title: const Text('Static', style: TextStyle(fontSize: 12)),
                        subtitle: const Text('Crates, fallen items', style: TextStyle(fontSize: 10)),
                        value: _config.announceStatic,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (value) {
                          _applyConfig(_config.copyWith(announceStatic: value ?? true));
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        // Speed Ramping Controls
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade700),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.speed, color: Colors.blue.shade300, size: 24),
                  const SizedBox(width: 8),
                  const Text(
                    'Speed Ramping',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Distance where robot starts slowing down',
                style: TextStyle(color: Colors.grey[400], fontSize: 11),
              ),
              const SizedBox(height: 12),

              // Safe Distance - 3 box feet input
              Row(
                children: [
                  const Text('Safe Distance:', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 12),
                  // Feet whole number
                  SizedBox(
                    width: 45,
                    child: TextField(
                      controller: TextEditingController(
                        text: _config.safeDistanceFeet.floor().toString(),
                      ),
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        final feet = int.tryParse(value) ?? 0;
                        final inches = ((_config.safeDistanceFeet - _config.safeDistanceFeet.floor()) * 12).round();
                        final totalFeet = feet + (inches / 12.0);
                        _applyConfig(_config.copyWith(
                          venue: CrowdLogicVenue.custom,
                          safeDistanceFeet: totalFeet.clamp(1.0, 10.0),
                        ));
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text('ft', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 8),
                  // Inches
                  SizedBox(
                    width: 45,
                    child: TextField(
                      controller: TextEditingController(
                        text: ((_config.safeDistanceFeet - _config.safeDistanceFeet.floor()) * 12).round().toString(),
                      ),
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        final inches = int.tryParse(value) ?? 0;
                        final feet = _config.safeDistanceFeet.floor();
                        final totalFeet = feet + (inches.clamp(0, 11) / 12.0);
                        _applyConfig(_config.copyWith(
                          venue: CrowdLogicVenue.custom,
                          safeDistanceFeet: totalFeet.clamp(1.0, 10.0),
                        ));
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text('in', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 16),
                  // Show meters equivalent
                  Text(
                    '(${_config.safeDistanceMeters.toStringAsFixed(2)}m)',
                    style: TextStyle(color: Colors.grey[500], fontSize: 11),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Ramp Rate slider
              Row(
                children: [
                  const Text('Slowdown Rate:', style: TextStyle(fontSize: 13)),
                  const Spacer(),
                  Text(
                    _getRampRateLabel(_config.rampRate),
                    style: TextStyle(
                      color: _getRampRateColor(_config.rampRate),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Text('Gentle', style: TextStyle(fontSize: 10)),
                  Expanded(
                    child: Slider(
                      value: _config.rampRate,
                      min: 0.1,
                      max: 1.0,
                      divisions: 9,
                      activeColor: _getRampRateColor(_config.rampRate),
                      onChanged: (value) {
                        _applyConfig(_config.copyWith(
                          venue: CrowdLogicVenue.custom,
                          rampRate: value,
                        ));
                      },
                    ),
                  ),
                  const Text('Aggressive', style: TextStyle(fontSize: 10)),
                ],
              ),
              Text(
                'Higher = stops faster/earlier, Lower = gradual slowdown',
                style: TextStyle(color: Colors.grey[500], fontSize: 10),
              ),
            ],
          ),
        ),

        // Quick settings
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: SwitchListTile(
                  title: const Text('Alert Sounds', style: TextStyle(fontSize: 14)),
                  subtitle: const Text('Beeps & horns at high levels', style: TextStyle(fontSize: 11)),
                  value: _config.enableSounds,
                  dense: true,
                  onChanged: (value) {
                    _applyConfig(_config.copyWith(
                      venue: CrowdLogicVenue.custom,
                      enableSounds: value,
                    ));
                  },
                ),
              ),
            ],
          ),
        ),

        // Advanced settings toggle
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextButton.icon(
            icon: Icon(_showAdvanced ? Icons.expand_less : Icons.expand_more),
            label: Text(_showAdvanced ? 'Hide Advanced' : 'Show Advanced Timing'),
            onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
          ),
        ),

        // Advanced timing settings
        if (_showAdvanced) ...[
          const Divider(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _buildTimingSlider(
                  'Check Interval',
                  'How often to check if blocked',
                  _config.checkInterval,
                  1, 10,
                  (v) => _applyConfig(_config.copyWith(venue: CrowdLogicVenue.custom, checkInterval: v)),
                ),
                _buildTimingSlider(
                  'Level 1: Polite',
                  'Seconds until first polite request',
                  _config.warning1,
                  3, 60,
                  (v) => _applyConfig(_config.copyWith(venue: CrowdLogicVenue.custom, warning1: v)),
                ),
                _buildTimingSlider(
                  'Level 2: Firm',
                  'Seconds until firm request',
                  _config.warning2,
                  5, 90,
                  (v) => _applyConfig(_config.copyWith(venue: CrowdLogicVenue.custom, warning2: v)),
                ),
                _buildTimingSlider(
                  'Level 3: Urgent',
                  'Seconds until urgent request',
                  _config.warning3,
                  10, 120,
                  (v) => _applyConfig(_config.copyWith(venue: CrowdLogicVenue.custom, warning3: v)),
                ),
                _buildTimingSlider(
                  'Level 4: Demanding + Beep',
                  'Seconds until demanding (with beep)',
                  _config.warning4,
                  15, 150,
                  (v) => _applyConfig(_config.copyWith(venue: CrowdLogicVenue.custom, warning4: v)),
                ),
                _buildTimingSlider(
                  'Level 5: Aggressive + Horn',
                  'Seconds until aggressive (with horn)',
                  _config.warning5,
                  20, 200,
                  (v) => _applyConfig(_config.copyWith(venue: CrowdLogicVenue.custom, warning5: v)),
                ),
                _buildTimingSlider(
                  'Level 6: Emergency',
                  'Seconds until emergency mode',
                  _config.warning6,
                  25, 300,
                  (v) => _applyConfig(_config.copyWith(venue: CrowdLogicVenue.custom, warning6: v)),
                ),
                _buildTimingSlider(
                  'Repeat Interval',
                  'Seconds between level 6 repeats',
                  _config.repeatInterval,
                  3, 60,
                  (v) => _applyConfig(_config.copyWith(venue: CrowdLogicVenue.custom, repeatInterval: v)),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],

        // Timing preview
        if (!_showAdvanced)
          Expanded(
            child: _buildTimingPreview(),
          ),
      ],
    );
  }

  Widget _buildTimingSlider(
    String title,
    String subtitle,
    int value,
    int min,
    int max,
    void Function(int) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
              ),
              Text('${value}s', style: TextStyle(color: Colors.grey[400], fontWeight: FontWeight.bold)),
            ],
          ),
          Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
          Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: max - min,
            onChanged: (v) => onChanged(v.round()),
          ),
        ],
      ),
    );
  }

  Widget _buildTimingPreview() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[700]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Escalation Timeline', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                _buildTimelineItem(1, _config.warning1, 'Polite request', Colors.green),
                _buildTimelineItem(2, _config.warning2, 'Firm request', Colors.lightGreen),
                _buildTimelineItem(3, _config.warning3, 'Urgent request', Colors.yellow),
                _buildTimelineItem(4, _config.warning4, 'Demanding + Beep', Colors.orange, hasSound: _config.enableSounds),
                _buildTimelineItem(5, _config.warning5, 'Aggressive + Horn', Colors.deepOrange, hasSound: _config.enableSounds),
                _buildTimelineItem(6, _config.warning6, 'EMERGENCY (repeats every ${_config.repeatInterval}s)', Colors.red, hasSound: _config.enableSounds),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(int level, int seconds, String description, Color color, {bool hasSound = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text('$level', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ),
          const SizedBox(width: 8),
          Text('${seconds}s', style: TextStyle(color: Colors.grey[400], fontSize: 12, fontFamily: 'monospace')),
          const SizedBox(width: 8),
          Expanded(
            child: Text(description, style: const TextStyle(fontSize: 12)),
          ),
          if (hasSound)
            Icon(Icons.volume_up, size: 14, color: Colors.grey[500]),
        ],
      ),
    );
  }

  Color _getVenueColor(CrowdLogicVenue venue) {
    switch (venue) {
      case CrowdLogicVenue.spaceship:
        return Colors.cyan;
      case CrowdLogicVenue.adultParty:
        return Colors.red;
      case CrowdLogicVenue.restaurant:
        return Colors.blue;
      case CrowdLogicVenue.kidsEvent:
        return Colors.green;
      case CrowdLogicVenue.hospital:
        return Colors.purple;
      case CrowdLogicVenue.custom:
        return Colors.orange;
    }
  }

  IconData _getVenueIcon(CrowdLogicVenue venue) {
    switch (venue) {
      case CrowdLogicVenue.spaceship:
        return Icons.rocket_launch;
      case CrowdLogicVenue.adultParty:
        return Icons.celebration;
      case CrowdLogicVenue.restaurant:
        return Icons.restaurant;
      case CrowdLogicVenue.kidsEvent:
        return Icons.child_care;
      case CrowdLogicVenue.hospital:
        return Icons.local_hospital;
      case CrowdLogicVenue.custom:
        return Icons.tune;
    }
  }

  String _getRampRateLabel(double rate) {
    if (rate <= 0.2) return 'Very Gentle';
    if (rate <= 0.4) return 'Gentle';
    if (rate <= 0.6) return 'Moderate';
    if (rate <= 0.8) return 'Quick';
    return 'Aggressive';
  }

  Color _getRampRateColor(double rate) {
    if (rate <= 0.2) return Colors.green;
    if (rate <= 0.4) return Colors.lightGreen;
    if (rate <= 0.6) return Colors.yellow;
    if (rate <= 0.8) return Colors.orange;
    return Colors.red;
  }
}
