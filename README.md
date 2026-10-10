# 🟧📦 squarebox

**Modern CLI/TUI tools and AI coding assistants in a portable development Box.**

Run the same terminal environment on your desktop, server, or Codespace.
One-line install, interactive setup, and persistent tools and settings.

![squarebox first-run setup](demo/squarebox-setup.gif)

Install
-------

Requires [Docker](https://docs.docker.com/get-docker/) or
[Podman](https://podman.io/getting-started/installation), plus
[Git](https://git-scm.com/) ([Git for Windows](https://gitforwindows.org/)).
The installer detects your runtime and asks which to use if both are installed.
[Need Docker?](docs/usage.md#installing-docker)

**Linux / macOS / Git Bash**

```bash
curl -fsSL https://github.com/SquareWaveSystems/squarebox/releases/latest/download/install.sh | bash
```

**Windows (PowerShell 7+)**

```powershell
irm https://github.com/SquareWaveSystems/squarebox/releases/latest/download/install.ps1 | iex
```

The installer pulls the latest stable Release and sets up `~/squarebox`.
First login runs a wizard for Git identity, GitHub sign-in, and optional tools.
Keep using the same adapter (Bash/Git Bash or PowerShell) for updates and uninstall.

For edge builds, custom paths, scripted setup, or Windows flags, see the
[usage reference](docs/usage.md#advanced-installation).
Upgrading? Check the [migration guides](docs/releases/) and [changelog](CHANGELOG.md).

Start
-----

```bash
squarebox        # or: sqrbx
```

Your code lives in `~/squarebox/workspace`, mounted at `/workspace`.
Shell history, credentials, assistant data, and SDKs live in the persistent
`squarebox-home` volume. Both survive Box replacement. Selected system packages
are reinstalled automatically; manually installed system packages are lost.

For a persistent server or NAS, see [server deployment](docs/usage.md#server-deployment).
For VS Code or GitHub Codespaces, see [Dev Containers and Codespaces](docs/usage.md#dev-containers-and-codespaces).

What's included
---------------

### CLI Tools

| Name | Description |
|------|-------------|
| [bat](https://github.com/sharkdp/bat) | Cat clone with syntax highlighting |
| [bubblewrap](https://github.com/containers/bubblewrap) | Unprivileged sandboxing tool (`bwrap`), used by the Codex CLI sandbox |
| [curl](https://github.com/curl/curl) | URL data transfer |
| [delta](https://github.com/dandavison/delta) | Syntax-highlighting pager for git diffs |
| [difftastic](https://github.com/Wilfred/difftastic) | Syntax-aware structural diff tool (`difft`) |
| [eza](https://github.com/eza-community/eza) | Modern ls replacement |
| [fd](https://github.com/sharkdp/fd) | Fast, user-friendly find alternative |
| [fzf](https://github.com/junegunn/fzf) | Fuzzy finder |
| [gh](https://github.com/cli/cli) | GitHub CLI |
| [glow](https://github.com/charmbracelet/glow) | Terminal markdown renderer |
| [gum](https://github.com/charmbracelet/gum) | Tool for shell scripts and dotfiles |
| [jq](https://github.com/jqlang/jq) | JSON processor |
| [just](https://github.com/casey/just) | Command runner / modern make alternative |
| [mise](https://github.com/jdx/mise) | Polyglot tool-version and SDK manager |
| [nano](https://nano-editor.org) | Default text editor |
| [ripgrep](https://github.com/BurntSushi/ripgrep) | Fast recursive grep |
| [starship](https://github.com/starship/starship) | Cross-shell prompt |
| [xh](https://github.com/ducaale/xh) | Friendly HTTP client |
| [yq](https://github.com/mikefarah/yq) | YAML/JSON/XML processor |
| [zoxide](https://github.com/ajeetdsouza/zoxide) | Smarter cd command |

What's optional
----------------

Choose any combination during first-run setup. Your selections are saved and
reused on rebuilds; change them anytime with `sqrbx-setup`.

### AI Coding Assistants

| Name | Description |
|------|-------------|
| [Claude Code](https://github.com/anthropics/claude-code) | AI coding assistant |
| [GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/cli-getting-started) | Supported GitHub Copilot terminal client (`copilot`) * |
| [Google Gemini CLI](https://github.com/google-gemini/gemini-cli) | Google Gemini in the terminal * |
| [OpenAI Codex CLI](https://github.com/openai/codex) | OpenAI Codex in the terminal * |
| [opencode](https://github.com/anomalyco/opencode) | AI coding TUI |
| [Pi Coding Agent](https://github.com/earendil-works/pi) | Minimal terminal coding harness (Earendil) * |
| [Oh My Pi](https://github.com/can1357/oh-my-pi) | Batteries-included coding harness (`omp`), installed via mise |

\* Requires Node.js (auto-installed if needed).

### Text Editors

Nano is always available and remains the fallback default unless you choose an
installed editor instead.

| Name | Description |
|------|-------------|
| [micro](https://github.com/micro-editor/micro) | Modern, intuitive terminal editor |
| [edit](https://github.com/microsoft/edit) | Terminal text editor (Microsoft) |
| [fresh](https://github.com/sinelaw/fresh) | Modern terminal text editor |
| [helix](https://github.com/helix-editor/helix) | Modal editor (Kakoune-inspired) |
| [nvim](https://github.com/neovim/neovim) | Neovim |

Selecting **nvim** offers a [LazyVim](https://www.lazyvim.org/) starter config.
Existing Neovim configuration is preserved. See [editor configuration](docs/usage.md#editor-configuration).

### TUI Tools

| Name | Description |
|------|-------------|
| [lazygit](https://github.com/jesseduffield/lazygit) | Git terminal UI |
| [gh-dash](https://github.com/dlvhdr/gh-dash) | GitHub dashboard for the terminal |
| [yazi](https://github.com/sxyazi/yazi) | Terminal file manager |
| [elio](https://github.com/elio-fm/elio) | Terminal file manager with rich previews, inline images, and trash support |

### Terminal Multiplexers

| Name | Description |
|------|-------------|
| [tmux](https://github.com/tmux/tmux) | Classic terminal multiplexer |
| [zellij](https://github.com/zellij-org/zellij) | Friendly terminal workspace |
| [herdr](https://herdr.dev) | Agent multiplexer — run multiple coding agents from one terminal |

### Shells and SDKs

Bash is the default shell; choose Zsh, Fish, or PowerShell during setup.
Node.js, Python, Go, .NET, and Rust are available through
[mise](https://github.com/jdx/mise).
See [shell configuration](docs/usage.md#shell-configuration) and
[SDK configuration](docs/usage.md#sdk-configuration).

Everyday commands
-----------------

Run these inside the Box:

```bash
sqrbx-help               # commands and navigation shortcuts
sqrbx-setup              # rerun the setup wizard
sqrbx-setup ai editors   # reconfigure specific sections
sqrbx-setup --list       # show your selections
sqrbx-update             # check for tool updates
sqrbx-update --apply     # update installed registered tools
sqrbx-update lazygit     # update or install one named tool
```

From the host, run `sqrbx-rebuild` to update the Box itself. This keeps your
workspace and persistent home, and reuses your installation settings.
Some bundled tools require a rebuild to update.

See the [aliases](docs/usage.md#aliases),
[keyboard shortcuts](docs/usage.md#keyboard-shortcuts), and
[update details](docs/usage.md#updates-and-rebuilds).

Uninstall
---------

From the host:

```bash
sqrbx-uninstall
```

This removes the Box and shell integration, keeping your workspace and
persistent home. `sqrbx-uninstall --purge` (PowerShell: `-Purge`) also removes
the persistent home and install directory, **including a workspace inside it**.
A custom external workspace is preserved.
See [uninstall options and recovery](docs/usage.md#uninstall-and-recovery).

Security
--------

The Box is a development environment with access to your mounted files and
credentials. SSH-directory mounts require explicit opt-in.
See [SECURITY.md](SECURITY.md) for SSH access, the trust model, artifact
verification, and vulnerability reporting.

Make it your own
----------------

Fork it, swap tools, or add your own dotfiles. The [Dockerfile](Dockerfile) and
[tool registry](scripts/lib/tools.yaml) define what's included.
