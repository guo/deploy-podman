#!/bin/bash

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to show usage
show_usage() {
    echo "Usage: $0 <target> [image-tag]"
    echo ""
    echo "Deploy application with zero-downtime using Caddy reverse proxy."
    echo ""
    echo "Arguments:"
    echo "  target      Target name (e.g., depinscan)"
    echo "  image-tag   Optional image tag (default: latest)"
    echo ""
    echo "Examples:"
    echo "  $0 depinscan              # Deploy latest"
    echo "  $0 depinscan v1.2.3       # Deploy specific version"
    echo "  $0 depinscan sha-abc123   # Deploy specific commit"
    echo ""
    echo "Prerequisites:"
    echo "  1. Run './setup-caddy.sh <target>' first to setup Caddy"
    echo "  2. Ensure target/.config has DOMAIN and APP_PORT configured"
    echo ""
}

# Check arguments
if [[ "$1" == "--help" || "$1" == "-h" || -z "$1" ]]; then
    show_usage
    exit 0
fi

TARGET="$1"
IMAGE_TAG="${2:-latest}"
TARGET_DIR="${SCRIPT_DIR}/targets/${TARGET}"

# Verify target directory exists
if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Target directory not found: ${TARGET_DIR}"
    exit 1
fi

# Load global config if exists
if [ -f "${SCRIPT_DIR}/.config" ]; then
    source "${SCRIPT_DIR}/.config"
fi

# Load target config
if [ -f "${TARGET_DIR}/.config" ]; then
    source "${TARGET_DIR}/.config"
else
    echo "Error: Target config not found: ${TARGET_DIR}/.config"
    exit 1
fi

# Default CONTAINER_NAME to target if not specified
if [ -z "$CONTAINER_NAME" ]; then
    CONTAINER_NAME="$TARGET"
fi

# Verify required variables
if [ -z "$SSH_HOST" ]; then
    echo "Error: SSH_HOST not set in ${TARGET_DIR}/.config"
    exit 1
fi

if [ -z "$CONTAINER_IMAGE" ]; then
    echo "Error: CONTAINER_IMAGE not set in ${TARGET_DIR}/.config"
    exit 1
fi

# Check .env file
if [ ! -f "${TARGET_DIR}/.env" ]; then
    echo "Error: .env file not found in ${TARGET_DIR}/"
    exit 1
fi

# Build full image name with tag (strip existing tag if present)
BASE_IMAGE="${CONTAINER_IMAGE%:*}"
FULL_IMAGE="${BASE_IMAGE}:${IMAGE_TAG}"

# Caddy settings with defaults
APP_PORT="${APP_PORT:-3000}"
HEALTH_CHECK_PATH="${HEALTH_CHECK_PATH:-/}"
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-30}"
CADDY_CONTAINER="caddy-${TARGET}"
BLUE_PORT="3001"
GREEN_PORT="${APP_PORT}"

# Remote paths
REMOTE_BASE_DIR="/var/app/${CONTAINER_NAME}"
REMOTE_ENV_FILE="${REMOTE_BASE_DIR}/.env"
REMOTE_CADDY_DIR="/var/app/${CADDY_CONTAINER}"
CADDYFILE_PATH="${REMOTE_CADDY_DIR}/Caddyfile"

echo "========================================="
echo "Podman Deployment (Caddy Mode)"
echo "========================================="
echo "Target: ${TARGET}"
echo "SSH Host: ${SSH_HOST}"
echo "Container: ${CONTAINER_NAME}"
echo "Image: ${FULL_IMAGE}"
echo "Registry Auth: $([ -n "$GHCR_USERNAME" ] && [ -n "$GHCR_TOKEN" ] && echo "Yes (${GHCR_USERNAME})" || echo "No (public image)")"
echo "Domain: ${DOMAIN:-<not configured>}"
echo "Deployment: Blue-Green (Zero-Downtime)"
echo ""

# Check SSH connection
echo "[1/10] Checking SSH connection..."
if ! ssh ${SSH_HOST} "echo 'SSH connection successful'" >/dev/null 2>&1; then
    echo "Error: Cannot connect to ${SSH_HOST}"
    exit 1
