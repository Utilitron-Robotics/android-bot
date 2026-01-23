import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../core/robot_connection.dart';
import '../core/rosbridge_client.dart';
import '../models/occupancy_grid.dart' as model;

/// Real-time map visualization from /map topic
class MapView extends StatefulWidget {
  /// When true, renders map fullscreen with no chrome (for HUD background)
  final bool fullscreen;

  /// Callback when map info changes (for external overlay display)
  final void Function(MapInfo? info, double robotX, double robotY)? onMapUpdate;

  /// A real-time stream of map data from WebRTC. If provided, this will be used
  /// instead of the legacy HTTP polling or WebSocket subscriptions.
  final Stream<model.OccupancyGrid>? mapStream;

  const MapView({
    super.key,
    this.fullscreen = false,
    this.onMapUpdate,
    this.mapStream,
  });

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
  StreamSubscription? _mapStreamSubscription;
  ui.Image? _mapImage;
  MapInfo? _mapInfo;
  bool _isLoading = false;
  String? _error;
  Timer? _pollTimer;
  RobotConnection? _robot;
  bool _lastKnownConnected = false;
  WsConnectionState? _lastWsState;
  String? _httpBaseUrl;  // HTTP endpoint for map (e.g., http://192.168.1.100:8765)
  bool _refreshRequested = false;  // Track if we've already requested a refresh on 404

  // Robot pose on map
  double _robotX = 0;
  double _robotY = 0;
  double _robotTheta = 0;

