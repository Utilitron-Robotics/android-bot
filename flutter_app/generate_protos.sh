#!/bin/bash

# Generate Dart protobuf files from proto definition
# THIS IS CRUCIAL FOR gRPC TO WORK!

echo "🚀 Generating Dart protobuf files for gRPC..."

# Create output directory
mkdir -p lib/generated

# Install protoc plugin for Dart if not already installed
if ! command -v protoc-gen-dart &> /dev/null; then
    echo "📦 Installing Dart protoc plugin..."
    dart pub global activate protoc_plugin
fi

# Path to proto file
PROTO_FILE="../proto/robot_control.proto"

# Generate Dart files
protoc --dart_out=grpc:lib/generated \
       --proto_path=../proto \
       $PROTO_FILE

if [ $? -eq 0 ]; then
    echo "✅ Successfully generated Dart protobuf files!"
    echo "📁 Files created in lib/generated/"
    ls -la lib/generated/
else
    echo "❌ Failed to generate protobuf files"
    echo "Make sure protoc is installed: brew install protobuf"
    exit 1
fi