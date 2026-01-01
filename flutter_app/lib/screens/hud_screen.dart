import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/robot_connection.dart';
import '../core/tour_mode.dart' show TourManager, TourStatus;
import '../core/smait_protocol.dart' as protocol;
import '../widgets/map_view.dart';
import '../widgets/joystick.dart';
import '../widgets/tour_editor.dart';
import '../widgets/voice_control.dart';
import '../widgets/fleet_picker.dart';

/// HUD-style cockpit layout for landscape tablet control
/// Inspired by spaceship cockpit / video game HUD design
class HudScreen extends StatefulWidget {
  const HudScreen({super.key});

  @override
  State<HudScreen> createState() => _HudScreenState();
}

class _HudScreenState extends State<HudScreen> with TickerProviderStateMixin {
  final _urlController = TextEditingController();

  // Edge panel states
  bool _leftPanelExpanded = true;
  bool _rightPanelExpanded = true;
  bool _bottomPanelExpanded = false;

  // Left panel tab (0 = waypoints, 1 = tour)
  int _leftPanelTab = 0;

  // Animation controllers for smooth panel transitions
  late AnimationController _leftPanelController;
  late AnimationController _rightPanelController;
  late AnimationController _bottomPanelController;

  // Cyberpunk accent color
  static const _accentColor = Color(0xFF00D4FF); // Cyan glow
  static const _accentSecondary = Color(0xFF00FF88); // Green glow
  static const _dangerColor = Color(0xFFFF3366); // Red/Pink warning

