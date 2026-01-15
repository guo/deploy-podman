#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if already installed
if command -v shipd >/dev/null 2>&1; then
    CURRENT_VERSION=$(shipd --version 2>/dev/null || echo "unknown")
    echo "Shipd is already installed: $CURRENT_VERSION"
    echo "Location: $(which shipd)"
    echo ""
    read -p "Reinstall/update? (y/N) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
    echo ""
fi

echo "Installing Shipd..."
echo ""

# Create directories
echo "[1/4] Creating installation directories..."
sudo mkdir -p /usr/local/bin
sudo mkdir -p /usr/local/lib/shipd
echo "✓ Directories created"
echo ""

# Copy main executable
echo "[2/4] Installing shipd command..."
sudo cp "${SCRIPT_DIR}/shipd.sh" /usr/local/bin/shipd
sudo chmod +x /usr/local/bin/shipd
echo "✓ Installed to /usr/local/bin/shipd"
echo ""

# Copy library files
echo "[3/4] Installing library files..."
sudo cp "${SCRIPT_DIR}/lib/cmd-deploy.sh" /usr/local/lib/shipd/
sudo cp "${SCRIPT_DIR}/lib/cmd-deploy-multi.sh" /usr/local/lib/shipd/
sudo cp "${SCRIPT_DIR}/lib/cmd-setup-caddy.sh" /usr/local/lib/shipd/
sudo cp "${SCRIPT_DIR}/lib/deploy-podman.sh" /usr/local/lib/shipd/
sudo cp "${SCRIPT_DIR}/lib/deploy-docker.sh" /usr/local/lib/shipd/
sudo cp "${SCRIPT_DIR}/lib/deploy-caddy.sh" /usr/local/lib/shipd/
sudo cp "${SCRIPT_DIR}/lib/hash-check.sh" /usr/local/lib/shipd/
sudo chmod +x /usr/local/lib/shipd/*.sh
echo "✓ Libraries installed to /usr/local/lib/shipd/"
echo ""

# Create user data directory
echo "[4/4] Creating user data directory..."
mkdir -p ~/.shipd/targets
echo "✓ Created ~/.shipd/targets/"
echo ""

# Verify installation
if command -v shipd >/dev/null 2>&1; then
    echo "=========================================="
    echo "✓ Shipd installed successfully!"
    echo "=========================================="
    echo ""
    shipd --version
    echo ""
    echo "Installation locations:"
    echo "  • Command:   /usr/local/bin/shipd"
    echo "  • Libraries: /usr/local/lib/shipd/"
    echo "  • User data: ~/.shipd/targets/"
    echo ""
    echo "Targets search order:"
    echo "  1. ./targets/ (current directory)"
    echo "  2. ~/.shipd/targets/ (home directory)"
    echo ""
    echo "Quick start:"
    echo "  # Create a target"
    echo "  mkdir -p ~/.shipd/targets/myapp"
    echo "  cp ${SCRIPT_DIR}/.config.example ~/.shipd/targets/myapp/.config"
    echo "  cp ${SCRIPT_DIR}/env.example ~/.shipd/targets/myapp/.env"
    echo ""
    echo "  # Deploy"
    echo "  shipd deploy myapp"
    echo ""

    # Offer to migrate existing targets
    if [ -d "${SCRIPT_DIR}/targets" ] && [ -n "$(ls -A "${SCRIPT_DIR}/targets" 2>/dev/null)" ]; then
        echo "=========================================="
        echo "Existing targets found in ${SCRIPT_DIR}/targets/"
        echo ""
        read -p "Would you like to copy them to ~/.shipd/targets/? (y/N) " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cp -r "${SCRIPT_DIR}/targets/"* ~/.shipd/targets/
            echo "✓ Targets copied to ~/.shipd/targets/"
        else
            echo "Skipped. You can copy them manually:"
            echo "  cp -r ${SCRIPT_DIR}/targets/* ~/.shipd/targets/"
        fi
        echo ""
    fi
else
    echo "⚠️  Installation completed but 'shipd' not found in PATH."
    echo "You may need to restart your terminal or add /usr/local/bin to PATH."
    echo ""
fi
