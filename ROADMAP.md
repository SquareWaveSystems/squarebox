# Roadmap

## Planned

- **Host theme transparency** — configure tools (fzf, eza, starship, tmux) to use ANSI colour references so they inherit the host terminal's theme automatically; provide sensible defaults for tools with their own named themes (bat, delta) with easy overrides
- **Dotfile portability** — let users mount or bootstrap their own dotfiles (starship.toml, tmux.conf, aliases, etc.) via a `~/.squarebox/` convention, with sensible merge/override behaviour against the defaults
- **Multiple concurrent container instances** — support running more than one squarebox container simultaneously
- **Neovim defaults from omarchy** — bring across the neovim configuration defaults from omarchy so nvim works well out of the box
