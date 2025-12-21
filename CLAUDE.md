# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Podman deployment automation tool for managing containerized applications across multiple remote servers via SSH. It supports multiple deployment targets (production, staging, demo, etc.) with target-specific configurations.

## Key Architecture

### Directory-Based Configuration

The deployment system uses a directory-based structure for organizing container files:

1. **targets.config** - Main configuration file (gitignored)
   - Common section: default settings like `CONTAINER_IMAGE`, `GHCR_USERNAME`, `GHCR_TOKEN`
   - Target sections: `[prod1]`, `[staging]`, etc. with SSH_HOST, CONTAINER_NAME, ports
   - Per-target overrides: Each target can override CONTAINER_IMAGE, GHCR_USERNAME, GHCR_TOKEN
   - Public images: Set empty credentials to skip authentication

2. **Container directories** - `targets/` directory (gitignored)
   - All container directories are organized under `targets/` folder
   - Each container has its own directory: `targets/${CONTAINER_NAME}/`
   - Required file: `targets/${CONTAINER_NAME}/.env` - environment variables
   - Optional files: any additional config/data files referenced in FILE_MAPPINGS
   - Local structure: `targets/myapp-prod/.env`, `targets/myapp-prod/config.json`, etc.
   - Remote structure: `/var/app/${CONTAINER_NAME}/.env`, `/var/app/${CONTAINER_NAME}/config.json`, etc.

3. **File Mappings** - Optional volume mounts
   - Configured via `FILE_MAPPINGS="file1:path1,file2:path2"` in targets.config
   - Paths are relative to container directory
   - Parsed and converted to podman `-v` flags

The `parse_config()` function in deploy-podman-ssh.sh handles reading both common and target-specific settings.

### Script Architecture

- **deploy-podman-ssh.sh** - Core deployment script for single target
  - Parses targets.config for specified target
  - Validates local container directory structure (targets/${CONTAINER_NAME}/ and .env file)
  - Uploads entire container directory to remote `/var/app/${CONTAINER_NAME}/`
  - Parses PORT_MAPPINGS (host:container format, comma-separated for multiple ports)
  - Parses FILE_MAPPINGS to build volume mount arguments
  - Executes 9-step deployment process: SSH verification, Podman installation, file upload, GHCR authentication, image pull, port/file mapping processing, container update/creation, verification
  - Handles both new deployments and updates to existing containers
  - Auto-generates remote paths based on container name

- **deploy-multi.sh** - Batch deployment wrapper
  - Requires either `--all` flag or explicit target names (no default behavior)
  - `--all` flag lists all targets and requires confirmation before deploying
  - Supports sequential (default) or parallel (`--parallel`) deployment modes
  - Creates per-target log files: `deploy-{target}.log`
  - Uses background processes for parallel execution with wait/trap for synchronization
  - Tracks success/failure via temporary `.deploy-{target}.result` files

## Common Commands

### Initial Setup
```bash
# Create configuration from examples
cp targets.config.example targets.config

# Create targets directory and container subdirectories
mkdir -p targets/myapp-prod targets/myapp-staging

# Create .env files
cp env.example targets/myapp-prod/.env
cp env.example targets/myapp-staging/.env

# Add additional config files if needed
echo '{"key":"value"}' > targets/myapp-prod/config.json

# Edit files with actual credentials and settings
vi targets.config
vi targets/myapp-prod/.env
```

### Deployment
```bash
# Deploy to specific target
./deploy-podman-ssh.sh deployment1

# Deploy to all targets (lists all and asks for confirmation)
./deploy-multi.sh --all

# Deploy to all targets in parallel
./deploy-multi.sh --all --parallel

# Deploy to specific targets
./deploy-multi.sh deployment1 staging

# Deploy to specific targets in parallel
./deploy-multi.sh --parallel deployment1 staging

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
- All sensitive files (targets.config, targets/ directory) are gitignored
- GHCR authentication uses personal access tokens with package:read permission (when provided)
- Public images can be used by setting empty credentials (GHCR_USERNAME="" GHCR_TOKEN="")
- Each target can use different registry credentials for multi-tenant deployments
- SSH keys must be configured for passwordless authentication to remote hosts

### File Organization
- Local: All containers organized under `targets/` directory
- Each container: `targets/${CONTAINER_NAME}/` with `.env` (required) and optional additional files
- Remote: Files uploaded to `/var/app/${CONTAINER_NAME}/` on SSH host
- Env file automatically used with `--env-file` flag
- Additional files mounted via FILE_MAPPINGS configuration

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
- Container logs are displayed if deployment verification fails
- deploy-all.sh captures exit codes and generates summary reports
