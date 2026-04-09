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
if [ -n "${USERPROFILE:-}" ]; then
	USER_HOME="$(cygpath -u "$USERPROFILE" 2>/dev/null || echo "$USERPROFILE")"
else
	USER_HOME="${HOME}"
fi
INSTALL_DIR="${USER_HOME}/squarebox"
IMAGE_NAME="squarebox"
CONTAINER_NAME="squarebox"
EDGE="${SQUAREBOX_EDGE:-0}"

for arg in "$@"; do
	case "$arg" in
		--edge) EDGE=1 ;;
	esac
done

# Clone or update
if [ -d "$INSTALL_DIR" ]; then
	echo "Updating existing install..."
	git -C "$INSTALL_DIR" fetch --tags --force origin
else
	echo "Cloning squarebox..."
	git clone "$REPO" "$INSTALL_DIR"
fi

# Select version: --edge uses latest main, default uses latest tagged release
if [ "$EDGE" = "1" ]; then
	echo "Using latest main (edge)..."
	git -C "$INSTALL_DIR" checkout main --quiet
	git -C "$INSTALL_DIR" pull --ff-only --quiet
else
	LATEST_TAG=$(git -C "$INSTALL_DIR" tag --sort=-v:refname | grep -v -- '-rc' | head -1)
	if [ -n "$LATEST_TAG" ]; then
		echo "Using release ${LATEST_TAG}..."
		git -C "$INSTALL_DIR" checkout "$LATEST_TAG" --quiet
	else
		echo "No releases found, using main branch..."
		git -C "$INSTALL_DIR" checkout main --quiet
		git -C "$INSTALL_DIR" pull --ff-only --quiet
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
echo "Building image..."
docker_cmd build -t "$IMAGE_NAME" "$INSTALL_DIR"

# Remove old container if it exists
if docker_cmd ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
	echo "Removing old container..."
	docker_cmd stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
	docker_cmd rm "$CONTAINER_NAME" >/dev/null
fi

# Shell config must go where bash/zsh actually reads from ($HOME), which may
# differ from USER_HOME on standalone MSYS2. The install directory uses
# USER_HOME so it lands somewhere visible, but shell config is separate.
case "${SHELL:-}" in
	*/zsh) SHELL_RC="${HOME}/.zshrc" ;;
	*)     SHELL_RC="${HOME}/.bashrc" ;;
esac

# Use shell functions (not aliases) so winpty detection happens at runtime
# rather than being baked in at install time. This way the same config works
# regardless of which terminal the user opens (Git Bash, PowerShell, etc.).
ALIASES_ADDED=false

_add_shell_func() {
	local name="$1" body="$2"
	if ! grep -q "^${name}()" "$SHELL_RC" 2>/dev/null; then
		printf '%s() { %s; }\n' "$name" "$body" >> "$SHELL_RC"
		ALIASES_ADDED=true
	fi
}

_docker_start='if command -v winpty &>/dev/null && [[ -n "${MSYSTEM:-}" ]]; then winpty docker start -ai squarebox; else docker start -ai squarebox; fi'
_add_shell_func "sqrbx" "$_docker_start"
_add_shell_func "squarebox" "$_docker_start"
_add_shell_func "sqrbx-rebuild" "${INSTALL_DIR}/install.sh"
_add_shell_func "squarebox-rebuild" "${INSTALL_DIR}/install.sh"

if [ "$ALIASES_ADDED" = true ]; then
	echo "Added squarebox functions to $SHELL_RC — restart your shell or run: source $SHELL_RC"
fi

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

# PowerShell 7+ profile (Windows) — uses functions since PS aliases can't take arguments.
# Only pwsh (7+) is supported; Windows PowerShell 5.1 is not.
# Query pwsh for the actual $PROFILE path since Documents may be redirected (e.g. OneDrive).
_pwsh=""
if command -v pwsh &>/dev/null; then
	_pwsh="$(command -v pwsh)"
elif [ -n "${MSYSTEM:-}" ] || [ -n "${USERPROFILE:-}" ]; then
	# pwsh is often not on Git Bash's PATH — search common Windows install locations
	for _candidate in \
		"$(cygpath -u "${PROGRAMFILES:-/c/Program Files}" 2>/dev/null)/PowerShell/7/pwsh.exe" \
		"$(cygpath -u "${LOCALAPPDATA:-}" 2>/dev/null)/Microsoft/PowerShell/pwsh.exe"; do
		if [ -x "$_candidate" ] 2>/dev/null; then
			_pwsh="$_candidate"
			break
		fi
	done
fi

echo "PowerShell profile setup:"
if [ -n "$_pwsh" ]; then
	echo "  pwsh: $_pwsh"
	_ps_profile_raw="$("$_pwsh" -NoProfile -Command '$PROFILE' 2>/dev/null | tr -d '\r' || true)"
	echo "  \$PROFILE (raw): ${_ps_profile_raw:-<empty>}"
	if [ -n "$_ps_profile_raw" ]; then
		_ps_profile="$(cygpath -u "$_ps_profile_raw" 2>/dev/null || echo "$_ps_profile_raw")"
		echo "  \$PROFILE (unix): $_ps_profile"
		mkdir -p "$(dirname "$_ps_profile")"
		if [ -f "$_ps_profile" ]; then
			echo "  Profile exists: yes ($(wc -l < "$_ps_profile") lines)"
		else
			echo "  Profile exists: no (will create)"
		fi
		if ! grep -q 'function sqrbx ' "$_ps_profile" 2>/dev/null; then
			cat >> "$_ps_profile" <<-'PSEOF'

			# squarebox aliases
			function sqrbx { docker start -ai squarebox }
			function squarebox { docker start -ai squarebox }
			function sqrbx-rebuild { bash "$HOME/squarebox/install.sh" }
			function squarebox-rebuild { bash "$HOME/squarebox/install.sh" }
			PSEOF
			if grep -q 'function sqrbx ' "$_ps_profile" 2>/dev/null; then
				echo "  => Added and verified squarebox functions in: $_ps_profile"
			else
				echo "  => ERROR: wrote to $_ps_profile but functions not found after write!"
			fi
			echo "  Restart PowerShell to use them."
			echo "  Note: if profile doesn't load, run: Set-ExecutionPolicy -Scope CurrentUser RemoteSigned"
		else
			echo "  => Functions already present, skipping."
		fi
	else
		echo "  => WARNING: pwsh returned empty \$PROFILE path."
	fi
else
	if [ -n "${MSYSTEM:-}" ] || [ -n "${USERPROFILE:-}" ]; then
		echo "  pwsh not found on PATH or in standard locations — skipping."
	else
		echo "  pwsh not found (not a Windows environment) — skipping."
	fi
fi

# Prepare host directories
mkdir -p "${USER_HOME}/.config/git" "${INSTALL_DIR}/workspace" "${INSTALL_DIR}/.config/lazygit"

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
	_win_gitcfg="$(cygpath -u "$USERPROFILE" 2>/dev/null || echo "$USERPROFILE")/.gitconfig"
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

docker_cmd create -it --name "$CONTAINER_NAME" \
	"${DOCKER_OPTS[@]}" \
	"${DOCKER_VOLUMES[@]}" \
	"$IMAGE_NAME" > /dev/null

if [ -t 0 ]; then
	docker_interactive start -ai "$CONTAINER_NAME"
else
	echo "Install complete. Run 'squarebox' (or 'sqrbx') to start (you may need to restart your shell first)."
fi
