"""
Low-level WebSocket client for Tibo robot communication
Handles connection, sending, and receiving messages
"""

import websockets
import asyncio
import json
import logging
from api.base_robot import BaseRobotClient
from config.settings import settings

logger = logging.getLogger(__name__)


class TiboClient(BaseRobotClient):
    """
    Manages WebSocket connection to the Tibo robot
    Handles low-level send/receive operations
    Inherits from BaseRobotClient for standardized interface
    """

    def __init__(self):
        self.uri = settings.get_robot_uri()
        self.websocket = None
        self._is_connected = False

    async def connect(self, timeout: int = 5) -> None:
        """
        Establish WebSocket connection to robot

        Args:
            timeout: Connection timeout in seconds
        
        Raises:
            ConnectionError: If connection fails
        """
        logger.info(f"Attempting to connect to Tibo robot at {self.uri} (timeout: {timeout}s)")
        try:
            self.websocket = await asyncio.wait_for(
                websockets.connect(
                    self.uri,
                    ping_interval=settings.WS_PING_INTERVAL,  # Send ping every N seconds
                    ping_timeout=settings.WS_PING_TIMEOUT,    # Wait N seconds for pong response
                    close_timeout=10                          # Wait 10 seconds for close handshake
                ), 
                timeout=timeout
            )
            self._is_connected = True
            logger.info(f"✓ Connected to Tibo robot at {self.uri}")
        except asyncio.TimeoutError:
            logger.error(f"Connection timeout after {timeout}s - robot not responding at {self.uri}")
            raise ConnectionError(
                f"Could not connect to robot at {self.uri} within {timeout} seconds."
            )
        except Exception as e:
            logger.error(f"Connection failed to {self.uri}: {type(e).__name__}: {e}")
            raise

    async def disconnect(self) -> None:
        """
        Close WebSocket connection
        """
        if self.websocket:
            await self.websocket.close()
            logger.info("Disconnected from Tibo robot")
        self._is_connected = False
    
    @property
    def is_connected(self) -> bool:
        """
        Check if currently connected to robot

        Returns:
            True if connected, False otherwise
        """
        return self._is_connected

    async def send_message(self, message_dict: dict) -> None:
        """
        Send a JSON message to the robot

        Args:
            message_dict: Dictionary to send as JSON
        """
        json_message = json.dumps(message_dict)
        logger.debug(f"→ Sending: {json_message}")
        await self.websocket.send(json_message)

    async def receive_message(self) -> dict:
        """
        Receive a message from the robot

        Returns:
            Parsed JSON message as dict
        """
        raw_msg = await self.websocket.recv()
        parsed_msg = json.loads(raw_msg)
        return parsed_msg
