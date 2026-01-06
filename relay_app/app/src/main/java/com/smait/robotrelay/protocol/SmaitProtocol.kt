package com.smait.robotrelay.protocol

import com.google.gson.Gson
import com.google.gson.JsonObject
import com.google.gson.annotations.SerializedName

/**
 * smAiT Upper Computer Communication Protocol implementation
 * Based on WebSocket JSON protocol for robot chassis control
 */
object SmaitProtocol {
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

    // Services
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

    fun subscribeMap(): String = toJson(MapSubscribeMsg(
        op = OP_SUBSCRIBE,
        id = "get_map",
        topic = TOPIC_MAP,
        type = "nav_msgs/OccupancyGrid",
        fragmentSize = 6000,
        compression = "png"
    ))

    /**
     * Subscribe to map WITHOUT fragmentation/compression.
     * Returns raw OccupancyGrid that Flutter can parse directly.
     * Uses throttle_rate to limit map updates to every 5 seconds.
     */
    fun subscribeMapSimple(): String = toJson(SubscribeMsg(
        op = OP_SUBSCRIBE,
        id = "get_map_simple",
        topic = TOPIC_MAP,
        type = "nav_msgs/OccupancyGrid",
        throttleRate = 5000
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
    val compression: String
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
