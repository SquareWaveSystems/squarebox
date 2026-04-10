# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

squarebox is a containerized development environment (Docker) combining modern CLI/TUI tools with Claude Code. It uses a persistent container model — the container suspends on exit and resumes on restart, preserving state. Workspace code lives on the host at `~/squarebox/workspace` via volume mount.

## Build & Run

```bash
# Build the Docker image
docker build -t squarebox .

# Create and run a new container (SSH agent forwarding, capability-restricted)
docker run -it --name squarebox \
  --cap-drop=ALL --cap-add=CHOWN --cap-add=DAC_OVERRIDE \
  --cap-add=FOWNER --cap-add=SETUID --cap-add=SETGID --cap-add=KILL \
  -e SSH_AUTH_SOCK=/tmp/ssh-agent.sock \
  -v "$SSH_AUTH_SOCK:/tmp/ssh-agent.sock" \
  -v ~/.ssh/config:/home/dev/.ssh/config:ro \
  -v ~/.ssh/known_hosts:/home/dev/.ssh/known_hosts:ro \
  -v ~/squarebox/workspace:/workspace \
  -v ~/.config/git:/home/dev/.config/git \
  -v ~/squarebox/.config/starship.toml:/home/dev/.config/starship.toml \
  -v ~/squarebox/.config/lazygit:/home/dev/.config/lazygit \
  -v /etc/localtime:/etc/localtime:ro \
  squarebox

# Resume an existing container
docker start -ai squarebox
```

The `install.sh` script automates initial setup (clone, build, create container, add `sqrbx` shell alias). A `.devcontainer/devcontainer.json` is also provided for VS Code Dev Containers / Codespaces.

**Windows PowerShell**: Only PowerShell 7+ (`pwsh`) is supported. Windows PowerShell 5.1 is not supported.

## First-Run Setup

`setup.sh` runs automatically on first container launch and prompts for:

1. **Git identity** — name and email (skipped if already configured)
2. **GitHub CLI auth** — persisted to `/workspace/.squarebox/gh` across rebuilds
3. **AI coding assistant** — Claude Code, GitHub Copilot CLI, Google Gemini CLI, OpenAI Codex CLI, OpenCode (any combination)
4. **Text editors** — micro, edit (Microsoft), fresh, nvim (nano is always available)
5. **TUI tools** — lazygit, gh-dash, yazi (any combination)
6. **Terminal multiplexers** — tmux, zellij
7. **SDKs** — Node.js (via nvm), Python (via uv), Go, .NET

Selections are saved to `/workspace/.squarebox/` and reused on subsequent rebuilds.

## Updating Tool Versions

```bash
# Update all pinned versions, checksums, Dockerfile ARGs, and setup.sh versions
scripts/update-versions.sh

# Inside a running container, update tool binaries in-place from GitHub releases
sqrbx-update
```

`scripts/update-versions.sh` fetches latest GitHub releases, downloads artifacts for both architectures, computes SHA256 checksums, and updates `checksums.txt`, `setup-checksums.txt`, `Dockerfile`, and `setup.sh`.

## CI

GitHub Actions workflow (`.github/workflows/build.yml`) validates the Dockerfile builds on every push and PR using buildx with GitHub Actions cache. An E2E test suite (`scripts/e2e-test.sh`, `.github/workflows/e2e.yml`) runs the container and validates tool installations.

## Dockerfile Architecture

The Dockerfile (Ubuntu 24.04 base) is organized into sequential stages:

1. **Base packages** — git, curl, ripgrep, bat, fzf, zoxide, fd, etc. via apt
2. **External APT repos** — GitHub CLI, Eza via apt (requires gnupg, stays combined)
3. **Per-tool binary installs** — one `RUN` layer per tool via `sb_install` from the shared library
4. **User setup** — creates non-root `dev` user with workspace directory
5. **Config files** — git config with delta as default pager (lazygit config is set up by setup.sh when lazygit is installed)
6. **Setup script & configs** — copies `setup.sh`, `sqrbx-update`, starship.toml
7. **Shell config** — bashrc with starship prompt, zoxide, aliases

The Dockerfile uses `SHELL ["/bin/bash", "-c"]` because `tool-lib.sh` relies on bash parameter substitution. All tool versions are pinned via `ARG` directives and verified against SHA256 checksums.

## Windows Support

- **PowerShell**: only PowerShell 7+ (`pwsh`) is supported. Windows PowerShell 5.1 (`powershell.exe`) is not supported.
- **Git Bash**: install.sh uses `MSYS_NO_PATHCONV=1` to prevent MSYS2 path mangling in Docker volume mounts.
- **Install directory**: uses `USERPROFILE` (not MSYS2 `HOME`) so the clone lands at `C:\Users\<user>\squarebox`.
- **`$HOME` vs `$USER_HOME`** (install.sh): on Git Bash these diverge — `$HOME` is the MSYS home (`/home/user`, where bash actually reads `.bashrc` from), while `$USER_HOME` is derived from `USERPROFILE` (`C:/Users/user`, where the clone lives). Things anchored to the running shell (rc files, the `~/.squarebox-shell-init` file the sentinel sources) must use `$HOME`; things anchored to the filesystem install (`$INSTALL_DIR`, git config path, volume mounts) use `$USER_HOME`. Baking `$INSTALL_DIR` into shell function bodies at install time avoids runtime `$HOME` resolving wrong. On Linux/macOS the two are identical.
- **Shell integration**: install.sh writes the four function bodies to `~/.squarebox-shell-init` and adds a single sentinel-marked `. ~/.squarebox-shell-init` line to `~/.bashrc` / `~/.zshrc` / PowerShell `$PROFILE`. The sentinel block (`# >>> squarebox >>>` / `# <<< squarebox <<<`) is scrubbed and rewritten on every run, along with any legacy `alias sqrbx=...` or one-liner `sqrbx() {...}` lines from pre-646a589 installs (those collide with the function definitions at parse time due to `expand_aliases` and produce a `syntax error near unexpected token '('`).

## Tool Registry

`scripts/lib/tools.yaml` is the single source of truth for tool metadata (repos, artifact patterns, arch mappings, extract methods). `scripts/lib/tool-lib.sh` is a shared shell library that consumes it.

- **YAML parsing uses awk** (not yq) to avoid a bootstrap problem — yq is one of the tools being installed
- **Architecture tokens**: `{dpkg_arch}` (amd64/arm64), `{zarch}` (x86_64/aarch64), `{larch}` (x86_64/arm64), `{goarch}`, `{ocarch}`, `{march}` — each tool uses whichever convention its upstream releases follow
- **Build-time**: library at `/tmp/tool-lib.sh`, consumers override `sb_verify()` for checksum verification
- **Runtime**: library at `/usr/local/lib/squarebox/tool-lib.sh`, used by `sqrbx-update` and `setup.sh`
- **Adding a new tool**: add an entry to `tools.yaml`, then run `scripts/update-versions.sh`
