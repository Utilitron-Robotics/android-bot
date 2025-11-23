"""
Unit tests for TourBot application
Tests core application logic, tour execution, and waypoint management
"""

import pytest
import asyncio
import os
from unittest.mock import AsyncMock, MagicMock, patch
from apps.tour_bot import TourBotApplication, TourRequest, TourStatusResponse


class TestTourBotApplication:
    """Test suite for TourBotApplication"""
    
    @pytest.fixture
    def tour_bot(self):
        """Create a TourBotApplication instance for testing"""
        return TourBotApplication()
        
    def test_initialization(self, tour_bot):
        """Test application initializes correctly"""
        assert tour_bot.state is not None
        assert tour_bot.state.status == "idle"
        assert tour_bot.client is None
        assert tour_bot.commands is None
        
    def test_tour_scripts_directory_exists(self, tour_bot):
        """Test tour scripts directory is configured"""
        assert tour_bot.tour_scripts_dir is not None
        assert "tour_scripts" in tour_bot.tour_scripts_dir
        
    @pytest.mark.asyncio
    async def test_initialize(self, tour_bot):
        """Test application initialization"""
        # Should not raise exception
        await tour_bot.initialize()
        
    def test_get_waypoint_script_start(self, tour_bot):
        """Test reading the start script file"""
        script = tour_bot.get_waypoint_script("start")
        
        # The start.txt file should exist in the repo
        assert script is not None
        assert isinstance(script, str)
        assert len(script) > 0
        
    def test_get_waypoint_script_missing(self, tour_bot):
        """Test handling missing script file"""
        script = tour_bot.get_waypoint_script("nonexistent_waypoint_12345")
        assert script is None
        
    def test_get_waypoint_script_various_waypoints(self, tour_bot):
        """Test reading various waypoint scripts"""
        waypoints_to_test = ["start", "end", "armin", "opendroids"]
        
        for waypoint in waypoints_to_test:
            script = tour_bot.get_waypoint_script(waypoint)
            # Most should exist, but we test None handling regardless
            if script is not None:
                assert isinstance(script, str)
                
    def test_get_status_idle(self, tour_bot):
        """Test status response when idle"""
        status = tour_bot.get_status()
        
        assert isinstance(status, TourStatusResponse)
        assert status.status == "idle"
        assert status.current_waypoint is None
        assert status.waypoints is None
        assert status.script is None
        
    def test_get_status_running(self, tour_bot):
        """Test status response when running"""
        tour_bot.state.status = "running"
        tour_bot.state.current_waypoint = "opendroids"
        tour_bot.state.waypoints = ["a", "b", "c"]
        tour_bot.state.current_script = "Test script"
        
        status = tour_bot.get_status()
        
        assert status.status == "running"
        assert status.current_waypoint == "opendroids"
        assert status.waypoints == ["a", "b", "c"]
        assert status.script == "Test script"
        
    @pytest.mark.asyncio
    async def test_start_tour_empty_waypoints(self, tour_bot):
        """Test starting tour with empty waypoints list"""
        response = await tour_bot.start_tour([])
        
        assert response.status == "error"
        assert "empty" in response.message.lower()
        assert tour_bot.state.status == "idle"
        
    @pytest.mark.asyncio
    async def test_start_tour_already_running(self, tour_bot):
        """Test starting tour when one is already running"""
        tour_bot.state.status = "running"
        
        response = await tour_bot.start_tour(["waypoint1"])
        
        assert response.status == "error"
        assert "already in progress" in response.message.lower()
        
    @pytest.mark.asyncio
    async def test_start_tour_success(self, tour_bot):
        """Test successfully starting a tour"""
        waypoints = ["waypoint1", "waypoint2"]
        
        response = await tour_bot.start_tour(waypoints)
        
        assert response.status == "running"
        assert response.waypoints == waypoints
        assert "started" in response.message.lower()
        assert tour_bot.state.tour_task is not None
        
        # Clean up the background task
        if tour_bot.state.tour_task and not tour_bot.state.tour_task.done():
            tour_bot.state.tour_task.cancel()
            try:
                await tour_bot.state.tour_task
            except asyncio.CancelledError:
                pass
                
    @pytest.mark.asyncio
    async def test_stop_tour_not_running(self, tour_bot):
        """Test stopping tour when none is running"""
        result = await tour_bot.stop_tour()
        
        assert result["status"] == "error"
        assert "no tour is currently running" in result["message"].lower()
        
    @pytest.mark.asyncio
    async def test_stop_tour_success(self, tour_bot):
        """Test stopping a running tour"""
        # Set up running state
        tour_bot.state.status = "running"
        mock_task = MagicMock()
        mock_task.done = MagicMock(return_value=False)  # Not AsyncMock - done() is sync
        mock_task.cancel = MagicMock()  # Also sync
        tour_bot.state.tour_task = mock_task
        
        result = await tour_bot.stop_tour()
        
        assert result["status"] == "success"
        assert "stopped" in result["message"].lower()
        assert tour_bot.state.status == "idle"
        mock_task.cancel.assert_called_once()
        
    def test_signal_audio_complete_with_event(self, tour_bot):
        """Test audio completion signal with event set"""
        event = asyncio.Event()
        tour_bot.state.audio_complete_event = event
        
        result = tour_bot.signal_audio_complete()
        
        assert "acknowledged" in result["message"].lower()
        assert event.is_set()
        
    def test_signal_audio_complete_without_event(self, tour_bot):
        """Test audio completion signal when not expected"""
        result = tour_bot.signal_audio_complete()
        
        assert "no audio completion expected" in result["message"].lower()
        
    @pytest.mark.asyncio
    async def test_cleanup_stops_tour(self, tour_bot):
        """Test cleanup stops running tour"""
        # Set up running tour
        tour_bot.state.status = "running"
        mock_task = MagicMock()
        mock_task.done = MagicMock(return_value=False)  # Sync method
        mock_task.cancel = MagicMock()  # Sync method
        tour_bot.state.tour_task = mock_task
        
        # Mock client
        tour_bot.client = MagicMock()
        tour_bot.client.is_connected = True
        tour_bot.client.disconnect = AsyncMock()
        
        await tour_bot.cleanup()
        
        mock_task.cancel.assert_called_once()
        
    @pytest.mark.asyncio
    async def test_cleanup_disconnects_client(self, tour_bot):
        """Test cleanup disconnects from robot"""
        mock_client = MagicMock()
        mock_client.is_connected = True
        mock_client.disconnect = AsyncMock()
        tour_bot.client = mock_client
        
        await tour_bot.cleanup()
        
        mock_client.disconnect.assert_called_once()


