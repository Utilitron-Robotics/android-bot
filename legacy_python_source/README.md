# 🤖 TourBot

A modular robot tour application that guides robots through predefined waypoints with audio narration. Built with a clean architecture that supports multiple robot platforms.

## ✨ Why TourBot is Special

**Write Once, Run on Any Robot**
```
┌─────────────────────────────────────────────────┐
│ Your Application (Tour, Security, Concierge)    │
│ ✓ Write business logic once                     │
│ ✓ Inherits connection & navigation infrastructure│
│ ✓ Works with ANY robot automatically            │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│ Just change .env:                                │
│ ROBOT_TYPE=tibo    → Uses Tibo robot            │
│ ROBOT_TYPE=lekiwi  → Uses Lekiwi robot          │
│ ROBOT_TYPE=xlerobot → Uses Xlerobot             │
└─────────────────────────────────────────────────┘
```

**Modular Benefits:**
- 🔌 **Plug & Play** - Add new robots without modifying apps
- 🔁 **Reusable** - Navigation functions work across all robots
- 🛡️ **Reliable** - Automatic reconnection and error handling
- 🎯 **Focused** - Write only application-specific logic

## 📐 Architecture

TourBot follows a layered architecture for maximum modularity and reusability:

```
┌─────────────────────────────────────────────────────┐
│  Applications Layer (apps/)                          │
│  ├─ tour_bot.py       - Tour guide application      │
│  ├─ concierge_bot.py  - (Future) Guest assistance   │
│  └─ security_bot.py   - (Future) Security patrol    │
└──────────────────┬──────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────┐
│  Base API Layer (api/)                               │
│  ├─ base_api.py       - BaseRobotApplication        │
│  ├─ base_robot.py     - Abstract interfaces         │
│  ├─ robot_factory.py  - Adapter selection           │
│  └─ tour_api.py       - REST API endpoints          │
└──────────────────┬──────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────┐
│  Adapters Layer (adapters/)                          │
│  ├─ tibo/             - Tibo robot adapter          │
│  ├─ lekiwi/           - (Future) Lekiwi adapter     │
│  └─ xlerobot/         - (Future) Xlerobot adapter   │
└──────────────────┬──────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────┐
│  Hardware Layer                                      │
│  └─ Robot Hardware (WebSocket/ROS Bridge)           │
└─────────────────────────────────────────────────────┘
```

### Key Design Principles

1. **Platform Agnostic**: Applications use abstract interfaces, not hardware-specific code
2. **Inheritance-Based Reusability**: All apps inherit from `BaseRobotApplication` for common functionality
3. **Adapter Pattern**: Each robot type has its own adapter implementing the base interface
4. **Factory Pattern**: Robot selection happens at runtime via configuration
5. **Separation of Concerns**: Clear boundaries between hardware, API, and application logic

### What You Get "For Free"

When you create a new application by inheriting from `BaseRobotApplication`, you automatically get:
- ✅ **Connection Management** - Automatic connection establishment with lazy loading
- ✅ **Reconnection Logic** - Automatic retry on connection failures with configurable attempts
- ✅ **Multi-Robot Support** - Works with any robot adapter (Tibo, Lekiwi, Xlerobot, etc.)
- ✅ **Navigation Commands** - High-level methods like `go_to()`, `wait_until_arrival()`
- ✅ **Status Monitoring** - Subscribe to robot status updates
- ✅ **Logging Infrastructure** - Structured logging with rotating files
- ✅ **Error Handling** - Consistent error handling across all operations

## 🧩 Core Concepts

### Three Key Abstractions

1. **BaseRobotClient** (`api/base_robot.py`)
   - Low-level communication protocol
   - Methods: `connect()`, `disconnect()`, `send_message()`, `receive_message()`
   - Hardware-specific implementations (WebSocket, REST, gRPC, etc.)

2. **BaseRobotCommands** (`api/base_robot.py`)
   - High-level robot operations
   - Methods: `go_to()`, `wait_until_arrival()`, `subscribe_status()`
   - Robot-specific implementations (different navigation protocols)

3. **BaseRobotApplication** (`api/base_api.py`)
   - Application infrastructure
   - Methods: `ensure_connection()`, `reconnect_robot()`
   - Inheritable base for all robot applications

### How They Work Together

