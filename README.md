SquareBox
=========

A containerised development environment packed with modern CLI/TUI tools and
AI coding assistants. One install script gives you a ready-to-go terminal
workspace with curated Rust/Go replacements for everyday Unix tools, multiple
AI-powered editors, and sensible defaults.

Built for developers who live in the terminal and want a reproducible, isolated
environment they can spin up on any machine with Docker. Useful as a daily
driver, a sandbox for trying out TUI tools, or a starting point for your own
container-based dev setup.

CLI Tools
---------

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
| [jq](https://github.com/jqlang/jq) | C | JSON processor |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | Rust | Fast recursive grep |
| [starship](https://github.com/starship/starship) | Rust | Cross-shell prompt |
| [xh](https://github.com/ducaale/xh) | Rust | Friendly HTTP client |
| [yq](https://github.com/mikefarah/yq) | Go | YAML/JSON/XML processor |
| [zoxide](https://github.com/ajeetdsouza/zoxide) | Rust | Smarter cd command |

TUI Tools
---------

| Name | Language | Description |
|------|----------|-------------|
| [Claude Code](https://github.com/anthropics/claude-code) | TypeScript | AI coding assistant |
| [opencode](https://github.com/anomalyco/opencode) | Go | AI coding TUI |
| [edit](https://github.com/microsoft/edit) | Rust | Terminal text editor (Microsoft) |
| [fresh](https://github.com/sinelaw/fresh) | Rust | Terminal text editor |
| [gh-dash](https://github.com/dlvhdr/gh-dash) | Go | GitHub dashboard for the terminal |
| [lazygit](https://github.com/jesseduffield/lazygit) | Go | Git terminal UI |
| [yazi](https://github.com/sxyazi/yazi) | Rust | Terminal file manager |

Aliases
-------

Inspired by [Omarchy](https://omarchy.com).

| Alias | Command | Description |
|-------|---------|-------------|
| `ls` | `eza --icons` | Modern ls with icons |
| `ll` | `eza -la --icons` | Long listing with icons |
| `lsa` | `ls -a` | List all including hidden files |
| `lt` | `eza --tree --level=2 --long --icons --git` | Tree view with git status |
| `lta` | `lt -a` | Tree view including hidden files |
| `cat` | `bat --paging=never` | Syntax-highlighted cat |
| `ff` | `fzf --preview 'bat ...'` | Fuzzy find with preview |
| `eff` | `$EDITOR "$(ff)"` | Fuzzy find and edit |
| `..` | `cd ..` | Go up one directory |
| `...` | `cd ../..` | Go up two directories |
| `....` | `cd ../../..` | Go up three directories |
| `c` | `claude` or `opencode` | Launch selected AI assistant |
| `g` | `git` | Git shorthand |
| `gcm` | `git commit -m` | Commit with message |
| `gcam` | `git commit -a -m` | Stage all and commit |
| `gcad` | `git commit -a --amend` | Stage all and amend |
| `lg` | `lazygit` | Launch lazygit |
| `claude-yolo` | `claude --dangerously-skip-permissions` | Claude without prompts |
| `opencode-yolo` | `opencode --dangerously-skip-permissions` | OpenCode without prompts |

Prerequisites
-------------

- [Docker](https://docs.docker.com/get-docker/)
- [Git](https://git-scm.com/)

Install
-------

    curl -fsSL https://raw.githubusercontent.com/BrettKinny/squarebox/main/install.sh | bash

This clones the repo, builds the Docker image, and drops you into the container.
On first login, a setup script runs automatically to configure git, GitHub CLI,
your choice of AI coding assistant, and language SDKs.

SDKs
----

The following SDKs are available during first-run setup:

| SDK | Installed via |
|-----|---------------|
| Node.js | [nvm](https://github.com/nvm-sh/nvm) |
| Python | [uv](https://github.com/astral-sh/uv) |
| Go | [go.dev](https://go.dev) |
| .NET | [dotnet-install](https://dot.net) |

Selections are saved to the workspace volume and reused automatically on
container rebuilds.

Start
-----

    docker start -ai squarebox

When you exit the shell, the container stops but is not removed. All changes inside
the container (installed packages, config files, shell history) persist between
sessions. Think of it as a VM that suspends on exit and resumes on start.

Your code lives on the host at ~/squarebox-workspace and is mounted into the container, so it
is never lost even if the container is deleted.

The install script also adds a `sqrbx` alias to your shell, so after the first
run you can just type `sqrbx` to jump back in.

Security
--------

All binary tools are pinned to specific versions and verified against SHA256
checksums at build time. Third-party install scripts (Claude Code, uv, .NET)
manage their own binary verification.

For the full trust model — what `install.sh` does on your machine, how each
layer is verified, and how to inspect the script before running it — see
[SECURITY.md](SECURITY.md).

How it works
------------

The container is a persistent stopped container, not an ephemeral one. The
difference:

- Ephemeral (`docker run --rm`): container is deleted when you exit. All
  filesystem changes are lost.
- Persistent (what this uses): container stops when you exit but stays on disk.
  `docker start -ai` resumes it with everything intact.

Volume mounts:

- ~/squarebox-workspace -> /workspace: your code (lives on host, survives container deletion)
- ~/.ssh -> /home/dev/.ssh (read-only): SSH keys for git
- ~/.config/git -> /home/dev/.config/git: shared git config

Update
------

There are two ways to update tools, depending on whether you want a quick
in-place update or a full rebuild.

### Quick update (from inside the container)

The `squarebox-update` command checks all GitHub-released tools against latest
versions and updates them in-place — no rebuild required. Your container state,
SDKs, and config are preserved.

    squarebox-update              # show available updates (dry run)
    squarebox-update --apply      # download and install all updates
    squarebox-update lazygit      # update a single tool
    squarebox-update --list       # list all tools and current versions

Set `GITHUB_TOKEN` to avoid API rate limits.

### Full rebuild (from the host)

Pulls the latest changes, rebuilds the image, and replaces the container.
Your code in ~/squarebox-workspace is safe since it lives on the host.
Setup selections (AI tool, SDKs, GitHub auth) are persisted in the workspace
volume and restored automatically.

    sqrbx-update

Or equivalently, re-run the install script:

    ~/squarebox/install.sh

Uninstall
---------

    docker stop squarebox 2>/dev/null; docker rm squarebox
    docker rmi squarebox
    rm -rf ~/squarebox

Remove the aliases from your shell config (~/.bashrc or ~/.zshrc):

    sed -i '/alias sqrbx=/d' ~/.bashrc ~/.zshrc 2>/dev/null
    sed -i '/alias sqrbx-update=/d' ~/.bashrc ~/.zshrc 2>/dev/null

Your code in ~/squarebox-workspace is left untouched. Delete it manually if
you no longer need it.
