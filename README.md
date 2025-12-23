# Podman Multi Deployment Script

This repository contains an automated deployment script for running containers across multiple servers/environments using Podman.

## Overview

This repository provides two deployment methods:

1. **Direct Deployment** (`deploy-podman-ssh.sh`) - Simple deployment with brief downtime during updates
2. **Zero-Downtime Deployment** (`deploy-with-caddy.sh`) - Blue-green deployment via Caddy reverse proxy

Both methods automate:
- Installing Podman on remote hosts
- Managing multiple targets (production, staging, demo, development)
- Uploading target-specific configurations
- Authenticating with GitHub Container Registry
- Image tag/version management for deployments and rollbacks

## Prerequisites

- SSH access to target hosts (with SSH keys configured for passwordless authentication)
- Sudo privileges on remote hosts (for Podman installation)
- GitHub Container Registry credentials (or use public images)

## Initial Setup

1. **(Optional) Create global defaults**
   ```bash
   # Copy the example configuration for global defaults
   cp .config.example .config

   # Edit with common values shared across all targets
   vi .config
   ```

2. **Create a target**
   ```bash
   # Create target directory
   mkdir -p targets/myapp-prod

   # Create target configuration
   cp .config.example targets/myapp-prod/.config
   vi targets/myapp-prod/.config

   # Create environment file
   cp env.example targets/myapp-prod/.env
   vi targets/myapp-prod/.env

   # (Optional) Add additional config files for volume mapping
   echo '{"key":"value"}' > targets/myapp-prod/config.json
   ```

**Important**: The `.config` files and `targets/` directory contain sensitive credentials and are excluded from git via `.gitignore`. Never commit these files to version control.


## Configuration System

### Directory Structure

Each target is a directory under `targets/` with its own configuration:

```
deploy-podman/
├── .config                      # Optional: global defaults
├── .config.example              # Template for configuration
├── targets/
│   ├── myapp-prod/
│   │   ├── .config             # Required: deployment configuration
│   │   ├── .env                # Required: environment variables
│   │   ├── config.json         # Optional: additional files
│   │   └── data.txt            # Optional: data files
│   └── myapp-staging/
│       ├── .config             # Required: deployment configuration
│       ├── .env                # Required: environment variables
│       └── config.json         # Optional: additional files
├── deploy-podman-ssh.sh        # Direct deployment (brief downtime)
├── setup-caddy.sh              # One-time Caddy setup
├── deploy-with-caddy.sh        # Zero-downtime deployment
└── deploy-multi.sh             # Batch deployment
```

Files are uploaded to remote host at `/var/app/${CONTAINER_NAME}/`

### Configuration Files

#### `.config` (Bash Variables)

Each target has a `.config` file with bash variables:

```bash
# Container Configuration
CONTAINER_IMAGE="ghcr.io/iotexproject/depinscan"
GHCR_USERNAME="your-username"
GHCR_TOKEN="ghp_your_token"
SSH_HOST="your-ssh-host"
CONTAINER_NAME="myapp-prod"

# Direct Deployment Settings (deploy-podman-ssh.sh)
PORT_MAPPINGS="80:3000"  # Only used by deploy-podman-ssh.sh
FILE_MAPPINGS="config.json:/app/config.json"

# Caddy Deployment Settings (deploy-with-caddy.sh)
DOMAIN="example.com"
APP_PORT="3000"
HEALTH_CHECK_PATH="/"
HEALTH_CHECK_TIMEOUT="30"
```

#### Global vs Target Config

- **Global** `.config` (optional) - Sets defaults for all targets
- **Target** `targets/{target}/.config` (required) - Overrides global settings
- Target config is loaded after global config via bash `source`

#### `.env` File

Environment variables loaded into the container:

```bash
DATABASE_URL=postgresql://...
API_KEY=secret123
PORT=3000
```

### Configuration Variables

#### Common Variables (Both Methods)

| Variable | Description | Example |
|----------|-------------|---------|
| `CONTAINER_IMAGE` | OCI image to deploy | `ghcr.io/org/app` |
| `GHCR_USERNAME` | Registry username (empty for public) | `username` |
| `GHCR_TOKEN` | Registry token (empty for public) | `ghp_...` |
| `SSH_HOST` | Remote server hostname | `prod-server` |
| `CONTAINER_NAME` | Container name (defaults to target) | `myapp-prod` |
| `FILE_MAPPINGS` | Volume mounts | `config.json:/app/config.json` |

#### Direct Deployment Only (`deploy-podman-ssh.sh`)

