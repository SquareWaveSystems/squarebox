# squarebox UAT Checklist (Manual)

> **Automated tests**: 55 of 71 checklist items are covered by the [E2E workflow](/.github/workflows/e2e.yml).
> Run it via `workflow_dispatch` or push a `v*` tag. See the generated `e2e-report.md` artifact for full results.
>
> This file lists only the **16 items that require manual verification**.

## Host Install
- [ ] `sqrbx` launches container and drops into interactive shell

## First-Run Setup (Interactive)
- [ ] Git identity prompt appears (name + email UX)
- [ ] GitHub sign-in prompt appears and can be declined (opt-out persists in `/workspace/.squarebox/gh-skip`)
- [ ] GitHub CLI auth flow works (prints URL, completes browser/device auth)
- [ ] GH auth persists to `/workspace/.squarebox/gh` across rebuilds
- [ ] Claude Code installs and runs (requires API key)
- [ ] Copilot / Gemini / Codex install via npm

## Tools Verification (TUI)
- [ ] `lazygit` — TUI launches and is usable
- [ ] `yazi` — file manager TUI launches
- [ ] `gh-dash` — GitHub dashboard TUI launches
- [ ] `gum` — interactive prompts work
- [ ] `fzf` — fuzzy search interactive mode works

## Container Lifecycle (Rebuild)
- [ ] `sqrbx-rebuild` rebuilds image + creates new container
- [ ] After rebuild: `/workspace/.squarebox/` selections reused (no re-prompts)
- [ ] After rebuild: GH CLI stays authenticated

## Pull/Compose Upgrade (cross-version, #89)
> Real cross-version test: start a container on an **older** image so the
> `squarebox-home` volume is seeded with that image's dotfiles, then upgrade the
> image and restart. The e2e `dotfiles` suite only simulates this within one
> image; this verifies it across an actual version bump.
- [ ] Start old image → stop → `docker compose pull` newer image → up: `~/.bashrc` matches the new image (entrypoint refresh defeated the volume shadow)
- [ ] fzf keybindings (Ctrl+R / Ctrl+T / Alt+C) and git tab-completion work in the upgraded container
- [ ] Desktop install path: host-edited `~/squarebox/dotfiles/bashrc` (bind-mounted) is NOT clobbered by the refresh

## Dev Container
- [ ] VS Code "Reopen in Container" builds and connects
- [ ] Manual `sqrbx-setup` works in VS Code integrated terminal
