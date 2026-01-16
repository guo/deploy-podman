# Shipd vs Alternatives

This guide helps you understand when to use Shipd versus other deployment tools.

## Shipd's Core Philosophy: Agentless & Remote

**The key difference:** Shipd is agentless. Your servers stay clean.

| Approach | Tools | What's on Server | Deploy From |
|----------|-------|------------------|-------------|
| **Agentless** | Shipd, Ansible | Just Docker/Podman | Your laptop, CI/CD |
| **Platform** | Dokku, CapRover, Coolify | Platform software + Docker | Git push, Web UI |
| **Cluster** | Kubernetes | Control plane + agents | kubectl anywhere |
| **PaaS** | Heroku, Render | Proprietary platform | Git push, API |

**With Shipd:**
- Install shipd on your laptop (not on servers)
- Servers just run Docker/Podman - nothing else
- Deploy remotely via SSH from anywhere
- No logging into servers needed
- No platform software to maintain
- Servers stay vanilla and debuggable

This agentless approach means:
- ✅ **Minimal resource usage** - no platform daemons consuming RAM/CPU
- ✅ **Manually maintainable** - SSH in and use standard docker/podman commands anytime
- ✅ Less to maintain (no platform updates)
- ✅ Less attack surface (only SSH + Docker)
- ✅ Easier debugging (standard Docker commands)
- ✅ Deploy from anywhere (laptop, CI/CD, another server)
- ✅ No vendor lock-in (just SSH and containers)
- ✅ Never locked out of your own server (no proprietary layer)

## Shipd vs Kubernetes

| Feature | Shipd | Kubernetes |
|---------|-------|------------|
| **Setup time** | 5 minutes | Days to weeks |
| **Learning curve** | Minimal (SSH + containers) | Steep (weeks to months) |
| **Infrastructure** | Any Linux server with SSH | Cluster required |
| **Best for** | 5-50 services | 50+ services, large scale |
| **Cost** | Free, runs on any server | Requires cluster management |
| **Complexity** | Simple bash config | Complex YAML manifests |
| **Zero-downtime** | Yes (via Caddy) | Yes (native) |
| **Auto-scaling** | No | Yes |
| **Service discovery** | Manual/Caddy | Built-in |

**Use Shipd when:**
- You have < 50 services
- You want simple SSH-based deployments
- You don't need auto-scaling
- Your team is small (< 20 developers)
- You want to avoid cluster management

**Use Kubernetes when:**
- You need auto-scaling
- You have > 50 services
- You need advanced networking features
- You have dedicated DevOps team
- You're already comfortable with K8s

## Shipd vs Docker/Podman CLI

| Feature | Shipd | Docker/Podman CLI |
|---------|-------|-------------------|
| **Multi-environment** | Built-in | Manual scripts |
| **Zero-downtime** | Yes (Caddy mode) | Manual setup required |
| **Version control** | Built-in (tag management) | Manual |
| **Rollback** | One command | Manual process |
| **Config management** | Target-based | Manual |
| **Remote deployment** | Built-in (SSH) | Manual SSH + commands |
| **Registry auth** | Automated | Manual login |

**Use Shipd when:**
- You deploy to multiple environments
- You want automated workflows
- You need zero-downtime deployments
- You want simplified config management

**Use Docker/Podman CLI when:**
- Single server, single environment
- You prefer manual control
- Very simple deployments
- Custom workflow requirements

## Shipd vs Ansible/Terraform

| Feature | Shipd | Ansible | Terraform |
|---------|-------|---------|-----------|
| **Purpose** | Container deployment | General automation | Infrastructure provisioning |
| **Learning curve** | Low | Medium | Medium-High |
| **Container focus** | Yes | No (general purpose) | No (infrastructure) |
| **Config format** | Bash variables | YAML playbooks | HCL |
| **Deployment speed** | Fast | Medium | Slow (state checks) |
| **Zero-downtime** | Built-in | Custom playbooks | Via external tools |
| **Best use case** | Deploy containers | Configure systems | Provision infrastructure |

**Use Shipd when:**
- Focused on container deployments
- Want simple, fast deployments
- Don't need system-level automation

**Use Ansible when:**
- Need system configuration management
- Need to automate non-container tasks
- Complex multi-step workflows

**Use Terraform when:**
- Provisioning cloud infrastructure
- Managing infrastructure as code
- Need state management

## Shipd vs Heroku/Render/Fly.io

| Feature | Shipd | Platform-as-a-Service |
|---------|-------|----------------------|
| **Cost** | Free + server costs (~$20/mo VPS) | $$ monthly per-app fees |
| **Cost for 3 apps** | $20/month (one VPS) | $21-75/month (3 × $7-25) |
| **Server control** | Full control | Limited/None |
| **Resource efficiency** | 100% VPS capacity for your apps | Shared/metered resources |
| **Server choice** | Any Linux server | Platform-specific |
| **Vendor lock-in** | None | High |
| **Setup** | Manual server setup | Instant |
| **Auto-scaling** | No | Yes (usually) |
| **Pricing model** | Pay for servers only | Pay per app/service |
| **Customization** | Complete freedom | Limited |
| **Migration** | Easy (standard containers) | Difficult (platform-specific) |

**Use Shipd when:**
- You want full server control
- **You want to minimize costs** (10x+ cheaper for multiple apps)
- **You want to fully utilize VPS capacity** (no platform overhead)
- You have specific infrastructure needs
- You want to avoid vendor lock-in
- You want easy migration between providers
- You run multiple small apps (cost efficiency)

