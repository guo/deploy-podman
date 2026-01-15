#!/bin/bash

# Prepare a release and update Homebrew formula

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

echo -e "${BLUE}=========================================="
echo "Shipd Release Preparation"
echo -e "==========================================${NC}"
echo ""

# Get version from user
if [ -z "$VERSION" ]; then
    echo "Usage: $0 [OPTIONS] <version>"
    echo ""
    echo "Options:"
    echo "  -y, --yes    Auto-confirm (skip prompts)"
    echo ""
    echo "Example:"
    echo "  $0 1.0.0"
    echo "  $0 -y 1.0.0"
    echo ""
    exit 1
fi

TAG="v${VERSION}"

# Check if tag already exists
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo -e "${RED}Error: Tag $TAG already exists${NC}"
    echo ""
    echo "Existing tags:"
    git tag | grep "^v" | tail -5
    exit 1
fi

# Check if working directory is clean
if [ -n "$(git status --porcelain)" ]; then
    echo -e "${YELLOW}Warning: Working directory has uncommitted changes${NC}"
    git status --short
    echo ""
    if [ "$AUTO_CONFIRM" = false ]; then
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    else
        echo "Auto-confirming (--yes flag)"
    fi
fi

# Get GitHub repo info
REMOTE_URL=$(git config --get remote.origin.url)
if [[ $REMOTE_URL =~ github.com[:/]([^/]+)/([^/.]+) ]]; then
    GITHUB_USER="${BASH_REMATCH[1]}"
    GITHUB_REPO="${BASH_REMATCH[2]}"
else
    echo -e "${RED}Error: Cannot detect GitHub repository${NC}"
    echo "Remote URL: $REMOTE_URL"
    exit 1
fi

TARBALL_URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}/archive/refs/tags/${TAG}.tar.gz"

echo "Release Information:"
echo "  Version:    ${VERSION}"
echo "  Tag:        ${TAG}"
echo "  Repository: ${GITHUB_USER}/${GITHUB_REPO}"
echo "  Tarball:    ${TARBALL_URL}"
echo ""

if [ "$AUTO_CONFIRM" = false ]; then
    read -p "Create release ${TAG}? (y/N) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
else
    echo "Auto-confirming release creation (--yes flag)"
    echo ""
fi

# Create tag
echo ""
echo -e "${BLUE}[1/4] Creating Git tag...${NC}"
git tag -a "$TAG" -m "Release ${VERSION}"
echo -e "${GREEN}✓ Tag created${NC}"

# Push tag
echo ""
echo -e "${BLUE}[2/4] Pushing tag to GitHub...${NC}"
git push origin "$TAG"
echo -e "${GREEN}✓ Tag pushed${NC}"

# Wait for GitHub to generate tarball
echo ""
echo -e "${BLUE}[3/4] Waiting for GitHub to generate tarball...${NC}"
echo "Checking: ${TARBALL_URL}"
for i in {1..10}; do
    if curl -sfL "$TARBALL_URL" >/dev/null; then
        echo -e "${GREEN}✓ Tarball available${NC}"
        break
    fi
    if [ $i -eq 10 ]; then
        echo -e "${RED}✗ Tarball not available after 30 seconds${NC}"
        echo "You may need to wait and run the SHA256 calculation manually:"
        echo "  curl -sL ${TARBALL_URL} | shasum -a 256"
        exit 1
    fi
    echo "  Waiting... ($i/10)"
    sleep 3
done

# Calculate SHA256
echo ""
echo -e "${BLUE}[4/4] Calculating SHA256...${NC}"
SHA256=$(curl -sL "$TARBALL_URL" | shasum -a 256 | cut -d' ' -f1)
echo -e "${GREEN}✓ SHA256: ${SHA256}${NC}"

# Update formula
echo ""
echo -e "${BLUE}Updating Homebrew formula...${NC}"
if [ -f "${SCRIPT_DIR}/shipd.rb" ]; then
    # Update version in formula
    sed -i.bak "s|url \".*\"|url \"${TARBALL_URL}\"|g" "${SCRIPT_DIR}/shipd.rb"
    sed -i.bak "s|sha256 \".*\"|sha256 \"${SHA256}\"|g" "${SCRIPT_DIR}/shipd.rb"
    rm -f "${SCRIPT_DIR}/shipd.rb.bak"
    echo -e "${GREEN}✓ Formula updated${NC}"
    echo ""
    echo "Changes to shipd.rb:"
    git diff "${SCRIPT_DIR}/shipd.rb" || true
else
    echo -e "${YELLOW}⚠️  Formula not found at ${SCRIPT_DIR}/shipd.rb${NC}"
    echo "Create it manually with:"
    echo "  url \"${TARBALL_URL}\""
    echo "  sha256 \"${SHA256}\""
fi

echo ""
echo -e "${GREEN}=========================================="
echo "✓ Release ${TAG} prepared!"
echo -e "==========================================${NC}"
echo ""
echo "Next steps:"
echo "  1. Commit formula changes:"
echo "     git add shipd.rb"
echo "     git commit -m \"Update formula for ${VERSION}\""
echo "     git push"
echo ""
echo "  2. Create GitHub release:"
echo "     https://github.com/${GITHUB_USER}/${GITHUB_REPO}/releases/new?tag=${TAG}"
echo ""
echo "  3. If using Homebrew tap:"
echo "     cp shipd.rb /path/to/homebrew-tap/Formula/"
echo "     cd /path/to/homebrew-tap"
echo "     git add Formula/shipd.rb"
echo "     git commit -m \"shipd ${VERSION}\""
echo "     git push"
echo ""
echo "  4. Test installation:"
echo "     brew uninstall shipd # if already installed"
echo "     brew install guo/tap/shipd"
echo ""
