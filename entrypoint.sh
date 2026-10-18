#!/usr/bin/env bash
set -e

# ==============================================================================
# AI Agent Sandbox Entrypoint
# Enforces non-root execution (UID 1000: agent) and handles ephemeral secrets
# ==============================================================================

# Verify we are running as unprivileged user
if [ "$(id -u)" -eq 0 ]; then
    echo "[SECURITY WARNING] Running as root is disallowed in this sandbox!"
    exit 1
fi

# Load ephemeral secrets from in-memory tmpfs mount if available
if [ -d "/run/secrets" ]; then
    for secret_env in /run/secrets/*.env; do
        if [ -f "$secret_env" ]; then
            echo "[SANDBOX] Sourcing temporary secrets from $secret_env (in-memory)"
            set -a
            # shellcheck source=/dev/null
            source "$secret_env"
            set +a
        fi
    done
fi

if [ -d "/home/agent/.secrets" ]; then
    for secret_env in /home/agent/.secrets/*.env; do
        if [ -f "$secret_env" ]; then
            echo "[SANDBOX] Sourcing temporary secrets from $secret_env (in-memory)"
            set -a
            # shellcheck source=/dev/null
            source "$secret_env"
            set +a
        fi
    done
fi

# Set default git identity if not configured yet
if [ -z "$(git config --global user.name 2>/dev/null)" ]; then
    git config --global user.name "${GIT_AUTHOR_NAME:-AI Agent}"
fi
if [ -z "$(git config --global user.email 2>/dev/null)" ]; then
    git config --global user.email "${GIT_AUTHOR_EMAIL:-agent@sandbox.local}"
fi

# Set default editor to standard vi / vim-tiny
export EDITOR="${EDITOR:-vi}"
export VISUAL="${VISUAL:-vi}"

# Include workspace and common source directories in PYTHONPATH if present
if [ -d "/workspace" ]; then
    export PYTHONPATH=".:/workspace:/workspace/src:/workspace/backend:${PYTHONPATH:-}"
fi

# Execute given command or default to interactive shell
if [ $# -eq 0 ]; then
    exec /bin/bash
else
    exec "$@"
fi
