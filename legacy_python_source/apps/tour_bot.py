"""
Tour Bot Application - Guides robots through predefined waypoints with audio narration
This is a specific application built on top of the base robot API
"""

import asyncio
import logging
import os
from typing import List, Optional
from pydantic import BaseModel

from api.base_api import BaseRobotApplication
from config.settings import settings

logger = logging.getLogger(__name__)


# Request/Response Models
class TourRequest(BaseModel):
    waypoints: List[str] = [
        "empty_1",  # empty office
        "armin",
        "empty_2",  # empty office
        "opendroids",
        "utilitron",
        "emerson",
        "avatar",
        "end",
    ]


class TourStatusResponse(BaseModel):
    status: str  # "idle", "running", "completed", "failed"
    current_waypoint: Optional[str] = None
    waypoints: Optional[List[str]] = None
    message: Optional[str] = None
    script: Optional[str] = None  # Current waypoint's script text


class WaypointScriptResponse(BaseModel):
    waypoint: str
    script: str


# Tour State Management
class TourState:
    """Manages the state of the current tour"""

    def __init__(self):
        self.status = "idle"
        self.current_waypoint = None
        self.current_script = None
        self.waypoints = []
        self.tour_task: Optional[asyncio.Task] = None
        self.audio_complete_event: Optional[asyncio.Event] = None

    def reset(self):
        """Reset tour state to idle"""
        self.status = "idle"
        self.current_waypoint = None
        self.current_script = None
        self.waypoints = []
        self.audio_complete_event = None


