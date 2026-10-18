#!/usr/bin/env bash
# ==============================================================================
# Helper script to build and launch the AI Agent Sandbox on Linux
# Features:
# - Strictly hardened for native Linux execution
# - 100% residue-free container destruction upon stop or git commit
# - Zero root privileges (agent user: UID 1000, GID 1000)
# - Volatile RAM tmpfs for temporary files and secrets
# - Live zero-latency inotify synchronization with the host workspace
# ==============================================================================

set -euo pipefail

# Ensure script runs on native Linux
if [ "$(uname -s)" != "Linux" ]; then
    echo "[ERROR] The AI Agent Sandbox is strictly designed for Linux systems." >&2
    exit 1
fi

SANDBOX_TARGET="${SANDBOX_TARGET:-}"

# Parse optional arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --clean)
            echo "[SANDBOX] Cleaning all dangling or stopped sandbox containers..."
            docker container prune -f --filter "label=sandbox=ai-agent"
            echo "[SANDBOX] Cleanup complete."
            exit 0
            ;;
        --target|-t)
            SANDBOX_TARGET="$2"
            shift 2
            ;;
        *)
            break
            ;;
    esac
done

# Determine workspace directory (if $1 is an existing directory, use it; otherwise default to current dir)
if [ $# -gt 0 ] && [ -d "$1" ]; then
    WORKSPACE_DIR="$1"
    shift 1
else
    WORKSPACE_DIR="$(pwd)"
fi

# Convert WORKSPACE_DIR to absolute path
WORKSPACE_DIR="$(cd "${WORKSPACE_DIR}" && pwd)"

# Auto-detect target stage from workspace contents if not explicitly specified
if [ -z "${SANDBOX_TARGET}" ]; then
    if [ -f "${WORKSPACE_DIR}/Cargo.toml" ]; then
        SANDBOX_TARGET="rust-game"
    elif [ -f "${WORKSPACE_DIR}/package.json" ] || [ -f "${WORKSPACE_DIR}/pyproject.toml" ] || [ -f "${WORKSPACE_DIR}/requirements.txt" ]; then
        SANDBOX_TARGET="web-ai-assistant"
    fi
fi

# Determine default image name based on target if SANDBOX_IMAGE is not set
if [ -n "${SANDBOX_IMAGE:-}" ]; then
    IMAGE_NAME="${SANDBOX_IMAGE}"
elif [ -n "${SANDBOX_TARGET}" ]; then
    IMAGE_NAME="ai-agent-sandbox:${SANDBOX_TARGET}"
else
    IMAGE_NAME="ai-agent-sandbox:latest"
fi

# Resource limits (can be overridden via environment variables)
CPUS="${SANDBOX_CPUS:-2.0}"
MEMORY="${SANDBOX_MEM:-4g}"
PIDS_LIMIT="${SANDBOX_PIDS:-250}"

# Network mode: 'bridge' (default) or 'none' (air-gapped zero-trust isolation)
NETWORK_MODE="${SANDBOX_NETWORK:-bridge}"

# Destroy container on git commit flag (1 = enabled, 0 = disabled)
DESTROY_ON_COMMIT="${DESTROY_ON_COMMIT:-1}"

# Check if image exists; if not, build it
if ! docker image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
    echo "[SANDBOX] Image '${IMAGE_NAME}' not found. Building now..."
    BUILD_ARGS=()
    if [ -n "${SANDBOX_TARGET}" ]; then
        BUILD_ARGS+=(--target "${SANDBOX_TARGET}")
    fi
    docker build "${BUILD_ARGS[@]}" -t "${IMAGE_NAME}" "$(dirname "$0")"
fi

# Generate unique container ID
CONTAINER_RANDOM="$(od -An -N4 -tu4 /dev/urandom | tr -d ' ' 2>/dev/null || date +%s%N)"
CONTAINER_NAME="ai-sandbox-${CONTAINER_RANDOM:0:10}"

# Host trap: guarantees 100% residue-free container removal on stop, exit, or interrupt
cleanup() {
    local exit_code=$?
    echo ""
    echo "[SANDBOX] Container stopped or finished."
    echo "[SANDBOX] Ensuring residue-free deletion of container and anonymous volumes..."
    docker rm -fv "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    echo "[SANDBOX] Destruction complete: No container residues remain."
    exit "${exit_code}"
}
trap cleanup EXIT INT TERM HUP

echo "================================================================="
echo " Starting AI Agent Sandbox (Residue-free Linux Ephemeral Instance)"
echo " Image:             ${IMAGE_NAME}"
if [ -n "${SANDBOX_TARGET}" ]; then
echo " Target Stage:      ${SANDBOX_TARGET}"
fi
echo " Container Name:    ${CONTAINER_NAME}"
echo " Workspace:         ${WORKSPACE_DIR}"
echo " User:              agent (UID 1000, GID 1000, strictly non-root)"
echo " Auto-Destruction:  Triggered on 'git commit' or container stop"
echo " CPU Limit:         ${CPUS} cores"
echo " Memory Limit:      ${MEMORY} (swap disabled)"
echo " PID Limit:         ${PIDS_LIMIT}"
echo " Network Mode:      ${NETWORK_MODE}"
echo " Ephemeral Tmpfs:   /tmp, /var/tmp, /home/agent/.secrets, /run/secrets"
echo "================================================================="

# Prepare optional temporary secret file mapping if present
SECRETS_ARGS=()
if [ -f "${WORKSPACE_DIR}/.secrets.env" ]; then
    echo "[SANDBOX] Found local .secrets.env - injecting into volatile memory only"
    SECRETS_ARGS+=(--env-file "${WORKSPACE_DIR}/.secrets.env")
fi

# TTY flags (attach terminal if interactive)
INTERACTIVE_FLAGS=()
if [ -t 0 ]; then
    INTERACTIVE_FLAGS+=(-it)
fi

# Run container with:
# - '--rm': automatic removal by Docker daemon upon termination
# - '--name': uniquely identified container
# - '--label sandbox=ai-agent': allows targeted pruning
# - RAM tmpfs mounts for all temp dirs: prevents any file or secret from touching disk
docker run \
    --rm \
    --name "${CONTAINER_NAME}" \
    --label "sandbox=ai-agent" \
    "${INTERACTIVE_FLAGS[@]}" \
    --security-opt=no-new-privileges:true \
    --cap-drop=ALL \
    --user 1000:1000 \
    --cpus="${CPUS}" \
    --memory="${MEMORY}" \
    --memory-swap="${MEMORY}" \
    --pids-limit="${PIDS_LIMIT}" \
    --network="${NETWORK_MODE}" \
    --tmpfs /tmp:rw,noexec,nosuid,size=256m,uid=1000,gid=1000 \
    --tmpfs /var/tmp:rw,noexec,nosuid,size=64m,uid=1000,gid=1000 \
    --tmpfs /run/secrets:rw,noexec,nosuid,size=16m,uid=1000,gid=1000 \
    --tmpfs /home/agent/.secrets:rw,noexec,nosuid,size=16m,uid=1000,gid=1000 \
    --tmpfs /home/agent/.cache:rw,noexec,nosuid,size=128m,uid=1000,gid=1000 \
    "${SECRETS_ARGS[@]}" \
    -e DESTROY_ON_COMMIT="${DESTROY_ON_COMMIT}" \
    -v "${WORKSPACE_DIR}:/workspace:rw" \
    -w /workspace \
    "${IMAGE_NAME}" "$@"
