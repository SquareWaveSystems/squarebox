# squarebox UAT Checklist

## 1. Host Install
- [ ] `install.sh` completes without errors
- [ ] Docker image builds successfully
- [ ] `~/squarebox/workspace` directory created
- [ ] Shell aliases added: `sqrbx`, `squarebox`, `sqrbx-rebuild`, `squarebox-rebuild`
- [ ] `sqrbx` launches container and drops into shell
- [ ] Host configs seeded: `starship.toml`, `lazygit/config.yml`

## 2. Docker Build
- [ ] `docker build -t squarebox .` succeeds (amd64)
- [ ] `docker build -t squarebox .` succeeds (arm64)
- [ ] All base tools present: `git curl jq rg bat fzf fd eza gh zoxide nano`
- [ ] All binary tools present: `delta yq lazygit xh yazi starship gh-dash glow gum`
- [ ] Checksum verification passes for all binaries

## 3. First-Run Setup
- [ ] Setup triggers automatically on first login
- [ ] Git identity prompt appears (name + email), skips if preconfigured
- [ ] GitHub CLI auth flow works (prints URL, completes login)
- [ ] GH auth persists to `/workspace/.squarebox/gh`
- [ ] AI tools selection: Claude Code installs and runs
- [ ] AI tools selection: Copilot / Gemini / Codex install via npm
- [ ] AI tools selection: OpenCode installs from binary
- [ ] Editor selection: micro, edit, fresh, helix, nvim each install cleanly
- [ ] Multiplexer selection: tmux installs with config, zellij installs from binary
- [ ] SDK selection: Node.js (nvm + LTS), Python (uv), Go, .NET each install
- [ ] All selections saved to `/workspace/.squarebox/` and reused on rebuild
- [ ] Non-interactive mode (piped stdin) skips prompts gracefully

## 4. Shell Environment
- [ ] Starship prompt displays with orange box indicator
- [ ] Zoxide initializes (`z` command works)
- [ ] MOTD banner displays with date and installed SDK versions
- [ ] `EDITOR` set to first selected editor
- [ ] `c` alias points to first selected AI tool
- [ ] SDK paths sourced (node/python/go/dotnet in PATH)
- [ ] Key aliases work:
  - [ ] `ls` / `ll` / `lt` (eza variants)
  - [ ] `cat` (bat)
  - [ ] `ff` (fzf + bat preview)
  - [ ] `g` / `gcm` / `gcam` / `lg` (git shortcuts)
  - [ ] `..` / `...` / `....` (directory nav)

## 5. Tools Verification
- [ ] `bat --version` — syntax highlighting works on a file
- [ ] `delta` — `git diff` shows colored side-by-side output
- [ ] `lazygit` — launches TUI
- [ ] `yazi` — launches file manager
- [ ] `gh-dash` — launches GitHub dashboard
- [ ] `glow` — renders a markdown file
- [ ] `xh` — makes an HTTP request
- [ ] `yq` — parses a YAML file
- [ ] `gum` — interactive prompts work
- [ ] `fzf` — fuzzy search works
- [ ] Git pager uses delta (global gitconfig)
- [ ] Lazygit uses delta pager (lazygit config)

## 6. Container Lifecycle
- [ ] `exit` suspends container (doesn't destroy it)
- [ ] `sqrbx` / `docker start -ai squarebox` resumes with state intact
- [ ] Files in `/workspace` persist across stop/start
- [ ] Files outside `/workspace` (e.g. `~/testfile`) persist across stop/start
- [ ] `sqrbx-rebuild` rebuilds image + container
- [ ] After rebuild: workspace files preserved
- [ ] After rebuild: `/workspace/.squarebox/` selections reused (no re-prompts)
- [ ] After rebuild: GH CLI stays authenticated
- [ ] Volume mounts work: SSH keys (read-only), git config, starship, lazygit

## 7. In-Container Updates (`sqrbx-update`)
- [ ] `sqrbx-update --help` shows usage
- [ ] `sqrbx-update --list` shows installed versions
- [ ] `sqrbx-update` (no args) shows available updates (dry run)
- [ ] `sqrbx-update --apply` downloads and installs updates
- [ ] `sqrbx-update <tool>` updates a single tool
- [ ] Checksum verification blocks tampered downloads
- [ ] Rate limit warning shown when approaching GitHub API limit
- [ ] `GITHUB_TOKEN` increases rate limit to 5000/hr

## 8. Dev Container
- [ ] `.devcontainer/devcontainer.json` is valid JSON
- [ ] VS Code "Reopen in Container" builds and connects
- [ ] Workspace folder is `/workspace`
- [ ] User is `dev` (not root)
- [ ] `DEVCONTAINER=1` set — interactive setup skipped
- [ ] Manual `~/setup.sh` works in integrated terminal

## 9. CI Pipeline
- [ ] Push to `main` triggers build workflow
- [ ] PR to `main` triggers build workflow
- [ ] Image builds with buildx
- [ ] All binary presence checks pass
- [ ] Alias resolution tests pass
- [ ] Container persistence test passes
