# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SquareBox is a containerized development environment (Docker) combining modern CLI/TUI tools with Claude Code. It uses a persistent container model — the container suspends on exit and resumes on restart, preserving state. Workspace code lives on the host at `~/squarebox-workspace` via volume mount.

## Build & Run

```bash
# Build the Docker image
docker build -t squarebox .

# Create and run a new container
docker run -it --name squarebox \
  -v ~/squarebox-workspace:/workspace \
  -v ~/.ssh:/home/dev/.ssh:ro \
  -v ~/.config/git:/home/dev/.config/git \
  squarebox

# Resume an existing container
docker start -ai squarebox
```

The `install.sh` script automates initial setup (clone, build, create container, add `squarebox` shell alias). The `setup.sh` script runs inside the container on first launch to configure git identity and GitHub CLI auth.

## CI

GitHub Actions workflow (`.github/workflows/build.yml`) validates the Dockerfile builds on every push and PR using buildx with GitHub Actions cache.

## Dockerfile Architecture

The Dockerfile (Ubuntu 24.04 base) is organized into sequential stages:

1. **Base packages & Rust CLI tools** — git, curl, ripgrep, bat, fzf, zoxide, fd, etc.
2. **External APT repos** — GitHub CLI, Eza
3. **Binary tool installs** — lazygit, xh, yazi, starship, gh-dash, glow, fresh, edit, opencode (fetched from GitHub releases, architecture-aware for x86_64/aarch64)
4. **User setup** — creates non-root `dev` user with workspace directory
5. **Config files** — git and lazygit configs with delta as default pager
6. **Setup script** — copies `setup.sh` for first-run configuration
7. **Claude Code** — installed via official installer
8. **Shell config** — bashrc with starship prompt, zoxide, aliases

Tools are fetched at build time by querying GitHub APIs for latest releases (no hardcoded versions for most tools). Each binary install follows the pattern: detect architecture, fetch release URL via GitHub API, download, extract to temp dir, move binary to `/usr/local/bin`, clean up.
