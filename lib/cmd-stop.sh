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
REMOVE_CONTAINER=false
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -y|--yes)
            AUTO_CONFIRM=true
            shift
            ;;
        -r|--remove)
            REMOVE_CONTAINER=true
            shift
            ;;
        --help|-h)
            echo "Usage: shipd stop [OPTIONS] <target>"
            echo ""
            echo "Stop a deployed containerized application on a remote server."
            echo "Supports both single-container and multi-container (compose) deployments."
            echo ""
            echo "Options:"
            echo "  -y, --yes      Auto-confirm stop (skip confirmation prompt)"
            echo "  -r, --remove   Remove container after stopping (default: keep stopped)"
            echo "  -h, --help     Show this help message"
            echo ""
            echo "Arguments:"
            echo "  target      Target name (e.g., myapp-prod)"
            echo ""
            list_targets
            echo ""
            echo "Examples:"
            echo "  shipd stop myapp-prod              # Stop container"
            echo "  shipd stop myapp-prod -y           # Stop with auto-confirm"
            echo "  shipd stop myapp-prod -r           # Stop and remove container"
            echo "  shipd stop myapp-prod -y -r        # Stop, remove, auto-confirm"
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
    echo "Usage: shipd stop [OPTIONS] <target>"
    echo "Try 'shipd stop --help' for more information."
    exit 1
fi

TARGET="$1"

# Find targets directory and locate target
TARGETS_DIR=$(find_targets_dir)
if [ -z "$TARGETS_DIR" ]; then
    echo "Error: No targets directory found"
    echo ""
    echo "Searched locations:"
    echo "  - ./targets/"
    echo "  - ~/.shipd/targets/"
    exit 1
fi

TARGET_DIR="${TARGETS_DIR}/${TARGET}"

# Verify target directory exists
if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Target directory not found: ${TARGET_DIR}"
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
elif [ -f "${TARGET_DIR}/docker-compose.yml" ]; then
    COMPOSE_FILE="docker-compose.yml"
    DEPLOY_MODE="compose"
    ENGINE="docker"  # Force Docker for compose
else
    # Single-container mode - use ENGINE from config or default to podman
    ENGINE="${ENGINE:-podman}"
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

# Set remote paths
if [ "$DEPLOY_MODE" = "compose" ]; then
    # For compose, use target name as base directory
    REMOTE_BASE_DIR="/var/app/${TARGET}"
else
    REMOTE_BASE_DIR="/var/app/${CONTAINER_NAME}"
fi

# Display stop configuration
echo "========================================"
echo "Stop Configuration"
echo "========================================"
echo "Target:           ${TARGET}"
echo "Deploy Mode:      ${DEPLOY_MODE}"
echo "Container Engine: ${ENGINE}"
echo "SSH Host:         ${SSH_HOST}"
echo ""

if [ "$DEPLOY_MODE" = "single" ]; then
    echo "Container Name:   ${CONTAINER_NAME}"
    echo ""
fi

if [ "$DEPLOY_MODE" = "compose" ]; then
    echo "Compose File:     ${COMPOSE_FILE}"
    echo "Remote Path:      ${REMOTE_BASE_DIR}"
    echo ""
fi

if [ "$REMOVE_CONTAINER" = true ]; then
    echo "Action:           Stop and Remove"
else
    echo "Action:           Stop"
fi
echo "========================================"
echo ""

# Confirmation prompt (skip if -y flag provided)
if [ "$AUTO_CONFIRM" = false ]; then
    read -p "Continue with stop? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Stop cancelled."
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

