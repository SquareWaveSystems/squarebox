# Similar Projects Research

Research into projects with overlapping goals to squarebox — containerized dev environments, curated CLI tool bundles, AI coding assistant integrations, and opinionated developer setups.

---

## Category 1: Containerized Claude Code / AI Coding Environments

These are the most directly comparable projects — Docker environments built specifically around AI coding assistants.

### RchGrav/claudebox
- **URL:** https://github.com/RchGrav/claudebox
- **Description:** "The Ultimate Claude Code Docker Development Environment" — runs Claude AI's coding assistant in a fully containerized, reproducible environment with pre-configured development profiles.
- **Key features:** Multiple dev profiles (Python+ML, C/C++, Rust+Go), persistent project data (auth state, shell history, tool configs), simultaneous multi-project instances.
- **Similarity:** Very close — Docker-based, persistent containers, Claude Code integration, reproducible environment.
- **Difference:** Focused primarily on Claude Code rather than being tool-agnostic; offers language-specific profiles rather than interactive SDK selection.

### nezhar/claude-container
- **URL:** https://github.com/nezhar/claude-container
- **Description:** Container workflow for Claude Code with complete isolation from the host system while maintaining persistent credentials and workspace access.
- **Key features:** Stores credentials in `$HOME/.config/claude-container`, reuses them after first login, credentials persist across container restarts.
- **Similarity:** Docker + Claude Code + persistence model.
- **Difference:** Minimal — focused solely on running Claude Code in a container, not a full dev environment with curated tools.

### trailofbits/claude-code-devcontainer
- **URL:** https://github.com/trailofbits/claude-code-devcontainer
- **Description:** Sandboxed devcontainer for running Claude Code in bypass mode safely. Built for security audits and untrusted code review.
- **Key features:** Security-focused, network firewall rules, designed for audit contexts.
- **Similarity:** Devcontainer-based Claude Code environment.
- **Difference:** Security/audit-focused rather than general-purpose dev environment; no curated CLI tools.

### centminmod/claude-code-devcontainers
- **URL:** https://github.com/centminmod/claude-code-devcontainers
- **Description:** Claude Code devcontainers with three-layer security including network firewall and persistent configurations.
- **Key features:** Persistent CLI configs across rebuilds, security layers, multiple language support.
- **Similarity:** Devcontainer + Claude Code + persistence.
- **Difference:** More security-focused; less emphasis on curated modern CLI tools.

### koogle/claudebox
- **URL:** https://github.com/koogle/claudebox
- **Description:** Run Claude Code in a container.
- **Similarity:** Docker + Claude Code.
- **Difference:** Simpler scope, container wrapper rather than full environment.

---

## Category 2: AI Agent Development Environments

These projects set up complete environments for AI-assisted coding workflows.

### runpod/lazy-agent
- **URL:** https://github.com/runpod/lazy-agent
- **Description:** "Like LazyVim, but for terminal-based AI agent workflows." Get a beautiful, productive terminal setup in minutes.
- **Key features:** Interactive setup.sh wizard, dotfiles for tmux/ghostty, step-by-step guides, designed for Claude Code and other AI CLIs.
- **Similarity:** Very close — interactive setup, modern terminal tools, AI coding assistant support, opinionated defaults.
- **Difference:** Not containerized (installs directly on host); more focused on Neovim/LazyVim as the primary editor.

### Dicklesworthstone/agentic_coding_flywheel_setup
- **URL:** https://github.com/Dicklesworthstone/agentic_coding_flywheel_setup
- **Description:** Bootstraps a fresh Ubuntu VPS into a complete multi-agent AI development environment in 30 minutes.
- **Key features:** Multi-agent coordination, lazygit, atuin, zoxide, direnv, fzf configs, session management, safety tools.
- **Similarity:** Ubuntu-based, modern CLI tools, AI coding assistants, automated setup.
- **Difference:** Targets VPS provisioning rather than Docker containers; focused on multi-agent orchestration.

---

## Category 3: Dockerized Developer Environments with Modern CLI Tools

