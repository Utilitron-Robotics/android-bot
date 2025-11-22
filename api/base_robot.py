"""
Base robot interfaces - Abstract classes for robot adapters
This provides a common interface that all robot hardware adapters must implement
"""

from abc import ABC, abstractmethod
from typing import Any, Dict, Optional


class BaseRobotClient(ABC):
    """
    Abstract base class for robot WebSocket/network clients
    All robot-specific clients (Tibo, Lekiwi, Xlerobot) must inherit from this
    """

    @abstractmethod
    async def connect(self, timeout: int = 5) -> None:
        """
        Establish connection to robot

        Args:
            timeout: Connection timeout in seconds
        
        Raises:
            ConnectionError: If connection fails
        """
        pass

    @abstractmethod
    async def disconnect(self) -> None:
        """
        Close connection to robot
        """
        pass

    @abstractmethod
    async def send_message(self, message_dict: Dict[str, Any]) -> None:
        """
        Send a message to the robot

        Args:
            message_dict: Message data as dictionary
        """
        pass

    @abstractmethod
    async def receive_message(self) -> Dict[str, Any]:
        """
        Receive a message from the robot

        Returns:
            Parsed message as dictionary
        """
        pass

    @property
    @abstractmethod
    def is_connected(self) -> bool:
        """
        Check if currently connected to robot

        Returns:
            True if connected, False otherwise
        """
        pass


class BaseRobotCommands(ABC):
    """
    Abstract base class for high-level robot commands
    All robot-specific command interfaces must inherit from this
    """

    def __init__(self, client: BaseRobotClient):
        """
        Initialize with a robot client

        Args:
            client: BaseRobotClient instance for communication
        """
        self.client = client

    @abstractmethod
    async def subscribe_status(self) -> None:
        """
        Subscribe to robot status updates for monitoring navigation state
        """
        pass

    @abstractmethod
    async def unsubscribe_status(self) -> None:
        """
        Unsubscribe from robot status updates
        """
        pass

    @abstractmethod
    async def go_to(self, poi: str, request_id: Optional[str] = None) -> None:
        """
        Send navigation command to move robot to a point of interest

        Args:
            poi: Point of interest name/identifier
            request_id: Optional request identifier for tracking
        """
        pass

    @abstractmethod
    async def wait_until_arrival(self, destination_name: str) -> bool:
        """
        Wait for robot to arrive at destination

        Args:
            destination_name: Name of destination for logging/tracking

        Returns:
            True if navigation successful, False if failed
        """
        pass

