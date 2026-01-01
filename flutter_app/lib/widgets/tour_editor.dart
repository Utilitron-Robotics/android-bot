import 'package:flutter/material.dart';
import '../core/tour_mode.dart';

/// Tour Editor widget for creating and managing tours
class TourEditor extends StatefulWidget {
  final List<String> availableWaypoints;
  final void Function(Tour tour)? onStartTour;

  const TourEditor({
    super.key,
    required this.availableWaypoints,
    this.onStartTour,
  });

  @override
  State<TourEditor> createState() => _TourEditorState();
}

class _TourEditorState extends State<TourEditor> {
  Tour? _selectedTour;
  bool _isEditing = false;

  // Managed TextEditingControllers to fix input issues
  final TextEditingController _tourNameController = TextEditingController();
  final TextEditingController _introTextController = TextEditingController();
  final TextEditingController _outroTextController = TextEditingController();
  final Map<String, TextEditingController> _stopControllers = {};

  @override
  void initState() {
    super.initState();
    TourManager.instance.load();
  }

  @override
  void dispose() {
    _tourNameController.dispose();
    _introTextController.dispose();
    _outroTextController.dispose();
    for (final c in _stopControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Get or create a controller for a stop field
  TextEditingController _getStopController(String stopKey, String initialValue) {
    if (!_stopControllers.containsKey(stopKey)) {
      _stopControllers[stopKey] = TextEditingController(text: initialValue);
    }
    return _stopControllers[stopKey]!;
  }

  /// Clear controllers for removed stops
  void _cleanupStopControllers(Tour tour) {
    final validKeys = <String>{};
    for (int i = 0; i < tour.stops.length; i++) {
      validKeys.add('${tour.id}_${i}_speak');
      validKeys.add('${tour.id}_${i}_url');
      validKeys.add('${tour.id}_${i}_duration');
      validKeys.add('${tour.id}_${i}_wait');
    }
    _stopControllers.removeWhere((key, controller) {
      if (!validKeys.contains(key)) {
        controller.dispose();
        return true;
      }
      return false;
    });
  }

  void _createNewTour() {
    final newTour = Tour(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'New Tour',
      description: '',
      stops: [],
    );
    TourManager.instance.saveTour(newTour);
    _tourNameController.text = newTour.name;
    _introTextController.text = '';
    _outroTextController.text = '';
    setState(() {
      _selectedTour = newTour;
      _isEditing = true;
    });
  }

  void _selectTour(Tour tour) {
    _tourNameController.text = tour.name;
    _introTextController.text = tour.introText ?? '';
    _outroTextController.text = tour.outroText ?? '';
    _cleanupStopControllers(tour);
    setState(() {
      _selectedTour = tour;
      _isEditing = false;
    });
  }

  void _deleteTour(Tour tour) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Tour'),
        content: Text('Delete "${tour.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              TourManager.instance.deleteTour(tour.id);
              if (_selectedTour?.id == tour.id) {
                setState(() {
                  _selectedTour = null;
                  _isEditing = false;
                });
              }
              Navigator.pop(ctx);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _saveTour() {
    // Build tour from controller values - no model updates during typing!
    if (_selectedTour == null) return;

    // Read all values from controllers
    final stops = <TourStop>[];
    for (int i = 0; i < _selectedTour!.stops.length; i++) {
      final oldStop = _selectedTour!.stops[i];
      stops.add(TourStop(
        waypoint: oldStop.waypoint,
        speakText: _stopControllers['${_selectedTour!.id}_${i}_speak']?.text,
        displayUrl: _stopControllers['${_selectedTour!.id}_${i}_url']?.text,
        displayDuration: int.tryParse(_stopControllers['${_selectedTour!.id}_${i}_duration']?.text ?? '') ?? 0,
        waitSeconds: int.tryParse(_stopControllers['${_selectedTour!.id}_${i}_wait']?.text ?? '') ?? 0,
      ));
    }

    final updatedTour = Tour(
      id: _selectedTour!.id,
      name: _tourNameController.text,
      description: _selectedTour!.description,
      stops: stops,
      loop: _selectedTour!.loop,
      announceArrival: _selectedTour!.announceArrival,
      introText: _introTextController.text.isEmpty ? null : _introTextController.text,
      outroText: _outroTextController.text.isEmpty ? null : _outroTextController.text,
    );

    _selectedTour = updatedTour;
    TourManager.instance.saveTour(updatedTour);
  }

  void _updateTourOptions({bool? loop, bool? announceArrival}) {
    // Only for checkboxes - these need immediate state update
    if (_selectedTour == null) return;
    setState(() {
      _selectedTour = _selectedTour!.copyWith(
        loop: loop ?? _selectedTour!.loop,
        announceArrival: announceArrival ?? _selectedTour!.announceArrival,
      );
    });
  }

  void _addStop(TourStop stop) {
    if (_selectedTour == null) return;
    setState(() {
      _selectedTour = _selectedTour!.addStop(stop);
    });
  }

  void _removeStop(int index) {
    if (_selectedTour == null) return;
    // Dispose the controllers for this stop
    _stopControllers.remove('${_selectedTour!.id}_${index}_speak')?.dispose();
    _stopControllers.remove('${_selectedTour!.id}_${index}_url')?.dispose();
    _stopControllers.remove('${_selectedTour!.id}_${index}_duration')?.dispose();
    _stopControllers.remove('${_selectedTour!.id}_${index}_wait')?.dispose();
    setState(() {
      _selectedTour = _selectedTour!.removeStop(index);
    });
  }

  void _reorderStops(int oldIndex, int newIndex) {
    if (_selectedTour == null) return;
    if (newIndex > oldIndex) newIndex--;
    setState(() {
      _selectedTour = _selectedTour!.reorderStop(oldIndex, newIndex);
    });
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('TourEditor: build() - isEditing=$_isEditing, selectedTour=${_selectedTour?.name}');

    // When editing, DON'T use ListenableBuilder - completely isolate from rebuilds
    // This prevents the text input chaos caused by rebuilds resetting cursor position
    if (_isEditing && _selectedTour != null) {
      debugPrint('TourEditor: Showing edit form');
      // Return the form directly - don't wrap in Column (causes Expanded layout issues)
      return _buildTourEditForm(_selectedTour!);
    }

    // When not editing, use ListenableBuilder for reactive updates
    return ListenableBuilder(
      listenable: TourManager.instance,
      builder: (context, _) {
        final tours = TourManager.instance.tours;
        final status = TourManager.instance.status;
        final runningTour = TourManager.instance.currentTour;
        debugPrint('TourEditor: ListenableBuilder - ${tours.length} tours, status=$status, running=${runningTour?.name}');

        // When a tour is running, show that tour's info (not local _selectedTour)
        final displayTour = (status == TourStatus.running && runningTour != null)
            ? runningTour
            : _selectedTour;

        return Column(
          children: [
            // Show running tour status prominently at top
            if (status == TourStatus.running)
              const TourRunnerWidget(),

            // Header with tour list
            _buildHeader(tours, status),

            // Tour content - show running tour or selected tour
            Expanded(
              child: displayTour == null
                  ? _buildEmptyState()
                  : _buildTourPreview(displayTour),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(List<Tour> tours, TourStatus status) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.tour, size: 24),
          const SizedBox(width: 8),
          const Text(
            'Tour Mode',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          if (status == TourStatus.running) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 6),
                  Text('Running', style: TextStyle(color: Colors.white, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.stop, color: Colors.red),
              onPressed: () => TourManager.instance.stopTour(),
              tooltip: 'Stop Tour',
            ),
          ] else ...[
            // Tour selector dropdown
            if (tours.isNotEmpty)
              DropdownButton<String>(
                value: _selectedTour?.id,
                hint: const Text('Select Tour'),
                items: tours.map((t) => DropdownMenuItem(
                  value: t.id,
                  child: Text(t.name),
                )).toList(),
                onChanged: (id) {
                  if (id != null) {
                    _selectTour(tours.firstWhere((t) => t.id == id));
                  }
                },
              ),
            // Delete selected tour
            if (_selectedTour != null)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => _deleteTour(_selectedTour!),
                tooltip: 'Delete Tour',
              ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _createNewTour,
              tooltip: 'New Tour',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    debugPrint('TourEditor: Building empty state');
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.tour_outlined, size: 64, color: Colors.white70),
          const SizedBox(height: 16),
          const Text(
            'No tour selected',
            style: TextStyle(fontSize: 18, color: Colors.white70),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Create Tour'),
            onPressed: _createNewTour,
          ),
        ],
      ),
    );
  }

  Widget _buildTourPreview(Tour tour) {
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
                      tour.name,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    if (tour.description.isNotEmpty)
                      Text(
                        tour.description,
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                    Text(
                      '${tour.stops.length} stops${tour.loop ? ' (loops)' : ''}',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => setState(() => _isEditing = true),
                tooltip: 'Edit Tour',
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deleteTour(tour),
                tooltip: 'Delete Tour',
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                onPressed: tour.stops.isNotEmpty
                    ? () {
                        widget.onStartTour?.call(tour);
                        TourManager.instance.startTour(tour);
                      }
                    : null,
              ),
            ],
          ),
        ),

        // Stops list
        Expanded(
          child: tour.stops.isEmpty
              ? Center(
                  child: Text(
                    'No stops configured. Tap Edit to add waypoints.',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: tour.stops.length,
                  itemBuilder: (ctx, index) {
                    final stop = tour.stops[index];
                    return _buildStopPreviewCard(stop, index);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildStopPreviewCard(TourStop stop, int index) {
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

  Widget _buildTourEditForm(Tour tour) {
    return Column(
      children: [
        // Edit header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  _saveTour();
                  setState(() => _isEditing = false);
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _tourNameController,
                  decoration: const InputDecoration(
                    labelText: 'Tour Name',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                icon: const Icon(Icons.done),
                label: const Text('Done'),
                onPressed: () {
                  _saveTour();
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
                  value: tour.loop,
                  dense: true,
                  onChanged: (v) => _updateTourOptions(loop: v),
                ),
              ),
              Expanded(
                child: CheckboxListTile(
                  title: const Text('Announce', style: TextStyle(fontSize: 14)),
                  value: tour.announceArrival,
                  dense: true,
                  onChanged: (v) => _updateTourOptions(announceArrival: v),
                ),
              ),
            ],
          ),
        ),

        // Start waypoint + intro message
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Start waypoint dropdown
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<String>(
                  initialValue: tour.startWaypoint,
                  decoration: const InputDecoration(
                    labelText: 'Start At',
                    prefixIcon: Icon(Icons.play_arrow, size: 20),
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('(None)')),
                    ...widget.availableWaypoints.map((wp) => DropdownMenuItem(
                      value: wp,
                      child: Text(wp, overflow: TextOverflow.ellipsis),
                    )),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedTour = _selectedTour!.copyWith(startWaypoint: value ?? '');
                    });
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
                    hintText: 'Welcome to our facility tour...',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  maxLines: 2,
                ),
              ),
            ],
          ),
        ),
        // End waypoint + outro message
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // End waypoint dropdown
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<String>(
                  initialValue: tour.endWaypoint,
                  decoration: const InputDecoration(
                    labelText: 'End At',
                    prefixIcon: Icon(Icons.stop, size: 20),
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('(None)')),
                    ...widget.availableWaypoints.map((wp) => DropdownMenuItem(
                      value: wp,
                      child: Text(wp, overflow: TextOverflow.ellipsis),
                    )),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedTour = _selectedTour!.copyWith(endWaypoint: value ?? '');
                    });
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

