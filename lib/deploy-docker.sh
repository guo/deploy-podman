#!/bin/bash

# Docker Deployment Module
# This module handles both single-container and compose deployments using Docker

deploy_docker_single() {
    echo "========================================="
    echo "Docker Single-Container Deployment"
    echo "========================================="
    echo "Target: $TARGET"
    echo "Container: $CONTAINER_NAME"
    echo "Image: $FULL_IMAGE"
    echo "Registry Auth: $([ -n "$GHCR_USERNAME" ] && [ -n "$GHCR_TOKEN" ] && echo "Yes (${GHCR_USERNAME})" || echo "No (public image)")"
    echo "Remote Dir: ${REMOTE_BASE_DIR}"
    echo ""

    # Check if docker is installed
    echo "[1/7] Checking Docker installation..."
    if ! ssh ${SSH_HOST} "command -v docker >/dev/null 2>&1"; then
        echo "Docker not found. Installing..."
        ssh ${SSH_HOST} "curl -fsSL https://get.docker.com | sudo sh && sudo usermod -aG docker \$USER"
        echo "✓ Docker installed successfully"
        echo "Note: You may need to log out and back in for group membership to take effect"
    else
        echo "✓ Docker already installed"
    fi
    echo ""

    # Login to container registry (if credentials provided)
    if [ -n "$GHCR_USERNAME" ] && [ -n "$GHCR_TOKEN" ]; then
        echo "[2/7] Logging into GitHub Container Registry..."
        echo "  Username: ${GHCR_USERNAME}"
        if ! ssh ${SSH_HOST} "echo '${GHCR_TOKEN}' | docker login ghcr.io -u ${GHCR_USERNAME} --password-stdin" 2>&1; then
            echo "Error: Failed to login to GitHub Container Registry"
            exit 1
        fi
        echo "✓ Logged in successfully"
        echo ""

        # Pull latest image with credentials
        echo "[3/7] Pulling container image (authenticated)..."
        ssh ${SSH_HOST} "docker pull ${FULL_IMAGE}"
        echo "✓ Image pulled"
        echo ""
    else
        echo "[2/7] Skipping container registry login (no credentials provided)"
        echo ""

        # Pull latest image without credentials (public image)
        echo "[3/7] Pulling container image (public)..."
        ssh ${SSH_HOST} "docker pull ${FULL_IMAGE}"
        echo "✓ Image pulled"
        echo ""
    fi

    # Parse PORT_MAPPINGS and build port arguments
    PORT_ARGS=""
    if [ -n "$PORT_MAPPINGS" ]; then
        echo "[4/7] Processing port mappings..."
        IFS=',' read -ra PORTS <<< "$PORT_MAPPINGS"
        for port_mapping in "${PORTS[@]}"; do
            port_mapping=$(echo "$port_mapping" | xargs)
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
            IFS=':' read -r local_file container_path <<< "$mapping"
            local_file=$(echo "$local_file" | xargs)
            container_path=$(echo "$container_path" | xargs)
            remote_file="${REMOTE_BASE_DIR}/${local_file}"
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
    CONTAINER_EXISTS=$(ssh ${SSH_HOST} "docker ps -a --format '{{.Names}}' | grep -c '^${CONTAINER_NAME}$' || true")

    if [ "$CONTAINER_EXISTS" -gt 0 ]; then
        echo "Container '${CONTAINER_NAME}' exists. Updating..."
        echo "  → Stopping container..."
        ssh ${SSH_HOST} "docker stop ${CONTAINER_NAME}" >/dev/null 2>&1 || true
        echo "  → Removing old container..."
        ssh ${SSH_HOST} "docker rm ${CONTAINER_NAME}" >/dev/null 2>&1 || true
        echo "  → Starting new container..."
        ssh ${SSH_HOST} "docker run -d --restart=always --env-file ${REMOTE_ENV_FILE}${PORT_ARGS}${VOLUME_MOUNTS} --name ${CONTAINER_NAME} ${FULL_IMAGE}"
        echo "✓ Container updated"
    else
        echo "Container '${CONTAINER_NAME}' not found. Creating new deployment..."
        ssh ${SSH_HOST} "docker run -d --restart=always --env-file ${REMOTE_ENV_FILE}${PORT_ARGS}${VOLUME_MOUNTS} --name ${CONTAINER_NAME} ${FULL_IMAGE}"
        echo "✓ Container deployed"
    fi
    echo ""

    # Verify deployment
    echo "[7/7] Verifying deployment..."
    sleep 3
    CONTAINER_STATUS=$(ssh ${SSH_HOST} "docker ps --filter name=${CONTAINER_NAME} --format '{{.Status}}'")

    if [ -z "$CONTAINER_STATUS" ]; then
        echo "⚠ Warning: Container is not running. Checking logs..."
        ssh ${SSH_HOST} "docker logs --tail 30 ${CONTAINER_NAME}"
        exit 1
    fi

    echo "✓ Container is running: ${CONTAINER_STATUS}"
    echo ""

    ssh ${SSH_HOST} "docker ps --filter name=${CONTAINER_NAME}"
    echo ""

    echo "========================================="
    echo "Recent container logs:"
    echo "========================================="
    ssh ${SSH_HOST} "docker logs --tail 20 ${CONTAINER_NAME}"
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
    echo "  View logs:       ssh ${SSH_HOST} 'docker logs -f ${CONTAINER_NAME}'"
    echo "  Stop container:  ssh ${SSH_HOST} 'docker stop ${CONTAINER_NAME}'"
    echo "  Start container: ssh ${SSH_HOST} 'docker start ${CONTAINER_NAME}'"
    echo "  Restart:         ssh ${SSH_HOST} 'docker restart ${CONTAINER_NAME}'"
    echo "  Remove:          ssh ${SSH_HOST} 'docker rm -f ${CONTAINER_NAME}'"
    echo ""
}

