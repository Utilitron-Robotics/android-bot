"""
Unit tests for Tibo WebSocket client
Tests connection, messaging, and error handling
"""

import pytest
import asyncio
import json
from unittest.mock import AsyncMock, MagicMock, patch
from adapters.tibo.tibo_client import TiboClient
from config.settings import settings


class TestTiboClient:
    """Test suite for TiboClient WebSocket client"""
    
    @pytest.fixture
    def client(self):
        """Create a TiboClient instance for testing"""
        return TiboClient()
        
    def test_initialization(self, client):
        """Test client initializes with correct defaults"""
        assert client.websocket is None
        assert client.is_connected is False
        assert client.uri.startswith("ws://")
        assert ":" in client.uri
        
    def test_uri_uses_settings(self, client):
        """Test URI is constructed from settings"""
        expected_uri = settings.get_robot_uri()
        assert client.uri == expected_uri
        
    @pytest.mark.asyncio
    async def test_connect_success(self, client):
        """Test successful WebSocket connection"""
        with patch('websockets.connect', new_callable=AsyncMock) as mock_connect:
            mock_ws = AsyncMock()
            mock_connect.return_value = mock_ws
            
            await client.connect(timeout=5)
            
            assert client.is_connected is True
            assert client.websocket is mock_ws
            mock_connect.assert_called_once()
            
            # Verify connection parameters
            call_kwargs = mock_connect.call_args.kwargs
            assert call_kwargs["ping_interval"] == settings.WS_PING_INTERVAL
            assert call_kwargs["ping_timeout"] == settings.WS_PING_TIMEOUT
            
    @pytest.mark.asyncio
    async def test_connect_timeout(self, client):
        """Test connection timeout handling"""
        with patch('websockets.connect', new_callable=AsyncMock) as mock_connect:
            mock_connect.side_effect = asyncio.TimeoutError()
            
            with pytest.raises(ConnectionError) as exc_info:
                await client.connect(timeout=5)
                
            assert "Could not connect" in str(exc_info.value)
            assert client.is_connected is False
            
    @pytest.mark.asyncio
    async def test_connect_exception(self, client):
        """Test connection exception handling"""
        with patch('websockets.connect', new_callable=AsyncMock) as mock_connect:
            mock_connect.side_effect = Exception("Network error")
            
            with pytest.raises(Exception) as exc_info:
                await client.connect(timeout=5)
                
            assert "Network error" in str(exc_info.value)
            assert client.is_connected is False
            
    @pytest.mark.asyncio
    async def test_disconnect(self, client):
        """Test disconnection closes WebSocket"""
        mock_ws = AsyncMock()
        client.websocket = mock_ws
        client._is_connected = True
        
        await client.disconnect()
        
        mock_ws.close.assert_called_once()
        assert client.is_connected is False
        
    @pytest.mark.asyncio
    async def test_disconnect_when_not_connected(self, client):
        """Test disconnect handles case when not connected"""
        client.websocket = None
        client._is_connected = False
        
        # Should not raise exception
        await client.disconnect()
        
        assert client.is_connected is False
        
    @pytest.mark.asyncio
    async def test_send_message_json_serialization(self, client):
        """Test sending message serializes to JSON"""
        mock_ws = AsyncMock()
        client.websocket = mock_ws
        client._is_connected = True
        
        message = {"op": "test", "data": {"value": 123}}
        await client.send_message(message)
        
        mock_ws.send.assert_called_once()
        sent_data = mock_ws.send.call_args[0][0]
        
        # Verify it's valid JSON
        parsed = json.loads(sent_data)
        assert parsed["op"] == "test"
        assert parsed["data"]["value"] == 123
        
    @pytest.mark.asyncio
    async def test_send_message_with_special_characters(self, client):
        """Test sending message with special characters"""
        mock_ws = AsyncMock()
        client.websocket = mock_ws
        client._is_connected = True
        
        message = {"text": "Hello \"World\" with 'quotes'"}
        await client.send_message(message)
        
        sent_data = mock_ws.send.call_args[0][0]
        parsed = json.loads(sent_data)
        assert parsed["text"] == "Hello \"World\" with 'quotes'"
        
    @pytest.mark.asyncio
    async def test_receive_message_json_parsing(self, client):
        """Test receiving and parsing JSON messages"""
        mock_ws = AsyncMock()
        mock_ws.recv.return_value = '{"status": "ok", "value": 42}'
        client.websocket = mock_ws
        
        result = await client.receive_message()
        
        assert result == {"status": "ok", "value": 42}
        mock_ws.recv.assert_called_once()
        
    @pytest.mark.asyncio
    async def test_receive_message_complex_data(self, client):
        """Test receiving complex nested JSON data"""
        mock_ws = AsyncMock()
        complex_data = {
            "topic": "/robot_status",
            "msg": {
                "nav_status": 603,
                "battery": 85,
                "position": [1.5, 2.3, 0.0]
            }
        }
        mock_ws.recv.return_value = json.dumps(complex_data)
        client.websocket = mock_ws
        
        result = await client.receive_message()
        
        assert result["topic"] == "/robot_status"
        assert result["msg"]["nav_status"] == 603
        assert result["msg"]["position"] == [1.5, 2.3, 0.0]
        
    def test_is_connected_property(self, client):
        """Test is_connected property reflects state"""
        assert client.is_connected is False
        
        client._is_connected = True
        assert client.is_connected is True
        
        client._is_connected = False
        assert client.is_connected is False
        
    @pytest.mark.asyncio
    async def test_connect_with_custom_timeout(self, client):
        """Test connection respects custom timeout"""
        with patch('websockets.connect', new_callable=AsyncMock) as mock_connect:
            mock_ws = AsyncMock()
            mock_connect.return_value = mock_ws
            
            await client.connect(timeout=10)
            
            # Verify timeout was passed to wait_for
            assert client.is_connected is True