class TourBotApplication(BaseRobotApplication):
    """
    Tour Bot Application - Manages robot tours with waypoint navigation and audio narration
    Inherits connection management from BaseRobotApplication
    """

    def __init__(self):
        super().__init__()
        self.state = TourState()

        # Get directory paths for tour assets
        base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self.tour_scripts_dir = os.path.join(base_dir, "assets", "tour_scripts")

    async def initialize(self):
        """Initialize the tour bot application"""
        logger.info("✓ TourBot Application initialized")
        logger.info(f"  Robot type: {settings.ROBOT_TYPE}")
        logger.info(f"  Robot URI: {settings.get_robot_uri()}")
        logger.info("  (Connection will be established on-demand)")

    async def cleanup(self):
        """Clean up tour bot resources"""
        # Stop any running tour
        if self.state.tour_task and not self.state.tour_task.done():
            self.state.tour_task.cancel()

        # Disconnect from robot
        await self.disconnect()
        logger.info("✓ TourBot Application cleaned up")

    def get_waypoint_script(self, waypoint: str) -> Optional[str]:
        """
        Read the tour script for a specific waypoint

        Args:
            waypoint: Name of the waypoint

        Returns:
            Script content as string, or None if file doesn't exist
        """
        script_path = os.path.join(self.tour_scripts_dir, f"{waypoint}.txt")

        if not os.path.exists(script_path):
            return None

        try:
            with open(script_path, "r", encoding="utf-8") as f:
                return f.read().strip()
        except Exception as e:
            logger.error(f"Error reading script for waypoint '{waypoint}': {e}")
            return None

    async def start_tour(self, waypoints: List[str]) -> TourStatusResponse:
        """
        Start a new tour with the specified waypoints

        Args:
            waypoints: List of waypoint names to visit

        Returns:
            TourStatusResponse with status and waypoints
        """
        if self.state.status == "running":
            logger.warning("Tour start rejected - tour already in progress")
            return TourStatusResponse(
                status="error",
                message="Tour already in progress. Wait for completion or stop current tour.",
            )

        if not waypoints:
            logger.error("Tour start rejected - empty waypoints list")
            return TourStatusResponse(
                status="error", message="Waypoints list cannot be empty"
            )

        logger.info(f"🎬 Tour start requested with {len(waypoints)} waypoints")

        # Start tour as an asyncio task
        self.state.tour_task = asyncio.create_task(self._run_tour_background(waypoints))

        return TourStatusResponse(
            status="running",
            waypoints=waypoints,
            message="Tour started successfully",
        )

    async def stop_tour(self) -> dict:
        """
        Stop the current tour (if running)

        Returns:
            Dictionary with status message
        """
        if self.state.status != "running":
            logger.warning("Tour stop rejected - no tour running")
            return {"status": "error", "message": "No tour is currently running"}

        logger.info("⛔ Tour stop requested")

        # Cancel robot navigation first (stop the robot from moving)
        if self.commands and self.client and self.client.is_connected:
            try:
                await self.commands.cancel_navigation()
                logger.info("Robot navigation cancelled")
            except Exception as e:
                logger.warning(f"Failed to cancel robot navigation: {e}")

        # Cancel the tour task
        if self.state.tour_task and not self.state.tour_task.done():
            self.state.tour_task.cancel()

        self.state.reset()
        logger.info("Tour stopped successfully")
        return {"status": "success", "message": "Tour stopped"}

    def get_status(self) -> TourStatusResponse:
        """
        Get current tour status including script for current waypoint

        Returns:
            TourStatusResponse with current status
        """
        return TourStatusResponse(
            status=self.state.status,
            current_waypoint=self.state.current_waypoint,
            waypoints=self.state.waypoints if self.state.status == "running" else None,
            script=self.state.current_script,
        )

    def signal_audio_complete(self) -> dict:
        """
        Signal that audio playback is complete for current waypoint
        Frontend calls this after TTS finishes playing

        Returns:
            Dictionary with acknowledgment message
        """
        if self.state.audio_complete_event:
            logger.debug("Audio completion signal received from frontend")
            self.state.audio_complete_event.set()
            return {"message": "Audio completion acknowledged"}
        else:
            logger.debug("Audio completion signal received but not expected")
            return {"message": "No audio completion expected at this time"}

    async def _run_tour_background(self, waypoints: List[str]):
        """
        Execute tour in background (internal method)

        Args:
            waypoints: List of waypoint names to visit
        """
        try:
            logger.info("=" * 60)
            logger.info("🚀 TOUR STARTING")
            logger.info(f"Waypoints: {waypoints}")
            logger.info("=" * 60)

            self.state.status = "running"
            self.state.waypoints = waypoints

            # Ensure robot connection before starting tour
            logger.info("Connecting to robot...")
            await self.ensure_connection()
            logger.info("Robot connected successfully")

            # Subscribe to status updates
            logger.info("Subscribing to robot status...")
            await self.commands.subscribe_status()
            logger.info("Subscribed to status")

            # Check and log battery level at tour start
            battery = await self.commands.get_battery_level(timeout=3.0)
            if battery is not None:
                logger.info(f"🔋 Battery level at tour start: {battery}%")
                if battery < 20:
                    logger.warning(f"⚠️ LOW BATTERY WARNING: {battery}% - Tour may fail!")
                elif battery < 40:
                    logger.warning(f"⚠️ Battery is low: {battery}% - Monitor closely")
            else:
                logger.warning("⚠️ Could not read battery level")

            # Play START script FIRST (without navigation)
            await self._play_script_at_location("start", "Playing introduction")

            # Navigate through waypoints (including 'end' which returns to home)
            for i, marker in enumerate(waypoints, 1):
                self.state.current_waypoint = marker
                self.state.current_script = None  # Clear script until we arrive

                logger.info("=" * 60)
                logger.info(f"📍 Waypoint {i}/{len(waypoints)}: {marker}")
                logger.info("=" * 60)

                # Navigate to waypoint with retry logic
                success = await self._navigate_to_waypoint(marker)

                if not success:
                    self.state.status = "failed"
                    self.state.current_script = None
                    logger.error(f"❌ Tour FAILED at waypoint {marker}")
                    await self.commands.unsubscribe_status()
                    return

                # Play script after arriving at waypoint
                await self._play_script_at_location(marker, f"At {marker}")

            await self.commands.unsubscribe_status()

            # Disconnect from robot after tour completion to prevent idle timeout
            await self.disconnect()
            logger.info("Disconnected from robot after tour completion")

            self.state.status = "completed"
            self.state.current_waypoint = None
            self.state.current_script = None
            logger.info("=" * 60)
            logger.info("✅ TOUR COMPLETED")
            logger.info("=" * 60)

        except asyncio.CancelledError:
            self.state.reset()
            # Disconnect on cancellation
            await self.disconnect()
            logger.warning("⛔ Tour cancelled by user")
            raise
        except (ConnectionError, ConnectionResetError) as e:
            self.state.reset()
            # Disconnect on connection error
            await self.disconnect()
            error_type = type(e).__name__
            logger.critical(f"❌ CONNECTION ERROR ({error_type}): {e}")
            logger.error("Check robot connection and network stability")
        except Exception as e:
            self.state.reset()
            # Disconnect on any unexpected error
            await self.disconnect()
            error_type = type(e).__name__
            logger.critical(f"❌ UNEXPECTED ERROR ({error_type}): {e}")
            import traceback

            logger.debug(traceback.format_exc())

    async def _navigate_to_waypoint(self, marker: str) -> bool:
        """
        Navigate to a waypoint with automatic retry on connection failure

        Args:
            marker: Waypoint name

        Returns:
            True if navigation successful, False otherwise
        """
        try:
            logger.info(f"Sending navigation command to {marker}...")
            await self.commands.go_to(poi=marker, request_id=f"marker_{marker}")

            logger.info(f"Waiting for arrival at {marker}...")
            success = await self.commands.wait_until_arrival(destination_name=marker)

            if not success:
                return False

            logger.info(f"✓ Reached {marker}")
            return True

        except (ConnectionError, ConnectionResetError, Exception) as e:
            # Connection lost - attempt to reconnect
            error_type = type(e).__name__
            logger.warning(f"⚠️  Connection error during navigation: {error_type}: {e}")

            # Try to reconnect
            reconnected = await self.reconnect_robot()

            if not reconnected:
                return False

            # After reconnection, retry the current waypoint
            logger.info(f"🔄 Retrying waypoint {marker}...")
            try:
                await self.commands.go_to(
                    poi=marker, request_id=f"marker_{marker}_retry"
                )
                success = await self.commands.wait_until_arrival(
                    destination_name=marker
                )

                if not success:
                    return False

                logger.info(f"✓ Reached {marker} after reconnection")
                return True

            except Exception as retry_error:
                logger.error(f"❌ Retry failed: {retry_error}")
                return False

    async def _play_script_at_location(self, waypoint: str, log_message: str):
        """
        Load and play script at a waypoint

        Args:
            waypoint: Waypoint name
            log_message: Message to log when playing script
        """
        script = self.get_waypoint_script(waypoint)

        if script:
            logger.info("=" * 60)
            logger.info(f"📍 {log_message}...")
            logger.info("=" * 60)
            logger.info(f"📜 Script loaded ({len(script)} chars): {script[:50]}...")

            # Set up event BEFORE setting the script in state
            self.state.audio_complete_event = asyncio.Event()

            # Set script in state - this triggers frontend to play audio
            self.state.current_script = script

            logger.info("🔊 Waiting for audio playback to complete...")

            # Wait for frontend to signal audio completion (with timeout)
            try:
                await asyncio.wait_for(
                    self.state.audio_complete_event.wait(),
                    timeout=settings.AUDIO_PLAYBACK_TIMEOUT,
                )
                logger.info("✓ Audio playback complete")
            except asyncio.TimeoutError:
                logger.warning(
                    f"⚠️  Audio playback timeout after {settings.AUDIO_PLAYBACK_TIMEOUT}s - continuing"
                )

            self.state.audio_complete_event = None
            self.state.current_script = None
        else:
            logger.warning(f"⚠️  No script found for {waypoint}")
