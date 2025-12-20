#!/bin/bash

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to parse INI-style config
parse_config() {
    local config_file="$1"
    local target="$2"
    local in_section=false

    # First, read common configuration (before any section)
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue

        # Check for section header
        if [[ "$key" =~ ^\[.*\]$ ]]; then
            break
        fi

        # Remove quotes and export
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs | sed 's/^"\(.*\)"$/\1/')
        [[ -n "$key" && -n "$value" ]] && export "$key=$value"
    done < "$config_file"

    # Now read target-specific configuration
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue

        # Check for section header
        if [[ "$key" =~ ^\[(.*)\]$ ]]; then
            section="${BASH_REMATCH[1]}"
            if [[ "$section" == "$target" ]]; then
                in_section=true
            else
                in_section=false
            fi
            continue
        fi

        # If we're in the right section, export variables
        if [[ "$in_section" == true ]]; then
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs | sed 's/^"\(.*\)"$/\1/')
            [[ -n "$key" && -n "$value" ]] && export "$key=$value"
        fi
    done < "$config_file"
}

# Function to list available targets
list_targets() {
    echo "Available targets:"
    grep -E '^\[.*\]$' "${SCRIPT_DIR}/targets.config" | sed 's/\[\(.*\)\]/  - \1/'
}

# Check arguments
TARGET="${1:-demo}"

if [[ "$TARGET" == "--help" || "$TARGET" == "-h" ]]; then
    echo "Usage: $0 <target>"
    echo ""
    list_targets
    echo ""
    echo "Example: $0 production"
    echo "         $0 staging"
    echo "         $0 demo (default)"
    exit 0
fi

# Load configuration
if [ ! -f "${SCRIPT_DIR}/targets.config" ]; then
    echo "Error: targets.config not found in ${SCRIPT_DIR}"
    exit 1
fi

# Parse config for the specified target
parse_config "${SCRIPT_DIR}/targets.config" "$TARGET"

# Verify target was found
if [ -z "$SSH_HOST" ]; then
    echo "Error: Target '$TARGET' not found in targets.config"
    echo ""
    list_targets
    exit 1
fi

# Check if targets directory exists
TARGETS_DIR="${SCRIPT_DIR}/targets"
if [ ! -d "${TARGETS_DIR}" ]; then
    echo "Error: targets/ directory not found in ${SCRIPT_DIR}"
    echo "Please create: mkdir -p targets"
    exit 1
fi

# Check if container directory exists
CONTAINER_DIR="${TARGETS_DIR}/${CONTAINER_NAME}"
if [ ! -d "${CONTAINER_DIR}" ]; then
    echo "Error: Container directory '${CONTAINER_NAME}' not found in ${TARGETS_DIR}"
    echo "Please create directory: mkdir -p targets/${CONTAINER_NAME}"
    exit 1
fi

# Check if .env file exists in container directory
if [ ! -f "${CONTAINER_DIR}/.env" ]; then
    echo "Error: .env file not found in ${CONTAINER_DIR}/"
    echo "Please create: targets/${CONTAINER_NAME}/.env"
    exit 1
fi

# Set remote paths
REMOTE_BASE_DIR="/var/app/${CONTAINER_NAME}"
REMOTE_ENV_FILE="${REMOTE_BASE_DIR}/.env"

echo "========================================="
echo "Podman Deployment Script"
echo "========================================="
echo "Target: $TARGET"
echo "SSH Host: $SSH_HOST"
echo "Container: $CONTAINER_NAME"
echo "Image: $CONTAINER_IMAGE"
echo "Registry Auth: $([ -n "$GHCR_USERNAME" ] && echo "Yes (${GHCR_USERNAME})" || echo "No (public image)")"
echo "Local Dir: ${CONTAINER_DIR}"
echo "Remote Dir: ${REMOTE_BASE_DIR}"
echo ""

# Check SSH connection
echo "[1/8] Checking SSH connection to ${SSH_HOST}..."
if ! ssh ${SSH_HOST} "echo 'SSH connection successful'" >/dev/null 2>&1; then
    echo "Error: Cannot connect to ${SSH_HOST}"
    exit 1
fi
echo "✓ SSH connection verified"
echo ""

# Check if podman is installed
echo "[2/8] Checking Podman installation..."
if ! ssh ${SSH_HOST} "command -v podman >/dev/null 2>&1"; then
    echo "Podman not found. Installing..."
    ssh ${SSH_HOST} "sudo apt-get update && sudo apt-get install -y podman"
    echo "✓ Podman installed successfully"
else
    echo "✓ Podman already installed"
fi
echo ""

# Upload container directory to remote host
echo "[3/8] Uploading container files..."
# Ensure the remote directory exists
ssh ${SSH_HOST} "mkdir -p ${REMOTE_BASE_DIR}"
# Upload all files from container directory
scp -r "${CONTAINER_DIR}/"* ${SSH_HOST}:${REMOTE_BASE_DIR}/
echo "✓ Container files uploaded to ${REMOTE_BASE_DIR}"
echo ""

