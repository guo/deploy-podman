#!/bin/bash

set -e

echo "Uninstalling Shipd..."
echo ""

# Check what's installed
INSTALLED_BIN=false
INSTALLED_LIB=false

if [ -f "/usr/local/bin/shipd" ]; then
    INSTALLED_BIN=true
fi

if [ -d "/usr/local/lib/shipd" ]; then
    INSTALLED_LIB=true
fi

if [ "$INSTALLED_BIN" = false ] && [ "$INSTALLED_LIB" = false ]; then
    echo "Shipd is not installed."
    echo ""
    echo "Checked locations:"
    echo "  - /usr/local/bin/shipd"
    echo "  - /usr/local/lib/shipd/"
    exit 0
fi

# Remove executable
if [ "$INSTALLED_BIN" = true ]; then
    echo "[1/2] Removing command..."
    sudo rm -f /usr/local/bin/shipd
    echo "✓ Removed /usr/local/bin/shipd"
    echo ""
fi

# Remove library directory
if [ "$INSTALLED_LIB" = true ]; then
    echo "[2/2] Removing libraries..."
    sudo rm -rf /usr/local/lib/shipd
    echo "✓ Removed /usr/local/lib/shipd/"
    echo ""
fi

echo "=========================================="
echo "✓ Shipd uninstalled successfully!"
echo "=========================================="
echo ""
echo "Note: User data at ~/.shipd/ was preserved."
echo ""
echo "To remove user data:"
echo "  rm -rf ~/.shipd"
echo ""
