# Changelog

## v1.1.0 — 2026-07-16

### Added

- Re-runnable setup sections through `sqrbx-setup`.
- Bash, experimental Zsh, and experimental Fish selection.
- tmux and Zellij selection with aligned keybindings.
- SSH client availability in the base image.
- Pi and Paseo assistant options.
- Version display in the MOTD and image metadata.
- Durable Install identity for safe rebuild and uninstall behavior.
- Assertion-backed release Evidence, SBOM/provenance, vulnerability scanning,
  a digest-bound published Evidence manifest, release-asset hashes, and
  image/asset signing.
- Cross-platform lifecycle and UAT tracking through durable GitHub issue briefs.

### Changed

- Published Releases bind one source revision to one immutable
  multi-architecture image digest in `release.json`.
- Stable installation discovers published Releases instead of raw Git tags.
- Release promotion reuses the tested Candidate digest rather than rebuilding.
- Saved tool Selections are reconciled with actual Box state after replacement.
- Direct artifact installation now fails closed and preserves the original
  error through cleanup; Managed-home releases use exact GitHub asset digests
  and serialized, rollback-capable destination transactions.
- Bulk `sqrbx-update --apply` updates installed tools only; an explicitly named
  absent tool is treated as an install request.
- Git identity is isolated in Squarebox-managed configuration instead of
  mounting and changing the host's real Git config.
- Dev Containers use `/workspace`, matching setup and Selection state.
- The selected default editor persists independently and survives Box
  reconciliation; LazyVim and Zsh sources resolve immutable commits.
- Rootless Podman maps the invoking host user to the Box's `dev` identity
  without relabeling host files.
- Release publication is serialized across tags, scans both architectures,
  and prevents historical reruns from rewinding `latest`.
- GitHub Copilot uses the supported `@github/copilot` package and `copilot`
  command.

### Fixed

- Runtime APT under a read-only timezone mount.
- Box-tier tmux/Zsh/Fish loss after container replacement.
- Updater parsing, false-success, deleted-log, duplicate-request, and absent-tool behavior.
- Custom install rebuild/purge state and fixed-name resource deletion.
- Non-1000 UID/GID defaults and rootless Podman ownership/SELinux options.
- Compose Managed-home volume identity.
- Dev Container state disappearing outside the cloned Workspace.
- Dotfile refresh following user-controlled symlinks as root.
- Setup cancellation erasing prior Selections and aliases targeting failed installs.
- First-install and purge authority races, unsafe shell-profile rewrites, and
  drift between the adapter-native Git Bash and PowerShell lifecycle validators.
- Multi-output updater races, destination-type confusion, incomplete observed
  state, and image-tier updates advertised without Candidate-authorized bytes.
- Fish derived aliases becoming stale after section-only setup reruns.
- CI reports claiming behavior that was not executed.
- Release-candidate failures caused by a Compose UID-remap startup race,
  cross-UID Evidence file permissions, LazyGit's lowercase Linux asset name,
  and Gum release binaries built with a vulnerable Go standard library.

### Removed

- Disabled learn-mode commands and command-logging hook from the default image.

### Migration notes

See [`docs/releases/v1.1.0.md`](docs/releases/v1.1.0.md).

## v1.0.0

Initial stable Squarebox release with Docker/Podman installation, a persistent
Managed home, Compose support, modern CLI tools, first-run setup, and host
Workspace mounting.