```
Your Application (e.g., SecurityBot)
         ↓ inherits from
  BaseRobotApplication
         ↓ uses
  BaseRobotCommands (interface)
         ↓ implemented by
  Robot-Specific Commands (e.g., TiboCommands)
         ↓ uses
  BaseRobotClient (interface)
         ↓ implemented by
  Robot-Specific Client (e.g., TiboClient)
         ↓ connects to
  Physical Robot Hardware
```

**Result**: Write your application once, works with any robot!

## 🚀 Quick Start

### Prerequisites

- Python 3.9+
- Robot with WebSocket/ROS Bridge support
- Network access to robot

### Installation

```bash
# Clone the repository
git clone <your-repo-url>
cd tour-bot

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
```

### Configuration

Create a `.env` file in the project root:

```env
# Robot Configuration
ROBOT_TYPE=tibo           # Robot type: tibo, lekiwi, xlerobot
ROBOT_IP=192.168.1.100    # Robot IP address
ROBOT_PORT=9090           # WebSocket port

# API Configuration
API_HOST=0.0.0.0          # API server host
API_PORT=8000             # API server port

# Timeouts (seconds)
CONNECTION_TIMEOUT=5
NAVIGATION_TIMEOUT=300
AUDIO_PLAYBACK_TIMEOUT=120

# Reconnection Settings
MAX_RECONNECTION_ATTEMPTS=3
RECONNECTION_DELAY=2

# WebSocket Keepalive Settings (for network stability)
WS_PING_INTERVAL=20        # Send ping every N seconds
WS_PING_TIMEOUT=120        # Wait N seconds for pong response

# Logging Configuration
LOG_LEVEL=INFO              # DEBUG, INFO, WARNING, ERROR, CRITICAL
LOG_DIR=logs                # Directory for log files
ENABLE_FILE_LOGGING=true    # Enable/disable file logging
```

### Running the Application

```bash
# Start the API server
python main.py

# The server will be available at http://localhost:8000
# Visit http://localhost:8000 for the web UI
# API documentation at http://localhost:8000/docs
```

## 📁 Project Structure

```
tour-bot/
├── api/                      # Base API Layer
│   ├── base_robot.py        # Abstract robot interfaces
│   ├── base_api.py          # Base application infrastructure
│   ├── robot_factory.py     # Factory for creating adapters
│   └── tour_api.py          # FastAPI REST endpoints
│
├── adapters/                # Hardware Adapters
│   └── tibo/
│       ├── tibo_client.py   # WebSocket client
│       └── tibo_commands.py # High-level commands
│
├── apps/                    # Applications (built on base API)
│   └── tour_bot.py          # Tour guide application
│
├── config/                  # Configuration
│   ├── settings.py          # Settings management
│   └── logging_config.py    # Logging configuration
│
├── assets/                  # Application assets
│   ├── tour_scripts/        # Tour narration scripts
│   └── tour_audio/          # Audio files
│
├── ui/                      # Web interfaces
│   └── tour_display_v5.html # Tour control UI
│
├── main.py                  # Application entry point
├── .env                     # Configuration (create from example)
└── README.md
```

## 🔌 API Endpoints

### Tour Control

- `POST /tour/start` - Start a tour with waypoints
- `GET /tour/status` - Get current tour status
- `POST /tour/stop` - Stop the current tour
- `GET /tour/script/{waypoint}` - Get script for a waypoint
- `POST /tour/audio-complete` - Signal audio completion

### System

- `GET /health` - Health check and connection status
- `GET /config` - View current configuration
- `GET /` - Web UI

### Example: Start a Tour

```bash
curl -X POST http://localhost:8000/tour/start \
  -H "Content-Type: application/json" \
  -d '{
    "waypoints": ["start", "opendroids", "utilitron", "end"]
  }'
```

## 🔧 Creating a New Application

The modular architecture makes it easy to create new robot applications. All applications inherit from `BaseRobotApplication`, which provides reusable infrastructure for robot control.

### The BaseRobotApplication Class

Located in `api/base_api.py`, this abstract base class provides:

**Core Methods:**
- `ensure_connection()` - Establishes connection to robot (lazy loading)
- `disconnect()` - Closes robot connection
- `reconnect_robot()` - Attempts reconnection with automatic retry

**Properties:**
- `self.client` - Low-level robot client (send/receive messages)
- `self.commands` - High-level command interface (go_to, wait_until_arrival, etc.)

