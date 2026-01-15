#!/bin/bash

# Update Homebrew tap after creating a release

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAP_DIR="../homebrew-tap"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================="
echo "Update Homebrew Tap"
echo -e "==========================================${NC}"
echo ""

# Check if tap directory exists
if [ ! -d "$TAP_DIR" ]; then
    echo -e "${RED}Error: Homebrew tap not found at ${TAP_DIR}${NC}"
    echo ""
    echo "Expected location: /Users/qevan/proj/homebrew-tap/"
    exit 1
fi

# Check if formula exists
if [ ! -f "${SCRIPT_DIR}/shipd.rb" ]; then
    echo -e "${RED}Error: Formula not found: ${SCRIPT_DIR}/shipd.rb${NC}"
    echo ""
    echo "Run prepare-release.sh first to create/update the formula."
    exit 1
fi

# Extract version from formula
VERSION=$(grep "url.*v" "${SCRIPT_DIR}/shipd.rb" | sed -E 's/.*v([0-9]+\.[0-9]+\.[0-9]+).*/\1/')

if [ -z "$VERSION" ]; then
    echo -e "${RED}Error: Could not extract version from formula${NC}"
    exit 1
fi

echo "Formula version: ${VERSION}"
echo "Tap directory:   ${TAP_DIR}"
echo ""

# Copy formula to tap
echo "[1/3] Copying formula to tap..."
cp "${SCRIPT_DIR}/shipd.rb" "${TAP_DIR}/Formula/shipd.rb"
echo -e "${GREEN}✓ Formula copied${NC}"
echo ""

# Commit changes
echo "[2/3] Committing changes..."
cd "$TAP_DIR"

if [ -z "$(git status --porcelain)" ]; then
    echo -e "${BLUE}No changes to commit (formula already up to date)${NC}"
else
    git add Formula/shipd.rb
    git commit -m "shipd ${VERSION}"
    echo -e "${GREEN}✓ Changes committed${NC}"
fi
echo ""

# Check if remote is configured
if ! git remote get-url origin >/dev/null 2>&1; then
    echo -e "${BLUE}[3/3] Git remote not configured${NC}"
    echo ""
    echo "To push, first configure the remote:"
    echo "  cd ${TAP_DIR}"
    echo "  git remote add origin https://github.com/guo/homebrew-tap.git"
    echo "  git push -u origin main"
else
    # Push changes
    echo "[3/3] Pushing to GitHub..."
    git push
    echo -e "${GREEN}✓ Changes pushed${NC}"
fi

cd - >/dev/null

echo ""
echo -e "${GREEN}=========================================="
echo "✓ Tap updated successfully!"
echo -e "==========================================${NC}"
echo ""
echo "Users can now update with:"
echo "  brew update"
echo "  brew upgrade shipd"
echo ""
