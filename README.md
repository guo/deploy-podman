# Podman Multi Deployment Script

This repository contains an automated deployment script for running containers across multiple servers/environments using Podman.

## Overview

The deployment script automates the process of:
- Installing Podman on remote hosts
- Managing multiple environments (production, staging, demo, development)
- Uploading environment-specific configurations
- Authenticating with GitHub Container Registry
- Deploying or updating containers with zero downtime

## Prerequisites

- SSH access to target hosts (configured in `deploy.config`)
- Sudo privileges on remote hosts
- GitHub Container Registry credentials
- SSH keys configured for passwordless authentication

## Initial Setup

1. **Create deployment configuration**
   ```bash
   # Copy the example configuration
   cp deploy.config.example deploy.config

   # Edit deploy.config with your actual values:
   # - GHCR_USERNAME and GHCR_TOKEN for GitHub Container Registry
   # - SSH_HOST for each environment
   # - Container names, ports, and paths
   vi deploy.config
   ```

2. **Create environment files**
   ```bash
   # Copy the example for each environment you need
   cp env.example .env.deployment1
   cp env.example .env.deployment2

   # Edit each .env file with environment-specific values
   vi .env.deployment1
   ```

**Important**: The `deploy.config` and `.env*` files contain sensitive credentials and are excluded from git via `.gitignore`. Never commit these files to version control.


## Multi-Server Configuration

### deploy.config Structure

The `deploy.config` file uses an INI-style format with sections for each environment:

```bash
# Common Configuration (shared across all environments)
CONTAINER_IMAGE="ghcr.io/xxx/xxxx"
GHCR_USERNAME="user"
GHCR_TOKEN="ghp_..."

# Environment-specific configuration
[deployment1]
SSH_HOST="DEPLOYMENT1_HOST"
CONTAINER_NAME="container_name"
CONTAINER_PORT="3000"
HOST_PORT="80"
ENV_FILE=".env.deployment1"
ENV_FILE_REMOTE_PATH="/path/to/env/file/on/remote/server"

[deployment2]
SSH_HOST="DEPLOYMENT2_HOST"
CONTAINER_NAME="container_name"
CONTAINER_PORT="3000"
HOST_PORT="80"
ENV_FILE=".env.deployment2"
ENV_FILE_REMOTE_PATH="/path/to/env/file/on/remote/server"
```

### Environment Files

Each environment has its own `.env` file:

| File | Environment | Purpose |
|------|-------------|---------|
| `.env.deployment1` | Deployment 1 | First deployment environment |
| `.env.deployment2` | Deployment 2 | Second deployment environment |

## Quick Start

### 1. Configure Environments

Edit `deploy.config` to set up your server configurations:
- Update SSH hosts for each environment
- Configure container names and ports
- Set GitHub Container Registry credentials

### 2. Configure Environment Variables

Edit the appropriate `.env.*` file for your environment:

### 3. Deploy to Specific Environment

```bash
# Deploy to deployment1
./deploy-podman-ssh.sh deployment1

# Deploy to deployment2
./deploy-podman-ssh.sh deployment2
```

### 4. List Available Environments

```bash
./deploy-podman-ssh.sh --help
```

Output:
```
Usage: ./deploy-podman-ssh.sh <environment>

Available environments:
  - deployment1
  - deployment2

Example: ./deploy-podman-ssh.sh deployment1
         ./deploy-podman-ssh.sh deployment2
```

## Deploy to All Environments

Use the `deploy-all.sh` script to deploy to multiple environments at once.

### Deploy to All Environments Sequentially

```bash
./deploy-all.sh
```

This will deploy to all configured environments one by one (default mode).

### Deploy to All Environments in Parallel

```bash
./deploy-all.sh --parallel
```

This deploys to all environments simultaneously (faster but uses more resources).

### Deploy to Specific Environments

```bash
# Deploy only to deployment1 and deployment2
./deploy-all.sh deployment1 deployment2

# Deploy to both deployments in parallel
./deploy-all.sh --parallel deployment1 deployment2
```

### Options

```
Usage: ./deploy-all.sh [OPTIONS] [ENVIRONMENTS...]

Options:
  -p, --parallel     Deploy to all environments in parallel (faster)
  -s, --sequential   Deploy to all environments sequentially (default)
  -h, --help         Show help message

Examples:
  ./deploy-all.sh                           # Deploy to all sequentially
  ./deploy-all.sh --parallel                # Deploy to all in parallel
  ./deploy-all.sh deployment1 deployment2   # Deploy only to deployment1 and deployment2
  ./deploy-all.sh -p deployment1 deployment2 # Deploy to both deployments in parallel
```

### Deployment Logs

Each environment's deployment creates a log file:
- `deploy-deployment1.log`
- `deploy-deployment2.log`

Check these files if a deployment fails.

## How It Works

The deployment script performs these steps for the selected environment:

1. **Parses configuration** - Reads deploy.config for the specified environment
2. **Validates files** - Checks that environment file exists
3. **Verifies SSH** - Tests connection to the target server
4. **Checks Podman** - Installs if not present
5. **Uploads environment** - Copies the appropriate `.env.*` file
6. **Authenticates** - Logs into GitHub Container Registry
7. **Pulls latest image** - Downloads the newest container version
8. **Updates container**:
   - If exists: Stops, removes, and recreates with latest image
   - If new: Creates fresh deployment
9. **Verifies** - Confirms container is running and shows logs

## Update Existing Deployment

Simply run the deployment script again to update to the latest image:

```bash
# Update deployment1
./deploy-podman-ssh.sh deployment1

# Update deployment2
./deploy-podman-ssh.sh deployment2
```

The script automatically:
- Pulls the latest image
- Stops the existing container gracefully
- Removes the old container
- Starts a new container with the latest image
- Verifies the deployment
