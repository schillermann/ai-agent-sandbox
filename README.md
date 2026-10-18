# AI Agent Sandbox

A hardened, ephemeral Docker sandbox for running Google Antigravity (`agy`) and AI coding agents safely without risk to the host system.

---

## Quickstart

### 1. Build the Sandbox
```bash
# Build default full environment (Python, Node.js, Rust):
docker compose build agent-sandbox

# Or build a specific target:
docker compose build agent-sandbox-rust-game        # Rust & OpenGL/X11
docker compose build agent-sandbox-web-ai-assistant # Python 3 & Node.js
```

### 2. Launch with Your Project
Mount your project directory via `PROJECT_DIR`. The container automatically launches `agy` inside your project workspace:

```bash
# Interactive Antigravity session (Full environment):
PROJECT_DIR=/path/to/project docker compose run --rm agent-sandbox

# Or for a specific profile (e.g. Rust):
PROJECT_DIR=/path/to/project docker compose run --rm agent-sandbox-rust-game
```

### 3. Non-Interactive / Headless Mode
Pass prompts directly to `agy`. The container exits and auto-destroys as soon as the prompt finishes:

```bash
PROJECT_DIR=/path/to/project docker compose run --rm agent-sandbox agy -p "Implement feature X and run tests"
```

### 4. Interactive Bash Shell (Optional)
If you need a plain shell inside the sandbox instead of `agy`:

```bash
PROJECT_DIR=/path/to/project docker compose run --rm agent-sandbox bash
```

---

## Profiles & Services

Select the profile that fits your project in [docker-compose.yml](docker-compose.yml):

| Service | Included Toolchains & Libraries |
| :--- | :--- |
| **`agent-sandbox`** *(Default)* | Full All-in-One: Python 3, Node.js 20, Rust, Pyright, Ruff, Clippy, X11/OpenGL |
| **`agent-sandbox-rust-game`** | Rust stable toolchain, Cargo, Clippy, Rustfmt, X11/Wayland/OpenGL dev headers |
| **`agent-sandbox-web-ai-assistant`** | Python 3, venv, Node.js 20, npm, Pyright, pytest, ruff, libpq-dev |

---

## Lifecycle & Ephemeral Cleanup

- 🤖 **Pre-Installed Antigravity (`agy`)**: Pre-installed globally and configured with autonomous permissions ([settings.json](settings.json)).
- 💥 **Bound to `agy` Lifecycle**: When `agy` completes its prompt or when you exit (`/exit` or `Ctrl+D`), the container stops and Docker immediately destroys all temporary container layers (`--rm`).
- 🔑 **Ephemeral Secrets via Tmpfs**: Secrets, OAuth tokens, and temporary files (`/tmp`, `/run/secrets`, `~/.secrets`) live strictly in RAM and vanish immediately upon container termination.
- 🧹 **Manual Cleanup**:
  ```bash
  docker compose down --remove-orphans
  ```

---

## Security Model

- 🛡️ **Zero Root Privileges**: Runs strictly under unprivileged user `agent` (`UID 1000:GID 1000`). Root access and `sudo` are eliminated.
- 🔒 **Kernel Hardening**: All Linux capabilities dropped (`--cap-drop=ALL`) and privilege escalation blocked (`no-new-privileges`).
- ⚡ **Resource Limits**: Fixed caps on CPU (2.0 cores), RAM (4 GB, swap disabled), and processes (250 PIDs limit) to prevent runaway scripts.

---

## Recommended Dual-Workflow

Because the sandbox bind-mounts your project natively on Linux with 0ms inotify latency:
- **Inside Sandbox (Terminal 1 - AI Agent):**
  `agy` edits code and runs tests in complete isolation.
  ```bash
  PROJECT_DIR=/path/to/project docker compose run --rm agent-sandbox
  ```
- **On Host (Terminal 2 - Developer / GUI & Testing):**
  Run GUI apps, local dev servers, or hot-reloaders natively with full GPU performance:
  ```bash
  cd /path/to/project
  cargo run  # or: cargo watch -x run
  ```

---

## License

MIT License - see [LICENSE](LICENSE) for details.
