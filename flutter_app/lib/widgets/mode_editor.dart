import 'package:flutter/material.dart';
import '../core/task_engine.dart';

/// Mode Editor widget for creating and managing task modes
/// Supports parallel and serial task execution
class ModeEditor extends StatefulWidget {
  final List<String> availableWaypoints;
  final void Function(String waypoint, String? modeId)? onAssignMode;

  const ModeEditor({
    super.key,
    required this.availableWaypoints,
    this.onAssignMode,
  });

  @override
  State<ModeEditor> createState() => _ModeEditorState();
}

class _ModeEditorState extends State<ModeEditor> {
  TaskMode? _selectedMode;
  bool _isEditing = false;
  String? _assigningToWaypoint;

  // Controllers for mode editing
  final TextEditingController _modeNameController = TextEditingController();
  final TextEditingController _modeDescController = TextEditingController();
  final Map<String, TextEditingController> _stepControllers = {};

  @override
  void initState() {
    super.initState();
    TaskEngine.instance.load();
  }

  @override
  void dispose() {
    _modeNameController.dispose();
    _modeDescController.dispose();
    for (final c in _stepControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _getStepController(String key, String initialValue) {
    if (!_stepControllers.containsKey(key)) {
      _stepControllers[key] = TextEditingController(text: initialValue);
    }
    return _stepControllers[key]!;
  }

  void _createNewMode() {
    final newMode = TaskMode(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'New Mode',
      description: '',
      steps: [],
    );
    TaskEngine.instance.saveMode(newMode);
    _modeNameController.text = newMode.name;
    _modeDescController.text = '';
    setState(() {
      _selectedMode = newMode;
      _isEditing = true;
    });
  }

  void _selectMode(TaskMode mode) {
    _modeNameController.text = mode.name;
    _modeDescController.text = mode.description;
    setState(() {
      _selectedMode = mode;
      _isEditing = false;
    });
  }

  void _deleteMode(TaskMode mode) {
    if (mode.isBuiltIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot delete built-in modes')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Mode'),
        content: Text('Delete "${mode.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              TaskEngine.instance.deleteMode(mode.id);
              if (_selectedMode?.id == mode.id) {
                setState(() {
                  _selectedMode = null;
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

  void _saveMode() {
    if (_selectedMode == null || _selectedMode!.isBuiltIn) return;

    // Build steps from controllers
    final steps = <TaskStep>[];
    for (int i = 0; i < _selectedMode!.steps.length; i++) {
      final oldStep = _selectedMode!.steps[i];
      steps.add(TaskStep(
        id: oldStep.id,
        action: oldStep.action,
        data: _stepControllers['${_selectedMode!.id}_${i}_data']?.text ?? oldStep.data,
        durationSeconds: int.tryParse(_stepControllers['${_selectedMode!.id}_${i}_duration']?.text ?? '') ?? oldStep.durationSeconds,
        parallel: oldStep.parallel,
      ));
    }

    final updatedMode = TaskMode(
      id: _selectedMode!.id,
      name: _modeNameController.text,
      description: _modeDescController.text,
      steps: steps,
      announceArrival: _selectedMode!.announceArrival,
      isBuiltIn: false,
    );

    _selectedMode = updatedMode;
    TaskEngine.instance.saveMode(updatedMode);
  }

  void _addStep(TaskAction action) {
    if (_selectedMode == null) return;
    final newStep = TaskStep(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      action: action,
      data: '',
      durationSeconds: action == TaskAction.wait ? 5 : 0,
    );
    setState(() {
      _selectedMode = _selectedMode!.copyWith(
        steps: [..._selectedMode!.steps, newStep],
      );
    });
  }

  void _removeStep(int index) {
    if (_selectedMode == null) return;
    _stepControllers.remove('${_selectedMode!.id}_${index}_data')?.dispose();
    _stepControllers.remove('${_selectedMode!.id}_${index}_duration')?.dispose();
    setState(() {
      final newSteps = [..._selectedMode!.steps]..removeAt(index);
      _selectedMode = _selectedMode!.copyWith(steps: newSteps);
    });
  }

  void _toggleParallel(int index) {
    if (_selectedMode == null) return;
    setState(() {
      final newSteps = [..._selectedMode!.steps];
      newSteps[index] = newSteps[index].copyWith(parallel: !newSteps[index].parallel);
      _selectedMode = _selectedMode!.copyWith(steps: newSteps);
    });
  }

  void _reorderSteps(int oldIndex, int newIndex) {
    if (_selectedMode == null) return;
    if (newIndex > oldIndex) newIndex--;
    setState(() {
      final newSteps = [..._selectedMode!.steps];
      final item = newSteps.removeAt(oldIndex);
      newSteps.insert(newIndex, item);
      _selectedMode = _selectedMode!.copyWith(steps: newSteps);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_assigningToWaypoint != null) {
      return _buildAssignmentView();
    }

    if (_isEditing && _selectedMode != null) {
      return _buildEditForm(_selectedMode!);
    }

    return ListenableBuilder(
      listenable: TaskEngine.instance,
      builder: (context, _) {
        final modes = TaskEngine.instance.allModes;

        return Column(
          children: [
            _buildHeader(modes),
            Expanded(
              child: _selectedMode == null
                  ? _buildEmptyState()
                  : _buildModePreview(_selectedMode!),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(List<TaskMode> modes) {
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
          const Icon(Icons.auto_fix_high, size: 24),
          const SizedBox(width: 8),
          const Text(
            'Task Modes',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          // Mode selector dropdown
          if (modes.isNotEmpty)
            DropdownButton<String>(
              value: _selectedMode?.id,
              hint: const Text('Select Mode'),
              items: modes.map((m) => DropdownMenuItem(
                value: m.id,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (m.isBuiltIn)
                      const Icon(Icons.lock, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(m.name),
                  ],
                ),
              )).toList(),
              onChanged: (id) {
                if (id != null) {
                  _selectMode(modes.firstWhere((m) => m.id == id));
                }
              },
            ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.assignment),
            onPressed: () => setState(() => _assigningToWaypoint = ''),
            tooltip: 'Assign to Waypoint',
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _createNewMode,
            tooltip: 'New Mode',
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.auto_fix_high, size: 64, color: Colors.white70),
          const SizedBox(height: 16),
          const Text(
            'No mode selected',
            style: TextStyle(fontSize: 18, color: Colors.white70),
          ),
          const SizedBox(height: 8),
          const Text(
            'Modes define what happens when the robot arrives at a waypoint',
            style: TextStyle(color: Colors.white54),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Create Mode'),
            onPressed: _createNewMode,
          ),
        ],
      ),
    );
  }

  Widget _buildModePreview(TaskMode mode) {
    return Column(
      children: [
        // Mode info header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          mode.name,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        if (mode.isBuiltIn) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('Built-in', style: TextStyle(fontSize: 10)),
                          ),
                        ],
                      ],
                    ),
                    if (mode.description.isNotEmpty)
                      Text(
                        mode.description,
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                    Text(
                      '${mode.steps.length} steps',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (!mode.isBuiltIn) ...[
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => setState(() => _isEditing = true),
                  tooltip: 'Edit Mode',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _deleteMode(mode),
                  tooltip: 'Delete Mode',
                ),
              ],
            ],
          ),
        ),

        // Steps list
        Expanded(
          child: mode.steps.isEmpty
              ? Center(
                  child: Text(
                    'No steps configured.',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: mode.steps.length,
                  itemBuilder: (ctx, index) {
                    final step = mode.steps[index];
                    return _buildStepPreviewCard(step, index, mode.steps.length);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildStepPreviewCard(TaskStep step, int index, int totalSteps) {
    final isLastStep = index == totalSteps - 1;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getActionColor(step.action),
          child: Icon(_getActionIcon(step.action), size: 18, color: Colors.white),
        ),
        title: Text(step.action.label),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (step.data.isNotEmpty)
              Text(
                step.data,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            if (step.durationSeconds > 0)
              Text(
                '${step.durationSeconds} seconds',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isLastStep)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: step.parallel ? Colors.orange.withValues(alpha: 0.3) : Colors.blue.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  step.parallel ? 'PARALLEL' : 'SERIAL',
                  style: TextStyle(
                    fontSize: 9,
                    color: step.parallel ? Colors.orange : Colors.blue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            if (!isLastStep)
              Icon(
                step.parallel ? Icons.call_split : Icons.arrow_downward,
                size: 16,
                color: Colors.grey[500],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditForm(TaskMode mode) {
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
                  _saveMode();
                  setState(() => _isEditing = false);
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _modeNameController,
                  decoration: const InputDecoration(
                    labelText: 'Mode Name',
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
                  _saveMode();
                  setState(() => _isEditing = false);
                },
              ),
            ],
          ),
        ),

        // Description
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _modeDescController,
            decoration: const InputDecoration(
              labelText: 'Description',
              hintText: 'What this mode does...',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),

        // Options
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: CheckboxListTile(
            title: const Text('Announce Arrival', style: TextStyle(fontSize: 14)),
            subtitle: const Text('Say "Arrived at [waypoint]" first', style: TextStyle(fontSize: 11)),
            value: mode.announceArrival,
            dense: true,
            onChanged: (v) {
              setState(() {
                _selectedMode = _selectedMode!.copyWith(announceArrival: v ?? true);
              });
            },
          ),
        ),

        const Divider(),

        // Add step buttons
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Steps', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildAddStepButton(TaskAction.speak, Icons.volume_up, Colors.blue),
                  _buildAddStepButton(TaskAction.display, Icons.web, Colors.purple),
                  _buildAddStepButton(TaskAction.wait, Icons.timer, Colors.orange),
                  _buildAddStepButton(TaskAction.navigate, Icons.navigation, Colors.green),
                  _buildAddStepButton(TaskAction.returnOrigin, Icons.home, Colors.teal),
                ],
              ),
            ],
          ),
        ),

        // Reorderable steps list
        Expanded(
          child: mode.steps.isEmpty
              ? Center(
                  child: Text(
                    'Add steps using the buttons above',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: mode.steps.length,
                  onReorder: _reorderSteps,
                  itemBuilder: (ctx, index) {
                    final step = mode.steps[index];
                    return _buildStepEditCard(mode, step, index);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildAddStepButton(TaskAction action, IconData icon, Color color) {
    return ElevatedButton.icon(
      icon: Icon(icon, size: 16),
      label: Text(action.label, style: const TextStyle(fontSize: 12)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.2),
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      onPressed: () => _addStep(action),
    );
  }

  Widget _buildStepEditCard(TaskMode mode, TaskStep step, int index) {
    final isLastStep = index == mode.steps.length - 1;

    return Card(
      key: ValueKey('${mode.id}_${step.id}_$index'),
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: ExpansionTile(
        leading: ReorderableDragStartListener(
          index: index,
          child: const Icon(Icons.drag_handle),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: _getActionColor(step.action),
              child: Icon(_getActionIcon(step.action), size: 14, color: Colors.white),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(step.action.label)),
            if (!isLastStep)
              IconButton(
                icon: Icon(
                  step.parallel ? Icons.call_split : Icons.arrow_downward,
                  color: step.parallel ? Colors.orange : Colors.blue,
                  size: 20,
                ),
                onPressed: () => _toggleParallel(index),
                tooltip: step.parallel ? 'Make Serial' : 'Make Parallel',
              ),
          ],
        ),
        subtitle: step.data.isNotEmpty
            ? Text(step.data, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))
            : null,
        trailing: IconButton(
          icon: const Icon(Icons.delete, size: 20),
          onPressed: () => _removeStep(index),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Data field - varies by action type
                if (step.action == TaskAction.speak)
                  TextField(
                    controller: _getStepController('${mode.id}_${index}_data', step.data),
                    decoration: const InputDecoration(
                      labelText: 'Text to speak',
                      hintText: 'What the robot should say...',
                      prefixIcon: Icon(Icons.volume_up),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    maxLines: 3,
                  )
                else if (step.action == TaskAction.display)
                  TextField(
                    controller: _getStepController('${mode.id}_${index}_data', step.data),
                    decoration: const InputDecoration(
                      labelText: 'Display URL',
                      hintText: 'https://...',
                      prefixIcon: Icon(Icons.web),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  )
                else if (step.action == TaskAction.navigate)
                  DropdownButtonFormField<String>(
                    initialValue: step.data.isEmpty ? null : step.data,
                    decoration: const InputDecoration(
                      labelText: 'Navigate to',
                      prefixIcon: Icon(Icons.navigation),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: widget.availableWaypoints.map((wp) => DropdownMenuItem(
                      value: wp,
                      child: Text(wp),
                    )).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        _getStepController('${mode.id}_${index}_data', step.data).text = value;
                        setState(() {
                          final newSteps = [..._selectedMode!.steps];
                          newSteps[index] = newSteps[index].copyWith(data: value);
                          _selectedMode = _selectedMode!.copyWith(steps: newSteps);
                        });
                      }
                    },
                  ),

                // Duration field for wait/display
                if (step.action == TaskAction.wait || step.action == TaskAction.display) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _getStepController('${mode.id}_${index}_duration', step.durationSeconds.toString()),
                    decoration: InputDecoration(
                      labelText: step.action == TaskAction.wait ? 'Wait duration (seconds)' : 'Display duration (seconds)',
                      prefixIcon: const Icon(Icons.timer),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],

                // Parallel/Serial indicator
                if (!isLastStep) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (step.parallel ? Colors.orange : Colors.blue).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          step.parallel ? Icons.call_split : Icons.arrow_downward,
                          color: step.parallel ? Colors.orange : Colors.blue,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            step.parallel
                                ? 'Runs IN PARALLEL with next step'
                                : 'Runs BEFORE next step (serial)',
                            style: TextStyle(
                              color: step.parallel ? Colors.orange : Colors.blue,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _toggleParallel(index),
                          child: Text(step.parallel ? 'Make Serial' : 'Make Parallel'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignmentView() {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _assigningToWaypoint = null),
              ),
              const SizedBox(width: 8),
              const Text(
                'Assign Mode to Waypoint',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),

        // Waypoint list with mode assignments
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: widget.availableWaypoints.length,
            itemBuilder: (ctx, index) {
              final waypoint = widget.availableWaypoints[index];
              final assignment = TaskEngine.instance.getAssignment(waypoint);
              final currentModeId = assignment?.modeId;

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.location_on),
                  title: Text(waypoint),
                  subtitle: currentModeId != null
                      ? Text(
                          TaskEngine.instance.getMode(currentModeId)?.name ?? currentModeId,
                          style: const TextStyle(color: Colors.green),
                        )
                      : const Text('No mode assigned', style: TextStyle(color: Colors.grey)),
                  trailing: DropdownButton<String?>(
                    value: currentModeId,
                    hint: const Text('Select Mode'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('(None)', style: TextStyle(color: Colors.grey)),
                      ),
                      ...TaskEngine.instance.allModes.map((m) => DropdownMenuItem(
                        value: m.id,
                        child: Text(m.name),
                      )),
                    ],
                    onChanged: (modeId) {
                      TaskEngine.instance.assignMode(waypoint, modeId);
                      widget.onAssignMode?.call(waypoint, modeId);
                      setState(() {});
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Color _getActionColor(TaskAction action) {
    switch (action) {
      case TaskAction.speak:
        return Colors.blue;
      case TaskAction.display:
        return Colors.purple;
      case TaskAction.wait:
        return Colors.orange;
      case TaskAction.navigate:
        return Colors.green;
      case TaskAction.returnOrigin:
        return Colors.teal;
    }
  }

  IconData _getActionIcon(TaskAction action) {
    switch (action) {
      case TaskAction.speak:
        return Icons.volume_up;
      case TaskAction.display:
        return Icons.web;
      case TaskAction.wait:
        return Icons.timer;
      case TaskAction.navigate:
        return Icons.navigation;
      case TaskAction.returnOrigin:
        return Icons.home;
    }
  }
}
