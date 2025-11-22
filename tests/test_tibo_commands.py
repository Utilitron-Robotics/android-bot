"""
Unit tests for Tibo robot commands
Tests navigation commands, status subscriptions, and waiting logic
"""

import pytest
from unittest.mock import AsyncMock, MagicMock
from adapters.tibo.tibo_commands import TiboCommands


class TestTiboCommands:
    """Test suite for TiboCommands high-level interface"""

    @pytest.fixture
    def mock_client(self):
        """Create a mock client for testing"""
        client = MagicMock()
        client.send_message = AsyncMock()
        client.receive_message = AsyncMock()
        return client

    @pytest.fixture
    def commands(self, mock_client):
        """Create commands instance with mock client"""
        return TiboCommands(mock_client)

    def test_initialization(self, commands, mock_client):
        """Test commands initializes with client"""
        assert commands.client is mock_client

    @pytest.mark.asyncio
    async def test_subscribe_status(self, commands, mock_client):
        """Test status subscription sends correct message"""
        await commands.subscribe_status()

        mock_client.send_message.assert_called_once()
        call_args = mock_client.send_message.call_args[0][0]

        assert call_args["op"] == "subscribe"
        assert call_args["topic"] == "/robot_status"
        assert call_args["type"] == "yutong_assistance/RobotStatus"
        assert call_args["id"] == "get_robot_status"

    @pytest.mark.asyncio
    async def test_unsubscribe_status(self, commands, mock_client):
        """Test status unsubscription sends correct message"""
        await commands.unsubscribe_status()

        mock_client.send_message.assert_called_once()
        call_args = mock_client.send_message.call_args[0][0]

        assert call_args["op"] == "unsubscribe"
        assert call_args["topic"] == "/robot_status"
        assert call_args["id"] == "get_robot_status"

    @pytest.mark.asyncio
    async def test_go_to_with_default_request_id(self, commands, mock_client):
        """Test navigation command with default request ID"""
        await commands.go_to(poi="waypoint1")

        mock_client.send_message.assert_called_once()
        call_args = mock_client.send_message.call_args[0][0]

        assert call_args["op"] == "call_service"
        assert call_args["service"] == "/poi"
        assert call_args["args"]["poi"] == "waypoint1"
        assert call_args["id"] == "nav_waypoint1"

    @pytest.mark.asyncio
    async def test_go_to_with_custom_request_id(self, commands, mock_client):
        """Test navigation command with custom request ID"""
        await commands.go_to(poi="waypoint1", request_id="custom_123")

        call_args = mock_client.send_message.call_args[0][0]
        assert call_args["id"] == "custom_123"
        assert call_args["args"]["poi"] == "waypoint1"

    @pytest.mark.asyncio
    async def test_go_to_different_waypoints(self, commands, mock_client):
        """Test navigation to different waypoints"""
        await commands.go_to(poi="opendroids")
        call_args1 = mock_client.send_message.call_args[0][0]

        await commands.go_to(poi="battery")
        call_args2 = mock_client.send_message.call_args[0][0]

        assert call_args1["args"]["poi"] == "opendroids"
        assert call_args2["args"]["poi"] == "battery"

    @pytest.mark.asyncio
    async def test_cancel_navigation(self, commands, mock_client):
        """Test navigation cancellation sends correct three-step sequence"""
        await commands.cancel_navigation()

        # Should have called send_message 3 times (advertise, publish, unadvertise)
        assert mock_client.send_message.call_count == 3

        # Check first call: advertise
        advertise_call = mock_client.send_message.call_args_list[0][0][0]
        assert advertise_call["op"] == "advertise"
        assert advertise_call["id"] == "cancel_goal"
        assert advertise_call["topic"] == "/move_base/cancel"
        assert advertise_call["type"] == "actionlib_msgs/GoalID"

        # Check second call: publish
        publish_call = mock_client.send_message.call_args_list[1][0][0]
        assert publish_call["op"] == "publish"
        assert publish_call["topic"] == "/move_base/cancel"
        assert publish_call["id"] == "cancel_goal"
        assert publish_call["msg"]["stamp"] == ""
        assert publish_call["msg"]["id"] == ""

        # Check third call: unadvertise
        unadvertise_call = mock_client.send_message.call_args_list[2][0][0]
        assert unadvertise_call["op"] == "unadvertise"
        assert unadvertise_call["id"] == "cancel_goal"
        assert unadvertise_call["topic"] == "/move_base/cancel"

    @pytest.mark.asyncio
    async def test_wait_until_arrival_success_601_to_603(self, commands, mock_client):
        """Test successful navigation (601 moving -> 603 arrived)"""
        mock_client.receive_message.side_effect = [
            {"topic": "/robot_status", "msg": {"nav_status": 601}},  # moving
            {"topic": "/robot_status", "msg": {"nav_status": 601}},  # still moving
            {"topic": "/robot_status", "msg": {"nav_status": 603}},  # arrived
        ]

        result = await commands.wait_until_arrival("test_destination")

        assert result is True
        assert mock_client.receive_message.call_count == 3

    @pytest.mark.asyncio
    async def test_wait_until_arrival_already_at_destination(
        self, commands, mock_client
    ):
        """Test when robot is already at destination (604)"""
        mock_client.receive_message.return_value = {
            "topic": "/robot_status",
            "msg": {"nav_status": 604},
        }

        result = await commands.wait_until_arrival("test_destination")

        assert result is True

    @pytest.mark.asyncio
    async def test_wait_until_arrival_ignores_initial_603(self, commands, mock_client):
        """Test that initial 603 status (idle) is ignored"""
        mock_client.receive_message.side_effect = [
            {"topic": "/robot_status", "msg": {"nav_status": 603}},  # ignore idle
            {"topic": "/robot_status", "msg": {"nav_status": 603}},  # ignore idle
            {"topic": "/robot_status", "msg": {"nav_status": 601}},  # now moving
            {"topic": "/robot_status", "msg": {"nav_status": 603}},  # arrived
        ]

        result = await commands.wait_until_arrival("test_destination")

        assert result is True

    @pytest.mark.asyncio
    async def test_wait_until_arrival_handles_idle_states(self, commands, mock_client):
        """Test handling of idle states (600, 605) before movement"""
        mock_client.receive_message.side_effect = [
            {"topic": "/robot_status", "msg": {"nav_status": 600}},  # idle
            {"topic": "/robot_status", "msg": {"nav_status": 605}},  # standby
            {"topic": "/robot_status", "msg": {"nav_status": 601}},  # moving
            {"topic": "/robot_status", "msg": {"nav_status": 603}},  # arrived
        ]

        result = await commands.wait_until_arrival("test_destination")

        assert result is True

    @pytest.mark.asyncio
    async def test_wait_until_arrival_handles_pause_602(self, commands, mock_client):
        """Test handling of pause/recalculation state (602) during navigation"""
        mock_client.receive_message.side_effect = [
            {"topic": "/robot_status", "msg": {"nav_status": 601}},  # moving
            {
                "topic": "/robot_status",
                "msg": {"nav_status": 602},
            },  # paused/recalculating
            {"topic": "/robot_status", "msg": {"nav_status": 601}},  # moving again
            {"topic": "/robot_status", "msg": {"nav_status": 603}},  # arrived
        ]

        result = await commands.wait_until_arrival("test_destination")

        assert result is True

    @pytest.mark.asyncio
    async def test_wait_until_arrival_unknown_status_fails(self, commands, mock_client):
        """Test navigation fails with unknown status code"""
        mock_client.receive_message.return_value = {
            "topic": "/robot_status",
            "msg": {"nav_status": 999},  # unknown status
        }

        result = await commands.wait_until_arrival("test_destination")

        assert result is False

    @pytest.mark.asyncio
    async def test_wait_until_arrival_skips_non_status_messages(
        self, commands, mock_client
    ):
        """Test that non-status messages are skipped"""
        mock_client.receive_message.side_effect = [
            {"topic": "/other_topic", "msg": {"data": "ignored"}},  # skip
            {"op": "service_response", "result": "success"},  # skip (no topic)
            {"topic": "/robot_status", "msg": {"nav_status": 604}},  # process
        ]

        result = await commands.wait_until_arrival("test_destination")

        assert result is True
        assert mock_client.receive_message.call_count == 3

    @pytest.mark.asyncio
    async def test_wait_until_arrival_with_complex_status_message(
        self, commands, mock_client
    ):
        """Test parsing status from complex message structure"""
        mock_client.receive_message.side_effect = [
            {
                "topic": "/robot_status",
                "msg": {
                    "nav_status": 601,
                    "velocity": [0.5, 0.0],
                    "battery": 85,
                    "position": [1.2, 3.4, 0.0],
                },
            },
            {
                "topic": "/robot_status",
                "msg": {"nav_status": 603, "velocity": [0.0, 0.0], "battery": 84},
            },
        ]

        result = await commands.wait_until_arrival("test_destination")

        assert result is True
