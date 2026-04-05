#!/usr/bin/env bash
set -euo pipefail

SETUP_CHECKSUMS="${HOME}/setup-checksums.txt"

# Verify SHA256 checksum of a downloaded file against the checksums file.
# Usage: verify_checksum <file> <artifact-name>
verify_checksum() {
	local file="$1" name="$2"
	local expected actual
	expected=$(grep -E "^[0-9a-f]{64}  ${name}$" "$SETUP_CHECKSUMS" | awk '{print $1}')
	if [ -z "$expected" ]; then
		echo "ERROR: No checksum entry found for '${name}' in ${SETUP_CHECKSUMS}" >&2
		return 1
	fi
	actual=$(sha256sum "$file" | awk '{print $1}')
	if [ "$actual" != "$expected" ]; then
		echo "CHECKSUM MISMATCH for ${name}" >&2
		echo "  expected: ${expected}" >&2
		echo "  actual:   ${actual}" >&2
		return 1
	fi
}

echo "=== SquareBox Setup ==="
echo

# Detect interactive terminal
INTERACTIVE=false
[ -t 0 ] && INTERACTIVE=true

# Git identity
if [ -z "$(git config --global user.name 2>/dev/null)" ]; then
	if $INTERACTIVE; then
		read -rp "Git name: " name
		git config --global user.name "$name"
	else
		echo "Skipping git identity setup (non-interactive)"
	fi
fi

if [ -z "$(git config --global user.email 2>/dev/null)" ]; then
	if $INTERACTIVE; then
		read -rp "Git email: " email
		git config --global user.email "$email"
	fi
fi

# Restore GitHub CLI config from persistent storage if available
GH_PERSIST="/workspace/.squarebox/gh"
if [ -d "$GH_PERSIST" ] && [ ! -d ~/.config/gh ]; then
	mkdir -p ~/.config
	cp -r "$GH_PERSIST" ~/.config/gh
fi

# GitHub CLI
if ! gh auth status &>/dev/null; then
	if $INTERACTIVE; then
		echo
		echo "Logging into GitHub..."
		BROWSER=echo gh auth login
		# Persist gh config for future rebuilds
		mkdir -p "$GH_PERSIST"
		cp -r ~/.config/gh/* "$GH_PERSIST"/
	else
		echo "Skipping GitHub CLI auth (non-interactive)"
	fi
else
	echo "GitHub CLI: already authenticated"
fi

# AI coding assistant
AI_CONFIG="/workspace/.squarebox/ai-tool"
mkdir -p /workspace/.squarebox ~/.local/bin

if [ -f "$AI_CONFIG" ]; then
	ai_choice=$(cat "$AI_CONFIG")
	echo "Installing AI tool: $ai_choice (from previous selection)"
else
	if $INTERACTIVE; then
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
	else
		echo "Defaulting to Claude Code (non-interactive)"
		ai_choice="claude"
	fi
	echo "$ai_choice" > "$AI_CONFIG"
fi

if [ "$ai_choice" = "claude" ] || [ "$ai_choice" = "both" ]; then
	echo "Installing Claude Code..."
	# Trust boundary: the Claude Code install script manages its own binary
	# fetching and verification. We rely on HTTPS for script integrity.
	curl -fsSL https://claude.ai/install.sh | bash
fi

# Pinned versions — update via: scripts/update-versions.sh
OPENCODE_VERSION="1.3.13"

if [ "$ai_choice" = "opencode" ] || [ "$ai_choice" = "both" ]; then
	echo "Installing OpenCode v${OPENCODE_VERSION}..."
	ARCH=$(uname -m)
	if [ "$ARCH" = "aarch64" ]; then OCARCH="arm64"; else OCARCH="x64"; fi
	curl -fsSLo /tmp/opencode.tar.gz "https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-${OCARCH}.tar.gz"
	verify_checksum /tmp/opencode.tar.gz "opencode-linux-${OCARCH}.tar.gz"
	tar xzf /tmp/opencode.tar.gz -C /tmp
	find /tmp -name 'opencode' -type f -executable -exec mv {} ~/.local/bin/opencode \;
	rm -f /tmp/opencode.tar.gz
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
} > ~/.squarebox-ai-aliases

# SDKs
SDK_CONFIG="/workspace/.squarebox/sdks"

if [ -f "$SDK_CONFIG" ]; then
	sdk_list=$(cat "$SDK_CONFIG")
	echo "Installing SDKs: $sdk_list (from previous selection)"
else
	if $INTERACTIVE; then
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
	else
		echo "Skipping SDK selection (non-interactive)"
		sdk_list=""
	fi
	echo "$sdk_list" > "$SDK_CONFIG"
fi

# SDK path setup file
> ~/.squarebox-sdk-paths

# Pinned versions — update via: scripts/update-versions.sh
NVM_VERSION="0.40.3"
GO_VERSION="go1.26.1"

install_node() {
	echo "Installing Node.js (via nvm v${NVM_VERSION})..."
	curl -fsSo /tmp/nvm-install.sh "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh"
	verify_checksum /tmp/nvm-install.sh "nvm-install-v${NVM_VERSION}.sh"
	bash /tmp/nvm-install.sh
	rm /tmp/nvm-install.sh
	export NVM_DIR="$HOME/.nvm"
	# shellcheck source=/dev/null
	[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
	# Node.js binary verification is handled by nvm
	nvm install --lts
	cat <<'PATHS' >> ~/.squarebox-sdk-paths
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
PATHS
}

install_python() {
	echo "Installing Python (via uv)..."
	# Trust boundary: the uv install script manages its own binary fetching
	# and verification. We rely on HTTPS for script integrity.
	curl -fsSL https://astral.sh/uv/install.sh | bash
	cat <<'PATHS' >> ~/.squarebox-sdk-paths
export PATH="$HOME/.local/bin:$PATH"
PATHS
}

install_go() {
	echo "Installing Go ${GO_VERSION}..."
	ARCH=$(uname -m)
	if [ "$ARCH" = "aarch64" ]; then GOARCH="arm64"; else GOARCH="amd64"; fi
	curl -fsSLo /tmp/go.tar.gz "https://go.dev/dl/${GO_VERSION}.linux-${GOARCH}.tar.gz"
	verify_checksum /tmp/go.tar.gz "${GO_VERSION}.linux-${GOARCH}.tar.gz"
	tar xzf /tmp/go.tar.gz -C ~/.local
	rm /tmp/go.tar.gz
	cat <<'PATHS' >> ~/.squarebox-sdk-paths
export GOROOT="$HOME/.local/go"
export GOPATH="$HOME/go"
export PATH="$GOROOT/bin:$GOPATH/bin:$PATH"
PATHS
}

install_dotnet() {
	echo "Installing .NET..."
	# Trust boundary: the .NET install script manages its own binary fetching
	# and verification. We rely on HTTPS for script integrity.
	curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel LTS
	cat <<'PATHS' >> ~/.squarebox-sdk-paths
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
