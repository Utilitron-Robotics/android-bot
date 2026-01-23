import '../core/rosbridge_client.dart';

/// Discovered topic info
class TopicInfo {
  final String name;
  final String type;

  TopicInfo(this.name, this.type);

  @override
  String toString() => '$name ($type)';

  Map<String, dynamic> toJson() => {'name': name, 'type': type};
}

/// Discovered service info
class ServiceInfo {
  final String name;
  final String type;

  ServiceInfo(this.name, this.type);

  @override
  String toString() => '$name ($type)';

  Map<String, dynamic> toJson() => {'name': name, 'type': type};
}

/// All discovered robot capabilities
class RobotCapabilities {
  final List<TopicInfo> topics;
  final List<ServiceInfo> services;
  final List<String> parameters;
  final List<String> waypoints;

  RobotCapabilities({
    required this.topics,
    required this.services,
    required this.parameters,
    required this.waypoints,
  });

  Map<String, dynamic> toJson() => {
        'topics': topics.map((t) => t.toJson()).toList(),
        'services': services.map((s) => s.toJson()).toList(),
        'parameters': parameters,
        'waypoints': waypoints,
        'features': {
          'navigation': hasNavigation,
          'velocity_control': hasVelocityControl,
          'status': hasStatus,
          'battery': hasBattery,
          'map': hasMap,
        }
      };

  // Feature detection helpers
  bool get hasNavigation => services.any((s) => s.name == '/poi');
  bool get hasVelocityControl => topics.any((t) => t.name.contains('cmd_vel'));
  bool get hasStatus => topics.any((t) => t.name == '/robot_status');
  bool get hasBattery => topics.any((t) => t.name.contains('sensors/core'));
  bool get hasMap => topics.any((t) => t.name.contains('/map'));

  @override
  String toString() {
    return 'Capabilities:\n'
        '  Topics: ${topics.length}\n'
        '  Services: ${services.length}\n'
        '  Parameters: ${parameters.length}\n'
        '  Waypoints: ${waypoints.length}';
  }
}

/// Introspects a rosbridge-connected robot to discover its capabilities
class RobotIntrospection {
  final RosbridgeClient client;

  RobotIntrospection(this.client);

  /// Discover all robot capabilities
  Future<RobotCapabilities> discover() async {
    print('RobotIntrospection: Starting discovery...');
    final results = await Future.wait([
      _discoverTopics(),
      _discoverServices(),
      _discoverParameters(),
      _discoverWaypoints(),
    ]);

    final caps = RobotCapabilities(
      topics: results[0] as List<TopicInfo>,
      services: results[1] as List<ServiceInfo>,
      parameters: results[2] as List<String>,
      waypoints: results[3] as List<String>,
    );
    print('RobotIntrospection: Discovery complete - ${caps.topics.length} topics, ${caps.services.length} services, ${caps.parameters.length} params, ${caps.waypoints.length} waypoints');
    return caps;
  }

  Future<List<TopicInfo>> _discoverTopics() async {
    try {
      // Get topic names
      final topicsResult = await client.callService(
        service: '/rosapi/topics',
        timeout: const Duration(seconds: 5),
      );

      final topicNames =
          (topicsResult['values']?['topics'] as List?)?.cast<String>() ?? [];

      // Get topic types
      final typesResult = await client.callService(
        service: '/rosapi/topics_types',
        timeout: const Duration(seconds: 5),
      );

      final topicTypes =
          (typesResult['values']?['types'] as List?)?.cast<String>() ?? [];

      // Combine into TopicInfo list
      final topics = <TopicInfo>[];
      for (var i = 0; i < topicNames.length; i++) {
        final type = i < topicTypes.length ? topicTypes[i] : 'unknown';
        topics.add(TopicInfo(topicNames[i], type));
      }

      return topics;
    } catch (e) {
      // rosapi might not be available, try alternative discovery
      return _discoverTopicsAlternative();
    }
  }

  Future<List<TopicInfo>> _discoverTopicsAlternative() async {
    // Common Pudu robot topics - fallback if rosapi unavailable
    return [
      TopicInfo('/robot_status', 'yutong_assistance/RobotStatus'),
      TopicInfo('/cmd_vel', 'geometry_msgs/Twist'),
      TopicInfo('/mobile_base/sensors/core', 'kobuki_msgs/SensorState'),
      TopicInfo('/move_base/cancel', 'actionlib_msgs/GoalID'),
      TopicInfo('/map', 'nav_msgs/OccupancyGrid'),
    ];
  }

  Future<List<ServiceInfo>> _discoverServices() async {
    try {
      final result = await client.callService(
        service: '/rosapi/services',
        timeout: const Duration(seconds: 5),
      );

      final serviceNames =
          (result['values']?['services'] as List?)?.cast<String>() ?? [];

      // For now, return without types (would need separate calls)
      return serviceNames.map((s) => ServiceInfo(s, 'unknown')).toList();
    } catch (e) {
      // Fallback common services
      return [
        ServiceInfo('/poi', 'pudu_msgs/POI'),
        ServiceInfo('/get_poi_list', 'pudu_msgs/GetPOIList'),
      ];
    }
  }

  Future<List<String>> _discoverParameters() async {
    try {
      final result = await client.callService(
        service: '/rosapi/get_param_names',
        timeout: const Duration(seconds: 5),
      );

      return (result['values']?['names'] as List?)?.cast<String>() ?? [];
    } catch (e) {
      return [];
    }
  }

  Future<List<String>> _discoverWaypoints() async {
    print('RobotIntrospection: Discovering waypoints via /poi service...');
    try {
      // Chassis protocol: call /poi with empty string to get available waypoints
      final result = await client.callService(
        service: '/poi',
        args: {'poi': ''},
        timeout: const Duration(seconds: 5),
      );
      print('RobotIntrospection: /poi response: $result');

      // Response has avaliable_list (note: typo in API is intentional)
      final pois = result['values']?['avaliable_list'] as List?;
      if (pois != null && pois.isNotEmpty) {
        print('RobotIntrospection: Found ${pois.length} waypoints');
        return pois.map((p) => p.toString()).toList();
      }
      print('RobotIntrospection: No waypoints in response');
    } catch (e) {
      print('RobotIntrospection: Waypoint discovery failed: $e');
    }

    // Return empty - user can configure manually
    return [];
  }
}
