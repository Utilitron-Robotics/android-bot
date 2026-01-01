import 'package:flutter/material.dart';
import '../services/audio_announcer.dart';

/// Widget for managing preset announcements
class AnnouncementPresetsEditor extends StatefulWidget {
  const AnnouncementPresetsEditor({super.key});

  @override
  State<AnnouncementPresetsEditor> createState() => _AnnouncementPresetsEditorState();
}

class _AnnouncementPresetsEditorState extends State<AnnouncementPresetsEditor> {
  AnnouncementCategory _selectedCategory = AnnouncementCategory.blockedPath;

  @override
  Widget build(BuildContext context) {
    final announcer = AudioAnnouncer();
    final presets = announcer.getPresetsByCategory(_selectedCategory);
    final isDefault = presets.isNotEmpty &&
        presets.every((p) => AudioAnnouncer.defaultBlockedPresets.any((d) => d.id == p.id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category selector
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.campaign, size: 24),
              const SizedBox(width: 8),
              const Text('Announcements', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              DropdownButton<AnnouncementCategory>(
                value: _selectedCategory,
                items: AnnouncementCategory.values.map((cat) {
                  return DropdownMenuItem(
                    value: cat,
                    child: Text(_categoryLabel(cat)),
                  );
                }).toList(),
                onChanged: (cat) {
                  if (cat != null) setState(() => _selectedCategory = cat);
                },
              ),
            ],
          ),
        ),

        // Info about current category
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            _categoryDescription(_selectedCategory),
            style: TextStyle(color: Colors.grey[400], fontSize: 12),
          ),
        ),

        if (isDefault)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Chip(
              label: const Text('Using defaults'),
              avatar: const Icon(Icons.info_outline, size: 16),
              backgroundColor: Colors.blue.withValues(alpha: 0.2),
            ),
          ),

        const SizedBox(height: 8),

        // Presets list
        Expanded(
          child: presets.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.volume_off, size: 48, color: Colors.grey[600]),
                      const SizedBox(height: 8),
                      Text('No presets for ${_categoryLabel(_selectedCategory)}',
                          style: TextStyle(color: Colors.grey[500])),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Add Preset'),
                        onPressed: () => _showAddDialog(context),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: presets.length,
                  itemBuilder: (ctx, index) {
                    final preset = presets[index];
                    final isDefaultPreset = AudioAnnouncer.defaultBlockedPresets.any((d) => d.id == preset.id);
                    return _buildPresetCard(preset, index, isDefaultPreset);
                  },
                ),
        ),

        // Add button
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add Preset'),
                  onPressed: () => _showAddDialog(context),
                ),
              ),
              if (_selectedCategory == AnnouncementCategory.blockedPath && !isDefault) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _resetToDefaults,
                  child: const Text('Reset to Defaults'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPresetCard(AnnouncementPreset preset, int index, bool isDefault) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: Text('${index + 1}'),
        ),
        title: Text(preset.text, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: preset.delaySeconds > 0
            ? Text('After ${preset.delaySeconds}s', style: const TextStyle(fontSize: 11))
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Test button
            IconButton(
              icon: const Icon(Icons.play_arrow, size: 20),
              onPressed: () => AudioAnnouncer().speak(preset.text),
              tooltip: 'Test',
            ),
            // Edit button (not for defaults)
            if (!isDefault)
              IconButton(
                icon: const Icon(Icons.edit, size: 20),
                onPressed: () => _showEditDialog(context, preset),
                tooltip: 'Edit',
              ),
            // Delete button (not for defaults)
            if (!isDefault)
              IconButton(
                icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                onPressed: () => _deletePreset(preset),
                tooltip: 'Delete',
              ),
          ],
        ),
      ),
    );
  }

  String _categoryLabel(AnnouncementCategory cat) {
    switch (cat) {
      case AnnouncementCategory.blockedPath:
        return 'Blocked Path';
      case AnnouncementCategory.arrival:
        return 'Arrival';
      case AnnouncementCategory.departure:
        return 'Departure';
      case AnnouncementCategory.warning:
        return 'Warning';
      case AnnouncementCategory.custom:
        return 'Custom';
    }
  }

  String _categoryDescription(AnnouncementCategory cat) {
    switch (cat) {
      case AnnouncementCategory.blockedPath:
        return 'Escalating announcements when the robot path is blocked during navigation. First at 10s, second at 20s, third at 35s.';
      case AnnouncementCategory.arrival:
        return 'Spoken when arriving at a waypoint.';
      case AnnouncementCategory.departure:
        return 'Spoken when leaving a waypoint.';
      case AnnouncementCategory.warning:
        return 'Warning announcements for low battery, obstacles, etc.';
      case AnnouncementCategory.custom:
        return 'Custom announcements for any purpose.';
    }
  }

  void _showAddDialog(BuildContext context) {
    final textController = TextEditingController();
    final delayController = TextEditingController(text: '0');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Preset'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: textController,
              decoration: const InputDecoration(
                labelText: 'Announcement Text',
                hintText: 'What to say...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: delayController,
              decoration: const InputDecoration(
                labelText: 'Delay (seconds)',
                hintText: '0 for immediate',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (textController.text.isNotEmpty) {
                final preset = AnnouncementPreset(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  text: textController.text,
                  category: _selectedCategory,
                  delaySeconds: int.tryParse(delayController.text) ?? 0,
                );
                AudioAnnouncer().addPreset(preset);
                setState(() {});
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, AnnouncementPreset preset) {
    final textController = TextEditingController(text: preset.text);
    final delayController = TextEditingController(text: preset.delaySeconds.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Preset'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: textController,
              decoration: const InputDecoration(
                labelText: 'Announcement Text',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: delayController,
              decoration: const InputDecoration(
                labelText: 'Delay (seconds)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (textController.text.isNotEmpty) {
                final updated = AnnouncementPreset(
                  id: preset.id,
                  text: textController.text,
                  category: preset.category,
                  delaySeconds: int.tryParse(delayController.text) ?? 0,
                );
                AudioAnnouncer().updatePreset(updated);
                setState(() {});
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _deletePreset(AnnouncementPreset preset) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Preset?'),
        content: Text('Delete "${preset.text}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              AudioAnnouncer().removePreset(preset.id);
              setState(() {});
              Navigator.pop(ctx);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _resetToDefaults() {
    // Remove all custom blocked path presets
    final presets = AudioAnnouncer().presets
        .where((p) => p.category == AnnouncementCategory.blockedPath)
        .toList();
    for (final p in presets) {
      AudioAnnouncer().removePreset(p.id);
    }
    setState(() {});
  }
}
