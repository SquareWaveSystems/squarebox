#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/SquareWaveSystems/squarebox.git"

# On MSYS2/Git Bash, automatic path conversion mangles the ":" separator in
# Docker volume mounts (-v host:container), causing mounts to point to wrong
# locations. MSYS_NO_PATHCONV disables this for docker commands.
docker_cmd() {
    if [[ -n "${MSYSTEM:-}" ]]; then
        MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' docker "$@"
    else
        docker "$@"
    fi
}

# On Windows/mintty (Git Bash), docker needs winpty for interactive TTY
# passthrough. mintty uses named pipes instead of the Windows Console API,
# which breaks interactive docker commands. winpty bridges the gap.
# PowerShell and CMD work natively — this only activates in MSYS2/mintty.
docker_interactive() {
    if [[ -n "${MSYSTEM:-}" || "${TERM_PROGRAM:-}" == "mintty" ]] \
        && command -v winpty &>/dev/null; then
        MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' winpty docker "$@"
    else
        docker "$@"
    fi
}

# On MSYS2/Git Bash, HOME points to the MSYS home (/home/user) which maps to
# an obscure Windows path (e.g. C:\Program Files\Git\home\user). Use USERPROFILE
# instead so the install lands at a normal location (C:\Users\user\squarebox).
# Mixed-mode (C:/Users/...) keeps paths compatible with both bash and Docker —
# MSYS2-format (/c/Users/...) breaks Docker when MSYS_NO_PATHCONV=1 is set.
#
# When Git Bash is invoked non-interactively from PowerShell (& bash.exe script),
# /etc/profile isn't sourced and cygpath may not be on PATH. The fallback converts
# MSYS2 POSIX paths (/c/Users/...) and Windows backslash paths (C:\Users\...)
# to mixed-mode manually.
if [ -n "${USERPROFILE:-}" ]; then
	USER_HOME="$(cygpath -m "$USERPROFILE" 2>/dev/null || true)"
	if [ -z "$USER_HOME" ]; then
		USER_HOME="${USERPROFILE//\\//}"
		# /c/Users/... → C:/Users/...
		if [[ "$USER_HOME" =~ ^/([a-zA-Z])(/.*)$ ]]; then
			USER_HOME="$(printf '%s' "${BASH_REMATCH[1]}" | tr '[:lower:]' '[:upper:]'):${BASH_REMATCH[2]}"
		fi
	fi
else
	USER_HOME="${HOME}"
fi
INSTALL_DIR="${USER_HOME}/squarebox"
IMAGE_NAME="squarebox"
CONTAINER_NAME="squarebox"
EDGE="${SQUAREBOX_EDGE:-0}"
VERBOSE=0

for arg in "$@"; do
	case "$arg" in
		--edge) EDGE=1 ;;
		--verbose) VERBOSE=1 ;;
	esac
done

# --quiet is applied to git operations unless --verbose is set
GIT_QUIET=(--quiet)
[ "$VERBOSE" = 1 ] && GIT_QUIET=()

# Clone or update
if [ -d "$INSTALL_DIR" ]; then
	echo "Updating existing install..."
	git -C "$INSTALL_DIR" fetch --tags --force "${GIT_QUIET[@]}" origin
else
	echo "Cloning squarebox..."
	git clone "${GIT_QUIET[@]}" "$REPO" "$INSTALL_DIR"
fi

# Select version: --edge uses latest main, default uses latest tagged release.
# The install dir is managed by this script — treat origin as source of truth and
# hard-reset rather than merging, so a diverged local main doesn't block updates.
if [ "$EDGE" = "1" ]; then
	echo "Using latest main (edge)..."
	git -C "$INSTALL_DIR" checkout main "${GIT_QUIET[@]}"
	git -C "$INSTALL_DIR" reset --hard "${GIT_QUIET[@]}" origin/main
