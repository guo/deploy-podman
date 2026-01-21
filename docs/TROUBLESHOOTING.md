# Troubleshooting Guide

Common issues and solutions for Shipd deployments.

## Table of Contents

- [SSH Connection Issues](#ssh-connection-issues)
- [Container Engine Issues](#container-engine-issues)
- [Image Pull Issues](#image-pull-issues)
- [Deployment Failures](#deployment-failures)
- [Zero-Downtime Issues](#zero-downtime-issues)
- [Docker Compose Issues](#docker-compose-issues)
- [Configuration Issues](#configuration-issues)
- [Performance Issues](#performance-issues)

## SSH Connection Issues

### Permission denied (publickey)

**Symptom:**
```
Permission denied (publickey)
```

**Solution:**
```bash
# Verify SSH key is added
ssh-add -l

# Add your key if not listed
ssh-add ~/.ssh/id_rsa

# Test SSH connection manually
ssh user@server.com

# Use specific key
ssh -i ~/.ssh/custom_key user@server.com
```

Update `.config` if using custom key:
```bash
SSH_HOST="user@server.com -i ~/.ssh/custom_key"
```

### Connection timeout

**Symptom:**
```
ssh: connect to host server.com port 22: Operation timed out
```

**Solutions:**
- Check firewall allows SSH (port 22)
- Verify server is running and accessible
- Try from different network (check if your IP is blocked)
- Check if server uses non-standard SSH port

For non-standard port:
```bash
SSH_HOST="user@server.com -p 2222"
```

### Host key verification failed

**Symptom:**
```
Host key verification failed
```

**Solution:**
```bash
# Remove old host key
ssh-keygen -R server.com

# Reconnect and accept new key
ssh user@server.com
```

## Container Engine Issues

### Podman not found / installation fails

**Symptom:**
```
podman: command not found
```

**Solution:**
Check if sudo is available:
```bash
ssh user@server.com 'sudo -n true'
```

If sudo requires password, either:
1. Configure passwordless sudo for the user
2. Pre-install Podman on the server
3. Use Docker instead (set `ENGINE="docker"` in `.config`)

### Docker daemon not running

**Symptom:**
```
Cannot connect to the Docker daemon
```

**Solution:**
```bash
# SSH to server and start Docker
ssh user@server.com
sudo systemctl start docker
sudo systemctl enable docker

# Verify Docker is running
sudo docker ps
```

### Permission denied (Docker)

**Symptom:**
```
permission denied while trying to connect to the Docker daemon socket
```

**Solution:**
```bash
# Add user to docker group
ssh user@server.com
sudo usermod -aG docker $USER

# Log out and back in for group changes to take effect
exit
ssh user@server.com

# Verify
docker ps
```

## Image Pull Issues

### Authentication failed

**Symptom:**
```
Error response from daemon: pull access denied
```

**Solutions:**

1. **For private registries**, verify credentials in `.config`:
```bash
GHCR_USERNAME="your-username"
GHCR_TOKEN="ghp_your_token_here"
```

2. **For GitHub Container Registry**, ensure token has `read:packages` permission

3. **Test login manually**:
```bash
ssh user@server.com
echo $TOKEN | podman login ghcr.io -u username --password-stdin
```

### Image not found

**Symptom:**
```
Error: image not found
```

**Solutions:**
- Verify image name is correct in `CONTAINER_IMAGE`
- Check if image exists: `docker pull ghcr.io/org/app:tag`
- For private images, ensure authentication is working
- Check image visibility (public vs private)

### Rate limit exceeded

**Symptom:**
```
You have reached your pull rate limit
```

**Solutions:**
- Wait for rate limit to reset (usually 6 hours)
- Authenticate to increase limits
- Use a different registry (ghcr.io instead of Docker Hub)
- Consider self-hosting a registry

## Deployment Failures

### Container fails to start

**Symptom:**
Container is created but exits immediately.

**Solution:**
```bash
# Check container logs
ssh user@server.com 'podman logs <CONTAINER_NAME>'

# Check container status
ssh user@server.com 'podman ps -a'

# Common issues:
# - Missing required environment variables in .env
# - Port already in use
# - Invalid file mappings
# - Application crashes on startup
```

### Port already in use

**Symptom:**
```
Error: address already in use
```

**Solutions:**
```bash
# Find what's using the port
ssh user@server.com 'sudo lsof -i :80'

# Stop the conflicting service
ssh user@server.com 'sudo systemctl stop nginx'

# Or change your port mapping
PORT_MAPPINGS="8080:3000"  # Use port 8080 instead
```

### File mapping fails

**Symptom:**
```
Error: mounting volume failed
```

**Solutions:**
- Verify file exists in target directory locally
- Check file permissions
- Ensure path in FILE_MAPPINGS is correct
- Use absolute container paths

Example:
```bash
FILE_MAPPINGS="config.json:/app/config/config.json"
```

### Environment variables not loaded

**Symptom:**
Application can't find required environment variables.

**Solution:**
- Verify `.env` file exists in target directory
- Check `.env` file format (no spaces around `=`)
- Ensure file is uploaded (check remote `/var/app/${CONTAINER_NAME}/`)

```bash
# Correct format
DATABASE_URL=postgresql://...
API_KEY=secret123

# Incorrect format
DATABASE_URL = postgresql://...  # No spaces!
```

## Zero-Downtime Issues

### Caddy container not running

**Symptom:**
```
Error: Caddy container is not running
```

**Solution:**
```bash
# Setup Caddy (one-time)
shipd setup-caddy myapp-prod

# Verify Caddy is running
ssh user@server.com 'podman ps | grep caddy'

# Check Caddy logs
ssh user@server.com 'podman logs myapp-prod-caddy'
```

### Health check fails

**Symptom:**
```
Health check failed after X seconds
```

**Solutions:**

1. **Increase timeout** in `.config`:
```bash
HEALTH_CHECK_TIMEOUT="60"  # Increase from 30 to 60 seconds
```

2. **Check health endpoint**:
```bash
# Verify your app responds to health check
curl http://server.com/health

# Make sure HEALTH_CHECK_PATH is correct
HEALTH_CHECK_PATH="/health"  # or "/" if no health endpoint
```

3. **Check app startup time**:
- If app takes long to start, increase timeout
- Check app logs for startup issues

### Traffic not switching

**Symptom:**
Old version still serving traffic after deployment.

**Solution:**
```bash
# Check Caddy configuration
ssh user@server.com 'cat /var/app/myapp-prod-caddy/Caddyfile'

# Reload Caddy manually
ssh user@server.com 'podman exec myapp-prod-caddy caddy reload --config /etc/caddy/Caddyfile'

# Check Caddy logs
ssh user@server.com 'podman logs myapp-prod-caddy'
```

## Docker Compose Issues

### Compose not found

**Symptom:**
```
docker-compose: command not found
```

**Solution:**
Shipd auto-installs Docker Compose v2. If it fails:

```bash
# SSH to server and install manually
ssh user@server.com
sudo mkdir -p /usr/local/lib/docker/cli-plugins
sudo curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Verify
docker compose version
```

### Services not starting

**Symptom:**
```
ERROR: for service_name  Cannot start service
```

**Solutions:**
```bash
# Check compose logs
ssh user@server.com 'cd /var/app/TARGET && docker compose logs'

# Check specific service
ssh user@server.com 'cd /var/app/TARGET && docker compose logs app'

# Verify compose file syntax
docker compose -f targets/myapp-prod/compose.yml config

# Common issues:
# - Missing IMAGE_TAG variable
# - Invalid volume paths
# - Port conflicts
# - Missing dependencies
```

### Environment variables not working

**Symptom:**
Services can't find environment variables.

**Solution:**
Ensure `env_file` is specified in compose.yml:

```yaml
services:
  app:
    image: ghcr.io/org/app:${IMAGE_TAG}
    env_file:
      - .env  # This line is required
```

## Configuration Issues

### Target not found

**Symptom:**
```
Error: Target directory not found
```

**Solutions:**
```bash
# Check target exists
ls -la targets/myapp-prod
# or
ls -la ~/.shipd/targets/myapp-prod

# Create target if missing
mkdir -p targets/myapp-prod
cp targets/example/.config targets/myapp-prod/.config
cp targets/example/.env targets/myapp-prod/.env
```

### Required variables missing

**Symptom:**
```
Error: SSH_HOST is not set
Error: CONTAINER_IMAGE is not set
```

**Solution:**
Edit `targets/myapp-prod/.config` and add required variables:

```bash
# Required for all deployments
SSH_HOST="user@server.com"

# Required for single-container
CONTAINER_IMAGE="ghcr.io/org/app"

# Required for Caddy deployment
USE_CADDY="true"
DOMAIN="example.com"
APP_PORT="3000"
```

### Global config not loading

**Symptom:**
Variables from global `.config` not being used.

**Solution:**
- Check `.config` exists in project root or `~/.shipd/`
- Verify file permissions (must be readable)
- Remember target config overrides global config
- Check for syntax errors in `.config` file

## Performance Issues

### Deployment is slow

**Possible causes and solutions:**

1. **Slow image pull:**
```bash
# Use smaller base images
# Pre-pull images on server
ssh user@server.com 'podman pull ghcr.io/org/app:latest'
```

2. **Slow file upload:**
```bash
# Reduce files in target directory
# Only include necessary files
# Use .gitignore-like approach
```

3. **Network latency:**
```bash
# Use compression for SSH
SSH_HOST="user@server.com -C"
```

### Container uses too much memory

**Solution:**
Add memory limits in compose file or single-container config:

```yaml
# In compose.yml
services:
  app:
    deploy:
      resources:
        limits:
          memory: 512M
```

Or for single container, manually add `--memory` flag by modifying the deployment script.

## Getting More Help

If you're still stuck:

1. **Check logs:**
```bash
# Deployment logs (for deploy-multi)
cat deploy-myapp-prod.log

# Container logs
ssh user@server.com 'podman logs myapp-prod'

# Caddy logs
ssh user@server.com 'podman logs myapp-prod-caddy'
```

2. **Enable debug mode:**
```bash
# Run deployment with bash debug
bash -x shipd.sh deploy myapp-prod
```

3. **Open an issue:**
- Use the bug report template
- Include error messages and logs
- Describe your environment
- Show relevant config (remove sensitive data)

4. **Check existing issues:**
- Search GitHub issues for similar problems
- Read closed issues for solutions

## Common Error Messages

| Error Message | Likely Cause | Solution |
|---------------|--------------|----------|
| `Permission denied (publickey)` | SSH key not configured | Add SSH key to server |
| `podman: command not found` | Podman not installed | Install manually or use Docker |
| `port is already allocated` | Port conflict | Change PORT_MAPPINGS |
| `no such file or directory` | Missing file in FILE_MAPPINGS | Check file exists |
| `Health check failed` | App not starting fast enough | Increase HEALTH_CHECK_TIMEOUT |
| `image not found` | Wrong image name or not authenticated | Check CONTAINER_IMAGE and credentials |
| `Cannot connect to Docker daemon` | Docker not running | Start Docker service |

## Prevention Tips

- Always test SSH connection before deployment
- Verify `.env` file has all required variables
- Test container locally before deploying
- Use health checks in your application
- Monitor container logs after deployment
- Keep Shipd updated (`brew upgrade shipd`)
- Use version tags (not `latest`) for production
