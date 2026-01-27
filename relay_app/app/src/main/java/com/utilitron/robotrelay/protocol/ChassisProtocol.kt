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

    // === BODY TRACKING / SKELETON TOPICS ===
    // These provide the "Minecraft-like" block visualization of humans with arms/hands
    const val TOPIC_BODY_TRACKER = "/body_tracker/people"  // cob_perception_msgs/People (skeleton array)
    const val TOPIC_BODY_TRACKER_SKELETON = "/body_tracker/skeleton"  // Skeleton keypoints
    const val TOPIC_BODY_TRACKER_MARKER = "/body_tracker/marker"  // Visualization markers
    const val TOPIC_BODY_TRACKER_POSITION = "/body_tracker/position"  // Position info
    const val TOPIC_SKELETON_3D = "/skeleton_3d"  // 3D skeleton data
    const val TOPIC_HUMANS_BODIES_TRACKED = "/humans/bodies/tracked"  // REP 155 standard
    const val TOPIC_HUMANS_BODIES_LIST = "/humans/bodies/list"  // REP 155 body list
    const val TOPIC_PERSON_TRACKER = "/person_tracker/people"  // Alternative tracker
    const val TOPIC_DETECTED_OBJECTS = "/detected_objects"  // Object detection (includes people)
    const val TOPIC_DETECTED_PERSONS = "/detected_persons"  // Person-specific detections
    const val TOPIC_BOUNDING_BOXES = "/bounding_boxes"  // 3D bounding boxes
    const val TOPIC_DEPTH_REGISTERED_POINTS = "/camera/depth_registered/points"  // Point cloud
    const val TOPIC_RGBD_DETECTIONS = "/rgbd_detections"  // RGB-D person detections

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

    // === BODY TRACKING SUBSCRIPTIONS ===
    // These topics may provide the detailed human shape data for map visualization

    /**
     * Subscribe to body tracker skeleton data (cob_perception_msgs style).
     * This provides full skeleton with joint positions - the "Minecraft blocks" for limbs.
     */
    fun subscribeBodyTrackerPeople(): String = toJson(SubscribeMsg(
        op = OP_SUBSCRIBE,
        id = "get_body_tracker_people",
        topic = TOPIC_BODY_TRACKER,
        type = "cob_perception_msgs/People",  // May also be body_tracker_msgs/BodyArray
        throttleRate = 100
    ))

    fun subscribeBodyTrackerSkeleton(): String = toJson(SubscribeMsg(
        op = OP_SUBSCRIBE,
        id = "get_body_tracker_skeleton",
        topic = TOPIC_BODY_TRACKER_SKELETON,
        type = "body_tracker_msgs/Skeleton",
        throttleRate = 100
    ))

    /**
     * Subscribe to 3D skeleton data (OpenPose / depth camera style).
     */
    fun subscribeSkeleton3D(): String = toJson(SubscribeMsg(
        op = OP_SUBSCRIBE,
        id = "get_skeleton_3d",
        topic = TOPIC_SKELETON_3D,
        type = "openpose_ros_msgs/PersonArray",  // Common format
        throttleRate = 100
    ))

    /**
     * Subscribe to REP 155 standard human tracking topics.
     */
    fun subscribeHumansBodiesTracked(): String = toJson(SubscribeMsg(
        op = OP_SUBSCRIBE,
        id = "get_humans_bodies_tracked",
        topic = TOPIC_HUMANS_BODIES_TRACKED,
        type = "hri_msgs/IdsList",
        throttleRate = 200
    ))

    /**
     * Subscribe to detected objects (may include people with bounding boxes).
     */
    fun subscribeDetectedObjects(): String = toJson(SubscribeMsg(
        op = OP_SUBSCRIBE,
        id = "get_detected_objects",
        topic = TOPIC_DETECTED_OBJECTS,
        type = "vision_msgs/Detection3DArray",  // Standard 3D detection format
        throttleRate = 100
    ))

    /**
     * Subscribe to person-specific detections with 3D bounding boxes.
     */
    fun subscribeDetectedPersons(): String = toJson(SubscribeMsg(
        op = OP_SUBSCRIBE,
        id = "get_detected_persons",
        topic = TOPIC_DETECTED_PERSONS,
        type = "spencer_tracking_msgs/DetectedPersons",  // SPENCER framework
        throttleRate = 100
    ))

    /**
     * Subscribe to depth camera point cloud for person visualization.
     * This raw data shows people as 3D point clusters.
     */
    fun subscribeDepthPoints(): String = toJson(SubscribeMsg(
        op = OP_SUBSCRIBE,
        id = "get_depth_points",
        topic = TOPIC_DEPTH_REGISTERED_POINTS,
        type = "sensor_msgs/PointCloud2",
        throttleRate = 500  // Heavy data, throttle hard
    ))

    // === ROSAPI SERVICE CALLS ===

    /**
     * Call /rosapi/topics to discover ALL available topics on the robot.
     * Response: { "topics": ["/topic1", "/topic2", ...], "types": ["type1", "type2", ...] }
     */
    fun callGetAllTopics(): String = """{"op":"call_service","id":"rosapi_topics","service":"/rosapi/topics"}"""

    /**
     * Call /rosapi/topic_type to get the message type for a specific topic.
     */
    fun callGetTopicType(topic: String): String = toJson(ServiceCallMsg(
        op = OP_CALL_SERVICE,
        id = "rosapi_topic_type",
        service = SERVICE_ROSAPI_TOPIC_TYPE,
        args = mapOf("topic" to topic)
    ))

    /**
     * Generic subscription with any topic/type - for discovered topics.
     */
    fun subscribeGeneric(topic: String, msgType: String, throttleMs: Int = 200): String = toJson(SubscribeMsg(
        op = OP_SUBSCRIBE,
        id = "sub_${topic.replace("/", "_")}",
        topic = topic,
        type = msgType,
        throttleRate = throttleMs
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
