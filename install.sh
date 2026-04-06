#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/BrettKinny/SquareBox.git"
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
	docker stop "$CONTAINER_NAME" 2>/dev/null || true
	docker rm "$CONTAINER_NAME"
fi

# Add shell aliases
case "${SHELL:-}" in
	*/zsh) SHELL_RC="${HOME}/.zshrc" ;;
	*)     SHELL_RC="${HOME}/.bashrc" ;;
esac

ALIASES_ADDED=false

if ! grep -q 'alias sqrbx=' "$SHELL_RC" 2>/dev/null; then
	echo "alias sqrbx='docker start -ai squarebox'" >> "$SHELL_RC"
	ALIASES_ADDED=true
fi

if ! grep -q 'alias sqrbx-rebuild=' "$SHELL_RC" 2>/dev/null; then
	echo "alias sqrbx-rebuild='~/squarebox/install.sh'" >> "$SHELL_RC"
	ALIASES_ADDED=true
fi

if [ "$ALIASES_ADDED" = true ]; then
	echo "Added sqrbx aliases to $SHELL_RC — restart your shell or run: source $SHELL_RC"
fi

# Prepare host directories
mkdir -p ~/.config/git "${INSTALL_DIR}/workspace" "${INSTALL_DIR}/.config/lazygit"

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
docker create -it --name "$CONTAINER_NAME" \
	-v "${INSTALL_DIR}/workspace:/workspace" \
	-v ~/.ssh:/home/dev/.ssh:ro \
	-v ~/.config/git:/home/dev/.config/git \
	-v "${INSTALL_DIR}/.config/starship.toml:/home/dev/.config/starship.toml" \
	-v "${INSTALL_DIR}/.config/lazygit:/home/dev/.config/lazygit" \
	"$IMAGE_NAME" > /dev/null

if [ -t 0 ]; then
	docker start -ai "$CONTAINER_NAME"
else
	echo "Install complete. Run 'sqrbx' to start (you may need to restart your shell first)."
fi
