#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/BrettKinny/tui-devbox.git"
INSTALL_DIR="${HOME}/tui-devbox"
IMAGE_NAME="devbox"
CONTAINER_NAME="devbox"

# Clone or update
if [ -d "$INSTALL_DIR" ]; then
	echo "Updating existing install..."
	git -C "$INSTALL_DIR" pull --ff-only
else
	echo "Cloning tui-devbox..."
	git clone "$REPO" "$INSTALL_DIR"
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
SHELL_RC="${HOME}/.bashrc"
[ -f "${HOME}/.zshrc" ] && SHELL_RC="${HOME}/.zshrc"

ALIASES_ADDED=false

if ! grep -q 'alias devbox=' "$SHELL_RC" 2>/dev/null; then
	echo "alias devbox='docker start -ai devbox'" >> "$SHELL_RC"
	ALIASES_ADDED=true
fi

if ! grep -q 'alias devbox-update=' "$SHELL_RC" 2>/dev/null; then
	echo "alias devbox-update='~/tui-devbox/install.sh'" >> "$SHELL_RC"
	ALIASES_ADDED=true
fi

if [ "$ALIASES_ADDED" = true ]; then
	echo "Added devbox aliases to $SHELL_RC — restart your shell or run: source $SHELL_RC"
fi

# Create and enter container
echo "Creating container..."
mkdir -p ~/.config/git ~/tui-devbox-workspace
docker run -it --name "$CONTAINER_NAME" \
	-v ~/tui-devbox-workspace:/workspace \
	-v ~/.ssh:/home/dev/.ssh:ro \
	-v ~/.config/git:/home/dev/.config/git \
	"$IMAGE_NAME"
