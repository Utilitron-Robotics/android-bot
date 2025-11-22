#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
PACKAGE_NAME="com.opendroids.tourbot"
DATASTORE_FILE_NAME="tour_config.preferences_pb"
LOCAL_DESTINATION_DIR="debug_config"

# --- Script Logic ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$SCRIPT_DIR"

echo "🔎 Attempting to pull DataStore config from device..."

# Check for ADB
if ! command -v adb &> /dev/null; then
    echo "❌ Error: adb is not installed or not in PATH."
    exit 1
fi

# Check for device
if ! adb devices | grep -w "device" | grep -v "List of devices attached" > /dev/null; then
    echo "❌ No active Android device found."
    exit 1
fi

# Construct the path to the file on the device
# Note: This path is standard for DataStore but might vary on rooted/custom devices.
DEVICE_FILE_PATH="/data/data/$PACKAGE_NAME/files/datastore/$DATASTORE_FILE_NAME"

echo "📲 Pulling from: $DEVICE_FILE_PATH"

# Create local destination directory if it doesn't exist
mkdir -p "$LOCAL_DESTINATION_DIR"
LOCAL_FILE_PATH="$LOCAL_DESTINATION_DIR/$DATASTORE_FILE_NAME"

# Use adb exec-out and check if the file exists on the device
# The 'run-as' command is necessary to access the app's private data directory.
if adb shell "run-as $PACKAGE_NAME cat $DEVICE_FILE_PATH" > "$LOCAL_FILE_PATH"; then
    # Check if the pulled file has content
    if [ -s "$LOCAL_FILE_PATH" ]; then
        echo "✅ Successfully pulled config to: $LOCAL_FILE_PATH"
        echo "💡 Note: This is a Protocol Buffer file, not plain text XML. Its contents are binary."
    else
        echo "⚠️  Warning: Pulled an empty file. The config might not have been created on the device yet."
        echo "💡 Tip: Run the app and make a change in the Control Panel to ensure the file is created."
        rm "$LOCAL_FILE_PATH" # Clean up empty file
    fi
else
    echo "❌ Error: Failed to pull the file."
    echo "💡 Possible reasons:"
    echo "   - The app has not been run yet, so the file doesn't exist."
    echo "   - The package name '$PACKAGE_NAME' is incorrect."
    echo "   - You are using a device without 'run-as' support (e.g., some production builds)."
    exit 1
fi
