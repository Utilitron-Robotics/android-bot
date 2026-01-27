package com.utilitron.robotrelay.protocol

import com.google.gson.Gson
import com.google.gson.JsonObject
import com.google.gson.annotations.SerializedName

/**
 * Chassis Upper Computer Communication Protocol implementation
 * Based on WebSocket JSON protocol for robot chassis control
 */
object ChassisProtocol {
    private val gson = Gson()

    // Operation types
    const val OP_ADVERTISE = "advertise"
    const val OP_PUBLISH = "publish"
    const val OP_UNADVERTISE = "unadvertise"
    const val OP_SUBSCRIBE = "subscribe"
    const val OP_UNSUBSCRIBE = "unsubscribe"
    const val OP_CALL_SERVICE = "call_service"
    const val OP_SERVICE_RESPONSE = "service_response"
    const val OP_FRAGMENT = "fragment"
    const val OP_PNG = "png"

    // Common topics
    const val TOPIC_ROBOT_POSE = "/robot_pose"
    const val TOPIC_ROBOT_STATUS = "/robot_status"
    const val TOPIC_LASER_DATA = "/laser_data"
    const val TOPIC_GLOBAL_PATH = "/global_path"
    const val TOPIC_MAP = "/map"
    const val TOPIC_NAVI_STATUS = "/navi_status"
    const val TOPIC_CMD_VEL = "/cmd_vel_mux/input/teleop"
    const val TOPIC_CANCEL_GOAL = "/move_base/cancel"
    const val TOPIC_SOFT_STOP = "/soft_stop"
    const val TOPIC_SENSORS_CORE = "/mobile_base/sensors/core"
    const val TOPIC_PEOPLE_DETECTED = "/people_detected"
    const val TOPIC_DETECTED_PEOPLE_ARRAY = "/detected_people_array"  // Rich people detection data
    const val TOPIC_HANDPOSE = "/handpose"  // Hand gesture detection
    const val TOPIC_LOCAL_COSTMAP = "/move_base/local_costmap/costmap"  // Real-time obstacle blocks

    // === DEPTH CAMERA & POINT CLOUD TOPICS ===
    // These are the ACTUAL topics on CIOT robots that provide human shape data
    // The "Minecraft blocks" come from depth camera → point cloud → costmap projection
    const val TOPIC_UPCAMERA_DEPTH_POINTS = "/upcamera/depth/points"  // sensor_msgs/PointCloud2 - RAW 3D point cloud
    const val TOPIC_UPCAMERA_DEPTH_IMAGE = "/upcamera/depth/image_raw"  // sensor_msgs/Image - depth image
    const val TOPIC_UPCAMERA_DEPTH_INFO = "/upcamera/depth/camera_info"  // sensor_msgs/CameraInfo
    const val TOPIC_UP_CAMERA_POINTS = "/up_camera_points"  // Processed camera points
    const val TOPIC_UP_CAMERA_SCAN = "/up_camera_scan"  // Camera converted to 2D scan
    const val TOPIC_UP_CAMERA_POINTCLOUD_BUFF = "/up_camera_pointcloud_buff"  // Buffered point cloud
    const val TOPIC_OVER_CAMERA_POINTCLOUD_BUFF = "/over_camera_pointcloud_buff"  // Over camera buffer
    const val TOPIC_UP_CAMERA_BEFORE_MAP = "/up_camera_before_to_map"  // Pre-transform points
    const val TOPIC_UP_CAMERA_AFTER_MAP = "/up_camera_after_to_map"  // Post-transform points
    const val TOPIC_OVER_CAMERA_BEFORE_MAP = "/over_camera_before_to_map"  // Over camera pre-transform
    const val TOPIC_OBSTACLE_REGION = "/obstacle_region"  // Detected obstacle shapes/regions
    const val TOPIC_UPCAM_DATA = "/upcam_data"  // Processed up camera data
    const val TOPIC_DOWNCAM_DATA = "/downcam_data"  // Processed down camera data

    // Services
    const val SERVICE_ROSAPI_TOPICS = "/rosapi/topics"  // List all available topics
    const val SERVICE_ROSAPI_TOPIC_TYPE = "/rosapi/topic_type"  // Get topic type
    const val SERVICE_POI = "/poi"
    const val SERVICE_NODE_MANAGER = "/node_manager_control"
    const val SERVICE_VELOCITY_CONTROL = "/velocity_control"
    const val SERVICE_ROBOT_INFO = "/robot_info"
    const val SERVICE_GET_MAP_INFO = "/get_map_info"

