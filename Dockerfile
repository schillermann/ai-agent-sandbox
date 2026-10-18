# ==============================================================================
# AI Agent Sandbox Dockerfile (Multi-Stage)
# Optimized for running AI coding agents (such as Antigravity) safely.
#
# Available Stages / Targets:
#   - base:        Minimal core sandbox (hardened, unprivileged 'agent', hooks, entrypoint)
#   - web:         Python backend + JavaScript frontend development (MaklerChat profile)
#   - python-node: Alias for 'web'
#   - rust:        Rust toolchain + X11/OpenGL/Wayland libraries (Low-Cube profile)
#   - rust-x11:    Alias for 'rust'
#   - full / all:  Combined sandbox with both Web and Rust/X11 development environments
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

# Create unprivileged 'agent' user (UID 1000, GID 1000) and prepare mountpoints
# Kept before COPY commands so rebuilds with script changes are instantaneous
RUN groupadd -g 1000 agent && \
    useradd -u 1000 -g agent -m -s /bin/bash agent && \
    mkdir -p /workspace /run/secrets /home/agent/.secrets /home/agent/.gemini/antigravity-cli /etc/git-hooks && \
    chown -R agent:agent /workspace /run/secrets /home/agent && \
    git config --system core.hooksPath /etc/git-hooks

# Copy executable scripts and configurations last to maximize Docker layer cache hits
COPY --chmod=755 hooks/post-commit /etc/git-hooks/post-commit
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chown=agent:agent settings.json /home/agent/.gemini/antigravity-cli/settings.json

# Permanently enforce non-root execution
USER agent
WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]


# ==============================================================================
# Stage 2: Web Development (Python Backend & JavaScript Frontend)
# Specifically tailored for projects like MaklerChat
# ==============================================================================
FROM base AS web

USER root
ARG DEBIAN_FRONTEND=noninteractive

# 1. Install Python 3 development environment & PostgreSQL client libs (for asyncpg / pyfakepg)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    libpq-dev \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

# 2. Install Node.js 20.x LTS & npm for modern frontend build tooling (Vite, Lit, etc.)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Configure npm global directory and Python environment for unprivileged 'agent' user
ENV NPM_CONFIG_PREFIX=/home/agent/.npm-global \
    PIP_BREAK_SYSTEM_PACKAGES=1 \
    PATH="/home/agent/.npm-global/bin:$PATH"

RUN mkdir -p /home/agent/.npm-global && \
    chown -R agent:agent /home/agent/.npm-global

USER agent


# Alias for web target
FROM web AS python-node


# ==============================================================================
# Stage 3: Rust & X11 / OpenGL Development
# Specifically tailored for graphical / engine projects like Low-Cube (.github)
# ==============================================================================
FROM base AS rust

USER root
ARG DEBIAN_FRONTEND=noninteractive

# 1. Install X11, OpenGL, Wayland, and pkg-config dependencies matching Low-Cube CI (.github)
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


# Alias for rust target
FROM rust AS rust-x11


# ==============================================================================
# Stage 4: Full All-in-One Sandbox (Default)
# Combines Python, Node.js, Rust, and X11/OpenGL libraries
# ==============================================================================
FROM web AS full

USER root
ARG DEBIAN_FRONTEND=noninteractive

# Install X11 / OpenGL libraries into full stage
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

# Copy pre-installed Rust toolchain from the rust stage
COPY --from=rust --chown=agent:agent /usr/local/rustup /usr/local/rustup
COPY --from=rust --chown=agent:agent /usr/local/cargo /usr/local/cargo

ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH="/usr/local/cargo/bin:/home/agent/.npm-global/bin:$PATH"

USER agent


# Alias for full target (default if built without --target)
FROM full AS all
