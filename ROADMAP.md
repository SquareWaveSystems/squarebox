# Roadmap

Grouped by effort, not priority. Near-term items are small additive changes;
medium items touch `setup.sh` or shared configs.

## Near-term

- **direnv** — [direnv](https://github.com/direnv/direnv) for automatic per-directory environment loading via `.envrc`; pinned in the Dockerfile tier.
- **hyperfine** — [hyperfine](https://github.com/sharkdp/hyperfine) command-line benchmarking; pinned in the Dockerfile tier.
- **Terminal bell on AI task completion** — emit a terminal bell when long-running AI commands finish, via a wrapper around the AI aliases.

## Medium

- **Atuin** — replace basic bash history with full-text search, sync, and stats across sessions.
- **Host theme transparency** — configure tools (fzf, eza, starship, tmux, zellij) to use ANSI colour references so they inherit the host terminal's theme; provide sensible defaults for tools with their own named themes (bat, delta) with easy overrides.
- **Neovim defaults from omarchy** — cherry-pick the omarchy neovim configuration so nvim works well out of the box when selected during setup.
- **Dotfile portability** — let users mount or bootstrap their own dotfiles (starship.toml, tmux.conf, aliases, etc.) via a `~/.squarebox/` convention, with sensible merge/override behaviour against the defaults.
