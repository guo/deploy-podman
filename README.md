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

2. **Create container directories**
   ```bash
   # Create targets directory
   mkdir -p targets

   # Create a directory for each container (use CONTAINER_NAME from config)
   mkdir -p targets/myapp-prod
   mkdir -p targets/myapp-staging

   # Create .env file in each container directory
   cp env.example targets/myapp-prod/.env
   cp env.example targets/myapp-staging/.env

   # Edit .env files with target-specific values
   vi targets/myapp-prod/.env
   vi targets/myapp-staging/.env

   # Add additional config files if needed
   echo '{"key":"value"}' > targets/myapp-prod/config.json
   ```

**Important**: The `targets.config` and `targets/` directory contain sensitive credentials and are excluded from git via `.gitignore`. Never commit these files to version control.


## Multi-Server Configuration

### Directory Structure

All container directories are organized under the `targets/` folder:

```
deploy-podman/
├── targets.config
├── targets/
│   ├── myapp-prod/
│   │   ├── .env              # Required: environment variables
│   │   ├── config.json       # Optional: additional config files
│   │   └── data.txt          # Optional: data files
│   └── myapp-staging/
│       ├── .env              # Required: environment variables
│       └── config.json       # Optional: additional config files
├── deploy-podman-ssh.sh
└── deploy-multi.sh
```

Files are uploaded to remote host at `/var/app/${CONTAINER_NAME}/`

### targets.config Structure

The `targets.config` file uses an INI-style format with sections for each target:

```bash
# Common Configuration (shared across all targets)
# These serve as defaults and can be overridden per-target
CONTAINER_IMAGE="ghcr.io/xxx/xxxx"
GHCR_USERNAME="user"
GHCR_TOKEN="ghp_..."

# Target 1 - Uses global credentials
[prod1]
SSH_HOST="PROD_HOST"
CONTAINER_NAME="myapp-prod"
PORT_MAPPINGS="80:3000,443:3443"  # Multiple port mappings
FILE_MAPPINGS="config.json:/app/config.json"

# Target 2 - Public image (no credentials)
[staging]
SSH_HOST="STAGING_HOST"
CONTAINER_NAME="myapp-staging"
PORT_MAPPINGS="80:80"
CONTAINER_IMAGE="nginx:latest"  # Override with public image
GHCR_USERNAME=""                # No credentials needed
GHCR_TOKEN=""

# Target 3 - Different private registry
[dev]
SSH_HOST="DEV_HOST"
CONTAINER_NAME="myapp-dev"
PORT_MAPPINGS="8080:3000"
CONTAINER_IMAGE="ghcr.io/other-org/dev:latest"  # Override image
GHCR_USERNAME="dev-user"                         # Override credentials
GHCR_TOKEN="ghp_dev_token"
```

### Configuration Inheritance

Each target can override global settings:

- **CONTAINER_IMAGE** - Defaults to global value, can be overridden per-target
- **GHCR_USERNAME** - Defaults to global value, can be overridden per-target
- **GHCR_TOKEN** - Defaults to global value, can be overridden per-target
- **Public images** - Set `GHCR_USERNAME=""` and `GHCR_TOKEN=""` to skip authentication

### Port Mappings

`PORT_MAPPINGS` defines how ports are mapped from host to container:

- **Format**: `"host_port:container_port,host_port2:container_port2"`
- **Examples**:
  - Single port: `PORT_MAPPINGS="80:3000"`
  - Multiple ports: `PORT_MAPPINGS="80:3000,443:3443"`
- **Optional**: Can be omitted if container doesn't expose ports

### File Mappings

`FILE_MAPPINGS` allows you to mount additional files from the container directory into the container:

- **Format**: `"local_file:container_path,local_file2:container_path2"`
- **Local paths**: Relative to `targets/${CONTAINER_NAME}/` directory
- **Optional**: Omit if you only need environment variables

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
2. **Validates directory** - Checks that `targets/${CONTAINER_NAME}/` directory and `.env` file exist
3. **Verifies SSH** - Tests connection to the target server
4. **Checks Podman** - Installs if not present
5. **Uploads files** - Copies entire container directory to `/var/app/${CONTAINER_NAME}/`
6. **Processes port mappings** - Parses `PORT_MAPPINGS` and builds port arguments
7. **Processes file mappings** - Parses `FILE_MAPPINGS` and builds volume mount arguments
8. **Authenticates** - Logs into container registry (skipped for public images)
9. **Pulls latest image** - Downloads the newest container version (with or without credentials)
10. **Updates container**:
   - If exists: Stops, removes, and recreates with latest image
   - If new: Creates fresh deployment
   - Uses `--env-file` for environment variables
   - Maps ports via `-p` flags
   - Mounts additional files via `-v` flags
11. **Verifies** - Confirms container is running and shows logs

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
