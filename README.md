# 🟧📦 squarebox

**A curated set of modern CLI/TUI tools and AI coding assistants in a Docker container. Batteries included.**

*For developers who live in the terminal but need to work across
multiple platforms and devices.*

**squarebox** packages a complete terminal-based development environment
into a single Docker container: modern CLI tools, AI coding assistants,
language SDKs, and an opinionated set of shell aliases. Run the same box
anywhere (desktop, VPS, or Codespace) and SSH in from your laptop, tablet,
or phone (please don't).

The goal is to make modern terminal tooling easy and accessible. One-line
install, interactive first-run setup, sensible defaults (thanks [omarchy](https://omarchy.org)).

![squarebox first-run setup](https://raw.githubusercontent.com/SquareWaveSystems/squarebox/demo/demo/squarebox-setup.gif)
*(Actual setup may involve more staring at the screen.)*

Prerequisites
-------------

- [Docker](https://docs.docker.com/get-docker/) (see one-line install below if you don't have it)
- [Git](https://git-scm.com/) - on Windows, install [Git for Windows](https://gitforwindows.org/)
  (provides `bash` and `winpty` needed by the install script)

### Don't have Docker? One-line install

**macOS** (via [Homebrew](https://brew.sh)):

    brew install --cask docker-desktop

**Linux** (official convenience script - inspect it first at [get.docker.com](https://get.docker.com)):

    curl -fsSL https://get.docker.com | sh && sudo usermod -aG docker $USER

Log out and back in (or run `newgrp docker`) so your shell picks up the new group.

**Windows** (via [winget](https://learn.microsoft.com/en-us/windows/package-manager/winget/), in PowerShell 7+):

    winget install --id Docker.DockerDesktop -e

On macOS and Windows, start Docker Desktop once after install so the daemon is
running before you continue.

Install
-------

These commands clone the repo, build the Docker image, and drop you into the
container (if possible). On first login, a setup script runs automatically to
configure git (pulling your name and email from the host's global git config
if available), optionally sign in to GitHub CLI, your choice of AI coding
assistant, and language SDKs.

**Stable**

    curl -fsSL https://raw.githubusercontent.com/SquareWaveSystems/squarebox/main/install.sh | bash

**Edge**

    curl -fsSL https://raw.githubusercontent.com/SquareWaveSystems/squarebox/main/install.sh | bash -s -- --edge

Stable installs the latest tagged release (pre-release tags like `-rc` are skipped). Edge uses the latest commit on main.

If the install fails or you want to see the full docker build and git output, re-run with `--verbose`:

    curl -fsSL https://raw.githubusercontent.com/SquareWaveSystems/squarebox/main/install.sh | bash -s -- --verbose

Start
-----

    squarebox        # or: sqrbx

These are shell aliases for `docker start -ai squarebox`, added automatically
for Bash, Zsh, and PowerShell 7+.

The container is persistent: it suspends on exit and resumes on start, keeping
installed packages, config, and shell history intact between sessions. Your
code and tool config live on the host under `~/squarebox` (`workspace/` for
code, `.config/` for tool config) via volume mounts, so they survive even if
the container is deleted.

What's included
---------------

### CLI Tools

| Name | Language | Description |
|------|----------|-------------|
| [bat](https://github.com/sharkdp/bat) | Rust | Cat clone with syntax highlighting |
| [curl](https://github.com/curl/curl) | C | URL data transfer |
| [delta](https://github.com/dandavison/delta) | Rust | Syntax-highlighting pager for git diffs |
| [eza](https://github.com/eza-community/eza) | Rust | Modern ls replacement |
| [fd](https://github.com/sharkdp/fd) | Rust | Fast, user-friendly find alternative |
| [fzf](https://github.com/junegunn/fzf) | Go | Fuzzy finder |
| [gh](https://github.com/cli/cli) | Go | GitHub CLI |
| [glow](https://github.com/charmbracelet/glow) | Go | Terminal markdown renderer |
| [gum](https://github.com/charmbracelet/gum) | Go | Tool for shell scripts and dotfiles |
| [jq](https://github.com/jqlang/jq) | C | JSON processor |
| [nano](https://nano-editor.org) | C | Default text editor |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | Rust | Fast recursive grep |
| [starship](https://github.com/starship/starship) | Rust | Cross-shell prompt |
| [xh](https://github.com/ducaale/xh) | Rust | Friendly HTTP client |
| [yq](https://github.com/mikefarah/yq) | Go | YAML/JSON/XML processor |
| [zoxide](https://github.com/ajeetdsouza/zoxide) | Rust | Smarter cd command |

What's optional
----------------

Selected during first-run setup. Choose any combination, all, or none.
Selections are saved to the workspace volume and reused automatically on
container rebuilds.

### AI Coding Assistants

| Name | Language | Description |
|------|----------|-------------|
| [Claude Code](https://github.com/anthropics/claude-code) | TypeScript | AI coding assistant |
| [GitHub Copilot CLI](https://github.com/githubnext/github-copilot-cli) | TypeScript | GitHub Copilot in the terminal * |
| [Google Gemini CLI](https://github.com/google-gemini/gemini-cli) | TypeScript | Google Gemini in the terminal * |
| [OpenAI Codex CLI](https://github.com/openai/codex) | TypeScript | OpenAI Codex in the terminal * |
| [opencode](https://github.com/anomalyco/opencode) | Go | AI coding TUI |

\* Requires Node.js (auto-installed if needed).

### Text Editors

Nano is always available as the default editor.

| Name | Language | Description |
|------|----------|-------------|
| [micro](https://github.com/micro-editor/micro) | Go | Modern, intuitive terminal editor |
| [edit](https://github.com/microsoft/edit) | Rust | Terminal text editor (Microsoft) |
| [fresh](https://github.com/sinelaw/fresh) | Rust | Modern terminal text editor |
| [helix](https://github.com/helix-editor/helix) | Rust | Modal editor (Kakoune-inspired) - *coming soon* |
| [nvim](https://github.com/neovim/neovim) | C/Lua | Neovim |

### TUI Tools

Installed during first-run setup. Choose any combination:

| Name | Language | Description |
|------|----------|-------------|
| [lazygit](https://github.com/jesseduffield/lazygit) | Go | Git terminal UI |
| [gh-dash](https://github.com/dlvhdr/gh-dash) | Go | GitHub dashboard for the terminal |
| [yazi](https://github.com/sxyazi/yazi) | Rust | Terminal file manager |

### Terminal Multiplexers

Installed during first-run setup. Choose either, both, or neither:

| Name | Description |
|------|-------------|
| [tmux](https://github.com/tmux/tmux) | Classic terminal multiplexer |
| [zellij](https://github.com/zellij-org/zellij) | Friendly terminal workspace |

### SDKs

| SDK | Installed via |
|-----|---------------|
| Node.js | [nvm](https://github.com/nvm-sh/nvm) |
| Python | [uv](https://github.com/astral-sh/uv) |
| Go | [go.dev](https://go.dev) |
| .NET | [dotnet-install](https://dot.net) |

Aliases
-------

| Alias | Command | Description |
|-------|---------|-------------|
| `ls` | `eza --icons` | Modern ls with icons |
| `ll` | `eza -la --icons` | Long listing with icons |
| `lsa` | `ls -a` (resolves to `eza --icons -a`) | List all including hidden files |
| `lt` | `eza --tree --level=2 --long --icons --git` | Tree view with git status |
| `lta` | `lt -a` | Tree view including hidden files |
| `cat` | `bat --paging=never` | Syntax-highlighted cat |
| `ff` | `fzf --preview 'bat ...'` | Fuzzy find with preview |
| `eff` | `$EDITOR "$(ff)"` | Fuzzy find and edit |
| `..` | `cd ..` | Go up one directory |
| `...` | `cd ../..` | Go up two directories |
| `....` | `cd ../../..` | Go up three directories |
| `c` | first selected AI tool | Launch selected AI assistant |
| `g` | `git` | Git shorthand |
| `gcm` | `git commit -m` | Commit with message |
| `gcam` | `git commit -a -m` | Stage all and commit |
| `gcad` | `git commit -a --amend` | Stage all and amend |
| `lg` | `lazygit` | Launch lazygit (if installed) |
| `claude-yolo` | `claude --dangerously-skip-permissions` | Claude without prompts |
| `opencode-yolo` | `opencode --dangerously-skip-permissions` | OpenCode without prompts |

### Multiplexer Keybindings (Experimental)

Both tmux and zellij ship with Omarchy-inspired defaults and matching keybindings:

| Feature | Tmux | Zellij |
|---------|------|--------|
| Config path | `~/.config/tmux/tmux.conf` | `~/.config/zellij/config.kdl` |
| Prefix | `Ctrl+Space` | `Ctrl+Space` (Tmux mode) |
| Pane navigation | `Ctrl+Alt+Arrow` | `Ctrl+Alt+Arrow` |
| Pane resizing | `Ctrl+Alt+Shift+Arrow` | `Ctrl+Alt+Shift+Arrow` |
| Tab/window select | `Alt+1-9` | `Alt+1-9` |
| Tab/window cycle | `Alt+Left/Right` | `Alt+Left/Right` |
| Split horizontal | `prefix h` | `prefix h` |
| Split vertical | `prefix v` | `prefix v` |
| Scrollback | 50,000 lines | 50,000 lines |
| Copy mode | Vi keys | Vi-style scroll |
| Theme | Blue accent, top bar | Blue accent, compact layout |

Update
------

### Quick update (from inside the container)

    sqrbx-update

Checks all GitHub-released tools against latest versions and updates them
in-place. No rebuild required. Your container state, SDKs, and config are
preserved.

    sqrbx-update              # show available updates (dry run)
    sqrbx-update --apply      # download and install all updates
    sqrbx-update lazygit      # update a single tool
    sqrbx-update --list       # list all tools and current versions

### Full rebuild (from the host)

    sqrbx-rebuild

Pulls the latest changes, rebuilds the image, and replaces the container.
Your code in ~/squarebox/workspace is safe since it lives on the host.
Setup selections (AI tool, editors, SDKs, GitHub auth) are persisted in the
workspace volume and restored automatically. However, shell history, manually
installed packages, and custom config files inside the container are lost.

#### What survives a rebuild

| Survives | Lost |
|----------|------|
| Code in ~/squarebox/workspace (host volume) | Shell history (~/.bash_history) |
| Starship and lazygit config (host volume) | Manually installed apt packages |
| AI tool / editor / SDK selections | Custom dotfiles in /home/dev/ |
| GitHub CLI auth | Caches and temp files |
| SSH keys (on host, forwarded via agent) | |

To preserve extra files across rebuilds, store them in `/workspace/.squarebox/`.

> **Tip:** Use `sqrbx-update` from inside the container to update tools without
> rebuilding. Only use `sqrbx-rebuild` when the base image itself needs to
> change (new apt packages, new base tools, Dockerfile changes).

Disk usage
----------

The base image (CLI tools only, no optional components) is **~370 MB** on disk.

First-run selections add to that:

| Component | Adds |
|-----------|------|
| Claude Code | ~300 MB |
| GitHub Copilot CLI | ~50 MB |
| Google Gemini CLI | ~50 MB |
| OpenAI Codex CLI | ~50 MB |
| OpenCode | ~30 MB |
| lazygit / gh-dash / yazi | ~10 / ~10 / ~10 MB |
| micro / edit | ~12 / ~7 MB |
| fresh / nvim | ~10 / ~45 MB |
| Node.js | ~90 MB |
| Python (uv) | ~35 MB |
| Go | ~500 MB |
| .NET | ~800 MB |

A typical setup (Claude Code + Node.js + one editor) lands around **~800 MB**.
Sizes are approximate and will vary as tools are updated.

Security
--------

Base image tools are pinned to specific versions and verified against SHA256
checksums when the Docker image is built, so `docker build` is reproducible.

Optional tools selected during first-run setup (editors, TUIs, OpenCode, nvm,
Go, zellij) install the latest upstream release at the time you run setup. The
trust model is the same as running each tool's installer yourself: HTTPS
downloads from the project's official GitHub release (or upstream server). You
get new features without waiting for a squarebox release, at the cost of
build-time pinning for that tier.

Third-party install scripts (Claude Code, uv, .NET) delegate to the vendor
installer. npm-based AI tools (Copilot CLI, Gemini CLI, Codex CLI) use npm's
built-in integrity verification.

For the full trust model (what `install.sh` does on your machine, how each
layer is verified, and how to inspect the script before running it) see
[SECURITY.md](SECURITY.md).

Devcontainer / Codespaces
-------------------------

Open this repo in VS Code with the
[Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers),
or launch it in [GitHub Codespaces](https://github.com/features/codespaces).
The included `.devcontainer/devcontainer.json` builds the full **squarebox** image
automatically.

The interactive first-run setup is skipped in devcontainer mode. To configure
AI tools or SDKs, run `~/setup.sh` from the integrated terminal.

You can also attach to a running codespace directly from your local terminal
using `gh codespace ssh`.

Uninstall
---------

    docker stop squarebox 2>/dev/null; docker rm squarebox
    docker rmi squarebox
    rm -rf ~/squarebox

Then remove the `sqrbx` and `sqrbx-rebuild` aliases from your shell config
(`~/.bashrc`, `~/.zshrc`, or `~/Documents/PowerShell/Microsoft.PowerShell_profile.ps1`).
Back up `~/squarebox/workspace` first if you need your code.

Make it your own
-----------------

**squarebox** is meant to be a starting point, not a finished product. Fork it,
swap out tools, add your own dotfiles, change the theme - build the dev
environment that fits the way you work. The Dockerfile is intentionally
straightforward and the tool registry (`scripts/lib/tools.yaml`) makes it easy
to add or remove tools. Use it as a base, take what's useful, and make it yours.
