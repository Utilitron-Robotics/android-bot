import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/robot_connection.dart';
import '../core/sequence_mode.dart';
import '../core/task_engine.dart';
import '../core/fleet_cloud.dart';

/// Sequence Editor widget for creating and managing sequences
class SequenceEditor extends StatefulWidget {
  final List<String> availableWaypoints;
  final void Function(Sequence seq)? onStartSequence;

  const SequenceEditor({
    super.key,
    required this.availableWaypoints,
    this.onStartSequence,
  });

  @override
  State<SequenceEditor> createState() => _SequenceEditorState();
}

class _SequenceEditorState extends State<SequenceEditor> {
  Sequence? _selectedSequence;
  bool _isEditing = false;

  // Managed TextEditingControllers to fix input issues
  final TextEditingController _tourNameController = TextEditingController();
  final TextEditingController _introTextController = TextEditingController();
  final TextEditingController _outroTextController = TextEditingController();
  final TextEditingController _motionGreetingController =
      TextEditingController();
  final TextEditingController _motionButtonTextController =
      TextEditingController();
  final Map<String, TextEditingController> _stopControllers = {};

  // Cache to reduce unnecessary rebuilds - only rebuild when these actually change
  int _cachedSequenceCount = 0;
  SequenceStatus? _cachedStatus;
  String? _cachedRunningSequenceId;

  @override
  void initState() {
    super.initState();
    // Load and auto-select running sequence or first available
    _initializeSelection();
    // Listen for running sequence changes (e.g. buffer executor reconnect restore)
    SequenceManager.instance.addListener(_onSequenceManagerChanged);
  }

