"""
Unit tests for FastAPI tour endpoints
Tests HTTP API routes and responses
"""

import pytest
from fastapi.testclient import TestClient
from unittest.mock import AsyncMock, MagicMock, patch
from api.tour_api import app
from apps.tour_bot import TourStatusResponse


@pytest.fixture
def client():
    """Create FastAPI test client"""
    # Disable startup/shutdown events for testing
    with TestClient(app) as test_client:
        yield test_client


@pytest.fixture
def mock_tour_bot():
    """Create a mock TourBotApplication"""
    mock_bot = MagicMock()
    mock_bot.state = MagicMock()
    mock_bot.state.status = "idle"
    mock_bot.client = None
    return mock_bot


class TestHealthEndpoint:
    """Test suite for /health endpoint"""
    
    def test_health_check_returns_200(self, client):
        """Test health check returns 200 OK"""
        with patch('api.tour_api.tour_bot') as mock_bot:
            mock_bot.client = None
            mock_bot.state.status = "idle"
            
            response = client.get("/health")
            
            assert response.status_code == 200
            
    def test_health_check_response_structure(self, client):
        """Test health check response contains expected fields"""
        with patch('api.tour_api.tour_bot') as mock_bot:
            mock_bot.client = None
            mock_bot.state.status = "idle"
            
            response = client.get("/health")
            data = response.json()
            
            assert "status" in data
            assert "robot_type" in data
            assert "robot_connected" in data
            assert "tour_status" in data
            
    def test_health_check_robot_not_connected(self, client):
        """Test health check shows robot not connected"""
        with patch('api.tour_api.tour_bot') as mock_bot:
            mock_bot.client = None
            mock_bot.state.status = "idle"
            
            response = client.get("/health")
            data = response.json()
            
            assert data["robot_connected"] is False
            
    def test_health_check_robot_connected(self, client):
        """Test health check shows robot connected"""
        with patch('api.tour_api.tour_bot') as mock_bot:
            mock_client = MagicMock()
            mock_client.is_connected = True
            mock_bot.client = mock_client
            mock_bot.state.status = "idle"
            
            response = client.get("/health")
            data = response.json()
            
            assert data["robot_connected"] is True


class TestConfigEndpoint:
    """Test suite for /config endpoint"""
    
    def test_get_config_returns_200(self, client):
        """Test config endpoint returns 200 OK"""
        response = client.get("/config")
        assert response.status_code == 200
        
    def test_get_config_returns_dict(self, client):
        """Test config endpoint returns dictionary"""
        response = client.get("/config")
        data = response.json()
        
        assert isinstance(data, dict)
        assert len(data) > 0
        
    def test_get_config_contains_robot_settings(self, client):
        """Test config contains robot configuration"""
        response = client.get("/config")
        data = response.json()
        
        assert "robot_type" in data
        assert "robot_ip" in data
        assert "robot_port" in data


class TestTourStatusEndpoint:
    """Test suite for /tour/status endpoint"""
    
    def test_get_status_returns_200(self, client):
        """Test status endpoint returns 200 OK"""
        with patch('api.tour_api.tour_bot') as mock_bot:
            mock_bot.get_status.return_value = TourStatusResponse(status="idle")
            
            response = client.get("/tour/status")
            
            assert response.status_code == 200
            
    def test_get_status_returns_tour_status(self, client):
        """Test status endpoint returns tour status"""
        with patch('api.tour_api.tour_bot') as mock_bot:
            mock_bot.get_status.return_value = TourStatusResponse(
                status="running",
                current_waypoint="opendroids",
                waypoints=["a", "b", "c"]
            )
            
            response = client.get("/tour/status")
            data = response.json()
            
            assert data["status"] == "running"
            assert data["current_waypoint"] == "opendroids"
            assert data["waypoints"] == ["a", "b", "c"]


