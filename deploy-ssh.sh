#!/bin/bash

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to list available targets
list_targets() {
    echo "Available targets:"
    if [ -d "${SCRIPT_DIR}/targets" ]; then
        for dir in "${SCRIPT_DIR}/targets"/*/ ; do
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
        echo "  (no targets found - create targets/ directory)"
    fi
}

# Check arguments
if [[ "$1" == "--help" || "$1" == "-h" || -z "$1" ]]; then
    echo "Usage: $0 <target> [image-tag]"
    echo ""
    echo "Deploy a containerized application to a remote server via SSH."
    echo "Supports both single-container and multi-container (compose) deployments."
    echo "Automatically selects Docker or Podman based on target configuration."
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
    echo "  $0 myapp              # Deploy latest"
    echo "  $0 myapp v1.2.3       # Deploy specific version"
    echo "  $0 myapp sha-abc123   # Deploy specific commit"
    exit 0
fi

TARGET="$1"
IMAGE_TAG="${2:-latest}"
TARGET_DIR="${SCRIPT_DIR}/targets/${TARGET}"

# Verify target directory exists
if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Target directory not found: ${TARGET_DIR}"
    echo ""
    echo "Create it with: mkdir -p targets/${TARGET}"
    echo ""
    list_targets
    exit 1
fi

# Load global config if it exists (defaults)
if [ -f "${SCRIPT_DIR}/.config" ]; then
    source "${SCRIPT_DIR}/.config"
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

# Check SSH connection
echo "Checking SSH connection to ${SSH_HOST}..."
if ! ssh ${SSH_HOST} "echo 'SSH connection successful'" >/dev/null 2>&1; then
    echo "Error: Cannot connect to ${SSH_HOST}"
    exit 1
fi
echo "✓ SSH connection verified"
echo ""

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

# Delegate to appropriate deployment module
if [ "$DEPLOY_MODE" = "compose" ]; then
    # Docker Compose deployment
    source "${SCRIPT_DIR}/lib/deploy-docker.sh"
    deploy_docker_compose
elif [ "$ENGINE" = "docker" ]; then
    # Docker single-container deployment
    source "${SCRIPT_DIR}/lib/deploy-docker.sh"
    deploy_docker_single
elif [ "$ENGINE" = "podman" ]; then
    # Podman single-container deployment
    source "${SCRIPT_DIR}/lib/deploy-podman.sh"
    deploy_with_podman
else
    echo "Error: Unknown engine: ${ENGINE}"
    echo "Supported engines: docker, podman"
    exit 1
fi
