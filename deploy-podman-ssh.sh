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
                echo "  - $target_name"
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
    echo ""
    echo "Arguments:"
    echo "  target      Target name (e.g., myapp)"
    echo "  image-tag   Optional image tag (default: latest)"
    echo ""
    list_targets
    echo ""
    echo "Setup:"
    echo "  1. cp .config.example .config              # Create global defaults (optional)"
    echo "  2. mkdir -p targets/myapp                  # Create target directory"
    echo "  3. cp .config.example targets/myapp/.config # Create target config"
    echo "  4. cp env.example targets/myapp/.env       # Create environment file"
    echo "  5. Edit targets/myapp/.config and .env with your settings"
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

# Default CONTAINER_NAME to target name if not specified
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

# Check if .env file exists in target directory
if [ ! -f "${TARGET_DIR}/.env" ]; then
    echo "Error: .env file not found in ${TARGET_DIR}/"
    echo "Please create: targets/${TARGET}/.env"
    exit 1
fi

# Build full image name with tag (strip existing tag if present)
BASE_IMAGE="${CONTAINER_IMAGE%:*}"
FULL_IMAGE="${BASE_IMAGE}:${IMAGE_TAG}"

# Set remote paths
REMOTE_BASE_DIR="/var/app/${CONTAINER_NAME}"
REMOTE_ENV_FILE="${REMOTE_BASE_DIR}/.env"

echo "========================================="
echo "Podman Deployment Script"
echo "========================================="
echo "Target: $TARGET"
echo "SSH Host: $SSH_HOST"
echo "Container: $CONTAINER_NAME"
echo "Image: $FULL_IMAGE"
echo "Registry Auth: $([ -n "$GHCR_USERNAME" ] && [ -n "$GHCR_TOKEN" ] && echo "Yes (${GHCR_USERNAME})" || echo "No (public image)")"
echo "Local Dir: ${TARGET_DIR}"
echo "Remote Dir: ${REMOTE_BASE_DIR}"
echo ""

# Check SSH connection
echo "[1/9] Checking SSH connection to ${SSH_HOST}..."
if ! ssh ${SSH_HOST} "echo 'SSH connection successful'" >/dev/null 2>&1; then
    echo "Error: Cannot connect to ${SSH_HOST}"
    exit 1
fi
echo "✓ SSH connection verified"
echo ""

# Check if podman is installed
echo "[2/9] Checking Podman installation..."
if ! ssh ${SSH_HOST} "command -v podman >/dev/null 2>&1"; then
    echo "Podman not found. Installing..."
    ssh ${SSH_HOST} "sudo apt-get update && sudo apt-get install -y podman"
    echo "✓ Podman installed successfully"
else
    echo "✓ Podman already installed"
fi
echo ""

# Upload target directory to remote host
echo "[3/9] Uploading target files..."
# Ensure the remote directory exists
ssh ${SSH_HOST} "mkdir -p ${REMOTE_BASE_DIR}"
# Upload all files from target directory (including hidden files)
shopt -s dotglob  # Enable matching hidden files
scp -r "${TARGET_DIR}/"* ${SSH_HOST}:${REMOTE_BASE_DIR}/ 2>/dev/null || \
    echo "Warning: No files to upload (this is normal if directory is empty)"
shopt -u dotglob  # Disable dotglob
echo "✓ Target files uploaded to ${REMOTE_BASE_DIR}"
echo ""

# Login to container registry (if credentials provided)
if [ -n "$GHCR_USERNAME" ] && [ -n "$GHCR_TOKEN" ]; then
    echo "[4/9] Logging into GitHub Container Registry..."
    echo "  Username: ${GHCR_USERNAME}"
    if ! ssh ${SSH_HOST} "echo '${GHCR_TOKEN}' | podman login ghcr.io -u ${GHCR_USERNAME} --password-stdin" 2>&1; then
        echo "Error: Failed to login to GitHub Container Registry"
        exit 1
    fi
    echo "✓ Logged in successfully"
    echo ""

    # Pull latest image with credentials
    echo "[5/9] Pulling container image (authenticated)..."
    ssh ${SSH_HOST} "podman pull ${FULL_IMAGE}"
    echo "✓ Image pulled"
    echo ""
else
    echo "[4/9] Skipping container registry login (no credentials provided)"
    echo ""

    # Pull latest image without credentials (public image)
    echo "[5/9] Pulling container image (public)..."
    ssh ${SSH_HOST} "podman pull ${FULL_IMAGE}"
    echo "✓ Image pulled"
    echo ""
fi

# Parse PORT_MAPPINGS and build port arguments
PORT_ARGS=""
if [ -n "$PORT_MAPPINGS" ]; then
    echo "[6/9] Processing port mappings..."
    IFS=',' read -ra PORTS <<< "$PORT_MAPPINGS"
    for port_mapping in "${PORTS[@]}"; do
        # Trim whitespace
        port_mapping=$(echo "$port_mapping" | xargs)
        # Add port mapping argument
        PORT_ARGS="${PORT_ARGS} -p ${port_mapping}"
        echo "  → Port: ${port_mapping}"
    done
    echo "✓ Port mappings configured"
else
    echo "[6/9] No port mappings specified"
fi
echo ""

# Parse FILE_MAPPINGS and build volume mount arguments
VOLUME_MOUNTS=""
if [ -n "$FILE_MAPPINGS" ]; then
    echo "[7/9] Processing file mappings..."
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
    echo "[7/9] No file mappings specified"
fi
echo ""

# Check if container exists
echo "[8/9] Checking for existing container..."
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
    echo "  → Starting new container with image..."
    ssh ${SSH_HOST} "podman run -d --restart=always --env-file ${REMOTE_ENV_FILE}${PORT_ARGS}${VOLUME_MOUNTS} --name ${CONTAINER_NAME} ${FULL_IMAGE}"

    echo "✓ Container updated to new version"
else
    echo "Container '${CONTAINER_NAME}' not found. Creating new deployment..."

    # Start new container
    ssh ${SSH_HOST} "podman run -d --restart=always --env-file ${REMOTE_ENV_FILE}${PORT_ARGS}${VOLUME_MOUNTS} --name ${CONTAINER_NAME} ${FULL_IMAGE}"

    echo "✓ Container deployed successfully"
fi
echo ""

# Verify deployment
echo "[9/9] Verifying deployment..."
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
echo "Image: ${FULL_IMAGE}"
if [ -n "$PORT_MAPPINGS" ]; then
    echo "Ports: ${PORT_MAPPINGS}"
fi
echo ""
echo "Useful commands:"
echo "  View logs:       ssh ${SSH_HOST} 'podman logs -f ${CONTAINER_NAME}'"
echo "  Stop container:  ssh ${SSH_HOST} 'podman stop ${CONTAINER_NAME}'"
echo "  Start container: ssh ${SSH_HOST} 'podman start ${CONTAINER_NAME}'"
echo "  Restart:         ssh ${SSH_HOST} 'podman restart ${CONTAINER_NAME}'"
echo "  Remove:          ssh ${SSH_HOST} 'podman rm -f ${CONTAINER_NAME}'"
echo ""
