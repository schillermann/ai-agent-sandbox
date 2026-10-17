# AI Agent Sandbox

A hardened, ephemeral Docker sandbox designed to execute AI coding agents (such as Google Antigravity, AutoGPT, SWE-agent, etc.) safely and without risk to the host system.

---

## Highlights

- 🛡️ **Zero Root Privileges**: Runs strictly under unprivileged user `agent` (`UID 1000`, `GID 1000`). Root access and `sudo` are completely eliminated. Dropped Linux capabilities (`--cap-drop=ALL`) and disabled privilege escalation (`no-new-privileges`).
- 💥 **Auto-Destruction on Git Commit**: Configured with a system-wide Git `post-commit` hook. Once the agent commits changes, the container terminates itself and Docker immediately wipes the container layer (`--rm`).
- ⚡ **Resource Constraints**: Hard caps on CPU usage, RAM, swap space, and process limits (PID cap) to prevent fork-bombs and runaway resource starvation.
- 🔑 **Ephemeral Secrets via Tmpfs**: Secrets and API tokens are mounted exclusively into volatile RAM filesystems (`tmpfs`), preventing any sensitive credentials from ever touching the host disk or container images.
- 📝 **Standard Editor**: Includes standard Linux `vim-tiny` / `vi`.


---

## Architecture & Security Model

```
+-------------------------------------------------------------+
| HOST SYSTEM (Secure, untouched)                             |
|                                                             |
|   +-------------------------------------------------------+ |
|   | Antigravity / AI Agent Orchestrator                   | |
|   +--------------------------+----------------------------+ |
|                              | docker run --rm              |
|                              v                              |
|   +-------------------------------------------------------+ |
|   | DOCKER CONTAINER SANDBOX                              | |
|   | - Non-root: user 'agent' (UID 1000:GID 1000)          | |
|   | - No new privileges, Cap drop: ALL                    | |
|   | - Limits: 2.0 CPUs, 4GB RAM, 250 PIDs                 | |
|   | - In-memory secrets: tmpfs (/run/secrets)             | |
|   |                                                       | |
|   | Workspace Volume Mount: /workspace                    | |
|   |                                                       | |
|   | Agent edits files -> Git commit -> post-commit hook   | |
|   |                              |                        | |
|   |                              v (kill 1)               | |
|   | Container exits & Docker cleans up immediately        | |
|   +-------------------------------------------------------+ |
+-------------------------------------------------------------+
```

### 1. 100% Residue-Free Auto-Destruction on Git Commit & Container Stop
To ensure that no container remnants, dangling volumes, or leaked caches persist:
1. **In-Container Purge**: When an AI agent executes `git commit`:
   - `/etc/git-hooks/post-commit` flushes files to the host mount (`sync`).
   - Volatile temporary directories and credentials (`/run/secrets`, `~/.secrets`, `/tmp`, `/var/tmp`) and command history are shredded in memory.
   - The hook signals PID 1 (`kill -TERM 1`) to terminate the container session cleanly.
