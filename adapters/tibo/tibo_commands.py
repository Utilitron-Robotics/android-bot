"""
High-level commands for Tibo robot
Provides convenient methods for navigation and status monitoring
"""

import asyncio
from datetime import datetime
from typing import Optional
import logging
from api.base_robot import BaseRobotCommands, BaseRobotClient

logger = logging.getLogger(__name__)


class TiboCommands(BaseRobotCommands):
    """
    High-level command interface for Tibo robot
    Handles navigation, status subscriptions, and waiting logic
    Inherits from BaseRobotCommands for standardized interface
    """

    def __init__(self, client: BaseRobotClient):
        """
        Initialize with a TiboClient instance

        Args:
            client: BaseRobotClient instance for low-level communication
        """
        super().__init__(client)
        self.client = client

    async def subscribe_status(self) -> None:
        """
        Subscribe to robot status topic to monitor navigation state
        """
        subscription = {
            "topic": "/robot_status",
            "type": "yutong_assistance/RobotStatus",
            "id": "get_robot_status",
            "op": "subscribe",
        }
        await self.client.send_message(subscription)
        logger.info("Subscribed to robot status updates")

    async def unsubscribe_status(self) -> None:
        """
        Unsubscribe from robot status topic
        """
        unsubscribe = {
            "op": "unsubscribe",
            "topic": "/robot_status",
            "id": "get_robot_status",
        }
        await self.client.send_message(unsubscribe)
        logger.info("Unsubscribed from robot status updates")

    async def get_battery_level(self, timeout: float = 5.0) -> Optional[float]:
        """
        Get current battery level from robot sensors

        Subscribes to /mobile_base/sensors/core, reads battery level,
        then unsubscribes from the topic.

        Args:
            timeout: Maximum time to wait for sensor data (seconds)

        Returns:
            Battery percentage as float (0-100), or None if unavailable
        """
        try:
            # Step 1: Subscribe to sensor core topic
            subscription = {
                "topic": "/mobile_base/sensors/core",
                "type": "kobuki_msgs/SensorState",
                "id": "get_sensors_core",
                "op": "subscribe",
            }
            await self.client.send_message(subscription)
            logger.debug("Subscribed to sensor core for battery reading")

            # Step 2: Wait for sensor data
            start_time = asyncio.get_event_loop().time()
            while True:
                remaining_time = timeout - (
                    asyncio.get_event_loop().time() - start_time
                )
                if remaining_time <= 0:
                    logger.warning("⚠️ Battery level read timeout")
                    break

                msg = await asyncio.wait_for(
                    self.client.receive_message(), timeout=remaining_time
                )

                # Check if this is the sensor core message we're looking for
                if msg.get("topic") == "/mobile_base/sensors/core":
                    battery = msg.get("msg", {}).get("battery")
                    if battery is not None:
                        logger.info(f"🔋 Battery level: {battery}%")

                        # Step 3: Unsubscribe from sensor topic
                        unsubscribe = {
                            "topic": "/mobile_base/sensors/core",
                            "type": "kobuki_msgs/SensorState",
                            "id": "get_sensors_core",
                            "op": "unsubscribe",
                        }
                        await self.client.send_message(unsubscribe)
                        logger.debug("Unsubscribed from sensor core")

                        return float(battery)
                else:
                    # Not the message we're looking for, keep waiting
                    logger.debug(f"Skipping message from topic: {msg.get('topic')}")
                    continue

        except asyncio.TimeoutError:
            logger.warning("⚠️ Battery level read timeout - no sensor data received")
        except Exception as e:
            logger.error(f"❌ Error reading battery level: {e}")

        # Cleanup: Try to unsubscribe even if we failed
        try:
            unsubscribe = {
                "topic": "/mobile_base/sensors/core",
                "type": "kobuki_msgs/SensorState",
                "id": "get_sensors_core",
                "op": "unsubscribe",
            }
            await self.client.send_message(unsubscribe)
        except:
            pass  # Ignore cleanup errors

        return None

    async def go_to(self, poi: str, request_id: Optional[str] = None) -> None:
        """
        Send navigation command to move robot to a point of interest

        Args:
            poi: Point of interest name (e.g., "opendroids", "battery")
            request_id: Optional request ID (defaults to "nav_{poi}")
        """
        if request_id is None:
            request_id = f"nav_{poi}"

        navigation_request = {
            "op": "call_service",
            "service": "/poi",
            "id": request_id,
            "args": {"poi": poi},
        }
        await self.client.send_message(navigation_request)
        logger.info(f"🎯 Navigation command sent to waypoint: {poi}")

    async def cancel_navigation(self) -> None:
        """
        Cancel current navigation target point

        Sends a three-step cancellation sequence:
        1. Advertise to /move_base/cancel topic
        2. Publish cancel message
        3. Unadvertise from topic
        """
        # Step 1: Advertise
        advertise_msg = {
            "op": "advertise",
            "id": "cancel_goal",
            "topic": "/move_base/cancel",
            "type": "actionlib_msgs/GoalID",
        }
        await self.client.send_message(advertise_msg)
        logger.debug("Advertised to /move_base/cancel topic")

        # Step 2: Publish cancel command
        cancel_msg = {
            "op": "publish",
            "topic": "/move_base/cancel",
            "id": "cancel_goal",
            "msg": {"stamp": "", "id": ""},
        }
        await self.client.send_message(cancel_msg)
        logger.info("🛑 Navigation cancellation sent")

        # Step 3: Unadvertise
        unadvertise_msg = {
            "op": "unadvertise",
            "id": "cancel_goal",
            "topic": "/move_base/cancel",
        }
        await self.client.send_message(unadvertise_msg)
        logger.debug("Unadvertised from /move_base/cancel topic")

    async def wait_until_arrival(self, destination_name: str) -> bool:
        """
        Wait for robot to arrive at destination

        Handles navigation status polling:
        - 600: Idle/Not started - wait for movement
        - 601: Robot is moving - continue waiting
        - 602: Paused/Recalculating - continue waiting
        - 603: Navigation complete (success)
        - 604: Already at destination (success)
        - 605: Standby/Idle - wait for movement
        - Other codes: Navigation failed

        Note: Ignores initial 603 status before navigation starts (stale/idle state)

        Args:
            destination_name: Name of destination for logging

        Returns:
            Boolean indicating if navigation was successful
        """
        navigation_started = False
        message_count = 0
        idle_message_count = 0
        max_idle_messages = 50  # Prevent infinite waiting on non-moving states

        while True:
            # Listen for messages
            msg = await self.client.receive_message()
            message_count += 1

            # Log all messages at DEBUG level
            logger.debug(f"← Received: {msg}")

            # Skip non-status messages (e.g., service responses)
            if msg.get("topic") != "/robot_status":
                logger.debug("Skipping non-status message")
                continue

            # Extract nav_status
            nav = msg["msg"]["nav_status"]

            # Log nav_status every 10 messages at DEBUG, or on state change at INFO
            if message_count % 10 == 0:
                velocity = msg["msg"].get("velocity", [0, 0])
                battery = msg["msg"].get("battery", "unknown")
                logger.debug(
                    f"nav_status: {nav}, velocity: {velocity}, battery: {battery}%"
                )

            # Handle different navigation states
            if nav == 601:  # running / moving
                idle_message_count = 0  # Reset idle counter
                if not navigation_started:
                    # First time seeing 601 - log at INFO
                    navigation_started = True
                    logger.info(f"🚶 Robot moving to {destination_name}...")
                continue

            elif nav == 603:  # success - arrived
                if navigation_started:
                    logger.info(f"✓ Arrived at {destination_name}")
                    return True
                else:
                    # Ignore initial 603 status (stale/idle state)
                    logger.debug("Ignoring initial 603 status (robot idle)")
                    continue

            elif nav == 604:  # Already at destination
                logger.info(f"✓ Already at {destination_name} (status 604)")
                return True

            elif nav in [600, 605]:  # Idle/standby states - wait for movement
                if not navigation_started:
                    idle_message_count += 1
                    if idle_message_count < max_idle_messages:
                        if idle_message_count == 1:
                            logger.debug(
                                f"Robot in idle state {nav}, waiting for navigation to start..."
                            )
                        continue
                    else:
                        logger.error(
                            f"❌ Navigation failed - robot stuck in idle state {nav} after {idle_message_count} messages"
                        )
                        return False
                else:
                    # If we were moving but now idle, that might be an error
                    logger.warning(
                        f"Robot returned to idle state {nav} after starting navigation"
                    )
                    continue

            elif nav == 602:  # Paused/recalculating during navigation
                if navigation_started:
                    logger.debug(
                        f"Robot paused/recalculating (status 602), continuing to wait..."
                    )
                    continue
                else:
                    # 602 before starting might indicate an issue, but give it time
                    idle_message_count += 1
                    if idle_message_count < max_idle_messages:
                        if idle_message_count == 1:
                            logger.debug(
                                f"Robot in state 602 before navigation started, waiting..."
                            )
                        continue
                    else:
                        logger.error(f"❌ Navigation failed - stuck in status {nav}")
                        return False

            else:  # Unknown/error status
                logger.error(f"❌ Navigation failed with unknown status: {nav}")
                return False
