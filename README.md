# Firefox Sync Server (syncstorage-rs)

[![Docker](https://github.com/buildplan/ffs-rs/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/buildplan/ffs-rs/actions/workflows/docker-publish.yml)
![License: MPL-2.0](https://img.shields.io/badge/License-MPL%202.0-blue.svg)

Self-hosted Mozilla Firefox Sync Storage server running on Docker with MariaDB. Docker image with multi-architecture support, automated CI/CD.

**Status:** ✅ Tested and verified working with syncstorage-rs v0.18.3

---

## Table of Contents

- [Features](#features)
- [System Requirements](#system-requirements)
- [Architecture](#architecture)
- [Quick Start](#quick-start-5-minutes)
- [Version Information](#version-information)
- [Pre-Production Checklist](#pre-production-checklist)
- [Deployment Scenarios](#deployment-scenarios)
- [Connecting Firefox Clients](#connecting-firefox-clients)
- [Monitoring & Maintenance](#monitoring--maintenance)
- [Troubleshooting](#troubleshooting)
- [Resources](#resources)

---

## Features

- **Multi-architecture** Docker image (amd64, arm64) - runs on Intel, AMD, and ARM servers
- **MariaDB** database backend with automatic schema migrations
- **Automated CI/CD** with GitHub Actions (build, test, publish to ghcr.io)
- **Security-focused** - runs as non-root user, no exposed secrets in images
- **UTF-8 database** support for international characters
- **Health checks** - built-in readiness probes for container orchestration

---

## System Requirements

### Local Development
- Docker 20.10+ ([install](https://docs.docker.com/engine/install/))
- Docker Compose 2.0+ ([install](https://docs.docker.com/compose/install/))
- ~2GB free disk space (for Docker build cache)
- 4GB RAM minimum (2GB for containers, 2GB for Docker)

### Production Server
- 1GB RAM minimum (2GB recommended)
- 1 CPU core minimum (2+ recommended for scaling)
- 5GB+ disk space (depends on sync data volume)
- Stable internet connection
- Domain name (for Firefox clients to connect)
- Reverse proxy (nginx/Cloudflare) for HTTPS

---

## Architecture

```
┌─────────────────────────────────────────────┐
│         Firefox Client (Desktop/Mobile)     │
└──────────────┬──────────────────────────────┘
               │
        HTTPS (TLS 1.2+)
               │
┌──────────────▼──────────────────────────────┐
│    Reverse Proxy (nginx/Cloudflare/etc)     │
│         (terminates HTTPS, enforces TLS)    │
└──────────────┬──────────────────────────────┘
               │
        HTTP (internal)
               │
┌──────────────▼──────────────────────────────┐
│      Docker Network (internal only)         │
│  ┌────────────────────────────────────────┐ │
│  │  Syncserver Container (Port 8000)      │ │
│  │  - Non-root user (UID 1000)            │ │
│  │  - syncstorage-rs v0.18.3              │ │
│  │  - Rust-based Sync server              │ │
│  └────────────────┬───────────────────────┘ │
│                   │                         │
│  ┌────────────────▼───────────────────────┐ │
│  │  MariaDB Container (Port 3306)         │ │
│  │  - 2 databases: syncstorage_rs, token  │ │
│  │  - Automatic backups support           │ │
│  │  - Volume: ./mariadb_data (persisted)  │ │
│  └────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

---

## File Structure

```
firefox-sync/
├── .github/
│   └── workflows/
│       └── docker-publish.yml        # GitHub Actions CI/CD pipeline
├── app/
│   ├── Dockerfile                    # Multi-stage Docker build
│   └── entrypoint.sh                 # Container startup script
├── data/
│   └── initdb.d/
│       └── init.sql                  # Database initialization
├── mariadb_data/                     # 📁 Docker volume (created at runtime)
├── config/                           # 📁 Syncserver config (created at runtime)
├── docker-compose.yml                # Main configuration
├── example.env                       # Environment template
├── .env                              # 🔐 Your secrets (created by you, never commit)
├── .gitignore                        # Excludes secrets and volumes
└── README.md                         # This file
```

---

## Quick Start (5 minutes)

### 1. Prerequisites

Ensure you have Docker and Docker Compose installed:

```bash
docker --version  # Should be 20.10+
docker compose version  # Should be 2.0+
```

### 2. Clone Repository

```bash
git clone https://github.com/yourusername/firefox-sync.git
cd firefox-sync
```

### 3. Generate Secrets

Generate cryptographically secure random values for production:

```bash
# Generate 64-character master secret
MASTER_SECRET=$(cat /dev/urandom | base32 | head -c64)
echo "SYNC_MASTER_SECRET: $MASTER_SECRET"

# Generate 64-character metrics hash secret
METRICS_SECRET=$(cat /dev/urandom | base32 | head -c64)
echo "METRICS_HASH_SECRET: $METRICS_SECRET"

# Generate 32-character passwords
DB_ROOT_PASS=$(cat /dev/urandom | base32 | head -c32)
echo "MYSQL_ROOT_PASSWORD: $DB_ROOT_PASS"

DB_SYNC_PASS=$(cat /dev/urandom | base32 | head -c32)
echo "MYSQL_PASSWORD: $DB_SYNC_PASS"
```

### 4. Configure Environment

```bash
cp example.env .env
nano .env  # or use your preferred editor
```

**Required configuration:**

```bash
# Your public domain (what Firefox clients will connect to)
SYNC_URL=https://sync.example.com

# Maximum concurrent users (scale based on your hardware)
SYNC_CAPACITY=10

# Paste the generated secrets from step 3
SYNC_MASTER_SECRET=<your-64-char-secret>
METRICS_HASH_SECRET=<your-64-char-secret>
MYSQL_ROOT_PASSWORD=<your-32-char-password>
MYSQL_PASSWORD=<your-32-char-password>

# Log level: error, warn, info, debug, trace
LOGLEVEL=warn
```


### 5. Start Services

```bash
# Build and start containers
docker compose up -d

# Wait 10 seconds for databases to initialize
sleep 10

# View logs
docker compose logs -f syncserver

# Test the server
curl http://localhost:8000/__heartbeat__
```

**Expected response:**
```json
{
  "version":"0.18.3",
  "database":"Ok",
  "status":"Ok",
  "quota":{"enabled":false,"size":0}
}
```

---

## Version Information

| Component | Version | Notes |
|-----------|---------|-------|
| **syncstorage-rs** | v0.18.3 | Sync storage backend |
| **MariaDB** | 11.4+ | Database engine |
| **Docker** | 20.10+ | Container runtime |
| **Docker Compose** | 2.0+ | Orchestration |
| **Tested On** | Debian 13 (amd64), Ubuntu 24.04 (arm64) | Verified platforms |

---

## Environment Variables Reference

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `SYNC_URL` | ✅ Yes | - | Public URL clients connect to (include https://) |
| `SYNC_CAPACITY` | ❌ No | `10` | Max users this server can handle (scale horizontally beyond 100) |
| `SYNC_MASTER_SECRET` | ✅ Yes | - | Encryption key (exactly 64 characters) |
| `METRICS_HASH_SECRET` | ✅ Yes | - | Metrics key (exactly 64 characters) |
| `MYSQL_ROOT_PASSWORD` | ✅ Yes | - | MariaDB root password |
| `MYSQL_PASSWORD` | ✅ Yes | - | Sync user password (same as DB_SYNC_PASS) |
| `LOGLEVEL` | ❌ No | `warn` | Verbosity (error, warn, info, debug, trace) |

---

## Quick Reference

### Essential Commands

```bash
# Start services
docker compose up -d

# View logs
docker compose logs -f syncserver

# Health check
curl http://localhost:8000/__heartbeat__

# Stop services (keep data)
docker compose down

# Stop and remove all data
docker compose down -v

# Restart services
docker compose restart

# View resource usage
docker stats

# Database backup
docker compose exec mariadb mysqldump -u sync -p${MYSQL_PASSWORD} syncstorage_rs > backup.sql
```

### File Locations

| Component | Location |
|-----------|----------|
| Secrets | `.env` (never commit) |
| Config | `./config/local.toml` (generated) |
| Database | `./mariadb_data/` (persisted volume) |
| Logs | `docker compose logs` (Docker) |
| App | `./app/` (Dockerfile, entrypoint.sh) |

---

## Pre-Production Checklist

Before deploying to production, ensure:

- [ ] Domain name registered and DNS configured
- [ ] SSL/TLS certificate obtained (Let's Encrypt recommended)
- [ ] Reverse proxy (nginx) installed and configured
- [ ] Firewall configured (only ports 80/443 exposed)
- [ ] Generated strong, random secrets (64+ characters)
- [ ] Backup plan in place
- [ ] Monitoring/alerting configured
- [ ] `.env` file is in `.gitignore` and never committed
- [ ] Database backups automated
- [ ] Server firewall and updates current
- [ ] Heartbeat endpoint tested and responding
- [ ] HTTPS certificate valid and auto-renewal configured

---

## Deployment Scenarios

### Scenario 1: Local Testing (macOS/Linux/Windows)

```bash
# Development setup
cp example.env .env
nano .env  # Use test values

docker compose build
docker compose up -d
curl http://localhost:8000/__heartbeat__

# Cleanup after testing
docker compose down -v
```

### Scenario 2: Production on VPS (Ubuntu 22.04+)

**Prerequisites:**
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
newgrp docker

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

**Setup:**
```bash
cd /opt
sudo git clone https://github.com/yourusername/firefox-sync.git
cd firefox-sync

# Generate production secrets (use strong, random values)
sudo nano .env  # Fill in SYNC_URL and generate secrets

# Start with persistent storage
sudo docker compose up -d
sudo docker compose logs -f syncserver

# Setup automatic restart on reboot
sudo systemctl enable docker
```

**Reverse Proxy (nginx example):**
```nginx
server {
    listen 443 ssl http2;
    server_name sync.example.com;

    ssl_certificate /etc/letsencrypt/live/sync.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/sync.example.com/privkey.pem;

    # Enforce modern TLS
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name sync.example.com;
    return 301 https://$server_name$request_uri;
}
```

### Scenario 3: Horizontal Scaling (Multiple Servers)

For large deployments, run multiple Syncserver instances:

```yaml
# Server 1: Database (MariaDB only)
# Server 2+: Syncserver instances connecting to Server 1

# Server 1 docker-compose.yml
services:
  mariadb:
    image: linuxserver/mariadb:latest
    ports:
      - "3306:3306"  # Expose to network
    # ... rest of config

# Server 2+ docker-compose.yml
services:
  syncserver:
    image: ghcr.io/youruser/firefox-sync:main
    environment:
      SYNC_SYNCSTORAGE_DATABASE_URL: mysql://sync:${MYSQL_PASSWORD}@server1.local:3306/syncstorage_rs
      SYNC_TOKENSERVER_DATABASE_URL: mysql://sync:${MYSQL_PASSWORD}@server1.local:3306/tokenserver_rs
```

---

## Connecting Firefox Clients

### Desktop (Windows/macOS/Linux)

1. Go to Firefox `about:config`
2. Search for `identity.sync.tokenserver.uri`
3. Set value to `https://sync.example.com/token/1.0/sync/1.5`
4. Restart Firefox
5. Go to **Settings** → **Sync** and sign in

**Verify sync is working:**
- Enable logging: Set `services.sync.log.appender.file.logOnSuccess` to `true`
- Check logs: Visit `about:sync-log`
- Server logs: `docker compose logs -f syncserver`

> **Tip:** Firefox will automatically sync every 5 minutes. You can also trigger manual sync from the main menu or by visiting `about:sync-log` to see detailed sync status.

### Mobile (iOS/Android)

**Android:**
1. Open Firefox
2. Menu → Settings → Sync
3. Enter custom server: `https://sync.example.com`
4. Sign in

**iOS:**
1. Open Firefox
2. Menu (3 dots) → Settings
3. Accounts & Sync → Sync Settings
4. Custom Sync Server: `https://sync.example.com`
5. Sign in

---

## Monitoring & Maintenance

### View Logs

```bash
# Realtime logs
docker compose logs -f

# Last 100 lines
docker compose logs --tail=100

# Syncserver only
docker compose logs -f syncserver

# MariaDB only
docker compose logs -f mariadb

# Save logs to file
docker compose logs > logs-$(date +%Y%m%d).txt
```

### Health Checks

```bash
# Server health endpoint
curl https://sync.example.com/__heartbeat__

# Database connectivity
docker compose exec mariadb mysql -u sync -p${MYSQL_PASSWORD} -e "SELECT 1;"

# Check container status
docker compose ps

# Monitor resource usage
docker stats
```

### Backup Database

**Manual backup:**
```bash
docker compose exec mariadb mysqldump -u sync -p${MYSQL_PASSWORD} --single-transaction --quick syncstorage_rs > backup-syncstorage-$(date +%Y%m%d).sql

docker compose exec mariadb mysqldump -u sync -p${MYSQL_PASSWORD} --single-transaction --quick tokenserver_rs >> backup-syncstorage-$(date +%Y%m%d).sql
```

**Automated daily backup (cron):**
```bash
# Add to crontab with: crontab -e
0 2 * * * cd /opt/firefox-sync && docker compose exec -T mariadb mysqldump -u sync -p${MYSQL_PASSWORD} syncstorage_rs > /backups/sync-$(date +\%Y\%m\%d).sql
```

**Restore from backup:**
```bash
docker compose exec -T mariadb mysql -u sync -p${MYSQL_PASSWORD} syncstorage_rs < backup-syncstorage-20251102.sql
docker compose exec -T mariadb mysql -u sync -p${MYSQL_PASSWORD} tokenserver_rs < backup-tokenserver-20251102.sql
```

---

## Updating

### Check for Updates

The GitHub repository is monitored for upstream changes. To update:

```bash
# Pull latest code
git pull origin main

# Pull latest Docker image
docker compose pull

# Restart with new image
docker compose down
docker compose up -d

# Monitor startup
docker compose logs -f syncserver
```

### Update syncstorage-rs Version

To use a newer syncstorage-rs version:

```bash
# Edit app/Dockerfile
nano app/Dockerfile

# Change the GIT_COMMIT line to the desired commit hash

# Rebuild and test on dev branch
git add app/Dockerfile
git commit -m "chore: update to syncstorage-rs <version>"
git push origin dev

# Test locally
docker compose build --no-cache
docker compose up -d
curl http://localhost:8000/__heartbeat__

# Once verified, merge to main
git checkout main
git merge dev
git push origin main

# GitHub Actions automatically builds and publishes to ghcr.io
```

---

## Troubleshooting

### Container won't start

```bash
# Check error logs
docker compose logs syncserver

# If database error: wait longer
sleep 30
docker compose up -d

# If build error: rebuild
docker compose build --no-cache
docker compose up -d
```

### Database connection refused

```bash
# Verify MariaDB is running
docker compose ps mariadb

# Check credentials in .env
grep MYSQL_ .env

# Test database connectivity
docker compose exec mariadb mysql -u sync -p${MYSQL_PASSWORD} -e "SELECT 1;"

# View database logs
docker compose logs mariadb | tail -50
```

### Port 8000 already in use

```bash
# Find process using port
lsof -i :8000

# Change port in docker-compose.yml
nano docker-compose.yml
# Change: "8000:8000" to "8001:8000"

# Restart
docker compose up -d
```

### Out of disk space

```bash
# Check usage
df -h

# Clean Docker cache
docker system prune -a

# Remove old backups
rm -f /backups/sync-*.sql

# If still full, increase VPS disk or add volume
```

### Firefox sync not working

**Check:**
1. URL in Firefox config is correct: `https://sync.example.com/token/1.0/sync/1.5`
2. Server is accessible: `curl https://sync.example.com/__heartbeat__`
3. HTTPS certificate is valid: `curl -v https://sync.example.com/__heartbeat__`
4. Firewall rules allow traffic
5. Server logs: `docker compose logs syncserver`

---

## Performance Tuning

### For Small Deployments (< 10 users)

```yaml
# docker-compose.yml
environment:
  SYNC_CAPACITY: 10
  
mariadb:
  environment:
    MYSQL_MAX_CONNECTIONS: 100
```

### For Medium Deployments (10-100 users)

```yaml
environment:
  SYNC_CAPACITY: 50

mariadb:
  environment:
    MYSQL_MAX_CONNECTIONS: 500
```

### For Large Deployments (> 100 users)

Run multiple Syncserver instances with a single MariaDB:

```bash
# Use reverse proxy to load balance
# or scale horizontally across servers
```

---

## Security Best Practices

- ✅ **Always use HTTPS** in production with valid SSL/TLS certificate
- ✅ **Rotate secrets** annually or after suspected compromise
- ✅ **Keep system updated**: `sudo apt update && sudo apt upgrade`
- ✅ **Use strong passwords**: 32+ characters, random
- ✅ **Never commit .env file** to git (included in .gitignore)
- ✅ **Enable firewall**: Only expose HTTPS port 443 to public
- ✅ **Monitor logs** regularly for errors
- ✅ **Backup database** regularly and store securely
- ✅ **Use VPN** for administrative access if possible
- ✅ **Enable SELinux/AppArmor** for additional container isolation

---

## CI/CD Pipeline

This repository includes a GitHub Actions workflow that:

1. **On push to `dev`**: Builds image for testing (only on code changes)
2. **On push to `main`**: Builds multi-arch images (amd64, arm64) and publishes to ghcr.io
3. **On git tags** (`v*.*.*`): Creates versioned releases
4. **Manual trigger**: Available via workflow_dispatch
5. **Smart skipping**: Ignores documentation and config file changes

### Manual Build Trigger

```bash
# Push to dev to test
git push origin dev

# Once verified, merge to main
git checkout main
git merge dev
git push origin main

# GitHub Actions automatically builds and pushes to:
# ghcr.io/yourusername/firefox-sync:main
```

---

## Resources

- **syncstorage-rs** - [GitHub Repository](https://github.com/mozilla-services/syncstorage-rs)
- **Firefox Sync** - [Mozilla Documentation](https://support.mozilla.org/en-US/kb/how-do-i-set-up-firefox-sync)
- **Docker** - [Official Documentation](https://docs.docker.com)
- **MariaDB** - [Official Documentation](https://mariadb.com/docs/)

---

## Support

### Getting Help

1. Check the **Troubleshooting** section above
2. Review **Server Logs**: `docker compose logs syncserver`
3. Check **Mozilla Documentation**: https://github.com/mozilla-services/syncstorage-rs

---

## License

This project is licensed under the **MPL-2.0 License** (same as syncstorage-rs).

See [LICENSE](./LICENSE) file for details.

---

**Last Updated:** November 2, 2025  
