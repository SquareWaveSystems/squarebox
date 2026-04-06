#!/usr/bin/env bash
set -euo pipefail

cleanup() {
	rm -f /tmp/opencode.tar.gz /tmp/micro.tar.gz /tmp/micro /tmp/edit.tar.zst \
		/tmp/edit.tar /tmp/fresh.tar.gz /tmp/helix.tar.xz /tmp/nvim.tar.gz \
		/tmp/nvm-install.sh /tmp/go.tar.gz /tmp/yazi.zip
	rm -rf /tmp/micro-* /tmp/fresh* /tmp/helix-* /tmp/nvim-linux-* /tmp/yazi-*
}
trap cleanup EXIT

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

# Detect interactive terminal
INTERACTIVE=false
[ -t 0 ] && INTERACTIVE=true

# Check for gum TUI tool
HAS_GUM=false
if $INTERACTIVE && command -v gum &>/dev/null; then
	HAS_GUM=true
fi

if $HAS_GUM; then
	gum style --border double --padding "0 2" --border-foreground 212 "SquareBox Setup"
else
	echo "=== SquareBox Setup ==="
fi
echo

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
		# Persist gh config for future rebuilds (only if auth succeeded)
		if gh auth status &>/dev/null; then
			mkdir -p "$GH_PERSIST"
			cp -r ~/.config/gh/* "$GH_PERSIST"/
		else
			echo "GitHub CLI auth was not completed — skipping config persistence"
		fi
	else
		echo "Skipping GitHub CLI auth (non-interactive)"
	fi
else
	echo "GitHub CLI: already authenticated"
fi

# AI coding assistant
AI_CONFIG="/workspace/.squarebox/ai-tool"
mkdir -p /workspace/.squarebox ~/.local/bin

ai_prev=""
if [ -f "$AI_CONFIG" ]; then
	ai_prev=$(cat "$AI_CONFIG")
fi

if $INTERACTIVE; then
	case "$ai_prev" in
		claude)   ai_default_label="Claude Code" ;;
		opencode) ai_default_label="OpenCode" ;;
		both)     ai_default_label="Both" ;;
		*)        ai_default_label="" ;;
	esac

	echo
	if $HAS_GUM; then
		gum_args=(--header "Choose your AI coding assistant:")
		[ -n "$ai_default_label" ] && gum_args+=(--selected "$ai_default_label")
		ai_label=$(gum choose "${gum_args[@]}" \
			"Claude Code" "OpenCode" "Both") || true
		case "$ai_label" in
			"Claude Code") ai_choice="claude" ;;
			"OpenCode")    ai_choice="opencode" ;;
			"Both")        ai_choice="both" ;;
			*)             echo "No selection, defaulting to Claude Code"; ai_choice="claude" ;;
		esac
	else
		echo "Choose your AI coding assistant:"
		if [ "$ai_prev" = "claude" ];   then echo "  1) Claude Code [current]"; else echo "  1) Claude Code"; fi
		if [ "$ai_prev" = "opencode" ]; then echo "  2) OpenCode [current]";    else echo "  2) OpenCode"; fi
		if [ "$ai_prev" = "both" ];     then echo "  3) Both [current]";        else echo "  3) Both"; fi
		read -rp "Selection [1/2/3]: " selection
		if [ -z "$selection" ] && [ -n "$ai_prev" ]; then
			ai_choice="$ai_prev"
		else
			case "$selection" in
				1) ai_choice="claude" ;;
				2) ai_choice="opencode" ;;
				3) ai_choice="both" ;;
				*) echo "Invalid selection, defaulting to Claude Code"; ai_choice="claude" ;;
			esac
		fi
	fi
	echo "$ai_choice" > "$AI_CONFIG"
elif [ -n "$ai_prev" ]; then
	ai_choice="$ai_prev"
	echo "Installing AI tool: $ai_choice (from previous selection)"
else
	echo "Defaulting to Claude Code (non-interactive)"
	ai_choice="claude"
	echo "$ai_choice" > "$AI_CONFIG"
fi

if [ "$ai_choice" = "claude" ] || [ "$ai_choice" = "both" ]; then
	echo "Installing Claude Code..."
	# Trust boundary: the Claude Code install script manages its own binary
	# fetching and verification. We rely on HTTPS for script integrity.
	curl -fsSL https://claude.ai/install.sh | bash
fi

# Pinned versions — update via: scripts/update-versions.sh
OPENCODE_VERSION="1.3.15"
MICRO_VERSION="2.0.15"
EDIT_VERSION="1.2.1"
EDIT_ASSET_VERSION="1.2.0"
FRESH_VERSION="0.2.21"
HELIX_VERSION="25.07.1"
NVIM_VERSION="0.12.0"

for _var in OPENCODE_VERSION MICRO_VERSION EDIT_VERSION EDIT_ASSET_VERSION FRESH_VERSION HELIX_VERSION NVIM_VERSION; do
	if [ -z "${!_var:-}" ]; then
		echo "Error: ${_var} is empty or unset" >&2
		exit 1
	fi
done

if [ "$ai_choice" = "opencode" ] || [ "$ai_choice" = "both" ]; then
	if command -v opencode &>/dev/null; then
		echo "OpenCode already installed, skipping."
	else
		echo "Installing OpenCode v${OPENCODE_VERSION}..."
		ARCH=$(uname -m)
		if [ "$ARCH" = "aarch64" ]; then OCARCH="arm64"; else OCARCH="x64"; fi
		curl -fsSLo /tmp/opencode.tar.gz "https://github.com/anomalyco/opencode/releases/download/v${OPENCODE_VERSION}/opencode-linux-${OCARCH}.tar.gz"
		verify_checksum /tmp/opencode.tar.gz "opencode-linux-${OCARCH}.tar.gz"
		tar xzf /tmp/opencode.tar.gz -C /tmp
		find /tmp -name 'opencode' -type f -executable -exec mv {} ~/.local/bin/opencode \;
		rm -f /tmp/opencode.tar.gz
	fi
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

# Text editors
EDITOR_CONFIG="/workspace/.squarebox/editors"

if [ -f "$EDITOR_CONFIG" ]; then
	editor_list=$(cat "$EDITOR_CONFIG")
	[ -n "$editor_list" ] && echo "Installing editors: $editor_list (from previous selection)"
else
	if $INTERACTIVE; then
		echo
		if $HAS_GUM; then
			echo "Nano is always available as the default editor."
			selected=$(gum choose --no-limit \
				--header "Select text editors to install (space=toggle, enter=confirm):" \
				"micro  — modern, intuitive terminal editor" \
				"edit   — terminal text editor (Microsoft)" \
				"fresh  — modern terminal text editor" \
				"helix  — modal editor (Kakoune-inspired)" \
				"nvim   — Neovim") || true
			editor_list=""
			while IFS= read -r line; do
				[ -z "$line" ] && continue
				name="${line%% *}"
				editor_list="${editor_list:+$editor_list,}${name}"
			done <<< "$selected"
		else
			echo "Select text editors to install (comma-separated, or 'all', or press Enter to skip):"
			echo "  Nano is always available as the default editor."
			echo "  1) micro    — modern, intuitive terminal editor"
			echo "  2) edit     — terminal text editor (Microsoft)"
			echo "  3) fresh    — modern terminal text editor"
			echo "  4) helix    — modal editor (Kakoune-inspired)"
			echo "  5) nvim     — Neovim"
			read -rp "Selection [1,2,3,4,5/all/skip]: " editor_selection
			editor_list=""
			if [ "$editor_selection" = "all" ]; then
				editor_list="micro,edit,fresh,helix,nvim"
			elif [ -n "$editor_selection" ]; then
				for item in $(echo "$editor_selection" | tr ',' ' '); do
					case "$item" in
						1) editor_list="${editor_list:+$editor_list,}micro" ;;
						2) editor_list="${editor_list:+$editor_list,}edit" ;;
						3) editor_list="${editor_list:+$editor_list,}fresh" ;;
						4) editor_list="${editor_list:+$editor_list,}helix" ;;
						5) editor_list="${editor_list:+$editor_list,}nvim" ;;
					esac
				done
			fi
		fi
	else
		echo "Skipping editor selection (non-interactive)"
		editor_list=""
	fi
	echo "$editor_list" > "$EDITOR_CONFIG"
fi

install_micro() {
	if command -v micro &>/dev/null; then echo "Micro already installed, skipping."; return 0; fi
	echo "Installing Micro v${MICRO_VERSION}..."
	ARCH=$(uname -m)
	if [ "$ARCH" = "aarch64" ]; then MARCH="-arm64"; else MARCH="64"; fi
	curl -fsSLo /tmp/micro.tar.gz "https://github.com/micro-editor/micro/releases/download/v${MICRO_VERSION}/micro-${MICRO_VERSION}-linux${MARCH}.tar.gz"
	verify_checksum /tmp/micro.tar.gz "micro-${MICRO_VERSION}-linux${MARCH}.tar.gz"
	tar xzf /tmp/micro.tar.gz --strip-components=1 -C /tmp
	mv /tmp/micro ~/.local/bin/micro
	rm -rf /tmp/micro*
}

install_edit() {
	if command -v edit &>/dev/null; then echo "Edit already installed, skipping."; return 0; fi
	echo "Installing Edit v${EDIT_VERSION}..."
	ARCH=$(uname -m)
	if [ "$ARCH" = "aarch64" ]; then ZARCH="aarch64"; else ZARCH="x86_64"; fi
	curl -fsSLo /tmp/edit.tar.zst "https://github.com/microsoft/edit/releases/download/v${EDIT_VERSION}/edit-${EDIT_ASSET_VERSION}-${ZARCH}-linux-gnu.tar.zst"
	verify_checksum /tmp/edit.tar.zst "edit-${EDIT_ASSET_VERSION}-${ZARCH}-linux-gnu.tar.zst"
	zstd -d /tmp/edit.tar.zst -o /tmp/edit.tar
	tar xf /tmp/edit.tar -C /tmp
	find /tmp -name 'edit' -type f -executable -exec mv {} ~/.local/bin/edit \;
	rm -f /tmp/edit.tar.zst /tmp/edit.tar
}

install_fresh() {
	if command -v fresh &>/dev/null; then echo "Fresh already installed, skipping."; return 0; fi
	echo "Installing Fresh v${FRESH_VERSION}..."
	ARCH=$(uname -m)
	if [ "$ARCH" = "aarch64" ]; then ZARCH="aarch64"; else ZARCH="x86_64"; fi
	curl -fsSLo /tmp/fresh.tar.gz "https://github.com/sinelaw/fresh/releases/download/v${FRESH_VERSION}/fresh-editor-${ZARCH}-unknown-linux-musl.tar.gz"
	verify_checksum /tmp/fresh.tar.gz "fresh-editor-${ZARCH}-unknown-linux-musl.tar.gz"
	tar xf /tmp/fresh.tar.gz -C /tmp
	find /tmp -name 'fresh' -type f -executable -exec mv {} ~/.local/bin/fresh \;
	rm -rf /tmp/fresh*
}

install_helix() {
	if command -v hx &>/dev/null; then echo "Helix already installed, skipping."; return 0; fi
	rm -rf ~/.config/helix/runtime
	echo "Installing Helix v${HELIX_VERSION}..."
	ARCH=$(uname -m)
	if [ "$ARCH" = "aarch64" ]; then ZARCH="aarch64"; else ZARCH="x86_64"; fi
	if sudo -n true 2>/dev/null; then
		sudo apt-get update -qq && sudo apt-get install -y -qq xz-utils >/dev/null 2>&1
	elif ! command -v xz &>/dev/null; then
		echo "Error: xz-utils required for Helix but sudo unavailable to install it. Skipping Helix." >&2
		return 1
	fi
	curl -fsSLo /tmp/helix.tar.xz "https://github.com/helix-editor/helix/releases/download/${HELIX_VERSION}/helix-${HELIX_VERSION}-${ZARCH}-linux.tar.xz"
	verify_checksum /tmp/helix.tar.xz "helix-${HELIX_VERSION}-${ZARCH}-linux.tar.xz"
	tar xJf /tmp/helix.tar.xz -C /tmp
	mv "/tmp/helix-${HELIX_VERSION}-${ZARCH}-linux/hx" ~/.local/bin/hx
	mkdir -p ~/.config/helix
	rm -rf ~/.config/helix/runtime
	mv "/tmp/helix-${HELIX_VERSION}-${ZARCH}-linux/runtime" ~/.config/helix/runtime
	rm -rf /tmp/helix*
}

install_nvim() {
	if command -v nvim &>/dev/null; then echo "Neovim already installed, skipping."; return 0; fi
	rm -rf ~/.local/nvim
	echo "Installing Neovim v${NVIM_VERSION}..."
	ARCH=$(uname -m)
	if [ "$ARCH" = "aarch64" ]; then NARCH="arm64"; else NARCH="x86_64"; fi
	curl -fsSLo /tmp/nvim.tar.gz "https://github.com/neovim/neovim/releases/download/v${NVIM_VERSION}/nvim-linux-${NARCH}.tar.gz"
	verify_checksum /tmp/nvim.tar.gz "nvim-linux-${NARCH}.tar.gz"
	tar xzf /tmp/nvim.tar.gz -C /tmp
	rm -rf ~/.local/nvim
	mv "/tmp/nvim-linux-${NARCH}" ~/.local/nvim
	ln -sf ~/.local/nvim/bin/nvim ~/.local/bin/nvim
	rm -f /tmp/nvim.tar.gz
}

editor_cmd=""
for editor in $(echo "$editor_list" | tr ',' ' '); do
	case "$editor" in
		micro) install_micro; [ -z "$editor_cmd" ] && editor_cmd="micro" ;;
		edit) install_edit; [ -z "$editor_cmd" ] && editor_cmd="edit" ;;
		fresh) install_fresh; [ -z "$editor_cmd" ] && editor_cmd="fresh" ;;
		helix) { install_helix && [ -z "$editor_cmd" ] && editor_cmd="hx"; } || echo "Warning: Helix installation failed, skipping." ;;
		nvim) install_nvim; [ -z "$editor_cmd" ] && editor_cmd="nvim" ;;
	esac
done

# Set EDITOR to the first selected editor
{
	if [ -n "$editor_cmd" ]; then
		echo "export EDITOR='$editor_cmd'"
	fi
} > ~/.squarebox-editor-aliases

# SDKs
SDK_CONFIG="/workspace/.squarebox/sdks"

sdk_prev=""
if [ -f "$SDK_CONFIG" ]; then
	sdk_prev=$(cat "$SDK_CONFIG")
fi

if $INTERACTIVE; then
	echo
	if $HAS_GUM; then
		# Build --selected from previously saved SDKs
		gum_selected=""
		for sdk in $(echo "$sdk_prev" | tr ',' ' '); do
			case "$sdk" in
				node)   gum_selected="${gum_selected:+$gum_selected,}Node.js" ;;
				python) gum_selected="${gum_selected:+$gum_selected,}Python" ;;
				go)     gum_selected="${gum_selected:+$gum_selected,}Go" ;;
				dotnet) gum_selected="${gum_selected:+$gum_selected,}.NET" ;;
			esac
		done
		gum_args=(--no-limit --header "Select SDKs to install (space=toggle, enter=confirm):")
		[ -n "$gum_selected" ] && gum_args+=(--selected "$gum_selected")
		selected=$(gum choose "${gum_args[@]}" \
			"Node.js" "Python" "Go" ".NET") || true
		sdk_list=""
		while IFS= read -r line; do
			case "$line" in
				"Node.js") sdk_list="${sdk_list:+$sdk_list,}node" ;;
				"Python")  sdk_list="${sdk_list:+$sdk_list,}python" ;;
				"Go")      sdk_list="${sdk_list:+$sdk_list,}go" ;;
				".NET")    sdk_list="${sdk_list:+$sdk_list,}dotnet" ;;
			esac
		done <<< "$selected"
		# Empty gum output means nothing selected
		[ -z "$selected" ] && sdk_list=""
	else
		echo "Select SDKs to install (comma-separated, or 'all', or 'none'):"
		for sdk_item in "1:node:Node.js" "2:python:Python" "3:go:Go" "4:dotnet:.NET"; do
			num="${sdk_item%%:*}"; rest="${sdk_item#*:}"; key="${rest%%:*}"; label="${rest#*:}"
			if [[ ",$sdk_prev," == *",${key},"* ]]; then
				echo "  ${num}) ${label} [installed]"
			else
				echo "  ${num}) ${label}"
			fi
		done
		read -rp "Selection [1,2,3,4/all/none]: " sdk_selection
		if [ -z "$sdk_selection" ] && [ -n "$sdk_prev" ]; then
			sdk_list="$sdk_prev"
		else
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
		fi
	fi
	echo "$sdk_list" > "$SDK_CONFIG"
elif [ -n "$sdk_prev" ]; then
	sdk_list="$sdk_prev"
	echo "Installing SDKs: $sdk_list (from previous selection)"
else
	echo "Skipping SDK selection (non-interactive)"
	sdk_list=""
	echo "$sdk_list" > "$SDK_CONFIG"
fi

# SDK path setup file (create if missing, preserve on retry)
touch ~/.squarebox-sdk-paths

# Pinned versions — update via: scripts/update-versions.sh
NVM_VERSION="0.40.3"
GO_VERSION="go1.26.1"

for _var in NVM_VERSION GO_VERSION; do
	if [ -z "${!_var:-}" ]; then
		echo "Error: ${_var} is empty or unset" >&2
		exit 1
	fi
done

install_node() {
	if command -v node &>/dev/null; then echo "Node.js already installed, skipping."; return 0; fi
	rm -rf "$HOME/.nvm"
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
	if ! grep -q 'NVM_DIR' ~/.squarebox-sdk-paths 2>/dev/null; then
		cat <<'PATHS' >> ~/.squarebox-sdk-paths
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
PATHS
	fi
	if ! command -v node &>/dev/null; then
		echo "Error: Node.js binary not found after installation" >&2
		exit 1
	fi
}

install_python() {
	if command -v uv &>/dev/null; then echo "uv already installed, skipping."; return 0; fi
	echo "Installing Python (via uv)..."
	# Trust boundary: the uv install script manages its own binary fetching
	# and verification. We rely on HTTPS for script integrity.
	curl -fsSL https://astral.sh/uv/install.sh | bash
	if ! grep -q '\.local/bin' ~/.squarebox-sdk-paths 2>/dev/null; then
		cat <<'PATHS' >> ~/.squarebox-sdk-paths
export PATH="$HOME/.local/bin:$PATH"
PATHS
	fi
	if ! command -v uv &>/dev/null; then
		echo "Error: uv binary not found after installation" >&2
		exit 1
	fi
}

install_go() {
	if [ -x "${HOME}/.local/go/bin/go" ]; then echo "Go already installed, skipping."; return 0; fi
	rm -rf "$HOME/.local/go"
	echo "Installing Go ${GO_VERSION}..."
	ARCH=$(uname -m)
	if [ "$ARCH" = "aarch64" ]; then GOARCH="arm64"; else GOARCH="amd64"; fi
	curl -fsSLo /tmp/go.tar.gz "https://go.dev/dl/${GO_VERSION}.linux-${GOARCH}.tar.gz"
	verify_checksum /tmp/go.tar.gz "${GO_VERSION}.linux-${GOARCH}.tar.gz"
	tar xzf /tmp/go.tar.gz -C ~/.local
	rm /tmp/go.tar.gz
	if ! grep -q 'GOROOT' ~/.squarebox-sdk-paths 2>/dev/null; then
		cat <<'PATHS' >> ~/.squarebox-sdk-paths
export GOROOT="$HOME/.local/go"
export GOPATH="$HOME/go"
export PATH="$GOROOT/bin:$GOPATH/bin:$PATH"
PATHS
	fi
	if [ ! -x "${HOME}/.local/go/bin/go" ]; then
		echo "Error: Go binary not found after installation" >&2
		exit 1
	fi
}

install_dotnet() {
	if [ -x "${HOME}/.dotnet/dotnet" ]; then echo ".NET already installed, skipping."; return 0; fi
	rm -rf "$HOME/.dotnet"
	echo "Installing .NET..."
	# Trust boundary: the .NET install script manages its own binary fetching
	# and verification. We rely on HTTPS for script integrity.
	curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel LTS
	if ! grep -q 'DOTNET_ROOT' ~/.squarebox-sdk-paths 2>/dev/null; then
		cat <<'PATHS' >> ~/.squarebox-sdk-paths
export DOTNET_ROOT="$HOME/.dotnet"
export PATH="$DOTNET_ROOT:$DOTNET_ROOT/tools:$PATH"
PATHS
	fi
	if [ ! -x "${HOME}/.dotnet/dotnet" ]; then
		echo "Error: .NET binary not found after installation" >&2
		exit 1
	fi
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
