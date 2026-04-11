# Roadmap

## Planned

Items are listed in priority order.

- **just** — add [just](https://github.com/casey/just) (modern task runner) to the default image; single binary, zero dependencies, gives users a standard way to define project commands
- **lazydocker** — add [lazydocker](https://github.com/jesseduffield/lazydocker) (Docker management TUI) to the default image; same author as lazygit, completes the TUI tool suite for developers managing containers
- **difftastic** — add [difftastic](https://github.com/Wilfred/difftastic) (syntax-aware structural diffs) to the default image; complements delta with language-aware diffing
- **btop** — add [btop](https://github.com/aristocratos/btop) (system resource monitor TUI) to the default image; fills the "what's eating my CPU/memory" gap without requiring manual package installation
- **direnv** — add [direnv](https://github.com/direnv/direnv) (automatic per-directory environment loading) to the default image; auto-loads `.envrc` files on `cd`, integrates with zoxide for seamless per-project environment variables
- **Zsh option** — offer Zsh with Oh My Zsh, autosuggestions, and syntax highlighting as a selectable shell in `setup.sh` alongside the Bash default; closes the biggest UX gap vs. competing dev environments
- **Dotfile portability** — let users mount or bootstrap their own dotfiles (starship.toml, tmux.conf, aliases, etc.) via a `~/.squarebox/` convention, with sensible merge/override behaviour against the defaults
- **MCP server pre-configuration** — ship ready-made MCP server configs (filesystem, GitHub, etc.) as part of the AI assistant setup step
- **hyperfine** — add [hyperfine](https://github.com/sharkdp/hyperfine) (command-line benchmarking) to the default image
- **Atuin (searchable shell history)** — replace basic bash history with full-text search, sync, and stats across sessions
- **Host theme transparency** — configure tools (fzf, eza, starship, tmux) to use ANSI colour references so they inherit the host terminal's theme automatically; provide sensible defaults for tools with their own named themes (bat, delta) with easy overrides
- **Per-project container profiles** — save and load named profiles (e.g. `sqrbx start --profile python-ml`) that pre-select SDKs, editors, and AI tools without re-running the wizard
- **Neovim defaults from omarchy** — bring across the neovim configuration defaults from omarchy so nvim works well out of the box
- **Task completion notifications** — webhook, terminal bell, or desktop notification when long-running AI tasks finish
- **Network firewall / sandboxing mode** — optional network-level isolation (iptables/seccomp) so AI agents can only reach approved endpoints, inspired by trailofbits and clampdown
- **Multiple concurrent container instances** — support running more than one squarebox container simultaneously
- **Multi-agent workflow orchestration** — explore adding a layer to run multiple AI coding agents simultaneously in isolated contexts (git worktrees + tmux sessions), inspired by agent-of-empires; may be better to integrate an existing tool than build from scratch
- ~~**Podman compatibility**~~ — ✅ done: install scripts auto-detect Docker or Podman and skip UID chown logic for Podman's rootless user namespace mapping
