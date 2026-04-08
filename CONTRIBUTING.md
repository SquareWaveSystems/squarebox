# Contributing

Thanks for your interest in squarebox! This guide covers the basics of building,
testing, and submitting changes.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) (with buildx)
- [Git](https://git-scm.com/)
- Bash shell

## Build

```bash
docker build -t squarebox .
```

The build verifies all binary downloads against SHA256 checksums in
`checksums.txt`. If a checksum doesn't match, the build fails immediately.

## Test

CI runs automatically on every push and PR via GitHub Actions
(`.github/workflows/build.yml`). The workflow:

1. Builds the Docker image
2. Verifies all tools are installed
3. Checks that shell config loads without errors
4. Validates aliases resolve to the correct binaries
5. Tests container stop/start persistence
6. Validates devcontainer JSON

To run a quick local smoke test:

```bash
docker build -t squarebox:test .
docker run --rm squarebox:test bash -c '
  for cmd in bat curl delta eza fd fzf gh gh-dash glow gum jq lazygit nano rg starship xh yazi yq zoxide; do
    which "$cmd" || { echo "MISSING: $cmd"; exit 1; }
  done
  echo "All tools present"
'
```

## Project structure

| File | Purpose |
|------|---------|
| `Dockerfile` | Image definition with pinned tool versions |
| `setup.sh` | First-run interactive setup (AI tools, editors, SDKs) |
| `install.sh` | Host-side install script (clone, build, create container) |
| `scripts/squarebox-update.sh` | In-container tool updater (`sqrbx-update`) |
| `scripts/update-versions.sh` | Fetches latest releases and updates checksums |
| `checksums.txt` | SHA256 checksums for Dockerfile binary tools |
| `setup-checksums.txt` | SHA256 checksums for setup.sh tools |

## Making changes

1. Fork and clone the repo.
2. Create a feature branch: `git checkout -b my-change`
3. Make your changes.
4. Build and test locally (see above).
5. Commit with a clear message describing *why*, not just *what*.
6. Open a pull request against `main`.

### Adding or updating a tool

If you're adding a new binary tool or bumping a version:

1. Run `./scripts/update-versions.sh` to fetch latest versions and checksums.
2. Review the diff — verify version bumps and checksums look correct.
3. Rebuild and test.

Tool versions are pinned via `ARG` directives in the Dockerfile and verified
against `checksums.txt`. Never skip checksum verification.

### Style

- Shell scripts use `set -euo pipefail`.
- Indent with 2 spaces in shell scripts and config files.
- Keep Dockerfile layers logical and commented.

## Pull requests

- Keep PRs focused — one logical change per PR.
- Include a short description of what changed and why.
- Make sure CI passes before requesting review.

## Reporting issues

Open an issue on GitHub with steps to reproduce. Include your architecture
(x86_64 or aarch64) and Docker version if relevant.
