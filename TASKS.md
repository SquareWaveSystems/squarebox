# TASKS

Items are ordered by priority within each section. Sections are ordered by priority.

## P0 — Pre-release blockers

- [x] **Pin all binary versions and add SHA256 checksum verification** for every download in Dockerfile and setup.sh
- [x] **Audit and document the trust model for `curl | bash` install path** — users piping install.sh into their shell need to understand what it does; mitigate MITM and compromised-repo risks
- [x] **Add a LICENSE file** — without one, the project is legally "all rights reserved" and nobody can use it. MIT or Apache-2.0.
- [x] **Fix install URL case mismatch** — not a real issue; GitHub raw URLs and git clone URLs are case-insensitive for repo names. Both `squarebox` and `SquareBox` resolve identically.
- [x] **Remove `/usr/local/bin` ownership by dev user** (Dockerfile line ~151) — `chown dev:dev /usr/local/bin` lets any code in the container replace system binaries. Use `sudo` in `sqrbx-update` or install user-updatable tools to `~/.local/bin` instead.
- [x] **Add checksum verification to `sqrbx-update`** — Dockerfile and setup.sh verify SHA256 checksums, but `squarebox-update.sh` downloads and installs binaries with zero integrity checking. Conspicuous gap in a project that emphasizes supply-chain security.
- [ ] **Remove TASKS.md from the public repo before v1** — internal backlog with unchecked TODOs and commentary about gaps signals "unfinished." Move to GitHub Issues or a project board.

## P1 — Reliability

- [x] **Validate version variables are non-empty** before using them in download URLs (Dockerfile lines 50-90, setup.sh SDK installs) — empty vars silently produce broken binaries
- [x] **Handle GitHub API rate limiting** (60 req/hr unauthenticated) — fail fast with a clear message instead of silently continuing; pass `GITHUB_TOKEN` header on GitHub API calls when available
- [x] **Verify SDK install success** before continuing (e.g. check `nvm install --lts` exit code, verify binaries exist)
- [x] Add cleanup trap in setup.sh to remove temp files on failure
- [x] Handle partial setup failure — clean up half-configured state so retries work cleanly
- [x] **Guard gh config persistence on auth failure** — `setup.sh` lines 71-72 copy `~/.config/gh/*` unconditionally after `gh auth login`. If the user cancels, this errors out and kills the entire setup script due to `set -e`. Wrap in `gh auth status` check.
- [x] **Fix delta install fallback in `sqrbx-update`** — `sudo dpkg -i ... 2>/dev/null || dpkg -i ...` swallows the real error and the non-sudo fallback also fails. Emit a clear error instead.
- [x] **Clean up temp dirs on failure in `sqrbx-update`** — each `*_install` function creates `mktemp -d` but never cleans up on error. Add trap or explicit cleanup.
- [x] **Use `mktemp` for `sqrbx-update` log file** — currently writes to predictable `/tmp/sqrbx-update-log.txt`.

## P1 — install.sh

- [x] **Fix shell detection** — use `$SHELL` instead of checking if `~/.zshrc` exists (currently writes aliases to wrong file for bash users with a stale .zshrc)
- [x] **Make alias injection idempotent** — check if aliases already exist before appending to shell RC file
- [x] Document (or mitigate) that `sqrbx-rebuild` destroys the container and loses in-container state (shell history, manually installed packages, custom dotfiles)

## P1 — Documentation fixes

- [x] **Fix SECURITY.md wrong alias** — references `sqrbx-update` but `install.sh` actually creates `sqrbx-rebuild`
- [x] **Fix CLAUDE.md `sqrbx-update` description** — says "pull latest repo changes and rebuild" but it actually updates tool binaries in-place

## P2 — Structural simplification

- [ ] **Extract a shared tool registry to eliminate 3-way install duplication** — `setup.sh`, `squarebox-update.sh`, and `update-versions.sh` each independently define how to download, extract, and install the same tools (URL patterns, arch mappings, extract steps). Adding a tool or changing a URL format requires updating all three files. A shared config (e.g. a declarative tool manifest or sourced shell library) could define each tool once and let the three scripts consume it.

## P2 — Dockerfile improvements

