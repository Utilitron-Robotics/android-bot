# Tour Bot Unit Tests

Comprehensive unit test suite for the Tour Bot application.

## Test Coverage

### Core Tests (No Robot Required)

- **test_settings.py** - Configuration and environment variable handling
- **test_robot_factory.py** - Robot client and command creation logic
- **test_tour_state.py** - Tour state management and lifecycle
- **test_tibo_client.py** - WebSocket client behavior (mocked)
- **test_tibo_commands.py** - Robot command interface (mocked)
- **test_tour_bot.py** - Tour bot application logic (mocked)
- **test_base_api.py** - Base API infrastructure and reconnection logic
- **test_tour_api.py** - FastAPI endpoints and HTTP responses

### Test Infrastructure

- **conftest.py** - Shared fixtures, mocks, and fake WebSocket server
- **pytest.ini** - Test configuration and coverage settings

## Running Tests

### Install Test Dependencies

```bash
# Activate virtual environment
source venv/bin/activate

# Install test dependencies
pip install -r requirements.txt
```

### Run All Tests

```bash
pytest
```

### Run Specific Test File

```bash
pytest tests/test_settings.py
pytest tests/test_tour_bot.py
```

### Run Specific Test Class or Function

```bash
pytest tests/test_tour_bot.py::TestTourBotApplication
pytest tests/test_tour_bot.py::TestTourBotApplication::test_initialization
```

### Run with Coverage Report

```bash
pytest --cov=apps --cov=api --cov=adapters --cov=config --cov-report=html
```

This generates an HTML coverage report in `htmlcov/index.html`.

### Run with Verbose Output

```bash
pytest -v
```

### Run Only Fast Tests (Skip Hardware Tests)

```bash
pytest -m "not hardware"
```

## Hardware Tests

Some tests are marked with `@pytest.mark.hardware` and require a physical robot or real robot endpoint. These are skipped by default.

To run hardware tests:

```bash
RUN_HARDWARE_TESTS=1 pytest -m hardware
```

## Test Philosophy

### Unit Tests (Current Implementation)
- **Fully offline** - no robot hardware required
- **Fast execution** - entire suite runs in seconds
- **Mocked dependencies** - WebSocket connections, file I/O, network calls
- **Tests logic** - state management, error handling, data validation

### Integration Tests (Future)
- Use fake WebSocket server from `conftest.py`
- Simulate robot message sequences
- Test end-to-end flows without hardware

### Hardware Tests (Minimal)
- Only for final validation
- Run manually or in CI with robot access
- Mark with `@pytest.mark.hardware`

## Key Testing Patterns

### Mocking WebSocket Client

```python
@pytest.fixture
def mock_client():
    client = MagicMock()
    client.send_message = AsyncMock()
    client.receive_message = AsyncMock()
    return client
```

### Testing Async Functions

```python
@pytest.mark.asyncio
async def test_async_function():
    result = await some_async_function()
    assert result is True
```

### Using Fake Robot Server

```python
async def test_with_fake_robot(fake_robot_server):
    # Queue messages the server should send
    fake_robot_server.queue_messages([
        {"topic": "/robot_status", "msg": {"nav_status": 601}},
        {"topic": "/robot_status", "msg": {"nav_status": 603}},
    ])
    
    # Connect client to fake_robot_server.uri
    # ... test code ...
```

## Coverage Goals

Current coverage targets:
- **Configuration**: 100%
- **Factory**: 100%
- **State Management**: 100%
- **Client/Commands**: 90%+
- **Application Logic**: 80%+
- **API Endpoints**: 80%+

View detailed coverage:

```bash
pytest --cov-report=term-missing
```

## Continuous Integration

These tests are designed to run in CI/CD environments without robot hardware:

```yaml
# Example CI configuration
- name: Run Tests
  run: |
    pip install -r requirements.txt
    pytest --cov --cov-report=xml
```

## Troubleshooting

### Import Errors

If you see import errors, ensure you're running from the project root:

```bash
cd /path/to/tour-bot
pytest
```

### Async Warnings

If you see warnings about async tests, ensure `pytest-asyncio` is installed:

```bash
pip install pytest-asyncio>=0.21.0
```

### Coverage Not Working

Install coverage plugin:

```bash
pip install pytest-cov>=4.1.0
```

## Adding New Tests

1. Create test file in `tests/` directory: `test_<module>.py`
2. Import the module you're testing
3. Create test classes: `class TestClassName:`
4. Write test functions: `def test_description():`
5. Use fixtures from `conftest.py` or create new ones
6. Mark hardware tests: `@pytest.mark.hardware`

Example:

```python
import pytest
from my_module import MyClass

class TestMyClass:
    @pytest.fixture
    def instance(self):
        return MyClass()
        
    def test_initialization(self, instance):
        assert instance is not None
        
    @pytest.mark.asyncio
    async def test_async_method(self, instance):
        result = await instance.async_method()
        assert result is True
```

## Test Maintenance

- Update tests when changing implementation
- Keep tests fast and focused
- Mock external dependencies
- Use descriptive test names
- Document complex test scenarios
- Run tests before committing code

