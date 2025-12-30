/// smAiT Upper Computer Communication Protocol for Flutter
/// Supports both direct robot connection and relay connection
library;

// Operation types
const String opAdvertise = 'advertise';
const String opPublish = 'publish';
const String opUnadvertise = 'unadvertise';
const String opSubscribe = 'subscribe';
const String opUnsubscribe = 'unsubscribe';
const String opCallService = 'call_service';
const String opServiceResponse = 'service_response';
const String opFragment = 'fragment';
const String opPng = 'png';

// Common topics
const String topicRobotPose = '/robot_pose';
const String topicRobotStatus = '/robot_status';
const String topicLaserData = '/laser_data';
const String topicGlobalPath = '/global_path';
const String topicMap = '/map';
const String topicNaviStatus = '/navi_status';
const String topicCmdVel = '/cmd_vel_mux/input/teleop';
const String topicCancelGoal = '/move_base/cancel';
const String topicSoftStop = '/soft_stop';
const String topicSensorsCore = '/mobile_base/sensors/core';

// Services
const String servicePoi = '/poi';
const String serviceNodeManager = '/node_manager_control';
const String serviceVelocityControl = '/velocity_control';
const String serviceRobotInfo = '/robot_info';
const String serviceGetMapInfo = '/get_map_info';

// Navigation status codes
const int navWaiting = 600;
const int navRunning = 601;
const int navCancelled = 602;
const int navSuccess = 603;
const int navFailed = 604;

// Control states
const int stateMapping = 20;
const int stateNavigation = 30;
const int stateError = 99;

// Speed modes
const int speedSafetyLow = 0;
const int speedSafetyMed = 1;
const int speedSafetyHigh = 2;
const int speedBalanceLow = 3;
const int speedBalanceMed = 4;
const int speedBalanceHigh = 5;
const int speedEfficiencyLow = 6;
const int speedEfficiencyMed = 7;
const int speedEfficiencyHigh = 8;
const int speedDefault = -1;
const int speedSmoothOn = 60;
const int speedSmoothOff = 61;
const int speedGetCurrent = 99;

/// smAiT Protocol message builder
class SmaitProtocol {
  // === Subscription Messages ===

  static Map<String, dynamic> subscribeRobotPose() => {
    'op': opSubscribe,
    'id': 'get_pose',
    'topic': topicRobotPose,
    'type': 'geometry_msgs/Pose2D',
  };

  static Map<String, dynamic> subscribeRobotStatus() => {
    'op': opSubscribe,
    'id': 'get_robot_status',
    'topic': topicRobotStatus,
    'type': 'yutong_assistance/RobotStatus',
  };

  static Map<String, dynamic> subscribeLaserData() => {
    'op': opSubscribe,
    'id': 'get_laser',
    'topic': topicLaserData,
    'type': 'yutong_assistance/point_array',
  };

  static Map<String, dynamic> subscribeNaviStatus() => {
    'op': opSubscribe,
    'id': 'get_navi_status',
    'topic': topicNaviStatus,
    'type': 'actionlib_msgs/GoalStatus',
  };

  static Map<String, dynamic> subscribeMap() => {
    'op': opSubscribe,
    'id': 'get_map',
    'topic': topicMap,
    'type': 'nav_msgs/OccupancyGrid',
    'fragment_size': 6000,
    'compression': 'png',
  };

  static Map<String, dynamic> subscribeSensorsCore() => {
    'op': opSubscribe,
    'id': 'get_sensors_core',
    'topic': topicSensorsCore,
    'type': 'kobuki_msgs/SensorState',
  };

  static Map<String, dynamic> unsubscribe(String topic, String id) => {
    'op': opUnsubscribe,
    'id': id,
    'topic': topic,
  };

  // === Publish Messages ===

  static Map<String, dynamic> advertiseVelocity() => {
    'op': opAdvertise,
    'id': 'velocity_control',
    'topic': topicCmdVel,
    'type': 'geometry_msgs/Twist',
  };

  static Map<String, dynamic> publishVelocity(double linearX, double angularZ) => {
    'op': opPublish,
    'id': 'velocity_control',
    'topic': topicCmdVel,
    'msg': {
      'linear': {'x': linearX, 'y': 0.0, 'z': 0.0},
      'angular': {'x': 0.0, 'y': 0.0, 'z': angularZ},
    },
  };

  static Map<String, dynamic> stopRobot() => publishVelocity(0.0, 0.0);

  static Map<String, dynamic> advertiseCancelGoal() => {
    'op': opAdvertise,
    'id': 'cancel_goal',
    'topic': topicCancelGoal,
    'type': 'actionlib_msgs/GoalID',
  };

  static Map<String, dynamic> publishCancelGoal() => {
    'op': opPublish,
    'id': 'cancel_goal',
    'topic': topicCancelGoal,
    'msg': {'stamp': '', 'id': ''},
  };

  static Map<String, dynamic> advertiseSoftStop() => {
    'op': opAdvertise,
    'id': 'set_estop',
    'topic': topicSoftStop,
    'type': 'std_msgs/Bool',
  };

