# Stage 1: Builder
FROM rust:latest AS builder

ARG GIT_COMMIT=1dc421474df2a4ee973d529534cd0eb7189d58ce

WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-virtualenv \
    python3-pip \
    python3-dev \
    default-mysql-client \
    && rm -rf /var/lib/apt/lists/*

# Clone syncstorage-rs and build it
RUN git clone https://github.com/mozilla-services/syncstorage-rs ./ \
    && git checkout ${GIT_COMMIT} \
    && cargo install --path ./syncserver --no-default-features --features=syncstorage-db/mysql --locked \
    && cargo install diesel_cli --no-default-features --features mysql \
    && cargo clean

# Setup the Python venv
RUN virtualenv venv \
    && /app/venv/bin/pip install --no-cache-dir -r requirements.txt \
    && /app/venv/bin/pip install --no-cache-dir -r tools/tokenserver/requirements.txt \
    && /app/venv/bin/pip install --no-cache-dir pyopenssl==22.1.0

# Stage 2: Runtime
FROM debian:testing-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    default-mysql-client \
    python3 \
    ca-certificates \
    libcurl4 \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN groupadd -r syncserver && useradd -r -g syncserver -u 1000 syncserver

# Create directories with proper ownership
RUN mkdir -p /app /config && chown -R syncserver:syncserver /app /config

WORKDIR /app

# Copy binaries from builder
COPY --from=builder --chown=syncserver:syncserver /usr/local/cargo/bin/syncserver /usr/local/bin/
COPY --from=builder --chown=syncserver:syncserver /usr/local/cargo/bin/diesel /usr/local/bin/

# Copy Python venv
COPY --from=builder --chown=syncserver:syncserver /app/venv /app/venv

# Copy migration directories
COPY --from=builder --chown=syncserver:syncserver /app/syncstorage-mysql /app/syncstorage-mysql
COPY --from=builder --chown=syncserver:syncserver /app/tokenserver-db /app/tokenserver-db

# Copy entrypoint script
COPY --chmod=755 entrypoint.sh /entrypoint.sh

# Switch to non-root user
USER syncserver

# Expose port
EXPOSE 8000

ENTRYPOINT ["/entrypoint.sh"]
