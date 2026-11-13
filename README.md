# AI Agent Sandbox

A hardened, ephemeral Docker sandbox for running Google Antigravity (`agy`) and AI coding agents safely without risk to the host system.

---

## Profiles & Services

Select the profile that fits your project in [docker-compose.yml](docker-compose.yml):

| Service | Toolchains & Libraries |
| :--- | :--- |
| **`web-ai-assistant`** | Python 3 (venv, pytest, ruff), Node.js 20 (npm, pyright), libpq-dev |
| **`rust-game`** | Rust stable (cargo, clippy, rustfmt), X11/Wayland/OpenGL dev headers |
| **`pyresponse`** | `python-base` + prebuilt `.venv` for [pyresponse](https://github.com/schillermann/pyresponse) (editable install, dev extras, pyright). Defaults to `PROJECT_DIR=../pyresponse` |
| **`badger-os`** | Rust stable (`aarch64-unknown-none`, clippy, rustfmt, `llvm-tools-preview`, `cargo-binutils`), `qemu-system-arm` (`qemu-system-aarch64`), `gdb-multiarch`. Defaults to `PROJECT_DIR=../badger-os` |

---

## Usage

### 1. Build
```bash
docker compose build <service>
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

- 🛡️ **Non-Root & Hardened**: Runs strictly as user `agent` (`UID 1000`), strips SUID/SGID binaries, drops all capabilities (`cap_drop: ALL`), and prevents privilege escalation (`no-new-privileges`).
- ⚡ **Resource Limits**: Capped at 2 CPUs, 4 GB RAM (swap disabled), and 250 PIDs.
- 💥 **Auto-Cleanup**: Container layers and in-memory `/tmp` (`tmpfs`) vanish completely upon exit (`--rm`).
- 🤖 **Autonomous Antigravity**: Pre-configured via [settings.json](settings.json), persistent sandbox state volume (`ai-agent-sandbox-agy-state`), and mounted `history.jsonl` for prompt history.

> [!TIP]
> **Recommended Dual-Workflow:** Let `agy` edit code and run tests inside the isolated sandbox while running GUI apps or dev servers natively on the host with 0ms inotify latency.

---

## License

MIT License - see [LICENSE](LICENSE) for details.