  @override
  void initState() {
    super.initState();
    // Force landscape on tablets
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    _leftPanelController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
      value: 1.0,
    );
    _rightPanelController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
      value: 1.0,
    );
    _bottomPanelController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
      value: 0.0,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final robot = context.read<RobotConnection>();
      _urlController.text = robot.robotUrl;
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _leftPanelController.dispose();
    _rightPanelController.dispose();
    _bottomPanelController.dispose();
    // Restore orientation
    SystemChrome.setPreferredOrientations([]);
    super.dispose();
  }

  void _toggleLeftPanel() {
    setState(() => _leftPanelExpanded = !_leftPanelExpanded);
    if (_leftPanelExpanded) {
      _leftPanelController.forward();
    } else {
      _leftPanelController.reverse();
    }
  }

  void _toggleRightPanel() {
    setState(() => _rightPanelExpanded = !_rightPanelExpanded);
    if (_rightPanelExpanded) {
      _rightPanelController.forward();
    } else {
      _rightPanelController.reverse();
    }
  }

  void _toggleBottomPanel() {
    setState(() => _bottomPanelExpanded = !_bottomPanelExpanded);
    if (_bottomPanelExpanded) {
      _bottomPanelController.forward();
    } else {
      _bottomPanelController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E14), // Deep dark blue-black
      body: Consumer<RobotConnection>(
        builder: (context, robot, _) {
          // Check if tour is running to adjust layout
          final tourManager = context.watch<TourManager>();
          final tourRunning = tourManager.status == TourStatus.running;

          if (robot.state == RobotConnectionState.disconnected ||
              robot.state == RobotConnectionState.error) {
            return _buildConnectionScreen(robot);
          }

          if (robot.state == RobotConnectionState.connecting) {
            return _buildConnectingScreen();
          }

          // Main HUD layout - Map is FULL SCREEN background, panels float on top
          return Stack(
            children: [
              // === LAYER 0: Full-screen Map (BACKGROUND) ===
              const Positioned.fill(
                child: MapView(),
              ),

              // === LAYER 1: Corner brackets (HUD aesthetic) ===
              ..._buildCornerBrackets(),

              // === LAYER 2: Tour overlay when running ===
              if (tourRunning)
                Positioned(
                  top: 60,
                  left: _leftPanelExpanded ? 290 : 56,
                  right: _rightPanelExpanded ? 270 : 56,
                  child: _buildTourOverlay(tourManager),
                ),

              // === LAYER 3: Glass panels on top ===
              // Top Status Bar
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildTopStatusBar(robot),
              ),

              // Left Edge Panel (Waypoints / Tour)
              Positioned(
                top: 56,
                left: 0,
                bottom: 50,
                child: _buildLeftPanel(robot, tourRunning, tourManager),
              ),

              // Right Edge Panel (Joystick / Controls)
              Positioned(
                top: 56,
                right: 0,
                bottom: 50,
                child: _buildRightPanel(robot),
              ),

              // Bottom Quick Actions Bar
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildBottomBar(robot),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildConnectionScreen(RobotConnection robot) {
    return Center(
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: const Color(0xFF151A22),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _accentColor.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: _accentColor.withValues(alpha: 0.1),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              robot.state == RobotConnectionState.error
                  ? Icons.error_outline
                  : Icons.precision_manufacturing,
              size: 64,
              color: robot.state == RobotConnectionState.error
                  ? _dangerColor
                  : _accentColor,
            ),
            const SizedBox(height: 16),
            Text(
              robot.state == RobotConnectionState.error
                  ? 'CONNECTION FAILED'
                  : 'DROID CONTROLLER',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: robot.state == RobotConnectionState.error
                    ? _dangerColor
                    : _accentColor,
                letterSpacing: 2,
              ),
            ),
            if (robot.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                robot.errorMessage!,
                style: TextStyle(color: Colors.grey.shade400),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    decoration: InputDecoration(
                      labelText: 'Robot URL',
                      hintText: 'ws://10.42.0.1:9090',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: _accentColor.withValues(alpha: 0.3)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: _accentColor.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: _accentColor),
                      ),
                      prefixIcon: Icon(Icons.link, color: _accentColor),
                    ),
                    style: const TextStyle(fontFamily: 'monospace'),
                    onSubmitted: (_) => _connect(robot),
                  ),
                ),
                const SizedBox(width: 12),
                const FleetConnectButton(),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _connect(robot),
                icon: const Icon(Icons.power_settings_new),
                label: const Text('CONNECT'),
                style: FilledButton.styleFrom(
                  backgroundColor: _accentColor,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectingScreen() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 80,
            height: 80,
            child: CircularProgressIndicator(
              color: _accentColor,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'INITIALIZING LINK...',
            style: TextStyle(
              fontSize: 18,
              color: _accentColor,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Discovering robot capabilities',
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildMapArea(RobotConnection robot, bool tourRunning, TourManager tourManager) {
    return Container(
      margin: EdgeInsets.only(
        top: 60,
        bottom: 50,
        left: _leftPanelExpanded ? 280 : 48,
        right: _rightPanelExpanded ? 260 : 48,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        border: Border.all(
          color: _accentColor.withValues(alpha: 0.2),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Stack(
          children: [
            // Map view fills the area
            const Positioned.fill(
              child: MapView(),
            ),
            // Tour overlay when running
            if (tourRunning)
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: _buildTourOverlay(tourManager),
              ),
            // Subtle corner brackets for HUD feel
            ..._buildCornerBrackets(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCornerBrackets() {
    const bracketSize = 24.0;
    const bracketThickness = 2.0;
    final bracketColor = _accentColor.withValues(alpha: 0.4);

    Widget bracket(bool top, bool left) {
      return Positioned(
        top: top ? 8 : null,
        bottom: top ? null : 8,
        left: left ? 8 : null,
        right: left ? null : 8,
        child: CustomPaint(
          size: const Size(bracketSize, bracketSize),
          painter: _BracketPainter(
            color: bracketColor,
            thickness: bracketThickness,
            top: top,
            left: left,
          ),
        ),
      );
    }

    return [
      bracket(true, true),
      bracket(true, false),
      bracket(false, true),
      bracket(false, false),
    ];
  }

  Widget _buildTourOverlay(TourManager tourManager) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _accentSecondary.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.tour, color: _accentSecondary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'TOUR: ${tourManager.currentTour?.name ?? ""}',
                  style: TextStyle(
                    color: _accentSecondary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                Text(
                  '${tourManager.currentPhase.label} • Stop ${tourManager.currentStopIndex + 1}/${tourManager.currentTour?.stops.length ?? 0}',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                ),
              ],
            ),
          ),
          if (tourManager.countdownSeconds > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _accentSecondary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${tourManager.countdownSeconds}s',
                style: TextStyle(
                  color: _accentSecondary,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopStatusBar(RobotConnection robot) {
    final status = robot.status;

    return Container(
      height: 52,
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF151A22).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _accentColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          // Connection status
          _HudChip(
            icon: Icons.check_circle,
            label: robot.robotUrl.contains('10.42.0.1') ? 'DIRECT' : 'RELAY',
            color: _accentSecondary,
          ),
          const SizedBox(width: 12),

          // Battery
          _HudChip(
            icon: _batteryIcon(status.battery),
            label: '${status.battery.toStringAsFixed(0)}%',
            color: _batteryColor(status.battery),
          ),
          const SizedBox(width: 12),

          // Nav status
          _HudChip(
            icon: status.isMoving ? Icons.directions_walk : Icons.pause,
            label: status.navStatusText,
            color: status.isMoving ? _accentSecondary : Colors.grey,
          ),

          // E-stop warning
          if (status.hasEstop) ...[
            const SizedBox(width: 12),
            _HudChip(
              icon: Icons.emergency,
              label: status.hardEstop ? 'HARD STOP' : 'SOFT STOP',
              color: _dangerColor,
              pulse: true,
            ),
          ],

          // Stale data warning
          if (robot.isStale) ...[
            const SizedBox(width: 12),
            _HudChip(
              icon: Icons.warning_amber,
              label: 'DATA STALE',
              color: Colors.amber,
              pulse: true,
            ),
          ],

          const Spacer(),

          // Current goal
          if (status.currentGoal.isNotEmpty) ...[
            Icon(Icons.flag, size: 16, color: _accentColor),
            const SizedBox(width: 4),
            Text(
              status.currentGoal,
              style: TextStyle(color: _accentColor, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 16),
          ],

          // Disconnect button
          IconButton(
            icon: const Icon(Icons.power_settings_new),
            color: _dangerColor,
            tooltip: 'Disconnect',
            onPressed: robot.disconnect,
          ),
        ],
      ),
    );
  }

  Widget _buildLeftPanel(RobotConnection robot, bool tourRunning, TourManager tourManager) {
    final capabilities = robot.capabilities;
    final waypoints = capabilities?.waypoints ?? [];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: _leftPanelExpanded ? 280 : 48,
      child: Container(
        margin: const EdgeInsets.only(left: 4, top: 4, bottom: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF151A22).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _accentColor.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            // Panel toggle & tabs
            _buildLeftPanelHeader(),

            // Panel content
            if (_leftPanelExpanded)
              Expanded(
                child: _leftPanelTab == 0
                    ? _buildWaypointsContent(waypoints)
                    : _buildTourContent(waypoints, tourManager),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeftPanelHeader() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: _accentColor.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          // Collapse/expand button
          IconButton(
            icon: Icon(
              _leftPanelExpanded ? Icons.chevron_left : Icons.chevron_right,
              color: _accentColor,
            ),
            onPressed: _toggleLeftPanel,
            tooltip: _leftPanelExpanded ? 'Collapse' : 'Expand',
            iconSize: 20,
          ),
          if (_leftPanelExpanded) ...[
            const SizedBox(width: 4),
            // Tab buttons
            _PanelTabButton(
              icon: Icons.location_on,
              label: 'POI',
              selected: _leftPanelTab == 0,
              color: _accentColor,
              onTap: () => setState(() => _leftPanelTab = 0),
            ),
            const SizedBox(width: 4),
            _PanelTabButton(
              icon: Icons.tour,
              label: 'TOUR',
              selected: _leftPanelTab == 1,
              color: _accentSecondary,
              onTap: () => setState(() => _leftPanelTab = 1),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWaypointsContent(List<String> waypoints) {
    if (waypoints.isEmpty) {
      return Center(
        child: Text(
          'No waypoints',
          style: TextStyle(color: Colors.grey.shade500),
        ),
      );
    }

    return Column(
      children: [
        // Voice control
        Padding(
          padding: const EdgeInsets.all(8),
          child: VoiceControl(availableWaypoints: waypoints),
        ),
        Divider(color: _accentColor.withValues(alpha: 0.2), height: 1),
        // Waypoint list (compact)
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: waypoints.length,
            itemBuilder: (context, index) {
              final wp = waypoints[index];
              return _WaypointButton(
                name: wp,
                color: _accentColor,
                onTap: () => _navigateTo(wp),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTourContent(List<String> waypoints, TourManager tourManager) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: TourEditor(availableWaypoints: waypoints),
    );
  }

  Widget _buildRightPanel(RobotConnection robot) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: _rightPanelExpanded ? 260 : 48,
      child: Container(
        margin: const EdgeInsets.only(right: 4, top: 4, bottom: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF151A22).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _accentColor.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            // Panel toggle
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: _accentColor.withValues(alpha: 0.2)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_rightPanelExpanded)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        'MANUAL CONTROL',
                        style: TextStyle(
                          color: _accentColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  IconButton(
                    icon: Icon(
                      _rightPanelExpanded ? Icons.chevron_right : Icons.chevron_left,
                      color: _accentColor,
                    ),
                    onPressed: _toggleRightPanel,
                    tooltip: _rightPanelExpanded ? 'Collapse' : 'Expand',
                    iconSize: 20,
                  ),
                ],
              ),
            ),

            // Joystick
            if (_rightPanelExpanded)
              const Expanded(
                child: JoystickControl(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(RobotConnection robot) {
    return Container(
      height: 46,
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF151A22).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _accentColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          // Quick action buttons
          _QuickActionButton(
            icon: Icons.stop_circle,
            label: 'STOP',
            color: _dangerColor,
            onTap: () {
              debugPrint('HUD: STOP pressed');
              robot.sendVelocity(0, 0);
            },
          ),
          const SizedBox(width: 8),
          _QuickActionButton(
            icon: Icons.cancel,
            label: 'CANCEL NAV',
            color: Colors.orange,
            onTap: () {
              debugPrint('HUD: CANCEL NAV pressed');
              robot.cancelNavigation();
            },
          ),
          const SizedBox(width: 8),
          _QuickActionButton(
            icon: Icons.emergency,
            label: robot.status.softEstop ? 'RELEASE' : 'E-STOP',
            color: robot.status.softEstop ? _accentSecondary : _dangerColor,
            onTap: () {
              debugPrint('HUD: E-STOP pressed, current=${robot.status.softEstop}');
              // Advertise first, then publish
              robot.client.send(protocol.SmaitProtocol.advertiseSoftStop());
              Future.delayed(const Duration(milliseconds: 100), () {
                robot.client.send(protocol.SmaitProtocol.publishSoftStop(!robot.status.softEstop));
              });
            },
          ),

          const Spacer(),

          // Messages toggle
          IconButton(
            icon: const Icon(Icons.message_outlined),
            color: _bottomPanelExpanded ? _accentColor : Colors.grey,
            onPressed: _toggleBottomPanel,
            tooltip: 'Toggle message log',
          ),
        ],
      ),
    );
  }

  void _connect(RobotConnection robot) {
    var url = _urlController.text.trim();
    if (url.isEmpty) return;

    // Convert HTTP to WS for rosbridge
    if (url.startsWith('http://')) {
      final uri = Uri.tryParse(url);
      if (uri != null) {
        url = 'ws://${uri.host}:8766';
      }
    }
    robot.connect(url);
  }

  void _navigateTo(String waypoint) {
    debugPrint('HUD: Navigate to $waypoint');
    final robot = context.read<RobotConnection>();
    robot.client.callService(
      service: '/poi',
      args: {'poi': waypoint},
    );
  }

  IconData _batteryIcon(double level) {
    if (level > 80) return Icons.battery_full;
    if (level > 60) return Icons.battery_5_bar;
    if (level > 40) return Icons.battery_4_bar;
    if (level > 20) return Icons.battery_2_bar;
    return Icons.battery_alert;
  }

  Color _batteryColor(double level) {
    if (level > 50) return _accentSecondary;
    if (level > 20) return Colors.orange;
    return _dangerColor;
  }
}

/// HUD-style status chip
class _HudChip extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool pulse;

  const _HudChip({
    required this.icon,
    required this.label,
    required this.color,
    this.pulse = false,
  });

  @override
  State<_HudChip> createState() => _HudChipState();
}

class _HudChipState extends State<_HudChip> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    if (widget.pulse) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_HudChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.pulse && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: widget.color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(widget.icon, size: 14, color: widget.color),
          const SizedBox(width: 4),
          Text(
            widget.label,
            style: TextStyle(
              color: widget.color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );

    if (widget.pulse) {
      return AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return Opacity(
            opacity: 0.5 + (_pulseController.value * 0.5),
            child: content,
          );
        },
      );
    }

    return content;
  }
}

/// Panel tab button
class _PanelTabButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _PanelTabButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? color.withValues(alpha: 0.5) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: selected ? color : Colors.grey),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: selected ? color : Colors.grey,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact waypoint button for HUD
class _WaypointButton extends StatelessWidget {
  final String name;
  final Color color;
  final VoidCallback onTap;

  const _WaypointButton({
    required this.name,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: color.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Icon(Icons.location_on, size: 16, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(color: color, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.play_arrow, size: 18, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Quick action button for bottom bar
class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Corner bracket painter for HUD aesthetic
class _BracketPainter extends CustomPainter {
  final Color color;
  final double thickness;
  final bool top;
  final bool left;

  _BracketPainter({
    required this.color,
    required this.thickness,
    required this.top,
    required this.left,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    final path = Path();

    if (top && left) {
      path.moveTo(0, size.height);
      path.lineTo(0, 0);
      path.lineTo(size.width, 0);
    } else if (top && !left) {
      path.moveTo(size.width, size.height);
      path.lineTo(size.width, 0);
      path.lineTo(0, 0);
    } else if (!top && left) {
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(size.width, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BracketPainter oldDelegate) {
    return oldDelegate.color != color ||
           oldDelegate.thickness != thickness ||
           oldDelegate.top != top ||
           oldDelegate.left != left;
  }
}
