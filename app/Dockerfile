# Firefox Sync Server - Builder Stage
FROM rust:latest AS builder

# This specific commit is intentionally hardcoded as newer versions have compatibility issues
ARG GIT_COMMIT=1dc421474df2a4ee973d529534cd0eb7189d58ce

WORKDIR /app

# Install build dependencies with cleanup in same layer
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-virtualenv \
    python3-pip \
    python3-dev \
    default-mysql-client \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Clone and build syncstorage-rs at the known-working commit
RUN git clone https://github.com/mozilla-services/syncstorage-rs ./ \
    && git checkout ${GIT_COMMIT} \
    && cargo install --path ./syncserver --no-default-features --features=syncstorage-db/mysql --locked \
    && cargo install diesel_cli --no-default-features --features mysql \
    && cargo clean \
    && rm -rf /usr/local/cargo/registry

# Setup Python venv and install dependencies
RUN virtualenv venv \
    && /app/venv/bin/pip install --no-cache-dir -r requirements.txt \
    && /app/venv/bin/pip install --no-cache-dir -r tools/tokenserver/requirements.txt \
    && /app/venv/bin/pip install --no-cache-dir pyopenssl==22.1.0 \
    && find /app/venv -type d -name __pycache__ -exec rm -rf {} +

# Runtime Stage - Using Debian 13 Trixie (stable)
FROM debian:trixie-slim AS runtime

# Re-declare ARG so it is defined in this stage for LABEL
ARG GIT_COMMIT=1dc421474df2a4ee973d529534cd0eb7189d58ce

# Install runtime dependencies with cleanup
RUN apt-get update && apt-get install -y --no-install-recommends \
    default-mysql-client \
    python3 \
    ca-certificates \
    libcurl4 \
    curl \
    tini \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN groupadd -r syncserver && useradd -r -g syncserver -u 1000 syncserver

# Create directories with proper ownership
RUN mkdir -p /app /config && chown -R syncserver:syncserver /app /config

WORKDIR /app

# Copy binaries from builder
COPY --from=builder --chown=syncserver:syncserver /usr/local/cargo/bin/syncserver /usr/local/bin/
COPY --from=builder --chown=syncserver:syncserver /usr/local/cargo/bin/diesel /usr/local/bin/

# Copy Python venv (ensure entrypoint.sh activates it)
COPY --from=builder --chown=syncserver:syncserver /app/venv /app/venv

# Copy migration directories
COPY --from=builder --chown=syncserver:syncserver /app/syncstorage-mysql /app/syncstorage-mysql
COPY --from=builder --chown=syncserver:syncserver /app/tokenserver-db /app/tokenserver-db

# Copy entrypoint script
COPY --chmod=755 entrypoint.sh /entrypoint.sh

# Security labels for traceability
LABEL org.opencontainers.image.source="https://github.com/buildplan/ffs-rs"
LABEL org.opencontainers.image.revision="${GIT_COMMIT}"
LABEL maintainer="buildplan"

# Verify binary compatibility
RUN ldd /usr/local/bin/syncserver > /dev/null 2>&1 || (echo "Binary compatibility check failed" && exit 1)

# Switch to non-root user
USER syncserver

# Expose port
EXPOSE 8000

# Use tini for proper signal handling and init
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