These bundle modern terminal tools in containers but may not include AI assistants.

### AmoxcalliDev/Lazy-Docker
- **URL:** https://github.com/AmoxcalliDev/Lazy-Docker
- **Description:** "Instant professional development environment in a container." 40+ developer tools including git, lazygit, tmux, python, node.js.
- **Key features:** Pre-configured LazyVim, 40+ tools, persistent storage via Docker volumes, automatic initialization.
- **Similarity:** Docker container, modern tools bundle, persistent state, instant setup.
- **Difference:** Centered on LazyVim/Neovim; no AI assistant integration; no interactive setup wizard.

### cmorenop1/lazyvim (Docker)
- **URL:** https://github.com/cmorenop1/lazyvim
- **Description:** LazyVim Docker image with lazygit, git-delta, fd-find, ripgrep, tree-sitter-cli, fzf.
- **Key features:** Persistent storage via Docker volumes, automatic initialization.
- **Similarity:** Docker + modern CLI tools + persistent storage.
- **Difference:** Neovim-centric; smaller tool set; no AI assistant support.

### ContainerCraft/devcontainer
- **URL:** https://github.com/ContainerCraft/devcontainer
- **Description:** Cloud Dev & Ops Devcontainer with custom shell, Starship prompt, and tmux session management.
- **Key features:** Starship prompt, tmux, shell utilities and aliases pre-configured.
- **Similarity:** Devcontainer with Starship prompt and pre-configured shell environment.
- **Difference:** Cloud/ops focused rather than general development; no AI tools.

### dbushell/docker-ubuntu
- **URL:** https://github.com/dbushell/docker-ubuntu
- **Description:** A configured Ubuntu sandbox development container with Zsh, Starship, Vim, Git, Deno, Bun, Node.
- **Similarity:** Ubuntu container + Starship + development tools.
- **Difference:** Simpler scope; Zsh-based; fewer tools; no AI integration.

---

## Category 4: Opinionated Developer Setup Systems (Non-Docker)

These aren't containerized but share the philosophy of curated, opinionated tool bundles.

### basecamp/omarchy
- **URL:** https://github.com/basecamp/omarchy
- **Description:** "Beautiful, Modern & Opinionated Linux" by DHH (David Heinemeier Hansson). Turns a fresh Arch Linux into a fully-configured web development system.
- **Key features:** Neovim, Docker, lazygit, GitHub CLI, multiple editor options (VSCode, Cursor, Zed, Helix), opinionated defaults.
- **Similarity:** Very similar philosophy — opinionated, curated modern tools, interactive setup, multiple editor choices. Squarebox's alias conventions are inspired by Omarchy.
- **Difference:** Full Linux distro setup (Arch + Hyprland) rather than a Docker container; not portable across OSes; no AI assistant integration.

### basecamp/omakub
- **URL:** https://omakub.org/
- **Description:** "An Omakase Developer Setup for Ubuntu 24.04+" by DHH. The predecessor to Omarchy.
- **Key features:** Same curated philosophy applied to Ubuntu, one-command setup.
- **Similarity:** Ubuntu-based, opinionated tool selection, interactive setup.
- **Difference:** Installs directly on Ubuntu host; no containerization; no AI tools.

### lavantien/dotfiles
- **URL:** https://github.com/lavantien/dotfiles
- **Description:** Universal SWE Dotfiles (Neovim/Wezterm/zsh/pwsh, Claude Code/Git Hooks, Linux/Windows) — Battery Included.
- **Key features:** 40+ CLI tools (fzf, yazi, zoxide, bat, eza, lazygit, gh, ripgrep, fd), Claude Code integration, cross-platform.
- **Similarity:** Modern CLI tools + Claude Code + opinionated defaults.
- **Difference:** Dotfiles repo (not containerized); cross-platform rather than Docker.

### deepusharma/dotfiles
- **URL:** https://github.com/deepusharma/dotfiles
- **Description:** Cross-platform terminal setup — Alacritty, Zsh, Zellij, Starship, lazygit, uv, full CLI suite. One script installs everything.
- **Key features:** Starship, lazygit, modern CLI tools, one-script install.
- **Similarity:** Curated modern tools, automated setup, Starship prompt.
- **Difference:** Not containerized; cross-platform dotfiles.

