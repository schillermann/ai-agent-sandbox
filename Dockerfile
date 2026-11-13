# ==============================================================================
# AI Agent Sandbox Dockerfile (Multi-Stage)
# Optimized for running AI coding agents (such as Antigravity) safely.
#
# Available Stages / Targets:
#   - base:              Minimal core sandbox (hardened, unprivileged 'agent', agy CLI, entrypoint)
#   - python-base:       Base Python environment managed by uv (shared foundation for Python stages)
#   - web-ai-assistant:  Python backend + JavaScript frontend development (Web & AI Assistant profile)
#   - rust-base:         Base Rust toolchain (stable, Cargo, rustc, Clippy, Rustfmt)
#   - rust-game:         rust-base + X11/OpenGL/Wayland libraries (Game engine & graphics profile)
#   - pyresponse:        python-base + prebuilt project venv for ~/code/pyresponse
#                        (requires the additional build context 'pyresponse-src')
#   - badger-os:         rust-base + bare-metal target (aarch64-unknown-none), QEMU & GDB for ~/code/badger-os
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

# Create unprivileged 'agent' user (UID 1000, GID 1000), prepare mountpoints with strict permissions,
# and strip SUID/SGID bits from all system binaries for defense-in-depth against privilege escalation
# Kept before COPY commands so rebuilds with script changes are instantaneous
RUN groupadd -g 1000 agent && \
    useradd -u 1000 -g agent -m -s /bin/bash agent && \
    mkdir -p /workspace /home/agent/.gemini/antigravity-cli /home/agent/.npm-global && \
    chmod 700 /home/agent/.gemini/antigravity-cli && \
    chown -R agent:agent /workspace /home/agent && \
    find / -xdev -perm /6000 -type f -exec chmod a-s {} + 2>/dev/null || true

# Copy executable scripts and configurations last to maximize Docker layer cache hits
# /usr/local/share/antigravity/settings.json remains owned by root:root (read-only template)
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chmod=644 settings.json /usr/local/share/antigravity/settings.json

# Permanently enforce non-root execution
USER agent
WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["agy"]


# ==============================================================================
# Stage 2: Base Python Environment
# Shared foundation providing uv and managed Python runtime (without Node/PostgreSQL)
# ==============================================================================
FROM base AS python-base

USER root

# Python version should match the project's production image (e.g. python:3.12-slim)
ARG PYTHON_VERSION=3.12

# 1. Install uv (fast Python version & package manager)
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# 2. Configure uv and Python bytecode cache (kept out of the mounted project folder)
ENV UV_PYTHON_INSTALL_DIR=/opt/python \
    UV_LINK_MODE=copy \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPYCACHEPREFIX=/tmp/pycache

# 3. Install Python ${PYTHON_VERSION} (independent of Debian bookworm's system Python 3.11)
RUN uv python install --no-cache ${PYTHON_VERSION} && \
    rm -rf /home/agent/.cache && \
    chown -R agent:agent /opt/python /home/agent

USER agent
CMD ["agy"]


# ==============================================================================
# Stage 3: Web & AI Assistant Development (Python Backend & JavaScript Frontend)
# Specifically tailored for Web & AI Assistant profiles
# ==============================================================================
FROM python-base AS web-ai-assistant

USER root
ARG DEBIAN_FRONTEND=noninteractive
ARG PYTHON_VERSION=3.12

