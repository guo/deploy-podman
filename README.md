# Shipd - Container Deployment Automation

This repository contains automated deployment scripts for running containers across multiple servers/environments. Supports both **Docker** and **Podman** with automatic engine selection based on deployment type.

## Installation

Shipd supports two installation methods: **Homebrew** (recommended) and **Manual**.

### Method 1: Homebrew (Recommended)

**Best for:** macOS and Linux users with Homebrew

```bash
# Install from Homebrew tap
brew tap yourusername/tap
brew install shipd

# Verify installation
shipd --version
```

**Installation locations (managed by Homebrew):**
- **Apple Silicon**: `/opt/homebrew/bin/shipd` and `/opt/homebrew/lib/shipd/`
- **Intel Mac**: `/usr/local/bin/shipd` and `/usr/local/lib/shipd/`
- **User data**: `~/.shipd/targets/` (created automatically)

**Benefits:**
- ✅ Automatic updates via `brew upgrade shipd`
- ✅ Clean uninstall via `brew uninstall shipd`
- ✅ Managed dependencies
- ✅ Standard package management

**Update/Uninstall:**
```bash
# Update to latest version
brew upgrade shipd

# Uninstall (preserves ~/.shipd/)
brew uninstall shipd
```

### Method 2: Manual Install

**Best for:** Systems without Homebrew, CI/CD, custom setups

```bash
# Clone the repository
git clone https://github.com/yourusername/shipd.git
cd shipd

# Run the install script
./install.sh

# Verify installation
shipd --version
```

**Installation locations:**
- **Command**: `/usr/local/bin/shipd`
- **Libraries**: `/usr/local/lib/shipd/`
- **User data**: `~/.shipd/targets/` (created automatically)

**Benefits:**
- ✅ Works without Homebrew
- ✅ Works on any Linux distribution
- ✅ Suitable for CI/CD pipelines
- ✅ Full control over installation

**Update/Uninstall:**
```bash
# Update (re-run install script)
cd /path/to/shipd
git pull
./install.sh

# Uninstall (preserves ~/.shipd/)
./uninstall.sh
```

### Method 3: Development Mode (No Installation)

**Best for:** Development, testing, or trying out shipd

Run directly from the repository without installation:

```bash
cd /path/to/shipd
./shipd.sh deploy myapp
./shipd.sh deploy-multi --all
./shipd.sh --help
```

Uses `./targets/` directory in the repository.

### Target Search Order

After installation (both Homebrew and manual), `shipd` searches for targets in this order:

1. **`./targets/`** (current directory) - Project-specific deployments
2. **`~/.shipd/targets/`** (home directory) - Global/shared deployments

**This allows you to:**
- Keep project-specific targets with your code (`./targets/`)
- Store shared targets in home directory (`~/.shipd/targets/`)
- Override home targets with local ones when needed
- Use `shipd` from any directory

**Example:**
```bash
# Use home directory target
cd ~/any-project
shipd deploy myapp              # Uses ~/.shipd/targets/myapp

# Override with local target
mkdir -p ./targets/myapp        # Create local target
shipd deploy myapp              # Uses ./targets/myapp (priority)
```

### User Data Preservation

Both uninstall methods preserve your deployment targets and configuration:
- `~/.shipd/targets/` - Your deployment targets (preserved)
- `~/.shipd/.config` - Optional global config (preserved)

To completely remove everything:
```bash
rm -rf ~/.shipd
```

## Overview

This repository provides deployment automation with **dual container engine support** (Docker + Podman):

### Deployment Methods

1. **Direct Deployment** (`shipd deploy`) - Automatic engine selection
   - **Single-container**: Podman (default) or Docker (configurable via `ENGINE` in `.config`)
   - **Multi-container (compose)**: Docker (automatic)
   - Brief downtime during updates

2. **Zero-Downtime Deployment** (`shipd deploy` with `USE_CADDY="true"`) - Blue-green deployment via Caddy
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

### Option 1: Project-Local Targets (Development)

Best for keeping targets with your project code:

```bash
# 1. (Optional) Create global defaults
cp .config.example .config
vi .config

# 2. Create target directory
mkdir -p targets/myapp-prod

# 3. Create target configuration
cp .config.example targets/myapp-prod/.config
vi targets/myapp-prod/.config

# 4. Create environment file
cp env.example targets/myapp-prod/.env
vi targets/myapp-prod/.env

# 5. (Optional) Add additional config files
echo '{"key":"value"}' > targets/myapp-prod/config.json
```

### Option 2: Home Directory Targets (Installed)

Best for global shared targets after installing `shipd`:

```bash
# 1. Install shipd globally
./install.sh

# 2. (Optional) Create global defaults
mkdir -p ~/.shipd
cp .config.example ~/.shipd/.config
vi ~/.shipd/.config

# 3. Create target directory
mkdir -p ~/.shipd/targets/myapp-prod

# 4. Create target configuration
cp .config.example ~/.shipd/targets/myapp-prod/.config
vi ~/.shipd/targets/myapp-prod/.config

# 5. Create environment file
cp env.example ~/.shipd/targets/myapp-prod/.env
vi ~/.shipd/targets/myapp-prod/.env

# 6. Deploy from anywhere
cd ~/projects/myapp
shipd deploy myapp-prod
```

