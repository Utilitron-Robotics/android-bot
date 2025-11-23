"""
Test script for battery level reading functionality
Run this to verify get_battery_level() works with the robot
"""

import asyncio
import logging
import sys
import os

# Add parent directory to path to import modules
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from adapters.tibo.tibo_client import TiboClient
from adapters.tibo.tibo_commands import TiboCommands
from config.settings import settings

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] %(levelname)-8s %(name)s - %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)

logger = logging.getLogger(__name__)


async def test_battery_reading():
    """Test battery level reading from robot"""
    
    logger.info("=" * 60)
    logger.info("🔋 Battery Level Reading Test")
    logger.info("=" * 60)
    
    client = None
    
    try:
        # Connect to robot
        logger.info(f"Connecting to robot at {settings.get_robot_uri()}...")
        client = TiboClient()
        await client.connect(timeout=10)
        logger.info("✓ Connected to robot")
        
        # Create commands interface
        commands = TiboCommands(client)
        
        # Test 1: Read battery level
        logger.info("\n--- Test 1: Reading battery level ---")
        battery = await commands.get_battery_level(timeout=5.0)
        
        if battery is not None:
            logger.info(f"✅ SUCCESS: Battery level is {battery}%")
            
            # Provide battery status interpretation
            if battery >= 80:
                logger.info("🟢 Battery status: Excellent")
            elif battery >= 50:
                logger.info("🟡 Battery status: Good")
            elif battery >= 20:
                logger.info("🟠 Battery status: Low - consider charging soon")
            else:
                logger.info("🔴 Battery status: Critical - charge immediately!")
        else:
            logger.error("❌ FAILED: Could not read battery level")
            return False
        
        # Test 2: Read battery level again (test repeatability)
        logger.info("\n--- Test 2: Reading battery level again ---")
        battery2 = await commands.get_battery_level(timeout=5.0)
        
        if battery2 is not None:
            logger.info(f"✅ SUCCESS: Battery level is {battery2}%")
            
            # Check if battery changed (should be same or very close)
            if abs(battery - battery2) <= 1:
                logger.info("✓ Battery readings are consistent")
            else:
                logger.warning(f"⚠️ Battery changed by {abs(battery - battery2)}% between readings")
        else:
            logger.error("❌ FAILED: Could not read battery level on second attempt")
            return False
        
        logger.info("\n" + "=" * 60)
        logger.info("✅ All battery reading tests passed!")
        logger.info("=" * 60)
        return True
        
    except ConnectionError as e:
        logger.error(f"❌ Connection error: {e}")
        logger.error("Make sure the robot is powered on and accessible")
        return False
    except Exception as e:
        logger.error(f"❌ Unexpected error: {e}", exc_info=True)
        return False
    finally:
        # Disconnect from robot
        if client and client.is_connected:
            await client.disconnect()
            logger.info("Disconnected from robot")


async def test_battery_with_status_subscription():
    """
    Test battery reading while robot status subscription is active
    This simulates the real tour scenario
    """
    
    logger.info("\n" + "=" * 60)
    logger.info("🔋 Battery Reading Test (with active status subscription)")
    logger.info("=" * 60)
    
    client = None
    
    try:
        # Connect to robot
        logger.info(f"Connecting to robot at {settings.get_robot_uri()}...")
        client = TiboClient()
        await client.connect(timeout=10)
        logger.info("✓ Connected to robot")
        
        # Create commands interface
        commands = TiboCommands(client)
        
        # Subscribe to robot status (like during a tour)
        logger.info("Subscribing to robot status...")
        await commands.subscribe_status()
        
        # Small delay to let status messages start flowing
        await asyncio.sleep(1)
        
        # Now try to read battery
        logger.info("\n--- Reading battery while status is subscribed ---")
        battery = await commands.get_battery_level(timeout=5.0)
        
        if battery is not None:
            logger.info(f"✅ SUCCESS: Battery level is {battery}%")
        else:
            logger.error("❌ FAILED: Could not read battery level")
            await commands.unsubscribe_status()
            return False
        
        # Unsubscribe from status
        await commands.unsubscribe_status()
        
        logger.info("\n" + "=" * 60)
        logger.info("✅ Battery reading with active subscription passed!")
        logger.info("=" * 60)
        return True
        
    except Exception as e:
        logger.error(f"❌ Error: {e}", exc_info=True)
        return False
    finally:
        # Disconnect from robot
        if client and client.is_connected:
            await client.disconnect()
            logger.info("Disconnected from robot")


async def main():
    """Run all battery reading tests"""
    
    print("\n" + "=" * 60)
    print("🧪 Starting Battery Reading Tests")
    print("=" * 60)
    print(f"Robot: {settings.ROBOT_TYPE}")
    print(f"URI: {settings.get_robot_uri()}")
    print("=" * 60 + "\n")
    
    # Run basic battery reading tests
    test1_passed = await test_battery_reading()
    
    # Run test with active status subscription
    test2_passed = await test_battery_with_status_subscription()
    
    # Summary
    print("\n" + "=" * 60)
    print("📊 Test Summary")
    print("=" * 60)
    print(f"Basic battery reading: {'✅ PASSED' if test1_passed else '❌ FAILED'}")
    print(f"Battery with subscription: {'✅ PASSED' if test2_passed else '❌ FAILED'}")
    print("=" * 60 + "\n")
    
    if test1_passed and test2_passed:
        print("🎉 All tests passed! Battery reading is working correctly.")
        return 0
    else:
        print("❌ Some tests failed. Check the logs above for details.")
        return 1


if __name__ == "__main__":
    exit_code = asyncio.run(main())
    sys.exit(exit_code)

