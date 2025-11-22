"""
Base API Infrastructure - Reusable components for all robot applications
Provides common connection management, reconnection logic, and utilities
"""

import asyncio
import logging
from typing import Optional
from abc import ABC, abstractmethod

from api.base_robot import BaseRobotClient, BaseRobotCommands
from api.robot_factory import create_robot_client, create_robot_commands
from config.settings import settings

logger = logging.getLogger(__name__)


class BaseRobotApplication(ABC):
    """
    Abstract base class for robot applications
    Provides common infrastructure like connection management and reconnection logic
    
    All robot applications (tour bot, concierge bot, security bot, etc.) should inherit from this
    """

    def __init__(self):
        self.client: Optional[BaseRobotClient] = None
        self.commands: Optional[BaseRobotCommands] = None

    async def ensure_connection(self):
        """
        Ensure robot connection is established using configured robot type
        Creates client and commands interface if not already connected
        """
        if self.client is None or not self.client.is_connected:
            # Use factory to create robot client based on configuration
            self.client = create_robot_client(settings.ROBOT_TYPE)
            await self.client.connect(timeout=settings.CONNECTION_TIMEOUT)

            # Create commands interface for the client
            self.commands = create_robot_commands(self.client)
            logger.info(f"✓ Connected to {settings.ROBOT_TYPE} robot")

    async def disconnect(self):
        """
        Disconnect from robot if connected
        """
        if self.client and self.client.is_connected:
            await self.client.disconnect()
            logger.info("Disconnected from robot")

    async def reconnect_robot(self) -> bool:
        """
        Attempt to reconnect to the robot after connection loss
        
        Returns:
            True if reconnection successful, False otherwise
        """
        logger.warning(f"🔄 Attempting to reconnect to {settings.ROBOT_TYPE} robot...")
        max_retries = settings.MAX_RECONNECTION_ATTEMPTS

        for attempt in range(1, max_retries + 1):
            try:
                logger.info(f"Reconnection attempt {attempt}/{max_retries}")

                # Clean up old connection
                if self.client:
                    try:
                        await self.client.disconnect()
                    except:
                        pass

                # Create new connection using factory
                self.client = create_robot_client(settings.ROBOT_TYPE)
                await self.client.connect(timeout=settings.CONNECTION_TIMEOUT)
                self.commands = create_robot_commands(self.client)

                # Resubscribe to status updates if commands support it
                if hasattr(self.commands, 'subscribe_status'):
                    await self.commands.subscribe_status()

                logger.info("✓ Reconnected successfully")
                return True

            except Exception as e:
                logger.error(f"❌ Reconnection attempt {attempt} failed: {e}")
                if attempt < max_retries:
                    await asyncio.sleep(settings.RECONNECTION_DELAY)

        logger.critical("❌ All reconnection attempts exhausted - connection lost")
        return False

    @abstractmethod
    async def initialize(self):
        """
        Initialize the application (called on startup)
        Override this to add application-specific initialization
        """
        pass

    @abstractmethod
    async def cleanup(self):
        """
        Clean up resources (called on shutdown)
        Override this to add application-specific cleanup
        """
        pass

