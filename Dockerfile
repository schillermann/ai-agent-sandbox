# ==============================================================================
# AI Agent Sandbox Dockerfile (Multi-Stage)
# Optimized for running AI coding agents (such as Antigravity) safely.
#
# Available Stages / Targets:
#   - base:              Minimal core sandbox (hardened, unprivileged 'agent', agy CLI, entrypoint)
#   - web-ai-assistant:  Python backend + JavaScript frontend development (Web & AI Assistant profile)
#   - rust-game:         Rust toolchain + X11/OpenGL/Wayland libraries (Game engine & graphics profile)
# ==============================================================================

# ==============================================================================
# Stage 1: Base Core Sandbox
# ==============================================================================
FROM debian:bookworm-slim AS base

# Build-time variable only (does not leak into container runtime)
ARG DEBIAN_FRONTEND=noninteractive

# Runtime environment variables
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    EDITOR=vi \
    VISUAL=vi \
    HOME=/home/agent

# Install essential CLI dependencies, minimal vim-tiny, Git, and base build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    ca-certificates \
    curl \
    git \
    gnupg \
    jq \
    less \
    openssh-client \
    procps \
    ripgrep \
    vim-tiny \
    && rm -rf /var/lib/apt/lists/*

# Install Google Antigravity CLI globally
RUN curl -fsSL https://antigravity.google/cli/install.sh | bash -s -- --dir /usr/local/bin && \
    chmod +x /usr/local/bin/agy

# Create unprivileged 'agent' user (UID 1000, GID 1000) and prepare mountpoints
# Kept before COPY commands so rebuilds with script changes are instantaneous
RUN groupadd -g 1000 agent && \
    useradd -u 1000 -g agent -m -s /bin/bash agent && \
    mkdir -p /workspace /run/secrets /home/agent/.secrets /home/agent/.gemini/antigravity-cli && \
    chown -R agent:agent /workspace /run/secrets /home/agent

# Copy executable scripts and configurations last to maximize Docker layer cache hits
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chown=agent:agent settings.json /home/agent/.gemini/antigravity-cli/settings.json

# Permanently enforce non-root execution
USER agent
WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["agy"]


# ==============================================================================
# Stage 2: Web & AI Assistant Development (Python Backend & JavaScript Frontend)
# Specifically tailored for Web & AI Assistant profiles
# ==============================================================================
FROM base AS web-ai-assistant

USER root
ARG DEBIAN_FRONTEND=noninteractive

# 1. Install Python 3 development environment and PostgreSQL client headers
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# 2. Install Node.js 20.x LTS & npm for frontend tooling, and global Pyright CLI
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g pyright \
    && rm -rf /var/lib/apt/lists/*

# Configure dedicated virtualenv and npm global directory for unprivileged 'agent' user
ENV VIRTUAL_ENV=/opt/venv \
    NPM_CONFIG_PREFIX=/home/agent/.npm-global \
    PATH="/opt/venv/bin:/home/agent/.npm-global/bin:$PATH"

RUN python3 -m venv /opt/venv && \
    mkdir -p /home/agent/.npm-global && \
    chown -R agent:agent /opt/venv /home/agent/.npm-global

# 3. Pre-install core testing and linting tools for AI agents
RUN /opt/venv/bin/pip install --no-cache-dir \
    pytest \
    pytest-asyncio \
    ruff

USER agent




# ==============================================================================
# Stage 3: Rust & X11 / OpenGL Game Development
# Specifically tailored for graphical and game engine projects
# ==============================================================================
FROM base AS rust-game

USER root
ARG DEBIAN_FRONTEND=noninteractive

# 1. Install X11, OpenGL, Wayland, and pkg-config dependencies for graphics and game engines
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1-mesa-dev \
    libwayland-dev \
    libx11-dev \
    libxcursor-dev \
    libxi-dev \
    libxinerama-dev \
    libxkbcommon-dev \
    libxrandr-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# 2. Install Rust toolchain (stable) with Cargo, rustc, Clippy, and Rustfmt
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH="/usr/local/cargo/bin:$PATH"

RUN mkdir -p /usr/local/rustup /usr/local/cargo && \
    chown -R agent:agent /usr/local/rustup /usr/local/cargo && \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal && \
    /usr/local/cargo/bin/rustup component add clippy rustfmt && \
    chown -R agent:agent /usr/local/rustup /usr/local/cargo

USER agent