---

## Category 5: Cloud/Self-Hosted Development Environments

Larger-scale platforms that solve a similar problem at organizational scale.

### Jetify/Devbox
- **URL:** https://www.jetify.com/devbox
- **Description:** Portable, isolated dev environments using Nix. No Docker or VMs required.
- **Key features:** Nix-based reproducibility, per-project isolation, shell environments.
- **Similarity:** Isolated, reproducible dev environments with curated tool selection.
- **Difference:** Nix-based (not Docker); no AI tools; focused on package management rather than full environment.

### devenv.sh
- **URL:** https://devenv.sh/
- **Description:** Fast, declarative, reproducible, and composable developer environments using Nix.
- **Key features:** Nix-powered, declarative configuration, composable.
- **Similarity:** Reproducible dev environments.
- **Difference:** Nix-based; declarative config rather than interactive setup; no bundled tools or AI assistants.

### loft-sh/devpod
- **URL:** https://github.com/loft-sh/devpod
- **Description:** Client-only, open-source tool for creating reproducible dev environments. No server-side setup needed.
- **Key features:** Works with any infrastructure (cloud, local, Kubernetes), devcontainer.json compatible.
- **Similarity:** Reproducible dev environments, devcontainer support.
- **Difference:** Infrastructure orchestrator rather than an opinionated tool bundle; no curated CLI tools.

### coder/coder
- **URL:** https://github.com/coder/coder
- **Description:** Open-source, self-hosted platform for deploying developer environments anywhere.
- **Key features:** Terraform-based provisioning, enterprise-focused, multi-cloud.
- **Similarity:** Containerized dev environments with persistence.
- **Difference:** Enterprise platform, not a personal dev environment; no opinionated tool selection.

---

## Category 6: Dev Container Ecosystem

Standards and tools that squarebox builds upon.

### devcontainers/spec
- **URL:** https://github.com/devcontainers/spec
- **Description:** The official Development Containers specification.
- **Similarity:** Squarebox includes a devcontainer.json for compatibility.
- **Difference:** A specification, not an implementation.

### manekinekko/awesome-devcontainers
- **URL:** https://github.com/manekinekko/awesome-devcontainers
- **Description:** Curated list of awesome devcontainer tools and resources.
- **Relevance:** Good reference for the devcontainer ecosystem squarebox participates in.

---

## Competitive Landscape Summary

| Feature | squarebox | claudebox | lazy-agent | Lazy-Docker | omarchy | Devbox |
|---|---|---|---|---|---|---|
| Docker-based | Yes | Yes | No | Yes | No | No |
| Persistent containers | Yes | Yes | N/A | Yes | N/A | N/A |
| AI assistants (multi) | Yes (5) | Claude only | Claude + others | No | No | No |
| Interactive setup | Yes | No | Yes | No | Yes | No |
| Modern CLI tools | Yes (20+) | Minimal | Yes | Yes (40+) | Yes | Per-project |
| Optional SDKs | Yes (4) | By profile | No | Partial | Partial | Via Nix |
| Checksum verification | Yes | No | No | No | N/A | Via Nix |
| Multi-arch (amd64+arm64) | Yes | Partial | N/A | Partial | N/A | Yes |
| In-place updates | Yes (sqrbx-update) | No | No | No | Yes | Yes |

### What makes squarebox unique:
1. **Multi-AI-assistant support** — lets users pick any combination of 5 AI coding tools
2. **Interactive first-run wizard** — guided setup for Git, GitHub, AI tools, editors, and SDKs
3. **Persistent container + volume mount model** — state survives restarts, code survives deletion
4. **SHA256 checksum verification** — every binary is pinned and verified at build, install, and update time
5. **In-place tool updates** — `sqrbx-update` updates binaries without rebuilding the container
6. **Clean tool registry architecture** — single YAML source of truth with shared shell library

---

*Research conducted April 2026*
