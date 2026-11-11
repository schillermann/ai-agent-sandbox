# ==============================================================================
# AI Agent Sandbox Dockerfile (Multi-Stage)
# Optimized for running AI coding agents (such as Antigravity) safely.
#
# Available Stages / Targets:
#   - base:              Minimal core sandbox (hardened, unprivileged 'agent', agy CLI, entrypoint)
#   - web-ai-assistant:  Python backend + JavaScript frontend development (Web & AI Assistant profile)
#   - rust-game:         Rust toolchain + X11/OpenGL/Wayland libraries (Game engine & graphics profile)
#   - pyresponse:        web-ai-assistant + prebuilt project venv for ~/code/pyresponse
#                        (requires the additional build context 'pyresponse-src')
#   - badger-os:         Rust bare-metal toolchain (aarch64-unknown-none) + QEMU & GDB for ~/code/badger-os
# ==============================================================================

# ==============================================================================
# Stage 1: Base Core Sandbox
# ==============================================================================
FROM debian:bookworm-slim AS base

# Fail build immediately if any command in a pipeline fails
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

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
    chmod +x /usr/local/bin/agy && \
    rm -rf /root/.cache

# Create unprivileged 'agent' user (UID 1000, GID 1000) and prepare mountpoints
# Kept before COPY commands so rebuilds with script changes are instantaneous
RUN groupadd -g 1000 agent && \
    useradd -u 1000 -g agent -m -s /bin/bash agent && \
    mkdir -p /workspace /run/secrets /home/agent/.secrets /home/agent/.gemini/antigravity-cli /home/agent/.npm-global && \
    chown -R agent:agent /workspace /run/secrets /home/agent

# Copy executable scripts and configurations last to maximize Docker layer cache hits
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chown=agent:agent settings.json /usr/local/share/antigravity/settings.json
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

# Python version should match the project's production image (e.g. python:3.12-slim)
ARG PYTHON_VERSION=3.12

# 1. Install PostgreSQL client headers (Python itself is provided by uv below,
#    independent of Debian bookworm's system Python 3.11)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# 2. Install uv (fast Python version & package manager)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# 3. Install Node.js 20.x LTS & npm for frontend tooling, and global Pyright CLI
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g pyright \
    && npm cache clean --force \
    && rm -rf /root/.npm /var/lib/apt/lists/*

# Configure virtualenv, uv, bytecode cache (kept out of the mounted project folder)
# and npm global directory for unprivileged 'agent' user
ENV VIRTUAL_ENV=/opt/venv \
    UV_PYTHON_INSTALL_DIR=/opt/python \
    UV_LINK_MODE=copy \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPYCACHEPREFIX=/tmp/pycache \
    NPM_CONFIG_PREFIX=/home/agent/.npm-global \
    PATH="/opt/venv/bin:/home/agent/.npm-global/bin:$PATH"

# 4. Install Python ${PYTHON_VERSION} and create the shared venv (pip seeded for compatibility)
RUN uv python install ${PYTHON_VERSION} && \
    uv venv /opt/venv --python ${PYTHON_VERSION} --seed && \
    chown -R agent:agent /opt/venv /opt/python

# 5. Pre-install core testing and linting tools directly as unprivileged 'agent' user
#    (project dependencies are synced at container start by entrypoint.sh)
USER agent

RUN uv pip install --no-cache \
    pytest \
    pytest-asyncio \
    ruff

CMD ["agy"]


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

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal && \
    /usr/local/cargo/bin/rustup component add clippy rustfmt && \
    chown -R agent:agent /usr/local/rustup /usr/local/cargo && \
    rm -rf /usr/local/rustup/downloads /usr/local/rustup/tmp

USER agent
CMD ["agy"]


# ==============================================================================
# Stage 4: pyresponse (Pure OOP Python web framework)
# Builds on web-ai-assistant and bakes the project venv into /workspace/.venv,
# because the project's AGENTS.md and pyright config expect '.venv/bin/...'.
#
# The host's .venv (linked against the host Python) does not work in the
# container. Mount an anonymous volume over /workspace/.venv (see
# docker-compose.yml) so the venv baked into this image shadows the host one
# without touching it on the host.
#
# Build (the source is passed as an additional build context):
#   docker build --target pyresponse \
#     --build-context pyresponse-src=../pyresponse -t ai-agent-sandbox:pyresponse .
# ==============================================================================
FROM web-ai-assistant AS pyresponse

# Project supports Python >= 3.11 (override with --build-arg PYTHON_VERSION=...)
ARG PYTHON_VERSION=3.12

# Project venv lives inside the workspace path (shadowed by a volume at runtime)
ENV VIRTUAL_ENV=/workspace/.venv \
    PATH="/workspace/.venv/bin:$PATH" \
    SANDBOX_SKIP_DEP_SYNC=1

# Only the files required for an editable install (metadata + package sources);
# at runtime the bind-mounted project replaces them at the same path
COPY --chown=agent:agent --from=pyresponse-src pyproject.toml README.md /workspace/
COPY --chown=agent:agent --from=pyresponse-src pyresponse /workspace/pyresponse

# 1. Create the project venv and install pyresponse editable with dev extras
#    (pytest, pytest-asyncio, httpx, uvicorn, pyright) -> provides .venv/bin/pyr
# 2. Warm up the pyright PyPI wrapper so it does not download at runtime
RUN uv venv /workspace/.venv --python ${PYTHON_VERSION} --seed && \
    uv pip install --no-cache --python /workspace/.venv/bin/python -e "/workspace[dev]" && \
    /workspace/.venv/bin/pyright --version && \
    rm -rf /workspace/pyresponse.egg-info

CMD ["agy"]


# ==============================================================================
# Stage 5: badger-os (AArch64 Rust Microkernel & OS Development)
# Specifically tailored for ~/code/badger-os with bare-metal AArch64 Rust
# toolchain, LLVM binutils, QEMU system emulation, and multi-arch GDB.
# ==============================================================================
FROM base AS badger-os

USER root
ARG DEBIAN_FRONTEND=noninteractive

# 1. Install QEMU AArch64 system emulator (via qemu-system-arm), Option-ROMs (ipxe-qemu), and multi-arch GDB
RUN apt-get update && apt-get install -y --no-install-recommends \
    gdb-multiarch \
    ipxe-qemu \
    qemu-system-arm \
    && rm -rf /var/lib/apt/lists/*

# 2. Install Rust toolchain (stable) with AArch64 bare-metal target and LLVM binary utilities
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH="/usr/local/cargo/bin:$PATH"

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal && \
    /usr/local/cargo/bin/rustup component add clippy rustfmt llvm-tools-preview && \
    /usr/local/cargo/bin/rustup target add aarch64-unknown-none && \
    /usr/local/cargo/bin/cargo install cargo-binutils && \
    chown -R agent:agent /usr/local/rustup /usr/local/cargo && \
    rm -rf /usr/local/rustup/downloads /usr/local/rustup/tmp /usr/local/cargo/registry /usr/local/cargo/.package-cache

USER agent
CMD ["agy"]
