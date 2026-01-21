#!/bin/bash

# Complete release workflow: Create release + Update tap

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Parse arguments
AUTO_CONFIRM=false
VERSION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -y|--yes)
            AUTO_CONFIRM=true
            shift
            ;;
        *)
            VERSION="$1"
            shift
            ;;
    esac
done

echo -e "${BOLD}${BLUE}=========================================="
echo "Shipd Complete Release Workflow"
echo -e "==========================================${NC}"
echo ""

if [ -z "$VERSION" ]; then
    # Show current version from git tags and formula
    CURRENT_TAG=$(git -C "$SCRIPT_DIR" tag --sort=-version:refname | head -1 | sed 's/^v//')
    CURRENT_FORMULA=$(grep 'url.*v[0-9]' "${SCRIPT_DIR}/homebrew/shipd.rb" | sed 's/.*v\([0-9.]*\)\.tar\.gz.*/\1/' 2>/dev/null || echo "unknown")

    echo -e "${BOLD}Current Release Version${NC}"
    echo -e "  Git tag:     ${BLUE}v${CURRENT_TAG}${NC}"
    echo -e "  Formula:     ${BLUE}v${CURRENT_FORMULA}${NC}"
    echo ""
    echo "Usage: $0 [OPTIONS] <version>"
    echo ""
    echo "Options:"
    echo "  -y, --yes    Auto-confirm (skip prompts)"
    echo ""
    echo "Example:"
    echo "  $0 1.1.0"
    echo "  $0 -y 1.1.0"
    echo ""
    echo "This script will:"
    echo "  1. Create GitHub release v<version>"
    echo "  2. Update Homebrew formula with SHA256"
    echo "  3. Copy formula to homebrew-tap"
    echo "  4. Commit and push to tap repository"
    exit 1
fi

echo -e "${BLUE}Version: ${BOLD}${VERSION}${NC}"
echo ""

# Step 1: Prepare release
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}Step 1: Creating GitHub Release${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ "$AUTO_CONFIRM" = true ]; then
    "${SCRIPT_DIR}/homebrew/prepare-release.sh" -y "$VERSION"
else
    "${SCRIPT_DIR}/homebrew/prepare-release.sh" "$VERSION"
fi

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Release preparation failed${NC}"
    exit 1
fi

echo ""

# Step 2: Update tap
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}Step 2: Updating Homebrew Tap${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

"${SCRIPT_DIR}/homebrew/update-tap.sh"

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Tap update failed${NC}"
    exit 1
fi

# Summary
echo ""
echo -e "${GREEN}${BOLD}=========================================="
echo "✓ Release v${VERSION} Complete!"
echo -e "==========================================${NC}"
echo ""
echo -e "${BOLD}What was done:${NC}"
echo "  ✓ Created Git tag v${VERSION}"
echo "  ✓ Pushed tag to GitHub"
echo "  ✓ Updated formula with SHA256"
echo "  ✓ Updated Homebrew tap"
echo ""
echo -e "${BOLD}Next steps:${NC}"
echo "  1. Create GitHub release notes:"
echo "     https://github.com/guo/shipd/releases/tag/v${VERSION}"
echo ""
echo "  2. Users can install/update:"
echo -e "     ${BLUE}brew update${NC}"
echo -e "     ${BLUE}brew upgrade shipd${NC}"
echo ""