deploy_docker_compose() {
    echo "========================================="
    echo "Docker Compose Deployment"
    echo "========================================="
    echo "Target: $TARGET"
    echo "Compose File: ${COMPOSE_FILE}"
    echo "Image Tag: ${IMAGE_TAG}"
    echo "Registry Auth: $([ -n "$GHCR_USERNAME" ] && [ -n "$GHCR_TOKEN" ] && echo "Yes (${GHCR_USERNAME})" || echo "No (public image)")"
    echo "Remote Dir: ${REMOTE_BASE_DIR}"
    echo ""

    # Check if docker is installed
    echo "[1/5] Checking Docker installation..."
    if ! ssh ${SSH_HOST} "command -v docker >/dev/null 2>&1"; then
        echo "Docker not found. Installing..."
        ssh ${SSH_HOST} "curl -fsSL https://get.docker.com | sudo sh && sudo usermod -aG docker \$USER"
        echo "✓ Docker installed successfully"
    else
        echo "✓ Docker already installed"
    fi
    echo ""

    # Check/Install Docker Compose
    echo "[2/5] Checking Docker Compose..."
    if ! ssh ${SSH_HOST} "docker compose version >/dev/null 2>&1"; then
        echo "Docker Compose not found. Installing..."
        ssh ${SSH_HOST} "
            COMPOSE_VERSION=v2.24.5
            sudo curl -SL https://github.com/docker/compose/releases/download/\${COMPOSE_VERSION}/docker-compose-linux-\$(uname -m) \
                -o /usr/local/bin/docker-compose && \
            sudo chmod +x /usr/local/bin/docker-compose && \
            sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
        "
        echo "✓ Docker Compose installed"
    else
        echo "✓ Docker Compose already installed"
    fi
    echo ""

    # Login to container registry (if credentials provided)
    if [ -n "$GHCR_USERNAME" ] && [ -n "$GHCR_TOKEN" ]; then
        echo "[3/5] Logging into GitHub Container Registry..."
        echo "  Username: ${GHCR_USERNAME}"
        if ! ssh ${SSH_HOST} "echo '${GHCR_TOKEN}' | docker login ghcr.io -u ${GHCR_USERNAME} --password-stdin" 2>&1; then
            echo "Error: Failed to login to GitHub Container Registry"
            exit 1
        fi
        echo "✓ Logged in successfully"
        echo ""
    else
        echo "[3/5] Skipping container registry login (no credentials provided)"
        echo ""
    fi

    # Deploy with docker compose
    echo "[4/5] Deploying with Docker Compose..."
    ssh ${SSH_HOST} "cd ${REMOTE_BASE_DIR} && \
        export IMAGE_TAG='${IMAGE_TAG}' && \
        docker compose -f ${COMPOSE_FILE} down 2>/dev/null || true && \
        docker compose -f ${COMPOSE_FILE} up -d"
    echo "✓ Compose deployment complete"
    echo ""

    # Verify deployment
    echo "[5/5] Verifying compose deployment..."
    sleep 5
    ssh ${SSH_HOST} "cd ${REMOTE_BASE_DIR} && docker compose -f ${COMPOSE_FILE} ps"
    echo ""

    echo "========================================="
    echo "Deployment completed successfully!"
    echo "========================================="
    echo ""
    echo "Target: ${TARGET}"
    echo "Compose File: ${COMPOSE_FILE}"
    echo "Image Tag: ${IMAGE_TAG}"
    echo ""
    echo "Useful commands:"
    echo "  View services:   ssh ${SSH_HOST} 'cd ${REMOTE_BASE_DIR} && docker compose -f ${COMPOSE_FILE} ps'"
    echo "  View logs:       ssh ${SSH_HOST} 'cd ${REMOTE_BASE_DIR} && docker compose -f ${COMPOSE_FILE} logs -f'"
    echo "  Stop services:   ssh ${SSH_HOST} 'cd ${REMOTE_BASE_DIR} && docker compose -f ${COMPOSE_FILE} down'"
    echo "  Restart:         ssh ${SSH_HOST} 'cd ${REMOTE_BASE_DIR} && docker compose -f ${COMPOSE_FILE} restart'"
    echo ""
}