- [ ] Split the monolithic binary tools `RUN` block (lines 50-90) into smaller per-tool `RUN` blocks for better cache behavior
- [ ] Unify architecture detection — currently uses `dpkg --print-architecture` in one place and `uname -m` in another
- [x] Pick one versioning strategy — mixed approach is intentional: binary tools are pinned+checksummed, APT packages use distro versions with GPG signatures, third-party installers fetch latest
- [x] **Add `CMD ["/bin/bash"]`** — without it, `docker run` without `-it` drops into `/bin/sh` (no starship, no aliases)
- [x] **Fix `apt-get purge` ordering** — gnupg purge runs after `rm -rf /var/lib/apt/lists/*`. Swap: purge first, then clean lists.
- [x] **Check if Eza APT repo supports HTTPS** — currently uses `http://deb.gierens.de`. GPG signing mitigates, but HTTPS is preferred.

## P2 — Script improvements

- [x] Add input validation for git name/email and SDK selection prompts
- [x] Make GO_VERSION parsing more robust (currently assumes first line of go.dev/VERSION response)
- [x] **Remove dead code in `update-versions.sh`** — line 63 calls `strip_v` on delta version, then line 64 immediately overwrites the result
- [x] **Fetch NVM version dynamically in `update-versions.sh`** — every other tool is fetched from GitHub, but NVM is hardcoded to `0.40.3` with no explanation
- [x] **Replace fragile `find -exec mv` pattern** — used in `setup.sh` (lines 141, 219, 231) and `sqrbx-update` to locate extracted binaries. Silently succeeds if no match is found. Use explicit paths instead.
- [x] **Fix empty SDK list message** — `setup.sh` line 294 prints "Installing SDKs: (from previous selection)" even when the list is empty
- [x] **Add comment explaining `BROWSER=echo` trick** — `setup.sh` line 69 uses this to make `gh auth login` print the URL instead of opening a browser. Non-obvious to contributors.
- [x] **Remove redundant `rm -rf`** — `install_helix` (setup.sh line 237) deletes `~/.config/helix/runtime` before starting the download, then does it again at line 252. Remove the first one.

## P2 — README/docs cleanup

- [x] **Note macOS `sed` incompatibility in uninstall section** — `sed -i` without a backup suffix doesn't work on macOS. Provide macOS-compatible commands.
- [x] **Remove `master` branch from CI triggers** — `.github/workflows/build.yml` triggers on both `main` and `master`. Repo uses `main`.
- [x] **Clarify alias table** — `lsa` is listed as `ls -a` but actually resolves to `eza --icons -a` due to alias chaining
- [x] **Verify OpenCode repo URL** — README links to `https://github.com/anomalyco/opencode`, which may have moved
- [x] **Add "approximate, as of v1.0" note to disk usage table** — sizes will drift as tools update

## P3 — CI coverage gaps

- [x] Test that aliases resolve correctly (e.g. `ls` runs `eza`)
- [x] Test container stop/start persistence

## P4 — Features & Polish

- [ ] **Add tmux and zellij as optional installs** — offer both terminal multiplexers in the setup.sh selection menu, preconfigured with sensible defaults
- [ ] **Custom colour theme** — ship a unified terminal colour palette (e.g. Catppuccin or Tokyo Night) so bat, delta, fzf, eza, starship, and tmux all look coordinated out of the box
- [ ] **Dotfile portability** — let users mount or bootstrap their own dotfiles (starship.toml, tmux.conf, aliases, etc.) via a `~/.squarebox/` convention, with sensible merge/override behaviour against the defaults
- [ ] **Versioned releases with changelogs** — publish GitHub Releases with semantic version tags and changelogs so users can pin to a known-good version and see what changed
- [ ] **Animated GIF demo** — create a terminal recording (VHS or asciinema) showcasing the tools and workflow for the README

## P5 — TBD / Minor

- [x] Add a `.dockerignore` to exclude `.git/` and other unnecessary context from Docker builds
- [ ] Support multiple concurrent container instances
- [ ] Add `.editorconfig` for contributor consistency
- [ ] Add `CONTRIBUTING.md` with build/test/PR instructions
- [ ] Expand `.gitignore` — currently only covers `.DS_Store` and swap files
- [ ] Add TASKS.md to `.dockerignore` to keep it out of build context
