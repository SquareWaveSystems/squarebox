#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/SquareWaveSystems/squarebox.git"

# On Windows/mintty (Git Bash), docker needs winpty for interactive TTY
# passthrough. mintty uses named pipes instead of the Windows Console API,
# which breaks interactive docker commands. winpty bridges the gap.
# PowerShell and CMD work natively — this only activates in MSYS2/mintty.
docker_interactive() {
    if [[ -n "${MSYSTEM:-}" || "${TERM_PROGRAM:-}" == "mintty" ]] \
        && command -v winpty &>/dev/null; then
        winpty docker "$@"
    else
        docker "$@"
    fi
}

INSTALL_DIR="${HOME}/squarebox"
IMAGE_NAME="squarebox"
CONTAINER_NAME="squarebox"

# Clone or update
if [ -d "$INSTALL_DIR" ]; then
	echo "Updating existing install..."
	git -C "$INSTALL_DIR" pull --ff-only
else
	echo "Cloning squarebox..."
	git clone "$REPO" "$INSTALL_DIR"
fi

# Verify Docker is available
if ! command -v docker &>/dev/null; then
	echo "Error: Docker is not installed. See https://docs.docker.com/get-docker/" >&2
	exit 1
fi
if ! docker info &>/dev/null; then
	echo "Error: Docker daemon is not running or current user lacks permissions." >&2
	exit 1
fi

# Build
echo "Building image..."
docker build -t "$IMAGE_NAME" "$INSTALL_DIR"

# Remove old container if it exists
if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
	echo "Removing old container..."
	docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
	docker rm "$CONTAINER_NAME" >/dev/null
fi

# Add shell aliases
case "${SHELL:-}" in
	*/zsh) SHELL_RC="${HOME}/.zshrc" ;;
	*)     SHELL_RC="${HOME}/.bashrc" ;;
esac

# Determine docker start command (winpty needed on mintty/MSYS2)
if [[ -n "${MSYSTEM:-}" || "${TERM_PROGRAM:-}" == "mintty" ]] \
    && command -v winpty &>/dev/null; then
	DOCKER_START="winpty docker start -ai squarebox"
else
	DOCKER_START="docker start -ai squarebox"
fi

ALIASES_ADDED=false

if ! grep -q 'alias sqrbx=' "$SHELL_RC" 2>/dev/null; then
	echo "alias sqrbx='${DOCKER_START}'" >> "$SHELL_RC"
	ALIASES_ADDED=true
fi

if ! grep -q 'alias squarebox=' "$SHELL_RC" 2>/dev/null; then
	echo "alias squarebox='${DOCKER_START}'" >> "$SHELL_RC"
	ALIASES_ADDED=true
fi

if ! grep -q 'alias sqrbx-rebuild=' "$SHELL_RC" 2>/dev/null; then
	echo "alias sqrbx-rebuild='~/squarebox/install.sh'" >> "$SHELL_RC"
	ALIASES_ADDED=true
fi

if ! grep -q 'alias squarebox-rebuild=' "$SHELL_RC" 2>/dev/null; then
	echo "alias squarebox-rebuild='~/squarebox/install.sh'" >> "$SHELL_RC"
	ALIASES_ADDED=true
fi

if [ "$ALIASES_ADDED" = true ]; then
	echo "Added squarebox aliases to $SHELL_RC — restart your shell or run: source $SHELL_RC"
fi

# PowerShell profile (Windows) — uses functions since PS aliases can't take arguments
if [ -n "${USERPROFILE:-}" ]; then
	_ps_dir="$(cygpath -u "$USERPROFILE" 2>/dev/null || echo "$USERPROFILE")/Documents/PowerShell"
	_ps_profile="${_ps_dir}/Microsoft.PowerShell_profile.ps1"
	if [ -d "$_ps_dir" ] || command -v pwsh &>/dev/null; then
		mkdir -p "$_ps_dir"
		PS_ADDED=false
		if ! grep -q 'function sqrbx ' "$_ps_profile" 2>/dev/null; then
			cat >> "$_ps_profile" <<-'PSEOF'

			# squarebox aliases
			function sqrbx { docker start -ai squarebox }
			function squarebox { docker start -ai squarebox }
			function sqrbx-rebuild { & "$HOME/squarebox/install.sh" }
			function squarebox-rebuild { & "$HOME/squarebox/install.sh" }
			PSEOF
			PS_ADDED=true
		fi
		if [ "$PS_ADDED" = true ]; then
			echo "Added squarebox functions to PowerShell profile — restart PowerShell to use them."
		fi
	fi
fi

# Prepare host directories
mkdir -p "${HOME}/.config/git" "${INSTALL_DIR}/workspace" "${INSTALL_DIR}/.config/lazygit"

# Propagate host git identity into the container's config directory.
# This avoids fragile file mounts on Windows/MSYS2 and prevents leaking
# credential helpers or tokens from the host's full git config.
#
# On MSYS2/Git Bash, HOME may point to the MSYS home (/home/user) rather than
# the Windows profile (C:/Users/user), so git config --global misses the real
# gitconfig. Fall back to reading from the Windows profile path via USERPROFILE.
_git_cfg="${HOME}/.config/git/config"

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

# Migrate from old layout if needed
if [ -d "${HOME}/squarebox-workspace" ] && [ ! -d "${INSTALL_DIR}/workspace" ]; then
	echo "Migrating ~/squarebox-workspace to ~/squarebox/workspace..."
	mv "${HOME}/squarebox-workspace" "${INSTALL_DIR}/workspace"
fi

# Seed default configs (preserves existing customizations)
if [ ! -f "${INSTALL_DIR}/.config/starship.toml" ]; then
	cp "${INSTALL_DIR}/starship.toml" "${INSTALL_DIR}/.config/starship.toml"
fi
if [ ! -f "${INSTALL_DIR}/.config/lazygit/config.yml" ]; then
	printf 'git:\n  paging:\n    colorArg: always\n    pager: delta --dark --paging=never\n' > "${INSTALL_DIR}/.config/lazygit/config.yml"
fi

echo "Creating container..."
DOCKER_VOLUMES=(
	-v "${INSTALL_DIR}/workspace:/workspace"
	-v "${HOME}/.ssh:/home/dev/.ssh:ro"
	-v "${HOME}/.config/git:/home/dev/.config/git"
	-v "${INSTALL_DIR}/.config/starship.toml:/home/dev/.config/starship.toml"
	-v "${INSTALL_DIR}/.config/lazygit:/home/dev/.config/lazygit"
	-v /etc/localtime:/etc/localtime:ro
)

docker create -it --name "$CONTAINER_NAME" \
	"${DOCKER_VOLUMES[@]}" \
	"$IMAGE_NAME" > /dev/null

if [ -t 0 ]; then
	docker_interactive start -ai "$CONTAINER_NAME"
else
	echo "Install complete. Run 'squarebox' (or 'sqrbx') to start (you may need to restart your shell first)."
fi
