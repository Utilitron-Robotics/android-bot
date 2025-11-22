"""
Shared pytest fixtures for tour-bot tests
Includes mock clients, fake WebSocket server, and common test utilities
"""

import asyncio
import pytest
import websockets
from unittest.mock import AsyncMock, MagicMock
from typing import AsyncIterator, List, Dict, Any
import os


# Set test environment variables before importing modules
os.environ["ROBOT_IP"] = "localhost"
os.environ["ROBOT_PORT"] = "9999"
os.environ["LOG_LEVEL"] = "ERROR"  # Suppress logs during tests


@pytest.fixture
def mock_robot_client():
    """Create a mock BaseRobotClient for testing"""
    client = MagicMock()
    client.send_message = AsyncMock()
    client.receive_message = AsyncMock()
    client.connect = AsyncMock()
    client.disconnect = AsyncMock()
    client.is_connected = True
    return client


@pytest.fixture
def mock_robot_commands(mock_robot_client):
    """Create a mock BaseRobotCommands for testing"""
    from adapters.tibo.tibo_commands import TiboCommands
    return TiboCommands(mock_robot_client)


class FakeRobotServer:
    """
    Fake WebSocket server that simulates a robot
    Can be configured to send specific message sequences
    """
    
    def __init__(self, host: str = "localhost", port: int = 8765):
        self.host = host
        self.port = port
        self.server = None
        self.message_queue: List[Dict[str, Any]] = []
        self.received_messages: List[Dict[str, Any]] = []
        
    async def handler(self, websocket, path):
        """Handle WebSocket connections from clients"""
        try:
            # Receive messages from client and send responses
            while True:
                try:
                    # Try to receive message with short timeout
                    message = await asyncio.wait_for(
                        websocket.recv(), 
                        timeout=0.1
                    )
                    import json
                    parsed = json.loads(message)
                    self.received_messages.append(parsed)
                except asyncio.TimeoutError:
                    pass
                
                # Send queued messages if any
                if self.message_queue:
                    msg = self.message_queue.pop(0)
                    import json
                    await websocket.send(json.dumps(msg))
                    
                # Small delay to prevent tight loop
                await asyncio.sleep(0.01)
                
        except websockets.exceptions.ConnectionClosed:
            pass
    
    async def start(self):
        """Start the fake robot server"""
        self.server = await websockets.serve(
            self.handler, 
            self.host, 
            self.port
        )
        
    async def stop(self):
        """Stop the fake robot server"""
        if self.server:
            self.server.close()
            await self.server.wait_closed()
            
    def queue_message(self, message: Dict[str, Any]):
        """Queue a message to be sent to clients"""
        self.message_queue.append(message)
        
    def queue_messages(self, messages: List[Dict[str, Any]]):
        """Queue multiple messages"""
        self.message_queue.extend(messages)
        
    @property
    def uri(self) -> str:
        """Get WebSocket URI for this server"""
        return f"ws://{self.host}:{self.port}"


@pytest.fixture
async def fake_robot_server() -> AsyncIterator[FakeRobotServer]:
    """
    Fixture that provides a fake robot WebSocket server
    Automatically starts and stops the server
    
    Example:
        async def test_navigation(fake_robot_server):
            # Queue messages the server should send
            fake_robot_server.queue_messages([
                {"topic": "/robot_status", "msg": {"nav_status": 601}},
                {"topic": "/robot_status", "msg": {"nav_status": 603}},
            ])
            
            # Connect client to fake_robot_server.uri
            # ... test code ...
    """
    server = FakeRobotServer()
    await server.start()
    yield server
    await server.stop()


@pytest.fixture
def sample_waypoints():
    """Common waypoint list for testing"""
    return ["empty_1", "armin", "empty_2", "opendroids", "utilitron", "emerson", "avatar", "end"]


@pytest.fixture
def temp_script_file(tmp_path):
    """Create a temporary script file for testing"""
    script_file = tmp_path / "test_script.txt"
    script_file.write_text("This is a test tour script.")
    return script_file