    // Navigation status codes
    const val NAV_WAITING = 600
    const val NAV_RUNNING = 601
    const val NAV_CANCELLED = 602
    const val NAV_SUCCESS = 603
    const val NAV_FAILED = 604

    // Control states
    const val STATE_MAPPING = 20
    const val STATE_NAVIGATION = 30
    const val STATE_ERROR = 99

    fun toJson(msg: Any): String = gson.toJson(msg)
    fun <T> fromJson(json: String, clazz: Class<T>): T = gson.fromJson(json, clazz)

    // === Subscription Messages ===

    fun subscribeRobotPose(): String = toJson(SubscribeMsg(
        op = OP_SUBSCRIBE,
        id = "get_pose",
        topic = TOPIC_ROBOT_POSE,
        type = "geometry_msgs/Pose2D"
    ))

    fun subscribeRobotStatus(): String = toJson(SubscribeMsg(
        op = OP_SUBSCRIBE,
        id = "get_robot_status",
        topic = TOPIC_ROBOT_STATUS,
        type = "yutong_assistance/RobotStatus"
    ))

    fun subscribeLaserData(): String = toJson(SubscribeMsg(
        op = OP_SUBSCRIBE,
        id = "get_laser",
        topic = TOPIC_LASER_DATA,
        type = "yutong_assistance/point_array"
    ))

    fun subscribeGlobalPath(): String = toJson(SubscribeMsg(
        op = OP_SUBSCRIBE,
        id = "get_global_path",
        topic = TOPIC_GLOBAL_PATH,
        type = "yutong_assistance/point_array"
    ))

    fun subscribeNaviStatus(): String = toJson(SubscribeMsg(
        op = OP_SUBSCRIBE,
        id = "get_navi_status",
        topic = TOPIC_NAVI_STATUS,
        type = "actionlib_msgs/GoalStatus"
    ))

    fun subscribeSensorsCore(): String = toJson(SubscribeMsg(
        op = OP_SUBSCRIBE,
        id = "get_sensors_core",
        topic = TOPIC_SENSORS_CORE,
        type = "kobuki_msgs/CoreSensors"
    ))

    fun subscribePeopleDetected(): String = toJson(SubscribeMsg(
        op = OP_SUBSCRIBE,
        id = "get_people_detected",
        topic = TOPIC_PEOPLE_DETECTED,
        type = "std_msgs/Bool"  // True when person detected
    ))

    /**
     * Subscribe to rich people detection data.
     * This topic provides position, count, and tracking info for detected people.
     * Message type is unknown - logging will reveal the actual format.
     */
    fun subscribeDetectedPeopleArray(): String = toJson(SubscribeMsg(
        op = OP_SUBSCRIBE,
        id = "get_detected_people_array",
        topic = TOPIC_DETECTED_PEOPLE_ARRAY,
        type = "yutong_assistance/PersonArray",  // Best guess based on other msg types
        throttleRate = 200
    ))

    /**
     * Subscribe to hand gesture detection.
     */
    fun subscribeHandpose(): String = toJson(SubscribeMsg(
        op = OP_SUBSCRIBE,
        id = "get_handpose",
        topic = TOPIC_HANDPOSE,
        type = "std_msgs/Int32"  // Likely gesture ID
    ))

    /**
     * Subscribe to local costmap - shows real-time obstacles as inflated "blocks".
     * This is what the OEM software uses to show obstacle rectangles on the map.
     * Throttled heavily because costmap can be large.
     */
    fun subscribeLocalCostmap(): String = toJson(SubscribeMsg(
        op = OP_SUBSCRIBE,
        id = "get_local_costmap",
        topic = TOPIC_LOCAL_COSTMAP,
        type = "nav_msgs/OccupancyGrid",
        throttleRate = 500  // 2Hz max - costmap is heavy
    ))

    /**
     * Subscribe to map WITHOUT fragmentation/compression.
     * Returns raw OccupancyGrid that Flutter can parse directly.
     * The fragmented+PNG approach from chassis docs does NOT produce
     * the expected message format on our robots.
     */
    fun subscribeMap(): String = toJson(SubscribeMsg(
        op = OP_SUBSCRIBE,
        id = "get_map",
        topic = TOPIC_MAP,
        type = "nav_msgs/OccupancyGrid",
        throttleRate = 5000
    ))

