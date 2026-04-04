#!/usr/bin/env bash
set -euo pipefail

echo "=== TUI Devbox Setup ==="
echo

# Git identity
if [ -z "$(git config --global user.name 2>/dev/null)" ]; then
	read -rp "Git name: " name
	git config --global user.name "$name"
fi

if [ -z "$(git config --global user.email 2>/dev/null)" ]; then
	read -rp "Git email: " email
	git config --global user.email "$email"
fi

# Restore GitHub CLI config from persistent storage if available
GH_PERSIST="/workspace/.devbox/gh"
if [ -d "$GH_PERSIST" ] && [ ! -d ~/.config/gh ]; then
	mkdir -p ~/.config
	cp -r "$GH_PERSIST" ~/.config/gh
fi

# GitHub CLI
if ! gh auth status &>/dev/null; then
	echo
	echo "Logging into GitHub..."
	BROWSER=echo gh auth login
	# Persist gh config for future rebuilds
	mkdir -p "$GH_PERSIST"
	cp -r ~/.config/gh/* "$GH_PERSIST"/
else
	echo "GitHub CLI: already authenticated"
fi

# AI coding assistant
AI_CONFIG="/workspace/.devbox/ai-tool"
mkdir -p /workspace/.devbox ~/.local/bin

if [ -f "$AI_CONFIG" ]; then
	ai_choice=$(cat "$AI_CONFIG")
	echo "Installing AI tool: $ai_choice (from previous selection)"
else
	echo
	echo "Choose your AI coding assistant:"
	echo "  1) Claude Code"
	echo "  2) OpenCode"
	echo "  3) Both"
	read -rp "Selection [1/2/3]: " selection
	case "$selection" in
		1) ai_choice="claude" ;;
		2) ai_choice="opencode" ;;
		3) ai_choice="both" ;;
		*) echo "Invalid selection, defaulting to Claude Code"; ai_choice="claude" ;;
	esac
	echo "$ai_choice" > "$AI_CONFIG"
fi

if [ "$ai_choice" = "claude" ] || [ "$ai_choice" = "both" ]; then
	echo "Installing Claude Code..."
	curl -fsSL https://claude.ai/install.sh | bash
fi

if [ "$ai_choice" = "opencode" ] || [ "$ai_choice" = "both" ]; then
	echo "Installing OpenCode..."
	ARCH=$(uname -m)
	if [ "$ARCH" = "aarch64" ]; then OCARCH="arm64"; else OCARCH="x64"; fi
	curl -fsSL "https://github.com/anomalyco/opencode/releases/latest/download/opencode-linux-${OCARCH}.tar.gz" | tar xz -C /tmp
	find /tmp -name 'opencode' -type f -executable -exec mv {} ~/.local/bin/opencode \;
fi

# Set aliases based on selection
{
	if [ "$ai_choice" = "claude" ]; then
		echo "alias c='claude'"
		echo "alias claude-yolo='claude --dangerously-skip-permissions'"
	elif [ "$ai_choice" = "opencode" ]; then
		echo "alias c='opencode'"
		echo "alias opencode-yolo='opencode --dangerously-skip-permissions'"
	else
		echo "alias claude-yolo='claude --dangerously-skip-permissions'"
		echo "alias opencode-yolo='opencode --dangerously-skip-permissions'"
	fi
} > ~/.devbox-ai-aliases

# SDKs
SDK_CONFIG="/workspace/.devbox/sdks"

if [ -f "$SDK_CONFIG" ]; then
	sdk_list=$(cat "$SDK_CONFIG")
	echo "Installing SDKs: $sdk_list (from previous selection)"
else
	echo
	echo "Select SDKs to install (comma-separated, or 'all', or 'none'):"
	echo "  1) Node.js"
	echo "  2) Python"
	echo "  3) Go"
	echo "  4) .NET"
	read -rp "Selection [1,2,3,4/all/none]: " sdk_selection
	sdk_list=""
	if [ "$sdk_selection" = "all" ]; then
		sdk_list="node,python,go,dotnet"
	elif [ "$sdk_selection" != "none" ] && [ -n "$sdk_selection" ]; then
		for item in $(echo "$sdk_selection" | tr ',' ' '); do
			case "$item" in
				1) sdk_list="${sdk_list:+$sdk_list,}node" ;;
				2) sdk_list="${sdk_list:+$sdk_list,}python" ;;
				3) sdk_list="${sdk_list:+$sdk_list,}go" ;;
				4) sdk_list="${sdk_list:+$sdk_list,}dotnet" ;;
			esac
		done
	fi
	echo "$sdk_list" > "$SDK_CONFIG"
fi

# SDK path setup file
> ~/.devbox-sdk-paths

install_node() {
	echo "Installing Node.js (via nvm)..."
	curl -fsSo /tmp/nvm-install.sh https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh
	bash /tmp/nvm-install.sh
	rm /tmp/nvm-install.sh
	export NVM_DIR="$HOME/.nvm"
	# shellcheck source=/dev/null
	[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
	nvm install --lts
	cat <<'PATHS' >> ~/.devbox-sdk-paths
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
PATHS
}

install_python() {
	echo "Installing Python (via uv)..."
	curl -fsSL https://astral.sh/uv/install.sh | bash
	cat <<'PATHS' >> ~/.devbox-sdk-paths
export PATH="$HOME/.local/bin:$PATH"
PATHS
}

install_go() {
	echo "Installing Go..."
	ARCH=$(uname -m)
	if [ "$ARCH" = "aarch64" ]; then GOARCH="arm64"; else GOARCH="amd64"; fi
	GO_VERSION=$(curl -fsSL "https://go.dev/VERSION?m=text" | head -1)
	curl -fsSL "https://go.dev/dl/${GO_VERSION}.linux-${GOARCH}.tar.gz" | tar xz -C ~/.local
	cat <<'PATHS' >> ~/.devbox-sdk-paths
export GOROOT="$HOME/.local/go"
export GOPATH="$HOME/go"
export PATH="$GOROOT/bin:$GOPATH/bin:$PATH"
PATHS
}

install_dotnet() {
	echo "Installing .NET..."
	curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel LTS
	cat <<'PATHS' >> ~/.devbox-sdk-paths
export DOTNET_ROOT="$HOME/.dotnet"
export PATH="$DOTNET_ROOT:$DOTNET_ROOT/tools:$PATH"
PATHS
}

for sdk in $(echo "$sdk_list" | tr ',' ' '); do
	case "$sdk" in
		node) install_node ;;
		python) install_python ;;
		go) install_go ;;
		dotnet) install_dotnet ;;
	esac
done

echo
echo "Done. Ready to go."
