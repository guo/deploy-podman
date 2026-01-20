#!/bin/bash

# Test Homebrew formula locally before publishing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=========================================="
echo "Testing Homebrew Formula Locally"
echo "=========================================="
echo ""

# Check if formula exists
if [ ! -f "${SCRIPT_DIR}/homebrew/shipd.rb" ]; then
    echo "Error: shipd.rb not found"
    echo "Create it first following homebrew/HOMEBREW.md"
    exit 1
fi

# Check if already installed via Homebrew
if brew list shipd >/dev/null 2>&1; then
    echo "Shipd is already installed via Homebrew"
    read -p "Uninstall and reinstall? (y/N) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        brew uninstall shipd
    else
        echo "Test cancelled."
        exit 0
    fi
fi

echo "[1/5] Installing from local formula..."
brew install --build-from-source "${SCRIPT_DIR}/homebrew/shipd.rb"
echo "✓ Installed"
echo ""

echo "[2/5] Testing version command..."
if shipd --version; then
    echo "✓ Version command works"
else
    echo "✗ Version command failed"
    exit 1
fi
echo ""

echo "[3/5] Testing help command..."
if shipd --help >/dev/null; then
    echo "✓ Help command works"
else
    echo "✗ Help command failed"
    exit 1
fi
echo ""

echo "[4/5] Checking installation paths..."
INSTALL_PREFIX=$(brew --prefix)/lib/shipd
if [ -d "$INSTALL_PREFIX" ]; then
    echo "✓ Library directory exists: $INSTALL_PREFIX"
    echo "  Files:"
    ls -1 "$INSTALL_PREFIX" | sed 's/^/    - /'
else
    echo "✗ Library directory not found: $INSTALL_PREFIX"
    exit 1
fi
echo ""

echo "[5/5] Testing target discovery..."
mkdir -p /tmp/shipd-test/targets/test-target
echo 'SSH_HOST="test"' > /tmp/shipd-test/targets/test-target/.config
echo 'TEST=1' > /tmp/shipd-test/targets/test-target/.env
cd /tmp/shipd-test
if shipd deploy --help 2>&1 | grep -q "test-target"; then
    echo "✓ Target discovery works"
else
    echo "✗ Target discovery failed"
    cd -
    rm -rf /tmp/shipd-test
    exit 1
fi
cd -
rm -rf /tmp/shipd-test
echo ""

echo "=========================================="
echo "✓ All tests passed!"
echo "=========================================="
echo ""
echo "Installed at: $(which shipd)"
echo "Library path: $INSTALL_PREFIX"
echo ""
echo "To uninstall:"
echo "  brew uninstall shipd"
echo ""
