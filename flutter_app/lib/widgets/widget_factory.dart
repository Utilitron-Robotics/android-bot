import 'package:flutter/material.dart';
import '../services/robot_introspection.dart';
import 'status_panel.dart';
import 'waypoint_grid.dart';
import 'joystick.dart';
import 'parameter_list.dart';
import 'voice_control.dart';

/// Dynamically generates UI widgets based on discovered robot capabilities
class WidgetFactory {
  final RobotCapabilities capabilities;

  WidgetFactory(this.capabilities);

  /// Generate all applicable widgets for this robot
  List<Widget> generateWidgets(BuildContext context) {
    final widgets = <Widget>[];

    // Always show status if available
    if (capabilities.hasStatus || capabilities.hasBattery) {
      widgets.add(const StatusPanel());
    }

    // Waypoint grid if navigation available
    if (capabilities.hasNavigation) {
      widgets.add(WaypointGrid(waypoints: capabilities.waypoints));
      // Voice control (uses waypoints for matching)
      widgets.add(VoiceControl(availableWaypoints: capabilities.waypoints));
    }

    // Joystick if velocity control available
    if (capabilities.hasVelocityControl) {
      widgets.add(const JoystickControl());
    }

    // Parameters if any discovered
    if (capabilities.parameters.isNotEmpty) {
      widgets.add(ParameterList(parameters: capabilities.parameters));
    }

    // Discovery summary (collapsible)
    widgets.add(_buildDiscoverySummary());

    return widgets;
  }

  Widget _buildDiscoverySummary() {
    return ExpansionTile(
      title: const Text('Discovered Capabilities'),
      leading: const Icon(Icons.info_outline),
      children: [
        ListTile(
          leading: const Icon(Icons.topic),
          title: Text('${capabilities.topics.length} Topics'),
          subtitle: Text(
            capabilities.topics.take(5).map((t) => t.name).join(', ') +
                (capabilities.topics.length > 5 ? '...' : ''),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.miscellaneous_services),
          title: Text('${capabilities.services.length} Services'),
          subtitle: Text(
            capabilities.services.take(5).map((s) => s.name).join(', ') +
                (capabilities.services.length > 5 ? '...' : ''),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.settings),
          title: Text('${capabilities.parameters.length} Parameters'),
        ),
        ListTile(
          leading: const Icon(Icons.location_on),
          title: Text('${capabilities.waypoints.length} Waypoints'),
          subtitle: Text(
            capabilities.waypoints.take(5).join(', ') +
                (capabilities.waypoints.length > 5 ? '...' : ''),
          ),
        ),
      ],
    );
  }
}