    // === DEPTH CAMERA SUBSCRIPTIONS ===
    // These are the ACTUAL CIOT robot topics for human visualization

    fun subscribeUpcameraDepthPoints(): String = toJson(SubscribeMsg(
        op = OP_SUBSCRIBE,
        id = "get_upcamera_depth_points",
        topic = TOPIC_UPCAMERA_DEPTH_POINTS,
        type = "sensor_msgs/PointCloud2",
        throttleRate = 200
    ))

    fun subscribeUpcameraDepthImage(): String = toJson(SubscribeMsg(
        op = OP_SUBSCRIBE,
        id = "get_upcamera_depth_image",
        topic = TOPIC_UPCAMERA_DEPTH_IMAGE,
        type = "sensor_msgs/Image",
        throttleRate = 500
    ))

    fun subscribeUpCameraPoints(): String = toJson(SubscribeMsg(
        op = OP_SUBSCRIBE,
        id = "get_up_camera_points",
        topic = TOPIC_UP_CAMERA_POINTS,
        type = "sensor_msgs/PointCloud2",
        throttleRate = 200
    ))

    fun subscribeUpCameraScan(): String = toJson(SubscribeMsg(
        op = OP_SUBSCRIBE,
        id = "get_up_camera_scan",
        topic = TOPIC_UP_CAMERA_SCAN,
        type = "sensor_msgs/LaserScan",
        throttleRate = 150
    ))

    fun subscribeObstacleRegion(): String = toJson(SubscribeMsg(
        op = OP_SUBSCRIBE,
        id = "get_obstacle_region",
        topic = TOPIC_OBSTACLE_REGION,
        type = "unknown",  // Will log actual type
        throttleRate = 200
    ))

    fun subscribeUpcamData(): String = toJson(SubscribeMsg(
        op = OP_SUBSCRIBE,
        id = "get_upcam_data",
        topic = TOPIC_UPCAM_DATA,
        type = "unknown",
        throttleRate = 200
    ))

    fun subscribeDowncamData(): String = toJson(SubscribeMsg(
        op = OP_SUBSCRIBE,
        id = "get_downcam_data",
        topic = TOPIC_DOWNCAM_DATA,
        type = "unknown",
        throttleRate = 200
    ))

    fun subscribeUpCameraAfterMap(): String = toJson(SubscribeMsg(
        op = OP_SUBSCRIBE,
        id = "get_up_camera_after_map",
        topic = TOPIC_UP_CAMERA_AFTER_MAP,
        type = "sensor_msgs/PointCloud2",
        throttleRate = 200
    ))

    fun unsubscribe(topic: String, id: String): String = toJson(UnsubscribeMsg(
        op = OP_UNSUBSCRIBE,
        id = id,
        topic = topic
    ))

    // === Publish Messages ===

    fun advertiseVelocity(): String = toJson(AdvertiseMsg(
        op = OP_ADVERTISE,
        id = "velocity_control",
        topic = TOPIC_CMD_VEL,
        type = "geometry_msgs/Twist"
    ))

    fun publishVelocity(linearX: Double, angularZ: Double): String = toJson(VelocityMsg(
        op = OP_PUBLISH,
        id = "velocity_control",
        topic = TOPIC_CMD_VEL,
        msg = TwistMsg(
            linear = Vector3(x = linearX),
            angular = Vector3(z = angularZ)
        )
    ))

    fun stopRobot(): String = publishVelocity(0.0, 0.0)

    fun advertiseCancelGoal(): String = toJson(AdvertiseMsg(
        op = OP_ADVERTISE,
        id = "cancel_goal",
        topic = TOPIC_CANCEL_GOAL,
        type = "actionlib_msgs/GoalID"
    ))

    fun publishCancelGoal(): String = toJson(CancelGoalMsg(
        op = OP_PUBLISH,
        id = "cancel_goal",
        topic = TOPIC_CANCEL_GOAL,
        msg = GoalID()
    ))

    fun advertiseSoftStop(): String = toJson(AdvertiseMsg(
        op = OP_ADVERTISE,
        id = "set_estop",
        topic = TOPIC_SOFT_STOP,
        type = "std_msgs/Bool"
    ))

