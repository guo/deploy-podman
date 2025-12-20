# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Podman deployment automation tool for managing containerized applications across multiple remote servers via SSH. It supports multiple deployment targets (production, staging, demo, etc.) with target-specific configurations.

## Key Architecture

### Configuration System

The deployment system uses an INI-style configuration format with two layers:

1. **targets.config** - Main configuration file (gitignored)
   - Common section: shared settings like `CONTAINER_IMAGE`, `GHCR_USERNAME`, `GHCR_TOKEN`
   - Target sections: `[deployment1]`, `[staging]`, etc. with SSH_HOST, CONTAINER_NAME, ports, and ENV_FILE path

2. **Env files** - `.env.deployment1`, `.env.staging`, etc. (gitignored)
   - Target-specific environment variables passed to containers
   - Each target references its .env file in targets.config

The `parse_config()` function in deploy-podman-ssh.sh handles reading both common and target-specific settings.

### Script Architecture

- **deploy-podman-ssh.sh** - Core deployment script for single target
  - Parses targets.config for specified target
  - Executes 7-step deployment process: SSH verification, Podman installation, env file upload, GHCR authentication, image pull, container update/creation, verification
  - Handles both new deployments and updates to existing containers

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
cp env.example .env.deployment1
# Edit files with actual credentials and settings
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
- All sensitive files (targets.config, .env.*) are gitignored
- GHCR authentication uses personal access tokens with package:read permission
- SSH keys must be configured for passwordless authentication to remote hosts

### Deployment Process
The deployment script always pulls the latest image and recreates the container, ensuring zero-downtime updates by:
1. Stopping existing container gracefully
2. Removing old container
3. Creating new container with `--restart=always` flag
4. Verifying container status with 3-second sleep before checking

### Error Handling
- `set -e` ensures scripts exit on any command failure
- SSH connection is verified before proceeding
- Container logs are displayed if deployment verification fails
- deploy-all.sh captures exit codes and generates summary reports
