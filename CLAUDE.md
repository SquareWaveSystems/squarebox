# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SquareBox is a containerized development environment (Docker) combining modern CLI/TUI tools with Claude Code. It uses a persistent container model — the container suspends on exit and resumes on restart, preserving state. Workspace code lives on the host at `~/squarebox/workspace` via volume mount.

## Build & Run

```bash
# Build the Docker image
docker build -t squarebox .

# Create and run a new container
docker run -it --name squarebox \
  -v ~/squarebox/workspace:/workspace \
  -v ~/.ssh:/home/dev/.ssh:ro \
  -v ~/.config/git:/home/dev/.config/git \
  -v ~/squarebox/.config/starship.toml:/home/dev/.config/starship.toml \
  -v ~/squarebox/.config/lazygit:/home/dev/.config/lazygit \
  squarebox

# Resume an existing container
docker start -ai squarebox
```

The `install.sh` script automates initial setup (clone, build, create container, add `sqrbx` shell alias). A `.devcontainer/devcontainer.json` is also provided for VS Code Dev Containers / Codespaces.

## First-Run Setup

`setup.sh` runs automatically on first container launch and prompts for:

1. **Git identity** — name and email (skipped if already configured)
2. **GitHub CLI auth** — persisted to `/workspace/.squarebox/gh` across rebuilds
3. **AI coding assistant** — Claude Code, OpenCode, or both
4. **Text editors** — micro, edit (Microsoft), fresh, helix, nvim (nano is always available)
5. **SDKs** — Node.js (via nvm), Python (via uv), Go, .NET

Selections are saved to `/workspace/.squarebox/` and reused on subsequent rebuilds.

## Updating Tool Versions

```bash
# Update all pinned versions, checksums, Dockerfile ARGs, and setup.sh versions
scripts/update-versions.sh

# Inside a running container, pull latest repo changes and rebuild
sqrbx-update
```

`scripts/update-versions.sh` fetches latest GitHub releases, downloads artifacts for both architectures, computes SHA256 checksums, and updates `checksums.txt`, `setup-checksums.txt`, `Dockerfile`, and `setup.sh`. Set `GITHUB_TOKEN` to avoid API rate limits.

## CI

GitHub Actions workflow (`.github/workflows/build.yml`) validates the Dockerfile builds on every push and PR using buildx with GitHub Actions cache.

## Dockerfile Architecture

The Dockerfile (Ubuntu 24.04 base) is organized into sequential stages:

1. **Base packages** — git, curl, ripgrep, bat, fzf, zoxide, fd, etc. via apt
2. **External APT repos + binary tools** — GitHub CLI, Eza via apt; delta and yq via direct download
3. **Binary tool installs** (split into 3a/3b/3c layers):
   - **3a Git tools** — lazygit, gh-dash
   - **3b File & HTTP tools** — xh, yazi, glow
   - **3c Shell tools** — starship
4. **User setup** — creates non-root `dev` user with workspace directory
5. **Config files** — git and lazygit configs with delta as default pager
6. **Setup script & configs** — copies `setup.sh`, `sqrbx-update`, starship.toml
7. **Shell config** — bashrc with starship prompt, zoxide, aliases

All tool versions are pinned via Dockerfile `ARG` directives and verified against SHA256 checksums in `checksums.txt`. Tools installed during `setup.sh` (AI assistants, editors, SDKs) use a separate `setup-checksums.txt`. Each binary install detects architecture (x86_64/aarch64), downloads, verifies checksum, extracts, and installs.
