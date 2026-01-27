#!/bin/bash

# Snaply Build and Run Script

echo "🔨 Building Snaply..."
swift build -c release

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    echo "🚀 Launching Snaply..."
    ./.build/release/Snaply &
else
    echo "❌ Build failed!"
    exit 1
fi
