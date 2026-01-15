# Shipd - Container Deployment Automation

This repository contains automated deployment scripts for running containers across multiple servers/environments. Supports both **Docker** and **Podman** with automatic engine selection based on deployment type.

## Overview

This repository provides deployment automation with **dual container engine support** (Docker + Podman):

### Deployment Methods

1. **Direct Deployment** (`deploy.sh` or `deploy.sh`) - Automatic engine selection
   - **Single-container**: Podman (default) or Docker (configurable via `ENGINE` in `.config`)
   - **Multi-container (compose)**: Docker (automatic)
   - Brief downtime during updates

2. **Zero-Downtime Deployment** (`deploy.sh with USE_CADDY="true"`) - Blue-green deployment via Caddy
   - Single-container only (Podman or Docker)
   - Production-ready with health checks

### Container Engine Selection

- **Docker**: For both single-container and multi-container (compose) deployments
- **Podman**: For single-container deployments only (rootless, more secure)
- **Auto-detection**: Compose files automatically use Docker; single-container defaults to Podman

All methods automate:
- Installing container engine on remote hosts (Docker or Podman)
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
shipd/
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
├── deploy.sh        # Direct deployment (brief downtime)
├── setup-caddy.sh              # One-time Caddy setup
├── deploy.sh with USE_CADDY="true"        # Zero-downtime deployment
└── deploy-multi.sh             # Batch deployment
```

Files are uploaded to remote host at `/var/app/${CONTAINER_NAME}/`

### Configuration Files

#### `.config` (Bash Variables)

Each target has a `.config` file with bash variables:

```bash
# Container Configuration
CONTAINER_IMAGE="ghcr.io/your-org/your-app"
GHCR_USERNAME="your-username"
GHCR_TOKEN="ghp_your_token"
SSH_HOST="your-ssh-host"
CONTAINER_NAME="myapp-prod"

# Direct Deployment Settings (deploy.sh)
PORT_MAPPINGS="80:3000"  # Only used by deploy.sh
FILE_MAPPINGS="config.json:/app/config.json"

# Caddy Deployment Settings (deploy.sh with USE_CADDY="true")
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

#### Direct Deployment Only (`deploy.sh`)

| Variable | Description | Example |
|----------|-------------|---------|
| `PORT_MAPPINGS` | Host to container port mapping | `80:3000,443:3443` |

#### Caddy Deployment Only (`deploy.sh with USE_CADDY="true"`)

| Variable | Description | Example |
|----------|-------------|---------|
| `DOMAIN` | Domain name (informational) | `example.com` |
| `APP_PORT` | Internal app port for Caddy proxy | `3000` |
| `HEALTH_CHECK_PATH` | Health check URL path | `/` or `/health` |
| `HEALTH_CHECK_TIMEOUT` | Startup timeout in seconds | `30` |

**Important**: `PORT_MAPPINGS` is NOT used with Caddy deployment. Caddy uses `--network=host` and proxies to `localhost:${APP_PORT}`.

## Deployment Methods

### Method 1: Direct Deployment (Simple, Brief Downtime)

Use `deploy.sh` for simple deployments where brief downtime during updates is acceptable.

```bash
# Deploy latest version
./deploy.sh myapp-prod

# Deploy specific version/tag
./deploy.sh myapp-prod v1.2.3

# Rollback to previous version
./deploy.sh myapp-prod v1.2.2
```

**Process**: Stops old container → Removes → Starts new container

### Method 2: Zero-Downtime Deployment (Caddy + Blue-Green)

Use `setup-caddy.sh` + `deploy.sh with USE_CADDY="true"` for production deployments requiring zero downtime.

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
./deploy.sh with USE_CADDY="true" myapp-prod

# Deploy specific version
./deploy.sh with USE_CADDY="true" myapp-prod v1.2.3

# Rollback with zero downtime
./deploy.sh with USE_CADDY="true" myapp-prod v1.2.2
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

### Method 3: Multi-Container Deployment (Compose)

Deploy complete application stacks with multiple services (app + database + cache) using Docker Compose.

#### Requirements

- Docker (auto-installed during deployment)
- Docker Compose v2 (auto-installed during deployment)
- Brief downtime during deployment (zero-downtime not supported yet)

#### Under the Hood

This deployment method uses **Docker + Docker Compose v2**:
- Docker is auto-installed if not present
- Docker Compose v2 is auto-installed if not present
- Simple and reliable (official Docker tooling)
- 100% compatible with standard docker-compose.yml files

**Note:** Compose deployments automatically use Docker (Podman doesn't support compose in this implementation). The `ENGINE` setting in `.config` is ignored for compose targets.

#### Setup

```bash
# Create target with compose file
mkdir -p targets/myapp-prod
cp compose.example.yml targets/myapp-prod/compose.yml
vi targets/myapp-prod/compose.yml

# Create simplified config (most settings in compose.yml)
echo 'SSH_HOST="user@server.com"' > targets/myapp-prod/.config

# Create environment file
cp env.example targets/myapp-prod/.env
vi targets/myapp-prod/.env
```

#### Deployment

```bash
# Deploy with latest tag (auto-detects compose)
./deploy.sh myapp-prod

# Deploy specific version
./deploy.sh myapp-prod v1.2.3

# Deploy to multiple compose targets
./deploy-multi.sh --all
```

**Auto-detection**: If `compose.yml` or `docker-compose.yml` exists in the target directory, the deployment script automatically uses `podman compose` instead of single-container deployment.

**Configuration**: For compose targets, the `.config` file is simplified - only `SSH_HOST` is required. All container settings (images, ports, volumes, networks) are defined in the compose file.

**Limitations**:
- ⚠️ Zero-downtime deployment (`deploy.sh with USE_CADDY="true"`) does not support compose targets yet
- Use `deploy.sh` for compose deployments (brief downtime during update)

See [compose.example.yml](compose.example.yml) for a complete example and [CLAUDE.md](CLAUDE.md#compose-deployments-multi-container) for detailed documentation.

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

### Direct Deployment (`deploy.sh`)

**Auto-detects** deployment mode: single-container or compose

#### Single-Container Mode

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

#### Compose Mode (auto-detected if compose.yml exists)

1. **Loads configuration** - Sources global `.config` (if exists), then target `.config`
2. **Installs Docker Compose v2** - Downloads and installs if not present
3. **Detects Podman mode** - Checks if rootless or rootful Podman
4. **Enables Podman socket** - Starts socket service for Docker Compose compatibility
5. **Verifies SSH** - Tests connection to target server
6. **Uploads files** - Copies entire target directory (including compose.yml) to `/var/app/${TARGET}/`
7. **Authenticates** - Logs into container registry (if credentials provided)
8. **Deploys stack**:
   - Exports `IMAGE_TAG` environment variable
   - Runs `DOCKER_HOST=unix:///run/podman/podman.sock docker-compose down`
   - Runs `DOCKER_HOST=unix:///run/podman/podman.sock docker-compose up -d`
9. **Verifies** - Confirms all services are running

### Zero-Downtime Deployment (`deploy.sh with USE_CADDY="true"`)

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