else
	LATEST_TAG=$(git -C "$INSTALL_DIR" tag --sort=-v:refname | grep -v -- '-rc' | head -1)
	if [ -n "$LATEST_TAG" ]; then
		echo "Using release ${LATEST_TAG}..."
		git -C "$INSTALL_DIR" checkout "$LATEST_TAG" "${GIT_QUIET[@]}"
	else
		echo "No releases found, using main branch..."
		git -C "$INSTALL_DIR" checkout main "${GIT_QUIET[@]}"
		git -C "$INSTALL_DIR" reset --hard "${GIT_QUIET[@]}" origin/main
	fi
fi

# Verify Docker is available
if ! command -v docker &>/dev/null; then
	echo "Error: Docker is not installed. See https://docs.docker.com/get-docker/" >&2
	exit 1
fi
if ! docker_cmd info &>/dev/null; then
	echo "Error: Docker daemon is not running or current user lacks permissions." >&2
	exit 1
fi

# Build
_build_log="$(mktemp)"
_rc_tmp=""
_create_log=""
trap 'rm -f "$_build_log" "$_rc_tmp" "$_create_log" 2>/dev/null || true' EXIT
if [ "$VERBOSE" = 1 ]; then
	echo "Building image..."
	docker_cmd build -t "$IMAGE_NAME" "$INSTALL_DIR"
else
	printf "Building image... "
	if docker_cmd build -t "$IMAGE_NAME" "$INSTALL_DIR" > "$_build_log" 2>&1; then
		echo "done"
	else
		echo "FAILED" >&2
		echo "Build output:" >&2
		cat "$_build_log" >&2
		exit 1
	fi
fi

# Remove old container if it exists
if docker_cmd ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
	echo "Removing old container..."
	docker_cmd stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
	docker_cmd rm "$CONTAINER_NAME" >/dev/null
fi

# Shell config must go where bash/zsh actually reads from ($HOME), which may
# differ from USER_HOME on standalone MSYS2. The install directory uses
# USER_HOME so it lands somewhere visible, but shell config is separate.
# On Git Bash (MSYSTEM set) force .bashrc regardless of $SHELL — if install.sh
# is re-invoked from a parent PowerShell, $SHELL may be unset or unrelated.
if [ -n "${MSYSTEM:-}" ]; then
	SHELL_RC="${HOME}/.bashrc"
else
	case "${SHELL:-}" in
		*/zsh) SHELL_RC="${HOME}/.zshrc" ;;
		*)     SHELL_RC="${HOME}/.bashrc" ;;
	esac
fi

# Write the function bodies to a dedicated file that install.sh overwrites on
# every run, and reference it from $SHELL_RC via a sentinel one-liner. Mirrors
# the pattern already used inside the container (see Dockerfile: ~/.squarebox-*
# aliases sourced from ~/.bashrc). Benefits:
#  - Future updates just overwrite the init file, no rc-file splicing.
#  - Legacy `alias sqrbx=...` / `sqrbx() {...}` cruft from older install.sh
#    versions gets scrubbed on every run — critical because an old alias
#    shadows the new function definition at parse time (expand_aliases is on
#    in interactive bash), producing a `syntax error near unexpected token '('`.
#
# The init file lives under $HOME (not $USER_HOME): on Git Bash these diverge
# (HOME=/home/user, USER_HOME=C:/Users/... from USERPROFILE), and the sentinel
# in $SHELL_RC sources `$HOME/.squarebox-shell-init` at shell startup — the
# init file must live where the running shell looks for it. The install dir
# itself still lives under USER_HOME, so INSTALL_DIR is baked into the body
# of sqrbx-rebuild below (unquoted heredoc) rather than using a runtime
# `$HOME/squarebox/install.sh` which would be wrong on Git Bash.
SQRBX_INIT="${HOME}/.squarebox-shell-init"
cat > "$SQRBX_INIT" <<SQRBXEOF
# Managed by squarebox install.sh — overwritten on every install.
# Drop any stale aliases with these names so they don't shadow the functions.
unalias sqrbx squarebox sqrbx-rebuild squarebox-rebuild 2>/dev/null || true
sqrbx() {
	# If the container was left running after an ungraceful exit (closed
	# terminal instead of \`exit\`), attaching to PID1 bash drops you onto a
	# prompt it already printed to the dead TTY — blinking cursor, no
	# output. Reset so the next start attaches to a fresh PID1 that paints
	# a visible prompt.
	if [ "\$(docker inspect -f '{{.State.Running}}' squarebox 2>/dev/null)" = "true" ]; then
		docker stop squarebox >/dev/null 2>&1 || true
	fi
	if command -v winpty &>/dev/null && [[ -n "\${MSYSTEM:-}" ]]; then
		winpty docker start -ai squarebox
	else
		docker start -ai squarebox
	fi
}
squarebox() { sqrbx "\$@"; }
sqrbx-rebuild() { "${INSTALL_DIR}/install.sh" "\$@"; }
squarebox-rebuild() { sqrbx-rebuild "\$@"; }
SQRBXEOF