class TestTourRequest:
    """Test suite for TourRequest model"""
    
    def test_default_waypoints(self):
        """Test default waypoints list"""
        request = TourRequest()
        
        assert len(request.waypoints) > 0
        assert "armin" in request.waypoints
        assert "opendroids" in request.waypoints
        assert "end" in request.waypoints
        
    def test_custom_waypoints(self):
        """Test custom waypoints list"""
        custom = ["waypoint1", "waypoint2"]
        request = TourRequest(waypoints=custom)
        
        assert request.waypoints == custom


class TestTourStatusResponse:
    """Test suite for TourStatusResponse model"""
    
    def test_status_field(self):
        """Test status field is required"""
        response = TourStatusResponse(status="idle")
        assert response.status == "idle"
        
    def test_optional_fields(self):
        """Test optional fields default to None"""
        response = TourStatusResponse(status="idle")
        
        assert response.current_waypoint is None
        assert response.waypoints is None
        assert response.message is None
        assert response.script is None
        
    def test_all_fields(self):
        """Test creating response with all fields"""
        response = TourStatusResponse(
            status="running",
            current_waypoint="test",
            waypoints=["a", "b"],
            message="Test message",
            script="Test script"
        )
        
        assert response.status == "running"
        assert response.current_waypoint == "test"
        assert response.waypoints == ["a", "b"]
        assert response.message == "Test message"
        assert response.script == "Test script"


class TestNavigateToWaypoint:
    """Test suite for _navigate_to_waypoint method"""
    
    @pytest.mark.asyncio
    async def test_navigate_success(self):
        """Test successful navigation to waypoint"""
        tour_bot = TourBotApplication()
        
        # Mock commands
        mock_commands = MagicMock()
        mock_commands.go_to = AsyncMock()
        mock_commands.wait_until_arrival = AsyncMock(return_value=True)
        tour_bot.commands = mock_commands
        
        result = await tour_bot._navigate_to_waypoint("test_marker")
        
        assert result is True
        mock_commands.go_to.assert_called_once_with(
            poi="test_marker", 
            request_id="marker_test_marker"
        )
        mock_commands.wait_until_arrival.assert_called_once_with(
            destination_name="test_marker"
        )
        
    @pytest.mark.asyncio
    async def test_navigate_arrival_failure(self):
        """Test navigation when arrival fails"""
        tour_bot = TourBotApplication()
        
        mock_commands = MagicMock()
        mock_commands.go_to = AsyncMock()
        mock_commands.wait_until_arrival = AsyncMock(return_value=False)
        tour_bot.commands = mock_commands
        
        result = await tour_bot._navigate_to_waypoint("test_marker")
        
        assert result is False


class TestPlayScriptAtLocation:
    """Test suite for _play_script_at_location method"""
    
    @pytest.mark.asyncio
    async def test_play_script_success(self):
        """Test playing script at location"""
        tour_bot = TourBotApplication()
        
        # Mock get_waypoint_script to return a script
        with patch.object(tour_bot, 'get_waypoint_script', return_value="Test script"):
            # Create event manually to test timeout path
            await tour_bot._play_script_at_location("test_waypoint", "Test message")
            
            # Verify script was set (then cleared)
            assert tour_bot.state.current_script is None  # Cleared after
            
    @pytest.mark.asyncio
    async def test_play_script_missing(self):
        """Test handling missing script"""
        tour_bot = TourBotApplication()
        
        with patch.object(tour_bot, 'get_waypoint_script', return_value=None):
            # Should not raise exception
            await tour_bot._play_script_at_location("missing", "Test")
            
            assert tour_bot.state.current_script is None