2. **Daemon-Level Auto-Removal**: Launched with `--rm`, the Docker engine automatically purges the container state and unmounted layers when the process exits.
3. **Host-Side Trap Assurance**: The wrapper script [run-sandbox.sh](file:///home/mario/code/ai-agent-sandbox/run-sandbox.sh) installs a POSIX `trap` (`EXIT INT TERM HUP`). Regardless of whether the container terminates normally, crashes, or is stopped with `Ctrl+C` or `docker stop`, `docker rm -fv <container_name>` is guaranteed to run, eliminating any lingering anonymous volumes or zombie containers.
4. **Targeted Pruning**: All sandbox containers carry the label `sandbox=ai-agent`. Run `./run-sandbox.sh --clean` at any time to purge any orphaned containers.


### 2. Ephemeral Secrets (Tmpfs)
API keys and SSH credentials should **never** be baked into Docker images or stored in persistent container storage:
- `run-sandbox.sh` mounts `/run/secrets` and `/home/agent/.secrets` as `tmpfs` (RAM-only filesystems).
- Temporary secrets can be loaded at startup via `.secrets.env` without ever writing them to disk layers.
- Once the container is destroyed, secrets in memory vanish instantly.

### 3. Standard Editor
The sandbox includes:
- Standard minimal `vim-tiny` (providing `/usr/bin/vi` and `/usr/bin/vim.tiny`).
- Configured with `EDITOR=vi` and `VISUAL=vi`.


---

## Do AI Agents Need Internet Access for Their Work?

**Short answer:** It depends on your architecture (host-driven vs. in-container) and whether the agent needs to install dependencies.

### 1. LLM API Communication
| Scenario | Needs Container Internet? | Description |
| :--- | :---: | :--- |
| **Antigravity / Agent on Host** *(Recommended)* | ❌ **No** | Antigravity runs on your host machine, making API calls to Gemini/Claude/OpenAI from the host. It invokes compiler/test commands inside the container via `docker exec` or `docker run`. The sandbox can run completely offline (`--network none`). |
| **Agent Process inside Container** | ✔️ **Yes** | If the agent runtime itself is inside the container and relies on cloud LLMs (`generativelanguage.googleapis.com`, `api.anthropic.com`, etc.), it must have outbound HTTPS access. |
| **Local LLM on Host (Ollama / vLLM)** | ❌ **No** | If using a local model running on the host or local network, the container only needs internal network access (`host.docker.internal`), not public internet. |

### 2. Software Development Tasks
| Task | Needs Internet? | Mitigation / Best Practice |
| :--- | :---: | :--- |
| **Package Installation** (`pip`, `npm`, `apt`) | ✔️ **Yes** (usually) | Pre-install required packages into a customized Dockerfile derivative, or mount a local cache directory. |
| **Remote Git** (`push`, `pull`, `clone`) | ✔️ **Yes** | Perform git fetch/push operations from the host system; keep the sandbox purely local to `/workspace`. |
| **Web Search & Documentation** | ✔️ **Yes** | Host agent handles web search tools (e.g. Antigravity's `search_web`), so the container does not need access. |

### 3. Recommended Isolation Strategy
- **Maximum Security (Air-Gapped / Zero-Trust)**:
  Run with `--network none`. Prevents prompt injections from exfiltrating code or secrets via outbound HTTP or DNS tunnels:
  ```bash
  SANDBOX_NETWORK=none ./run-sandbox.sh /path/to/project
  ```
- **Standard Development (Controlled Egress)**:
  Default `bridge` network for tasks requiring `npm install` or `pip install`, protected by all other sandbox safeguards (non-root, PID limits, auto-destruction).

---

## Getting Started

### Prerequisites
- Docker Engine 20.10+ (or Podman)
- Linux / macOS / WSL2

### 1. Build the Docker Image
```bash
docker build -t ai-agent-sandbox:latest .
```

### 2. Launch with the Hardened Helper Script
The included [run-sandbox.sh](file:///home/mario/code/ai-agent-sandbox/run-sandbox.sh) script automatically applies all security flags:

```bash
# Run in the current directory:
./run-sandbox.sh

# Or specify a target workspace:
./run-sandbox.sh /home/mario/code/my-project
```

### 3. Manual Docker CLI Invocation
If you prefer running raw `docker run`:

```bash
docker run --rm -it \
  --security-opt=no-new-privileges:true \
  --cap-drop=ALL \
  --user 1000:1000 \
  --cpus="2.0" \
  --memory="4g" \
  --memory-swap="4g" \
  --pids-limit=250 \
  --tmpfs /tmp:rw,noexec,nosuid,size=256m,uid=1000,gid=1000 \
  --tmpfs /run/secrets:rw,noexec,nosuid,size=16m,uid=1000,gid=1000 \
  -e DESTROY_ON_COMMIT=1 \
  -v "$(pwd):/workspace:rw" \
  -w /workspace \
  ai-agent-sandbox:latest
```

### 4. Running with Docker Compose
```bash
# Start an interactive sandbox session
docker compose run --rm agent-sandbox
```

---

## Configuration & Environment Variables

| Variable | Default | Description |
| :--- | :--- | :--- |
| `DESTROY_ON_COMMIT` | `1` | Automatically terminates and destroys the container after `git commit`. Set to `0` to keep container alive across commits. |
| `SANDBOX_CPUS` | `2.0` | Maximum number of CPU cores allocated to the container. |
| `SANDBOX_MEM` | `4g` | Maximum memory allocated to the container. |
| `SANDBOX_PIDS` | `250` | Maximum number of simultaneous processes (prevents fork bombs). |
| `SANDBOX_NETWORK` | `bridge` | Network mode. Set to `none` for total air-gapped isolation. |

---

## Verifying Auto-Destruction

Inside the running sandbox container:

```bash
# 1. Initialize a git repo (or work inside an existing one)
git init
echo "Hello from AI Agent" > test.txt
git add test.txt

# 2. Commit changes
git commit -m "feat: agent milestone"

# Output:
# =================================================================
#  [SANDBOX] Git commit detected! Terminating container...
#  Container will be destroyed immediately by Docker (--rm).
# =================================================================
```

The container immediately exits and is wiped by Docker. The committed changes persist safely on your host's mounted workspace folder.

---

## License

This project is licensed under the MIT License - see the [LICENSE](file:///home/mario/code/ai-agent-sandbox/LICENSE) file for details.
