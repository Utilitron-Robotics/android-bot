"""
Configuration settings for TourBot
Manages environment variables and application settings
"""

import os
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()


class Settings:
    """
    Application settings loaded from environment variables
    """

    # Robot Configuration
    ROBOT_TYPE: str = os.getenv("ROBOT_TYPE", "tibo")
    ROBOT_IP: str = os.getenv("ROBOT_IP", "localhost")
    ROBOT_PORT: str = os.getenv("ROBOT_PORT", "9090")

    # API Configuration
    API_HOST: str = os.getenv("API_HOST", "0.0.0.0")
    API_PORT: int = int(os.getenv("API_PORT", "8000"))

    # Timeouts (in seconds)
    CONNECTION_TIMEOUT: int = int(os.getenv("CONNECTION_TIMEOUT", "5"))
    NAVIGATION_TIMEOUT: int = int(os.getenv("NAVIGATION_TIMEOUT", "300"))
    AUDIO_PLAYBACK_TIMEOUT: int = int(os.getenv("AUDIO_PLAYBACK_TIMEOUT", "120"))

    # Reconnection settings
    MAX_RECONNECTION_ATTEMPTS: int = int(os.getenv("MAX_RECONNECTION_ATTEMPTS", "3"))
    RECONNECTION_DELAY: int = int(os.getenv("RECONNECTION_DELAY", "2"))

    # WebSocket keepalive settings (for handling network latency/stability)
    WS_PING_INTERVAL: int = int(os.getenv("WS_PING_INTERVAL", "20"))  # Send ping every N seconds
    WS_PING_TIMEOUT: int = int(os.getenv("WS_PING_TIMEOUT", "120"))   # Wait N seconds for pong response

    # Logging settings
    LOG_LEVEL: str = os.getenv("LOG_LEVEL", "INFO")
    LOG_DIR: str = os.getenv("LOG_DIR", "logs")
    ENABLE_FILE_LOGGING: bool = os.getenv("ENABLE_FILE_LOGGING", "true").lower() == "true"

    @classmethod
    def get_robot_uri(cls) -> str:
        """
        Get the full WebSocket URI for robot connection

        Returns:
            WebSocket URI string (e.g., "ws://192.168.1.100:9090")
        """
        return f"ws://{cls.ROBOT_IP}:{cls.ROBOT_PORT}"

    @classmethod
    def display_config(cls) -> dict:
        """
        Get current configuration as a dictionary (for debugging/display)

        Returns:
            Dictionary with current settings
        """
        return {
            "robot_type": cls.ROBOT_TYPE,
            "robot_ip": cls.ROBOT_IP,
            "robot_port": cls.ROBOT_PORT,
            "api_host": cls.API_HOST,
            "api_port": cls.API_PORT,
            "connection_timeout": cls.CONNECTION_TIMEOUT,
            "navigation_timeout": cls.NAVIGATION_TIMEOUT,
            "audio_timeout": cls.AUDIO_PLAYBACK_TIMEOUT,
            "max_reconnect_attempts": cls.MAX_RECONNECTION_ATTEMPTS,
            "ws_ping_interval": cls.WS_PING_INTERVAL,
            "ws_ping_timeout": cls.WS_PING_TIMEOUT,
            "log_level": cls.LOG_LEVEL,
            "log_dir": cls.LOG_DIR,
            "enable_file_logging": cls.ENABLE_FILE_LOGGING,
        }


# Global settings instance
settings = Settings()

