# Podman Multi Deployment Script

This repository contains an automated deployment script for running containers across multiple servers/environments using Podman.

## Overview

The deployment script automates the process of:
- Installing Podman on remote hosts
- Managing multiple targets (production, staging, demo, development)
- Uploading target-specific configurations
- Authenticating with GitHub Container Registry
- Deploying or updating containers with zero downtime

## Prerequisites

- SSH access to target hosts (configured in `targets.config`)
- Sudo privileges on remote hosts
- GitHub Container Registry credentials
- SSH keys configured for passwordless authentication

## Initial Setup

1. **Create deployment configuration**
   ```bash
   # Copy the example configuration
   cp targets.config.example targets.config

   # Edit targets.config with your actual values:
   # - GHCR_USERNAME and GHCR_TOKEN for GitHub Container Registry
   # - SSH_HOST for each target
   # - Container names, ports, and paths
   vi targets.config
   ```

2. **Create env files**
   ```bash
   # Copy the example for each target you need
   cp env.example .env.deployment1
   cp env.example .env.deployment2

   # Edit each .env file with target-specific values
   vi .env.deployment1
   ```

**Important**: The `targets.config` and `.env*` files contain sensitive credentials and are excluded from git via `.gitignore`. Never commit these files to version control.


## Multi-Server Configuration

### targets.config Structure

The `targets.config` file uses an INI-style format with sections for each target:

```bash
# Common Configuration (shared across all targets)
CONTAINER_IMAGE="ghcr.io/xxx/xxxx"
GHCR_USERNAME="user"
GHCR_TOKEN="ghp_..."

# Target-specific configuration
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

### Env Files

Each target has its own `.env` file:

| File | Target | Purpose |
|------|--------|---------|
| `.env.deployment1` | Deployment 1 | First deployment target |
| `.env.deployment2` | Deployment 2 | Second deployment target |

## Quick Start

### 1. Configure Targets

Edit `targets.config` to set up your server configurations:
- Update SSH hosts for each target
- Configure container names and ports
- Set GitHub Container Registry credentials

### 2. Configure Environment Variables

Edit the appropriate `.env.*` file for your target:

### 3. Deploy to Specific Target

```bash
# Deploy to deployment1
./deploy-podman-ssh.sh deployment1

# Deploy to deployment2
./deploy-podman-ssh.sh deployment2
```

### 4. List Available Targets

```bash
./deploy-podman-ssh.sh --help
```

Output:
```
Usage: ./deploy-podman-ssh.sh <target>

Available targets:
  - deployment1
  - deployment2

Example: ./deploy-podman-ssh.sh deployment1
         ./deploy-podman-ssh.sh deployment2
```

## Deploy to Multiple Targets

Use the `deploy-multi.sh` script to deploy to multiple targets at once.

### Deploy to All Targets

```bash
# Deploy to all targets sequentially (with confirmation)
./deploy-multi.sh --all

# Deploy to all targets in parallel
./deploy-multi.sh --all --parallel
```

When using `--all`, the script will:
1. List all configured targets
2. Ask for confirmation before proceeding

### Deploy to Specific Targets

```bash
# Deploy to specific targets sequentially
./deploy-multi.sh deployment1 deployment2

# Deploy to specific targets in parallel
./deploy-multi.sh --parallel deployment1 deployment2
```

### Options

```
Usage: ./deploy-multi.sh [OPTIONS] <TARGETS...>

Options:
  --all              Deploy to all configured targets
  -p, --parallel     Deploy in parallel (faster)
  -s, --sequential   Deploy sequentially (default)
  -h, --help         Show help message

Examples:
  ./deploy-multi.sh --all                     # Deploy to all (with confirmation)
  ./deploy-multi.sh --all --parallel          # Deploy to all in parallel
  ./deploy-multi.sh staging production        # Deploy to staging and production
  ./deploy-multi.sh -p staging production     # Deploy to both in parallel
```

Note: Running `./deploy-multi.sh` without arguments will show the help message.

### Deployment Logs

Each target's deployment creates a log file:
- `deploy-deployment1.log`
- `deploy-deployment2.log`

Check these files if a deployment fails.

## How It Works

The deployment script performs these steps for the selected target:

1. **Parses configuration** - Reads targets.config for the specified target
2. **Validates files** - Checks that env file exists
3. **Verifies SSH** - Tests connection to the target server
4. **Checks Podman** - Installs if not present
5. **Uploads env file** - Copies the appropriate `.env.*` file
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