class TestStartTourEndpoint:
    """Test suite for /tour/start endpoint"""
    
    def test_start_tour_default_waypoints(self, client):
        """Test starting tour with default waypoints"""
        with patch('api.tour_api.tour_bot') as mock_bot:
            mock_bot.start_tour = AsyncMock(return_value=TourStatusResponse(
                status="running",
                waypoints=["empty_1", "armin"],
                message="Tour started"
            ))
            
            response = client.post("/tour/start")
            
            assert response.status_code == 200
            data = response.json()
            assert data["status"] == "running"
            
    def test_start_tour_custom_waypoints(self, client):
        """Test starting tour with custom waypoints"""
        with patch('api.tour_api.tour_bot') as mock_bot:
            mock_bot.start_tour = AsyncMock(return_value=TourStatusResponse(
                status="running",
                waypoints=["custom1", "custom2"],
                message="Tour started"
            ))
            
            response = client.post(
                "/tour/start",
                json={"waypoints": ["custom1", "custom2"]}
            )
            
            assert response.status_code == 200
            
    def test_start_tour_already_running_returns_409(self, client):
        """Test starting tour when already running returns 409 Conflict"""
        with patch('api.tour_api.tour_bot') as mock_bot:
            mock_bot.start_tour = AsyncMock(return_value=TourStatusResponse(
                status="error",
                message="Tour already in progress"
            ))
            
            response = client.post("/tour/start")
            
            assert response.status_code == 409
            
    def test_start_tour_empty_waypoints_returns_400(self, client):
        """Test starting tour with empty waypoints returns 400 Bad Request"""
        with patch('api.tour_api.tour_bot') as mock_bot:
            mock_bot.start_tour = AsyncMock(return_value=TourStatusResponse(
                status="error",
                message="Waypoints list cannot be empty"
            ))
            
            response = client.post(
                "/tour/start",
                json={"waypoints": []}
            )
            
            assert response.status_code == 400


class TestStopTourEndpoint:
    """Test suite for /tour/stop endpoint"""
    
    def test_stop_tour_success(self, client):
        """Test successfully stopping a tour"""
        with patch('api.tour_api.tour_bot') as mock_bot:
            mock_bot.stop_tour = AsyncMock(return_value={
                "status": "success",
                "message": "Tour stopped"
            })
            
            response = client.post("/tour/stop")
            
            assert response.status_code == 200
            data = response.json()
            assert data["message"] == "Tour stopped"
            
    def test_stop_tour_not_running_returns_400(self, client):
        """Test stopping tour when none running returns 400"""
        with patch('api.tour_api.tour_bot') as mock_bot:
            mock_bot.stop_tour = AsyncMock(return_value={
                "status": "error",
                "message": "No tour is currently running"
            })
            
            response = client.post("/tour/stop")
            
            assert response.status_code == 400


class TestScriptEndpoint:
    """Test suite for /tour/script/{waypoint} endpoint"""
    
    def test_get_script_success(self, client):
        """Test getting script for valid waypoint"""
        with patch('api.tour_api.tour_bot') as mock_bot:
            mock_bot.get_waypoint_script.return_value = "This is a test script"
            
            response = client.get("/tour/script/test_waypoint")
            
            assert response.status_code == 200
            data = response.json()
            assert data["waypoint"] == "test_waypoint"
            assert data["script"] == "This is a test script"
            
    def test_get_script_not_found_returns_404(self, client):
        """Test getting script for non-existent waypoint returns 404"""
        with patch('api.tour_api.tour_bot') as mock_bot:
            mock_bot.get_waypoint_script.return_value = None
            
            response = client.get("/tour/script/nonexistent")
            
            assert response.status_code == 404
            
    def test_get_script_various_waypoints(self, client):
        """Test getting scripts for various waypoints"""
        with patch('api.tour_api.tour_bot') as mock_bot:
            mock_bot.get_waypoint_script.return_value = "Test script"
            
            waypoints = ["start", "armin", "opendroids", "end"]
            
            for waypoint in waypoints:
                response = client.get(f"/tour/script/{waypoint}")
                assert response.status_code == 200


class TestAudioCompleteEndpoint:
    """Test suite for /tour/audio-complete endpoint"""
    
    def test_audio_complete_signal(self, client):
        """Test signaling audio completion"""
        with patch('api.tour_api.tour_bot') as mock_bot:
            mock_bot.signal_audio_complete.return_value = {
                "message": "Audio completion acknowledged"
            }
            
            response = client.post("/tour/audio-complete")
            
            assert response.status_code == 200
            data = response.json()
            assert "acknowledged" in data["message"].lower()
            
    def test_audio_complete_not_expected(self, client):
        """Test audio completion when not expected"""
        with patch('api.tour_api.tour_bot') as mock_bot:
            mock_bot.signal_audio_complete.return_value = {
                "message": "No audio completion expected at this time"
            }
            
            response = client.post("/tour/audio-complete")
            
            assert response.status_code == 200


