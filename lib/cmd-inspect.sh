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
    echo "Usage: shipd inspect <target>"
    echo ""
    echo "Inspect a deployed container's runtime information."
    echo ""
    echo "Shows:"
    echo "  - Container status and uptime"
    echo "  - Image information (tag, ID, registry digest)"
    echo "  - Port mappings and volumes"
    echo "  - Resource usage (CPU, memory)"
    echo "  - Health status (for Caddy deployments)"
    echo ""
    echo "Arguments:"
    echo "  target    Target name (e.g., myapp-prod)"
    echo ""
    echo "Example:"
    echo "  shipd inspect depinscan"
    echo ""
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

echo "=========================================="
echo "Container Inspection: ${TARGET}"
echo "=========================================="
echo ""
echo "SSH Host:     ${SSH_HOST}"
echo "Deploy Mode:  ${DEPLOY_MODE}"
echo "Engine:       ${ENGINE}"
echo ""

if [ "$DEPLOY_MODE" = "compose" ]; then
    # Compose mode inspection
    echo "==========================================="
    echo "Docker Compose Stack"
    echo "==========================================="
    echo ""

    REMOTE_BASE_DIR="/var/app/${CONTAINER_NAME:-${TARGET}}"

    # Get list of containers
    containers=$(ssh ${SSH_HOST} "cd ${REMOTE_BASE_DIR} && docker compose -f ${COMPOSE_FILE} ps -q 2>/dev/null" || echo "")

    if [ -z "$containers" ]; then
        echo "Status: NOT RUNNING"
        echo ""
        echo "No containers found for this compose stack."
        exit 0
    fi

    echo "Status: RUNNING"
    echo ""

    # Inspect each container
    for container_id in $containers; do
        [ -z "$container_id" ] && continue

        container_name=$(ssh ${SSH_HOST} "docker inspect ${container_id} --format='{{.Name}}' 2>/dev/null | sed 's|^/||'" || echo "")

        echo "-------------------------------------------"
        echo "Container: ${container_name}"
        echo "-------------------------------------------"

        # Basic info
        ssh ${SSH_HOST} "docker inspect ${container_id} --format='
Status:        {{.State.Status}}
Started:       {{.State.StartedAt}}
Image:         {{.Config.Image}}
Image ID:      {{.Image}}
Ports:         {{range \$p, \$conf := .NetworkSettings.Ports}}{{if \$conf}}{{(index \$conf 0).HostPort}}->{{(\$p)}} {{end}}{{end}}
'" 2>/dev/null || echo "  (unable to get details)"

        # Get registry digest
        current_image=$(ssh ${SSH_HOST} "docker inspect ${container_id} --format='{{.Config.Image}}'" 2>/dev/null || echo "")
        if [ -n "$current_image" ]; then
            registry_digest=$(ssh ${SSH_HOST} "docker inspect ${current_image} --format='{{.RepoDigests}}' 2>/dev/null | grep -oE 'sha256:[a-f0-9]{64}' | head -1" || echo "")
            if [ -n "$registry_digest" ]; then
                echo "Registry Digest: ${registry_digest}"
            fi
        fi

        echo ""
    done

else
    # Single container mode inspection
    CONTAINER_NAME="${CONTAINER_NAME:-${TARGET}}"

    echo "==========================================="
    echo "Container: ${CONTAINER_NAME}"
    echo "==========================================="
    echo ""

    # Check if container exists
    container_exists=$(ssh ${SSH_HOST} "$ENGINE ps -a --format '{{.Names}}' | grep -c '^${CONTAINER_NAME}\$' || true")

    if [ "$container_exists" -eq 0 ]; then
        echo "Status: NOT FOUND"
        echo ""
        echo "Container '${CONTAINER_NAME}' does not exist on ${SSH_HOST}"
        exit 0
    fi

    # Get container details
    echo "Basic Information:"
    echo "-------------------------------------------"
    ssh ${SSH_HOST} "$ENGINE inspect ${CONTAINER_NAME} --format='
