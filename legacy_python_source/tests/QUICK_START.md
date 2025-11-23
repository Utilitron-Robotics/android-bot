# Quick Start - Running Tests

## ✅ Run All Tests

```bash
source venv/bin/activate
pytest
```

Expected output: **133 passed in ~2 minutes**

## 📊 View Coverage Report

```bash
pytest --cov --cov-report=html
open htmlcov/index.html
```

## 🎯 Common Test Commands

```bash
# Run specific test file
pytest tests/test_tour_bot.py

# Run with verbose output
pytest -v

# Run only failed tests from last run
pytest --lf

# Run tests matching a pattern
pytest -k "test_navigation"

# Stop at first failure
pytest -x

# Show print statements
pytest -s
```

## 🚫 Skip Hardware Tests

By default, hardware tests are skipped. To run them:

```bash
RUN_HARDWARE_TESTS=1 pytest -m hardware
```

## 📁 Test Files

- `test_settings.py` - Configuration tests
- `test_robot_factory.py` - Factory pattern tests  
- `test_tibo_client.py` - WebSocket client tests
- `test_tibo_commands.py` - Robot command tests
- `test_tour_state.py` - State management tests
- `test_tour_bot.py` - Application logic tests
- `test_base_api.py` - Base infrastructure tests
- `test_tour_api.py` - FastAPI endpoint tests

## 🐛 Debugging Failed Tests

```bash
# Show full traceback
pytest --tb=long

# Drop into debugger on failure
pytest --pdb

# Show local variables in traceback
pytest -l
```

## 💡 Tips

- Tests use mocks - **no robot hardware needed**
- All tests are **fast and offline**
- Coverage report shows **what code isn't tested**
- Tests are **safe to run anytime**

For more details, see `tests/README.md`

