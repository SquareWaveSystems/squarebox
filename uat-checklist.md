# Squarebox v1.1 manual UAT

Automated release assertions are defined in `scripts/e2e-required.tsv` and
reported from exact Evidence by `.github/workflows/e2e.yml`. This checklist
contains only behavior that still needs a person, real host integration, or
hardware outside GitHub-hosted runners. An unchecked item is **untested**, not
an automated pass.

Record the Candidate version, source SHA, image digest, host OS, architecture,
container runtime/version, and result for every run.

Tracking issues: [Linux desktop #99](https://github.com/SquareWaveSystems/squarebox/issues/99),
[Fedora/Podman #100](https://github.com/SquareWaveSystems/squarebox/issues/100),
[macOS #101](https://github.com/SquareWaveSystems/squarebox/issues/101),
[Windows/Git Bash #102](https://github.com/SquareWaveSystems/squarebox/issues/102),
[Dev Containers/Codespaces #103](https://github.com/SquareWaveSystems/squarebox/issues/103),
[demo regeneration #104](https://github.com/SquareWaveSystems/squarebox/issues/104), and
[physical Candidate qualification #105](https://github.com/SquareWaveSystems/squarebox/issues/105).

## Linux desktop — Docker

- [ ] Fresh Bash installer: launch, interactive setup, exit, resume, rebuild, uninstall
- [ ] Existing v1.0 Managed home upgrade: no repeated prompts; selections reconcile
- [ ] Host UID/GID other than 1000: Workspace and managed files remain host-owned
- [ ] Custom install path, Workspace, and Managed-home volume survive rebuild and purge correctly
- [ ] Purge refuses an unrelated directory/container/image/volume with a colliding name
- [ ] Docker daemon unavailable during uninstall produces a clear nonzero partial-cleanup result

## Rootless Podman and SELinux

- [ ] Fedora with enforcing SELinux: Workspace/SSH/system labels remain unchanged and the documented `label=disable` tradeoff is acceptable
- [ ] Rootless keep-id mapping: host and Box create mutually writable files
- [ ] Rootless Podman rejects PUID/PGID values that differ from the invoking host identity
- [ ] Stop/start, replacement, rebuild, and purge honor the same Install identity
- [ ] SSH agent and read-only SSH fallback both work

## macOS — Docker Desktop

- [ ] Fresh install and upgrade with paths containing spaces
- [ ] SSH agent forwarding works; fallback private-key mount remains read-only
- [ ] Missing `/etc/localtime` uses the documented timezone fallback
- [ ] Rebuild and purge preserve/remove only recorded Managed resources

## Windows — native PowerShell 7 and Docker Desktop

- [ ] Fresh `install.ps1`, Box launch, PowerShell rebuild, and `uninstall.ps1` remain on the same native adapter
- [ ] Shell functions work in ConsoleHost and VS Code PowerShell hosts
- [ ] Install from one PowerShell host and uninstall from another removes the intended integration
- [ ] Git identity contains only name/email; host credential/signing configuration is not mounted
- [ ] Native PowerShell mounts `%USERPROFILE%\.ssh` read-only and does not claim `SSH_AUTH_SOCK` forwarding
- [ ] Paths containing spaces and non-ASCII characters survive every lifecycle action
- [ ] Install identity access is limited by the current user's Windows install-directory ACL
- [ ] Native PowerShell rejects a Git Bash-created Install identity without modifying its resources or profiles

## Git Bash compatibility

- [ ] Bash integration uses the MSYS home while the Install identity uses the Windows user home
- [ ] SSH agent socket translation works with Docker Desktop path conversion disabled
- [ ] Git Bash install, rebuild, and uninstall consume the Bash-created identity only
- [ ] Git Bash rejects a native PowerShell-created Install identity without modifying its resources or shell integration

## Interactive setup

- [ ] Cancel each multi-select and confirm the prior Selection is preserved
- [ ] Deliberately choose an empty Selection and confirm it is saved distinctly from cancel
- [ ] Fail one assistant install and confirm aliases target the first successfully observed assistant
- [ ] GitHub device authentication succeeds; decline marker and credentials survive Box replacement
- [ ] Claude, Copilot, Gemini, Codex, OpenCode, and Pi launch after installation
- [ ] Copilot uses the supported `copilot` command
- [ ] Bash initializes Starship, Zoxide, fzf keybindings/completion, aliases, and mise shims
- [ ] Zsh and Fish initialize Starship, Zoxide, the `fzf`/`ff` command path, aliases, and mise shims
- [ ] Section-only AI/editor/TUI reruns refresh Fish derived configuration
- [ ] A non-first default editor survives Box replacement and noninteractive reconciliation
- [ ] Explicit `set -g mouse off` remains respected during tmux migration

## Interactive tools

- [ ] `lazygit`, `yazi`, `gh-dash`, and Helix (`hx`) render and accept input
- [ ] `gum` and `fzf` interactive modes work with the host terminal
- [ ] tmux and Zellij keybindings match the documentation
- [ ] Neovim/LazyVim first launch completes without wedging dpkg under the timezone mount

## Dev Containers and Codespaces

- [ ] VS Code Dev Containers builds the tagged Candidate source, runs `postCreateCommand`, and reopens successfully (source rebuild is not byte-identical to the published image)
- [ ] GitHub Codespaces runs the noninteractive defaults and preserves independent successful Selections after one section fails
- [ ] Rebuilds preserve Workspace Selection state and Managed-home authentication/toolchains

## Candidate promotion

- [ ] Pull the published Candidate by digest on real amd64 hardware
- [ ] Pull the same Candidate digest on real arm64 hardware
- [ ] Verify the version file, MOTD, Git source ref, and `release.json` agree
- [ ] Confirm the active release-tag ruleset rejects update/deletion of the `v*` tag and that its peeled remote commit still equals the Candidate source SHA
- [ ] Download the non-discoverable draft assets with authenticated `gh release download` and verify their hashes and Cosign identity signature
- [ ] Run fresh and upgraded Compose flows against the digest
- [ ] Confirm stable installers cannot discover the Release until all gates pass
- [ ] Record the qualification evidence and explicit promote/no-promote decision in [issue #105](https://github.com/SquareWaveSystems/squarebox/issues/105)
- [ ] Approve the waiting `v1.1-production` environment deployment to publish the tested Candidate without rebuilding different image bytes
- [ ] After publication, run `gh release verify <tag>` and confirm GitHub reports a valid immutable-Release attestation
- [ ] Confirm GitHub Release and GHCR `latest` identify the greatest published stable version
- [ ] Rerun an older stable workflow (or its equivalent dry-run check) and confirm neither `latest` pointer can rewind
