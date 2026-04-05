#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/BrettKinny/squarebox.git"
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

if ! grep -q 'alias sqrbx=' "$SHELL_RC" 2>/dev/null; then
	echo "alias sqrbx='docker start -ai squarebox'" >> "$SHELL_RC"
	ALIASES_ADDED=true
fi

if ! grep -q 'alias sqrbx-update=' "$SHELL_RC" 2>/dev/null; then
	echo "alias sqrbx-update='~/squarebox/install.sh'" >> "$SHELL_RC"
	ALIASES_ADDED=true
fi

if [ "$ALIASES_ADDED" = true ]; then
	echo "Added sqrbx aliases to $SHELL_RC — restart your shell or run: source $SHELL_RC"
fi

# Create and enter container
mkdir -p ~/.config/git ~/squarebox-workspace

echo "Creating container..."
docker create -it --name "$CONTAINER_NAME" \
	-v ~/squarebox-workspace:/workspace \
	-v ~/.ssh:/home/dev/.ssh:ro \
	-v ~/.config/git:/home/dev/.config/git \
	"$IMAGE_NAME" > /dev/null

if [ -t 0 ]; then
	docker start -ai "$CONTAINER_NAME"
else
	echo "Install complete. Run 'sqrbx' to start (you may need to restart your shell first)."
fi