  static Map<String, dynamic> publishSoftStop(bool enabled) => {
    'op': opPublish,
    'id': 'set_estop',
    'topic': topicSoftStop,
    'msg': {'data': enabled},
  };

  // === Service Calls ===

  static Map<String, dynamic> callNavigateToPoi(String poiName) => {
    'op': opCallService,
    'id': 'service_poi',
    'service': servicePoi,
    'args': {'poi': poiName},
  };

  static Map<String, dynamic> callGetRobotInfo() => {
    'op': opCallService,
    'id': 'service_robot_info',
    'service': serviceRobotInfo,
    'args': {'cmd': 0},
  };

  static Map<String, dynamic> callGetMapInfo() => {
    'op': opCallService,
    'id': 'service_get_map_info',
    'service': serviceGetMapInfo,
    'args': {'cmd': 0},
  };

  static Map<String, dynamic> callSetSpeedMode(int mode) => {
    'op': opCallService,
    'id': 'service_velocity_control',
    'service': serviceVelocityControl,
    'args': {'cmd': mode, 'str': ''},
  };

  static Map<String, dynamic> callNodeManagerControl({
    required String buildingName,
    required String floorNum,
    required int cmd,
    int args = 0,
  }) => {
    'op': opCallService,
    'id': 'service_node_manager_control',
    'service': serviceNodeManager,
    'args': {
      'building_name': buildingName,
      'floor_num': floorNum,
      'cmd': cmd,
      'args': args,
    },
  };
}

/// Robot pose data
class RobotPose {
  final double x;
  final double y;
  final double theta;

  RobotPose({this.x = 0, this.y = 0, this.theta = 0});

  factory RobotPose.fromJson(Map<String, dynamic> json) => RobotPose(
    x: (json['x'] as num?)?.toDouble() ?? 0,
    y: (json['y'] as num?)?.toDouble() ?? 0,
    theta: (json['theta'] as num?)?.toDouble() ?? 0,
  );

  double get thetaDegrees => theta * 180 / 3.14159;
}

/// Full robot status
class RobotStatusData {
  final String? buildingName;
  final String? floorName;
  final bool softEstop;
  final bool hardEstop;
  final int battery;
  final int charger;
  final int navStatus;
  final int patrolStatus;
  final List<double> velocity;
  final int controlState;
  final String? currentGoalName;
  final RobotPose? currentGoalCoordinate;
  final RobotPose pose;

  RobotStatusData({
    this.buildingName,
    this.floorName,
    this.softEstop = false,
    this.hardEstop = false,
    this.battery = 0,
    this.charger = 0,
    this.navStatus = 0,
    this.patrolStatus = 0,
    this.velocity = const [0.0, 0.0],
    this.controlState = 0,
    this.currentGoalName,
    this.currentGoalCoordinate,
    RobotPose? pose,
  }) : pose = pose ?? RobotPose();

  factory RobotStatusData.fromJson(Map<String, dynamic> json) {
    final vel = json['velocity'] as List<dynamic>?;
    return RobotStatusData(
      buildingName: json['current_building_name'] as String?,
      floorName: json['current_floor_name'] as String?,
      softEstop: json['soft_estop'] as bool? ?? false,
      hardEstop: json['hard_estop'] as bool? ?? false,
      battery: json['battery'] as int? ?? 0,
      charger: json['charger'] as int? ?? 0,
      navStatus: json['nav_status'] as int? ?? 0,
      patrolStatus: json['patrol_status'] as int? ?? 0,
      velocity: vel?.map((e) => (e as num).toDouble()).toList() ?? [0.0, 0.0],
      controlState: json['control_state'] as int? ?? 0,
      currentGoalName: json['current_goal_name'] as String?,
      currentGoalCoordinate: json['current_goal_coordinate'] != null
          ? RobotPose.fromJson(json['current_goal_coordinate'] as Map<String, dynamic>)
          : null,
    );
  }

  RobotStatusData copyWith({RobotPose? pose}) => RobotStatusData(
    buildingName: buildingName,
    floorName: floorName,
    softEstop: softEstop,
    hardEstop: hardEstop,
    battery: battery,
    charger: charger,
    navStatus: navStatus,
    patrolStatus: patrolStatus,
    velocity: velocity,
    controlState: controlState,
    currentGoalName: currentGoalName,
    currentGoalCoordinate: currentGoalCoordinate,
    pose: pose ?? this.pose,
  );

  String get navStatusText {
    switch (navStatus) {
      case navWaiting: return 'Waiting';
      case navRunning: return 'Running';
      case navCancelled: return 'Cancelled';
      case navSuccess: return 'Success';
      case navFailed: return 'Failed';
      default: return 'Unknown ($navStatus)';
    }
  }

  String get controlStateText {
    switch (controlState) {
      case stateMapping: return 'Mapping';
      case stateNavigation: return 'Navigation';
      case stateError: return 'Error';
      default: return 'Unknown ($controlState)';
    }
  }

  bool get isEstopped => softEstop || hardEstop;
  double get linearVelocity => velocity.isNotEmpty ? velocity[0] : 0;
  double get angularVelocity => velocity.length > 1 ? velocity[1] : 0;
}