    fun publishSoftStop(enabled: Boolean): String = toJson(SoftStopMsg(
        op = OP_PUBLISH,
        id = "set_estop",
        topic = TOPIC_SOFT_STOP,
        msg = BoolMsg(data = enabled)
    ))

    // === Service Calls ===

    fun callNavigateToPoi(poiName: String): String = toJson(ServiceCallMsg(
        op = OP_CALL_SERVICE,
        id = "service_poi",
        service = SERVICE_POI,
        args = mapOf("poi" to poiName)
    ))

    fun callGetRobotInfo(): String = toJson(ServiceCallMsg(
        op = OP_CALL_SERVICE,
        id = "service_robot_info",
        service = SERVICE_ROBOT_INFO,
        args = mapOf("cmd" to 0)
    ))

    fun callGetMapInfo(): String = toJson(ServiceCallMsg(
        op = OP_CALL_SERVICE,
        id = "service_get_map_info",
        service = SERVICE_GET_MAP_INFO,
        args = mapOf("cmd" to 0)
    ))

    fun callSetSpeedMode(mode: Int): String = toJson(ServiceCallMsg(
        op = OP_CALL_SERVICE,
        id = "service_velocity_control",
        service = SERVICE_VELOCITY_CONTROL,
        args = mapOf("cmd" to mode, "str" to "")
    ))

    // Speed modes
    const val SPEED_SAFETY_LOW = 0
    const val SPEED_SAFETY_MED = 1
    const val SPEED_SAFETY_HIGH = 2
    const val SPEED_BALANCE_LOW = 3
    const val SPEED_BALANCE_MED = 4
    const val SPEED_BALANCE_HIGH = 5
    const val SPEED_EFFICIENCY_LOW = 6
    const val SPEED_EFFICIENCY_MED = 7
    const val SPEED_EFFICIENCY_HIGH = 8
    const val SPEED_DEFAULT = -1
    const val SPEED_SMOOTH_ON = 60
    const val SPEED_SMOOTH_OFF = 61
    const val SPEED_GET_CURRENT = 99
}

// === Data Classes ===

data class SubscribeMsg(
    val op: String,
    val id: String,
    val topic: String,
    val type: String,
    @SerializedName("throttle_rate") val throttleRate: Int? = null
)

data class MapSubscribeMsg(
    val op: String,
    val id: String,
    val topic: String,
    val type: String,
    @SerializedName("fragment_size") val fragmentSize: Int,
    val compression: String,
    @SerializedName("throttle_rate") val throttleRate: Int? = null
)

data class UnsubscribeMsg(
    val op: String,
    val id: String,
    val topic: String
)

data class AdvertiseMsg(
    val op: String,
    val id: String,
    val topic: String,
    val type: String
)

data class Vector3(
    val x: Double = 0.0,
    val y: Double = 0.0,
    val z: Double = 0.0
)

data class TwistMsg(
    val linear: Vector3,
    val angular: Vector3
)

data class VelocityMsg(
    val op: String,
    val id: String,
    val topic: String,
    val msg: TwistMsg
)

data class GoalID(
    val stamp: String = "",
    val id: String = ""
)

data class CancelGoalMsg(
    val op: String,
    val id: String,
    val topic: String,
    val msg: GoalID
)

data class BoolMsg(val data: Boolean)

data class SoftStopMsg(
    val op: String,
    val id: String,
    val topic: String,
    val msg: BoolMsg
)

data class ServiceCallMsg(
    val op: String,
    val id: String,
    val service: String,
    val args: Map<String, Any>
)

// === Response Data Classes ===

data class RobotPose(
    val x: Double,
    val y: Double,
    val theta: Double
)

data class RobotStatus(
    @SerializedName("current_building_name") val buildingName: String?,
    @SerializedName("current_floor_name") val floorName: String?,
    @SerializedName("soft_estop") val softEstop: Boolean,
    @SerializedName("hard_estop") val hardEstop: Boolean,
    val battery: Int,
    val charger: Int,
    @SerializedName("nav_status") val navStatus: Int,
    @SerializedName("patrol_status") val patrolStatus: Int,
    val velocity: List<Double>?,
    @SerializedName("control_state") val controlState: Int,
    @SerializedName("current_goal_name") val currentGoalName: String?,
    @SerializedName("current_goal_coordinate") val currentGoalCoordinate: RobotPose?
)

data class NaviStatus(
    val status: Int,
    val text: String,
    @SerializedName("goal_id") val goalId: JsonObject?
)
