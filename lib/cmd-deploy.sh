#!/bin/bash

set -e

# Detect lib directory (for sourcing deployment modules)
if [ -d "/opt/homebrew/lib/shipd" ] && [ ! -d "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib" ]; then
    # Homebrew (Apple Silicon)
    LIB_DIR="/opt/homebrew/lib/shipd"
elif [ -d "/usr/local/lib/shipd" ] && [ ! -d "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib" ]; then
    # Homebrew (Intel) or manual install
    LIB_DIR="/usr/local/lib/shipd"
else
    # Development mode
    LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Find targets directory (search current dir, then home dir)
find_targets_dir() {
    if [ -d "./targets" ]; then
        echo "$(pwd)/targets"
    elif [ -d "$HOME/.shipd/targets" ]; then
        echo "$HOME/.shipd/targets"
    else
        echo ""
    fi
}

# Find global config file (search current dir, then home dir)
find_global_config() {
    if [ -f "./.config" ]; then
        echo "$(pwd)/.config"
    elif [ -f "$HOME/.shipd/.config" ]; then
        echo "$HOME/.shipd/.config"
    else
        echo ""
    fi
}

# Function to list available targets
list_targets() {
    local TARGETS_DIR=$(find_targets_dir)
    echo "Available targets:"
    if [ -n "$TARGETS_DIR" ] && [ -d "$TARGETS_DIR" ]; then
        for dir in "$TARGETS_DIR"/*/ ; do
            if [ -d "$dir" ]; then
                target_name=$(basename "$dir")
                # Detect deployment mode
                if [ -f "$dir/docker-compose.yml" ] || [ -f "$dir/compose.yml" ]; then
                    echo "  - $target_name (compose → docker)"
                else
                    # Check ENGINE setting
                    engine="podman"
                    if [ -f "$dir/.config" ]; then
                        source "$dir/.config"
                        engine="${ENGINE:-podman}"
                    fi
                    echo "  - $target_name (single → $engine)"
                fi
            fi
        done
    else
        echo "  (no targets found)"
        echo "  Searched:"
        echo "    - ./targets/"
        echo "    - ~/.shipd/targets/"
    fi
}

# Parse flags
AUTO_CONFIRM=false
FORCE_DEPLOY=false
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -y|--yes)
            AUTO_CONFIRM=true
            shift
            ;;
        -f|--force)
            FORCE_DEPLOY=true
            shift
            ;;
        --help|-h)
            echo "Usage: shipd deploy [OPTIONS] <target> [image-tag]"
            echo ""
            echo "Deploy a containerized application to a remote server via SSH."
            echo "Supports both single-container and multi-container (compose) deployments."
            echo "Automatically selects Docker or Podman based on target configuration."
            echo ""
            echo "Options:"
            echo "  -y, --yes     Auto-confirm deployment (skip confirmation prompt)"
            echo "  -f, --force   Force deployment even if image hash unchanged"
            echo "  -h, --help    Show this help message"
            echo ""
            echo "Arguments:"
            echo "  target      Target name (e.g., myapp)"
            echo "  image-tag   Optional image tag (default: latest)"
            echo ""
            list_targets
            echo ""
            echo "Engine Selection:"
            echo "  - Compose files (docker-compose.yml) → Always uses Docker"
            echo "  - Single-container → Uses ENGINE from .config (default: podman)"
            echo ""
            echo "Examples:"
            echo "  shipd deploy myapp              # Deploy latest"
            echo "  shipd deploy myapp v1.2.3       # Deploy specific version"
            echo "  shipd deploy myapp -y           # Deploy latest with auto-confirm"
            echo "  shipd deploy -y myapp v1.2.3    # Deploy with auto-confirm"
            echo "  shipd deploy -f myapp           # Force deploy even if hash unchanged"
            exit 0
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

# Restore positional parameters
set -- "${POSITIONAL_ARGS[@]}"

# Check required arguments
if [[ -z "$1" ]]; then
    echo "Error: Missing required argument <target>"
    echo ""
    echo "Usage: shipd deploy [OPTIONS] <target> [image-tag]"
    echo "Try 'shipd deploy --help' for more information."
    exit 1
fi

TARGET="$1"
IMAGE_TAG="${2:-latest}"

# Find targets directory and locate target
TARGETS_DIR=$(find_targets_dir)
if [ -z "$TARGETS_DIR" ]; then
    echo "Error: No targets directory found"
    echo ""
    echo "Searched locations:"
    echo "  - ./targets/"
    echo "  - ~/.shipd/targets/"
    echo ""
    echo "Create one with:"
    echo "  mkdir -p ./targets/${TARGET}"
    echo "  or"
    echo "  mkdir -p ~/.shipd/targets/${TARGET}"
    exit 1
fi

TARGET_DIR="${TARGETS_DIR}/${TARGET}"

# Verify target directory exists
if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Target directory not found: ${TARGET_DIR}"
    echo ""
    echo "Create it with:"
    if [ "$TARGETS_DIR" = "$(pwd)/targets" ]; then
        echo "  mkdir -p ./targets/${TARGET}"
    else
        echo "  mkdir -p ~/.shipd/targets/${TARGET}"
    fi
    echo ""
    list_targets
    exit 1
fi

# Load global config if it exists (defaults)
GLOBAL_CONFIG=$(find_global_config)
if [ -n "$GLOBAL_CONFIG" ]; then
    source "$GLOBAL_CONFIG"
fi

# Load target-specific config (overrides global)
if [ -f "${TARGET_DIR}/.config" ]; then
    source "${TARGET_DIR}/.config"
else
    echo "Error: Target config not found: ${TARGET_DIR}/.config"
    echo ""
    echo "Create it with: cp .config.example targets/${TARGET}/.config"
    exit 1
fi

# Check if Caddy zero-downtime deployment is enabled
USE_CADDY="${USE_CADDY:-false}"

# Detect deployment mode and engine
COMPOSE_FILE=""
DEPLOY_MODE="single"

if [ -f "${TARGET_DIR}/compose.yml" ]; then
    COMPOSE_FILE="compose.yml"
    DEPLOY_MODE="compose"
    ENGINE="docker"  # Force Docker for compose
    echo "Detected: Compose deployment (docker-compose.yml)"
elif [ -f "${TARGET_DIR}/docker-compose.yml" ]; then
    COMPOSE_FILE="docker-compose.yml"
    DEPLOY_MODE="compose"
    ENGINE="docker"  # Force Docker for compose
    echo "Detected: Compose deployment (docker-compose.yml)"
else
    # Single-container mode - use ENGINE from config or default to podman
    ENGINE="${ENGINE:-podman}"
    echo "Detected: Single-container deployment (using ${ENGINE})"
fi

# Validate Caddy configuration if enabled
if [ "$USE_CADDY" = "true" ]; then
    # Caddy only supports single-container deployments
    if [ "$DEPLOY_MODE" = "compose" ]; then
        echo "❌ Error: USE_CADDY=true not supported for compose deployments"
        echo "Target '${TARGET}' has compose.yml (multi-container)"
        echo ""
        echo "Options:"
        echo "  1. Set USE_CADDY=false in ${TARGET_DIR}/.config"
        echo "  2. Use deploy.sh without USE_CADDY for compose (brief downtime)"
        echo ""
        echo "Zero-downtime compose deployment is planned for future release."
        exit 1
    fi

    # Validate required Caddy settings
    if [ -z "$DOMAIN" ]; then
        echo "⚠️  Warning: DOMAIN not set in ${TARGET_DIR}/.config"
        echo "DOMAIN is recommended for automatic HTTPS with Caddy"
        echo ""
    fi

    # Set defaults for health check
    APP_PORT="${APP_PORT:-3000}"
    HEALTH_CHECK_PATH="${HEALTH_CHECK_PATH:-/}"
    HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-30}"

    echo "✓ Caddy zero-downtime deployment enabled"
    echo ""
fi

# Default CONTAINER_NAME to target name if not specified (single container mode only)
if [ -z "$CONTAINER_NAME" ]; then
    CONTAINER_NAME="$TARGET"
fi

# Verify required variables
if [ -z "$SSH_HOST" ]; then
    echo "Error: SSH_HOST not set in ${TARGET_DIR}/.config"
    exit 1
fi

# CONTAINER_IMAGE only required for single container mode with Podman/Docker
if [ "$DEPLOY_MODE" = "single" ] && [ -z "$CONTAINER_IMAGE" ]; then
    echo "Error: CONTAINER_IMAGE not set in ${TARGET_DIR}/.config"
    exit 1
fi

# Check if .env file exists in target directory
if [ ! -f "${TARGET_DIR}/.env" ]; then
    echo "Error: .env file not found in ${TARGET_DIR}/"
    echo "Please create: targets/${TARGET}/.env"
    exit 1
fi

# Build full image name with tag for single container mode
if [ "$DEPLOY_MODE" = "single" ]; then
    BASE_IMAGE="${CONTAINER_IMAGE%:*}"
    FULL_IMAGE="${BASE_IMAGE}:${IMAGE_TAG}"
fi

# Set remote paths
if [ "$DEPLOY_MODE" = "compose" ]; then
    # For compose, use target name as base directory
    REMOTE_BASE_DIR="/var/app/${TARGET}"
else
    REMOTE_BASE_DIR="/var/app/${CONTAINER_NAME}"
fi
REMOTE_ENV_FILE="${REMOTE_BASE_DIR}/.env"

# Display deployment configuration
echo "========================================"
echo "Deployment Configuration"
echo "========================================"
echo "Target:           ${TARGET}"
echo "Deploy Mode:      ${DEPLOY_MODE}"
echo "Container Engine: ${ENGINE}"
echo "SSH Host:         ${SSH_HOST}"
echo ""

if [ "$DEPLOY_MODE" = "single" ]; then
    echo "Container Name:   ${CONTAINER_NAME}"
    echo "Image:            ${FULL_IMAGE}"
    echo ""
fi

if [ "$USE_CADDY" = "true" ]; then
    echo "Zero-Downtime:    Enabled (Caddy)"
    echo "Domain:           ${DOMAIN:-<not set>}"
    echo "App Port:         ${APP_PORT}"
    echo "Health Check:     ${HEALTH_CHECK_PATH} (timeout: ${HEALTH_CHECK_TIMEOUT}s)"
    echo ""
fi

if [ "$DEPLOY_MODE" = "compose" ]; then
    echo "Compose File:     ${COMPOSE_FILE}"
    echo "Image Tag:        ${IMAGE_TAG}"
    echo ""
fi

if [ "$DEPLOY_MODE" = "single" ] && [ -n "$PORT_MAPPINGS" ]; then
    echo "Port Mappings:    ${PORT_MAPPINGS}"
    echo ""
fi

if [ -n "$FILE_MAPPINGS" ]; then
    echo "File Mappings:    ${FILE_MAPPINGS}"
    echo ""
fi

if [ -n "$GHCR_USERNAME" ]; then
    echo "Registry Auth:    ${GHCR_USERNAME} (token configured)"
    echo ""
fi

echo "Remote Path:      ${REMOTE_BASE_DIR}"
echo "========================================"
echo ""

# Confirmation prompt (skip if -y flag provided)
if [ "$AUTO_CONFIRM" = false ]; then
    read -p "Continue with deployment? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Deployment cancelled."
        exit 0
    fi
    echo ""
fi

# Check SSH connection
echo "Checking SSH connection to ${SSH_HOST}..."
if ! ssh ${SSH_HOST} "echo 'SSH connection successful'" >/dev/null 2>&1; then
    echo "Error: Cannot connect to ${SSH_HOST}"
    exit 1
fi
echo "✓ SSH connection verified"
echo ""

# Check if this is a first deployment (before creating directory)
REMOTE_DIR_EXISTS=$(ssh ${SSH_HOST} "[ -d '${REMOTE_BASE_DIR}' ] && echo 'yes' || echo 'no'")

if [ "$REMOTE_DIR_EXISTS" = "no" ]; then
    echo ""
    echo "⚠️  WARNING: FIRST DEPLOYMENT DETECTED"
    echo "========================================="
    echo ""
    echo "No existing deployment folder found on server!"
    echo ""
    echo "Server:        ${SSH_HOST}"
    echo "Target:        ${TARGET}"
    echo "Remote folder: ${REMOTE_BASE_DIR}"
    echo ""
    echo "This appears to be a first-time deployment for this target."
    echo ""
    echo "⚠️  Please verify:"
    echo "  • Target name is correct: ${TARGET}"
    echo "  • SSH host is correct: ${SSH_HOST}"
    echo "  • You intend to deploy to this server"
    echo "  • This is not an old/deprecated target"
    echo ""
    echo "========================================="
    echo ""

    # Always prompt for first deployment (even with -y flag)
    read -p "Type 'yes' to proceed with FIRST deployment (or anything else to cancel): " -r
    echo ""

    if [[ ! "$REPLY" =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "✗ Deployment cancelled"
        echo ""
        exit 0
    fi

    echo "✓ First deployment confirmed"
    echo ""
fi

# Upload target directory to remote host
echo "Uploading target files..."
# Ensure the remote directory exists
ssh ${SSH_HOST} "mkdir -p ${REMOTE_BASE_DIR}"
# Upload all files from target directory (including hidden files)
shopt -s dotglob  # Enable matching hidden files
scp -r "${TARGET_DIR}/"* ${SSH_HOST}:${REMOTE_BASE_DIR}/ 2>/dev/null || \
    echo "Warning: No files to upload (this is normal if directory is empty)"
shopt -u dotglob  # Disable dotglob
echo "✓ Target files uploaded to ${REMOTE_BASE_DIR}"
echo ""

# Export FORCE_DEPLOY for deployment modules
export FORCE_DEPLOY

# Delegate to appropriate deployment module
if [ "$USE_CADDY" = "true" ]; then
    # Zero-downtime deployment via Caddy (single-container only)
    source "${LIB_DIR}/deploy-caddy.sh"
    deploy_with_caddy
elif [ "$DEPLOY_MODE" = "compose" ]; then
    # Docker Compose deployment
    source "${LIB_DIR}/deploy-docker.sh"
    deploy_docker_compose
elif [ "$ENGINE" = "docker" ]; then
    # Docker single-container deployment
    source "${LIB_DIR}/deploy-docker.sh"
    deploy_docker_single
elif [ "$ENGINE" = "podman" ]; then
    # Podman single-container deployment
    source "${LIB_DIR}/deploy-podman.sh"
    deploy_with_podman
else
    echo "Error: Unknown engine: ${ENGINE}"
    echo "Supported engines: docker, podman"
    exit 1
fi
