#!/bin/bash

# Podman Single-Container Deployment Module
# This module handles single-container deployments using Podman

# Source hash checking functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/hash-check.sh"

deploy_with_podman() {
    echo "========================================="
    echo "Podman Single-Container Deployment"
    echo "========================================="
    echo "Target: $TARGET"
    echo "Container: $CONTAINER_NAME"
    echo "Image: $FULL_IMAGE"
    echo "Registry Auth: $([ -n "$GHCR_USERNAME" ] && [ -n "$GHCR_TOKEN" ] && echo "Yes (${GHCR_USERNAME})" || echo "No (public image)")"
    echo "Remote Dir: ${REMOTE_BASE_DIR}"
    echo ""

    # Check if podman is installed
    echo "[1/7] Checking Podman installation..."
    if ! ssh ${SSH_HOST} "command -v podman >/dev/null 2>&1"; then
        echo "Podman not found. Installing..."
        ssh ${SSH_HOST} "sudo apt-get update && sudo apt-get install -y podman"
        echo "✓ Podman installed successfully"
    else
        echo "✓ Podman already installed"
    fi
    echo ""

    # Login to container registry (if credentials provided)
    if [ -n "$GHCR_USERNAME" ] && [ -n "$GHCR_TOKEN" ]; then
        echo "[2/7] Logging into GitHub Container Registry..."
        echo "  Username: ${GHCR_USERNAME}"
        if ! ssh ${SSH_HOST} "echo '${GHCR_TOKEN}' | podman login ghcr.io -u ${GHCR_USERNAME} --password-stdin" 2>&1; then
            echo "Error: Failed to login to GitHub Container Registry"
            exit 1
        fi
        echo "✓ Logged in successfully"
        echo ""

        # Pull latest image with credentials
        echo "[3/7] Pulling container image (authenticated)..."
        ssh ${SSH_HOST} "podman pull ${FULL_IMAGE}"
        echo "✓ Image pulled"
        echo ""
    else
        echo "[2/7] Skipping container registry login (no credentials provided)"
        echo ""
    fi

    # Check if image hash has changed (unless forced)
    if [ "${FORCE_DEPLOY:-false}" != "true" ]; then
        echo "[3/7] Checking image hash..."
        if ! check_image_hash_changed "podman" "${CONTAINER_NAME}" "${FULL_IMAGE}"; then
            echo ""
            echo "========================================="
            echo "Deployment skipped (image unchanged)"
            echo "========================================="
            echo ""
            echo "Target: ${TARGET}"
            echo "Container: ${CONTAINER_NAME}"
            echo "Image: ${FULL_IMAGE}"
            echo ""
            echo "The deployed image hash matches the target image."
            echo "No deployment needed."
            echo ""
            echo "To force deployment anyway:"
            echo "  ./deploy.sh -f ${TARGET} ${IMAGE_TAG}"
            echo ""
            return 0
        fi
        echo ""

        # Pull latest image
        echo "Pulling container image..."
        if [ -n "$GHCR_USERNAME" ] && [ -n "$GHCR_TOKEN" ]; then
            ssh ${SSH_HOST} "podman pull ${FULL_IMAGE}"
        else
            ssh ${SSH_HOST} "podman pull ${FULL_IMAGE}"
        fi
        echo "✓ Image pulled"
        echo ""
    else
        echo "[3/7] Skipping hash check (forced deployment)..."
        echo ""

        # Pull latest image
        echo "Pulling container image..."
        if [ -n "$GHCR_USERNAME" ] && [ -n "$GHCR_TOKEN" ]; then
            ssh ${SSH_HOST} "podman pull ${FULL_IMAGE}"
        else
            ssh ${SSH_HOST} "podman pull ${FULL_IMAGE}"
        fi
        echo "✓ Image pulled"
        echo ""
    fi

    # Parse PORT_MAPPINGS and build port arguments
    PORT_ARGS=""
    if [ -n "$PORT_MAPPINGS" ]; then
        echo "[4/7] Processing port mappings..."
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
        echo "[4/7] No port mappings specified"
    fi
    echo ""

    # Parse FILE_MAPPINGS and build volume mount arguments
    VOLUME_MOUNTS=""
    if [ -n "$FILE_MAPPINGS" ]; then
        echo "[5/7] Processing file mappings..."
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
        echo "[5/7] No file mappings specified"
    fi
    echo ""

    # Check if container exists
    echo "[6/7] Deploying container..."
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
        echo "  → Starting new container..."
        ssh ${SSH_HOST} "podman run -d --restart=always --env-file ${REMOTE_ENV_FILE}${PORT_ARGS}${VOLUME_MOUNTS} --name ${CONTAINER_NAME} ${FULL_IMAGE}"

        echo "✓ Container updated"
    else
        echo "Container '${CONTAINER_NAME}' not found. Creating new deployment..."

        # Start new container
        ssh ${SSH_HOST} "podman run -d --restart=always --env-file ${REMOTE_ENV_FILE}${PORT_ARGS}${VOLUME_MOUNTS} --name ${CONTAINER_NAME} ${FULL_IMAGE}"

        echo "✓ Container deployed"
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
    echo "Image: ${FULL_IMAGE}"
    IMAGE_DIGEST=$(ssh ${SSH_HOST} "podman inspect ${CONTAINER_NAME} --format='{{.Image}}'" 2>/dev/null | cut -c8-19)
    if [ -n "$IMAGE_DIGEST" ]; then
        echo "Image Digest: ${IMAGE_DIGEST}"
    fi
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
}
