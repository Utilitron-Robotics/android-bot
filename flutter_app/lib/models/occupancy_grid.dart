// NOTE: This file is part of the new WebRTC map streaming implementation.

/// Represents a 2D occupancy grid map from the robot.
class OccupancyGrid {
  final MapInfo info;
  final List<int> data;

  OccupancyGrid({required this.info, required this.data});
}

/// Contains metadata about the map.
class MapInfo {
  final double resolution;
  final int width;
  final int height;
  final Pose origin;

  MapInfo({
    required this.resolution,
    required this.width,
    required this.height,
    required this.origin,
  });
}

/// Represents a 2D pose (position and orientation).
class Pose {
  final Point position;
  final Quaternion orientation;

  Pose({required this.position, required this.orientation});
}

class Point {
  final double x;
  final double y;
  final double z;

  Point({required this.x, required this.y, required this.z});
}

class Quaternion {
  final double x;
  final double y;
  final double z;
  final double w;

  Quaternion({required this.x, required this.y, required this.z, required this.w});
}