fi
echo "✓ SSH connection verified"
echo ""

# Check if Caddy container exists
echo "[2/10] Verifying Caddy container..."
CADDY_EXISTS=$(ssh ${SSH_HOST} "podman ps --filter name=${CADDY_CONTAINER} --format '{{.Names}}' | grep -c '^${CADDY_CONTAINER}$' || true")
if [ "$CADDY_EXISTS" -eq 0 ]; then
    echo "Error: Caddy container '${CADDY_CONTAINER}' not found"
    echo "Please run: ./setup-caddy.sh ${TARGET}"
    exit 1
fi
echo "✓ Caddy container is running"
echo ""

# Upload target files
echo "[3/10] Uploading target files..."
ssh ${SSH_HOST} "mkdir -p ${REMOTE_BASE_DIR}"
shopt -s dotglob
scp -r "${TARGET_DIR}/"* ${SSH_HOST}:${REMOTE_BASE_DIR}/ 2>/dev/null || true
shopt -u dotglob
echo "✓ Target files uploaded"
echo ""

# Login to registry if credentials provided
if [ -n "$GHCR_USERNAME" ] && [ -n "$GHCR_TOKEN" ]; then
    echo "[4/10] Logging into container registry..."
    if ! ssh ${SSH_HOST} "echo '${GHCR_TOKEN}' | podman login ghcr.io -u ${GHCR_USERNAME} --password-stdin" 2>&1; then
        echo "Error: Failed to login to container registry"
        exit 1
    fi
    echo "✓ Logged in successfully"
    echo ""
else
    echo "[4/10] Skipping registry login (no credentials)"
    echo ""
fi

# Pull latest image
echo "[5/10] Pulling image: ${FULL_IMAGE}..."
ssh ${SSH_HOST} "podman pull ${FULL_IMAGE}"
echo "✓ Image pulled"
echo ""

# Build volume mount arguments
VOLUME_MOUNTS=""
if [ -n "$FILE_MAPPINGS" ]; then
    echo "[6/10] Processing file mappings..."
    IFS=',' read -ra MAPPINGS <<< "$FILE_MAPPINGS"
    for mapping in "${MAPPINGS[@]}"; do
        IFS=':' read -r local_file container_path <<< "$mapping"
        local_file=$(echo "$local_file" | xargs)
        container_path=$(echo "$container_path" | xargs)
        remote_file="${REMOTE_BASE_DIR}/${local_file}"
        VOLUME_MOUNTS="${VOLUME_MOUNTS} -v ${remote_file}:${container_path}"
        echo "  → Mapping: ${local_file} -> ${container_path}"
    done
    echo "✓ File mappings configured"
else
    echo "[6/10] No file mappings specified"
fi
echo ""

# Start blue container (new version on alternate port)
echo "[7/10] Starting new container (blue) on port ${BLUE_PORT}..."
BLUE_CONTAINER="${CONTAINER_NAME}-blue"

# Remove existing blue container if it exists
ssh ${SSH_HOST} "podman stop ${BLUE_CONTAINER} 2>/dev/null || true"
ssh ${SSH_HOST} "podman rm ${BLUE_CONTAINER} 2>/dev/null || true"

# Start blue container
ssh ${SSH_HOST} "podman run -d \
    --name ${BLUE_CONTAINER} \
    --network=host \
    --env-file ${REMOTE_ENV_FILE} \
    -e PORT=${BLUE_PORT} \
    ${VOLUME_MOUNTS} \
    ${FULL_IMAGE}"

echo "✓ Blue container started"
echo ""

# Health check with timeout
echo "[8/10] Running health check (timeout: ${HEALTH_CHECK_TIMEOUT}s)..."
HEALTH_CHECK_URL="http://localhost:${BLUE_PORT}${HEALTH_CHECK_PATH}"
HEALTH_CHECK_PASSED=false

for i in $(seq 1 ${HEALTH_CHECK_TIMEOUT}); do
    if ssh ${SSH_HOST} "curl -f -s ${HEALTH_CHECK_URL} > /dev/null 2>&1"; then
        echo "✓ Health check passed after ${i}s"
        HEALTH_CHECK_PASSED=true
        break
    fi
    echo "  Waiting for container to be ready... (${i}/${HEALTH_CHECK_TIMEOUT})"
    sleep 1
