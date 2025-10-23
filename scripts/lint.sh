#!/bin/bash
# Run SwiftLint on all Swift files

set -e

echo "🔍 Linting Swift code..."

# Check if swiftlint is installed
if ! command -v swiftlint &> /dev/null; then
    echo "❌ SwiftLint is not installed"
    echo "   Install with: brew install swiftlint"
    exit 1
fi

# Run linter
if swiftlint lint --strict; then
    echo "✅ All linting checks passed!"
else
    echo ""
    echo "❌ Linting failed. Fix the issues above."
    echo ""
    echo "💡 Tip: Some issues can be auto-fixed with:"
    echo "   swiftlint --fix"
    exit 1
fi