# Scrub legacy content from $SHELL_RC and append a fresh sentinel block that
# sources $SQRBX_INIT. Portable awk + mktemp + mv (no `sed -i` GNU/BSD footgun).
if [ -f "$SHELL_RC" ]; then
	_rc_tmp="$(mktemp "${SHELL_RC}.sqrbx.XXXXXX")"
	awk '
		/^# >>> squarebox >>>/ { skip=1; next }
		/^# <<< squarebox <<</ { skip=0; next }
		skip { next }
		/^[[:space:]]*alias[[:space:]]+(sqrbx|squarebox|sqrbx-rebuild|squarebox-rebuild)=/ { next }
		/^(sqrbx|squarebox|sqrbx-rebuild|squarebox-rebuild)\(\)[[:space:]]*\{/ { next }
		{ print }
	' "$SHELL_RC" > "$_rc_tmp" && mv "$_rc_tmp" "$SHELL_RC"
	_rc_tmp=""
fi

cat >> "$SHELL_RC" <<'SQRBXRCEOF'
# >>> squarebox >>>
[ -f "$HOME/.squarebox-shell-init" ] && . "$HOME/.squarebox-shell-init"
# <<< squarebox <<<
SQRBXRCEOF

echo "Installed squarebox shell integration → $SHELL_RC"

# Self-check: catch future regressions that would break the rc file at source
# time. Use the matching shell's parser — bash -n rejects valid zsh syntax
# (setopt, glob qualifiers, etc.) and would trigger false warnings for zsh users.
case "$SHELL_RC" in
	*.bashrc|*.bash_profile|*/.bashrc|*/.bash_profile)
		if ! bash -n "$SHELL_RC" 2>/dev/null; then
			echo "Warning: $SHELL_RC fails bash syntax check after edit — please inspect." >&2
		fi
		;;
	*.zshrc|*.zprofile|*/.zshrc|*/.zprofile)
		if command -v zsh >/dev/null 2>&1 && ! zsh -n "$SHELL_RC" 2>/dev/null; then
			echo "Warning: $SHELL_RC fails zsh syntax check after edit — please inspect." >&2
		fi
		;;
esac
# end squarebox shell integration