| Variable | Description | Example |
|----------|-------------|---------|
| `PORT_MAPPINGS` | Host to container port mapping | `80:3000,443:3443` |

#### Caddy Deployment Only (`deploy-with-caddy.sh`)

| Variable | Description | Example |
|----------|-------------|---------|
| `DOMAIN` | Domain name (informational) | `example.com` |
| `APP_PORT` | Internal app port for Caddy proxy | `3000` |
| `HEALTH_CHECK_PATH` | Health check URL path | `/` or `/health` |
| `HEALTH_CHECK_TIMEOUT` | Startup timeout in seconds | `30` |

**Important**: `PORT_MAPPINGS` is NOT used with Caddy deployment. Caddy uses `--network=host` and proxies to `localhost:${APP_PORT}`.

## Deployment Methods

### Method 1: Direct Deployment (Simple, Brief Downtime)

Use `deploy-podman-ssh.sh` for simple deployments where brief downtime during updates is acceptable.

```bash
# Deploy latest version
./deploy-podman-ssh.sh myapp-prod

# Deploy specific version/tag
./deploy-podman-ssh.sh myapp-prod v1.2.3

# Rollback to previous version
./deploy-podman-ssh.sh myapp-prod v1.2.2
```

**Process**: Stops old container → Removes → Starts new container

### Method 2: Zero-Downtime Deployment (Caddy + Blue-Green)

Use `setup-caddy.sh` + `deploy-with-caddy.sh` for production deployments requiring zero downtime.

#### Initial Setup (One-Time)

```bash
# Setup Caddy reverse proxy for the target
./setup-caddy.sh myapp-prod
```

This creates a Caddy container that:
- Listens on port 80 (HTTP only, SSL handled by Cloudflare/proxy)
- Proxies to your app on `localhost:${APP_PORT}`
- Has `auto_https` disabled (external proxy handles SSL)

#### Deploy Updates

```bash
# Deploy latest version with zero downtime
./deploy-with-caddy.sh myapp-prod

# Deploy specific version
./deploy-with-caddy.sh myapp-prod v1.2.3

# Rollback with zero downtime
./deploy-with-caddy.sh myapp-prod v1.2.2
```

**Process**:
1. Starts new container on alternate port (blue: 3001)
2. Runs health check with timeout
3. Switches Caddy traffic to new container
4. Stops old container
5. Recreates container on standard port (green: 3000)
6. Switches traffic back and removes blue

**Architecture**:
```
Browser → HTTPS (Cloudflare) → HTTP (Caddy :80) → HTTP (App :3000)
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

### Direct Deployment (`deploy-podman-ssh.sh`)

1. **Loads configuration** - Sources global `.config` (if exists), then target `.config`
2. **Validates** - Checks target directory, `.config`, and `.env` file exist
3. **Verifies SSH** - Tests connection to target server
4. **Checks Podman** - Installs if not present
5. **Uploads files** - Copies entire target directory to `/var/app/${CONTAINER_NAME}/`
6. **Authenticates** - Logs into container registry (skipped for public images)
7. **Pulls image** - Downloads specified image:tag (defaults to `:latest`)
8. **Processes mappings**:
   - Port mappings: Builds `-p host:container` arguments
   - File mappings: Builds `-v` volume mount arguments
9. **Updates container**:
   - Stops existing container (if exists)
   - Removes old container
   - Creates new container with `--restart=always`
   - Uses `--env-file` for environment variables
10. **Verifies** - Confirms container is running

### Zero-Downtime Deployment (`deploy-with-caddy.sh`)

**Prerequisites**: Run `./setup-caddy.sh <target>` once to create Caddy container

1. **Loads configuration** - Sources global `.config` (if exists), then target `.config`
2. **Validates** - Checks Caddy container is running
3. **Uploads files** - Copies target directory to remote server
4. **Authenticates** - Logs into container registry (if needed)
5. **Pulls image** - Downloads specified image:tag
6. **Blue container**:
   - Starts new container on port 3001 (blue)
   - Runs health check with timeout
   - Aborts and rolls back if health check fails
7. **Traffic switch**:
   - Updates Caddyfile to proxy to blue (3001)
   - Reloads Caddy configuration
   - Stops old container
8. **Green container**:
   - Recreates container on port 3000 (green) with `--restart=always`
   - Updates Caddyfile to proxy to green (3000)
   - Reloads Caddy configuration
   - Removes blue container
9. **Verifies** - Confirms final container is running

**Result**: Zero downtime - traffic is always served during entire process
