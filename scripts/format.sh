#!/bin/bash
# Format all Swift files using SwiftFormat

set -e

echo "🎨 Formatting Swift code..."

# Check if swiftformat is installed
if ! command -v swiftformat &> /dev/null; then
    echo "❌ SwiftFormat is not installed"
    echo "   Install with: brew install swiftformat"
    exit 1
fi

# Format the Sources directory
swiftformat Sources/

echo "✅ Code formatted successfully"
echo ""
echo "💡 Tip: Run 'git diff' to see changes"
