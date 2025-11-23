"""
Unit tests for robot factory
Tests robot client and command creation logic
"""

import pytest
from api.robot_factory import (
    create_robot_client,
    create_robot_commands,
    create_robot_stack
)
from api.base_robot import BaseRobotClient, BaseRobotCommands
from adapters.tibo.tibo_client import TiboClient
from adapters.tibo.tibo_commands import TiboCommands


class TestRobotFactory:
    """Test suite for robot factory functions"""
    
    def test_create_tibo_client(self):
        """Test creating a Tibo client"""
        client = create_robot_client("tibo")
        
        assert client is not None
        assert isinstance(client, TiboClient)
        assert isinstance(client, BaseRobotClient)
        
    def test_create_tibo_client_case_insensitive(self):
        """Test robot type is case-insensitive"""
        client_lower = create_robot_client("tibo")
        client_upper = create_robot_client("TIBO")
        client_mixed = create_robot_client("TiBo")
        
        assert isinstance(client_lower, TiboClient)
        assert isinstance(client_upper, TiboClient)
        assert isinstance(client_mixed, TiboClient)
        
    def test_create_invalid_robot_type(self):
        """Test error handling for unknown robot type"""
        with pytest.raises(ValueError) as exc_info:
            create_robot_client("invalid_robot")
            
        assert "Unknown robot type" in str(exc_info.value)
        assert "invalid_robot" in str(exc_info.value)
        
    def test_create_empty_robot_type(self):
        """Test error handling for empty robot type"""
        with pytest.raises(ValueError):
            create_robot_client("")
            
    def test_create_robot_commands_for_tibo(self):
        """Test creating commands for Tibo client"""
        client = create_robot_client("tibo")
        commands = create_robot_commands(client)
        
        assert commands is not None
        assert isinstance(commands, TiboCommands)
        assert isinstance(commands, BaseRobotCommands)
        assert commands.client is client
        
    def test_create_robot_commands_invalid_client(self):
        """Test error handling for invalid client type"""
        from unittest.mock import MagicMock
        
        invalid_client = MagicMock()
        
        with pytest.raises(ValueError) as exc_info:
            create_robot_commands(invalid_client)
            
        assert "Unknown client type" in str(exc_info.value)
        
    def test_create_robot_stack(self):
        """Test creating both client and commands together"""
        client, commands = create_robot_stack("tibo")
        
        assert isinstance(client, TiboClient)
        assert isinstance(commands, TiboCommands)
        assert commands.client is client
        
    def test_create_robot_stack_invalid_type(self):
        """Test error handling for invalid robot type in stack creation"""
        with pytest.raises(ValueError):
            create_robot_stack("nonexistent_robot")
            
    def test_client_has_required_methods(self):
        """Test created client has all required BaseRobotClient methods"""
        client = create_robot_client("tibo")
        
        assert hasattr(client, "connect")
        assert hasattr(client, "disconnect")
        assert hasattr(client, "send_message")
        assert hasattr(client, "receive_message")
        assert hasattr(client, "is_connected")
        
    def test_commands_has_required_methods(self):
        """Test created commands has all required BaseRobotCommands methods"""
        client = create_robot_client("tibo")
        commands = create_robot_commands(client)
        
        assert hasattr(commands, "subscribe_status")
        assert hasattr(commands, "unsubscribe_status")
        assert hasattr(commands, "go_to")
        assert hasattr(commands, "wait_until_arrival")
        
    def test_multiple_clients_are_independent(self):
        """Test that multiple client instances are independent"""
        client1 = create_robot_client("tibo")
        client2 = create_robot_client("tibo")
        
        assert client1 is not client2
        assert id(client1) != id(client2)

