import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
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
  StreamSubscription? _mapSubscription;
  StreamSubscription? _wsStateSubscription;
  ui.Image? _mapImage;
  MapInfo? _mapInfo;
  bool _isLoading = false; // Start false - use cached data if available
  bool _subscribed = false;
  String? _error;
  Timer? _timeoutTimer;
  RobotConnection? _robot;
  bool _lastKnownConnected = false;
  WsConnectionState? _lastWsState;

  // Robot pose on map
  double _robotX = 0;
  double _robotY = 0;
  double _robotTheta = 0;

  @override
  void initState() {
    super.initState();
    debugPrint('MapView: initState called - new widget instance created');

    // CRITICAL: Restore from static cache IMMEDIATELY to prevent "loading" flash
    // This is the fix for map going to loading after waypoint navigation
    if (_MapCache.image != null) {
      debugPrint('MapView: Restoring map from static cache!');
      _mapImage = _MapCache.image;
      _mapInfo = _MapCache.info;
      _robotX = _MapCache.robotX;
      _robotY = _MapCache.robotY;
      _robotTheta = _MapCache.robotTheta;
      _isLoading = false;  // We have cached data, no loading needed
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('MapView: postFrameCallback - setting up subscriptions');
      _robot = context.read<RobotConnection>();
      _lastKnownConnected = _robot?.isConnected ?? false;
      _lastWsState = _robot?.client.state;
      _subscribeToMap();

      // Listen for RobotConnection changes (for high-level state)
      _robot?.addListener(_onConnectionChanged);

      // CRITICAL: Also listen to WebSocket state stream to detect reconnections
      // When rosbridge reconnects, it creates NEW stream controllers, so we must
      // re-subscribe to the new message stream
      _wsStateSubscription = _robot?.client.connectionState.listen(_onWsStateChanged);
    });
  }

  /// Handle WebSocket connection state changes (detect reconnection)
  void _onWsStateChanged(WsConnectionState newState) {
    debugPrint('MapView: WS state changed: $_lastWsState -> $newState');

    final wasConnected = _lastWsState == WsConnectionState.connected;
    final isNowConnected = newState == WsConnectionState.connected;

    // Detect reconnection: was connected -> lost connection -> connected again
    if (isNowConnected && !wasConnected && _lastWsState != null) {
      debugPrint('MapView: WebSocket reconnected, re-subscribing to map stream');
      // Force re-subscription since the stream controller was recreated
      _subscribed = false;
      _mapSubscription?.cancel();
      _mapSubscription = null;
      _subscribeToMap();
    } else if (isNowConnected && _lastWsState == null) {
      // First connection - subscribe if not already
      debugPrint('MapView: First connection detected, subscribing');
      if (!_subscribed) {
        _subscribeToMap();
      }
    }

    _lastWsState = newState;
  }

  void _onConnectionChanged() {
    final robot = _robot;
    if (robot == null) return;

    final isConnected = robot.isConnected;

    // Only react when connection state actually changes
    if (isConnected == _lastKnownConnected) return;

    if (isConnected && !_lastKnownConnected) {
      debugPrint('MapView: Connection restored, re-subscribing to map');
      _subscribed = false;  // Reset so we can re-subscribe
      _subscribeToMap();
    } else if (!isConnected && _lastKnownConnected) {
      debugPrint('MapView: Connection lost');
      // Don't clear the map image - keep showing last known state
      // Just mark as not subscribed so we re-subscribe on reconnect
      if (mounted) {
        setState(() {
          _subscribed = false;
        });
      }
    }
    _lastKnownConnected = isConnected;
  }

  @override
  void dispose() {
    debugPrint('MapView: DISPOSE called! Widget is being destroyed.');
    _robot?.removeListener(_onConnectionChanged);
    _wsStateSubscription?.cancel();
    _mapSubscription?.cancel();
    _timeoutTimer?.cancel();
    // CRITICAL: Do NOT dispose the image if it's in the static cache!
    // The cache survives widget recreation, so disposing would break the cached image.
    // Only dispose if this is a different image than what's cached.
    if (_mapImage != null && _mapImage != _MapCache.image) {
      debugPrint('MapView: Disposing non-cached image');
      _mapImage?.dispose();
    }
    super.dispose();
  }

  void _subscribeToMap() {
    final robot = _robot ?? context.read<RobotConnection>();
    if (!robot.isConnected) {
      // Only update state if we don't have a map - keep showing last known map
      if (_mapImage == null) {
        setState(() {
          _error = 'Not connected';
          _isLoading = false;
          _subscribed = false;
        });
      }
      return;
    }

    // If already subscribed with an active listener, don't re-subscribe
    if (_subscribed && _mapSubscription != null) {
      debugPrint('MapView: Already subscribed, skipping');
      return;
    }

    debugPrint('MapView: Subscribing to map topics');

    // Cancel any existing subscription first (important for reconnection!)
    _mapSubscription?.cancel();
    _mapSubscription = null;

    // Only show loading if we don't have a map image yet
    if (_mapImage == null) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    // The relay now subscribes to /map itself, so we just need to listen.
    // For direct connection mode, send subscribe to ensure map is flowing.
    robot.client.send({
      'op': 'subscribe',
      'topic': '/map',
      'type': 'nav_msgs/OccupancyGrid',
      'throttle_rate': 5000, // Only get map updates every 5 seconds
      'queue_length': 1,
    });
    debugPrint('MapView: Sent /map subscribe');

    // Subscribe to robot pose for showing position on map
    robot.client.subscribe(
      topic: '/robot_pose',
      type: 'geometry_msgs/Pose2D',
    );

    // Create NEW subscription to the current message stream FIRST
    // This ensures we're listening before any messages arrive
    var msgCount = 0;
    var mapMsgCount = 0;
    final topicCounts = <String, int>{};

    _mapSubscription = robot.client.messages.listen((msg) {
      msgCount++;
      final topic = msg['topic'] as String?;

      // Track topic counts for debugging
      if (topic != null) {
        topicCounts[topic] = (topicCounts[topic] ?? 0) + 1;
      }

      if (topic == '/map') {
        mapMsgCount++;
        debugPrint('MapView: Received /map message #$mapMsgCount (total msgs: $msgCount)');
        _handleMapMessage(msg['msg']);
      } else if (topic == '/robot_pose') {
        _handlePoseMessage(msg['msg']);
      }
      // Log every 50 messages to show stream is alive and what topics we're getting
      if (msgCount % 50 == 0) {
        debugPrint('MapView: Stream alive, $msgCount msgs, /map count: $mapMsgCount, topics: $topicCounts');
      }
    }, onError: (e) {
      debugPrint('MapView: Stream error: $e');
      if (mounted) {
        setState(() {
          _subscribed = false;
          // Only show error if we don't have a map - keep showing last valid map
          if (_mapImage == null) {
            _error = 'Stream error';
          }
        });
      }
    }, onDone: () {
      debugPrint('MapView: Stream closed (will re-subscribe on reconnect)');
      if (mounted) {
        setState(() {
          _subscribed = false;
          // Clear error on stream close - we'll get a new stream on reconnect
          // but keep showing any existing map
          if (_mapImage == null) {
            _error = null;
            _isLoading = false;
          }
        });
      }
    });

    setState(() => _subscribed = true);

    // Set timeout - stop spinner after 8 seconds if no data
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && _isLoading && _mapImage == null) {
        debugPrint('MapView: Timeout - no map data received in 8 seconds');
        setState(() => _isLoading = false);
      }
    });

    debugPrint('MapView: Listener set up, waiting for /map messages');
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
                onPressed: _subscribeToMap,
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
              _subscribed ? 'Subscribed to /map - waiting for data...' : 'Not subscribed',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 4),
            const Text(
              'Robot may not be publishing map',
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