        const Divider(),

        // Add waypoint button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Text('Stops', style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              ElevatedButton.icon(
                icon: const Icon(Icons.add_location, size: 18),
                label: const Text('Add Stop'),
                onPressed: () => _showAddStopDialog(tour),
              ),
            ],
          ),
        ),

        // Reorderable stops list
        Expanded(
          child: tour.stops.isEmpty
              ? Center(
                  child: Text(
                    'Tap "Add Stop" to add waypoints',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: tour.stops.length,
                  onReorder: _reorderStops,
                  itemBuilder: (ctx, index) {
                    final stop = tour.stops[index];
                    return _buildStopEditCard(tour, stop, index);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildStopEditCard(Tour tour, TourStop stop, int index) {
    return Card(
      key: ValueKey('${tour.id}_${stop.waypoint}_$index'),
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
            ? const Text('Actions configured', style: TextStyle(fontSize: 11, color: Colors.green))
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
                  controller: _getStopController('${tour.id}_${index}_speak', stop.speakText ?? ''),
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
                  controller: _getStopController('${tour.id}_${index}_url', stop.displayUrl ?? ''),
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
                        controller: _getStopController('${tour.id}_${index}_duration', stop.displayDuration.toString()),
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
                        controller: _getStopController('${tour.id}_${index}_wait', stop.waitSeconds.toString()),
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

  void _showAddStopDialog(Tour tour) {
    // Filter out waypoints already in the tour
    final usedWaypoints = tour.stops.map((s) => s.waypoint).toSet();
    final available = widget.availableWaypoints
        .where((wp) => !usedWaypoints.contains(wp))
        .toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All waypoints already added')),
      );
      return;
    }

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
              return ListTile(
                leading: const Icon(Icons.location_on),
                title: Text(wp),
                onTap: () {
                  _addStop(TourStop(waypoint: wp));
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
}

/// Compact tour runner widget for showing during tour execution
class TourRunnerWidget extends StatelessWidget {
  const TourRunnerWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: TourManager.instance,
      builder: (context, _) {
        final tour = TourManager.instance.currentTour;
        final status = TourManager.instance.status;
        final stopIndex = TourManager.instance.currentStopIndex;
        final stop = TourManager.instance.currentStop;

        if (status != TourStatus.running || tour == null) {
          return const SizedBox.shrink();
        }

        return Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green),
          ),
          child: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tour.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (stop != null)
                      Text(
                        'Stop ${stopIndex + 1}/${tour.stops.length}: ${stop.waypoint}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.skip_next),
                onPressed: TourManager.instance.skipToNextStop,
                tooltip: 'Skip to next',
              ),
              IconButton(
                icon: const Icon(Icons.stop, color: Colors.red),
                onPressed: TourManager.instance.stopTour,
                tooltip: 'Stop tour',
              ),
            ],
          ),
        );
      },
    );
  }
}
