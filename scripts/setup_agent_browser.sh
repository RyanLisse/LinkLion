#!/bin/bash

# Setup script for agent-browser CLI tool
# Installs agent-browser globally and downloads Chromium

set -e

echo "🔍 Checking if agent-browser is installed..."

if command -v agent-browser &> /dev/null; then
    echo "✓ agent-browser is already installed"
    agent-browser --version
else
    echo "📦 Installing agent-browser globally..."
    npm install -g agent-browser
fi

echo ""
echo "⬇️  Downloading Chromium for agent-browser..."
agent-browser install

echo ""
echo "✅ Verifying installation..."
agent-browser --version

echo ""
echo "🎉 agent-browser setup complete!"
