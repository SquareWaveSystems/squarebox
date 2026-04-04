# TASKS

Items are ordered by priority within each section. Sections are ordered by priority.

## P0 — Security (fix first)

- [ ] **Pin all binary versions and add SHA256 checksum verification** for every download in Dockerfile and setup.sh
- [ ] **Audit and document the trust model for `curl | bash` install path** — users piping install.sh into their shell need to understand what it does; mitigate MITM and compromised-repo risks

## P1 — Reliability (fix next)

- [ ] **Validate version variables are non-empty** before using them in download URLs (Dockerfile lines 50-90, setup.sh SDK installs) — empty vars silently produce broken binaries
- [ ] **Handle GitHub API rate limiting** (60 req/hr unauthenticated) — fail fast with a clear message instead of silently continuing; pass `GITHUB_TOKEN` header on GitHub API calls when available
- [ ] **Verify SDK install success** before continuing (e.g. check `nvm install --lts` exit code, verify binaries exist)
- [ ] Add cleanup trap in setup.sh to remove temp files on failure
- [ ] Handle partial setup failure — clean up half-configured state so retries work cleanly

## P1 — install.sh (fix next)

- [ ] **Fix shell detection** — use `$SHELL` instead of checking if `~/.zshrc` exists (currently writes aliases to wrong file for bash users with a stale .zshrc)
- [ ] **Make alias injection idempotent** — check if aliases already exist before appending to shell RC file
- [ ] Document (or mitigate) that `devbox-update` destroys the container and loses in-container state (installed SDKs, shell history, setup-done flag)

## P2 — Dockerfile improvements

- [ ] Split the monolithic binary tools `RUN` block (lines 50-90) into smaller per-tool `RUN` blocks for better cache behavior
- [ ] Unify architecture detection — currently uses `dpkg --print-architecture` in one place and `uname -m` in another
- [ ] Pick one versioning strategy: either pin all versions or fetch all dynamically (currently mixed)

## P2 — setup.sh improvements

- [ ] Add input validation for git name/email and SDK selection prompts
- [ ] Make GO_VERSION parsing more robust (currently assumes first line of go.dev/VERSION response)

## P3 — CI coverage gaps

- [ ] Test that aliases resolve correctly (e.g. `ls` runs `eza`)
- [ ] Test container stop/start persistence
- [ ] Test SDK installation flow end-to-end
- [ ] Test behavior when GitHub API is rate-limited

## P4 — TBD / Minor

- [x] Add a `.dockerignore` to exclude `.git/` and other unnecessary context from Docker builds
- [ ] Make container name configurable (currently hardcoded as `devbox` everywhere)
- [ ] Add mechanism to update tools inside a running container without full rebuild
- [ ] Support multiple concurrent container instances
