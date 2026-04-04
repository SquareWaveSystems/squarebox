# Security

## What `install.sh` does on your machine

Before piping anything to bash, you should know exactly what it does. The
install script performs these actions on your **host** system:

1. Clones this repo to `~/tui-devbox` (or pulls if it already exists)
2. Creates `~/tui-devbox-workspace` and `~/.config/git` directories
3. Builds a Docker image tagged `devbox` from the Dockerfile
4. Creates a Docker container named `devbox` with volume mounts for your
   workspace (`~/tui-devbox-workspace`), SSH keys (`~/.ssh`, read-only),
   and git config (`~/.config/git`)
5. Appends two shell aliases (`devbox`, `devbox-update`) to your `~/.bashrc`
   or `~/.zshrc`
6. Starts the container interactively

It does **not** use `sudo`, install system packages, or modify anything outside
your home directory.

## Verify before running

If you prefer to inspect the script before running it:

```bash
curl -fsSL https://raw.githubusercontent.com/BrettKinny/tui-devbox/main/install.sh -o install.sh
less install.sh        # read it
bash install.sh        # run it
```

## Trust model

Running `curl | bash` trusts that GitHub serves the authentic file over HTTPS.
Beyond that initial step, the project uses different verification strategies
at each layer:

| Layer | What's fetched | Transport | Integrity check | Version pinned? |
|-------|---------------|-----------|-----------------|-----------------|
| **install.sh** | Git repo from GitHub | HTTPS | Git transport verification | Tracks `main` branch |
| **Dockerfile — APT packages** | Ubuntu 24.04 packages, GitHub CLI, Eza | HTTPS | APT GPG signatures | Distro versions (not pinned) |
| **Dockerfile — binary tools** | 10 tools from GitHub Releases (delta, lazygit, starship, etc.) | HTTPS | SHA256 checksum — build fails on mismatch | Yes, all pinned |
| **setup.sh — SDKs with checksums** | OpenCode, nvm, Go | HTTPS | SHA256 checksum | Yes, all pinned |
| **setup.sh — third-party installers** | Claude Code, uv, .NET | HTTPS | Delegates to vendor installer | No (latest/LTS) |

**What this means in practice:**

- The Dockerfile binary tools have the strongest guarantees — pinned versions
  with SHA256 checksums covering both x86_64 and aarch64. A compromised release
  or man-in-the-middle attack causes the build to fail immediately.
- Third-party install scripts (Claude Code from Anthropic, uv from Astral, .NET
  from Microsoft) manage their own binary verification. We trust these vendors'
  HTTPS endpoints and their installers' built-in integrity checks.
- APT packages are verified by Ubuntu's and each repo's GPG signatures.

## Binary integrity

Checksums are maintained in `checksums.txt` (Dockerfile tools) and
`setup-checksums.txt` (setup.sh tools), covering both x86_64 and aarch64
architectures. To update all tool versions and recompute checksums:

```bash
./scripts/update-versions.sh
```
