import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../core/robot_connection.dart';
import '../core/rosbridge_client.dart';

/// Real-time map visualization from /map topic
class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  State<MapView> createState() => _MapViewState();
}

// Static cache for map data - survives widget recreation
class _MapCache {
  static ui.Image? image;
  static MapInfo? info;
  static double robotX = 0;
  static double robotY = 0;
  static double robotTheta = 0;
}

class _MapViewState extends State<MapView> {
  StreamSubscription? _poseSubscription;
  StreamSubscription? _wsStateSubscription;
  ui.Image? _mapImage;
  MapInfo? _mapInfo;
  bool _isLoading = false;
  String? _error;
  Timer? _pollTimer;
  RobotConnection? _robot;
  bool _lastKnownConnected = false;
  WsConnectionState? _lastWsState;
  String? _httpBaseUrl;  // HTTP endpoint for map (e.g., http://192.168.1.100:8765)

  // Robot pose on map
  double _robotX = 0;
  double _robotY = 0;
  double _robotTheta = 0;

  @override
  void initState() {
    super.initState();
    debugPrint('MapView: initState - using HTTP transport for map');

    // Restore from static cache IMMEDIATELY to prevent "loading" flash
    if (_MapCache.image != null) {
      debugPrint('MapView: Restoring map from static cache!');
      _mapImage = _MapCache.image;
      _mapInfo = _MapCache.info;
      _robotX = _MapCache.robotX;
      _robotY = _MapCache.robotY;
      _robotTheta = _MapCache.robotTheta;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _robot = context.read<RobotConnection>();
      _lastKnownConnected = _robot?.isConnected ?? false;
      _lastWsState = _robot?.client.state;

      // Extract HTTP base URL from WebSocket URL
      _updateHttpBaseUrl();

      // Start HTTP polling for map
      _startMapPolling();

      // Subscribe to robot pose via WebSocket (small messages, WS is fine)
      _subscribeToPose();

      _robot?.addListener(_onConnectionChanged);
      _wsStateSubscription = _robot?.client.connectionState.listen(_onWsStateChanged);
    });
  }

  void _updateHttpBaseUrl() {
    // Convert ws://host:port to http://host:(port-1) for HTTP API
    // WS is on 8766, HTTP is on 8765
    final robot = _robot;
    if (robot == null) return;

    // Get the URL from the connection
    final wsUrl = robot.robotUrl;
    if (wsUrl.isNotEmpty) {
      try {
        final uri = Uri.parse(wsUrl);
        // If connecting to relay WS (8766), HTTP is on 8765
        // If connecting direct to robot (9090), no HTTP map endpoint available
        if (uri.port == 8766) {
          _httpBaseUrl = 'http://${uri.host}:8765';
          debugPrint('MapView: HTTP base URL: $_httpBaseUrl');
        } else {
          debugPrint('MapView: Direct robot connection, HTTP map not available');
          _httpBaseUrl = null;
        }
      } catch (e) {
        debugPrint('MapView: Failed to parse WS URL: $e');
      }
    }
  }

  void _onWsStateChanged(WsConnectionState newState) {
    debugPrint('MapView: WS state changed: $_lastWsState -> $newState');

    final wasConnected = _lastWsState == WsConnectionState.connected;
    final isNowConnected = newState == WsConnectionState.connected;

    if (isNowConnected && !wasConnected) {
      debugPrint('MapView: Connection restored, restarting map polling');
      _updateHttpBaseUrl();
      _startMapPolling();
      _subscribeToPose();
    }

    _lastWsState = newState;
  }

  void _onConnectionChanged() {
    final robot = _robot;
    if (robot == null) return;

    final isConnected = robot.isConnected;
    if (isConnected == _lastKnownConnected) return;

    if (isConnected && !_lastKnownConnected) {
      debugPrint('MapView: Connection restored');
      _updateHttpBaseUrl();
      _startMapPolling();
      _subscribeToPose();
    } else if (!isConnected && _lastKnownConnected) {
      debugPrint('MapView: Connection lost');
      _pollTimer?.cancel();
    }
    _lastKnownConnected = isConnected;
  }

  @override
  void dispose() {
    debugPrint('MapView: DISPOSE called');
    _robot?.removeListener(_onConnectionChanged);
    _wsStateSubscription?.cancel();
    _poseSubscription?.cancel();
    _pollTimer?.cancel();
    if (_mapImage != null && _mapImage != _MapCache.image) {
      _mapImage?.dispose();
    }
    super.dispose();
  }

  /// Start HTTP polling for map data - much more reliable than WebSocket for large payloads
  void _startMapPolling() {
    _pollTimer?.cancel();

    if (_httpBaseUrl == null) {
      debugPrint('MapView: No HTTP base URL, falling back to WebSocket subscription');
      _subscribeToMapViaWebSocket();
      return;
    }

    // Fetch map immediately
    _fetchMapViaHttp();

    // Then poll every 5 seconds (matches the robot's /map throttle rate)
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _fetchMapViaHttp();
    });

    debugPrint('MapView: Started HTTP map polling');
  }

  /// Fallback: Subscribe to map via WebSocket (for direct robot connections)
  void _subscribeToMapViaWebSocket() {
    final robot = _robot;
    if (robot == null || !robot.isConnected) return;

    robot.client.send({
      'op': 'subscribe',
      'topic': '/map',
      'type': 'nav_msgs/OccupancyGrid',
      'throttle_rate': 5000,
      'queue_length': 1,
    });

    // Listen for map messages
    _poseSubscription?.cancel();
    _poseSubscription = robot.client.messages.listen((msg) {
      final topic = msg['topic'] as String?;
      if (topic == '/map') {
        _handleMapMessage(msg['msg']);
      } else if (topic == '/robot_pose') {
        _handlePoseMessage(msg['msg']);
      }
    });

    debugPrint('MapView: Subscribed to /map via WebSocket (fallback mode)');
  }

  /// Fetch map via HTTP - single request/response, no subscription issues
  Future<void> _fetchMapViaHttp() async {
    if (_httpBaseUrl == null) return;

    final robot = _robot;
    if (robot == null || !robot.isConnected) return;

    try {
      final response = await http.get(
        Uri.parse('$_httpBaseUrl/map'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        // The response is the raw rosbridge message: {topic: "/map", msg: {...}}
        final msg = data['msg'];
        if (msg != null) {
          _handleMapMessage(msg);
        }
      } else if (response.statusCode == 404) {
        // No map cached yet - this is normal on startup
        debugPrint('MapView: No map cached on relay yet');
      } else {
        debugPrint('MapView: HTTP map fetch failed: ${response.statusCode}');
      }
    } catch (e) {
      // Don't spam errors - just log once
      debugPrint('MapView: HTTP map fetch error: $e');
    }
  }

  /// Subscribe to robot pose via WebSocket (small messages, WS is fine for this)
  void _subscribeToPose() {
    final robot = _robot;
    if (robot == null || !robot.isConnected) return;

    _poseSubscription?.cancel();

    robot.client.subscribe(
      topic: '/robot_pose',
      type: 'geometry_msgs/Pose2D',
    );

    _poseSubscription = robot.client.messages.listen((msg) {
      final topic = msg['topic'] as String?;
      if (topic == '/robot_pose') {
        _handlePoseMessage(msg['msg']);
      }
    });

    debugPrint('MapView: Subscribed to robot pose');
  }

  /// Force a map refresh via HTTP
  void _forceMapRefresh() {
    if (_httpBaseUrl == null) {
      debugPrint('MapView: Cannot refresh - no HTTP URL');
      return;
    }

    debugPrint('MapView: Force refresh triggered');

    setState(() {
      _isLoading = true;
      _error = null;
    });

    // Tell relay to refresh its map subscription
    http.post(Uri.parse('$_httpBaseUrl/map/refresh')).then((_) {
      // Wait a bit for the relay to get fresh map, then fetch
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          _fetchMapViaHttp();
        }
      });
    }).catchError((e) {
      debugPrint('MapView: Refresh request failed: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Refresh failed';
        });
      }
    });
  }

  void _handleMapMessage(dynamic data) async {
    if (data == null) return;

    try {
      final info = data['info'] as Map<String, dynamic>?;
      final mapData = data['data'] as List?;

      if (info == null || mapData == null) return;

      final width = info['width'] as int? ?? 0;
      final height = info['height'] as int? ?? 0;
      final resolution = (info['resolution'] as num?)?.toDouble() ?? 0.05;
      final originX = (info['origin']?['position']?['x'] as num?)?.toDouble() ?? 0;
      final originY = (info['origin']?['position']?['y'] as num?)?.toDouble() ?? 0;

      if (width == 0 || height == 0) return;

      _mapInfo = MapInfo(
        width: width,
        height: height,
        resolution: resolution,
        originX: originX,
        originY: originY,
      );

      // Convert occupancy grid to image
      final image = await _occupancyGridToImage(
        mapData.cast<int>(),
        width,
        height,
      );

      if (mounted) {
        setState(() {
          // Don't dispose old image if it's the cached one
          if (_mapImage != _MapCache.image) {
            _mapImage?.dispose();
          }
          _mapImage = image;
          _mapInfo = _mapInfo;  // Already set above
          _isLoading = false;
          _error = null;

          // CRITICAL: Update static cache so map survives widget recreation
          _MapCache.image = image;
          _MapCache.info = _mapInfo;
          debugPrint('MapView: Updated static cache with new map');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Map parse error: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _handlePoseMessage(dynamic data) {
    if (data == null) return;
    final x = (data['x'] as num?)?.toDouble() ?? 0;
    final y = (data['y'] as num?)?.toDouble() ?? 0;
    final theta = (data['theta'] as num?)?.toDouble() ?? 0;

    setState(() {
      _robotX = x;
      _robotY = y;
      _robotTheta = theta;
    });

    // Update static cache for robot position too
    _MapCache.robotX = x;
    _MapCache.robotY = y;
    _MapCache.robotTheta = theta;
  }

  Future<ui.Image> _occupancyGridToImage(List<int> data, int width, int height) async {
    // Convert occupancy grid values to RGBA pixels
    // -1 = unknown (gray), 0 = free (white), 100 = occupied (black)
    final pixels = Uint8List(width * height * 4);

    for (var i = 0; i < data.length; i++) {
      final value = data[i];
      final pixelIndex = i * 4;

      int gray;
      if (value == -1) {
        gray = 128; // Unknown = gray
      } else if (value == 0) {
        gray = 255; // Free = white
      } else {
        gray = 0; // Occupied = black
      }

      pixels[pixelIndex] = gray;     // R
      pixels[pixelIndex + 1] = gray; // G
      pixels[pixelIndex + 2] = gray; // B
      pixels[pixelIndex + 3] = 255;  // A
    }

    // Create image from pixels
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      width,
      height,
      ui.PixelFormat.rgba8888,
      (image) => completer.complete(image),
    );

    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    // Simplified layout - parent (widget_factory) provides Card/ExpansionTile wrapper
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          // Compact header with info and refresh
          Row(
            children: [
              if (_mapInfo != null)
                Text(
                  '${_mapInfo!.width}x${_mapInfo!.height} • ${_mapInfo!.resolution.toStringAsFixed(3)}m/px',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const Spacer(),
              if (_mapInfo != null)
                Text(
                  'Robot: (${_robotX.toStringAsFixed(1)}, ${_robotY.toStringAsFixed(1)})',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _forceMapRefresh,
                tooltip: 'Refresh map',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Map fills remaining space
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade700),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _buildMapContent(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 8),
            Text('Loading map...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ),
      );
    }

    if (_mapImage == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, size: 48, color: Colors.grey.shade600),
            const SizedBox(height: 8),
            const Text('No map data'),
            Text(
              _httpBaseUrl != null ? 'Polling via HTTP...' : 'Not connected',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tap refresh or wait for map data',
              style: TextStyle(color: Colors.grey, fontSize: 11),
            ),
          ],
        ),
      );
    }

    return CustomPaint(
      painter: _MapPainter(
        mapImage: _mapImage!,
        mapInfo: _mapInfo!,
        robotX: _robotX,
        robotY: _robotY,
        robotTheta: _robotTheta,
      ),
      size: Size.infinite,
    );
  }
}

class MapInfo {
  final int width;
  final int height;
  final double resolution;
  final double originX;
  final double originY;

  MapInfo({
    required this.width,
    required this.height,
    required this.resolution,
    required this.originX,
    required this.originY,
  });
}

class _MapPainter extends CustomPainter {
  final ui.Image mapImage;
  final MapInfo mapInfo;
  final double robotX;
  final double robotY;
  final double robotTheta;

  _MapPainter({
    required this.mapImage,
    required this.mapInfo,
    required this.robotX,
    required this.robotY,
    required this.robotTheta,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw the map image, flipped vertically (ROS convention)
    final scale = size.width / mapImage.width;

    canvas.save();
    canvas.translate(0, size.height);
    canvas.scale(scale, -scale);
    canvas.drawImage(mapImage, Offset.zero, Paint());
    canvas.restore();

    // Draw robot position
    final robotPixelX = (robotX - mapInfo.originX) / mapInfo.resolution;
    final robotPixelY = (robotY - mapInfo.originY) / mapInfo.resolution;

    // Convert to screen coordinates
    final screenX = robotPixelX * scale;
    final screenY = size.height - (robotPixelY * scale);

    // Draw robot as arrow
    canvas.save();
    canvas.translate(screenX, screenY);
    canvas.rotate(-robotTheta);

    // Robot body
    canvas.drawCircle(
      Offset.zero,
      8,
      Paint()..color = Colors.blue,
    );
    canvas.drawCircle(
      Offset.zero,
      8,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Direction arrow
    final arrowPath = Path()
      ..moveTo(10, 0)
      ..lineTo(-5, 6)
      ..lineTo(-5, -6)
      ..close();
    canvas.drawPath(
      arrowPath,
      Paint()..color = Colors.blue.shade700,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) {
    return oldDelegate.mapImage != mapImage ||
        oldDelegate.robotX != robotX ||
        oldDelegate.robotY != robotY ||
        oldDelegate.robotTheta != robotTheta;
  }
}
