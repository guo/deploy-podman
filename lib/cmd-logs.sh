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
    echo "Usage: shipd logs <target> [service] [options]"
    echo ""
    echo "Show container logs in follow mode."
    echo ""
    echo "Arguments:"
    echo "  target     Target name (e.g., myapp-prod)"
    echo "  service    Service name (compose mode only, optional)"
    echo ""
    echo "Options:"
    echo "  -n, --tail <lines>  Number of lines to show from the end (default: 100)"
    echo "  --no-follow         Show logs without following"
    echo ""
    echo "Examples:"
    echo "  shipd logs myapp-prod              # Follow logs for single container"
    echo "  shipd logs myapp-prod -n 50        # Follow last 50 lines"
    echo "  shipd logs myapp-prod --no-follow  # Show logs without following"
    echo "  shipd logs myapp-prod app          # Follow logs for 'app' service (compose)"
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
shift

# Parse optional arguments
SERVICE=""
TAIL_LINES="100"
FOLLOW=true

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--tail)
            TAIL_LINES="$2"
            shift 2
            ;;
        --no-follow)
            FOLLOW=false
            shift
            ;;
        -*)
            echo "Error: Unknown option: $1"
            exit 1
            ;;
        *)
            SERVICE="$1"
            shift
            ;;
    esac
done

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

# Build follow flag and SSH options
FOLLOW_FLAG=""
SSH_TTY=""
if [ "$FOLLOW" = true ]; then
    FOLLOW_FLAG="-f"
    SSH_TTY="-tt"  # Force TTY allocation for follow mode
fi

if [ "$DEPLOY_MODE" = "compose" ]; then
    REMOTE_BASE_DIR="/var/app/${CONTAINER_NAME}"

    echo "Showing logs for compose stack: ${TARGET}"
    if [ -n "$SERVICE" ]; then
        echo "Service: ${SERVICE}"
    fi
    if [ "$FOLLOW" = true ]; then
        echo "Press Ctrl+C to stop"
    fi
    echo "-------------------------------------------"

    # Run docker compose logs
    ssh ${SSH_TTY} ${SSH_HOST} "cd ${REMOTE_BASE_DIR} && docker compose -f ${COMPOSE_FILE} logs ${FOLLOW_FLAG} --tail=${TAIL_LINES} ${SERVICE}"
else
    # Check container status
    container_status=$(ssh ${SSH_HOST} "$ENGINE inspect ${CONTAINER_NAME} --format='{{.State.Status}}'" 2>/dev/null || echo "not found")

    echo "Showing logs for container: ${CONTAINER_NAME}"
    if [ "$container_status" != "running" ]; then
        echo "Warning: Container is ${container_status} (follow mode will exit after showing existing logs)"
    elif [ "$FOLLOW" = true ]; then
        echo "Press Ctrl+C to stop"
    fi
    echo "-------------------------------------------"

    # Run container logs
    ssh ${SSH_TTY} ${SSH_HOST} "$ENGINE logs ${FOLLOW_FLAG} --tail=${TAIL_LINES} ${CONTAINER_NAME}"
fi