# Execute stop based on deployment mode
if [ "$DEPLOY_MODE" = "compose" ]; then
    echo "========================================="
    echo "Stopping Docker Compose Stack"
    echo "========================================="
    echo ""

    # Check if directory exists
    if ! ssh ${SSH_HOST} "[ -d '${REMOTE_BASE_DIR}' ]" 2>/dev/null; then
        echo "⚠️  Warning: Remote directory not found: ${REMOTE_BASE_DIR}"
        echo "Target may not be deployed or already stopped."
        exit 0
    fi

    # Check if compose file exists
    if ! ssh ${SSH_HOST} "[ -f '${REMOTE_BASE_DIR}/${COMPOSE_FILE}' ]" 2>/dev/null; then
        echo "⚠️  Warning: Compose file not found: ${REMOTE_BASE_DIR}/${COMPOSE_FILE}"
        echo "Target may not be deployed or already stopped."
        exit 0
    fi

    # Stop the compose stack
    echo "Stopping compose stack..."
    if [ "$REMOVE_CONTAINER" = true ]; then
        ssh ${SSH_HOST} "cd ${REMOTE_BASE_DIR} && docker compose down"
        echo "✓ Compose stack stopped and removed"
    else
        ssh ${SSH_HOST} "cd ${REMOTE_BASE_DIR} && docker compose stop"
        echo "✓ Compose stack stopped"
    fi
    echo ""

    # Show status
    echo "Checking container status..."
    ssh ${SSH_HOST} "cd ${REMOTE_BASE_DIR} && docker compose ps -a" || true
    echo ""

else
    # Single-container mode
    echo "========================================="
    echo "Stopping ${ENGINE^} Container"
    echo "========================================="
    echo ""

    # Check if container exists
    if ! ssh ${SSH_HOST} "${ENGINE} ps -a --format '{{.Names}}' | grep -q '^${CONTAINER_NAME}\$'" 2>/dev/null; then
        echo "⚠️  Warning: Container '${CONTAINER_NAME}' not found"
        echo "Target may not be deployed or already removed."
        exit 0
    fi

    # Check if container is running
    IS_RUNNING=$(ssh ${SSH_HOST} "${ENGINE} ps --format '{{.Names}}' | grep -q '^${CONTAINER_NAME}\$' && echo 'yes' || echo 'no'")

    if [ "$IS_RUNNING" = "no" ]; then
        echo "Container is already stopped"
        if [ "$REMOVE_CONTAINER" = true ]; then
            echo ""
            echo "Removing stopped container..."
            ssh ${SSH_HOST} "${ENGINE} rm ${CONTAINER_NAME}"
            echo "✓ Container removed"
        fi
    else
        echo "Stopping container '${CONTAINER_NAME}'..."
        ssh ${SSH_HOST} "${ENGINE} stop ${CONTAINER_NAME}"
        echo "✓ Container stopped"
        echo ""

        if [ "$REMOVE_CONTAINER" = true ]; then
            echo "Removing container..."
            ssh ${SSH_HOST} "${ENGINE} rm ${CONTAINER_NAME}"
            echo "✓ Container removed"
        fi
    fi
    echo ""

    # Show container status
    echo "Checking container status..."
    ssh ${SSH_HOST} "${ENGINE} ps -a --filter name=^${CONTAINER_NAME}\$ --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'" || echo "Container not found (may have been removed)"
    echo ""
fi

echo "========================================="
echo "Stop Complete"
echo "========================================="
echo ""
echo "Target: ${TARGET}"
if [ "$DEPLOY_MODE" = "single" ]; then
    echo "Container: ${CONTAINER_NAME}"
fi
echo ""

if [ "$REMOVE_CONTAINER" = false ]; then
    echo "To restart the container:"
    if [ "$DEPLOY_MODE" = "compose" ]; then
        echo "  ssh ${SSH_HOST} 'cd ${REMOTE_BASE_DIR} && docker compose start'"
    else
        echo "  ssh ${SSH_HOST} '${ENGINE} start ${CONTAINER_NAME}'"
    fi
    echo ""
    echo "To remove the stopped container:"
    echo "  shipd stop ${TARGET} --remove"
else
    echo "Container removed. To redeploy:"
    echo "  shipd deploy ${TARGET}"
fi
echo ""
