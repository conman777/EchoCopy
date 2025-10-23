#!/bin/bash
# Setup Git hooks for code quality checks

set -e

echo "🔧 Setting up Git hooks..."

# Configure git to use .githooks directory
git config core.hooksPath .githooks

echo "✅ Git hooks configured"
echo ""
echo "📝 Installed hooks:"
echo "   - pre-commit: Runs format, lint, and build checks before committing"
echo ""
echo "💡 Hooks will run automatically on 'git commit'"
echo "   Skip hooks with: git commit --no-verify (not recommended)"
