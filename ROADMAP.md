# Roadmap

## Planned

- **Custom colour theme** — ship a unified terminal colour palette (e.g. Catppuccin or Tokyo Night) so bat, delta, fzf, eza, starship, and tmux all look coordinated out of the box
- **Dotfile portability** — let users mount or bootstrap their own dotfiles (starship.toml, tmux.conf, aliases, etc.) via a `~/.squarebox/` convention, with sensible merge/override behaviour against the defaults
- **Multiple concurrent container instances** — support running more than one squarebox container simultaneously
- **Network firewall / sandboxing mode** — optional network-level isolation (iptables/seccomp) so AI agents can only reach approved endpoints, inspired by trailofbits and clampdown
- **Per-project container profiles** — save and load named profiles (e.g. `sqrbx start --profile python-ml`) that pre-select SDKs, editors, and AI tools without re-running the wizard
- **MCP server pre-configuration** — ship ready-made MCP server configs (filesystem, GitHub, etc.) as part of the AI assistant setup step
- **Atuin (searchable shell history)** — replace basic bash history with full-text search, sync, and stats across sessions
- **Zsh as optional shell** — offer Zsh + Oh-My-Zsh as a setup wizard option alongside bash
- **direnv integration** — automatic per-directory environment variable loading for multi-project workspaces
- **Task completion notifications** — webhook, terminal bell, or desktop notification when long-running AI tasks finish
- **Multi-agent workflow orchestration** — explore adding a layer to run multiple AI coding agents simultaneously in isolated contexts (git worktrees + tmux sessions), inspired by agent-of-empires; may be better to integrate an existing tool than build from scratch
