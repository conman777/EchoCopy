#!/bin/bash
# Build optimized release binary

set -e

echo "🔨 Building release binary..."

# Check swift is available
if ! command -v swift &> /dev/null; then
    echo "❌ Swift is not installed"
    echo "   Install Xcode and run: xcode-select --install"
    exit 1
fi

# Build release binary
swift build -c release --static-swift-stdlib

BINARY=".build/release/ClipboardManager"

if [ -f "$BINARY" ]; then
    echo "✅ Build successful!"
    echo ""
    echo "📦 Binary location: $BINARY"
    echo ""

    # Get binary size
    SIZE=$(du -h "$BINARY" | cut -f1)
    echo "📊 Binary size: $SIZE"
    echo ""

    echo "🚀 To test the binary:"
    echo "   $BINARY"
    echo ""

    echo "📦 To copy for distribution:"
    echo "   cp $BINARY ~/Downloads/ClipboardManager"
else
    echo "❌ Build failed"
    exit 1
fi