# Login to container registry (if credentials provided)
if [ -n "$GHCR_USERNAME" ] && [ -n "$GHCR_TOKEN" ]; then
    echo "[4/8] Logging into GitHub Container Registry..."
    ssh ${SSH_HOST} "echo '${GHCR_TOKEN}' | podman login ghcr.io -u ${GHCR_USERNAME} --password-stdin" >/dev/null 2>&1
    echo "✓ Logged in successfully"
    echo ""

    # Pull latest image with credentials
    echo "[5/8] Pulling latest container image (authenticated)..."
    ssh ${SSH_HOST} "podman pull --creds ${GHCR_USERNAME}:${GHCR_TOKEN} ${CONTAINER_IMAGE}"
    echo "✓ Latest image pulled"
    echo ""
else
    echo "[4/8] Skipping container registry login (no credentials provided)"
    echo ""

    # Pull latest image without credentials (public image)
    echo "[5/8] Pulling latest container image (public)..."
    ssh ${SSH_HOST} "podman pull ${CONTAINER_IMAGE}"
    echo "✓ Latest image pulled"
    echo ""
fi

# Parse FILE_MAPPINGS and build volume mount arguments
VOLUME_MOUNTS=""
if [ -n "$FILE_MAPPINGS" ]; then
    echo "[6/8] Processing file mappings..."
    IFS=',' read -ra MAPPINGS <<< "$FILE_MAPPINGS"
    for mapping in "${MAPPINGS[@]}"; do
        # Split mapping into local_file:container_path
        IFS=':' read -r local_file container_path <<< "$mapping"
        # Trim whitespace
        local_file=$(echo "$local_file" | xargs)
        container_path=$(echo "$container_path" | xargs)

        # Build remote file path
        remote_file="${REMOTE_BASE_DIR}/${local_file}"

        # Add volume mount argument
        VOLUME_MOUNTS="${VOLUME_MOUNTS} -v ${remote_file}:${container_path}"
        echo "  → Mapping: ${local_file} -> ${container_path}"
    done
    echo "✓ File mappings configured"
else
    echo "[6/8] No file mappings specified"
fi
echo ""

# Check if container exists
echo "[7/8] Checking for existing container..."
CONTAINER_EXISTS=$(ssh ${SSH_HOST} "podman ps -a --format '{{.Names}}' | grep -c '^${CONTAINER_NAME}$' || true")

if [ "$CONTAINER_EXISTS" -gt 0 ]; then
    echo "Container '${CONTAINER_NAME}' exists. Updating..."

    # Stop the existing container
    echo "  → Stopping container..."
    ssh ${SSH_HOST} "podman stop ${CONTAINER_NAME}" >/dev/null 2>&1 || true

    # Remove the old container
    echo "  → Removing old container..."
    ssh ${SSH_HOST} "podman rm ${CONTAINER_NAME}" >/dev/null 2>&1 || true

    # Start new container with latest image
    echo "  → Starting new container with latest image..."
    ssh ${SSH_HOST} "podman run -d --restart=always --env-file ${REMOTE_ENV_FILE} -p ${HOST_PORT}:${CONTAINER_PORT}${VOLUME_MOUNTS} --name ${CONTAINER_NAME} ${CONTAINER_IMAGE}"

    echo "✓ Container updated to latest version"
else
    echo "Container '${CONTAINER_NAME}' not found. Creating new deployment..."

    # Start new container
    ssh ${SSH_HOST} "podman run -d --restart=always --env-file ${REMOTE_ENV_FILE} -p ${HOST_PORT}:${CONTAINER_PORT}${VOLUME_MOUNTS} --name ${CONTAINER_NAME} ${CONTAINER_IMAGE}"

    echo "✓ Container deployed successfully"
fi
echo ""

# Verify deployment
echo "[8/8] Verifying deployment..."
sleep 3
CONTAINER_STATUS=$(ssh ${SSH_HOST} "podman ps --filter name=${CONTAINER_NAME} --format '{{.Status}}'")

if [ -z "$CONTAINER_STATUS" ]; then
    echo "⚠ Warning: Container is not running. Checking logs..."
    ssh ${SSH_HOST} "podman logs --tail 30 ${CONTAINER_NAME}"
    exit 1
fi

echo "✓ Container is running: ${CONTAINER_STATUS}"
echo ""

ssh ${SSH_HOST} "podman ps --filter name=${CONTAINER_NAME}"
echo ""

# Show recent logs
echo "========================================="
echo "Recent container logs:"
echo "========================================="
ssh ${SSH_HOST} "podman logs --tail 20 ${CONTAINER_NAME}"
echo ""

echo "========================================="
echo "Deployment completed successfully!"
echo "========================================="
echo ""
echo "Target: ${TARGET}"
echo "Container: ${CONTAINER_NAME}"
echo "Image: ${CONTAINER_IMAGE}"
echo "Port Mapping: ${HOST_PORT} (host) -> ${CONTAINER_PORT} (container)"
echo ""
echo "Useful commands:"
echo "  View logs:       ssh ${SSH_HOST} 'podman logs -f ${CONTAINER_NAME}'"
echo "  Stop container:  ssh ${SSH_HOST} 'podman stop ${CONTAINER_NAME}'"
echo "  Start container: ssh ${SSH_HOST} 'podman start ${CONTAINER_NAME}'"
echo "  Restart:         ssh ${SSH_HOST} 'podman restart ${CONTAINER_NAME}'"
echo "  Remove:          ssh ${SSH_HOST} 'podman rm -f ${CONTAINER_NAME}'"
echo ""
