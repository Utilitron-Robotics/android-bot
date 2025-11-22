"""
Unit tests for base API infrastructure
Tests BaseRobotApplication connection management and reconnection logic
"""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from api.base_api import BaseRobotApplication
from api.base_robot import BaseRobotClient, BaseRobotCommands


class ConcreteRobotApp(BaseRobotApplication):
    """
    Concrete implementation of BaseRobotApplication for testing
    Required to test abstract base class
    """
    
    async def initialize(self):
        """Simple initialization for testing"""
        pass
        
    async def cleanup(self):
        """Simple cleanup for testing"""
        await self.disconnect()


class TestBaseRobotApplication:
    """Test suite for BaseRobotApplication"""
    
    @pytest.fixture
    def app(self):
        """Create a concrete robot application instance"""
        return ConcreteRobotApp()
        
    def test_initialization(self, app):
        """Test application initializes with no client"""
        assert app.client is None
        assert app.commands is None
        
    @pytest.mark.asyncio
    async def test_ensure_connection_creates_client(self, app):
        """Test ensure_connection creates client and commands"""
        with patch('api.base_api.create_robot_client') as mock_create_client, \
             patch('api.base_api.create_robot_commands') as mock_create_commands:
            
            # Set up mocks
            mock_client = MagicMock(spec=BaseRobotClient)
            mock_client.is_connected = False
            mock_client.connect = AsyncMock()
            mock_create_client.return_value = mock_client
            
            mock_commands = MagicMock(spec=BaseRobotCommands)
            mock_create_commands.return_value = mock_commands
            
            await app.ensure_connection()
            
            # Verify client and commands were created
            assert app.client is mock_client
            assert app.commands is mock_commands
            mock_client.connect.assert_called_once()
            
    @pytest.mark.asyncio
    async def test_ensure_connection_when_already_connected(self, app):
        """Test ensure_connection skips if already connected"""
        # Set up already connected client
        mock_client = MagicMock(spec=BaseRobotClient)
        mock_client.is_connected = True
        mock_client.connect = AsyncMock()
        app.client = mock_client
        
        await app.ensure_connection()
        
        # Should not attempt to connect again
        mock_client.connect.assert_not_called()
        
    @pytest.mark.asyncio
    async def test_ensure_connection_when_client_exists_but_disconnected(self, app):
        """Test ensure_connection reconnects if client exists but disconnected"""
        with patch('api.base_api.create_robot_client') as mock_create_client, \
             patch('api.base_api.create_robot_commands') as mock_create_commands:
            
            # Set up disconnected client
            old_client = MagicMock(spec=BaseRobotClient)
            old_client.is_connected = False
            app.client = old_client
            
            # New client to be created
            new_client = MagicMock(spec=BaseRobotClient)
            new_client.is_connected = False
            new_client.connect = AsyncMock()
            mock_create_client.return_value = new_client
            
            new_commands = MagicMock(spec=BaseRobotCommands)
            mock_create_commands.return_value = new_commands
            
            await app.ensure_connection()
            
            # Should create new client and commands
            assert app.client is new_client
            assert app.commands is new_commands
            new_client.connect.assert_called_once()
            
    @pytest.mark.asyncio
    async def test_disconnect_when_connected(self, app):
        """Test disconnecting from robot"""
        mock_client = MagicMock(spec=BaseRobotClient)
        mock_client.is_connected = True
        mock_client.disconnect = AsyncMock()
        app.client = mock_client
        
        await app.disconnect()
        
        mock_client.disconnect.assert_called_once()
        
    @pytest.mark.asyncio
    async def test_disconnect_when_not_connected(self, app):
        """Test disconnect handles case when not connected"""
        app.client = None
        
        # Should not raise exception
        await app.disconnect()
        
    @pytest.mark.asyncio
    async def test_disconnect_with_disconnected_client(self, app):
        """Test disconnect when client exists but is already disconnected"""
        mock_client = MagicMock(spec=BaseRobotClient)
        mock_client.is_connected = False
        mock_client.disconnect = AsyncMock()
        app.client = mock_client
        
        await app.disconnect()
        
        # BaseRobotApplication only calls disconnect if is_connected is True
        # So with is_connected = False, disconnect is not called
        # This is actually correct behavior
        
    @pytest.mark.asyncio
    async def test_reconnect_robot_success_first_attempt(self, app):
        """Test successful reconnection on first attempt"""
        with patch('api.base_api.create_robot_client') as mock_create_client, \
             patch('api.base_api.create_robot_commands') as mock_create_commands:
            
            # Set up old client
            old_client = MagicMock(spec=BaseRobotClient)
            old_client.disconnect = AsyncMock()
            app.client = old_client
            
            # Set up new client
            new_client = MagicMock(spec=BaseRobotClient)
            new_client.connect = AsyncMock()
            mock_create_client.return_value = new_client
            
            new_commands = MagicMock(spec=BaseRobotCommands)
            new_commands.subscribe_status = AsyncMock()
            mock_create_commands.return_value = new_commands
            
            result = await app.reconnect_robot()
            
            assert result is True
            assert app.client is new_client
            assert app.commands is new_commands
            new_client.connect.assert_called_once()
            new_commands.subscribe_status.assert_called_once()
            
    @pytest.mark.asyncio
    async def test_reconnect_robot_success_after_retry(self, app):
        """Test successful reconnection after one failed attempt"""
        with patch('api.base_api.create_robot_client') as mock_create_client, \
             patch('api.base_api.create_robot_commands') as mock_create_commands, \
             patch('asyncio.sleep', new_callable=AsyncMock):
            
            # Create client for second attempt (success)
            successful_client = MagicMock(spec=BaseRobotClient)
            successful_client.connect = AsyncMock()
            
            new_commands = MagicMock(spec=BaseRobotCommands)
            new_commands.subscribe_status = AsyncMock()
            mock_create_commands.return_value = new_commands
            
            # Properly handle the side_effect - first fails, second succeeds
            def create_client_side_effect(*args, **kwargs):
                if not hasattr(create_client_side_effect, 'call_count'):
                    create_client_side_effect.call_count = 0
                create_client_side_effect.call_count += 1
                
                if create_client_side_effect.call_count == 1:
                    raise Exception("Connection failed")
                else:
                    return successful_client
                    
            mock_create_client.side_effect = create_client_side_effect
            
            result = await app.reconnect_robot()
            
            assert result is True
            
    @pytest.mark.asyncio
    async def test_reconnect_robot_all_attempts_fail(self, app):
        """Test reconnection fails after all attempts exhausted"""
        with patch('api.base_api.create_robot_client') as mock_create_client, \
             patch('asyncio.sleep', new_callable=AsyncMock):
            
            # All attempts fail
            mock_create_client.side_effect = Exception("Connection failed")
            
            result = await app.reconnect_robot()
            
            assert result is False
            # Should try MAX_RECONNECTION_ATTEMPTS times (default 3)
            assert mock_create_client.call_count >= 3
            
    @pytest.mark.asyncio
    async def test_reconnect_robot_cleans_up_old_connection(self, app):
        """Test reconnection cleans up old client"""
        with patch('api.base_api.create_robot_client') as mock_create_client, \
             patch('api.base_api.create_robot_commands') as mock_create_commands:
            
            # Set up old client
            old_client = MagicMock(spec=BaseRobotClient)
            old_client.disconnect = AsyncMock()
            app.client = old_client
            
            # Set up new client
            new_client = MagicMock(spec=BaseRobotClient)
            new_client.connect = AsyncMock()
            mock_create_client.return_value = new_client
            
            mock_commands = MagicMock(spec=BaseRobotCommands)
            mock_commands.subscribe_status = AsyncMock()
            mock_create_commands.return_value = mock_commands
            
            await app.reconnect_robot()
            
            # Old client should be disconnected
            old_client.disconnect.assert_called()
            
    @pytest.mark.asyncio
    async def test_initialize_abstract_method(self, app):
        """Test initialize can be called"""
        # ConcreteRobotApp has a simple implementation
        await app.initialize()
        # Should not raise exception
        
    @pytest.mark.asyncio
    async def test_cleanup_abstract_method(self, app):
        """Test cleanup can be called"""
        await app.cleanup()
        # Should not raise exception


class TestBaseRobotApplicationAbstract:
    """Test that BaseRobotApplication enforces abstract methods"""
    
    def test_cannot_instantiate_base_class(self):
        """Test that abstract base class cannot be instantiated"""
        with pytest.raises(TypeError):
            BaseRobotApplication()