Status:        {{.State.Status}}
Running:       {{.State.Running}}
Started:       {{.State.StartedAt}}
Restart Count: {{.RestartCount}}
'" 2>/dev/null || echo "  (unable to get details)"

    echo ""
    echo "Image Information:"
    echo "-------------------------------------------"

    # Image details
    current_image=$(ssh ${SSH_HOST} "$ENGINE inspect ${CONTAINER_NAME} --format='{{.Config.Image}}'" 2>/dev/null || echo "")
    image_id=$(ssh ${SSH_HOST} "$ENGINE inspect ${CONTAINER_NAME} --format='{{.Image}}'" 2>/dev/null || echo "")

    echo "Image Tag:     ${current_image}"
    echo "Image ID:      ${image_id}"

    # Get registry digest
    if [ -n "$current_image" ]; then
        registry_digest=$(ssh ${SSH_HOST} "$ENGINE inspect ${current_image} --format='{{.RepoDigests}}' 2>/dev/null | grep -oE 'sha256:[a-f0-9]{64}' | head -1" || echo "")
        if [ -n "$registry_digest" ]; then
            echo "Registry Digest: ${registry_digest}"
        else
            echo "Registry Digest: (not available)"
        fi
    fi

    echo ""
    echo "Network & Volumes:"
    echo "-------------------------------------------"

    # Port mappings
    ports=$(ssh ${SSH_HOST} "$ENGINE inspect ${CONTAINER_NAME} --format='{{range \$p, \$conf := .NetworkSettings.Ports}}{{if \$conf}}{{(index \$conf 0).HostPort}}->{{(\$p)}} {{end}}{{end}}'" 2>/dev/null || echo "")
    if [ -n "$ports" ]; then
        echo "Ports:         ${ports}"
    else
        echo "Ports:         (none)"
    fi

    # Volume mounts
    volumes=$(ssh ${SSH_HOST} "$ENGINE inspect ${CONTAINER_NAME} --format='{{range .Mounts}}{{.Source}}:{{.Destination}} {{end}}'" 2>/dev/null || echo "")
    if [ -n "$volumes" ]; then
        echo "Volumes:       ${volumes}"
    else
        echo "Volumes:       (none)"
    fi

    # Check if Caddy deployment
    USE_CADDY="${USE_CADDY:-false}"
    if [ "$USE_CADDY" = "true" ]; then
        echo ""
        echo "Caddy Zero-Downtime:"
        echo "-------------------------------------------"
        echo "Enabled:       Yes"
        echo "Domain:        ${DOMAIN:-not set}"

        # Check Caddy container
        caddy_container="caddy-${CONTAINER_NAME}"
        caddy_status=$(ssh ${SSH_HOST} "$ENGINE inspect ${caddy_container} --format='{{.State.Status}}' 2>/dev/null" || echo "not found")
        echo "Caddy Status:  ${caddy_status}"

        if [ "$caddy_status" = "running" ]; then
            # Get upstream from Caddy config
            upstream=$(ssh ${SSH_HOST} "$ENGINE exec ${caddy_container} cat /etc/caddy/Caddyfile 2>/dev/null | grep 'reverse_proxy' | awk '{print \$2}'" || echo "")
            if [ -n "$upstream" ]; then
                echo "Upstream:      ${upstream}"
            fi
        fi
    fi

    echo ""
    echo "Resource Usage:"
    echo "-------------------------------------------"

    # Get stats (single snapshot)
    stats=$(ssh ${SSH_HOST} "$ENGINE stats ${CONTAINER_NAME} --no-stream --format 'CPU: {{.CPUPerc}}  Memory: {{.MemUsage}}' 2>/dev/null" || echo "(unable to get stats)")
    echo "${stats}"
fi

echo ""
echo "==========================================="
echo ""