class TestRootEndpoint:
    """Test suite for / root endpoint"""
    
    def test_root_endpoint(self, client):
        """Test root endpoint returns UI or message"""
        response = client.get("/")
        
        # Should return either HTML file or JSON message
        assert response.status_code == 200
        
        # Check if it's HTML or JSON
        content_type = response.headers.get("content-type", "")
        assert "html" in content_type or "json" in content_type


class TestRobotNavigationEndpoint:
    """Test suite for /robot/go-to endpoint"""
    
    @pytest.mark.asyncio
    async def test_go_to_waypoint_success(self, client):
        """Test successful navigation to waypoint"""
        with patch('api.tour_api.tour_bot') as mock_bot:
            # Mock successful navigation
            mock_bot.ensure_connection = AsyncMock()
            mock_bot.commands = MagicMock()
            mock_bot.commands.subscribe_status = AsyncMock()
            mock_bot.commands.go_to = AsyncMock()
            mock_bot.commands.wait_until_arrival = AsyncMock(return_value=True)
            mock_bot.commands.unsubscribe_status = AsyncMock()
            
            response = client.post("/robot/go-to?waypoint=opendroids")
            
            assert response.status_code == 200
            data = response.json()
            assert data["status"] == "success"
            assert data["waypoint"] == "opendroids"
            assert "arrived" in data["message"].lower()
            
    @pytest.mark.asyncio
    async def test_go_to_waypoint_failed(self, client):
        """Test failed navigation to waypoint"""
        with patch('api.tour_api.tour_bot') as mock_bot:
            # Mock failed navigation
            mock_bot.ensure_connection = AsyncMock()
            mock_bot.commands = MagicMock()
            mock_bot.commands.subscribe_status = AsyncMock()
            mock_bot.commands.go_to = AsyncMock()
            mock_bot.commands.wait_until_arrival = AsyncMock(return_value=False)
            mock_bot.commands.unsubscribe_status = AsyncMock()
            
            response = client.post("/robot/go-to?waypoint=battery")
            
            assert response.status_code == 200
            data = response.json()
            assert data["status"] == "failed"
            assert data["waypoint"] == "battery"
            assert "failed" in data["message"].lower()
            
    @pytest.mark.asyncio
    async def test_go_to_waypoint_connection_error(self, client):
        """Test navigation with connection error"""
        with patch('api.tour_api.tour_bot') as mock_bot:
            # Mock connection error
            mock_bot.ensure_connection = AsyncMock(side_effect=ConnectionError("Robot offline"))
            mock_bot.commands = MagicMock()
            
            response = client.post("/robot/go-to?waypoint=armin")
            
            assert response.status_code == 503
            data = response.json()
            assert "connection error" in data["detail"].lower()
            
    @pytest.mark.asyncio
    async def test_go_to_waypoint_no_commands(self, client):
        """Test navigation when commands not initialized"""
        with patch('api.tour_api.tour_bot') as mock_bot:
            # Mock no commands available
            mock_bot.ensure_connection = AsyncMock()
            mock_bot.commands = None
            
            response = client.post("/robot/go-to?waypoint=test")
            
            assert response.status_code == 500
            data = response.json()
            assert "not initialized" in data["detail"].lower()
            
    @pytest.mark.asyncio
    async def test_go_to_different_waypoints(self, client):
        """Test navigation to different waypoints"""
        with patch('api.tour_api.tour_bot') as mock_bot:
            mock_bot.ensure_connection = AsyncMock()
            mock_bot.commands = MagicMock()
            mock_bot.commands.subscribe_status = AsyncMock()
            mock_bot.commands.go_to = AsyncMock()
            mock_bot.commands.wait_until_arrival = AsyncMock(return_value=True)
            mock_bot.commands.unsubscribe_status = AsyncMock()
            
            waypoints = ["opendroids", "battery", "armin", "avatar"]
            
            for waypoint in waypoints:
                response = client.post(f"/robot/go-to?waypoint={waypoint}")
                assert response.status_code == 200
                data = response.json()
                assert data["waypoint"] == waypoint

