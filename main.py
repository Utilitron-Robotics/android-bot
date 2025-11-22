"""
Tour Bot - FastAPI Server Entry Point
Launches the TourBot REST API for controlling robot tours
"""

import uvicorn
from config.settings import settings
from config.logging_config import setup_logging, get_logger

if __name__ == "__main__":
    # Initialize logging first
    setup_logging(
        log_level=settings.LOG_LEVEL,
        log_dir=settings.LOG_DIR,
        enable_file_logging=settings.ENABLE_FILE_LOGGING
    )
    
    logger = get_logger(__name__)
    
    logger.info("🤖 TourBot Server Starting")
    logger.info(f"Robot Type: {settings.ROBOT_TYPE}")
    logger.info(f"Robot URI: {settings.get_robot_uri()}")
    logger.info(f"API: http://{settings.API_HOST}:{settings.API_PORT}")
    
    uvicorn.run(
        "api.tour_api:app",
        host=settings.API_HOST,
        port=settings.API_PORT,
        reload=True
    )
