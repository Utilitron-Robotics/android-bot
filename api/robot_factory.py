"""
Robot Factory - Creates robot clients and command interfaces
Provides centralized robot adapter selection based on configuration
"""

from api.base_robot import BaseRobotClient, BaseRobotCommands
from adapters.tibo.tibo_client import TiboClient
from adapters.tibo.tibo_commands import TiboCommands


def create_robot_client(robot_type: str) -> BaseRobotClient:
    """
    Factory function to create robot clients based on robot type
    
    Args:
        robot_type: Type of robot ("tibo", "lekiwi", "xlerobot", etc.)
    
    Returns:
        Instance of BaseRobotClient for the specified robot type
    
    Raises:
        ValueError: If robot_type is not recognized
    
    Example:
        >>> client = create_robot_client("tibo")
        >>> await client.connect()
    """
    robot_type = robot_type.lower()
    
    if robot_type == "tibo":
        return TiboClient()
    # Future robot types - uncomment when adapters are implemented:
    # elif robot_type == "lekiwi":
    #     from adapters.lekiwi.lekiwi_client import LekiwiClient
    #     return LekiwiClient()
    # elif robot_type == "xlerobot":
    #     from adapters.xlerobot.xlerobot_client import XlerobotClient
    #     return XlerobotClient()
    else:
        raise ValueError(
            f"Unknown robot type: '{robot_type}'. "
            f"Supported types: tibo (add more adapters to support other robots)"
        )


def create_robot_commands(client: BaseRobotClient) -> BaseRobotCommands:
    """
    Factory function to create command interfaces for robot clients
    
    Args:
        client: BaseRobotClient instance
    
    Returns:
        Instance of BaseRobotCommands appropriate for the client type
    
    Raises:
        ValueError: If client type is not recognized
    
    Example:
        >>> client = create_robot_client("tibo")
        >>> commands = create_robot_commands(client)
    """
    if isinstance(client, TiboClient):
        return TiboCommands(client)
    # Future robot types - uncomment when adapters are implemented:
    # elif isinstance(client, LekiwiClient):
    #     from adapters.lekiwi.lekiwi_commands import LekiwiCommands
    #     return LekiwiCommands(client)
    # elif isinstance(client, XlerobotClient):
    #     from adapters.xlerobot.xlerobot_commands import XlerobotCommands
    #     return XlerobotCommands(client)
    else:
        raise ValueError(
            f"Unknown client type: {type(client).__name__}. "
            f"Cannot create commands interface."
        )


def create_robot_stack(robot_type: str) -> tuple[BaseRobotClient, BaseRobotCommands]:
    """
    Convenience function to create both client and commands in one call
    
    Args:
        robot_type: Type of robot ("tibo", "lekiwi", "xlerobot", etc.)
    
    Returns:
        Tuple of (client, commands) ready to use
    
    Example:
        >>> client, commands = create_robot_stack("tibo")
        >>> await client.connect()
        >>> await commands.go_to("waypoint1")
    """
    client = create_robot_client(robot_type)
    commands = create_robot_commands(client)
    return client, commands

