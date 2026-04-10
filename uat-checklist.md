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

## Dev Container
- [ ] VS Code "Reopen in Container" builds and connects
- [ ] Manual `~/setup.sh` works in VS Code integrated terminal
