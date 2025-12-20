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

# Check if env file exists
if [ ! -f "${SCRIPT_DIR}/${ENV_FILE}" ]; then
    echo "Error: Env file '${ENV_FILE}' not found in ${SCRIPT_DIR}"
    exit 1
fi

# Auto-generate remote env file path based on container name
ENV_FILE_REMOTE_PATH="/var/app/${CONTAINER_NAME}/.env"

echo "========================================="
echo "Podman Deployment Script"
echo "========================================="
echo "Target: $TARGET"
echo "SSH Host: $SSH_HOST"
echo "Container: $CONTAINER_NAME"
echo "Env File: $ENV_FILE -> ${ENV_FILE_REMOTE_PATH}"
echo ""

# Check SSH connection
echo "[1/7] Checking SSH connection to ${SSH_HOST}..."
if ! ssh ${SSH_HOST} "echo 'SSH connection successful'" >/dev/null 2>&1; then
    echo "Error: Cannot connect to ${SSH_HOST}"
    exit 1
fi
echo "✓ SSH connection verified"
echo ""

# Check if podman is installed
echo "[2/7] Checking Podman installation..."
if ! ssh ${SSH_HOST} "command -v podman >/dev/null 2>&1"; then
    echo "Podman not found. Installing..."
    ssh ${SSH_HOST} "sudo apt-get update && sudo apt-get install -y podman"
    echo "✓ Podman installed successfully"
else
    echo "✓ Podman already installed"
fi
echo ""

# Upload env file to remote host
echo "[3/7] Uploading env file..."
# Ensure the remote directory exists
REMOTE_DIR=$(dirname "${ENV_FILE_REMOTE_PATH}")
ssh ${SSH_HOST} "mkdir -p ${REMOTE_DIR}"
scp "${SCRIPT_DIR}/${ENV_FILE}" ${SSH_HOST}:${ENV_FILE_REMOTE_PATH}
echo "✓ Env file uploaded to ${ENV_FILE_REMOTE_PATH}"
echo ""

# Login to GitHub Container Registry
echo "[4/7] Logging into GitHub Container Registry..."
ssh ${SSH_HOST} "echo '${GHCR_TOKEN}' | podman login ghcr.io -u ${GHCR_USERNAME} --password-stdin" >/dev/null 2>&1
echo "✓ Logged in successfully"
echo ""

# Pull latest image
echo "[5/7] Pulling latest container image..."
ssh ${SSH_HOST} "podman pull --creds ${GHCR_USERNAME}:${GHCR_TOKEN} ${CONTAINER_IMAGE}"
echo "✓ Latest image pulled"
echo ""

# Check if container exists
echo "[6/7] Checking for existing container..."
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
    ssh ${SSH_HOST} "podman run -d --restart=always --env-file ${ENV_FILE_REMOTE_PATH} -p ${HOST_PORT}:${CONTAINER_PORT} --name ${CONTAINER_NAME} ${CONTAINER_IMAGE}"

    echo "✓ Container updated to latest version"
else
    echo "Container '${CONTAINER_NAME}' not found. Creating new deployment..."

    # Start new container
    ssh ${SSH_HOST} "podman run -d --restart=always --env-file ${ENV_FILE_REMOTE_PATH} -p ${HOST_PORT}:${CONTAINER_PORT} --name ${CONTAINER_NAME} ${CONTAINER_IMAGE}"

    echo "✓ Container deployed successfully"
fi
echo ""

# Verify deployment
echo "[7/7] Verifying deployment..."
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
