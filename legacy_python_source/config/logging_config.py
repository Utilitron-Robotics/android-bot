"""
Logging configuration for TourBot
Sets up structured logging with proper formatting and handlers
"""

import logging
import logging.handlers
import os
from datetime import datetime
from pathlib import Path


class TourBotFormatter(logging.Formatter):
    """Custom formatter with colors for console output"""
    
    # ANSI color codes
    COLORS = {
        'DEBUG': '\033[36m',      # Cyan
        'INFO': '\033[32m',       # Green
        'WARNING': '\033[33m',    # Yellow
        'ERROR': '\033[31m',      # Red
        'CRITICAL': '\033[35m',   # Magenta
    }
    RESET = '\033[0m'
    
    def __init__(self, use_color=True):
        super().__init__()
        self.use_color = use_color
    
    def format(self, record):
        # Add color to levelname for console
        if self.use_color:
            levelname_color = self.COLORS.get(record.levelname, '')
            record.levelname_colored = f"{levelname_color}{record.levelname:8s}{self.RESET}"
        else:
            record.levelname_colored = f"{record.levelname:8s}"
        
        # Format: [HH:MM:SS] LEVEL    module - message
        log_format = "[%(asctime)s] %(levelname_colored)s %(name)s - %(message)s"
        formatter = logging.Formatter(log_format, datefmt='%H:%M:%S')
        return formatter.format(record)


class FileFormatter(logging.Formatter):
    """Formatter for file output (no colors)"""
    
    def format(self, record):
        # Format: [YYYY-MM-DD HH:MM:SS] LEVEL module - message
        log_format = "[%(asctime)s] %(levelname)-8s %(name)s - %(message)s"
        formatter = logging.Formatter(log_format, datefmt='%Y-%m-%d %H:%M:%S')
        return formatter.format(record)


def setup_logging(
    log_level: str = "INFO",
    log_dir: str = "logs",
    enable_file_logging: bool = True
):
    """
    Configure logging for the entire application
    
    Args:
        log_level: Minimum log level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
        log_dir: Directory for log files
        enable_file_logging: Whether to write logs to files
    """
    
    # Create logs directory if it doesn't exist
    if enable_file_logging:
        Path(log_dir).mkdir(parents=True, exist_ok=True)
    
    # Get root logger
    root_logger = logging.getLogger()
    root_logger.setLevel(logging.DEBUG)  # Capture everything, handlers will filter
    
    # Clear any existing handlers
    root_logger.handlers.clear()
    
    # Console Handler - colored output
    console_handler = logging.StreamHandler()
    console_handler.setLevel(getattr(logging, log_level.upper()))
    console_handler.setFormatter(TourBotFormatter(use_color=True))
    root_logger.addHandler(console_handler)
    
    if enable_file_logging:
        # File Handler - All logs (INFO and above)
        app_log_file = os.path.join(log_dir, "app.log")
        app_handler = logging.handlers.RotatingFileHandler(
            app_log_file,
            maxBytes=10 * 1024 * 1024,  # 10 MB
            backupCount=5,
            encoding='utf-8'
        )
        app_handler.setLevel(logging.INFO)
        app_handler.setFormatter(FileFormatter())
        root_logger.addHandler(app_handler)
        
        # Error Handler - Only errors and above
        error_log_file = os.path.join(log_dir, "error.log")
        error_handler = logging.handlers.RotatingFileHandler(
            error_log_file,
            maxBytes=10 * 1024 * 1024,  # 10 MB
            backupCount=5,
            encoding='utf-8'
        )
        error_handler.setLevel(logging.ERROR)
        error_handler.setFormatter(FileFormatter())
        root_logger.addHandler(error_handler)
        
        # Tour Handler - Tour-specific events
        tour_log_file = os.path.join(log_dir, "tour.log")
        tour_handler = logging.handlers.RotatingFileHandler(
            tour_log_file,
            maxBytes=5 * 1024 * 1024,  # 5 MB
            backupCount=10,
            encoding='utf-8'
        )
        tour_handler.setLevel(logging.INFO)
        tour_handler.setFormatter(FileFormatter())
        # Only log from tour-related modules
        tour_handler.addFilter(lambda record: 'tour' in record.name.lower() or 'waypoint' in record.getMessage().lower())
        root_logger.addHandler(tour_handler)
    
    # Reduce noise from third-party libraries
    logging.getLogger("websockets").setLevel(logging.WARNING)
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)
    logging.getLogger("uvicorn.error").setLevel(logging.INFO)
    
    # Log startup message
    logger = logging.getLogger(__name__)
    logger.info("=" * 60)
    logger.info("TourBot logging initialized")
    logger.info(f"Log level: {log_level}")
    if enable_file_logging:
        logger.info(f"Log directory: {log_dir}")
    logger.info("=" * 60)


def get_logger(name: str) -> logging.Logger:
    """
    Get a logger instance for a module
    
    Args:
        name: Module name (typically __name__)
        
    Returns:
        Configured logger instance
    """
    return logging.getLogger(name)

