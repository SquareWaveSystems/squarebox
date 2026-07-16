# Roadmap

## v1.1.0 release gate

- Pass every assertion in `scripts/e2e-required.tsv` against one immutable Candidate digest.
- Complete the real-host matrix in `uat-checklist.md`, especially Windows,
  macOS, Fedora rootless Podman/SELinux, Dev Containers/Codespaces, and
  physical arm64 (tracked by GitHub issues #99–#105).
- `v1.1.0-rc5` completed the automatic publication rehearsal.
- Keep GitHub immutable Releases enabled, keep the no-bypass `v*` update and
  deletion ruleset active, and verify the stable/prerelease environment
  protections before creating a final tag.
- Create the immutable `v1.1.0` tag so CI builds one final Candidate and
  prepares its signed assets as a non-discoverable draft. Complete physical
  qualification against that exact digest and draft asset set, then approve
  the `v1.1-production` environment to publish those bytes without rebuilding.
  Do not retarget the final tag if qualification fails; fix forward with a new
  version.
- Resolve or explicitly defer every open release-blocking GitHub issue.

## After v1.1

- **Install identity schema consolidation** — replace four regression-locked
  adapter validators with one authoritative cross-language contract (#106).
- **Windows SSH and adapter migration** — design native OpenSSH-agent
  forwarding and a safe Git Bash/PowerShell identity migration path (#107).
- **Lifecycle replacement recovery** — restore a coherent runnable prior Box,
  image, source, and state after handled late rebuild failures (#108).
- **Learn mode redesign** — opt-in lessons with corrected versioned content,
  binary-based capability checks, an explicit privacy contract, and no command
  logging without informed consent.
- **User dotfile adapters** — documented merge/override behavior for Starship,
  tmux, aliases, Zsh, and Fish without weakening managed refresh safety.
- **Atuin** — persistent searchable shell history with optional sync.
- **direnv** — pinned image-tier automatic `.envrc` loading.
- **hyperfine** — pinned image-tier command benchmarking.
- **Host-theme inheritance** — ANSI-first defaults for fzf, eza, Starship,
  tmux, and Zellij with clear overrides for bat/delta themes.
- **Assistant completion notifications** — opt-in terminal bell/desktop adapter
  around long-running assistant commands.
- **Native platform depth** — move remaining Windows, macOS, Podman/SELinux,
  and physical-arm64 UAT into automated adapters where runners permit.