# Git Bash on Windows opens a login shell which reads .bash_profile (not
# .bashrc). Ensure .bash_profile sources .bashrc so aliases are available.
# Both files must live under $HOME (where bash reads from).
if [[ -n "${MSYSTEM:-}" ]] && [[ "${SHELL_RC}" == *".bashrc" ]]; then
	_bash_profile="${HOME}/.bash_profile"
	if ! grep -q '\.bashrc' "$_bash_profile" 2>/dev/null; then
		cat >> "$_bash_profile" <<-'BPEOF'

		# Source .bashrc for aliases and functions
		[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"
		BPEOF
		echo "Updated .bash_profile to source .bashrc."
	fi
fi

# PowerShell 7+ profile (Windows). install.ps1 handles everything natively
# (clone, build, container, profile) — no Git Bash needed. If the user ran
# install.sh directly from Git Bash, nudge them toward install.ps1 for
# PowerShell integration.
if [ -n "${MSYSTEM:-}" ] || [ -n "${USERPROFILE:-}" ]; then
	_ps1_path="$(cygpath -w "${INSTALL_DIR}/install.ps1" 2>/dev/null || echo "${INSTALL_DIR}\\install.ps1")"
	echo ""
	echo "PowerShell: for native PowerShell support (no Git Bash needed), run:"
	echo "  pwsh -File \"${_ps1_path}\""
	echo ""
fi

# Prepare host directories
mkdir -p "${USER_HOME}/.config/git" "${INSTALL_DIR}/workspace" "${INSTALL_DIR}/.config/lazygit"

# On Linux where host uid != 1000, a previous install may have chowned
# ${USER_HOME}/.config/git to 1000:1000 (for the container's `dev` user), so
# `git config --file` below would fail with "could not lock config file". If
# that's the case, reclaim ownership back to the current user before writing.
# Only this one path needs reclaiming — INSTALL_DIR/workspace is never written
# to from install.sh, and INSTALL_DIR/.config writes further down are all
# guarded by `[ ! -f ]` so only fire on first install where we just mkdir'd
# the dir as the current user. The final chown-to-1000 still runs further down.
if [ "$(uname -s)" = "Linux" ] && [ "$(id -u)" -ne 1000 ] && [ ! -w "${USER_HOME}/.config/git" ]; then
	if [ "$(id -u)" -eq 0 ]; then
		chown -R "$(id -u):$(id -g)" "${USER_HOME}/.config/git"
	elif command -v sudo &>/dev/null; then
		sudo chown -R "$(id -u):$(id -g)" "${USER_HOME}/.config/git"
	fi
	if [ ! -w "${USER_HOME}/.config/git" ]; then
		echo "Error: ${USER_HOME}/.config/git is not writable by uid $(id -u)." >&2
		echo "       A previous install chowned it to uid 1000 for the container." >&2
		echo "       Fix: sudo chown -R $(id -u):$(id -g) ${USER_HOME}/.config/git" >&2
		exit 1
	fi
fi

# Propagate host git identity into the container's config directory.
# This avoids fragile file mounts on Windows/MSYS2 and prevents leaking
# credential helpers or tokens from the host's full git config.
#
# On MSYS2/Git Bash, HOME may point to the MSYS home (/home/user) rather than
# the Windows profile (C:/Users/user), so git config --global misses the real
# gitconfig. Fall back to reading from the Windows profile path via USERPROFILE.
_git_cfg="${USER_HOME}/.config/git/config"

_host_name="$(git config --global user.name 2>/dev/null || true)"
_host_email="$(git config --global user.email 2>/dev/null || true)"

if [ -z "$_host_name" ] && [ -n "${USERPROFILE:-}" ]; then
	_win_gitcfg="${USER_HOME}/.gitconfig"
	if [ -f "$_win_gitcfg" ]; then
		_host_name="$(git config --file "$_win_gitcfg" user.name 2>/dev/null || true)"
		_host_email="$(git config --file "$_win_gitcfg" user.email 2>/dev/null || true)"
	fi
fi

[ -n "$_host_name" ] && git config --file "$_git_cfg" user.name "$_host_name"
[ -n "$_host_email" ] && git config --file "$_git_cfg" user.email "$_host_email"

# Seed default configs (preserves existing customizations)
if [ ! -f "${INSTALL_DIR}/.config/starship.toml" ]; then
	cp "${INSTALL_DIR}/starship.toml" "${INSTALL_DIR}/.config/starship.toml"
fi
if [ ! -f "${INSTALL_DIR}/.config/lazygit/config.yml" ]; then
	printf 'git:\n  paging:\n    colorArg: always\n    pager: delta --dark --paging=never\n' > "${INSTALL_DIR}/.config/lazygit/config.yml"
fi

# The container's `dev` user is uid 1000. On native Linux, bind mounts preserve
# host ownership, so when the host user's uid differs (e.g. installing as root
# on DietPi), `dev` can't write to the mounted dirs and setup.sh fails with
# "Permission denied". Chown the host paths we manage to 1000:1000 in that case.
# Linux-only: macOS and Windows Docker Desktop remap bind-mount ownership
# transparently via their VMs, so chowning host dirs there is both unnecessary
# and harmful (uid 1000 typically doesn't exist on the host).
if [ "$(uname -s)" = "Linux" ] && [ "$(id -u)" -ne 1000 ]; then
	_chown_paths=(
		"${USER_HOME}/.config/git"
		"${INSTALL_DIR}/workspace"
		"${INSTALL_DIR}/.config"
	)
	if [ "$(id -u)" -eq 0 ]; then
		_chown=(chown)
	elif command -v sudo &>/dev/null; then
		echo "Host uid $(id -u) differs from container 'dev' uid (1000); using sudo to chown mount dirs..."
		_chown=(sudo chown)
	else
		echo "Warning: host uid $(id -u) differs from container 'dev' uid (1000) and sudo is unavailable." >&2
		echo "         You may see permission errors in the container. Manually run:" >&2
		echo "         chown -R 1000:1000 ${_chown_paths[*]}" >&2
		_chown=()
	fi
	if [ ${#_chown[@]} -gt 0 ]; then
		"${_chown[@]}" -R 1000:1000 "${_chown_paths[@]}"
	fi
fi

echo "Creating container..."
DOCKER_OPTS=()
DOCKER_VOLUMES=(
	-v "${INSTALL_DIR}/workspace:/workspace"
	-v "${USER_HOME}/.config/git:/home/dev/.config/git"
	-v "${INSTALL_DIR}/.config/starship.toml:/home/dev/.config/starship.toml"
	-v "${INSTALL_DIR}/.config/lazygit:/home/dev/.config/lazygit"
)
# /etc/localtime doesn't exist on Windows — only mount it on Linux/macOS
[ -f /etc/localtime ] && DOCKER_VOLUMES+=(-v /etc/localtime:/etc/localtime:ro)

# SSH: prefer agent forwarding (private keys never enter the container).
# Falls back to mounting ~/.ssh read-only if no agent is detected.
if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "$SSH_AUTH_SOCK" ]; then
	DOCKER_VOLUMES+=(-v "$SSH_AUTH_SOCK:/tmp/ssh-agent.sock")
	DOCKER_OPTS+=(-e SSH_AUTH_SOCK=/tmp/ssh-agent.sock)
	[ -f "${USER_HOME}/.ssh/config" ] && DOCKER_VOLUMES+=(-v "${USER_HOME}/.ssh/config:/home/dev/.ssh/config:ro")
	[ -f "${USER_HOME}/.ssh/known_hosts" ] && DOCKER_VOLUMES+=(-v "${USER_HOME}/.ssh/known_hosts:/home/dev/.ssh/known_hosts:ro")
elif [ -d "${USER_HOME}/.ssh" ]; then
	echo "Note: SSH agent not detected — mounting ~/.ssh read-only"
	DOCKER_VOLUMES+=(-v "${USER_HOME}/.ssh:/home/dev/.ssh:ro")
fi

# Drop all Linux capabilities except those needed for scoped sudo
DOCKER_OPTS+=(--cap-drop=ALL --cap-add=CHOWN --cap-add=DAC_OVERRIDE --cap-add=FOWNER --cap-add=SETUID --cap-add=SETGID --cap-add=KILL)

_create_log="$(mktemp)"
if ! docker_cmd create -it --name "$CONTAINER_NAME" \
	"${DOCKER_OPTS[@]}" \
	"${DOCKER_VOLUMES[@]}" \
	"$IMAGE_NAME" > "$_create_log" 2>&1; then
	echo "Error: failed to create container '$CONTAINER_NAME'." >&2
	cat "$_create_log" >&2
	exit 1
fi

if [ -t 0 ]; then
	docker_interactive start -ai "$CONTAINER_NAME"
else
	echo "Install complete. Run 'squarebox' (or 'sqrbx') to start (you may need to restart your shell first)."
fi
