"""
FastAPI server for TourBot
Provides REST endpoints to control robot tours
This is a thin API layer that delegates to the TourBotApplication
"""

from fastapi import FastAPI, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
import os
import logging

from apps.tour_bot import (
    TourBotApplication,
    TourRequest,
    TourStatusResponse,
    WaypointScriptResponse,
)
from config.settings import settings
from config.logging_config import setup_logging

logger = logging.getLogger(__name__)


# Get the directory paths
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UI_DIR = os.path.join(BASE_DIR, "ui")
AUDIO_DIR = os.path.join(BASE_DIR, "assets", "tour_audio")

# Create the tour bot application instance
tour_bot = TourBotApplication()

# FastAPI app
app = FastAPI(title="TourBot API", version="1.0.0")

# Mount static files
if os.path.exists(UI_DIR):
    app.mount("/static", StaticFiles(directory=UI_DIR), name="static")

# Mount audio files
if os.path.exists(AUDIO_DIR):
    app.mount("/audio", StaticFiles(directory=AUDIO_DIR), name="audio")


# Lifecycle management
@app.on_event("startup")
async def startup_event():
    """Initialize API server and tour bot application"""
    # Initialize logging if not already done
    setup_logging(
        log_level=settings.LOG_LEVEL,
        log_dir=settings.LOG_DIR,
        enable_file_logging=settings.ENABLE_FILE_LOGGING,
    )

    # Initialize tour bot application
    await tour_bot.initialize()
    logger.info("✓ TourBot API server ready")


@app.on_event("shutdown")
async def shutdown_event():
    """Clean up resources on server shutdown"""
    await tour_bot.cleanup()
    logger.info("✓ TourBot API server shut down")


# UI Endpoints
@app.get("/")
async def read_root():
    """Serve the main UI"""
    display_path = os.path.join(UI_DIR, "tour_display_v6.html")
    if os.path.exists(display_path):
        return FileResponse(display_path)
    return {"message": "TourBot API is running. UI not found."}


# Tour Control Endpoints
@app.post("/tour/start", response_model=TourStatusResponse)
async def start_tour(tour_request: TourRequest = TourRequest()):
    """
    Start a new tour with the specified waypoints.
    Default waypoints: ["empty_1", "armin", "empty_2", "opendroids", "utilitron", "emerson", "avatar", "end"]
    Returns error if tour is already running
    """
    response = await tour_bot.start_tour(tour_request.waypoints)

    # Convert error responses to HTTP exceptions
    if response.status == "error":
        if "already in progress" in response.message:
            raise HTTPException(status_code=409, detail=response.message)
        else:
            raise HTTPException(status_code=400, detail=response.message)

    return response


@app.get("/tour/status", response_model=TourStatusResponse)
async def get_tour_status():
    """Get current tour status including script for current waypoint"""
    return tour_bot.get_status()


@app.post("/tour/stop")
async def stop_tour():
    """
    Stop the current tour (if running)
    Note: This is a graceful stop - robot will complete current waypoint
    """
    result = await tour_bot.stop_tour()

    if result["status"] == "error":
        raise HTTPException(status_code=400, detail=result["message"])

    return {"message": result["message"]}


@app.get("/tour/script/{waypoint}")
async def get_script(waypoint: str):
    """
    Get the tour script for a specific waypoint
    """
    script = tour_bot.get_waypoint_script(waypoint)

    if script is None:
        raise HTTPException(
            status_code=404, detail=f"No script found for waypoint '{waypoint}'"
        )

    return WaypointScriptResponse(waypoint=waypoint, script=script)


@app.post("/tour/audio-complete")
async def signal_audio_complete():
    """
    Signal that audio playback is complete for current waypoint.
    Frontend calls this after TTS finishes playing.
    """
    return tour_bot.signal_audio_complete()


# Robot Navigation Endpoints
@app.post("/robot/go-to")
async def go_to_waypoint(waypoint: str):
    """
    Send robot to a specific waypoint/POI

    Args:
        waypoint: Name of the waypoint (e.g., "opendroids", "battery", "armin")

    Returns:
        Status message with navigation result
    """
    try:
        # Ensure robot is connected
        await tour_bot.ensure_connection()

        # Subscribe to status if not already subscribed
        if not tour_bot.commands:
            raise HTTPException(
                status_code=500, detail="Robot commands not initialized"
            )

        await tour_bot.commands.subscribe_status()

        # Send navigation command
        logger.info(f"API: Sending robot to waypoint '{waypoint}'")
        await tour_bot.commands.go_to(poi=waypoint)

        # Wait for arrival
        success = await tour_bot.commands.wait_until_arrival(destination_name=waypoint)

        # Unsubscribe from status
        await tour_bot.commands.unsubscribe_status()

        if success:
            return {
                "status": "success",
                "message": f"Robot arrived at {waypoint}",
                "waypoint": waypoint,
            }
        else:
            return {
                "status": "failed",
                "message": f"Robot failed to reach {waypoint}",
                "waypoint": waypoint,
            }

    except ConnectionError as e:
        logger.error(f"Connection error during navigation: {e}")
        raise HTTPException(status_code=503, detail=f"Robot connection error: {str(e)}")
    except Exception as e:
        logger.error(f"Error navigating to waypoint: {e}")
        raise HTTPException(status_code=500, detail=str(e))


# System Endpoints
@app.get("/health")
async def health_check():
    """Health check endpoint"""
    robot_connected = False
    if tour_bot.client and tour_bot.client.is_connected:
        robot_connected = True

    return {
        "status": "healthy",
        "robot_type": settings.ROBOT_TYPE,
        "robot_connected": robot_connected,
        "tour_status": tour_bot.state.status,
    }


@app.get("/config")
async def get_config():
    """Get current configuration settings"""
    return settings.display_config()
