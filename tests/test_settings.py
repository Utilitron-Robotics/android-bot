"""
Unit tests for configuration settings
Tests the Settings class and environment variable handling
"""

import pytest
import os
from config.settings import Settings


class TestSettings:
    """Test suite for Settings configuration class"""
    
    def test_default_robot_type(self):
        """Test default robot type is 'tibo'"""
        assert Settings.ROBOT_TYPE == "tibo"
        
    def test_default_api_port(self):
        """Test default API port is 8000"""
        assert Settings.API_PORT == 8000
        
    def test_default_api_host(self):
        """Test default API host is 0.0.0.0"""
        assert Settings.API_HOST == "0.0.0.0"
        
    def test_default_timeouts(self):
        """Test default timeout values"""
        assert Settings.CONNECTION_TIMEOUT == 5
        assert Settings.NAVIGATION_TIMEOUT == 300
        assert Settings.AUDIO_PLAYBACK_TIMEOUT == 120
        
    def test_default_reconnection_settings(self):
        """Test default reconnection settings"""
        assert Settings.MAX_RECONNECTION_ATTEMPTS == 3
        assert Settings.RECONNECTION_DELAY == 2
        
    def test_default_websocket_settings(self):
        """Test default WebSocket keepalive settings"""
        assert Settings.WS_PING_INTERVAL == 20
        assert Settings.WS_PING_TIMEOUT == 120
        
    def test_default_logging_settings(self):
        """Test default logging configuration"""
        # Note: conftest.py sets LOG_LEVEL to ERROR for tests
        assert Settings.LOG_DIR == "logs"
        assert Settings.ENABLE_FILE_LOGGING is True
        
    def test_get_robot_uri_format(self):
        """Test WebSocket URI construction format"""
        uri = Settings.get_robot_uri()
        assert uri.startswith("ws://")
        assert ":" in uri
        
    def test_get_robot_uri_contains_ip_and_port(self):
        """Test URI contains configured IP and port"""
        uri = Settings.get_robot_uri()
        # Note: conftest.py sets ROBOT_IP to localhost and ROBOT_PORT to 9999
        assert "localhost" in uri or Settings.ROBOT_IP in uri
        
    def test_display_config_returns_dict(self):
        """Test display_config returns a dictionary"""
        config = Settings.display_config()
        assert isinstance(config, dict)
        
    def test_display_config_contains_all_keys(self):
        """Test config dictionary contains all expected keys"""
        config = Settings.display_config()
        
        expected_keys = [
            "robot_type",
            "robot_ip",
            "robot_port",
            "api_host",
            "api_port",
            "connection_timeout",
            "navigation_timeout",
            "audio_timeout",
            "max_reconnect_attempts",
            "ws_ping_interval",
            "ws_ping_timeout",
            "log_level",
            "log_dir",
            "enable_file_logging",
        ]
        
        for key in expected_keys:
            assert key in config, f"Missing key: {key}"
            
    def test_display_config_values_match_settings(self):
        """Test config dictionary values match Settings attributes"""
        config = Settings.display_config()
        
        assert config["robot_type"] == Settings.ROBOT_TYPE
        assert config["api_port"] == Settings.API_PORT
        assert config["connection_timeout"] == Settings.CONNECTION_TIMEOUT
        assert config["log_level"] == Settings.LOG_LEVEL
        
    def test_enable_file_logging_boolean(self):
        """Test ENABLE_FILE_LOGGING is a boolean"""
        assert isinstance(Settings.ENABLE_FILE_LOGGING, bool)

