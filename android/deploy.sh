#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Navigate to the script's directory (android/) to ensure relative paths work
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$SCRIPT_DIR"

echo "🚀 Starting Android deployment..."

# Check for verify flag
VERIFY_ONLY=false
if [ "$1" == "--verify" ]; then
    VERIFY_ONLY=true
    echo "🔍 Verification mode: Checking tools..."
fi

# Try to add local Android SDK to PATH if defined in local.properties
if [ -f "local.properties" ]; then
    # Extract sdk.dir, handling potential whitespace around the =
    SDK_DIR=$(grep "^sdk.dir" local.properties | cut -d'=' -f2 | xargs)
    if [ ! -z "$SDK_DIR" ] && [ -d "$SDK_DIR/platform-tools" ]; then
        echo "ℹ️  Adding $SDK_DIR/platform-tools to PATH"
        export PATH="$PATH:$SDK_DIR/platform-tools"
    fi
fi

# Check for ADB
if ! command -v adb &> /dev/null; then
    echo "❌ Error: adb is not installed or not in PATH."
    echo "💡 Tip: Ensure Android SDK Platform-Tools are installed and in your PATH, or defined in local.properties."
    exit 1
fi

# Check for Java (required for Gradle)
# Try to find Android Studio's bundled JDK if system Java is not found or not working
# (macOS /usr/bin/java stub exists even if no Runtime is installed)
JAVA_OK=false
if command -v java &> /dev/null && java -version &> /dev/null; then
    JAVA_OK=true
fi

if [ "$JAVA_OK" = "false" ]; then
    echo "⚠️  System Java not found or not working. Checking common Android Studio locations..."
    POSSIBLE_JAVA_HOMES=(
        "/Applications/Android Studio.app/Contents/jbr/Contents/Home"
        "/Applications/Android Studio.app/Contents/jre/Contents/Home"
        "$HOME/Library/Application Support/JetBrains/Toolbox/apps/AndroidStudio/ch-0/*/jre/Contents/Home"
    )
    
    # Add system java_home if available
    if [ -x "/usr/libexec/java_home" ]; then
        SYSTEM_JAVA_HOME=$(/usr/libexec/java_home 2>/dev/null || true)
        if [ ! -z "$SYSTEM_JAVA_HOME" ]; then
            POSSIBLE_JAVA_HOMES+=("$SYSTEM_JAVA_HOME")
        fi
    fi

    for CANDIDATE in "${POSSIBLE_JAVA_HOMES[@]}"; do
        if [ -n "$CANDIDATE" ] && [ -d "$CANDIDATE" ] && [ -x "$CANDIDATE/bin/java" ]; then
            echo "✅ Found bundled JDK at $CANDIDATE"
            export JAVA_HOME="$CANDIDATE"
            export PATH="$CANDIDATE/bin:$PATH"
            JAVA_OK=true
            break
        fi
    done
fi

if [ "$JAVA_OK" = "false" ]; then
    echo "❌ Error: Java is not found in PATH and could not be auto-detected."
    echo "💡 Tip: Install a JDK (version 17 recommended) and ensure JAVA_HOME is set."
    exit 1
fi

if [ "$VERIFY_ONLY" = true ]; then
    echo "✅ ADB found: $(command -v adb)"
    adb --version | head -n 1
    
    echo "✅ Java found: $(command -v java)"
    java -version 2>&1 | head -n 1
    
    echo "✅ Gradle Wrapper found"
    ./gradlew --version | grep "Gradle" | head -n 1
    
    echo "✅ Environment verification complete."
    exit 0
fi

# Check if a device is connected
# 'adb devices' output usually has a header line, then devices. 
# We look for a line ending in 'device' to skip 'unauthorized' or 'offline' ones if possible, 
# but strictly checking for any device is a good start.
if ! adb devices | grep -w "device" | grep -v "List of devices attached" > /dev/null; then
    echo "❌ No active Android device found. Please connect a device or start an emulator."
    exit 1
fi

echo "🏗️  Building debug APK..."
# Using ./gradlew relative to the android directory
if ./gradlew assembleDebug; then
    echo "✅ Build successful."
else
    echo "❌ Build failed."
    exit 1
fi

APK_PATH="app/build/outputs/apk/debug/app-debug.apk"

if [ ! -f "$APK_PATH" ]; then
    echo "❌ APK not found at $APK_PATH"
    exit 1
fi

echo "📲 Installing APK..."
if adb install -r "$APK_PATH"; then
    echo "✅ Install successful."
else
    echo "❌ Install failed."
    exit 1
fi

echo "🚀 Launching app..."
PACKAGE_NAME="com.opendroids.tourbot"
ACTIVITY_NAME=".MainActivity"
COMPONENT="$PACKAGE_NAME/$ACTIVITY_NAME"

if adb shell am start -n "$COMPONENT"; then
    echo "✅ App launched successfully!"
else
    echo "❌ Failed to launch app."
    exit 1
fi