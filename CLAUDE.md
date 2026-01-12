# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a deployment automation tool for managing containerized applications across multiple remote servers via SSH. It supports both **Docker** and **Podman** as container engines, with automatic engine selection based on deployment type. Supports multiple deployment targets (production, staging, demo, etc.) with target-specific configurations.

### Container Engine Support

- **Docker**: For both single-container and multi-container (compose) deployments
- **Podman**: For single-container deployments only (rootless, more secure)
- **Auto-detection**: Compose files automatically use Docker; single-container defaults to Podman (configurable)

## Key Architecture

### Directory-Based Configuration

The deployment system uses a simple directory-based structure:

1. **Global config** - `.config` file in project root (gitignored, optional)
   - Sets default values for all targets
   - Simple bash variable format: `VARIABLE="value"`
   - Can be overridden by target-specific configs

2. **Target directories** - `targets/{target}/` structure (gitignored)
   - Each target is a directory under `targets/`
   - Target name is the directory name
   - Structure:
     ```
     targets/
     ├── myapp-prod/
     │   ├── .config          # Required: deployment configuration
     │   ├── .env             # Required: environment variables
     │   └── config.json      # Optional: additional files for mapping
     └── myapp-staging/
         ├── .config
         └── .env
     ```

3. **Configuration files**
   - `.config` - Deployment settings (bash variables)
     - `ENGINE` - Container engine: `"podman"` or `"docker"` (default: podman for single-container, docker for compose)
     - `USE_CADDY` - Enable zero-downtime deployment (format: `"true"` or `"false"`, default: false)
       - Requires single-container mode (not compose)
       - Requires Caddy to be set up first via setup-caddy.sh
       - Requires DOMAIN, APP_PORT, HEALTH_CHECK_PATH, HEALTH_CHECK_TIMEOUT settings
     - `CONTAINER_IMAGE` - Docker/OCI image to deploy (without tag, specified at runtime) - **Required for single-container only**
     - `GHCR_USERNAME` / `GHCR_TOKEN` - Registry credentials (empty for public images)
     - `SSH_HOST` - Remote server hostname - **Always required**
     - `CONTAINER_NAME` - Container name (defaults to target directory name)
     - `PORT_MAPPINGS` - Port mappings for direct deployment (format: `"80:3000,443:3001"`) - **Single-container only**
     - `FILE_MAPPINGS` - Volume mounts (format: `"file:path,file2:path2"`) - **Single-container only**
     - Caddy-specific (when USE_CADDY="true"):
       - `DOMAIN` - Domain name for automatic HTTPS
       - `APP_PORT` - Internal application port (default: 3000)
       - `HEALTH_CHECK_PATH` - Health check endpoint (default: "/")
       - `HEALTH_CHECK_TIMEOUT` - Health check timeout in seconds (default: 30)
   - `.env` - Container environment variables (loaded with `--env-file` or `env_file` in compose)
   - Additional files - Any files referenced in FILE_MAPPINGS or compose volumes
   - `docker-compose.yml` or `compose.yml` - **Optional**: Triggers Docker compose deployment (ENGINE setting ignored)

4. **Configuration loading**
   - Global `.config` is sourced first (if exists)
   - Target `.config` is sourced second (overrides global)
   - Simple bash sourcing - no complex INI parsing needed

### Script Architecture

- **deploy-ssh.sh** - Main unified deployment script
  - Auto-detects deployment mode (single vs compose) and engine (Docker vs Podman)
  - Supports zero-downtime deployment via USE_CADDY configuration flag
  - Single entry point for all deployments
  - Delegates to modular implementations in `lib/` directory

- **lib/deploy-podman.sh** - Podman single-container deployment module
  - Standard deployment with brief downtime

- **lib/deploy-docker.sh** - Docker deployment module (single-container + compose)
  - Contains two functions: `deploy_docker_single()` and `deploy_docker_compose()`
  - Handles Docker installation, registry authentication, and deployment
  - **Single-container**: Similar to Podman but uses Docker commands
  - **Compose**: Installs Docker Compose v2, deploys multi-container stacks

- **lib/deploy-caddy.sh** - Caddy zero-downtime deployment module
  - Blue-green deployment strategy with health checks
  - Activated when USE_CADDY="true" in target configuration
  - Single-container only (not compose)

### Deployment Flow

**Single-Container (Podman or Docker):**
1. Validates configuration and SSH connection
2. Uploads target files to remote server
3. Installs container engine if needed
4. Authenticates with registry (if credentials provided)
5. Pulls image
6. Processes port and file mappings
7. Deploys/updates container
8. Verifies deployment

**Multi-Container (Docker Compose):**
1. Validates configuration and SSH connection
2. Uploads target files including compose.yml
3. Installs Docker and Docker Compose v2 if needed
4. Authenticates with registry (if credentials provided)
5. Runs `docker compose down` (stops existing)
6. Runs `docker compose up -d` (starts new stack)
7. Verifies all services running

