# Using Shipd in GitHub Actions

This guide shows how to use Shipd for automated deployments in GitHub Actions CI/CD pipelines.

## Quick Start

### 1. Configure GitHub Secrets

Add the following secrets to your GitHub repository (Settings → Secrets and variables → Actions):

**Required Secrets:**

```
SSH_PRIVATE_KEY         # SSH private key for server access
SSH_HOST                # SSH host address (e.g., user@example.com)
CONTAINER_IMAGE         # Container image (e.g., ghcr.io/username/app)
CONTAINER_NAME          # Container name (e.g., myapp-prod)
```

**Optional Secrets:**

```
PORT_MAPPINGS           # Port mappings (e.g., 80:3000,443:3001)
GHCR_USERNAME           # GitHub Container Registry username
GHCR_TOKEN              # GitHub Container Registry token
ENV_FILE                # Environment variables (multiline)
```

### 2. Create Workflow

Copy the example file:

```bash
mkdir -p .github/workflows
cp .github/workflows/deploy.yml.example .github/workflows/deploy.yml
```

Or manually create `.github/workflows/deploy.yml`:

```yaml
name: Deploy with Shipd

on:
  push:
    tags:
      - 'v*'

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Install Shipd
        run: |
          curl -L https://github.com/guo/shipd/archive/refs/tags/v1.0.3.tar.gz | tar xz
          cd shipd-1.0.3
          sudo ./install.sh
          shipd --version

      - name: Setup SSH
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.SSH_PRIVATE_KEY }}" > ~/.ssh/deploy_key
          chmod 600 ~/.ssh/deploy_key
          cat >> ~/.ssh/config <<EOF
          Host *
            IdentityFile ~/.ssh/deploy_key
            StrictHostKeyChecking no
          EOF

      - name: Setup target
        run: |
          mkdir -p ~/.shipd/targets/myapp-prod

          cat > ~/.shipd/targets/myapp-prod/.config <<EOF
          CONTAINER_IMAGE="${{ secrets.CONTAINER_IMAGE }}"
          SSH_HOST="${{ secrets.SSH_HOST }}"
          CONTAINER_NAME="${{ secrets.CONTAINER_NAME }}"
          PORT_MAPPINGS="${{ secrets.PORT_MAPPINGS }}"
          GHCR_USERNAME="${{ secrets.GHCR_USERNAME }}"
          GHCR_TOKEN="${{ secrets.GHCR_TOKEN }}"
          EOF

          echo "${{ secrets.ENV_FILE }}" > ~/.shipd/targets/myapp-prod/.env

      - name: Deploy
        run: shipd deploy -y myapp-prod ${{ github.ref_name }}
```

### 3. Commit and Push

```bash
git add .github/workflows/deploy.yml
git commit -m "Add GitHub Actions deployment"
git push
```

### 4. Trigger Deployment

```bash
# Create tag to trigger deployment
git tag v1.0.0
git push origin v1.0.0

# Or use GitHub UI to manually trigger
```

## Use Cases

### Use Case 1: Deploy on Tag Push

```yaml
on:
  push:
    tags:
      - 'v*'
```

**When to use:** Automatically deploy when creating version tags

```bash
git tag v1.2.3
git push origin v1.2.3  # Triggers deployment
```

### Use Case 2: Deploy on Main Branch Push

```yaml
on:
  push:
    branches:
      - main
```

**When to use:** Auto-deploy to staging on every merge to main

```bash
git push origin main  # Auto-deploys
```

### Use Case 3: Manual Deployment Trigger

```yaml
on:
  workflow_dispatch:
    inputs:
      target:
        description: 'Target environment'
        required: true
        type: choice
        options:
          - production
          - staging
      image_tag:
        description: 'Image tag'
        required: false
        default: 'latest'
```

**When to use:** Manually select environment and version from GitHub UI

### Use Case 4: Multi-Environment Deployment

```yaml
on:
  push:
    tags:
      - 'v*'

jobs:
  deploy-staging:
    runs-on: ubuntu-latest
    steps:
      # ... setup
      - run: shipd deploy -y myapp-staging ${{ github.ref_name }}

  deploy-production:
    runs-on: ubuntu-latest
    needs: deploy-staging  # Wait for staging success
    steps:
      # ... setup
      - run: shipd deploy -y myapp-prod ${{ github.ref_name }}
```

**When to use:** Deploy to staging first, then production after success

## Advanced Configuration

### Docker Compose Deployment

```yaml
- name: Setup Compose target
  run: |
    mkdir -p ~/.shipd/targets/myapp-prod

    # Compose mode only needs SSH_HOST
    cat > ~/.shipd/targets/myapp-prod/.config <<EOF
    SSH_HOST="${{ secrets.SSH_HOST }}"
    GHCR_USERNAME="${{ secrets.GHCR_USERNAME }}"
    GHCR_TOKEN="${{ secrets.GHCR_TOKEN }}"
    EOF

    # Copy compose file
    cp docker-compose.yml ~/.shipd/targets/myapp-prod/compose.yml

    # Environment file
    echo "${{ secrets.ENV_FILE }}" > ~/.shipd/targets/myapp-prod/.env
```

### Zero-Downtime Deployment (Caddy)

