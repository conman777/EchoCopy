#!/bin/bash

# EchoCopy Build and Run Script

echo "🔨 Building EchoCopy..."
swift build -c release

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    echo "🚀 Launching EchoCopy..."
    ./.build/release/EchoCopy &
else
    echo "❌ Build failed!"
    exit 1
fi