**Abstract Methods (you must implement):**
- `initialize()` - Application-specific initialization
- `cleanup()` - Application-specific cleanup

### Example: Concierge Bot

```python
# apps/concierge_bot.py
from api.base_api import BaseRobotApplication
import logging

logger = logging.getLogger(__name__)

class ConciergeApplication(BaseRobotApplication):
    """Concierge bot for greeting and assisting guests"""
    
    async def initialize(self):
        logger.info("✓ Concierge Bot initialized")
    
    async def cleanup(self):
        await self.disconnect()
        logger.info("✓ Concierge Bot cleaned up")
    
    async def greet_guest(self, location: str):
        """Navigate to location and greet guest"""
        # Reuse base connection management
        await self.ensure_connection()
        await self.commands.subscribe_status()
        
        # Navigate to guest location
        await self.commands.go_to(poi=location)
        await self.commands.wait_until_arrival(location)
        
        # Greeting logic here
        logger.info(f"Greeting guest at {location}")
        
        await self.commands.unsubscribe_status()
```

That's it! The concierge bot automatically inherits:
- ✅ Connection management
- ✅ Automatic reconnection on failure
- ✅ Multi-robot support via configuration
- ✅ Logging infrastructure

### Example: Security Patrol Bot

Here's how easy it is to create a security patrol application:

```python
# apps/security_bot.py
from api.base_api import BaseRobotApplication
import asyncio
import logging

logger = logging.getLogger(__name__)

class SecurityBotApplication(BaseRobotApplication):
    """Security patrol bot that monitors checkpoints"""
    
    async def initialize(self):
        logger.info("✓ Security Bot initialized")
    
    async def cleanup(self):
        await self.disconnect()
        logger.info("✓ Security Bot cleaned up")
    
    async def patrol_route(self, checkpoints: list):
        """Patrol between security checkpoints"""
        # Reuse base infrastructure
        await self.ensure_connection()
        await self.commands.subscribe_status()
        
        for checkpoint in checkpoints:
            # Navigation handled by base class
            await self.commands.go_to(poi=checkpoint)
            success = await self.commands.wait_until_arrival(checkpoint)
            
            if not success:
                # Automatic reconnection is handled!
                reconnected = await self.reconnect_robot()
                if not reconnected:
                    break
            
            # Security-specific logic
            await self.check_security(checkpoint)
            await asyncio.sleep(5)  # Pause at checkpoint
        
        await self.commands.unsubscribe_status()
    
    async def check_security(self, location: str):
        """Perform security checks at location"""
        logger.info(f"🔒 Checking security at {location}")
        # Add camera monitoring, sensor checks, etc.
```

**Key Point**: Both concierge and security bots reuse the exact same navigation and connection infrastructure - just focus on your application-specific logic!

No need to reimplement robot communication - just focus on your application logic!

## 🔧 Adding a New Robot Adapter

To support a new robot type, create an adapter following this template:

### 1. Create Adapter Files

```bash
mkdir -p adapters/myrobot
touch adapters/myrobot/__init__.py
touch adapters/myrobot/myrobot_client.py
touch adapters/myrobot/myrobot_commands.py
```

### 2. Implement Client

```python
# adapters/myrobot/myrobot_client.py
from api.base_robot import BaseRobotClient

class MyRobotClient(BaseRobotClient):
    async def connect(self, timeout: int = 5) -> None:
        # Implement connection logic
        pass
    
    async def disconnect(self) -> None:
        # Implement disconnection logic
        pass
    
    async def send_message(self, message_dict: dict) -> None:
        # Implement message sending
        pass
    
    async def receive_message(self) -> dict:
        # Implement message receiving
        pass
    
    @property
    def is_connected(self) -> bool:
        # Return connection status
        return self._is_connected
```

### 3. Implement Commands

```python
# adapters/myrobot/myrobot_commands.py
from api.base_robot import BaseRobotCommands

class MyRobotCommands(BaseRobotCommands):
    async def subscribe_status(self) -> None:
        # Subscribe to robot status
        pass
    
    async def unsubscribe_status(self) -> None:
        # Unsubscribe from status
        pass
    
    async def go_to(self, poi: str, request_id: str = None) -> None:
        # Send navigation command
        pass
    
    async def wait_until_arrival(self, destination_name: str) -> bool:
        # Wait for navigation to complete
        pass
```

### 4. Register in Factory