  void _onSequenceManagerChanged() {
    // Auto-select running sequence if we don't have one selected
    final manager = SequenceManager.instance;
    final runningSeq = manager.currentSequence;

    if (runningSeq != null && _selectedSequence?.id != runningSeq.id) {
      debugPrint(
          'SequenceEditor: Running sequence changed, auto-selecting: ${runningSeq.name}');
      _selectSequence(runningSeq);
    }

    // Rebuild UI when sequences list changes (e.g., cloud sync PULL/PUSH)
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _initializeSelection() async {
    await SequenceManager.instance.load();
    // Auto-select running sequence, or first available
    final manager = SequenceManager.instance;
    final runningSeq = manager.currentSequence;
    final sequences = manager.sequences;

    if (runningSeq != null) {
      debugPrint(
          'SequenceEditor: Auto-selecting running sequence: ${runningSeq.name}');
      _selectSequence(runningSeq);
    } else if (sequences.isNotEmpty && _selectedSequence == null) {
      debugPrint(
          'SequenceEditor: Auto-selecting first sequence: ${sequences.first.name}');
      _selectSequence(sequences.first);
    }
  }

  @override
  void dispose() {
    SequenceManager.instance.removeListener(_onSequenceManagerChanged);
    _tourNameController.dispose();
    _introTextController.dispose();
    _outroTextController.dispose();
    _motionGreetingController.dispose();
    _motionButtonTextController.dispose();
    for (final c in _stopControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Normalize waypoint value for dropdown - null/empty becomes null,
  /// invalid waypoints (not in available list) become null
  String? _normalizeWaypointValue(String? waypoint) {
    if (waypoint == null || waypoint.isEmpty) return null;
    // Ensure waypoint exists in available list, otherwise return null
    if (widget.availableWaypoints.contains(waypoint)) return waypoint;
    return null;
  }

  /// Get or create a controller for a stop field
  TextEditingController _getStopController(
      String stopKey, String initialValue) {
    if (!_stopControllers.containsKey(stopKey)) {
      _stopControllers[stopKey] = TextEditingController(text: initialValue);
    }
    return _stopControllers[stopKey]!;
  }

  Future<void> _createNewSequence() async {
    final newTour = Sequence(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'New Mode',
      description: '',
      stops: [],
    );
    debugPrint(
        'SequenceEditor._createNewSequence: Creating tour "${newTour.name}" id=${newTour.id}');
    await SequenceManager.instance.saveSequence(newTour);
    debugPrint('SequenceEditor._createNewSequence: saveSequence completed');
    _tourNameController.text = newTour.name;
    _introTextController.text = '';
    _outroTextController.text = '';
    _motionGreetingController.text = '';
    _motionButtonTextController.text = '';
    setState(() {
      _selectedSequence = newTour;
      _isEditing = true;
    });
  }

  void _selectSequence(Sequence seq) {
    // Clear ALL stop controllers when switching sequences to ensure fresh state
    for (final controller in _stopControllers.values) {
      controller.dispose();
    }
    _stopControllers.clear();

    // Update tour name/intro/outro controllers
    _tourNameController.text = seq.name;
    _introTextController.text = seq.introText ?? '';
    _outroTextController.text = seq.outroText ?? '';
    _motionGreetingController.text = seq.motionGreeting ?? '';
    _motionButtonTextController.text = seq.motionButtonText ?? '';

    setState(() {
      _selectedSequence = seq;
      _isEditing = false;
    });
  }

  void _deleteSequence(Sequence seq) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Sequence'),
        content: Text('Delete "${seq.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await SequenceManager.instance.deleteSequence(seq.id);
              if (_selectedSequence?.id == seq.id) {
                setState(() {
                  _selectedSequence = null;
                  _isEditing = false;
                });
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveSequence() async {
    // Build tour from controller values - no model updates during typing!
    if (_selectedSequence == null) return;

    debugPrint(
        'SequenceEditor._saveSequence: Saving tour "${_selectedSequence!.name}"');

    // Read all values from controllers
    final stops = <SequenceStop>[];
    for (int i = 0; i < _selectedSequence!.stops.length; i++) {
      final oldStop = _selectedSequence!.stops[i];
      stops.add(SequenceStop(
        waypoint: oldStop.waypoint,
        speakText:
            _stopControllers['${_selectedSequence!.id}_${i}_speak']?.text,
        displayUrl: _stopControllers['${_selectedSequence!.id}_${i}_url']?.text,
        displayDuration: int.tryParse(
                _stopControllers['${_selectedSequence!.id}_${i}_duration']
                        ?.text ??
                    '') ??
            0,
        waitSeconds: int.tryParse(
                _stopControllers['${_selectedSequence!.id}_${i}_wait']?.text ??
                    '') ??
            0,
      ));
    }

    final updatedTour = Sequence(
      id: _selectedSequence!.id,
      name: _tourNameController.text,
      description: _selectedSequence!.description,
      stops: stops,
      loop: _selectedSequence!.loop,
      announceArrival: _selectedSequence!.announceArrival,
      restAtEndSeconds: _selectedSequence!.restAtEndSeconds,
      introText:
          _introTextController.text.isEmpty ? null : _introTextController.text,
      outroText:
          _outroTextController.text.isEmpty ? null : _outroTextController.text,
      startWaypoint: _selectedSequence!.startWaypoint,
      endWaypoint: _selectedSequence!.endWaypoint,
      motionTriggerStart: _selectedSequence!.motionTriggerStart,
      motionGreeting: _motionGreetingController.text.isEmpty
          ? null
          : _motionGreetingController.text,
      motionButtonText: _motionButtonTextController.text.isEmpty
          ? null
          : _motionButtonTextController.text,
    );

    _selectedSequence = updatedTour;
    await SequenceManager.instance.saveSequence(updatedTour);
    debugPrint(
        'SequenceEditor._saveSequence: Save completed for "${updatedTour.name}"');
  }

  void _updateTourOptions(
      {bool? loop, bool? announceArrival, bool? motionTriggerStart}) {
    // Only for checkboxes - these need immediate state update AND save
    if (_selectedSequence == null) return;
    setState(() {
      _selectedSequence = _selectedSequence!.copyWith(
        loop: loop ?? _selectedSequence!.loop,
        announceArrival: announceArrival ?? _selectedSequence!.announceArrival,
        motionTriggerStart:
            motionTriggerStart ?? _selectedSequence!.motionTriggerStart,
      );
    });
    // Auto-save checkbox changes
    _saveSequence();
  }

  void _addStop(SequenceStop stop) {
    if (_selectedSequence == null) return;
    setState(() {
      _selectedSequence = _selectedSequence!.addStop(stop);
    });
    // Auto-save when stop is added
    _saveSequence();
  }

  void _removeStop(int index) {
    if (_selectedSequence == null) return;

    // CRITICAL: First, save ALL current controller values to the SequenceStop data
    // This ensures we don't lose edits when we clear controllers
    _saveSequence();

    // Clear ALL stop controllers - indices shift after removal
    // They will be recreated from the (updated) SequenceStop data
    for (final controller in _stopControllers.values) {
      controller.dispose();
    }
    _stopControllers.clear();

    setState(() {
      _selectedSequence = _selectedSequence!.removeStop(index);
    });

    // Save after removing stop
    _saveSequence();
  }

  void _reorderStops(int oldIndex, int newIndex) async {
    if (_selectedSequence == null) return;
    if (newIndex > oldIndex) newIndex--;

    // CRITICAL FIX: Save BEFORE clearing controllers!
    // First save all current text from controllers to the model
    await _saveSequence();

    // Now that data is saved, reorder the stops in the model
    final reorderedSequence = _selectedSequence!.reorderStop(oldIndex, newIndex);

    // Update the model with reordered stops
    _selectedSequence = reorderedSequence;

    // Clear controllers AFTER reordering - they'll be recreated with correct data
    for (final controller in _stopControllers.values) {
      controller.dispose();
    }
    _stopControllers.clear();

    // Force rebuild which will recreate controllers from the reordered model
    setState(() {
      // The setState will trigger rebuild and _getOrCreateController will
      // recreate controllers with the preserved text data
    });

    // Save the final reordered sequence to storage
    await SequenceManager.instance.saveSequence(reorderedSequence);
  }

  void _showCloudSyncDialog() {
    // Default to AWS CloudFormation API Gateway endpoint
    final apiUrlController = TextEditingController(
      text: SequenceManager.instance.cloudApiUrl ??
            'https://e536dpa128.execute-api.us-west-1.amazonaws.com/dev',
    );

    // Auto-detect map ID from connected robot
    final robotConnection = context.read<RobotConnection>();
    final robotStatus = robotConnection.status;
    final autoMapId = (robotStatus.buildingName.isNotEmpty &&
            robotStatus.floorName.isNotEmpty)
        ? '${robotStatus.buildingName}_${robotStatus.floorName}'
        : null;
    final mapIdController = TextEditingController(
      text: SequenceManager.instance.currentMapId ?? autoMapId ?? '',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cloud_sync),
            SizedBox(width: 8),
            Text('Cloud Sync'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status indicator
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: SequenceManager.instance.cloudSyncEnabled
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: SequenceManager.instance.cloudSyncEnabled
                        ? Colors.green
                        : Colors.grey,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      SequenceManager.instance.cloudSyncEnabled
                          ? Icons.cloud_done
                          : Icons.cloud_off,
                      color: SequenceManager.instance.cloudSyncEnabled
                          ? Colors.green
                          : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      SequenceManager.instance.cloudSyncEnabled
                          ? 'Connected to cloud'
                          : 'Not connected',
                      style: TextStyle(
                        color: SequenceManager.instance.cloudSyncEnabled
                            ? Colors.green
                            : Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              // API URL
              TextField(
                controller: apiUrlController,
                decoration: const InputDecoration(
                  labelText: 'Cloud API URL',
                  hintText: 'Leave empty for local storage',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.cloud),
                ),
              ),
              const SizedBox(height: 16),
              // Map ID
              TextField(
                controller: mapIdController,
                decoration: const InputDecoration(
                  labelText: 'Map ID (for tour filtering)',
                  hintText: 'Leave blank for all sequences',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.map),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tours are shared between all robots on the same floor',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
              // Push/Pull explanation
              if (SequenceManager.instance.cloudSyncEnabled) ...[
                const SizedBox(height: 16),
                // Tours section
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.route, size: 18),
                          SizedBox(width: 8),
                          Text('TOURS',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.cloud_upload,
                              color: Colors.blue, size: 16),
                          SizedBox(width: 4),
                          Text('PUSH',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                  fontSize: 12)),
                          Text(' - Upload local tours',
                              style: TextStyle(fontSize: 11)),
                          Spacer(),
                          Icon(Icons.cloud_download,
                              color: Colors.green, size: 16),
                          SizedBox(width: 4),
                          Text('PULL',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                  fontSize: 12)),
                          Text(' - Download from cloud',
                              style: TextStyle(fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Waypoints section
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: Colors.purple.withValues(alpha: 0.3)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.location_on,
                              size: 18, color: Colors.purple),
                          SizedBox(width: 8),
                          Text('WAYPOINTS',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.cloud_upload,
                              color: Colors.blue, size: 16),
                          SizedBox(width: 4),
                          Text('PUSH',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                  fontSize: 12)),
                          Text(' - Upload POI list',
                              style: TextStyle(fontSize: 11)),
                          Spacer(),
                          Icon(Icons.cloud_download,
                              color: Colors.green, size: 16),
                          SizedBox(width: 4),
                          Text('PULL',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                  fontSize: 12)),
                          Text(' - Download POI list',
                              style: TextStyle(fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          // Push/Pull buttons when connected
          if (SequenceManager.instance.cloudSyncEnabled) ...[
            // Waypoint Push button (purple)
            TextButton.icon(
              icon:
                  const Icon(Icons.location_on, color: Colors.purple, size: 18),
              label: const Text('WP↑',
                  style: TextStyle(color: Colors.purple, fontSize: 12)),
              onPressed: () async {
                Navigator.pop(ctx);
                final waypoints = widget.availableWaypoints;
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Row(
                      children: [
                        Icon(Icons.location_on, color: Colors.purple),
                        SizedBox(width: 8),
                        Text('Push Waypoints?'),
                      ],
                    ),
                    content: Text(
                      'This will upload ${waypoints.length} waypoint(s) to the cloud.\n\n'
                      'Other robots on this floor can then pull this POI list.',
                    ),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('Cancel')),
                      FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.purple),
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('Push'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  final mapId = mapIdController.text.trim().isEmpty
                      ? null
                      : mapIdController.text.trim();
                  final cloud = FleetCloudClient();
                  cloud.configure(apiEndpoint: apiUrlController.text.trim());
                  if (mapId != null) cloud.setMapId(mapId);
                  final success =
                      await cloud.pushWaypoints(waypoints, mapId: mapId);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(success
                            ? 'Pushed ${waypoints.length} waypoint(s) to cloud!'
                            : 'Failed to push waypoints'),
                        backgroundColor: success ? Colors.green : Colors.red,
                      ),
                    );
                  }
                }
              },
            ),
            // Waypoint Pull button (purple/green)
            TextButton.icon(
              icon: const Icon(Icons.location_on, color: Colors.teal, size: 18),
              label: const Text('WP↓',
                  style: TextStyle(color: Colors.teal, fontSize: 12)),
              onPressed: () async {
                Navigator.pop(ctx);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Row(
                      children: [
                        Icon(Icons.location_on, color: Colors.teal),
                        SizedBox(width: 8),
                        Text('Pull Waypoints?'),
                      ],
                    ),
                    content: const Text(
                      'This will download the POI list from the cloud.\n\n'
                      'NOTE: Waypoints are stored on the robot base. '
                      'Pull only shows what\'s in the cloud for reference.',
                    ),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('Cancel')),
                      FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.teal),
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('Pull'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  final mapId = mapIdController.text.trim().isEmpty
                      ? null
                      : mapIdController.text.trim();
                  final cloud = FleetCloudClient();
                  cloud.configure(apiEndpoint: apiUrlController.text.trim());
                  if (mapId != null) cloud.setMapId(mapId);
                  final cloudWaypoints = await cloud.getWaypoints(mapId: mapId);
                  if (mounted) {
                    if (cloudWaypoints.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('No waypoints found in cloud for this map'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    } else {
                      // Show the waypoints (informational only - can't write to robot base)
                      showDialog(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: Text(
                              'Cloud Waypoints (${cloudWaypoints.length})'),
                          content: SizedBox(
                            width: 300,
                            height: 300,
                            child: ListView.builder(
                              itemCount: cloudWaypoints.length,
                              itemBuilder: (ctx, i) => ListTile(
                                leading:
                                    const Icon(Icons.location_on, size: 18),
                                title: Text(cloudWaypoints[i]),
                                dense: true,
                              ),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      );
                    }
                  }
                }
              },
            ),
            const SizedBox(width: 8),
            // Tour Push button
            TextButton.icon(
              icon:
                  const Icon(Icons.cloud_upload, color: Colors.blue, size: 18),
              label: const Text('Tours↑',
                  style: TextStyle(color: Colors.blue, fontSize: 12)),
              onPressed: () async {
                Navigator.pop(ctx);
                // Confirm push
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Push Tours to Cloud?'),
                    content: Text(
                      'This will upload ${SequenceManager.instance.sequences.length} local tour(s) to the cloud.\n\n'
                      'Cloud tours will be updated with your local versions.',
                    ),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('Push')),
                    ],
                  ),
                );
                if (confirm == true) {
                  final pushed =
                      await SequenceManager.instance.pushAllToCloud();
                  if (mounted) {
                    final totalTours = SequenceManager.instance.sequences.length;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(pushed == totalTours
                            ? 'Pushed $pushed tour(s) to cloud!'
                            : 'ERROR: Only pushed $pushed/$totalTours tours! Check debug console for errors.'),
                        backgroundColor: pushed == totalTours ? null : Colors.red,
                        duration: Duration(seconds: pushed == totalTours ? 2 : 5),
                      ),
                    );
                    setState(() {});
                  }
                }
              },
            ),
            // Tour Pull button
            TextButton.icon(
              icon: const Icon(Icons.cloud_download,
                  color: Colors.green, size: 18),
              label: const Text('Tours↓',
                  style: TextStyle(color: Colors.green, fontSize: 12)),
              onPressed: () async {
                Navigator.pop(ctx);
                // Confirm pull
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Pull Tours from Cloud?'),
                    content: const Text(
                      'This will download tours from the cloud and REPLACE your local tours.\n\n'
                      'Any local-only tours will be lost!',
                    ),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('Cancel')),
                      FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.orange),
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('Pull & Replace'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await SequenceManager.instance.loadFromCloud();
                  // Save pulled tours to local storage
                  await SequenceManager.instance.save();
                  final count = SequenceManager.instance.sequences.length;
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Pulled $count tour(s) from cloud!')),
                    );
                    setState(() {});
                  }
                }
              },
            ),
          ],
          // Save & Connect button
          FilledButton.icon(
            icon: const Icon(Icons.save),
            label: Text(SequenceManager.instance.cloudSyncEnabled
                ? 'Update'
                : 'Connect'),
            onPressed: () async {
              Navigator.pop(ctx);
              await SequenceManager.instance.configureCloud(
                apiUrl: apiUrlController.text.trim(),
                mapId: mapIdController.text.trim().isEmpty
                    ? null
                    : mapIdController.text.trim(),
              );
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      SequenceManager.instance.cloudSyncEnabled
                          ? 'Connected! Use PUSH or PULL to sync.'
                          : 'Cloud sync disabled',
                    ),
                  ),
                );
                setState(() {}); // Refresh UI
              }
            },
          ),
        ],
      ),
    );
  }

  // Debug flag for verbose logging
  static const bool _enableVerboseLogging = false;

  @override
  Widget build(BuildContext context) {
    if (_enableVerboseLogging) {
      debugPrint(
          'SequenceEditor: build() - isEditing=$_isEditing, selectedSequence=${_selectedSequence?.name}');
    }

    // When editing, DON'T use ListenableBuilder - completely isolate from rebuilds
    // This prevents the text input chaos caused by rebuilds resetting cursor position
    if (_isEditing && _selectedSequence != null) {
      if (_enableVerboseLogging) {
        debugPrint('SequenceEditor: Showing edit form');
      }
      // Return the form directly - don't wrap in Column (causes Expanded layout issues)
      return _buildSequenceEditForm(_selectedSequence!);
    }

    // When not editing, use ListenableBuilder for reactive updates
    return ListenableBuilder(
      listenable: SequenceManager.instance,
      builder: (context, _) {
        final sequences = SequenceManager.instance.sequences;
        final status = SequenceManager.instance.status;
        final runningSequence = SequenceManager.instance.currentSequence;

        // Skip excessive logging - only log when something we care about changed
        final sequenceCount = sequences.length;
        final runningId = runningSequence?.id;
        final shouldLog = sequenceCount != _cachedSequenceCount ||
            status != _cachedStatus ||
            runningId != _cachedRunningSequenceId;

        if (shouldLog) {
          debugPrint(
              'SequenceEditor: ListenableBuilder - $sequenceCount sequences, status=$status, running=${runningSequence?.name}');
          _cachedSequenceCount = sequenceCount;
          _cachedStatus = status;
          _cachedRunningSequenceId = runningId;
        }

        // When a tour is running, show prominent status and collapse editor
        if (status == SequenceStatus.running && runningSequence != null) {
          return Column(
            children: [
              // Running sequence takes center stage
              const Expanded(
                child: SequenceRunnerWidget(),
              ),
              // Collapsed header - just show we have sequences available
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  border: Border(top: BorderSide(color: Colors.grey[700]!)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.folder, size: 16, color: Colors.grey[500]),
                    const SizedBox(width: 8),
                    Text(
                      '${sequences.length} sequence${sequences.length == 1 ? '' : 's'} available',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                    const Spacer(),
                    Text(
                      'Stop sequence to edit',
                      style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 11,
                          fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        // When not running, show full editor
        final displayTour = _selectedSequence;

        return Column(
          children: [
            // Header with tour list
            _buildHeader(sequences, status),

            // Sequence content - show selected sequence or empty state
            Expanded(
              child: displayTour == null
                  ? _buildEmptyState()
                  : _buildSequencePreview(displayTour),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(List<Sequence> sequences, SequenceStatus status) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Title row
          Row(
            children: [
              const Icon(Icons.route, size: 18),
              const SizedBox(width: 6),
              const Text(
                'Sequence',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (status == SequenceStatus.running) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 4),
                      Text('On',
                          style: TextStyle(color: Colors.white, fontSize: 11)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      debugPrint('SequenceEditor: Stop button pressed!');
                      SequenceManager.instance.stopSequence();
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: Colors.red.withValues(alpha: 0.5)),
                      ),
                      child:
                          const Icon(Icons.stop, color: Colors.red, size: 18),
                    ),
                  ),
                ),
              ] else ...[
                // Cloud sync button
                SizedBox(
                  width: 32,
                  height: 32,
                  child: IconButton(
                    icon: Icon(
                      Icons.cloud_sync,
                      size: 18,
                      color: SequenceManager.instance.cloudSyncEnabled
                          ? Colors.green
                          : Colors.grey,
                    ),
                    onPressed: _showCloudSyncDialog,
                    tooltip: 'Cloud',
                    padding: EdgeInsets.zero,
                  ),
                ),
                SizedBox(
                  width: 32,
                  height: 32,
                  child: IconButton(
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: _createNewSequence,
                    tooltip: 'New',
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ],
          ),
          // Controls row (when not running)
          if (status != SequenceStatus.running && sequences.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    value: _selectedSequence?.id,
                    hint: const Text('Select Sequence',
                        style: TextStyle(fontSize: 13)),
                    isExpanded: true,
                    isDense: true,
                    items: sequences
                        .map((t) => DropdownMenuItem(
                              value: t.id,
                              child:
                                  Text(t.name, overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (id) {
                      if (id != null) {
                        _selectSequence(
                            sequences.firstWhere((t) => t.id == id));
                      }
                    },
                  ),
                ),
                if (_selectedSequence != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.red, size: 20),
                    onPressed: () => _deleteSequence(_selectedSequence!),
                    tooltip: 'Delete Sequence',
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    debugPrint('SequenceEditor: Building empty state');
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.route_outlined, size: 64, color: Colors.white70),
          const SizedBox(height: 16),
          const Text(
            'No sequence selected',
            style: TextStyle(fontSize: 18, color: Colors.white70),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Create Sequence'),
            onPressed: _createNewSequence,
          ),
        ],
      ),
    );
  }

  Widget _buildSequencePreview(Sequence seq) {
    return Column(
      children: [
        // Tour info header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      seq.name,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    if (seq.description.isNotEmpty)
                      Text(
                        seq.description,
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                    Text(
                      '${seq.stops.length} stops${seq.loop ? ' (loops)' : ''}',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => setState(() => _isEditing = true),
                tooltip: 'Edit Sequence',
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deleteSequence(seq),
                tooltip: 'Delete Sequence',
              ),
              const SizedBox(width: 8),
              // Show prominent Start Tour button if startWaypoint exists
              if (seq.startWaypoint != null && seq.startWaypoint!.isNotEmpty)
                ElevatedButton.icon(
                  icon: const Icon(Icons.rocket_launch),
                  label: const Text('START TOUR'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: seq.stops.isNotEmpty
                      ? () {
                          debugPrint(
                              'Starting tour with startWaypoint: ${seq.startWaypoint}');
                          widget.onStartSequence?.call(seq);
                          SequenceManager.instance.startSequence(seq);
                        }
                      : null,
                )
              else
                // Regular start button if no startWaypoint
                ElevatedButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: seq.stops.isNotEmpty
                      ? () {
                          widget.onStartSequence?.call(seq);
                          SequenceManager.instance.startSequence(seq);
                        }
                      : null,
                ),
            ],
          ),
        ),

        // Stops list
        Expanded(
          child: seq.stops.isEmpty
              ? Center(
                  child: Text(
                    'No stops configured. Tap Edit to add waypoints.',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: seq.stops.length,
                  itemBuilder: (ctx, index) {
                    final stop = seq.stops[index];
                    return _buildStopPreviewCard(stop, index);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildStopPreviewCard(SequenceStop stop, int index) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: Text('${index + 1}'),
        ),
        title: Text(stop.waypoint),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (stop.speakText != null && stop.speakText!.isNotEmpty)
              Row(
                children: [
                  const Icon(Icons.volume_up, size: 14),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      stop.speakText!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            if (stop.displayUrl != null && stop.displayUrl!.isNotEmpty)
              Row(
                children: [
                  const Icon(Icons.web, size: 14),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      stop.displayUrl!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
          ],
        ),
        trailing: stop.hasActions
            ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
            : const Icon(Icons.radio_button_unchecked, size: 20),
      ),
    );
  }

  Widget _buildSequenceEditForm(Sequence seq) {
    return Column(
      children: [
        // Edit header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () async {
                  await _saveSequence();
                  setState(() => _isEditing = false);
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _tourNameController,
                  decoration: const InputDecoration(
                    labelText: 'Sequence Name',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                icon: const Icon(Icons.done),
                label: const Text('Done'),
                onPressed: () async {
                  await _saveSequence();
                  setState(() => _isEditing = false);
                },
              ),
            ],
          ),
        ),

        // Tour options
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: CheckboxListTile(
                  title: const Text('Loop', style: TextStyle(fontSize: 14)),
                  value: seq.loop,
                  dense: true,
                  onChanged: (v) => _updateTourOptions(loop: v),
                ),
              ),
              Expanded(
                child: CheckboxListTile(
                  title: const Text('Announce', style: TextStyle(fontSize: 14)),
                  value: seq.announceArrival,
                  dense: true,
                  onChanged: (v) => _updateTourOptions(announceArrival: v),
                ),
              ),
            ],
          ),
        ),

        // Motion Trigger - Start tour when someone approaches
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: seq.motionTriggerStart
                ? Colors.blue.withValues(alpha: 0.1)
                : Colors.grey.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color:
                  seq.motionTriggerStart ? Colors.blue : Colors.grey.shade700,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    seq.motionTriggerStart ? Icons.sensors : Icons.sensors_off,
                    color: seq.motionTriggerStart ? Colors.blue : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Motion Trigger',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Switch(
                    value: seq.motionTriggerStart,
                    onChanged: (v) => _updateTourOptions(motionTriggerStart: v),
                  ),
                ],
              ),
              if (seq.motionTriggerStart) ...[
                Text(
                  'Robot greets visitors at Start location and shows Start button',
                  style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _motionGreetingController,
                  decoration: const InputDecoration(
                    labelText: 'Greeting Message (TTS)',
                    hintText: 'Would you like a Tour of the Robotics Floor?',
                    border: OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: Icon(Icons.record_voice_over, size: 18),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _motionButtonTextController,
                  decoration: const InputDecoration(
                    labelText: 'Button Text',
                    hintText: 'Start Tour',
                    border: OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: Icon(Icons.touch_app, size: 18),
                  ),
                ),
              ],
            ],
          ),
        ),

        // Start waypoint + intro message
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Start waypoint dropdown - use key to force recreation on sequence change
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<String?>(
                  key: ValueKey(
                      'start_wp_${seq.id}_${_normalizeWaypointValue(seq.startWaypoint)}'),
                  // Convert empty string to null; ensure value exists in waypoints or use null
                  initialValue: _normalizeWaypointValue(seq.startWaypoint),
                  decoration: const InputDecoration(
                    labelText: 'Start At',
                    prefixIcon: Icon(Icons.play_arrow, size: 20),
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('(None)')),
                    ...widget.availableWaypoints
                        .map((wp) => DropdownMenuItem<String?>(
                              value: wp,
                              child: Text(wp, overflow: TextOverflow.ellipsis),
                            )),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedSequence =
                          _selectedSequence!.copyWith(startWaypoint: value);
                    });
                    // Auto-save dropdown changes
                    _saveSequence();
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Start message
              Expanded(
                child: TextField(
                  controller: _introTextController,
                  decoration: const InputDecoration(
                    labelText: 'Start Message',
                    hintText: 'Welcome to our facility...',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  maxLines: 2,
                ),
              ),
            ],
          ),
        ),
        // End waypoint + rest time + outro message
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // End waypoint dropdown - use key to force recreation on sequence change
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<String?>(
                  key: ValueKey(
                      'end_wp_${seq.id}_${_normalizeWaypointValue(seq.endWaypoint)}'),
                  // Convert empty string to null; ensure value exists in waypoints or use null
                  initialValue: _normalizeWaypointValue(seq.endWaypoint),
                  decoration: const InputDecoration(
                    labelText: 'End At',
                    prefixIcon: Icon(Icons.stop, size: 20),
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('(None)')),
                    ...widget.availableWaypoints
                        .map((wp) => DropdownMenuItem<String?>(
                              value: wp,
                              child: Text(wp, overflow: TextOverflow.ellipsis),
                            )),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedSequence =
                          _selectedSequence!.copyWith(endWaypoint: value);
                    });
                    // Auto-save dropdown changes
                    _saveSequence();
                  },
                ),
              ),
              const SizedBox(width: 8),
              // End message
              Expanded(
                child: TextField(
                  controller: _outroTextController,
                  decoration: const InputDecoration(
                    labelText: 'End Message',
                    hintText: 'Thank you for visiting...',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  maxLines: 2,
                ),
              ),
            ],
          ),
        ),

        // Rest at end timer (only show if loop is enabled or end waypoint is set)
        if (seq.loop || (seq.endWaypoint?.isNotEmpty == true))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.hourglass_bottom,
                    size: 20, color: Colors.orange),
                const SizedBox(width: 8),
                const Text('Rest at end:'),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    value: seq.restAtEndSeconds.toDouble(),
                    min: 0,
                    max: 300,
                    divisions: 30,
                    label: seq.restAtEndSeconds == 0
                        ? 'No rest'
                        : '${seq.restAtEndSeconds} sec',
                    onChanged: (value) {
                      setState(() {
                        _selectedSequence = _selectedSequence!.copyWith(
                          restAtEndSeconds: value.round(),
                        );
                      });
                    },
                    onChangeEnd: (value) {
                      // Auto-save when slider is released (not during drag)
                      _saveSequence();
                    },
                  ),
                ),
                SizedBox(
                  width: 60,
                  child: Text(
                    seq.restAtEndSeconds == 0
                        ? 'None'
                        : '${seq.restAtEndSeconds}s',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),

        const Divider(),

        // Add waypoint button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Text('Stops',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              ElevatedButton.icon(
                icon: const Icon(Icons.add_location, size: 18),
                label: const Text('Add Stop'),
                onPressed: () => _showAddStopDialog(seq),
              ),
            ],
          ),
        ),

        // Reorderable stops list
        Expanded(
          child: seq.stops.isEmpty
              ? Center(
                  child: Text(
                    'Tap "Add Stop" to add waypoints',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: seq.stops.length,
                  onReorder: _reorderStops,
                  itemBuilder: (ctx, index) {
                    final stop = seq.stops[index];
                    return _buildStopEditCard(seq, stop, index);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildStopEditCard(Sequence seq, SequenceStop stop, int index) {
    return Card(
      key: ValueKey('${seq.id}_${stop.waypoint}_$index'),
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ExpansionTile(
        leading: ReorderableDragStartListener(
          index: index,
          child: const Icon(Icons.drag_handle),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 12,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Text('${index + 1}', style: const TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 8),
            Text(stop.waypoint),
          ],
        ),
        subtitle: stop.hasActions
            ? const Text('Actions configured',
                style: TextStyle(fontSize: 11, color: Colors.green))
            : null,
        trailing: IconButton(
          icon: const Icon(Icons.delete, size: 20),
          onPressed: () => _removeStop(index),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Speak text - NO onChanged, read from controller on save
                TextField(
                  controller: _getStopController(
                      '${seq.id}_${index}_speak', stop.speakText ?? ''),
                  decoration: const InputDecoration(
                    labelText: 'Speak Text (TTS)',
                    hintText: 'What to say at this stop...',
                    prefixIcon: Icon(Icons.volume_up),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),

                // Display URL - NO onChanged
                TextField(
                  controller: _getStopController(
                      '${seq.id}_${index}_url', stop.displayUrl ?? ''),
                  decoration: const InputDecoration(
                    labelText: 'Display URL (website/image)',
                    hintText: 'https://...',
                    prefixIcon: Icon(Icons.web),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),

                // Duration and wait - NO onChanged
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _getStopController(
                            '${seq.id}_${index}_duration',
                            stop.displayDuration.toString()),
                        decoration: const InputDecoration(
                          labelText: 'Display (sec)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _getStopController(
                            '${seq.id}_${index}_wait',
                            stop.waitSeconds.toString()),
                        decoration: const InputDecoration(
                          labelText: 'Extra Wait (sec)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAddStopDialog(Sequence seq) {
    // Filter out waypoints already in the tour
    final usedWaypoints = seq.stops.map((s) => s.waypoint).toSet();
    final available = widget.availableWaypoints
        .where((wp) => !usedWaypoints.contains(wp))
        .toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All waypoints already added')),
      );
      return;
    }

    final taskEngine = TaskEngine.instance;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Stop'),
        content: SizedBox(
          width: 300,
          height: 400,
          child: ListView.builder(
            itemCount: available.length,
            itemBuilder: (ctx, index) {
              final wp = available[index];
              final hasTask = taskEngine.hasMode(wp);
              return ListTile(
                leading: Icon(
                  Icons.location_on,
                  color: hasTask ? Colors.green : null,
                ),
                title: Text(wp),
                subtitle: hasTask
                    ? const Text('Has task config',
                        style: TextStyle(fontSize: 11, color: Colors.green))
                    : null,
                trailing: hasTask
                    ? const Icon(Icons.auto_awesome,
                        size: 16, color: Colors.green)
                    : null,
                onTap: () {
                  // Copy task config values to the new SequenceStop
                  final stop = _createStopFromWaypointTask(wp, taskEngine);
                  _addStop(stop);
                  Navigator.pop(ctx);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  /// Create a SequenceStop from a waypoint, copying any TaskEngine task config
  SequenceStop _createStopFromWaypointTask(
      String waypoint, TaskEngine taskEngine) {
    final assignment = taskEngine.getAssignment(waypoint);

    if (assignment == null || assignment.modeId == null) {
      // No task configured - return basic stop
      return SequenceStop(waypoint: waypoint);
    }

    final params = assignment.params;

    // Copy speak text and display URL from task config
    return SequenceStop(
      waypoint: waypoint,
      speakText: params['speak_text'],
      displayUrl: params['display_url'],
      displayDuration: int.tryParse(params['display_duration'] ?? '0') ?? 0,
      waitSeconds: int.tryParse(params['wait_seconds'] ?? '0') ?? 0,
    );
  }
}

/// Sequence runner widget - expands to fill space when sequence is active
class SequenceRunnerWidget extends StatelessWidget {
  const SequenceRunnerWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SequenceManager.instance,
      builder: (context, _) {
        final seq = SequenceManager.instance.currentSequence;
        final status = SequenceManager.instance.status;
        final stopIndex = SequenceManager.instance.currentStopIndex;
        final stop = SequenceManager.instance.currentStop;
        final phase = SequenceManager.instance.currentPhase;
        final countdown = SequenceManager.instance.countdownSeconds;
        final phaseDuration = SequenceManager.instance.phaseDurationSeconds;

        if (status != SequenceStatus.running || seq == null) {
          return const SizedBox.shrink();
        }

        return Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.green, width: 2),
          ),
          child: Column(
            children: [
              // Header with tour name and controls
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.2),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(14)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.play_circle,
                        color: Colors.green, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            seq.name,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Stop ${stopIndex + 1} of ${seq.stops.length}${seq.loop ? ' (looping)' : ''}',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[400]),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next, size: 28),
                      onPressed: SequenceManager.instance.skipToNextStop,
                      tooltip: 'Skip to next stop',
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.stop, size: 18),
                      label: const Text('Stop'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: SequenceManager.instance.stopSequence,
                    ),
                  ],
                ),
              ),

              // Main content area - stacked vertically for narrow panel
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      // Phase display row - compact
                      Row(
                        children: [
                          // Countdown circle (smaller)
                          Container(
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                              color:
                                  _getPhaseColor(phase).withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: _getPhaseColor(phase), width: 2),
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                if (countdown > 0 && phaseDuration > 0)
                                  SizedBox(
                                    width: 60,
                                    height: 60,
                                    child: CircularProgressIndicator(
                                      value: countdown / phaseDuration,
                                      strokeWidth: 5,
                                      backgroundColor: Colors.grey[800],
                                      color: _getPhaseColor(phase),
                                    ),
                                  ),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(phase.icon,
                                        size: 20, color: _getPhaseColor(phase)),
                                    if (countdown > 0)
                                      Text(
                                        '${countdown}s',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: _getPhaseColor(phase),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Phase badge + waypoint
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _getPhaseColor(phase),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(phase.icon,
                                          size: 14, color: Colors.white),
                                      const SizedBox(width: 4),
                                      Text(
                                        phase.label,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (stop != null)
                                  Row(
                                    children: [
                                      const Icon(Icons.location_on, size: 16),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          stop.waypoint,
                                          style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Stop details
                      if (stop != null) ...[
                        if (stop.speakText != null &&
                            stop.speakText!.isNotEmpty)
                          _buildDetailRow(
                              Icons.volume_up, 'Speech', stop.speakText!),
                        if (stop.displayUrl != null &&
                            stop.displayUrl!.isNotEmpty)
                          _buildDetailRow(
                              Icons.web, 'Display', stop.displayUrl!),
                        if (stop.waitSeconds > 0)
                          _buildDetailRow(Icons.timer, 'Wait',
                              '${stop.waitSeconds} seconds'),
                      ],

                      const SizedBox(height: 12),
                      // Stop progress indicator
                      _buildStopProgress(seq, stopIndex),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey[500]),
          const SizedBox(width: 8),
          Text('$label: ',
              style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStopProgress(Sequence seq, int currentIndex) {
    return Row(
      children: List.generate(seq.stops.length, (index) {
        final isCompleted = index < currentIndex;
        final isCurrent = index == currentIndex;
        return Expanded(
          child: Container(
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: isCompleted
                  ? Colors.green
                  : isCurrent
                      ? Colors.green.withValues(alpha: 0.5)
                      : Colors.grey[700],
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
      }),
    );
  }

  Color _getPhaseColor(SequencePhase phase) {
    switch (phase) {
      case SequencePhase.navigating:
        return Colors.blue;
      case SequencePhase.arriving:
        return Colors.green;
      case SequencePhase.speaking:
        return Colors.orange;
      case SequencePhase.displaying:
        return Colors.purple;
      case SequencePhase.waiting:
        return Colors.teal;
      case SequencePhase.awaitingVisitor:
        return Colors.amber;
    }
  }
}
