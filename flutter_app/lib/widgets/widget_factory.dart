import 'package:flutter/material.dart';
import '../services/robot_introspection.dart';
import 'status_panel.dart';
import 'waypoint_grid.dart';
import 'joystick.dart';
import 'parameter_list.dart';
import 'voice_control.dart';
import 'map_view.dart';
import 'tablet_control_panel.dart';
import 'sequence_editor.dart';
import 'mode_editor.dart';
import 'announcement_presets.dart';
import 'crowd_logic_settings.dart';

/// Dynamically generates UI widgets based on discovered robot capabilities
class WidgetFactory {
  final RobotCapabilities capabilities;
  final String?
      relayHttpUrl; // HTTP URL for tablet relay (e.g., http://192.168.1.100:8765)

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
      // Task modes editor (for waypoint arrival actions)
      widgets.add(_buildModeSection(capabilities.waypoints));
      // Tour mode editor
      widgets.add(_buildTourSection(capabilities.waypoints));
    }

    // Map view - collapsible, show before joystick for better UX
    widgets.add(_buildMapSection());

    // Joystick if velocity control available
    if (capabilities.hasVelocityControl) {
      widgets.add(const JoystickControl());
    }

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

  Widget _buildMapSection() {
    // Use a ValueKey to ensure this widget is stable across rebuilds
    // Without this, the Consumer in home_screen rebuilds this on every
    // robot status update, which destroys and recreates MapView
    return const Card(
      key: ValueKey('map_section'),
      margin: EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        key: ValueKey('map_expansion'),
        title: Text('Map'),
        leading: Icon(Icons.map),
        subtitle: Text('Real-time SLAM map view'),
        initiallyExpanded: true,
        children: [
          SizedBox(
            height: 432, // 20% taller (was 360)
            child: MapView(),
          ),
        ],
      ),
    );
  }

  Widget _buildAnnouncementsSection() {
    return const Card(
      key: ValueKey('announcements_section'),
      margin: EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        key: ValueKey('announcements_expansion'),
        title: Text('Crowd Logic & Announcements'),
        leading: Icon(Icons.campaign),
        subtitle: Text('Configure blocked path behavior and announcements'),
        children: [
          SizedBox(
            height: 500,
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  TabBar(
                    tabs: [
                      Tab(icon: Icon(Icons.people), text: 'Crowd Logic'),
                      Tab(icon: Icon(Icons.volume_up), text: 'Announcements'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        CrowdLogicSettings(),
                        AnnouncementPresetsEditor(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSection(List<String> waypoints) {
    return Card(
      key: const ValueKey('mode_section'),
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        key: const ValueKey('mode_expansion'),
        title: const Text('Task Modes'),
        leading: const Icon(Icons.auto_fix_high),
        subtitle: const Text('Define actions when robot arrives at waypoints'),
        initiallyExpanded: false,
        children: [
          SizedBox(
            height: 550,
            child: ModeEditor(availableWaypoints: waypoints),
          ),
        ],
      ),
    );
  }

  Widget _buildTourSection(List<String> waypoints) {
    return Card(
      key: const ValueKey('tour_section'),
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        key: const ValueKey('tour_expansion'),
        title: const Text('Tour Mode'),
        leading: const Icon(Icons.tour),
        subtitle: const Text('Create guided tours with waypoint sequences'),
        initiallyExpanded: false,
        children: [
          SizedBox(
            height: 600, // Increased height for better editing
            child: SequenceEditor(availableWaypoints: waypoints),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscoverySummary() {
    return ExpansionTile(
      key: const ValueKey('discovery_summary'),
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