**Use PaaS when:**
- You want zero infrastructure management
- You prioritize speed over cost
- You need auto-scaling
- You're building an MVP quickly
- Cost is not a primary concern

## Shipd vs Docker Compose

| Feature | Shipd | Docker Compose |
|---------|-------|----------------|
| **Multi-server** | Yes (SSH to each) | No (single host) |
| **Multi-environment** | Built-in | Manual |
| **Zero-downtime** | Yes (Caddy mode) | No |
| **Version control** | Tag management | Manual |
| **Remote deployment** | Built-in | Manual SSH |
| **Compose support** | Yes | Yes |

**Use Shipd when:**
- Deploying to multiple servers
- Need zero-downtime
- Want environment management
- Need automated remote deployment

**Use Docker Compose directly when:**
- Single server only
- Local development
- Don't need zero-downtime
- Simple manual workflows

## Shipd vs Dokku/CapRover

| Feature | Shipd | Dokku/CapRover |
|---------|-------|----------------|
| **Setup** | No server setup needed | Requires full platform install |
| **Architecture** | Agentless (pure SSH) | Agent/platform on server |
| **Server state** | Clean (just Docker/Podman) | Platform software installed |
| **Resource overhead** | None (no daemons) | Platform daemons + web UI |
| **Manual access** | Full - standard Docker commands | Limited by platform layer |
| **Git-based** | No | Yes |
| **UI** | CLI only | CLI + Web UI (CapRover) |
| **Simplicity** | Very simple | Simple |
| **Dependencies** | None (SSH only) | Platform installation required |
| **Maintenance** | Zero (no platform to maintain) | Platform updates needed |
| **Debugging** | Standard Docker/Podman | Platform-specific |
| **Remote deploy** | From anywhere (laptop, CI/CD) | Need git push or SSH to platform |

**Use Shipd when:**
- You don't want platform software on servers
- You prefer agentless deployment
- You want maximum simplicity and cleanliness
- **You want to minimize server resource usage** (no platform overhead)
- **You need to manually maintain servers when necessary** (standard Docker commands)
- You deploy from laptop or CI/CD
- You already have servers running
- You want to keep servers vanilla
- You value easy debugging
- You don't want to be locked into a platform abstraction

**Use Dokku/CapRover when:**
- You want Heroku-like git push workflow
- You want a web UI for management
- You're okay with platform installation and maintenance
- You want more built-in services (databases, etc.)
- You prefer git-based deployment

## Decision Matrix

Choose Shipd if you answer **yes** to most of these:

- [ ] You deploy containerized applications
- [ ] You have SSH access to your servers
- [ ] You manage 5-50 services
- [ ] You want simple configuration
- [ ] You prefer agentless tools (no platform to install)
- [ ] You want to keep servers vanilla/clean
- [ ] **You want to fully utilize VPS capacity** (no platform overhead)
- [ ] **You want to minimize costs** (vs PaaS per-app pricing)
- [ ] You deploy remotely from your laptop or CI/CD
- [ ] You want to avoid vendor lock-in
- [ ] You don't need auto-scaling
- [ ] You want zero-downtime deployments
- [ ] You deploy to multiple environments
- [ ] Kubernetes feels like overkill

## Migration Guides

### From PaaS (Heroku/Render/Fly.io)

**Cost savings example:**

Before (Heroku):
- 3 web apps: 3 × $25/mo = $75/month
- 1 worker: $25/month
- 1 Postgres: $9/month
- **Total: $109/month**

After (Shipd + VPS):
- 1 VPS (4GB): $20/month (DigitalOcean/Hetzner)
- Shipd: Free
- Run all 3 apps + worker + Postgres containers
- **Total: $20/month** → **Save $89/month ($1,068/year)**

**Migration steps:**
1. Get a VPS (DigitalOcean, Hetzner, AWS EC2)
2. Install shipd on your laptop: `brew install shipd`
3. Create target configs for each app
4. Deploy: `shipd deploy myapp-prod`
5. Cancel PaaS subscriptions

**Bonus:** Full control, no vendor lock-in, more resources for your apps.

### From Docker Compose

```bash
# Before: SSH + manual commands
ssh server "cd /app && docker-compose pull && docker-compose up -d"

# After: Shipd
shipd deploy myapp-prod
```

### From Kubernetes

Shipd works great for services that don't need K8s features:

- Stateless web apps
- API services
- Background workers
- Databases (with persistent volumes)

Keep Kubernetes for:
- Services that auto-scale heavily
- Complex service mesh requirements
- Multi-region active-active

### From Manual Docker

```bash
# Before: Manual deployment
ssh server "docker pull ghcr.io/org/app:latest"
ssh server "docker stop myapp || true"
ssh server "docker rm myapp || true"
ssh server "docker run -d --name myapp -p 80:3000 ghcr.io/org/app:latest"

# After: Shipd (one command)
shipd deploy myapp-prod
```

## Still Not Sure?

Ask these questions:

1. **How many services?** < 50 → Shipd, > 50 → Consider K8s
2. **Team size?** < 20 → Shipd works great
3. **Need auto-scaling?** Yes → K8s, No → Shipd is fine
4. **Budget for PaaS?** No → Shipd, Yes → PaaS is easier
5. **Have K8s experience?** No → Start with Shipd

**Pro tip:** You can use Shipd now and migrate to Kubernetes later if needed. Shipd doesn't lock you in.
