#!/usr/bin/env bash
set -e

# ==============================================================================
# AI Agent Sandbox Entrypoint
# Enforces non-root execution (UID 1000: agent) and initializes environment
# ==============================================================================

# Verify we are running as unprivileged user
if [ "$(id -u)" -eq 0 ]; then
    echo "[SECURITY WARNING] Running as root is disallowed in this sandbox!"
    exit 1
fi

# Set default git identity if not configured yet
if [ -z "$(git config --global user.name 2>/dev/null)" ]; then
    git config --global user.name "${GIT_AUTHOR_NAME:-AI Agent}"
fi
if [ -z "$(git config --global user.email 2>/dev/null)" ]; then
    git config --global user.email "${GIT_AUTHOR_EMAIL:-agent@sandbox.local}"
fi

# Ensure workspace is treated as a safe git directory
git config --global --add safe.directory /workspace 2>/dev/null || true
git config --global --add safe.directory '*' 2>/dev/null || true

# Set default editor to standard vi / vim-tiny
export EDITOR="${EDITOR:-vi}"
export VISUAL="${VISUAL:-vi}"

# Include workspace and common source directories in PYTHONPATH if present
if [ -d "/workspace" ]; then
    export PYTHONPATH=".:/workspace:/workspace/src:/workspace/backend:${PYTHONPATH:-}"
fi

# Sync project Python dependencies into the sandbox venv (/opt/venv)
# - Only active in stages that provide uv + /opt/venv (e.g. web-ai-assistant)
# - Override the requirement files via SANDBOX_REQUIREMENTS (space-separated paths)
# - Disable entirely with SANDBOX_SKIP_DEP_SYNC=1
# - A failed sync is reported but never blocks the agent from starting
if [ "${SANDBOX_SKIP_DEP_SYNC:-0}" != "1" ] && [ -x "/opt/venv/bin/python" ] && command -v uv >/dev/null 2>&1; then
    REQUIREMENT_FILES="${SANDBOX_REQUIREMENTS:-/workspace/requirements.txt /workspace/requirements-dev.txt /workspace/backend/requirements.txt /workspace/backend/requirements-dev.txt}"
    for req in $REQUIREMENT_FILES; do
        if [ -f "$req" ]; then
            echo "[SANDBOX] Syncing Python dependencies from $req into /opt/venv ..."
            if uv pip install --quiet --python /opt/venv/bin/python -r "$req"; then
                echo "[SANDBOX] Python dependencies from $req installed."
            else
                echo "[SANDBOX WARNING] Dependency sync failed for $req (continuing without it)."
            fi
        fi
    done
fi

# Ensure onboarding state is marked complete so agy skips the first-run wizard
mkdir -p /home/agent/.gemini/antigravity-cli/cache
chmod 700 /home/agent/.gemini/antigravity-cli 2>/dev/null || true
if [ ! -f "/home/agent/.gemini/antigravity-cli/cache/onboarding.json" ]; then
    echo '{"consumerOnboardingComplete":true,"enterpriseOnboardingComplete":false,"onboardingComplete":true}' > /home/agent/.gemini/antigravity-cli/cache/onboarding.json
fi

# Sync baseline settings.json from image template and ensure workspace is automatically trusted
DEFAULT_SETTINGS="/usr/local/share/antigravity/settings.json"
SETTINGS_FILE="/home/agent/.gemini/antigravity-cli/settings.json"
if [ -f "$DEFAULT_SETTINGS" ]; then
    cp "$DEFAULT_SETTINGS" "$SETTINGS_FILE"
    chmod 600 "$SETTINGS_FILE" 2>/dev/null || true
fi
if [ -f "$SETTINGS_FILE" ] && command -v jq >/dev/null 2>&1; then
    CURRENT_DIR="$(pwd)"
    jq --arg dir "$CURRENT_DIR" '.trustedWorkspaces = ((.trustedWorkspaces // []) + ["/workspace", $dir] | unique)' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
    chmod 600 "$SETTINGS_FILE" 2>/dev/null || true
fi

# Execute given command, or default to agy (if available) / interactive bash shell
if [ $# -gt 0 ]; then
    exec "$@"
elif command -v agy >/dev/null 2>&1; then
    echo "[SANDBOX] Starting Antigravity CLI as primary process..."
    exec agy
else
    exec /bin/bash
fi