Add your new robot to the factory functions in `api/robot_factory.py`:

```python
# In create_robot_client()
def create_robot_client(robot_type: str) -> BaseRobotClient:
    robot_type = robot_type.lower()
    
    if robot_type == "tibo":
        return TiboClient()
    elif robot_type == "myrobot":  # Add your robot here
        from adapters.myrobot.myrobot_client import MyRobotClient
        return MyRobotClient()
    else:
        raise ValueError(f"Unknown robot type: '{robot_type}'")

# In create_robot_commands()
def create_robot_commands(client: BaseRobotClient) -> BaseRobotCommands:
    if isinstance(client, TiboClient):
        return TiboCommands(client)
    elif isinstance(client, MyRobotClient):  # Add your robot here
        from adapters.myrobot.myrobot_commands import MyRobotCommands
        return MyRobotCommands(client)
    else:
        raise ValueError(f"Unknown client type: {type(client).__name__}")
```

### 5. Use New Robot

```env
ROBOT_TYPE=myrobot
```

That's it! No changes needed in applications or API layer.

## 🎯 Features

- ✅ Multi-robot support via adapter pattern
- ✅ REST API for remote control
- ✅ Web-based UI for tour control
- ✅ Audio narration at each waypoint
- ✅ Automatic reconnection on connection loss
- ✅ Configurable timeouts and retry logic
- ✅ Health monitoring and status reporting
- ✅ Extensible architecture for new applications
- ✅ Comprehensive logging system with rotating files

## 🛣️ Roadmap

- [ ] Add Lekiwi robot adapter
- [ ] Add Xlerobot adapter
- [ ] Android mobile app
- [ ] iOS mobile app
- [ ] Concierge bot application
- [ ] Security patrol application
- [ ] Multi-robot coordination
- [ ] WebSocket API for real-time updates

## ❓ FAQ

**Q: Can I use this with my robot that doesn't use ROS?**  
A: Yes! Just implement `BaseRobotClient` and `BaseRobotCommands` for your robot's protocol (REST, gRPC, MQTT, etc.).

**Q: Do I need to modify existing code to add a new robot?**  
A: No! Just create a new adapter in `adapters/myrobot/` and register it in `robot_factory.py`. All applications will automatically work with your new robot.

**Q: What if my robot doesn't support status subscriptions?**  
A: Just implement `subscribe_status()` and `unsubscribe_status()` as no-ops (empty methods). The interface is flexible enough to handle different robot capabilities.

**Q: Can I create multiple applications that share the same robot?**  
A: Yes! Each application is independent and uses the factory pattern to create its own robot connection.

**Q: How do I switch between robots?**  
A: Just change `ROBOT_TYPE` in your `.env` file. No code changes needed!

## 🔧 Troubleshooting

**Connection Timeout**
- Verify robot IP address and port in `.env`
- Ensure robot is powered on and network-accessible
- Check firewall settings

**WebSocket Keepalive Ping Timeout**
- If you see `ConnectionClosedError: keepalive ping timeout` on your server but not locally
- This indicates network latency differences between environments
- **Solution**: Increase `WS_PING_TIMEOUT` in your `.env` file (e.g., to 180 or 240 seconds)
- You can also increase `WS_PING_INTERVAL` to reduce ping frequency
- For high-latency networks, try: `WS_PING_INTERVAL=30` and `WS_PING_TIMEOUT=180`

**Navigation Failures**
- Verify waypoint names match robot's configured points of interest
- Check robot status using `/health` endpoint
- Review logs in `logs/` directory

**Module Import Errors**
- Ensure virtual environment is activated
- Run `pip install -r requirements.txt`
- Check Python version (3.9+ required)

## 📚 Documentation

- [Architecture Summary](docs/ARCHITECTURE_SUMMARY.md) - Comprehensive architecture overview
- [New Architecture Details](docs/NEW_ARCHITECTURE.md) - Design principles and patterns
- [Workflow Guide](docs/workflow.md) - Development workflow
- [Logging System](docs/LOGGING.md) - Logging configuration and usage
- [Migration Guide](docs/MIGRATION.md) - Migration notes
- [Refactoring Summary](docs/REFACTORING_SUMMARY.md) - Refactoring history

## 🤝 Contributing

Contributions are welcome! Please follow the existing code structure and patterns.

## 📄 License

[Your License Here]

## 👤 Author

Jordan - Tour Bot Project
