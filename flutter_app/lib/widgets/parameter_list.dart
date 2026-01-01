import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/robot_connection.dart';

/// Displays and allows editing of robot parameters
class ParameterList extends StatefulWidget {
  final List<String> parameters;

  const ParameterList({super.key, required this.parameters});

  @override
  State<ParameterList> createState() => _ParameterListState();
}

class _ParameterListState extends State<ParameterList> {
  final Map<String, dynamic> _paramValues = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadParameters();
  }

  Future<void> _loadParameters() async {
    final robot = context.read<RobotConnection>();
    final client = robot.client;

    for (final param in widget.parameters) {
      try {
        final result = await client.callService(
          service: '/rosapi/get_param',
          args: {'name': param},
          timeout: const Duration(seconds: 2),
        );
        _paramValues[param] = result['values']?['value'];
      } catch (e) {
        _paramValues[param] = null;
      }
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.settings),
        title: const Text('Robot Parameters'),
        subtitle: Text('${widget.parameters.length} parameters'),
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.parameters.length,
              itemBuilder: (context, index) {
                final param = widget.parameters[index];
                return _buildParameterTile(param);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildParameterTile(String param) {
    final value = _paramValues[param];
    final shortName = param.split('/').last;

    return ListTile(
      dense: true,
      title: Text(shortName),
      subtitle: Text(param, style: const TextStyle(fontSize: 10)),
      trailing: Text(
        value?.toString() ?? 'N/A',
        style: const TextStyle(fontFamily: 'monospace'),
      ),
      onTap: () => _showEditDialog(param, value),
    );
  }

  Future<void> _showEditDialog(String param, dynamic currentValue) async {
    final controller = TextEditingController(text: currentValue?.toString());

    final newValue = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit ${param.split('/').last}'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: param,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newValue != null && newValue != currentValue?.toString()) {
      await _setParameter(param, newValue);
    }
  }

  Future<void> _setParameter(String param, String value) async {
    final robot = context.read<RobotConnection>();
    try {
      await robot.client.callService(
        service: '/rosapi/set_param',
        args: {'name': param, 'value': value},
      );
      setState(() => _paramValues[param] = value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Updated $param')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e')),
        );
      }
    }
  }
}
