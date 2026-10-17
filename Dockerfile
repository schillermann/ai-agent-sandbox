# ==============================================================================
# AI Agent Sandbox Dockerfile
# Optimized for running AI coding agents (such as Antigravity) safely.
#
# Key Features:
# - Strictly Non-Root: runs as 'agent' (UID 1000, GID 1000)
# - Auto-destruction on git commit: post-commit hook triggers container termination
# - Standard Editor: vim-tiny / vi
# - In-memory ephemeral secrets support via tmpfs
# - Optimal Layer Caching: static system layers first, scripts last
# ==============================================================================

FROM debian:bookworm-slim

# Build-time variable only (does not leak into container runtime)
ARG DEBIAN_FRONTEND=noninteractive

# Runtime environment variables
ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    EDITOR=vi \
    VISUAL=vi \
    HOME=/home/agent

# Install essential dependencies, minimal vim-tiny, Git, Python, and build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    ca-certificates \
    curl \
    git \
    jq \
    less \
    openssh-client \
    procps \
    python3 \
    python3-pip \
    python3-venv \
    ripgrep \
    vim-tiny \
    && rm -rf /var/lib/apt/lists/*

# Create unprivileged 'agent' user (UID 1000, GID 1000) and prepare mountpoints
# Kept before COPY commands so rebuilds with script changes are instantaneous
RUN groupadd -g 1000 agent && \
    useradd -u 1000 -g agent -m -s /bin/bash agent && \
    mkdir -p /workspace /run/secrets /home/agent/.secrets /etc/git-hooks && \
    chown -R agent:agent /workspace /run/secrets /home/agent && \
    git config --system core.hooksPath /etc/git-hooks

# Copy executable scripts last to maximize Docker layer cache hits
COPY --chmod=755 hooks/post-commit /etc/git-hooks/post-commit
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

# Permanently enforce non-root execution
USER agent
WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