```yaml
- name: Setup Caddy target
  run: |
    mkdir -p ~/.shipd/targets/myapp-prod

    cat > ~/.shipd/targets/myapp-prod/.config <<EOF
    USE_CADDY="true"
    DOMAIN="${{ secrets.DOMAIN }}"
    APP_PORT="3000"
    HEALTH_CHECK_PATH="/health"
    CONTAINER_IMAGE="${{ secrets.CONTAINER_IMAGE }}"
    SSH_HOST="${{ secrets.SSH_HOST }}"
    GHCR_USERNAME="${{ secrets.GHCR_USERNAME }}"
    GHCR_TOKEN="${{ secrets.GHCR_TOKEN }}"
    EOF

# First-time Caddy setup
- name: Setup Caddy (first time only)
  run: shipd setup-caddy myapp-prod
  if: github.run_number == 1  # Only on first run
```

### Deploy Multiple Targets

```yaml
- name: Deploy to all targets
  run: |
    # Setup all targets
    for target in staging demo production; do
      mkdir -p ~/.shipd/targets/$target
      # ... configure each target
    done

    # Batch deploy
    shipd deploy-multi -y --all
```

### Matrix Strategy

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        target: [staging, demo, production]
    steps:
      - name: Deploy to ${{ matrix.target }}
        run: shipd deploy -y ${{ matrix.target }} ${{ github.ref_name }}
```

## Setting Up SSH Keys

### Generate SSH Key Pair

```bash
# Generate new key pair
ssh-keygen -t ed25519 -C "github-actions" -f ~/.ssh/github_actions_key -N ""

# Copy public key to server
ssh-copy-id -i ~/.ssh/github_actions_key.pub user@server.com

# Copy private key content for GitHub Secrets
cat ~/.ssh/github_actions_key
# Copy entire output, including BEGIN and END lines
```

### Add Private Key to GitHub

1. Go to repository Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Name: `SSH_PRIVATE_KEY`
4. Value: Paste entire private key content (including header/footer)
5. Click "Add secret"

## Configuring Environment Variables

### Single-line Environment Variables

```bash
# In GitHub Secrets
ENV_FILE = "DATABASE_URL=postgres://...\nAPI_KEY=secret123"
```

### Multi-line Environment Variables (Recommended)

```bash
# In GitHub Secrets, paste directly with newlines
DATABASE_URL=postgres://...
API_KEY=secret123
PORT=3000
NODE_ENV=production
```

## Best Practices

### 1. Use Environment Separation

```yaml
jobs:
  deploy-staging:
    environment: staging
    steps:
      - run: shipd deploy -y staging ${{ github.ref_name }}

  deploy-production:
    environment: production
    needs: deploy-staging
    steps:
      - run: shipd deploy -y production ${{ github.ref_name }}
```

### 2. Add Notifications

```yaml
- name: Notify success
  if: success()
  run: |
    curl -X POST ${{ secrets.SLACK_WEBHOOK }} \
      -H 'Content-Type: application/json' \
      -d '{"text":"✅ Deployment succeeded: ${{ github.ref_name }}"}'

- name: Notify failure
  if: failure()
  run: |
    curl -X POST ${{ secrets.SLACK_WEBHOOK }} \
      -H 'Content-Type: application/json' \
      -d '{"text":"❌ Deployment failed: ${{ github.ref_name }}"}'
```

### 3. Cache Shipd Installation

```yaml
- name: Cache Shipd
  uses: actions/cache@v3
  with:
    path: ~/shipd
    key: shipd-v1.0.3

- name: Install Shipd
  run: |
    if [ ! -f ~/shipd/shipd.sh ]; then
      cd ~
      curl -L https://github.com/guo/shipd/archive/refs/tags/v1.0.3.tar.gz | tar xz
      mv shipd-1.0.3 shipd
    fi
    cd ~/shipd && sudo ./install.sh
```

### 4. Verify Deployment

```yaml
- name: Deploy
  run: shipd deploy -y myapp-prod ${{ github.ref_name }}

- name: Verify deployment
  run: |
    # Wait for container to start
    sleep 10

    # Health check
    curl -f https://myapp.com/health || exit 1

    echo "✅ Deployment verified"
```

## Troubleshooting

### SSH Connection Failure

```yaml
- name: Test SSH connection
  run: |
    ssh -i ~/.ssh/deploy_key ${{ secrets.SSH_HOST }} "echo 'SSH connection OK'"
```

### View Detailed Logs

```yaml
- name: Deploy with debug
  run: |
    set -x  # Enable debug output
    shipd deploy -y myapp-prod ${{ github.ref_name }}
```

### Save Deployment Logs

```yaml
- name: Upload logs
  if: failure()
  uses: actions/upload-artifact@v3
  with:
    name: deployment-logs
    path: |
      deploy-*.log
      ~/.shipd/
```

## Complete Example

See complete example: [.github/workflows/deploy.yml.example](../.github/workflows/deploy.yml.example)

## Security Recommendations

1. ✅ Use dedicated SSH keys (not personal keys)
2. ✅ Limit SSH key permissions (deploy only, no code modification)
3. ✅ Use GitHub Environments to protect production
4. ✅ Rotate keys and tokens regularly
5. ✅ Don't print sensitive info in logs
6. ✅ Use principle of least privilege

## More Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Shipd Documentation](../README.md)
- [Release Best Practices](../RELEASING.md)
