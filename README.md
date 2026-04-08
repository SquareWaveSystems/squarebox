# 🟧📦 squarebox

**Containerised dev environment packed with modern CLI/TUI tools and AI coding assistants. Batteries included.**

Curated Rust/Go replacements for everyday Unix tools, multiple AI-powered
editors, and sensible defaults, all in a reproducible Docker container you can
spin up on any machine.

![squarebox first-run setup](https://raw.githubusercontent.com/SquareWaveSystems/squarebox/demo/demo/squarebox-setup.gif)
*Actual setup may involve more staring at the screen.*

Prerequisites
-------------

- [Docker](https://docs.docker.com/get-docker/)
- [Git](https://git-scm.com/) - on Windows, install [Git for Windows](https://gitforwindows.org/)
  (provides `bash` and `winpty` needed by the install script)

Install
-------

    curl -fsSL https://raw.githubusercontent.com/SquareWaveSystems/squarebox/main/install.sh | bash

This clones the repo, builds the Docker image, and drops you into the container.
On first login, a setup script runs automatically to configure git, GitHub CLI,
your choice of AI coding assistant, and language SDKs.

Start
-----

    squarebox        # or: sqrbx

Shell aliases are added automatically for Bash, Zsh, and PowerShell 7+.

The container is persistent: it suspends on exit and resumes on start, keeping
installed packages, config, and shell history intact between sessions. Your code
lives on the host at `~/squarebox/workspace` via volume mount, so it survives
even if the container is deleted.

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

### TUI Tools

| Name | Language | Description |
|------|----------|-------------|
| [gh-dash](https://github.com/dlvhdr/gh-dash) | Go | GitHub dashboard for the terminal |
| [lazygit](https://github.com/jesseduffield/lazygit) | Go | Git terminal UI |
| [yazi](https://github.com/sxyazi/yazi) | Rust | Terminal file manager |

### AI Coding Assistants (optional)

Installed during first-run setup. Choose any combination:

| Name | Language | Description |
|------|----------|-------------|
| [Claude Code](https://github.com/anthropics/claude-code) | TypeScript | AI coding assistant |
| [GitHub Copilot CLI](https://github.com/githubnext/github-copilot-cli) | TypeScript | GitHub Copilot in the terminal * |
| [Google Gemini CLI](https://github.com/google-gemini/gemini-cli) | TypeScript | Google Gemini in the terminal * |
| [OpenAI Codex CLI](https://github.com/openai/codex) | TypeScript | OpenAI Codex in the terminal * |
| [opencode](https://github.com/anomalyco/opencode) | Go | AI coding TUI |

\* Requires Node.js (auto-installed if needed).

### Text Editors (optional)

Installed during first-run setup. Nano is always available as the default editor.

| Name | Language | Description |
|------|----------|-------------|
| [micro](https://github.com/micro-editor/micro) | Go | Modern, intuitive terminal editor |
| [edit](https://github.com/microsoft/edit) | Rust | Terminal text editor (Microsoft) |
| [fresh](https://github.com/sinelaw/fresh) | Rust | Modern terminal text editor |
| [helix](https://github.com/helix-editor/helix) | Rust | Modal editor (Kakoune-inspired) — *coming soon* |
| [nvim](https://github.com/neovim/neovim) | C/Lua | Neovim |

### Aliases

Inspired by [Omarchy](https://omarchy.org).

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
| `lg` | `lazygit` | Launch lazygit |
| `claude-yolo` | `claude --dangerously-skip-permissions` | Claude without prompts |
| `opencode-yolo` | `opencode --dangerously-skip-permissions` | OpenCode without prompts |

### SDKs (optional)

Selected during first-run setup. Choose any combination, all, or none:

| SDK | Installed via |
|-----|---------------|
| Node.js | [nvm](https://github.com/nvm-sh/nvm) |
| Python | [uv](https://github.com/astral-sh/uv) |
| Go | [go.dev](https://go.dev) |
| .NET | [dotnet-install](https://dot.net) |

Selections are saved to the workspace volume and reused automatically on
container rebuilds.

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

Set `GITHUB_TOKEN` to avoid API rate limits.

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
| SSH keys (read-only mount from host) | |

To preserve extra files across rebuilds, store them in `/workspace/.squarebox/`.

> **Tip:** Use `sqrbx-update` from inside the container to update tools without
> rebuilding. Only use `sqrbx-rebuild` when the base image itself needs to
> change (new apt packages, new base tools, Dockerfile changes).

Disk usage
----------

The base image (all CLI/TUI tools, no optional components) is **~400 MB** on disk.

First-run selections add to that:

| Component | Adds |
|-----------|------|
| Claude Code | ~300 MB |
| GitHub Copilot CLI | ~50 MB |
| Google Gemini CLI | ~50 MB |
| OpenAI Codex CLI | ~50 MB |
| OpenCode | ~30 MB |
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

All binary tools are pinned to specific versions and verified against SHA256
checksums at build time. Third-party install scripts (Claude Code, uv, .NET)
manage their own binary verification. npm-based AI tools (Copilot CLI, Gemini
CLI, Codex CLI) use npm's built-in integrity verification.

For the full trust model (what `install.sh` does on your machine, how each
layer is verified, and how to inspect the script before running it) see
[SECURITY.md](SECURITY.md).

Devcontainer / Codespaces
-------------------------

Open this repo in VS Code with the
[Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers),
or launch it in [GitHub Codespaces](https://github.com/features/codespaces).
The included `.devcontainer/devcontainer.json` builds the full squarebox image
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
