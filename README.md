# Firefox Sync Server (syncstorage-rs)

[![Docker](https://github.com/buildplan/ffs-rs/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/buildplan/ffs-rs/actions/workflows/docker-publish.yml)
[![License: MPL-2.0](https://img.shields.io/badge/License-MPL%202.0-blue.svg)](https://www.mozilla.org/en-US/MPL/2.0/)
[![Image](https://img.shields.io/badge/ghcr.io-buildplan%2Fffs--rs%3Amain-blue)](https://github.com/buildplan/ffs-rs/pkgs/container/ffs-rs)

Self-hosted Mozilla Firefox Sync Storage server running on Docker with MariaDB.

Image: ghcr.io/buildplan/ffs-rs:main

Status: Tested and verified working with syncstorage-rs v0.18.3

-----

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
- [Updating](#updating)
- [Build from Source](#build-from-source)
- [CI/CD Pipeline](#cicd-pipeline)
- [Resources](#resources)
- [License](#license)

-----

## Features

- **Multi-architecture image** (amd64, arm64) via GitHub Actions
- **MariaDB backend**
- **Security-focused**: non-root user, no secrets baked into image
- Health checks and readiness probes
- Reverse proxy guidance
- Optional local build path

-----

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
- Domain name + HTTPS reverse proxy (nginx/Pangolin/Cloudflare)

-----

## Architecture

```text
┌─────────────────────────────────────────────┐
│         Firefox Client (Desktop/Mobile)     │
└───────────────────┬─────────────────────────┘
                    │
             HTTPS (TLS 1.2+)
                    │
┌───────────────────▼─────────────────────────┐
│Reverse Proxy (nginx/Pangolin/Cloudflare/etc)│
│         (terminates HTTPS, enforces TLS)    │
└───────────────────┬─────────────────────────┘
                    │
              HTTP (internal)
                    │
┌───────────────────▼─────────────────────────┐
│      Docker Network (internal only)         │
│  ┌────────────────────────────────────────┐ │
│  │  Syncserver Container (Port 8000)      │ │
│  │  - Non-root user (UID 1000)            │ │
│  │  - syncstorage-rs v0.18.3              │ │
│  │  - Rust-based Sync server              │ │
│  └────────────────┬───────────────────────┘ │
│                   │                         │
│  ┌────────────────▼───────────────────────┐ │
│  │  MariaDB Container (Port 3306)         │ │
│  │  - 2 databases: syncstorage_rs, token  │ │
│  │  - Persisted volume                    │ │
│  └────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

-----

## Quick Start (5 minutes)

### 1. Prerequisites

```bash
docker --version
docker compose version
```

### 2. Clone repository (optional)

```bash
git clone https://github.com/buildplan/ffs-rs.git
cd ffs-rs
```

### 3. Review `init.sql`

This SQL script is located at `./data/initdb.d/init.sql` and is executed once by the MariaDB container to create the two required databases and grant permissions to the `sync` user defined in your `.env` file.

```sql
CREATE DATABASE IF NOT EXISTS syncstorage_rs CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS tokenserver_rs CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

GRANT ALL PRIVILEGES ON syncstorage_rs.* TO 'sync'@'%';
GRANT ALL PRIVILEGES ON tokenserver_rs.* TO 'sync'@'%';
FLUSH PRIVILEGES;
```

### 4. Generate secrets

```bash
# 64-char master secret
MASTER_SECRET=$(cat /dev/urandom | base32 | head -c64)
echo "SYNC_MASTER_SECRET: $MASTER_SECRET"

# 64-char metrics hash secret
METRICS_SECRET=$(cat /dev/urandom | base32 | head -c64)
echo "METRICS_HASH_SECRET: $METRICS_SECRET"

# 32-char passwords
DB_ROOT_PASS=$(cat /dev/urandom | base32 | head -c32)
echo "MYSQL_ROOT_PASSWORD: $DB_ROOT_PASS"

DB_SYNC_PASS=$(cat /dev/urandom | base32 | head -c32)
echo "MYSQL_PASSWORD: $DB_SYNC_PASS"
```

### 5. Configure environment

Copy the example file and edit it to include your secrets and public URL:

```bash
cp example.env .env
nano .env
```

**`example.env` content:**

```bash
# Required:
SYNC_URL=https://sync.example.com    # The public-facing HTTPS URL
SYNC_CAPACITY=10                     # Node capacity (concurrent assignments)
SYNC_MASTER_SECRET=<your-64-char-secret>
METRICS_HASH_SECRET=<your-64-char-secret>
MYSQL_ROOT_PASSWORD=<your-32-char-password>
MYSQL_PASSWORD=<your-32-char-password>
LOGLEVEL=warn                        # Set to 'info' or 'debug' for more verbosity

# Optional:
TZ=UTC                               # Timezone for the DB container
PUID=1001                            # User ID for MariaDB volume permissions
PGID=1001                            # Group ID for MariaDB volume permissions
```

> **Security Note:** Never commit `.env` (contains secrets). It is already in `.gitignore`.

### 6. Create `docker-compose.yml` and `init.sql`

Create a file named `docker-compose.yml` in the root directory.

> **Note:** The `./data/initdb.d/init.sql` volume ensures both the **`syncstorage_rs`** and **`tokenserver_rs`** databases are created, and user grants are set, upon first run of the MariaDB container. The actual application tables and schema migrations are then automatically applied by the `syncserver` when it starts up.

```yaml
# Minimal services using the pre-built image
# Save as docker-compose.yml
services:
  firefox-mariadb:
    container_name: firefox-mariadb
    image: linuxserver/mariadb:11.4.8
    restart: unless-stopped
    environment:
      # PUID/PGID and TZ are set in .env
      PUID: ${PUID}
      PGID: ${PGID}
      TZ: ${TZ}
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_USER: sync
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
      MYSQL_DATABASE: syncstorage_rs
    volumes:
      - ./data/config:/config
      - ./data/initdb.d/init.sql:/config/initdb.d/init.sql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 5

  firefox-syncserver:
    container_name: firefox-syncserver
    image: ghcr.io/buildplan/ffs-rs:main
    restart: unless-stopped
    depends_on:
      # Ensures the sync server waits for the DB to be ready
      firefox-mariadb:
        condition: service_healthy
    environment:
      LOGLEVEL: ${LOGLEVEL}
      SYNC_URL: ${SYNC_URL}
      SYNC_CAPACITY: ${SYNC_CAPACITY}
      SYNC_MASTER_SECRET: ${SYNC_MASTER_SECRET}
      METRICS_HASH_SECRET: ${METRICS_HASH_SECRET}
      # IMPORTANT: Service name (firefox-mariadb) must match the DB host
      SYNC_SYNCSTORAGE_DATABASE_URL: mysql://sync:${MYSQL_PASSWORD}@firefox-mariadb:3306/syncstorage_rs
      SYNC_TOKENSERVER_DATABASE_URL: mysql://sync:${MYSQL_PASSWORD}@firefox-mariadb:3306/tokenserver_rs
    # Bind to localhost to prevent external exposure. Adjust '127.0.0.1:8010' if needed.
    ports:
      - "127.0.0.1:8010:8000" 
    volumes:
      - ./config:/config
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:8000/__heartbeat__ || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 15s
```

### 7. Start services (pre-built image)

```bash
docker compose up -d
sleep 10
curl http://localhost:8010/__heartbeat__  # Note the 8010 port bind
docker compose logs -f firefox-syncserver
```

Expected heartbeat:

```json
{
  "version":"0.18.3",
  "database":"Ok",
  "status":"Ok",
  "quota":{"enabled":false,"size":0}
}
```

### 8. Update to latest image

```bash
docker compose pull
docker compose up -d --force-recreate
```

-----

## Version Information

| Component | Version | Notes |
|----------|---------|-------|
| syncstorage-rs | v0.18.3 | Backend |
| MariaDB | 11.4+ | DB engine |
| Docker | 20.10+ | Runtime |
| Docker Compose | 2.0+ | Orchestration |
| Tested On | Debian 13 (amd64), Ubuntu 24.04 (arm64) | Verified |

-----

## Pre-Production Checklist

- [ ] DNS and HTTPS configured
- [ ] Reverse proxy in place (nginx/Pangolin/Cloudflare)
- [ ] Firewall only exposes 443
- [ ] Strong, random secrets generated
- [ ] Backups and monitoring in place
- [ ] `.env` not committed
- [ ] Heartbeat returns Ok

-----

## Deployment Scenarios

### Scenario 1: Local testing

```bash
cp example.env .env
nano .env
docker compose up -d
curl http://localhost:8010/__heartbeat__
docker compose down -v
```

### Scenario 2: Production on VPS

```bash
sudo apt update && sudo apt upgrade -y
curl -fsSL https://get.docker.com -o get-docker.sh && sudo sh get-docker.sh
sudo usermod -aG docker $USER && newgrp docker

sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" 
-o /usr/local/bin/docker-compose && sudo chmod +x /usr/local/bin/docker-compose

cd /opt && sudo git clone https://github.com/buildplan/ffs-rs.git
cd ffs-rs && sudo nano .env

sudo docker compose up -d
sudo docker compose logs -f syncserver
sudo systemctl enable docker
```

#### nginx reverse proxy

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

#### Pangolin (alternative to nginx)

Assuming Newt is running on the same host and you can either put this project on same docker network or run Newt container in host mode. ([Pangolin Docs](https://docs.pangolin.net/manage/resources/targets))

Create a public Resource for sync.example.com and add one Target pointing to your local syncserver. Do not enable Pangolin authentication and do not use path rewrites.

- Resource
  - Hostname: sync.example.com
  - TLS/SSL: enabled (terminates HTTPS at Pangolin)
  - Authentication: disabled

- Target
  - Scheme: `http`
  - Address: `127.0.0.1`
  - Port: `8010`
  - Health check:
    - Method: `HTTP`
    - IP/Host: `127.0.0.1`
    - Port: `8010`
    - Path: `/__heartbeat__`
    - Custom headers: optional

Notes:

- Keep path rewrites disabled to preserve Firefox Sync routes like /token/1.0/sync/1.5 and the storage endpoints.
- If you add multiple syncserver instances later, create additional Targets with the same Match prefix “/” to enable round‑robin on the same node.
- If your compose binds a different host/port, adjust Address/Port here accordingly.

-----

## Connecting Firefox Clients

### Desktop (Windows/macOS/Linux)

1. Open Firefox `about:config`
2. Set `identity.sync.tokenserver.uri` to `https://sync.example.com/token/1.0/sync/1.5`
3. Restart Firefox
4. Settings → Sync → sign in

Verify:

- Enable logging: `services.sync.log.appender.file.logOnSuccess = true`
- Check `about:sync-log`
- Server logs: `docker compose logs -f syncserver`

### Mobile (Android)

1. Menu → Settings → About Firefox
2. Tap the Firefox logo 5 times to enable Debug menu
3. Back in Settings, open Sync Debug
4. Enable “Use Custom Sync Server”
5. Set to `https://sync.example.com/token/1.0/sync/1.5`
6. Sign in

Note: On iOS, custom server support via debug menu may be limited by version.

-----

## Monitoring & Maintenance

Logs:

```bash
docker compose logs -f
docker compose logs --tail=100
docker compose logs -f syncserver
docker compose logs -f mariadb
docker compose logs > logs-$(date +%Y%m%d).txt
```

Health:

```bash
curl https://sync.example.com/__heartbeat__
docker compose exec mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e "SELECT 1;"
docker compose ps
docker stats
```

Backups:

```bash
docker compose exec mariadb mysqldump -u sync -p"${MYSQL_PASSWORD}" --single-transaction --quick syncstorage_rs > backup-syncstorage-$(date +%Y%m%d).sql
docker compose exec mariadb mysqldump -u sync -p"${MYSQL_PASSWORD}" --single-transaction --quick tokenserver_rs >> backup-syncstorage-$(date +%Y%m%d).sql
```

Cron:

```cron
0 2 * * * cd /opt/ffs-rs && docker compose exec -T mariadb mysqldump -u sync -p${MYSQL_PASSWORD} syncstorage_rs > /backups/sync-$(date +%Y%m%d).sql
```

Restore:

```bash
docker compose exec -T mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" syncstorage_rs < backup-syncstorage-20251102.sql
docker compose exec -T mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" tokenserver_rs < backup-tokenserver-20251102.sql
```

**Advanced Database Lookups:**

The queries below are a few examples. For a full, categorized set of useful commands to query the database, refer to the separate file:

> [`useful-lookups.md`](./useful-lookups.md)

-----

## Troubleshooting

- Container won’t start

```bash
docker compose logs syncserver
sleep 30 && docker compose up -d
docker compose build --no-cache && docker compose up -d
```

- DB connection refused

```bash
docker compose ps mariadb
grep MYSQL_ .env
docker compose exec mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e "SELECT 1;"
docker compose logs mariadb | tail -50
```

- Port 8010 in use (if you used the default `docker-compose.yml`)

```bash
lsof -i :8010

# change to "8011:8000" in compose and restart
```

- Firefox not syncing

1. Verify tokenserver URL in Firefox: `https://sync.example.com/token/1.0/sync/1.5`
2. Check heartbeat
3. Confirm HTTPS cert
4. Firewall allows 443
5. Check server logs

- Revert to default Mozilla tokenserver

```text
about:config → identity.sync.tokenserver.uri = https://token.services.mozilla.com/1.0/sync/1.5
Sign out, restart, sign in
```

-----

## Updating

### Image tags

- `ghcr.io/buildplan/ffs-rs:main` — rolling from main (latest successful CI build)

Update:

```bash
docker compose pull
docker compose up -d
```

-----

## Build from Source

If you prefer building locally:

```bash
git clone https://github.com/buildplan/ffs-rs.git
cd ffs-rs

# Option A: use compose with build:

# syncserver:

# build:

# context: ./app

# dockerfile: Dockerfile

# Option B: manual build and reference:

docker build ./app -t ffs-rs:local

# Then in docker-compose.yml:

# image: ffs-rs:local

docker compose up -d
```

-----

## CI/CD Pipeline

- On push to main: build and publish multi-arch image to `ghcr.io/buildplan/ffs-rs`
- Manual trigger via workflow_dispatch

-----

## Useful DB Lookups

- Collection dictionary

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e 
"SELECT id AS collection_id, name FROM syncstorage_rs.collections ORDER BY id;"
```

- BSO counts (names)

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e 
"SELECT c.name AS collection, COUNT(*) AS bso_count
FROM syncstorage_rs.bso b
JOIN syncstorage_rs.collections c ON c.id = b.collection
GROUP BY c.name ORDER BY bso_count DESC;"
```

- Recent BSOs (human time)

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e 
"SELECT b.id, c.name AS collection,
FROM_UNIXTIME(b.modified/1000) AS modified_ts, b.modified AS modified_ms
FROM syncstorage_rs.bso b
JOIN syncstorage_rs.collections c ON c.id = b.collection
ORDER BY b.modified DESC LIMIT 50;"
```

- Per-user last_modified (human time)

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e 
"SELECT uc.userid, c.name AS collection,
FROM_UNIXTIME(uc.last_modified/1000) AS modified_ts, uc.last_modified AS modified_ms,
uc.count AS bso_count, uc.total_bytes
FROM syncstorage_rs.user_collections uc
JOIN syncstorage_rs.collections c ON c.id = uc.collection
ORDER BY uc.last_modified DESC LIMIT 50;"
```

- Batch uploads note: These tables may be empty unless clients used server-side batching.

Heredoc tip (disable TTY):

```bash
docker compose exec -T firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" <<'SQL'
USE syncstorage_rs;
SELECT c.name, COUNT(*) AS bso_count
FROM bso b JOIN collections c ON c.id = b.collection
GROUP BY c.name ORDER BY bso_count DESC;
SQL
```

-----

## Resources

- syncstorage-rs — [https://github.com/mozilla-services/syncstorage-rs](https://github.com/mozilla-services/syncstorage-rs)
- Mozilla Docs - [https://mozilla-services.readthedocs.io/en/latest/howtos/run-sync-1.5.html](https://mozilla-services.readthedocs.io/en/latest/howtos/run-sync-1.5.html)
- Firefox Sync — [https://support.mozilla.org/en-US/kb/how-do-i-set-up-firefox-sync](https://support.mozilla.org/en-US/kb/how-do-i-set-up-firefox-sync)
- Docker — [https://docs.docker.com](https://docs.docker.com)
- MariaDB — [https://mariadb.com/docs/](https://mariadb.com/docs/)
- Nginx - [https://nginx.org/en/docs/beginners_guide.html](https://nginx.org/en/docs/beginners_guide.html)
- Pangolin - [https://docs.pangolin.net/manage/resources/targets](https://docs.pangolin.net/manage/resources/targets)
- Guides
  - [https://blog.diego.dev/posts/firefox-sync-server/](https://blog.diego.dev/posts/firefox-sync-server/)
  - [https://www.kyzer.me.uk/syncserver/](https://www.kyzer.me.uk/syncserver/)
  - [https://thesmarthomejourney.com/2023/03/18/self-hosting-firefox-sync/](https://thesmarthomejourney.com/2023/03/18/self-hosting-firefox-sync/)
  - [https://news.ycombinator.com/item?id=43214294](https://news.ycombinator.com/item?id=43214294)

-----

## License

This project is licensed under the MPL-2.0 License.

See [LICENSE](./LICENSE) for details.
