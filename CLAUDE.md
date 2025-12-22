# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Podman deployment automation tool for managing containerized applications across multiple remote servers via SSH. It supports multiple deployment targets (production, staging, demo, etc.) with target-specific configurations.

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
     - `CONTAINER_IMAGE` - Docker/OCI image to deploy
     - `GHCR_USERNAME` / `GHCR_TOKEN` - Registry credentials (empty for public images)
     - `SSH_HOST` - Remote server hostname
     - `CONTAINER_NAME` - Container name (defaults to target directory name)
     - `PORT_MAPPINGS` - Port mappings (format: `"80:3000,443:3001"`)
     - `FILE_MAPPINGS` - Volume mounts (format: `"file:path,file2:path2"`)
   - `.env` - Container environment variables (loaded with `--env-file`)
   - Additional files - Any files referenced in FILE_MAPPINGS

4. **Configuration loading**
   - Global `.config` is sourced first (if exists)
   - Target `.config` is sourced second (overrides global)
   - Simple bash sourcing - no complex INI parsing needed

### Script Architecture

- **deploy-podman-ssh.sh** - Core deployment script for single target
  - Loads global `.config` (optional defaults)
  - Loads target `.config` from `targets/{target}/.config` (overrides global)
  - Validates required variables (SSH_HOST, CONTAINER_IMAGE)
  - Validates target directory structure (`.config` and `.env` files)
  - Uploads entire target directory to remote `/var/app/${CONTAINER_NAME}/`
  - Parses PORT_MAPPINGS (host:container format, comma-separated for multiple ports)
  - Parses FILE_MAPPINGS to build volume mount arguments
  - Executes 9-step deployment process: SSH verification, Podman installation, file upload, GHCR authentication, image pull, port/file mapping processing, container update/creation, verification
  - Handles both new deployments and updates to existing containers
  - Container name defaults to target directory name if not specified in config

- **deploy-multi.sh** - Batch deployment wrapper
  - Discovers targets from `targets/` directory structure
  - Requires either `--all` flag or explicit target names (no default behavior)
  - `--all` flag lists all targets and requires confirmation before deploying
  - Supports sequential (default) or parallel (`--parallel`) deployment modes
  - Creates per-target log files: `deploy-{target}.log`
  - Uses background processes for parallel execution with wait/trap for synchronization
  - Tracks success/failure via temporary `.deploy-{target}.result` files

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
```bash
# Deploy to specific target
./deploy-podman-ssh.sh myapp-prod

# Deploy to all targets (lists all and asks for confirmation)
./deploy-multi.sh --all

# Deploy to all targets in parallel
./deploy-multi.sh --all --parallel

# Deploy to specific targets
./deploy-multi.sh myapp-prod myapp-staging

# Deploy to specific targets in parallel
./deploy-multi.sh --parallel myapp-prod myapp-staging

# List available targets
./deploy-podman-ssh.sh --help
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
