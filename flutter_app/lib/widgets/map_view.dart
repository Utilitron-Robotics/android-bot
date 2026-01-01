import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/robot_connection.dart';

/// Real-time map visualization from /map topic
class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  StreamSubscription? _mapSubscription;
  ui.Image? _mapImage;
  MapInfo? _mapInfo;
  bool _isLoading = true;
  bool _subscribed = false;
  String? _error;
  Timer? _timeoutTimer;

  // Robot pose on map
  double _robotX = 0;
  double _robotY = 0;
  double _robotTheta = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _subscribeToMap();
    });
  }

  @override
  void dispose() {
    _mapSubscription?.cancel();
    _timeoutTimer?.cancel();
    _mapImage?.dispose();
    super.dispose();
  }

  void _subscribeToMap() {
    final robot = context.read<RobotConnection>();
    if (!robot.isConnected) {
      setState(() {
        _error = 'Not connected';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _subscribed = false;
      _error = null;
    });

    // Subscribe to map topic with throttle to avoid flooding
    robot.client.send({
      'op': 'subscribe',
      'topic': '/map',
      'type': 'nav_msgs/OccupancyGrid',
      'throttle_rate': 5000, // Only get map updates every 5 seconds
      'queue_length': 1,
    });

    // Subscribe to robot pose for showing position on map
    robot.client.subscribe(
      topic: '/robot_pose',
      type: 'geometry_msgs/Pose2D',
    );

    _mapSubscription?.cancel();
    _mapSubscription = robot.client.messages.listen((msg) {
      final topic = msg['topic'] as String?;
      if (topic == '/map') {
        _handleMapMessage(msg['msg']);
      } else if (topic == '/robot_pose') {
        _handlePoseMessage(msg['msg']);
      }
    });

    setState(() => _subscribed = true);

    // Set timeout - stop spinner after 8 seconds if no data
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && _isLoading && _mapImage == null) {
        setState(() => _isLoading = false);
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
          _mapImage?.dispose();
          _mapImage = image;
          _isLoading = false;
          _error = null;
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
    setState(() {
      _robotX = (data['x'] as num?)?.toDouble() ?? 0;
      _robotY = (data['y'] as num?)?.toDouble() ?? 0;
      _robotTheta = (data['theta'] as num?)?.toDouble() ?? 0;
    });
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.map),
                const SizedBox(width: 8),
                Text(
                  'Map',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                if (_mapInfo != null)
                  Text(
                    '${_mapInfo!.width}x${_mapInfo!.height}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _subscribeToMap,
                  tooltip: 'Refresh map',
                ),
              ],
            ),
            const SizedBox(height: 8),
            AspectRatio(
              aspectRatio: 1.0,
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
            if (_mapInfo != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Resolution: ${_mapInfo!.resolution.toStringAsFixed(3)}m/px • '
                  'Robot: (${_robotX.toStringAsFixed(1)}, ${_robotY.toStringAsFixed(1)})',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
                ),
              ),
          ],
        ),
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
