# Usage reference

[Back to README](../README.md) · [Security](../SECURITY.md)

- [Installing Docker](#installing-docker)
- [Advanced installation](#advanced-installation)
- [Windows installation](#windows-installation)
- [Server deployment](#server-deployment)
- [Shell configuration](#shell-configuration)
- [Editor configuration](#editor-configuration)
- [SDK configuration](#sdk-configuration)
- [Help and reconfiguration](#help-and-reconfiguration)
- [Aliases](#aliases)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Updates and rebuilds](#updates-and-rebuilds)
- [Dev Containers and Codespaces](#dev-containers-and-codespaces)
- [Uninstall and recovery](#uninstall-and-recovery)

## Installing Docker

**macOS** (via [Homebrew](https://brew.sh)):

    brew install --cask docker-desktop

**Linux** (official convenience script - inspect it first at [get.docker.com](https://get.docker.com)):

    curl -fsSL https://get.docker.com | sh && sudo usermod -aG docker $USER

Log out and back in (or run `newgrp docker`) so your shell picks up the new group.

**Windows** (via [winget](https://learn.microsoft.com/en-us/windows/package-manager/winget/), in PowerShell 7+):

    winget install --id Docker.DockerDesktop -e

On macOS and Windows, start Docker Desktop once after install so the daemon is
running before you continue.

## Advanced installation

Stable resolves the latest published GitHub Release and pulls the immutable
image digest recorded in its `release.json`. Raw Git tags are not installable
stable releases. An explicit `SQUAREBOX_TAG=v…` resolves that published Release
and its matching source revision. Edge builds the latest commit on `main`. To
build a published Release from source instead of pulling, pass `--build`.

Install edge from Bash:

```bash
curl -fsSL https://github.com/SquareWaveSystems/squarebox/releases/latest/download/install.sh | bash -s -- --edge
```

If the install fails or you want to see the full build/pull and git output,
re-run with `--verbose`.

Flags: `--build` (build from source), `--edge` (latest `main`), `--adopt`
(one-time migration of a legacy installation), and `--verbose`.

| Variable | Default | Purpose |
|----------|---------|---------|
| `SQUAREBOX_DIR` | `~/squarebox` | Install location (repo + workspace). Point at durable storage on hosts where `$HOME` is volatile — e.g. Unraid `/mnt/user/appdata/squarebox`. |
| `SQUAREBOX_WORKSPACE` | `$SQUAREBOX_DIR/workspace` | Host path mounted as `/workspace`. |
| `SQUAREBOX_TAG` | latest published stable | Published Release to install (for example `v1.2.1`). Tags use `vMAJOR.MINOR.PATCH[-prerelease]`; build metadata is not published. |
| `SQUAREBOX_IMAGE` | value from `release.json` | Optional image-repository override for development/testing. |
| `SQUAREBOX_BUILD` | `0` | `1` is equivalent to `--build`. |
| `PUID` / `PGID` | invoking Linux user | Host uid/gid that should own bind-mounted files. Unprivileged Linux installs must match the invoking account. Root-run rootful runtimes, including Docker or Podman on NAS and Unraid, may override these (typically `99` / `100`); rootless Podman also requires the invoking host identity. |
| `SQUAREBOX_RUNTIME` | auto | Force `docker` or `podman`. |
| `SQUAREBOX_HOME_VOLUME` | `squarebox-home` | Name of the named volume backing `/home/dev`. |
| `SQUAREBOX_EDGE` | `0` | `1` is equivalent to `--edge`. |
| `SQUAREBOX_MOUNT_SSH` | `0` | `1` mounts your host `~/.ssh` directory, **private keys included**, read-only into the Box when no SSH agent is forwarded. Recorded for rebuilds; set `0` to turn it back off. See [SSH access](../SECURITY.md#ssh-access). |

**Non-interactive provisioning** — set any of these to a comma-separated list to
pre-select a toolset and install it without prompts (handy for servers and
scripted installs). Values use the same keys as `sqrbx-setup`:

| Variable | Selects |
|----------|---------|
| `SQUAREBOX_AI` | AI assistants (`claude,copilot,gemini,codex,opencode,pi,omp`) |
| `SQUAREBOX_SDKS` | language SDKs (`node,python,go,dotnet,rust`) |
| `SQUAREBOX_EDITORS` | editors (`micro,edit,fresh,helix,nvim`; Helix launches as `hx`) |
| `SQUAREBOX_TUIS` | TUI tools (`lazygit,gh-dash,yazi,elio`) |
| `SQUAREBOX_MULTIPLEXERS` | multiplexers (`tmux,zellij,herdr`) |
| `SQUAREBOX_GIT_NAME` / `SQUAREBOX_GIT_EMAIL` | git identity (when no host gitconfig) |

Example:

```bash
curl -fsSL https://github.com/SquareWaveSystems/squarebox/releases/latest/download/install.sh \
  | env SQUAREBOX_AI=claude SQUAREBOX_SDKS=node,python bash
```

Each successful v1.1-or-newer install records its effective lifecycle settings at
`<SQUAREBOX_DIR>/.squarebox/install-state` (mode 0600 on POSIX; inherited
current-user install-directory ACL on native Windows). Rebuild and uninstall
parse this file as data; they do not reconstruct defaults or source it as shell
code. Release pulls record an immutable image digest; source/edge builds record
their local image ID/reference. Existing pre-v1.1 checkouts require a one-time
reviewed `--adopt`/`-Adopt`.

## Windows installation

Windows users can install directly from PowerShell - no Git Bash required.
This handles Release resolution, pull/build, Box creation, and PowerShell functions
(`sqrbx`, `squarebox`, etc.) natively:

    irm https://github.com/SquareWaveSystems/squarebox/releases/latest/download/install.ps1 | iex

Once installed, you can re-run or pass flags from the local copy:

    .\install.ps1              # re-install / update
    .\install.ps1 -Edge        # latest main instead of latest release
    .\install.ps1 -Build       # build the resolved source locally
    .\install.ps1 -Adopt       # migrate a legacy pre-v1.1 installation
    .\install.ps1 -MountSsh    # opt in to mounting %USERPROFILE%\.ssh read-only

> **Note:** `irm ... | iex` does not support flags - PowerShell interprets them
> as arguments to `Invoke-Expression`, not the script. Use the local
> `.\install.ps1` form for `-Edge`, `-Build`, `-Adopt`, or `-MountSsh`.
> PowerShell streams runtime and Git failures directly by default.

> **Windows adapter boundary:** Keep install, rebuild, and uninstall on the
> adapter that created the Install identity. Native PowerShell and Git Bash
> use the same Install identity field names, but their native path and
> shell-profile values are not interchangeable;
> cross-adapter state consumption is rejected.
> Native PowerShell does not forward `SSH_AUTH_SOCK` and mounts
> `%USERPROFILE%\.ssh` read-only only when you opt in with `-MountSsh` or
> `SQUAREBOX_MOUNT_SSH=1`. The separate Git Bash adapter supports SSH
> agent-socket forwarding with its Bash lifecycle.
> Use `./scripts/migrate-windows-adapter.ps1 -Target PowerShell` or
> `-Target GitBash` from PowerShell 7 for an explicit cross-adapter migration.
> Normal installers and uninstallers continue to reject foreign adapter state.

## Server deployment

The `curl | bash` installer is built around an interactive desktop shell. To run
squarebox as a persistent server container you attach into on demand — on
Unraid, a NAS, or a VPS — use the prebuilt image directly with the bundled
`docker-compose.yml`:

    cp .env.example .env        # set PUID/PGID, the workspace path, and a tag
    docker compose up -d
    docker compose exec -u dev squarebox bash

Set `PUID`/`PGID` in `.env` to match your host so files squarebox writes to the
workspace mount are owned correctly — on Unraid that's `99` / `100`. The `-u dev`
on `exec` is needed because the container starts as root (to apply PUID/PGID)
then drops to the `dev` user; `exec` bypasses that, so `-u dev` lands you where
you want to be.

Per-user state (shell history, gh auth, mise toolchains, AI-assistant state)
lives in the `squarebox-home` named volume and survives image updates; your code
lives on the host at the workspace path. To update, pull a newer tag and
`docker compose up -d`. The published image is multi-arch (amd64 + arm64), so it
also runs on ARM NAS/VPS hosts.

> **Unraid note:** the host's `/root` is tmpfs and wiped on reboot, so a raw
> `curl | bash` install there won't persist. Either use compose (above) with the
> workspace path under `/mnt/user/appdata`, or run the installer with
> `SQUAREBOX_DIR` and `SQUAREBOX_WORKSPACE` pointed at appdata.

## Shell configuration

By default, squarebox uses Bash. During first-run setup you can opt in to
**Zsh**, **Fish**, or **PowerShell** instead.

**Zsh** installs:

| Name | Description |
|------|-------------|
| [zsh](https://www.zsh.org) | Z shell (via apt) |
| [Oh My Zsh](https://ohmyz.sh) | Community framework for managing zsh config |
| [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions) | Fish-like history-based suggestions |
| [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting) | Inline command syntax highlighting |

The generated `~/.zshrc` mirrors the default bashrc — same aliases, starship
prompt, zoxide, and AI/editor/SDK sourcing — layered on top of Oh My Zsh.

**Fish** installs [fish](https://fishshell.com) (via apt), which ships with
autosuggestions and syntax highlighting built in. The generated
`~/.config/fish/config.fish` mirrors the default bashrc in fish-native syntax;
AI/editor/TUI/SDK selections are translated from their bash files into
`~/.config/fish/conf.d/squarebox-selections.fish` at setup time.

**PowerShell** installs PowerShell 7 (`pwsh`) from Microsoft's official
[GitHub release](https://github.com/PowerShell/PowerShell/releases) `.deb`
(asset SHA-256 verified against the release metadata before install). The
generated `~/.config/powershell/profile.ps1` mirrors the default bashrc in
PowerShell-native syntax — starship, zoxide, and mise activate, plus the
standard aliases as functions (PowerShell `Set-Alias` cannot attach
arguments); AI/editor/TUI selections are translated from their bash files into
`~/.config/powershell/squarebox-selections.ps1` at setup time.

> The marker file `~/.squarebox-use-zsh`,
> `~/.squarebox-use-fish`, or `~/.squarebox-use-pwsh` causes `~/.bashrc` to
> `exec` the chosen shell on every interactive login, so the next shell start
> picks up the new shell. Set `SQUAREBOX_NO_ZSH=1`, `SQUAREBOX_NO_FISH=1`, or
> `SQUAREBOX_NO_PWSH=1` to force bash for a single session, or re-run
> `sqrbx-setup shell` to switch back permanently. Tooling is primarily tested
> against bash, so a few edge cases may need polish — please file an issue if
> you hit one. SDK shims are wired into all four shells via
> `mise activate {bash,zsh,fish,pwsh}`.

## Editor configuration

Selecting **nvim** offers to install the [LazyVim](https://www.lazyvim.org/) starter config to `~/.config/nvim`, turning Neovim into a preconfigured IDE. Plugins sync on first launch and persist in the `squarebox-home` volume. A Nerd Font in your terminal is recommended for icons; the starter is skipped if `~/.config/nvim` already exists, so your own config is never overwritten.

## SDK configuration

All SDKs are managed by [mise](https://github.com/jdx/mise) — a single
polyglot version manager. Selections are written to `~/.config/mise/config.toml`
and `mise activate` wires up shims and PATH automatically across bash, zsh,
and fish.

| SDK   | mise tool |
|-------|-----------|
| Node.js | `node` |
| Python  | `python` |
| Go      | `go` |
| .NET    | `dotnet` |
| Rust    | `rust` |

## Help and reconfiguration

Run `sqrbx-help` inside the container for a one-screen overview of the
`sqrbx-*` commands, Bash's fzf (`Ctrl+R`/`Ctrl+T`/`Alt+C`/`**<Tab>`) bindings,
and zoxide (`z`/`zi`) navigation. Zsh and Fish retain the `fzf`, `ff`, and
`eff` commands but do not claim those Bash-specific bindings. The MOTD points
to the help command on every shell start.

Re-run the first-run wizard at any time from inside the container with
`sqrbx-setup`. With no arguments it walks every section; pass one or more
section names to reconfigure just those: `git`, `github`, `ai`, `editors`,
`tuis`, `multiplexers`, `sdks`, `shell`. `sqrbx-setup --list` shows your
current selections and `sqrbx-setup --help` the usage.

## Aliases

| Alias | Command | Description |
|-------|---------|-------------|
| `ls` | `eza --icons` | Modern ls with icons |
| `ll` | `eza -la --icons` | Long listing with icons |
| `lsa` | `ls -a` (resolves to `eza --icons -a`) | List all including hidden files |
| `lt` | `eza --tree --level=2 --long --icons --git` | Tree view with git status |
| `lta` | `lt -a` | Tree view including hidden files |
| `cat` | `bat --paging=never` | Syntax-highlighted cat |
| `ff` | `fzf --preview 'bat ...'` | Fuzzy find with preview |
| `eff` | `$EDITOR "$(ff)"` | Fuzzy find and edit |
| `..` | `cd ..` | Go up one directory |
| `...` | `cd ../..` | Go up two directories |
| `....` | `cd ../../..` | Go up three directories |
| `c` | first selected AI tool | Launch selected AI assistant |
| `g` | `git` | Git shorthand |
| `gcm` | `git commit -m` | Commit with message |
| `gcam` | `git commit -a -m` | Stage all and commit |
| `gcad` | `git commit -a --amend` | Stage all and amend |
| `lg` | `lazygit` | Launch lazygit (if installed) |
| `claude-yolo` | `claude --dangerously-skip-permissions` | Claude without prompts |
| `copilot-yolo` | `copilot --allow-all` | Copilot CLI without permission prompts |
| `codex-yolo` | `codex --dangerously-bypass-approvals-and-sandbox` | Codex without prompts or sandboxing |
| `gemini-yolo` | `gemini --approval-mode=yolo` | Gemini CLI without prompts |
| `opencode-yolo` | `opencode --dangerously-skip-permissions` | OpenCode without prompts |
| `omp-yolo` | `omp --approval-mode yolo` | Oh My Pi without prompts |

The `*-yolo` aliases are generated only for selected AI tools that are
installed. They disable that tool's normal approval prompts; `codex-yolo` also
disables Codex's sandbox. Use them only in a workspace whose contents and
commands you trust.

## Keyboard shortcuts

Squarebox uses one portable rule: `Super` belongs
to the OS/window manager, while `Ctrl` acts immediately in the focused app.
Herdr uses `Ctrl+Alt` for direct letter chords because many terminals collapse
`Ctrl+Shift+letter` into the unshifted control key. Its `F12` prefix remains
available as a compatibility fallback.

Herdr's generated default uses familiar app shortcuts:

| Feature | Herdr |
|---------|-------|
| New / close | `Ctrl+T` / `Ctrl+W` |
| Cycle / select tabs | `Ctrl+Tab`, `Ctrl+Shift+Tab` / `Ctrl+1-9` |
| Focus / swap pane | `Ctrl+Arrow` / `Ctrl+Shift+Arrow` |
| Sidebar / go to | `Ctrl+B` / `Ctrl+G` |
| Split right / down | `Ctrl+\\` / `Ctrl+Alt+\\` |
| Zoom / new workspace | `Ctrl+Alt+Z` / `Ctrl+Alt+N` |
| Compatibility prefix | `F12` |

These bindings intentionally take precedence over matching shell or nested-app
shortcuts while Herdr is focused. Existing `~/.config/herdr/config.toml` files
remain user-managed and are never replaced by setup.

Tmux and Zellij use matching defaults:

| Feature | Tmux | Zellij |
|---------|------|--------|
| Config path | `~/.config/tmux/tmux.conf` | `~/.config/zellij/config.kdl` |
| Prefix | `Ctrl+Space` | `Ctrl+Space` (Tmux mode) |
| Alternate prefix | `Ctrl+B` | `Ctrl+B` (Tmux mode) |
| Prefix help | — | `prefix ?` |
| Pane navigation | `Ctrl+Alt+Arrow` | `Ctrl+Alt+Arrow` |
| Pane resizing | `Ctrl+Alt+Shift+Arrow` | `Ctrl+Alt+Shift+Arrow` |
| Tab/window select | `Alt+1-9` | `Alt+1-9` |
| Tab/window cycle | `Alt+Left/Right` | `Alt+Left/Right` |
| Split horizontal | `prefix h` | `prefix h` |
| Split vertical | `prefix v` | `prefix v` |
| Scrollback | 50,000 lines | 50,000 lines |
| Copy mode | Vi keys | Vi-style scroll |
| Theme | Blue accent, top bar | Blue accent, compact layout |

## Updates and rebuilds

### Quick update (from inside the container)

    sqrbx-update

Checks installed registered tools against upstream releases. A dry run never
installs absent optional tools; `--apply` updates the installed set only. Naming
an absent tool explicitly is an install request. Failures are aggregated,
reported with preserved logs, and return nonzero. Managed-home tools can advance
in place. Image-tier tools advance only through a newer Squarebox Candidate and
Box rebuild unless the current Candidate already authorizes the exact release
asset; an unvetted upstream release is reported but never advertised as applyable.
Broken version probes and incomplete Yazi, Helix, or Neovim output sets are
reported as repairs; a failed post-install verification restores prior managed
outputs.

    sqrbx-update              # show available updates (dry run)
    sqrbx-update --apply      # update all installed registered tools
    sqrbx-update lazygit      # update, or explicitly install, one tool
    sqrbx-update --list       # list all tools and current versions

Setup and `sqrbx-update` read GitHub release metadata through the GitHub API,
which allows only 60 unauthenticated requests per hour per IP address. On a
shared NAT or CI runner, authenticate those requests to avoid HTTP 403 rate
limits: export `GH_TOKEN` (or `GITHUB_TOKEN`), or run `gh auth login` inside
the Box. The token is optional, is sent only to the GitHub API, and a rejected
token falls back to unauthenticated requests.

### Full rebuild (from the host)

    sqrbx-rebuild

Resolves the requested published Release, pulls its immutable image digest, and
replaces the Box. Installations created with `--build` retain that choice and
build the matching source instead.
Your code in ~/squarebox/workspace is safe since it lives on the host. Most
in-container state (shell history, GitHub auth, SDK toolchains) survives
because /home/dev is backed by the `squarebox-home` named Docker volume.
Manually installed apt packages are still lost, since the image is rebuilt.

#### What survives a rebuild

| Survives | Reconciled or lost |
|----------|--------------------|
| Workspace code on the host | Selected tmux/Zsh/Fish packages are reconciled into the new Box |
| Managed home: history, auth, assistant data, mise toolchains | Manually installed, unselected APT packages are lost |
| Selection state in `/workspace/.squarebox` | Image-tier binaries are replaced by the Candidate digest |
| Host SSH access (agent forwarding, or the recorded `SQUAREBOX_MOUNT_SSH` opt-in) | Image-managed dotfiles are safely refreshed |

Use `sqrbx-uninstall --purge` to wipe recorded state. Do not remove a volume by
name alone; lifecycle commands verify the Install identity and ownership
labels before deleting a Managed resource.

> **Tip:** Use `sqrbx-update` from inside the container for Managed-home tools.
> Use `sqrbx-rebuild` for image-tier binaries, new APT packages, base-tool
> changes, or any upstream release the current Candidate cannot authorize.

## Dev Containers and Codespaces

Open this repo in VS Code with the
[Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers),
or launch it in [GitHub Codespaces](https://github.com/features/codespaces).
The included `.devcontainer/devcontainer.json` builds the full **squarebox** image
automatically and mounts the cloned repository at `/workspace`, matching setup
and Selection state. A per-Box named volume, derived from the stable
Dev Container identity, mounts at `/home/dev` so authentication, history, and
mise toolchains survive container rebuilds without being shared across
unrelated workspaces.

The interactive first-run wizard can't run in devcontainer mode (no TTY at
create time), so a default toolset — **Claude Code + Node.js** — is installed
non-interactively by `postCreateCommand`. Override the defaults with these
container environment variables (set to an empty string to opt out of a tier):

| Variable | Default | Selects |
|----------|---------|---------|
| `SQUAREBOX_DC_AI` | `claude` | AI assistants (`claude,copilot,gemini,codex,opencode,pi,omp`) |
| `SQUAREBOX_DC_SDKS` | `node` | SDKs (`node,python,go,dotnet,rust`) |
| `SQUAREBOX_DC_EDITORS` | _(none)_ | Editors (`micro,edit,fresh,helix,nvim`; Helix launches as `hx`) |
| `SQUAREBOX_DC_TUIS` | _(none)_ | TUI tools (`lazygit,gh-dash,yazi,elio`) |
| `SQUAREBOX_DC_MULTIPLEXERS` | _(none)_ | Multiplexers (`tmux,zellij,herdr`) |

To add or change tools after the fact, run `sqrbx-setup` from the integrated
terminal.

You can also attach to a running codespace directly from your local terminal
using `gh codespace ssh`. The official Dev Containers SSH server Feature is
version- and digest-locked for this path. It is added only to the derived Dev
Container image, not the published Squarebox Candidate, and remote-forwarded
ports remain bound to loopback by default.

## Uninstall and recovery

sqrbx-uninstall

Removes the recorded Box, owned image reference, and shell integration but **keeps**
the install directory/Workspace and Managed-home volume
(shell history, gh auth, mise toolchains) so your code and per-user state are
safe by default. Pass `--purge` to remove the Managed home and recorded install
directory. The default Workspace nested inside that directory is removed with
it; a custom external Workspace is always preserved:

    sqrbx-uninstall --purge

The confirmation summary lists a non-empty nested Workspace, with its item count,
as something that will be deleted, and a second confirmation is required.
Pass `-y` (or `-Yes` on PowerShell) to skip prompts for scripting. Unattended
purge refuses, before removing anything, to delete a non-empty nested
Workspace unless you also pass `--delete-workspace` (`-DeleteWorkspace` on
PowerShell):

    sqrbx-uninstall --purge --yes --delete-workspace

An empty Workspace or an external Workspace needs no extra flag.
Idempotent for a valid Install identity. Legacy resources require `--adopt`;
purging an adopted, unlabeled volume additionally requires `--force`.

**Windows (PowerShell 7+):**

    sqrbx-uninstall                # keep ~/squarebox
    sqrbx-uninstall -Purge         # also remove ~/squarebox
    sqrbx-uninstall -Yes           # skip confirmations
    sqrbx-uninstall -Purge -Yes -DeleteWorkspace  # also delete a non-empty nested Workspace

**Broken-state recovery** (e.g. shell functions are missing, or after partial
install): run the script matching the adapter that created the Install identity
directly from the install directory. PowerShell and Git Bash lifecycle state is
not cross-consumed:

    ~/squarebox/uninstall.sh              # Linux / macOS / Git Bash
    ~/squarebox/uninstall.ps1             # Windows PowerShell

Start a new shell afterwards (or `exec bash` / `exec zsh`) so the `sqrbx` and
`squarebox` functions are dropped from the current session.
