#!/bin/bash

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to show usage
show_usage() {
    echo "Usage: $0 <target>"
    echo ""
    echo "Setup Caddy reverse proxy for a deployment target."
    echo ""
    echo "Arguments:"
    echo "  target      Target name (e.g., depinscan)"
    echo ""
    echo "Examples:"
    echo "  $0 depinscan"
    echo ""
    echo "This will:"
    echo "  1. Create Caddyfile for the target"
    echo "  2. Deploy Caddy container (caddy-<target>)"
    echo "  3. Configure automatic HTTPS if domain is set"
    echo ""
}

# Check arguments
if [[ "$1" == "--help" || "$1" == "-h" || -z "$1" ]]; then
    show_usage
    exit 0
fi

TARGET="$1"
TARGET_DIR="${SCRIPT_DIR}/targets/${TARGET}"

# Verify target directory exists
if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Target directory not found: ${TARGET_DIR}"
    exit 1
fi

# Load target config
if [ -f "${TARGET_DIR}/.config" ]; then
    source "${TARGET_DIR}/.config"
else
    echo "Error: Target config not found: ${TARGET_DIR}/.config"
    exit 1
fi

# Verify required variables
if [ -z "$SSH_HOST" ]; then
    echo "Error: SSH_HOST not set in ${TARGET_DIR}/.config"
    exit 1
fi

if [ -z "$DOMAIN" ]; then
    echo "Warning: DOMAIN not set in .config. Caddy will not enable HTTPS."
    echo "Set DOMAIN in ${TARGET_DIR}/.config for automatic HTTPS."
fi

# Default APP_PORT if not set
APP_PORT="${APP_PORT:-3000}"

# Set Caddy container name
CADDY_CONTAINER="caddy-${TARGET}"
REMOTE_CADDY_DIR="/var/app/${CADDY_CONTAINER}"
CADDYFILE_PATH="${REMOTE_CADDY_DIR}/Caddyfile"

echo "========================================="
echo "Caddy Setup"
echo "========================================="
echo "Target: ${TARGET}"
echo "SSH Host: ${SSH_HOST}"
echo "Caddy Container: ${CADDY_CONTAINER}"
echo "Domain: ${DOMAIN:-<not configured>}"
echo "App Port: ${APP_PORT}"
echo ""

# Check SSH connection
echo "[1/6] Checking SSH connection..."
if ! ssh ${SSH_HOST} "echo 'SSH connection successful'" >/dev/null 2>&1; then
    echo "Error: Cannot connect to ${SSH_HOST}"
    exit 1
fi
echo "✓ SSH connection verified"
echo ""

# Check if podman is installed
echo "[2/6] Checking Podman installation..."
if ! ssh ${SSH_HOST} "command -v podman >/dev/null 2>&1"; then
    echo "Podman not found. Installing..."
    ssh ${SSH_HOST} "sudo apt-get update && sudo apt-get install -y podman"
    echo "✓ Podman installed successfully"
else
    echo "✓ Podman already installed"
fi
echo ""

# Create remote directory for Caddy config
echo "[3/6] Creating Caddy configuration directory..."
ssh ${SSH_HOST} "mkdir -p ${REMOTE_CADDY_DIR}/data ${REMOTE_CADDY_DIR}/config"
echo "✓ Directory created: ${REMOTE_CADDY_DIR}"
echo ""

# Generate Caddyfile
echo "[4/6] Generating Caddyfile..."
if [ -n "$DOMAIN" ]; then
    # With domain - automatic HTTPS
    CADDYFILE_CONTENT="${DOMAIN} {
    reverse_proxy localhost:${APP_PORT}
    
    # Optional: Enable compression
    encode gzip
    
    # Optional: Add security headers
    header {
        # Enable HSTS
        Strict-Transport-Security \"max-age=31536000; includeSubDomains; preload\"
        # Prevent content type sniffing
        X-Content-Type-Options \"nosniff\"
        # Enable XSS protection
        X-Frame-Options \"SAMEORIGIN\"
    }
}"
else
    # Without domain - HTTP only on port 80
    CADDYFILE_CONTENT=":80 {
    reverse_proxy localhost:${APP_PORT}
}"
fi

# Upload Caddyfile
ssh ${SSH_HOST} "cat > ${CADDYFILE_PATH}" <<< "$CADDYFILE_CONTENT"
echo "✓ Caddyfile created"
echo ""

# Check if Caddy container already exists
echo "[5/6] Checking for existing Caddy container..."
CADDY_EXISTS=$(ssh ${SSH_HOST} "podman ps -a --format '{{.Names}}' | grep -c '^${CADDY_CONTAINER}$' || true")

if [ "$CADDY_EXISTS" -gt 0 ]; then
    echo "Caddy container exists. Stopping and removing..."
    ssh ${SSH_HOST} "podman stop ${CADDY_CONTAINER}" >/dev/null 2>&1 || true
    ssh ${SSH_HOST} "podman rm ${CADDY_CONTAINER}" >/dev/null 2>&1 || true
    echo "✓ Old container removed"
fi
echo ""

# Deploy Caddy container
echo "[6/6] Deploying Caddy container..."
ssh ${SSH_HOST} "podman run -d \
    --name ${CADDY_CONTAINER} \
    --restart=always \
    --network=host \
    -v ${CADDYFILE_PATH}:/etc/caddy/Caddyfile:ro \
    -v ${REMOTE_CADDY_DIR}/data:/data \
    -v ${REMOTE_CADDY_DIR}/config:/config \
    docker.io/library/caddy:latest"

echo "✓ Caddy container deployed"
echo ""

# Verify deployment
sleep 3
CADDY_STATUS=$(ssh ${SSH_HOST} "podman ps --filter name=${CADDY_CONTAINER} --format '{{.Status}}'")

if [ -z "$CADDY_STATUS" ]; then
    echo "⚠ Warning: Caddy container is not running. Checking logs..."
    ssh ${SSH_HOST} "podman logs --tail 30 ${CADDY_CONTAINER}"
    exit 1
fi

echo "✓ Caddy is running: ${CADDY_STATUS}"
echo ""

# Show Caddy info
ssh ${SSH_HOST} "podman ps --filter name=${CADDY_CONTAINER}"
echo ""

echo "========================================="
echo "Caddy Setup Complete!"
echo "========================================="
echo ""
echo "Caddy Container: ${CADDY_CONTAINER}"
echo "Configuration: ${CADDYFILE_PATH}"
if [ -n "$DOMAIN" ]; then
    echo "Domain: ${DOMAIN}"
    echo "HTTPS: Enabled (automatic via Let's Encrypt)"
else
    echo "Domain: Not configured (HTTP only on port 80)"
fi
echo "Proxying to: localhost:${APP_PORT}"
echo ""
echo "Next steps:"
echo "  1. Deploy your application with: ./deploy-with-caddy.sh ${TARGET}"
echo "  2. View Caddy logs: ssh ${SSH_HOST} 'podman logs -f ${CADDY_CONTAINER}'"
echo "  3. Update Caddyfile: Edit on server at ${CADDYFILE_PATH}"
echo "  4. Reload Caddy: ssh ${SSH_HOST} 'podman exec ${CADDY_CONTAINER} caddy reload --config /etc/caddy/Caddyfile'"
echo ""
