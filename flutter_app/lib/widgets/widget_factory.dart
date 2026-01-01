import 'package:flutter/material.dart';
import '../services/robot_introspection.dart';
import 'status_panel.dart';
import 'waypoint_grid.dart';
import 'joystick.dart';
import 'parameter_list.dart';
import 'voice_control.dart';
import 'map_view.dart';
import 'tablet_control_panel.dart';
import 'tour_editor.dart';
import 'announcement_presets.dart';

/// Dynamically generates UI widgets based on discovered robot capabilities
class WidgetFactory {
  final RobotCapabilities capabilities;
  final String? relayHttpUrl;  // HTTP URL for tablet relay (e.g., http://192.168.1.100:8765)

  WidgetFactory(this.capabilities, {this.relayHttpUrl});

  /// Generate all applicable widgets for this robot
  List<Widget> generateWidgets(BuildContext context) {
    final widgets = <Widget>[];

    // Always show status if available
    if (capabilities.hasStatus || capabilities.hasBattery) {
      widgets.add(const StatusPanel());
    }

    // Waypoint grid if navigation available
    if (capabilities.hasNavigation) {
      widgets.add(WaypointGrid(
        waypoints: capabilities.waypoints,
        relayUrl: relayHttpUrl,
      ));
      // Voice control (uses waypoints for matching)
      widgets.add(VoiceControl(availableWaypoints: capabilities.waypoints));
      // Tour mode editor
      widgets.add(_buildTourSection(capabilities.waypoints));
    }

    // Joystick if velocity control available
    if (capabilities.hasVelocityControl) {
      widgets.add(const JoystickControl());
    }

    // Map view - always show, it will display status if no data
    widgets.add(const MapView());

    // Tablet control panel (only when connected via relay)
    if (relayHttpUrl != null) {
      widgets.add(TabletControlPanel(relayHttpUrl: relayHttpUrl));
    }

    // Parameters if any discovered
    if (capabilities.parameters.isNotEmpty) {
      widgets.add(ParameterList(parameters: capabilities.parameters));
    }

    // Announcement presets editor
    widgets.add(_buildAnnouncementsSection());

    // Discovery summary (collapsible)
    widgets.add(_buildDiscoverySummary());

    return widgets;
  }

  Widget _buildAnnouncementsSection() {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        title: const Text('Announcements'),
        leading: const Icon(Icons.campaign),
        subtitle: const Text('Configure blocked path and custom announcements'),
        children: [
          const SizedBox(
            height: 350,
            child: AnnouncementPresetsEditor(),
          ),
        ],
      ),
    );
  }

  Widget _buildTourSection(List<String> waypoints) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        title: const Text('Tour Mode'),
        leading: const Icon(Icons.tour),
        subtitle: const Text('Create guided tours with waypoint sequences'),
        initiallyExpanded: true,  // Start expanded for debugging
        children: [
          SizedBox(
            height: 400,
            child: TourEditor(availableWaypoints: waypoints),
          ),
        ],
      ),
    );
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