**Zero-Downtime (Caddy Blue-Green):**
1. Validates configuration and SSH connection
2. Verifies Caddy container is running
3. Uploads target files to remote server
4. Authenticates with registry (if credentials provided)
5. Pulls image
6. Starts new container (blue) on alternate port with health check
7. Switches Caddy traffic to blue container
8. Stops old container and recreates on standard port
9. Switches traffic back and removes blue container
10. Verifies deployment

**Note:** Standard deployment methods have brief downtime. Use USE_CADDY="true" for zero-downtime.

- **setup-caddy.sh** - One-time Caddy reverse proxy setup per target
  - Creates Caddy container per target: `caddy-{target}`
  - Generates Caddyfile with automatic HTTPS (Let's Encrypt)
  - Configures reverse proxy to application container
  - Mounts Caddyfile and certificate storage volumes
  - Exposes ports 80/443 on Caddy container
  - **Usage:** `./setup-caddy.sh <target>` (run once per target)

- **deploy-multi.sh** - Batch deployment wrapper
  - Discovers targets from `targets/` directory structure
  - Requires either `--all` flag or explicit target names (no default behavior)
  - `--all` flag lists all targets and requires confirmation before deploying
  - Supports sequential (default) or parallel (`--parallel`) deployment modes
  - Creates per-target log files: `deploy-{target}.log`
  - Uses background processes for parallel execution with wait/trap for synchronization
  - Tracks success/failure via temporary `.deploy-{target}.result` files

### Deployment Strategy Selection

**Use deploy-ssh.sh for all deployments** (unified command):

**With USE_CADDY="false"** (default - brief downtime):
- Development/staging environments where brief downtime is acceptable
- Quick iterations during development
- Cost-sensitive environments (simpler infrastructure)

**With USE_CADDY="true"** (zero-downtime):
- Production environments requiring zero downtime
- Customer-facing applications with SLA requirements
- Need automatic HTTPS (Let's Encrypt)
- Want health checks before switching traffic
- Need easy rollback capabilities

**Configuration:**
```bash
# In targets/myapp-prod/.config:
USE_CADDY="true"           # Enable zero-downtime (default: false)
DOMAIN="myapp.com"         # For automatic HTTPS
APP_PORT="3000"            # Internal app port
HEALTH_CHECK_PATH="/"      # Health endpoint
HEALTH_CHECK_TIMEOUT="30"  # Timeout in seconds
```

**Image Tag Strategy:**
- **Development:** Use `latest` tag for continuous deployment
- **Staging:** Use specific version tags (e.g., `v1.2.3-rc1`)
- **Production:** Always use specific version tags for reproducibility
- **Rollback:** Deploy previous version tag (e.g., `v1.2.2`)

### Engine Selection Logic

The deployment script automatically selects the appropriate container engine:

| Target Has | .config ENGINE | Actual Engine Used | Deployment Type |
|------------|---------------|-------------------|-----------------|
| compose.yml | podman | **docker** | Multi-container (forced) |
| compose.yml | docker | docker | Multi-container |
| compose.yml | (not set) | **docker** | Multi-container (forced) |
| (no compose) | podman | podman | Single-container |
| (no compose) | docker | docker | Single-container |
| (no compose) | (not set) | **podman** | Single-container (default) |

**Key Rules:**
- Compose files ALWAYS use Docker (Podman doesn't support compose in this implementation)
- Single-container defaults to Podman (more secure, rootless)
- Can override with `ENGINE="docker"` in `.config` for single-container

### Compose Deployments (Multi-Container)

**Auto-detection**: If `compose.yml` or `docker-compose.yml` exists in target directory, deployment automatically uses Docker with Docker Compose v2.

**Requirements**:
- Docker (auto-installed if not present)
- Docker Compose v2 (auto-installed if not present)

**How it works**:
- Uses **Docker + Docker Compose v2** (official, Go-based implementation)
- Simple and reliable (no socket configuration needed)
- 100% compatible with standard docker-compose.yml files

**Target structure**:
```
targets/myapp-prod/
├── .config              # SSH_HOST and optional IMAGE_TAG
├── .env                 # Environment variables
├── compose.yml          # Compose file (triggers compose mode)
└── config/              # Additional files for volumes
    └── app.conf
```

**Example .config** (simplified for compose):
```bash
SSH_HOST="user@server.com"
IMAGE_TAG="latest"       # Optional - passed to compose as ${IMAGE_TAG}
GHCR_USERNAME="user"     # Optional - for private registries
GHCR_TOKEN="ghp_xxx"

# NOT NEEDED for compose (defined in compose.yml):
# CONTAINER_IMAGE, CONTAINER_NAME, PORT_MAPPINGS, FILE_MAPPINGS
```

**Example compose.yml**:
```yaml
services:
  app:
    image: ghcr.io/user/myapp:${IMAGE_TAG:-latest}
    ports:
      - "3000:3000"
    env_file:
      - .env
    volumes:
      - ./config/app.conf:/app/config/app.conf:ro
    depends_on:
      - db
    restart: always

  db:
    image: postgres:15-alpine
    env_file:
      - .env
    volumes:
      - db_data:/var/lib/postgresql/data
    restart: always

volumes:
  db_data:
```

**Deployment**:
```bash
# Deploy with latest tag
./deploy-ssh.sh myapp-prod

# Deploy specific version
./deploy-ssh.sh myapp-prod v1.2.3

# Multi-target deploy (supports both single and compose targets)
./deploy-multi.sh --all
```

**Limitations**:
- ⚠️ **No zero-downtime support**: Compose targets do not support USE_CADDY="true" yet. Use standard deployment (brief downtime during redeployment).
- For multiple registries, pre-authenticate on remote server using `podman login`

**Future**: Zero-downtime compose deployment planned for future release.

## Common Commands

### Initial Setup
```bash
# Optional: Create global defaults
cp .config.example .config
vi .config

# Create a new target
mkdir -p targets/myapp-prod

# Create target configuration
cp .config.example targets/myapp-prod/.config
vi targets/myapp-prod/.config

# Create environment file
cp env.example targets/myapp-prod/.env
vi targets/myapp-prod/.env

# Optional: Add additional config files for volume mapping
echo '{"key":"value"}' > targets/myapp-prod/config.json

# Add FILE_MAPPINGS to .config if needed
echo 'FILE_MAPPINGS="config.json:/app/config.json"' >> targets/myapp-prod/.config
```

### Deployment

#### Quick Start (Brief Downtime - Default)
```bash
# Deploy latest image
./deploy-ssh.sh myapp-prod

# Deploy specific version
./deploy-ssh.sh myapp-prod v1.2.3

# Deploy specific commit
./deploy-ssh.sh myapp-prod sha-abc123

# Deploy to all targets (lists all and asks for confirmation)
./deploy-multi.sh --all

# Deploy to all targets in parallel
./deploy-multi.sh --all --parallel

# List available targets
./deploy-ssh.sh --help
```

#### Zero-Downtime Deployment (Production)
```bash
# 1. First-time setup (run once per target)
./setup-caddy.sh myapp-prod

# 2. Enable Caddy in target configuration
echo 'USE_CADDY="true"' >> targets/myapp-prod/.config
# Also add: DOMAIN, APP_PORT, HEALTH_CHECK_PATH, HEALTH_CHECK_TIMEOUT

# 3. Deploy with zero-downtime (same command!)
./deploy-ssh.sh myapp-prod           # Deploy latest
./deploy-ssh.sh myapp-prod v1.2.3    # Deploy specific version
./deploy-ssh.sh myapp-prod v1.2.2    # Rollback to previous version
```

**Configuration requirements for USE_CADDY:**
```bash
# In targets/myapp-prod/.config:
USE_CADDY="true"           # Enable zero-downtime
DOMAIN="myapp.com"         # For automatic HTTPS
APP_PORT="3000"            # Internal app port
HEALTH_CHECK_PATH="/"      # Health endpoint
HEALTH_CHECK_TIMEOUT="30"  # Timeout in seconds
```

### Remote Container Management
```bash
# View logs
ssh <SSH_HOST> 'podman logs -f <CONTAINER_NAME>'

# Restart container
ssh <SSH_HOST> 'podman restart <CONTAINER_NAME>'

# Stop container
ssh <SSH_HOST> 'podman stop <CONTAINER_NAME>'
```

## Important Implementation Details

### Security
- All sensitive files (`.config`, `targets/` directory) are gitignored
- GHCR authentication uses personal access tokens with package:read permission (when provided)
- Public images can be used by leaving credentials empty in `.config`
- Each target can use different registry credentials for multi-tenant deployments
- SSH keys must be configured for passwordless authentication to remote hosts

### File Organization
- Local: All targets organized under `targets/` directory
- Each target: `targets/{target}/` with `.config` (required), `.env` (required), and optional additional files
- Remote: All target files uploaded to `/var/app/${CONTAINER_NAME}/` on SSH host
- `.env` file automatically used with `--env-file` flag
- Additional files mounted via FILE_MAPPINGS configuration in `.config`
- CONTAINER_NAME defaults to target directory name if not set in `.config`

### Deployment Process
The deployment script always pulls the latest image and recreates the container, ensuring zero-downtime updates by:
1. Stopping existing container gracefully
2. Removing old container
3. Creating new container with `--restart=always` flag
4. Mounting env file and additional volumes as configured
5. Verifying container status with 3-second sleep before checking

### Error Handling
- `set -e` ensures scripts exit on any command failure
- SSH connection is verified before proceeding
- Required variables (SSH_HOST, CONTAINER_IMAGE) are validated before deployment
- Target directory and config files are validated before proceeding
- Container logs are displayed if deployment verification fails
- deploy-multi.sh captures exit codes and generates summary reports
