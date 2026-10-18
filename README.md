# AI Agent Sandbox

A hardened, ephemeral Docker sandbox for running Google Antigravity (`agy`) and AI coding agents safely without risk to the host system.

---

## Profiles & Services

Select the profile that fits your project in [docker-compose.yml](docker-compose.yml):

| Service | Toolchains & Libraries |
| :--- | :--- |
| **`agent-sandbox-web-ai-assistant`** | Python 3 (venv, pytest, ruff), Node.js 20 (npm, pyright), libpq-dev |
| **`agent-sandbox-rust-game`** | Rust stable (cargo, clippy, rustfmt), X11/Wayland/OpenGL dev headers |

---

## Usage

### 1. Build
```bash
docker compose build agent-sandbox-web-ai-assistant  # or: agent-sandbox-rust-game
```

### 2. Run
Mount your project directory via `PROJECT_DIR`. By default, the container starts `agy` interactively:

```bash
PROJECT_DIR=/path/to/project docker compose run --rm <service>
```

#### Common Options:
```bash
# Headless prompt (auto-destroys when done):
PROJECT_DIR=/path/to/project docker compose run --rm <service> agy -p "Implement feature X and run tests"

# Plain bash shell:
PROJECT_DIR=/path/to/project docker compose run --rm <service> bash

# Custom name & labels (for tracking and filtering):
PROJECT_DIR=/path/to/project docker compose run --rm \
  --name my-agent \
  --label task=issue-42 \
  <service>
```

---

## Security & Ephemeral Lifecycle

- 🛡️ **Non-Root & Hardened**: Runs strictly as user `agent` (`UID 1000`), drops all capabilities (`cap_drop: ALL`), and prevents privilege escalation (`no-new-privileges`).
- ⚡ **Resource Limits**: Capped at 2 CPUs, 4 GB RAM (swap disabled), and 250 PIDs.
- 💥 **Auto-Cleanup**: Container layers and in-memory secrets (`/tmp`, `/run/secrets`, `~/.secrets`) vanish completely upon exit (`--rm`).
- 🤖 **Autonomous Antigravity**: Pre-configured via [settings.json](settings.json) and mounted OAuth token.

> [!TIP]
> **Recommended Dual-Workflow:** Let `agy` edit code and run tests inside the isolated sandbox while running GUI apps or dev servers natively on the host with 0ms inotify latency.

---

## License

MIT License - see [LICENSE](LICENSE) for details.