# 1. Install PostgreSQL client headers
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# 2. Install Node.js 20.x LTS & npm for frontend tooling, and global Pyright CLI
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && npm install -g pyright \
    && npm cache clean --force \
    && rm -rf /root/.npm /home/agent/.npm /var/lib/apt/lists/*

# Configure shared virtualenv and npm global directory for unprivileged 'agent' user
ENV VIRTUAL_ENV=/opt/venv \
    NPM_CONFIG_PREFIX=/home/agent/.npm-global \
    PATH="/opt/venv/bin:/home/agent/.npm-global/bin:$PATH"

# 3. Create the shared venv (pip seeded for compatibility)
RUN uv venv --no-cache /opt/venv --python ${PYTHON_VERSION} --seed && \
    rm -rf /home/agent/.cache && \
    chown -R agent:agent /opt/venv /home/agent

# 4. Pre-install project dependencies, testing, and linting tools directly as unprivileged 'agent' user
#    (any additional project dependencies are synced at container start by entrypoint.sh)
USER agent

RUN uv pip install --no-cache \
    "git+https://github.com/schillermann/pyresponse.git@main" \
    "git+https://github.com/schillermann/pyfakepg.git@main" \
    "git+https://github.com/schillermann/pyaidoc.git@main" \
    "uvicorn[standard]>=0.28.0" \
    "pydantic>=2.6.0" \
    "pytest>=8.0.0" \
    "pytest-asyncio>=0.23.0" \
    "httpx>=0.27.0" \
    "python-dotenv>=1.0.0" \
    "asyncpg>=0.30.0" \
    "boto3>=1.34.0" \
    "python-multipart>=0.0.9" \
    "pymupdf>=1.24.0" \
    "reportlab>=4.0.0" \
    "bcrypt>=4.0.0" \
    "pyright>=1.1.0" \
    ruff

CMD ["agy"]


# ==============================================================================
# Stage 4: Base Rust Environment
# Shared foundation providing Rust toolchain (stable, Cargo, rustc, Clippy, Rustfmt)
# ==============================================================================
FROM base AS rust-base

USER root

ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH="/usr/local/cargo/bin:$PATH"

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal --no-modify-path && \
    /usr/local/cargo/bin/rustup component add clippy rustfmt && \
    chown -R agent:agent /usr/local/rustup /usr/local/cargo /home/agent && \
    rm -rf /usr/local/rustup/downloads /usr/local/rustup/tmp

USER agent
CMD ["agy"]


# ==============================================================================
# Stage 5: Rust & X11 / OpenGL Game Development
# Specifically tailored for graphical and game engine projects
# ==============================================================================
FROM rust-base AS rust-game

USER root
ARG DEBIAN_FRONTEND=noninteractive

# Install X11, OpenGL, Wayland, and pkg-config dependencies for graphics and game engines
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

USER agent
CMD ["agy"]


# ==============================================================================
# Stage 6: pyresponse (Pure OOP Python web framework)
# Builds on python-base and bakes the project venv into /workspace/.venv,
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
FROM python-base AS pyresponse

# Project supports Python >= 3.11 (override with --build-arg PYTHON_VERSION=...)
ARG PYTHON_VERSION=3.12

# Project venv lives inside the workspace path (shadowed by a volume at runtime);
# keep pyright-python's nodeenv cache outside /tmp (which is mounted as tmpfs at runtime)
ENV VIRTUAL_ENV=/workspace/.venv \
    PATH="/workspace/.venv/bin:$PATH" \
    PYRIGHT_PYTHON_CACHE_DIR=/home/agent/.cache/pyright-python \
    SANDBOX_SKIP_DEP_SYNC=1

# Only the files required for an editable install (metadata + package sources);
# at runtime the bind-mounted project replaces them at the same path
COPY --chown=agent:agent --from=pyresponse-src pyproject.toml README.md /workspace/
COPY --chown=agent:agent --from=pyresponse-src pyresponse /workspace/pyresponse

# 1. Create the project venv and install pyresponse editable with dev extras
#    (pytest, pytest-asyncio, httpx, uvicorn, pyright) -> provides .venv/bin/pyr
# 2. Warm up the pyright PyPI wrapper so it does not download at runtime
RUN uv venv --no-cache /workspace/.venv --python ${PYTHON_VERSION} --seed && \
    uv pip install --no-cache --python /workspace/.venv/bin/python -e "/workspace[dev]" && \
    /workspace/.venv/bin/pyright --version && \
    rm -rf /workspace/pyresponse.egg-info

CMD ["agy"]


# ==============================================================================
# Stage 7: badger-os (AArch64 Rust Microkernel & OS Development)
# Specifically tailored for ~/code/badger-os with bare-metal AArch64 Rust
# toolchain, LLVM binutils, QEMU system emulation, and multi-arch GDB.
# ==============================================================================
FROM rust-base AS badger-os

USER root
ARG DEBIAN_FRONTEND=noninteractive

# 1. Install QEMU AArch64 system emulator (via qemu-system-arm), Option-ROMs (ipxe-qemu), and multi-arch GDB
RUN apt-get update && apt-get install -y --no-install-recommends \
    gdb-multiarch \
    ipxe-qemu \
    qemu-system-arm \
    && rm -rf /var/lib/apt/lists/*

# 2. Add AArch64 bare-metal target and LLVM binary utilities to the base Rust toolchain
RUN /usr/local/cargo/bin/rustup component add llvm-tools-preview && \
    /usr/local/cargo/bin/rustup target add aarch64-unknown-none && \
    /usr/local/cargo/bin/cargo install cargo-binutils && \
    chown -R agent:agent /usr/local/rustup /usr/local/cargo /home/agent && \
    rm -rf /usr/local/rustup/downloads /usr/local/rustup/tmp /usr/local/cargo/registry /usr/local/cargo/.package-cache

USER agent
CMD ["agy"]
