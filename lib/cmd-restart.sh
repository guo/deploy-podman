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

# Find global config
find_global_config() {
    if [ -f "./.config" ]; then
        echo "$(pwd)/.config"
    elif [ -f "$HOME/.shipd/.config" ]; then
        echo "$HOME/.shipd/.config"
    else
        echo ""
    fi
}

# Parse arguments
if [[ $# -eq 0 ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    echo "Usage: shipd restart <target> [service]"
    echo ""
    echo "Restart a container or compose service."
    echo ""
    echo "Arguments:"
    echo "  target     Target name (e.g., myapp-prod)"
    echo "  service    Service name (compose mode only, optional)"
    echo ""
    echo "Examples:"
    echo "  shipd restart myapp-prod        # Restart single container"
    echo "  shipd restart myapp-prod app    # Restart 'app' service (compose)"
    echo ""
    targets=()
    for search_dir in "./targets" "$HOME/.shipd/targets"; do
        if [ -d "$search_dir" ]; then
            for dir in "$search_dir"/*/ ; do
                if [ -d "$dir" ]; then
                    targets+=("$(basename "$dir")")
                fi
            done
        fi
    done
    if [ ${#targets[@]} -gt 0 ]; then
        echo "Available targets:"
        for t in "${targets[@]}"; do
            echo "  - $t"
        done
        echo ""
    fi
    exit 0
fi

TARGET="$1"
SERVICE="${2:-}"

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

# Detect deployment mode and engine
COMPOSE_FILE=""
DEPLOY_MODE="single"

if [ -f "${TARGET_DIR}/compose.yml" ]; then
    COMPOSE_FILE="compose.yml"
    DEPLOY_MODE="compose"
    ENGINE="docker"
elif [ -f "${TARGET_DIR}/docker-compose.yml" ]; then
    COMPOSE_FILE="docker-compose.yml"
    DEPLOY_MODE="compose"
    ENGINE="docker"
else
    ENGINE="${ENGINE:-podman}"
fi

# Validate SSH_HOST
if [ -z "$SSH_HOST" ]; then
    echo "Error: SSH_HOST not configured in ${TARGET_DIR}/.config"
    exit 1
fi

# Check SSH connection
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes ${SSH_HOST} exit 2>/dev/null; then
    echo "Error: Cannot connect to ${SSH_HOST}"
    exit 1
fi

CONTAINER_NAME="${CONTAINER_NAME:-${TARGET}}"

if [ "$DEPLOY_MODE" = "compose" ]; then
    REMOTE_BASE_DIR="/var/app/${CONTAINER_NAME}"

    echo "Restarting compose stack: ${TARGET}"
    if [ -n "$SERVICE" ]; then
        echo "Service: ${SERVICE}"
        ssh ${SSH_HOST} "cd ${REMOTE_BASE_DIR} && docker compose -f ${COMPOSE_FILE} restart ${SERVICE}"
    else
        ssh ${SSH_HOST} "cd ${REMOTE_BASE_DIR} && docker compose -f ${COMPOSE_FILE} restart"
    fi
else
    echo "Restarting container: ${CONTAINER_NAME}"
    ssh ${SSH_HOST} "$ENGINE restart ${CONTAINER_NAME}"
fi

echo "Done."