  @override
  void initState() {
    super.initState();

    // Restore from static cache IMMEDIATELY to prevent "loading" flash
    if (_MapCache.image != null) {
      _mapImage = _MapCache.image;
      _mapInfo = _MapCache.info;
      _robotX = _MapCache.robotX;
      _robotY = _MapCache.robotY;
      _robotTheta = _MapCache.robotTheta;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final robot = context.read<RobotConnection>();
      if (widget.mapStream != null) {
        debugPrint('MapView: initState - Using WebRTC map stream.');
        _subscribeToWebRtcMapStream();
      } else {
        debugPrint('MapView: initState - Using legacy WebSocket/HTTP for map.');
        _robot = robot;
        _lastKnownConnected = _robot?.isConnected ?? false;
        _lastWsState = _robot?.client.state;
        _updateHttpBaseUrl();
        _startMapPolling();
        _robot?.addListener(_onConnectionChanged);
        _wsStateSubscription = _robot?.client.connectionState.listen(_onWsStateChanged);
      }
      
      // Always subscribe to pose, assuming it comes from a separate topic
      _subscribeToPose();
    });
  }

  void _subscribeToWebRtcMapStream() {
    _mapStreamSubscription?.cancel();
    _mapStreamSubscription = widget.mapStream!.listen((grid) {
      _handleMapMessage(grid);
    }, onError: (e) {
      debugPrint('MapView: Error from WebRTC map stream: $e');
      if (mounted) {
        setState(() {
          _error = 'Map stream error: $e';
        });
      }
    });
  }

  void _updateHttpBaseUrl() {
    // Derive HTTP API URL (port 8765) from robot connection info
    final robot = _robot;
    if (robot == null) {
      debugPrint('MapView: _updateHttpBaseUrl - robot is null!');
      return;
    }

    final robotUrl = robot.robotUrl;
    debugPrint('MapView: _updateHttpBaseUrl - robot.robotUrl = $robotUrl');

    if (robotUrl.isNotEmpty) {
      try {
        final uri = Uri.parse(robotUrl);
        String? host;

        if (uri.host.isNotEmpty) {
          // Full URL with scheme (e.g., ws://192.168.88.37:8766)
          if (uri.port == 9090) {
            // Direct robot connection - no HTTP map endpoint
            debugPrint('MapView: Direct robot connection (port 9090), HTTP map not available');
            _httpBaseUrl = null;
            return;
          }
          host = uri.host;
        } else {
          // Bare IP/hostname (e.g., "192.168.88.37") - relay is at this host
          host = robotUrl.trim();
        }

        if (host != null && host.isNotEmpty) {
          final newUrl = 'http://$host:8765';
          if (newUrl != _httpBaseUrl) {
            debugPrint('MapView: HTTP base URL: $newUrl');
          }
          _httpBaseUrl = newUrl;
        }
      } catch (e) {
        debugPrint('MapView: Failed to parse robot URL: $e');
      }
    } else {
      debugPrint('MapView: _updateHttpBaseUrl - robotUrl is empty!');
    }
  }

  void _onWsStateChanged(WsConnectionState newState) {
    debugPrint('MapView: WS state changed: $_lastWsState -> $newState');

    final wasConnected = _lastWsState == WsConnectionState.connected;
    final isNowConnected = newState == WsConnectionState.connected;

    if (isNowConnected && !wasConnected) {
      debugPrint('MapView: Connection restored, resubscribing to map');
      // CRITICAL: Update HTTP URL in case robot URL changed!
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
      _startMapPolling();
      _subscribeToPose();
    } else if (!isConnected && _lastKnownConnected) {
      debugPrint('MapView: Connection lost (HTTP map polling continues independently)');
      // DON'T cancel _pollTimer! HTTP polling is independent of WebSocket
      // The map can keep updating via HTTP even when WS drops
    }
    _lastKnownConnected = isConnected;
  }

  @override
  void dispose() {
    debugPrint('MapView: DISPOSE called');
    _mapStreamSubscription?.cancel();
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

  /// Fetch map via HTTP - single request/response, no subscription issues
  Future<void> _fetchMapViaHttp() async {
    if (_httpBaseUrl == null) return;

    // Don't gate on robot.isConnected - HTTP is independent of WebSocket state
    // The relay HTTP server runs regardless of WS connection

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
          _refreshRequested = false;  // Reset on success
        }
      } else if (response.statusCode == 404) {
        // No map cached yet - trigger a refresh to kickstart subscription
        if (!_refreshRequested) {
          debugPrint('MapView: No map cached on relay, requesting refresh...');
          _refreshRequested = true;
          http.post(Uri.parse('$_httpBaseUrl/map/refresh')).catchError((e) {
            debugPrint('MapView: Refresh request failed: $e');
          });
        }
      } else {
        debugPrint('MapView: HTTP map fetch failed: ${response.statusCode}');
      }
    } catch (e) {
      // Don't spam errors - just log once
      debugPrint('MapView: HTTP map fetch error: $e');
    }
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

    // Listen for map messages (also handles pose if already subscribed)
    _poseSubscription?.cancel();
    _poseSubscription = robot.client.messages.listen((msg) {
      final topic = msg['topic'] as String?;
      if (topic == '/map') {
        _handleMapMessage(msg['msg']);
      } else if (topic == '/robot_pose') {
        _handlePoseMessage(msg['msg']);
      }
    });

    debugPrint('MapView: Subscribed to /map via WebSocket');
  }

  /// Subscribe to robot pose via WebSocket
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
      debugPrint('MapView: Cannot refresh - no HTTP URL, trying WebSocket');
      _subscribeToMapViaWebSocket();
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

    MapInfo? newMapInfo;
    ui.Image? image;

    // Adapt to either legacy message (Map<String, dynamic>) or new model
    if (data is model.OccupancyGrid) {
      newMapInfo = MapInfo(
        width: data.info.width,
        height: data.info.height,
        resolution: data.info.resolution,
        originX: data.info.origin.position.x,
        originY: data.info.origin.position.y,
      );
      image = await _occupancyGridToImage(data.data, newMapInfo.width, newMapInfo.height);
    } else {
      // Legacy path - handle both raw occupancy grid and PNG-encoded data
      try {
        final mapData = data['data'];
        final info = data['info'] as Map<String, dynamic>?;

        if (mapData is String) {
          // PNG-encoded map data (from fragmented/compressed subscription)
          final pngBytes = base64Decode(mapData);
          final codec = await ui.instantiateImageCodec(Uint8List.fromList(pngBytes));
          final frame = await codec.getNextFrame();
          image = frame.image;

          // Extract map info if available
          if (info != null) {
            newMapInfo = MapInfo(
              width: info['width'] as int? ?? image.width,
              height: info['height'] as int? ?? image.height,
              resolution: (info['resolution'] as num?)?.toDouble() ?? 0.05,
              originX: (info['origin']?['position']?['x'] as num?)?.toDouble() ?? 0,
              originY: (info['origin']?['position']?['y'] as num?)?.toDouble() ?? 0,
            );
          } else {
            newMapInfo = MapInfo(
              width: image.width,
              height: image.height,
              resolution: 0.05,
              originX: 0,
              originY: 0,
            );
          }
        } else if (mapData is List) {
          // Raw occupancy grid data
          if (info == null) return;
          newMapInfo = MapInfo(
            width: info['width'] as int? ?? 0,
            height: info['height'] as int? ?? 0,
            resolution: (info['resolution'] as num?)?.toDouble() ?? 0.05,
            originX: (info['origin']?['position']?['x'] as num?)?.toDouble() ?? 0,
            originY: (info['origin']?['position']?['y'] as num?)?.toDouble() ?? 0,
          );
          final gridData = mapData.cast<int>();
          image = await _occupancyGridToImage(gridData, newMapInfo.width, newMapInfo.height);
        } else {
          debugPrint('MapView: Unknown map data type: ${mapData.runtimeType}');
          return;
        }
      } catch (e) {
        debugPrint('MapView: Map parse error: $e');
        if (mounted) setState(() => _error = 'Map parse error: $e');
        return;
      }
    }

    if (newMapInfo == null || image == null) return;
    if (newMapInfo.width == 0 || newMapInfo.height == 0) return;

    _mapInfo = newMapInfo;

    if (mounted) {
      final oldImage = _mapImage;
      setState(() {
        _mapImage = image;
        _isLoading = false;
        _error = null;
        _MapCache.image = image;
        _MapCache.info = _mapInfo;
      });
      if (oldImage != null && oldImage != image) {
        oldImage.dispose();
      }
    }
  }

  void _handlePoseMessage(dynamic data) async {
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

    // Notify external listeners (for HUD overlay)
    widget.onMapUpdate?.call(_mapInfo, _robotX, _robotY);
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
    // Fullscreen mode - just the map, no chrome (for HUD background)
    if (widget.fullscreen) {
      return _buildFullscreenMap();
    }

    // Regular mode with header and border (for widget_factory/home_screen)
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

  Widget _buildFullscreenMap() {
    return Container(
      color: const Color(0xFF0A0E14),
      child: _mapImage == null
          ? const SizedBox.expand()
          : CustomPaint(
              key: ValueKey(_mapImage.hashCode),
              painter: _MapPainter(
                mapImage: _mapImage!,
                mapInfo: _mapInfo!,
                robotX: _robotX,
                robotY: _robotY,
                robotTheta: _robotTheta,
                fillMode: true,
              ),
              size: Size.infinite,
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
      key: ValueKey(_mapImage.hashCode),
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
  final bool fillMode; // When true, centers map and fills available space

  _MapPainter({
    required this.mapImage,
    required this.mapInfo,
    required this.robotX,
    required this.robotY,
    required this.robotTheta,
    this.fillMode = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    double scale;
    double centerX = 0;
    double centerY = 0;
    double scaledWidth;
    double scaledHeight;

    if (fillMode) {
      // Contain mode: scale to fit entirely and center the map (no clipping)
      final scaleX = size.width / mapImage.width;
      final scaleY = size.height / mapImage.height;
      scale = scaleX < scaleY ? scaleX : scaleY; // Use SMALLER scale to contain

      // Calculate centered position
      scaledWidth = mapImage.width * scale;
      scaledHeight = mapImage.height * scale;
      centerX = (size.width - scaledWidth) / 2;
      centerY = (size.height - scaledHeight) / 2;
    } else {
      // Fit mode: scale to fit width
      scale = size.width / mapImage.width;
      scaledWidth = size.width;
      scaledHeight = mapImage.height * scale;
      centerX = 0;
      centerY = 0;
    }

    // Draw the map image, flipped vertically (ROS convention)
    // Translate to bottom of centered rect, then negative Y scale flips it upward
    canvas.save();
    canvas.translate(centerX, centerY + scaledHeight);
    canvas.scale(scale, -scale);
    canvas.drawImage(mapImage, Offset.zero, Paint());
    canvas.restore();

    // Draw robot position
    final robotPixelX = (robotX - mapInfo.originX) / mapInfo.resolution;
    final robotPixelY = (robotY - mapInfo.originY) / mapInfo.resolution;

    // Convert to screen coordinates (same transform as map)
    final screenX = centerX + (robotPixelX * scale);
    final screenY = (centerY + scaledHeight) - (robotPixelY * scale);

    // Draw robot as arrow
    canvas.save();
    canvas.translate(screenX, screenY);
    canvas.rotate(-robotTheta);

    // Robot body - slightly larger in fill mode
    final robotRadius = fillMode ? 10.0 : 8.0;
    canvas.drawCircle(
      Offset.zero,
      robotRadius,
      Paint()..color = Colors.blue,
    );
    canvas.drawCircle(
      Offset.zero,
      robotRadius,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Direction arrow
    final arrowScale = fillMode ? 1.2 : 1.0;
    final arrowPath = Path()
      ..moveTo(12 * arrowScale, 0)
      ..lineTo(-6 * arrowScale, 7 * arrowScale)
      ..lineTo(-6 * arrowScale, -7 * arrowScale)
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
        oldDelegate.robotTheta != robotTheta ||
        oldDelegate.fillMode != fillMode;
  }
}
