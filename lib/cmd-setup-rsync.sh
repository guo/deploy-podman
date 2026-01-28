#!/bin/bash

set -e

# Detect lib directory
if [ -d "/opt/homebrew/lib/shipd" ] && [ ! -d "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib" ]; then
    LIB_DIR="/opt/homebrew/lib/shipd"
elif [ -d "/usr/local/lib/shipd" ] && [ ! -d "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib" ]; then
    LIB_DIR="/usr/local/lib/shipd"
else
    LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Find targets directory
find_targets_dir() {
    if [ -d "./targets" ]; then
        echo "$(pwd)/targets"
    elif [ -d "$HOME/.shipd/targets" ]; then
        echo "$HOME/.shipd/targets"
    else
        echo ""
    fi
}

# Find global config file
find_global_config() {
    if [ -f "./.config" ]; then
        echo "$(pwd)/.config"
    elif [ -f "$HOME/.shipd/.config" ]; then
        echo "$HOME/.shipd/.config"
    else
        echo ""
    fi
}

# Show usage
show_usage() {
    echo "Usage: shipd setup-rsync <target>"
    echo ""
    echo "Install rsync on the remote server for a deployment target."
    echo ""
    echo "Arguments:"
    echo "  target      Target name (e.g., myapp-prod)"
    echo ""
    echo "Examples:"
    echo "  shipd setup-rsync myapp-prod"
    echo ""
    echo "This will:"
    echo "  1. Connect to the remote server via SSH"
    echo "  2. Detect the package manager (apt, yum, dnf, apk, zypper, pacman)"
    echo "  3. Install rsync"
    echo ""
    echo "Supported distributions:"
    echo "  - Debian/Ubuntu (apt)"
    echo "  - RHEL/CentOS/Fedora (yum/dnf)"
    echo "  - Alpine (apk)"
    echo "  - openSUSE (zypper)"
    echo "  - Arch Linux (pacman)"
    echo ""
}

# Check arguments
if [[ "$1" == "--help" || "$1" == "-h" || -z "$1" ]]; then
    show_usage
    exit 0
fi

TARGET="$1"

# Find target directory (search both locations)
TARGET_DIR=""
for search_dir in "./targets" "$HOME/.shipd/targets"; do
    if [ -d "${search_dir}/${TARGET}" ]; then
        TARGET_DIR="${search_dir}/${TARGET}"
        break
    fi
done

# Verify target directory exists
if [ -z "$TARGET_DIR" ]; then
    echo "Error: Target not found: ${TARGET}"
    echo ""
    echo "Available targets:"
    for search_dir in "./targets" "$HOME/.shipd/targets"; do
        if [ -d "$search_dir" ]; then
            for dir in "$search_dir"/*/ ; do
                if [ -d "$dir" ]; then
                    echo "  - $(basename "$dir")"
                fi
            done
        fi
    done
    exit 1
fi

# Load global config if exists
GLOBAL_CONFIG=$(find_global_config)
if [ -n "$GLOBAL_CONFIG" ]; then
    source "$GLOBAL_CONFIG"
fi

# Load target config
if [ -f "${TARGET_DIR}/.config" ]; then
    source "${TARGET_DIR}/.config"
else
    echo "Error: Target config not found: ${TARGET_DIR}/.config"
    exit 1
fi

# Verify SSH_HOST
if [ -z "$SSH_HOST" ]; then
    echo "Error: SSH_HOST not set in ${TARGET_DIR}/.config"
    exit 1
fi

echo "========================================"
echo "Setup rsync on remote server"
echo "========================================"
echo "Target:    ${TARGET}"
echo "SSH Host:  ${SSH_HOST}"
echo "========================================"
echo ""

# Check SSH connection
echo "Checking SSH connection..."
if ! ssh $SSH_HOST "echo 'SSH connection successful'" >/dev/null 2>&1; then
    echo "Error: Cannot connect to ${SSH_HOST}"
    exit 1
fi
echo "✓ SSH connection verified"
echo ""

# Check if rsync is already installed
echo "Checking if rsync is already installed..."
if ssh $SSH_HOST "command -v rsync >/dev/null 2>&1"; then
    RSYNC_VERSION=$(ssh $SSH_HOST "rsync --version | head -1")
    echo "✓ rsync is already installed: ${RSYNC_VERSION}"
    exit 0
fi
echo "rsync not found, will install..."
echo ""

# Detect package manager and install rsync
echo "Detecting package manager..."

INSTALL_CMD=$(ssh $SSH_HOST 'sh -s' << 'EOF'
if command -v apt-get >/dev/null 2>&1; then
    echo "apt-get update && apt-get install -y rsync"
elif command -v dnf >/dev/null 2>&1; then
    echo "dnf install -y rsync"
elif command -v yum >/dev/null 2>&1; then
    echo "yum install -y rsync"
elif command -v apk >/dev/null 2>&1; then
    echo "apk add --no-cache rsync"
elif command -v zypper >/dev/null 2>&1; then
    echo "zypper install -y rsync"
elif command -v pacman >/dev/null 2>&1; then
    echo "pacman -S --noconfirm rsync"
else
    echo ""
fi
EOF
)

if [ -z "$INSTALL_CMD" ]; then
    echo "Error: Could not detect package manager on remote server"
    echo ""
    echo "Please install rsync manually:"
    echo "  ssh ${SSH_HOST}"
    echo "  # Then run the appropriate command for your distribution"
    exit 1
fi

echo "Detected install command: ${INSTALL_CMD}"
echo ""

# Install rsync
echo "Installing rsync..."
if ! ssh $SSH_HOST "sudo sh -c '${INSTALL_CMD}'"; then
    echo ""
    echo "Error: Failed to install rsync"
    echo ""
    echo "You may need to install it manually:"
    echo "  ssh ${SSH_HOST}"
    echo "  sudo sh -c '${INSTALL_CMD}'"
    exit 1
fi

echo ""

# Verify installation
echo "Verifying installation..."
if ssh $SSH_HOST "command -v rsync >/dev/null 2>&1"; then
    RSYNC_VERSION=$(ssh $SSH_HOST "rsync --version | head -1")
    echo "✓ rsync installed successfully: ${RSYNC_VERSION}"
else
    echo "Error: rsync installation verification failed"
    exit 1
fi

echo ""
echo "========================================"
echo "✓ Setup complete!"
echo "========================================"
echo ""
echo "You can now use rsync-based file comparison with:"
echo "  shipd deploy ${TARGET}"