**Important**: The `.config` files and `targets/` directories contain sensitive credentials. The repository's `.gitignore` excludes `./targets/` and `./.config`. Never commit these files to version control.


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
├── shipd.sh                    # Main CLI entry point
└── lib/
    ├── cmd-deploy.sh           # Deploy command
    ├── cmd-deploy-multi.sh     # Multi-target deploy command
    ├── cmd-setup-caddy.sh      # Caddy setup command
    ├── deploy-podman.sh        # Podman deployment module
    ├── deploy-docker.sh        # Docker deployment module
    └── deploy-caddy.sh         # Caddy zero-downtime module
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

# Direct Deployment Settings (shipd deploy)
PORT_MAPPINGS="80:3000"  # Only used by direct deploy
FILE_MAPPINGS="config.json:/app/config.json"

# Caddy Deployment Settings (shipd deploy with USE_CADDY="true")
USE_CADDY="true"
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

#### Direct Deployment Only (`shipd deploy`)

| Variable | Description | Example |
|----------|-------------|---------|
| `PORT_MAPPINGS` | Host to container port mapping | `80:3000,443:3443` |

#### Caddy Deployment Only (`shipd deploy` with `USE_CADDY="true"`)

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
shipd deploy myapp-prod

# Deploy specific version/tag
shipd deploy myapp-prod v1.2.3

# Rollback to previous version
shipd deploy myapp-prod v1.2.2
```

**Process**: Stops old container → Removes → Starts new container

### Method 2: Zero-Downtime Deployment (Caddy + Blue-Green)

Use `shipd setup-caddy` + `shipd deploy` (with `USE_CADDY="true"`) for production deployments requiring zero downtime.

#### Initial Setup (One-Time)

```bash
# Setup Caddy reverse proxy for the target
shipd setup-caddy myapp-prod
```

This creates a Caddy container that:
- Listens on port 80 (HTTP only, SSL handled by Cloudflare/proxy)
- Proxies to your app on `localhost:${APP_PORT}`
- Has `auto_https` disabled (external proxy handles SSL)

#### Deploy Updates

```bash
# Deploy latest version with zero downtime
shipd deploy with USE_CADDY="true" myapp-prod

# Deploy specific version
shipd deploy with USE_CADDY="true" myapp-prod v1.2.3

# Rollback with zero downtime
shipd deploy with USE_CADDY="true" myapp-prod v1.2.2
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
shipd deploy myapp-prod

# Deploy specific version
shipd deploy myapp-prod v1.2.3

# Deploy to multiple compose targets
shipd deploy-multi --all
```

**Auto-detection**: If `compose.yml` or `docker-compose.yml` exists in the target directory, the deployment script automatically uses `podman compose` instead of single-container deployment.

**Configuration**: For compose targets, the `.config` file is simplified - only `SSH_HOST` is required. All container settings (images, ports, volumes, networks) are defined in the compose file.

**Limitations**:
- ⚠️ Zero-downtime deployment (`shipd deploy` with `USE_CADDY="true"`) does not support compose targets yet
- Use `shipd deploy` for compose deployments (brief downtime during update)

See [compose.example.yml](compose.example.yml) for a complete example and [CLAUDE.md](CLAUDE.md#compose-deployments-multi-container) for detailed documentation.

## Deploy to Multiple Targets

Use the `deploy-multi.sh` script to deploy to multiple targets at once.

### Deploy to All Targets

```bash
# Deploy to all targets sequentially (with confirmation)
shipd deploy-multi --all

# Deploy to all targets in parallel
shipd deploy-multi --all --parallel
```

When using `--all`, the script will:
1. List all configured targets
2. Ask for confirmation before proceeding

### Deploy to Specific Targets

```bash
# Deploy to specific targets sequentially
shipd deploy-multi deployment1 deployment2

# Deploy to specific targets in parallel
shipd deploy-multi --parallel deployment1 deployment2
```

### Options

```
Usage: shipd deploy-multi [OPTIONS] <TARGETS...>

Options:
  --all              Deploy to all configured targets
  -p, --parallel     Deploy in parallel (faster)
  -s, --sequential   Deploy sequentially (default)
  -h, --help         Show help message

Examples:
  shipd deploy-multi --all                     # Deploy to all (with confirmation)
  shipd deploy-multi --all --parallel          # Deploy to all in parallel
  shipd deploy-multi staging production        # Deploy to staging and production
  shipd deploy-multi -p staging production     # Deploy to both in parallel
```

Note: Running `shipd deploy-multi` without arguments will show the help message.

### Deployment Logs

Each target's deployment creates a log file:
- `deploy-deployment1.log`
- `deploy-deployment2.log`

Check these files if a deployment fails.

## How It Works

### Direct Deployment (`shipd deploy`)

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

**Prerequisites**: Run `shipd setup-caddy <target>` once to create Caddy container

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
