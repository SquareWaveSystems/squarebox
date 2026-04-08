# Roadmap

## Planned

- **Host theme transparency** — configure tools (fzf, eza, starship, tmux) to use ANSI colour references so they inherit the host terminal's theme automatically; provide sensible defaults for tools with their own named themes (bat, delta) with easy overrides
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
- **Neovim defaults from omarchy** — bring across the neovim configuration defaults from omarchy so nvim works well out of the box
- **Additional developer TUI tools** — add difftastic (syntax-aware structural diffs), hyperfine (command-line benchmarking), and just (modern task runner) to the default image
