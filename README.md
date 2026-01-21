# Shipd - Container Deployment Automation

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub release](https://img.shields.io/github/release/guo/shipd.svg)](https://github.com/guo/shipd/releases)
[![Homebrew](https://img.shields.io/badge/homebrew-available-blue.svg)](https://github.com/guo/homebrew-tap)

**Deploy containers to your servers from your laptop. No platform to install. Just SSH and go.**

Agentless container deployment for teams who don't need Kubernetes. Deploy remotely via SSH - your servers stay clean and simple, running only Docker/Podman. Zero-downtime deployments, multi-environment management, and Docker Compose support built-in.

## Why Shipd?

**Perfect for:**
- Small to medium teams running 5-50 services
- Deploying to VPS (DigitalOcean, Hetzner, AWS EC2)
- Projects that don't need Kubernetes complexity
- Teams who want simple, SSH-based deployments
- **Cost-conscious teams** - 10x cheaper than PaaS for multiple apps
- **Resource-constrained servers** - no platform overhead, fully utilize VPS capacity
- Anyone who wants to keep servers manually accessible and portable

**vs Kubernetes:** No cluster management, no YAML sprawl, no learning curve. Just SSH and containers.

**vs Docker/Podman directly:** Automated image updates, zero-downtime deployments, multi-environment config, rollback support. Deploy remotely without logging into servers.

**vs Ansible/Terraform:** Purpose-built for container deployments. Simpler config, faster iterations. No complex playbooks needed.

**vs Dokku/CapRover:** Agentless - no platform software to install on servers. Just SSH and deploy. Server stays vanilla.

**vs Platform-as-a-Service:** Keep full control. Deploy to your own servers. No vendor lock-in. **Much cheaper** - fully utilize your VPS capacity instead of paying per-app PaaS fees.

## Key Features

- **Agentless & Remote** - No software to install on servers. Deploy from your laptop via SSH. Server stays clean.
- **Zero-downtime deployments** - Blue-green deployment with health checks via Caddy
- **Multi-container stacks** - Full Docker Compose support for complex applications
- **Multi-environment** - Manage production, staging, demo environments from one place
- **Version control** - Deploy specific tags, rollback to previous versions instantly
- **Auto-installation** - Installs Docker/Podman on remote servers automatically
- **Flexible engines** - Use Docker or Podman (rootless by default)
- **Simple config** - Bash variables, no complex YAML or infrastructure code
- **GitHub Actions** - Ready-to-use CI/CD workflows included
- **Works everywhere** - Any Linux server you can SSH into. No cloud vendor lock-in.

## Quick Start

```bash
# Install
brew tap guo/tap
brew install shipd

# Configure a deployment target
mkdir -p ~/.shipd/targets/myapp-prod
echo 'SSH_HOST="user@server.com"' > ~/.shipd/targets/myapp-prod/.config
echo 'CONTAINER_IMAGE="ghcr.io/org/myapp"' >> ~/.shipd/targets/myapp-prod/.config
echo 'PORT_MAPPINGS="80:3000"' >> ~/.shipd/targets/myapp-prod/.config

# Create env file
echo 'DATABASE_URL=...' > ~/.shipd/targets/myapp-prod/.env

# Deploy
shipd deploy myapp-prod           # Deploy latest
shipd deploy myapp-prod v1.2.3    # Deploy specific version
```

That's it. No cluster setup, no complex YAML, just SSH and go.

## What Makes Shipd Different?

**Agentless Architecture** - Your servers stay clean and simple:

- ✅ No platform software to install (unlike Dokku, CapRover, Coolify)
- ✅ No agents or daemons running (unlike many deployment tools)
- ✅ **Minimal resource usage** - no platform overhead, just your containers
- ✅ Deploy from anywhere with SSH access (laptop, CI/CD, another server)
- ✅ Server just runs Docker/Podman - nothing else
- ✅ **Manually maintainable** - can SSH in and use standard docker/podman commands anytime
- ✅ No maintenance overhead - SSH + containers is all you need
- ✅ Easy to debug - everything is standard Docker/Podman commands
- ✅ **No proprietary layer** - never locked out of your own server

**Before Shipd:**
```bash
# SSH into each server
ssh prod-server
cd /app
docker pull myapp:latest
docker stop myapp
docker rm myapp
docker run -d --name myapp ...
exit

# Repeat for staging, demo, etc.
```

**With Shipd:**
```bash
# Deploy from your laptop to all environments
shipd deploy myapp-prod v1.2.3
shipd deploy myapp-staging v1.2.3
shipd deploy myapp-demo v1.2.3
```

No logging in. No manual commands. No forgetting steps.

**Server Resource Usage:**

| Tool | What Runs on Server | Typical RAM Usage | $20/mo VPS Usable RAM* |
|------|---------------------|-------------------|----------------------|
| Shipd | Just your containers | 0 MB overhead | ~3.8 GB (95%) |
| Dokku | Platform + Nginx + your containers | ~150-300 MB | ~3.5 GB (87%) |
| CapRover | Platform + Web UI + your containers | ~200-400 MB | ~3.4 GB (85%) |
| Kubernetes | Control plane + agents + your containers | ~500-1000 MB | ~3.0 GB (75%) |

_*Based on 4GB VPS from DigitalOcean/Hetzner_

**Cost Comparison:**

Run 3 small apps on one server:
- **Shipd + $20/mo VPS** = $20/month total
- **Heroku/Render** = ~$21-75/month (3 apps × $7-25 each)
- **Fly.io/Railway** = ~$15-45/month

**Fully utilize your VPS capacity.** No platform overhead means more RAM for your apps. No PaaS lock-in means you can switch providers anytime.

**Plus with Shipd:** You can always SSH in and use standard `docker ps`, `docker logs`, `docker exec` commands. No proprietary platform layer blocking you.

## Installation

Shipd supports two installation methods: **Homebrew** (recommended) and **Manual**.

### Method 1: Homebrew (Recommended)

**Best for:** macOS and Linux users with Homebrew

```bash
# Install from Homebrew tap
brew tap guo/tap
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
git clone https://github.com/guo/shipd.git
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

## GitHub Actions Integration

Use Shipd in CI/CD pipelines for automated deployments:

- 📖 **[GitHub Actions Guide](docs/GITHUB_ACTIONS.md)** - Complete CI/CD integration guide
- 📄 **[Workflow Example](.github/workflows/deploy.yml.example)** - Ready-to-use workflow template

Quick example:
```yaml
- name: Deploy
  run: |
    curl -L https://github.com/guo/shipd/archive/refs/tags/v1.0.3.tar.gz | tar xz
    cd shipd-1.0.3 && sudo ./install.sh
    shipd deploy -y production ${{ github.ref_name }}
```

## Initial Setup

### Option 1: Project-Local Targets (Development)

Best for keeping targets with your project code:

```bash
# 1. (Optional) Create global defaults
cp targets/example/.config .config
vi .config

# 2. Create target directory
mkdir -p targets/myapp-prod

# 3. Create target configuration
cp targets/example/.config targets/myapp-prod/.config
vi targets/myapp-prod/.config

# 4. Create environment file
cp targets/example/.env targets/myapp-prod/.env
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
cp targets/example/.config ~/.shipd/.config
vi ~/.shipd/.config

# 3. Create target directory
mkdir -p ~/.shipd/targets/myapp-prod

# 4. Create target configuration
cp targets/example/.config ~/.shipd/targets/myapp-prod/.config
vi ~/.shipd/targets/myapp-prod/.config

# 5. Create environment file
cp targets/example/.env ~/.shipd/targets/myapp-prod/.env
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
├── targets/
│   ├── example/                 # Example target (template)
│   │   ├── .config              # Example configuration
│   │   ├── .env                 # Example environment
│   │   └── compose.yml          # Example compose file
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
cp targets/example/compose.yml targets/myapp-prod/compose.yml
vi targets/myapp-prod/compose.yml

# Create simplified config (most settings in compose.yml)
echo 'SSH_HOST="user@server.com"' > targets/myapp-prod/.config

# Create environment file
cp targets/example/.env targets/myapp-prod/.env
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

See [targets/example/compose.yml](targets/example/compose.yml) for a complete example and [CLAUDE.md](CLAUDE.md#compose-deployments-multi-container) for detailed documentation.

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
