#!/bin/bash

# ClipboardManager Build and Run Script

echo "🔨 Building ClipboardManager..."
swift build -c release

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    echo "🚀 Launching ClipboardManager..."
    ./.build/release/ClipboardManager &
else
    echo "❌ Build failed!"
    exit 1
fi
