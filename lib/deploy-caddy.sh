#!/bin/bash

# Caddy zero-downtime deployment module
# Uses blue-green deployment strategy with health checks

deploy_with_caddy() {
    # Caddy settings with defaults
    APP_PORT="${APP_PORT:-3000}"
    HEALTH_CHECK_PATH="${HEALTH_CHECK_PATH:-/}"
    HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-30}"
    CADDY_CONTAINER="caddy-${TARGET}"
    BLUE_PORT="3001"
    GREEN_PORT="${APP_PORT}"

    # Remote Caddy paths
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

    # Check if Caddy container exists
    echo "[1/7] Verifying Caddy container..."
    CADDY_EXISTS=$(ssh ${SSH_HOST} "podman ps --filter name=${CADDY_CONTAINER} --format '{{.Names}}' | grep -c '^${CADDY_CONTAINER}$' || true")
    if [ "$CADDY_EXISTS" -eq 0 ]; then
        echo "Error: Caddy container '${CADDY_CONTAINER}' not found"
        echo "Please run: ./setup-caddy.sh ${TARGET}"
        exit 1
    fi
    echo "✓ Caddy container is running"
    echo ""

    # Login to registry if credentials provided
    if [ -n "$GHCR_USERNAME" ] && [ -n "$GHCR_TOKEN" ]; then
        echo "[2/7] Logging into container registry..."
        if ! ssh ${SSH_HOST} "echo '${GHCR_TOKEN}' | podman login ghcr.io -u ${GHCR_USERNAME} --password-stdin" 2>&1; then
            echo "Error: Failed to login to container registry"
            exit 1
        fi
        echo "✓ Logged in successfully"
        echo ""
    else
        echo "[2/7] Skipping registry login (no credentials)"
        echo ""
    fi

    # Pull latest image
    echo "[3/7] Pulling image: ${FULL_IMAGE}..."
    ssh ${SSH_HOST} "podman pull ${FULL_IMAGE}"
    echo "✓ Image pulled"
    echo ""

    # Build volume mount arguments
    VOLUME_MOUNTS=""
    if [ -n "$FILE_MAPPINGS" ]; then
        echo "[4/7] Processing file mappings..."
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
        echo "[4/7] No file mappings specified"
    fi
    echo ""

    # Start blue container (new version on alternate port)
    echo "[5/7] Starting new container (blue) on port ${BLUE_PORT}..."
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
    echo "[6/7] Running health check (timeout: ${HEALTH_CHECK_TIMEOUT}s)..."
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
    echo "[7/7] Switching traffic to new container..."
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
    echo "Verifying deployment..."
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
    echo ""
}
