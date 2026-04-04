TUI Devbox Environment
======================

This is a containerised development environment with modern CLI tools. Use these tools for better output and workflows.

Available CLI Tools
-------------------

### File & Text Operations

* `fd` - Modern `find` replacement. Use for file searches: `fd pattern`, `fd -e py` (by extension), `fd -H` (include hidden)
* `rg` (ripgrep) - Fast grep replacement. Use for code search: `rg pattern`, `rg -t py pattern` (by filetype), `rg -C3` (with context)
* `bat` - `cat` with syntax highlighting. Use instead of cat: `bat file.py`, `bat -l json` (force language)
* `fzf` - Fuzzy finder. Pipe anything into it: `fd | fzf`, `rg -l pattern | fzf`
* `jq` - JSON processor. Use for JSON manipulation: `jq '.key'`, `jq -r '.[]'`
* `yq` - YAML processor (like jq for YAML): `yq '.key' file.yaml`, `yq -i '.key = "value"'`

### HTTP & Network

* `xh` - Modern HTTPie alternative. Use for API calls: `xh GET url`, `xh POST url key=value`, `xh -b` (body only)

### Git & GitHub

* `git` - With delta configured as pager for beautiful diffs
* `delta` - Syntax-highlighting diff viewer (auto-used by git)
* `gh` - GitHub CLI. Use for PRs, issues, repos: `gh pr create`, `gh issue list`, `gh repo clone`

### File Management

* `eza` (alias: `ls`, `ll`) - Modern ls replacement with icons. `ll` for detailed view
* `zoxide` (alias: `cd`) - Smart cd that learns your habits. Just `cd` to frecent dirs

### System

* `zstd` - Fast compression: `zstd file`, `zstd -d file.zst`

Shell Aliases
-------------

* `ls` → `eza --icons`
* `ll` → `eza -la --icons`
* `cat` → `bat --paging=never`
* `cd` → `zoxide` (smart directory jumping)
* `claude-yolo` → `claude --dangerously-skip-permissions`

TUI Tools
---------

* `lazygit` (alias: `lg`) - Full git TUI. Stage, commit, branch, rebase interactively
* `yazi` - Terminal file manager with image preview, bulk rename, plugin system
* `tmux` - Terminal multiplexer. Sessions, windows, panes
* `btop` - System resource monitor (CPU, memory, disk, network)
* `gh-dash` - GitHub dashboard TUI for PRs and issues
* `glow` - Markdown renderer/pager for the terminal
* `fresh` - VS Code-like terminal text editor with LSP, file explorer, fuzzy finder
* `edit` - Microsoft's lightweight terminal text editor

Recommended Workflows
---------------------

### Code Search

# Find files then search content
fd -e ts | xargs rg "pattern"
# or interactively
rg -l "pattern" | fzf --preview 'bat --color=always {}'

### Git Operations

Use `git` for staging, committing, branching. Use `gh` for GitHub operations.

### File Navigation

Use `cd` freely - zoxide learns.