done

if [ "$HEALTH_CHECK_PASSED" = false ]; then
    echo "✗ Health check failed after ${HEALTH_CHECK_TIMEOUT}s"
    echo ""
    echo "Container logs:"
    ssh ${SSH_HOST} "podman logs --tail 50 ${BLUE_CONTAINER}"
    echo ""
    echo "Rolling back: Removing failed container..."
    ssh ${SSH_HOST} "podman stop ${BLUE_CONTAINER}"
    ssh ${SSH_HOST} "podman rm ${BLUE_CONTAINER}"
    echo "✗ Deployment failed (old container still running)"
    exit 1
fi
echo ""

# Update Caddyfile to point to blue port
echo "[9/10] Switching traffic to new container..."
ssh ${SSH_HOST} "sed -i 's/localhost:[0-9]\+/localhost:${BLUE_PORT}/' ${CADDYFILE_PATH}"
ssh ${SSH_HOST} "podman exec ${CADDY_CONTAINER} caddy reload --config /etc/caddy/Caddyfile" 2>&1
echo "✓ Traffic switched to blue container (port ${BLUE_PORT})"
sleep 2

# Stop old green container
GREEN_CONTAINER="${CONTAINER_NAME}"
ssh ${SSH_HOST} "podman stop ${GREEN_CONTAINER} 2>/dev/null || true"
ssh ${SSH_HOST} "podman rm ${GREEN_CONTAINER} 2>/dev/null || true"
echo "✓ Old container removed"

# Recreate green container on standard port
ssh ${SSH_HOST} "podman run -d \
    --name ${GREEN_CONTAINER} \
    --restart=always \
    --network=host \
    --env-file ${REMOTE_ENV_FILE} \
    -e PORT=${GREEN_PORT} \
    ${VOLUME_MOUNTS} \
    ${FULL_IMAGE}"
echo "✓ New container started on port ${GREEN_PORT}"

# Switch Caddyfile back to green port
ssh ${SSH_HOST} "sed -i 's/localhost:[0-9]\+/localhost:${GREEN_PORT}/' ${CADDYFILE_PATH}"
ssh ${SSH_HOST} "podman exec ${CADDY_CONTAINER} caddy reload --config /etc/caddy/Caddyfile" 2>&1
echo "✓ Traffic switched to green container (port ${GREEN_PORT})"

# Remove blue container
ssh ${SSH_HOST} "podman stop ${BLUE_CONTAINER}"
ssh ${SSH_HOST} "podman rm ${BLUE_CONTAINER}"
echo "✓ Blue container removed"
echo ""

# Verify final deployment
echo "[10/10] Verifying deployment..."
sleep 2
CONTAINER_STATUS=$(ssh ${SSH_HOST} "podman ps --filter name=^${GREEN_CONTAINER}$ --format '{{.Status}}'")

if [ -z "$CONTAINER_STATUS" ]; then
    echo "⚠ Warning: Container is not running!"
    exit 1
fi

echo "✓ Container is running: ${CONTAINER_STATUS}"
echo ""

# Show container status
ssh ${SSH_HOST} "podman ps --filter name=^${GREEN_CONTAINER}$"
echo ""

echo "========================================="
echo "Deployment Complete! (Zero-Downtime)"
echo "========================================="
echo ""
echo "Target: ${TARGET}"
echo "Container: ${GREEN_CONTAINER}"
echo "Image: ${FULL_IMAGE}"
echo "Domain: ${DOMAIN:-localhost}"
echo ""
echo "Useful commands:"
echo "  App logs:    ssh ${SSH_HOST} 'podman logs -f ${GREEN_CONTAINER}'"
echo "  Caddy logs:  ssh ${SSH_HOST} 'podman logs -f ${CADDY_CONTAINER}'"
echo "  Restart app: ssh ${SSH_HOST} 'podman restart ${GREEN_CONTAINER}'"
echo "  Rollback:    ./deploy-with-caddy.sh ${TARGET} <previous-tag>"
echo ""
