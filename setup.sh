#!/usr/bin/env bash
set -euo pipefail

cleanup() {
	rm -f /tmp/opencode.tar.gz /tmp/micro.tar.gz /tmp/micro /tmp/edit.tar.zst \
		/tmp/edit.tar /tmp/fresh.tar.gz /tmp/helix.tar.xz /tmp/nvim.tar.gz \
		/tmp/nvm-install.sh /tmp/go.tar.gz /tmp/yazi.zip
	rm -rf /tmp/micro-* /tmp/fresh* /tmp/helix-* /tmp/nvim-linux-* /tmp/yazi-* /tmp/zellij*
}
trap cleanup EXIT

SETUP_CHECKSUMS="${HOME}/setup-checksums.txt"

# Fix /workspace ownership if volume mount left it owned by a different UID
if [ -d /workspace ] && ! [ -w /workspace ]; then
	if ! command -v sudo >/dev/null 2>&1; then
		echo "ERROR: /workspace is not writable and sudo is not available to fix ownership." >&2
		echo "Please make /workspace writable for user 'dev' or rerun with appropriate privileges." >&2
		exit 1
	elif ! sudo -n true >/dev/null 2>&1; then
		echo "ERROR: /workspace is not writable and passwordless sudo is required to fix ownership automatically." >&2
		echo "Please run 'sudo chown dev:dev /workspace' manually or rerun with appropriate privileges." >&2
		exit 1
	elif ! sudo -n chown dev:dev /workspace; then
		echo "ERROR: Failed to change ownership of /workspace to dev:dev." >&2
		echo "This can happen on volume types that do not allow chown." >&2
		echo "Please make /workspace writable for user 'dev' or adjust the mount configuration and try again." >&2
		exit 1
	fi
fi

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

# Source shared tool library and wire up checksum verification
export SB_TOOLS_YAML=/usr/local/lib/squarebox/tools.yaml
source /usr/local/lib/squarebox/tool-lib.sh
sb_verify() { verify_checksum "$1" "$2"; }

# Detect interactive terminal
INTERACTIVE=false
[ -t 0 ] && INTERACTIVE=true

# Check for gum TUI tool
HAS_GUM=false
if $INTERACTIVE && command -v gum &>/dev/null; then
	HAS_GUM=true
fi

if $HAS_GUM; then
	gum style --border double --padding "0 2" --border-foreground 212 "squarebox setup"
else
	echo "=== squarebox setup ==="
fi
echo

# Git identity
if [ -z "$(git config --global user.name 2>/dev/null)" ]; then
	if $INTERACTIVE; then
		while true; do
			read -rp "Git name: " name
			[ -n "$name" ] && break
			echo "Name cannot be empty."
		done
		git config --global user.name "$name"
	else
		echo "Skipping git identity setup (non-interactive)"
	fi
fi

if [ -z "$(git config --global user.email 2>/dev/null)" ]; then
	if $INTERACTIVE; then
		while true; do
			read -rp "Git email: " email
			[ -n "$email" ] && break
			echo "Email cannot be empty."
		done
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
		# BROWSER=echo makes gh print the auth URL instead of trying to open a browser
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
	# Migrate legacy single-choice values
	case "$ai_prev" in
		both) ai_prev="claude,opencode" ;;
	esac
fi

if $INTERACTIVE; then
	echo
	if $HAS_GUM; then
		# Build --selected from previously saved AI tools
		gum_selected=""
		for ai in $(echo "$ai_prev" | tr ',' ' '); do
			case "$ai" in
				claude)   gum_selected="${gum_selected:+$gum_selected,}Claude Code" ;;
				copilot)  gum_selected="${gum_selected:+$gum_selected,}GitHub Copilot CLI" ;;
				gemini)   gum_selected="${gum_selected:+$gum_selected,}Google Gemini CLI" ;;
				codex)    gum_selected="${gum_selected:+$gum_selected,}OpenAI Codex CLI" ;;
				opencode) gum_selected="${gum_selected:+$gum_selected,}OpenCode" ;;
			esac
		done
		gum_args=(--no-limit --header "Select AI coding assistants (space=toggle, enter=confirm):")
		[ -n "$gum_selected" ] && gum_args+=(--selected "$gum_selected")
		selected=$(gum choose "${gum_args[@]}" \
			"Claude Code" "GitHub Copilot CLI" "Google Gemini CLI" \
			"OpenAI Codex CLI" "OpenCode") || true
		ai_choice=""
		while IFS= read -r line; do
			case "$line" in
				"Claude Code")        ai_choice="${ai_choice:+$ai_choice,}claude" ;;
				"GitHub Copilot CLI") ai_choice="${ai_choice:+$ai_choice,}copilot" ;;
				"Google Gemini CLI")  ai_choice="${ai_choice:+$ai_choice,}gemini" ;;
				"OpenAI Codex CLI")   ai_choice="${ai_choice:+$ai_choice,}codex" ;;
				"OpenCode")           ai_choice="${ai_choice:+$ai_choice,}opencode" ;;
			esac
		done <<< "$selected"
	else
		echo "Select AI coding assistants (comma-separated, 'all', or press Enter to skip):"
		for ai_item in "1:claude:Claude Code" "2:copilot:GitHub Copilot CLI" "3:gemini:Google Gemini CLI" "4:codex:OpenAI Codex CLI" "5:opencode:OpenCode"; do
			num="${ai_item%%:*}"; rest="${ai_item#*:}"; key="${rest%%:*}"; label="${rest#*:}"
			if [[ ",$ai_prev," == *",${key},"* ]]; then
				echo "  ${num}) ${label} [installed]"
			else
				echo "  ${num}) ${label}"
			fi
		done
		read -rp "Selection [1,2,3,4,5/all/skip]: " ai_selection
		if [ -z "$ai_selection" ] && [ -n "$ai_prev" ]; then
			ai_choice="$ai_prev"
		else
			ai_choice=""
			if [ "$ai_selection" = "all" ]; then
				ai_choice="claude,copilot,gemini,codex,opencode"
			elif [ -n "$ai_selection" ]; then
				for item in $(echo "$ai_selection" | tr ',' ' '); do
					case "$item" in
						1) ai_choice="${ai_choice:+$ai_choice,}claude" ;;
						2) ai_choice="${ai_choice:+$ai_choice,}copilot" ;;
						3) ai_choice="${ai_choice:+$ai_choice,}gemini" ;;
						4) ai_choice="${ai_choice:+$ai_choice,}codex" ;;
						5) ai_choice="${ai_choice:+$ai_choice,}opencode" ;;
					esac
				done
			fi
		fi
	fi
	echo "$ai_choice" > "$AI_CONFIG"
elif [ -n "$ai_prev" ]; then
	ai_choice="$ai_prev"
	echo "Installing AI tools: $ai_choice (from previous selection)"
else
	echo "Defaulting to Claude Code (non-interactive)"
	ai_choice="claude"
	echo "$ai_choice" > "$AI_CONFIG"
fi

# Pinned versions — update via: scripts/update-versions.sh
OPENCODE_VERSION="1.3.15"
MICRO_VERSION="2.0.15"
EDIT_VERSION="1.2.1"
EDIT_ASSET_VERSION="1.2.0"
FRESH_VERSION="0.2.21"
HELIX_VERSION="25.07.1"
NVIM_VERSION="0.12.0"
ZELLIJ_VERSION="0.44.0"

for _var in OPENCODE_VERSION MICRO_VERSION EDIT_VERSION EDIT_ASSET_VERSION FRESH_VERSION HELIX_VERSION NVIM_VERSION ZELLIJ_VERSION; do
	if [ -z "${!_var:-}" ]; then
		echo "Error: ${_var} is empty or unset" >&2
		exit 1
	fi
done

# Pinned SDK versions needed early (for npm-based AI tools)
NVM_VERSION="0.40.3"

# SDK path setup file (create if missing, preserve on retry)
touch ~/.squarebox-sdk-paths

install_node() {
	if command -v node &>/dev/null; then echo "Node.js already installed, skipping."; return 0; fi
	rm -rf "$HOME/.nvm"
	echo "Installing Node.js (via nvm v${NVM_VERSION})..."
	curl -fsSo /tmp/nvm-install.sh "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh"
	verify_checksum /tmp/nvm-install.sh "nvm-install-v${NVM_VERSION}.sh"
	bash /tmp/nvm-install.sh >/dev/null 2>&1
	rm /tmp/nvm-install.sh
	export NVM_DIR="$HOME/.nvm"
	# shellcheck source=/dev/null
	[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
	# Node.js binary verification is handled by nvm
	nvm install --lts >/dev/null 2>&1
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

# Ensure Node.js is available for npm-based AI tools
ensure_node_for_npm() {
	if command -v node &>/dev/null; then return 0; fi
	echo "Installing Node.js (required for npm-based AI tools)..."
	install_node
	# Ensure node/npm are available in this session
	export NVM_DIR="$HOME/.nvm"
	# shellcheck source=/dev/null
	[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
	# Persist Node.js in SDK config so it survives rebuilds
	local sdk_cfg="/workspace/.squarebox/sdks"
	if [ -f "$sdk_cfg" ]; then
		local sdk_current
		sdk_current=$(cat "$sdk_cfg")
		if [[ ",$sdk_current," != *",node,"* ]] && [ "$sdk_current" != "node" ]; then
			echo "${sdk_current:+$sdk_current,}node" > "$sdk_cfg"
		fi
	else
		echo "node" > "$sdk_cfg"
	fi
}

install_copilot() {
	if command -v github-copilot-cli &>/dev/null; then echo "GitHub Copilot CLI already installed, skipping."; return 0; fi
	ensure_node_for_npm
	echo "Installing GitHub Copilot CLI..."
	npm install -g --silent @githubnext/github-copilot-cli 2>/dev/null
}

install_gemini() {
	if command -v gemini &>/dev/null; then echo "Google Gemini CLI already installed, skipping."; return 0; fi
	ensure_node_for_npm
	echo "Installing Google Gemini CLI..."
	npm install -g --silent @google/gemini-cli 2>/dev/null
}

install_codex() {
	if command -v codex &>/dev/null; then echo "OpenAI Codex CLI already installed, skipping."; return 0; fi
	ensure_node_for_npm
	echo "Installing OpenAI Codex CLI..."
	npm install -g --silent @openai/codex 2>/dev/null
}

for ai_tool in $(echo "$ai_choice" | tr ',' ' '); do
	case "$ai_tool" in
		claude)
			echo "Installing Claude Code..."
			# Trust boundary: the Claude Code install script manages its own binary
			# fetching and verification. We rely on HTTPS for script integrity.
			curl -fsSL https://claude.ai/install.sh | bash >/dev/null 2>&1
			;;
		opencode)
			if command -v opencode &>/dev/null; then
				echo "OpenCode already installed, skipping."
			else
				echo "Installing OpenCode v${OPENCODE_VERSION}..."
				sb_install opencode "$OPENCODE_VERSION"
			fi
			;;
		copilot)  install_copilot ;;
		gemini)   install_gemini ;;
		codex)    install_codex ;;
	esac
done

# Set aliases based on selection — c maps to first selected tool in priority order
{
	c_target=""
	for ai_tool in claude copilot gemini codex opencode; do
		if [[ ",$ai_choice," == *",$ai_tool,"* ]]; then
			[ -z "$c_target" ] && c_target="$ai_tool"
			case "$ai_tool" in
				claude)   echo "alias claude-yolo='claude --dangerously-skip-permissions'" ;;
				opencode) echo "alias opencode-yolo='opencode --dangerously-skip-permissions'" ;;
			esac
		fi
	done
	[ -n "$c_target" ] && echo "alias c='$c_target'"
} > ~/.squarebox-ai-aliases

# Text editors
EDITOR_CONFIG="/workspace/.squarebox/editors"

editor_prev=""
if [ -f "$EDITOR_CONFIG" ]; then
	editor_prev=$(cat "$EDITOR_CONFIG")
fi

if $INTERACTIVE; then
	echo
	if $HAS_GUM; then
		# Build --selected from previously saved editors
		gum_selected=""
		for ed in $(echo "$editor_prev" | tr ',' ' '); do
			case "$ed" in
				micro) gum_selected="${gum_selected:+$gum_selected,}micro" ;;
				edit)  gum_selected="${gum_selected:+$gum_selected,}edit" ;;
				fresh) gum_selected="${gum_selected:+$gum_selected,}fresh" ;;
				helix) gum_selected="${gum_selected:+$gum_selected,}helix" ;;
				nvim)  gum_selected="${gum_selected:+$gum_selected,}nvim" ;;
			esac
		done
		echo "Nano is always available as the default editor."
		gum_args=(--no-limit --header "Select text editors to install:")
		[ -n "$gum_selected" ] && gum_args+=(--selected "$gum_selected")
		selected=$(gum choose "${gum_args[@]}" \
			"micro" "edit" "fresh" "helix" "nvim") || true
		editor_list=""
		while IFS= read -r line; do
			[ -z "$line" ] && continue
			editor_list="${editor_list:+$editor_list,}${line}"
		done <<< "$selected"
	else
		echo "Select text editors to install (comma-separated, or 'all', or press Enter to skip):"
		echo "  Nano is always available as the default editor."
		for ed_item in "1:micro:micro" "2:edit:edit" "3:fresh:fresh" "4:helix:helix" "5:nvim:nvim"; do
			num="${ed_item%%:*}"; rest="${ed_item#*:}"; key="${rest%%:*}"; label="${rest#*:}"
			case "$key" in
				micro) desc="modern, intuitive terminal editor" ;;
				edit)  desc="terminal text editor (Microsoft)" ;;
				fresh) desc="modern terminal text editor" ;;
				helix) desc="modal editor (Kakoune-inspired)" ;;
				nvim)  desc="Neovim" ;;
			esac
			if [[ ",$editor_prev," == *",${key},"* ]]; then
				echo "  ${num}) ${label} — ${desc} [installed]"
			else
				echo "  ${num}) ${label} — ${desc}"
			fi
		done
		read -rp "Selection [1,2,3,4,5/all/skip]: " editor_selection
		if [ -z "$editor_selection" ] && [ -n "$editor_prev" ]; then
			editor_list="$editor_prev"
		else
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
	fi
	echo "$editor_list" > "$EDITOR_CONFIG"
elif [ -n "$editor_prev" ]; then
	editor_list="$editor_prev"
	[ -n "$editor_list" ] && echo "Installing editors: $editor_list (from previous selection)"
else
	echo "Skipping editor selection (non-interactive)"
	editor_list=""
	echo "$editor_list" > "$EDITOR_CONFIG"
fi

install_micro() {
	if command -v micro &>/dev/null; then echo "Micro already installed, skipping."; return 0; fi
	echo "Installing Micro v${MICRO_VERSION}..."
	sb_install micro "$MICRO_VERSION"
}

install_edit() {
	if command -v edit &>/dev/null; then echo "Edit already installed, skipping."; return 0; fi
	echo "Installing Edit v${EDIT_VERSION}..."
	SB_ASSET_VERSION="$EDIT_ASSET_VERSION" sb_install edit "$EDIT_VERSION"
}

install_fresh() {
	if command -v fresh &>/dev/null; then echo "Fresh already installed, skipping."; return 0; fi
	echo "Installing Fresh v${FRESH_VERSION}..."
	sb_install fresh "$FRESH_VERSION"
}

install_helix() {
	if command -v hx &>/dev/null; then echo "Helix already installed, skipping."; return 0; fi
	echo "Installing Helix v${HELIX_VERSION}..."
	if sudo -n true 2>/dev/null; then
		sudo apt-get update -qq && sudo apt-get install -y -qq xz-utils >/dev/null 2>&1
	elif ! command -v xz &>/dev/null; then
		echo "Error: xz-utils required for Helix but sudo unavailable to install it. Skipping Helix." >&2
		return 1
	fi
	sb_install helix "$HELIX_VERSION"
}

install_nvim() {
	if command -v nvim &>/dev/null; then echo "Neovim already installed, skipping."; return 0; fi
	echo "Installing Neovim v${NVIM_VERSION}..."
	sb_install nvim "$NVIM_VERSION"
}

editor_cmd=""
for editor in $(echo "$editor_list" | tr ',' ' '); do
	case "$editor" in
		micro) install_micro; [ -z "$editor_cmd" ] && editor_cmd="micro" ;;
		edit) install_edit; [ -z "$editor_cmd" ] && editor_cmd="edit" ;;
		fresh) install_fresh; [ -z "$editor_cmd" ] && editor_cmd="fresh" ;;
		helix) install_helix && { [ -z "$editor_cmd" ] && editor_cmd="hx"; true; } || echo "Warning: Helix installation failed, skipping." ;;
		nvim) install_nvim; [ -z "$editor_cmd" ] && editor_cmd="nvim" ;;
	esac
done

# Set EDITOR to the first selected editor
{
	if [ -n "$editor_cmd" ]; then
		echo "export EDITOR='$editor_cmd'"
	fi
} > ~/.squarebox-editor-aliases

# Terminal multiplexer
MUX_CONFIG="/workspace/.squarebox/multiplexer"

mux_prev=""
if [ -f "$MUX_CONFIG" ]; then
	mux_prev=$(cat "$MUX_CONFIG")
fi

if $INTERACTIVE; then
	echo
	if $HAS_GUM; then
		# Build --selected from previously saved multiplexers
		gum_selected=""
		for mux in $(echo "$mux_prev" | tr ',' ' '); do
			case "$mux" in
				tmux)   gum_selected="${gum_selected:+$gum_selected,}tmux" ;;
				zellij) gum_selected="${gum_selected:+$gum_selected,}zellij" ;;
			esac
		done
		gum_args=(--no-limit --header "Select terminal multiplexer:")
		[ -n "$gum_selected" ] && gum_args+=(--selected "$gum_selected")
		selected=$(gum choose "${gum_args[@]}" \
			"tmux" "zellij") || true
		mux_list=""
		while IFS= read -r line; do
			[ -z "$line" ] && continue
			mux_list="${mux_list:+$mux_list,}${line}"
		done <<< "$selected"
	else
		echo "Select terminal multiplexer (comma-separated, or 'all', or press Enter to skip):"
		for mux_item in "1:tmux:classic terminal multiplexer" "2:zellij:friendly terminal workspace"; do
			num="${mux_item%%:*}"; rest="${mux_item#*:}"; key="${rest%%:*}"; desc="${rest#*:}"
			if [[ ",$mux_prev," == *",${key},"* ]]; then
				echo "  ${num}) ${key} — ${desc} [installed]"
			else
				echo "  ${num}) ${key} — ${desc}"
			fi
		done
		read -rp "Selection [1,2/all/skip]: " mux_selection
		if [ -z "$mux_selection" ] && [ -n "$mux_prev" ]; then
			mux_list="$mux_prev"
		else
			mux_list=""
			if [ "$mux_selection" = "all" ]; then
				mux_list="tmux,zellij"
			elif [ -n "$mux_selection" ]; then
				for item in $(echo "$mux_selection" | tr ',' ' '); do
					case "$item" in
						1) mux_list="${mux_list:+$mux_list,}tmux" ;;
						2) mux_list="${mux_list:+$mux_list,}zellij" ;;
					esac
				done
			fi
		fi
	fi
	echo "$mux_list" > "$MUX_CONFIG"
elif [ -n "$mux_prev" ]; then
	mux_list="$mux_prev"
	[ -n "$mux_list" ] && echo "Installing multiplexer(s): $mux_list (from previous selection)"
else
	echo "Skipping multiplexer selection (non-interactive)"
	mux_list=""
	echo "$mux_list" > "$MUX_CONFIG"
fi

install_tmux() {
	if command -v tmux &>/dev/null; then echo "Tmux already installed, skipping."; return 0; fi
	echo "Installing tmux via apt..."
	sudo apt-get update -qq && sudo apt-get install -y -qq tmux >/dev/null 2>&1
	# Install default config
	if [ ! -f ~/.tmux.conf ]; then
		cat > ~/.tmux.conf <<-'TMUXCONF'
		set -g mouse on
		set -g default-terminal "tmux-256color"
		set -g history-limit 10000
		set -g prefix C-a
		unbind C-b
		bind C-a send-prefix
		TMUXCONF
	fi
}

install_zellij() {
	if command -v zellij &>/dev/null; then echo "Zellij already installed, skipping."; return 0; fi
	echo "Installing Zellij v${ZELLIJ_VERSION}..."
	sb_install zellij "$ZELLIJ_VERSION"
}

for mux in $(echo "$mux_list" | tr ',' ' '); do
	case "$mux" in
		tmux) install_tmux ;;
		zellij) install_zellij ;;
	esac
done

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
		gum_args=(--no-limit --header "Select SDKs to install:")
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
		echo "Select SDKs to install (comma-separated, 'all', or 'none' to skip):"
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
	if [ -n "$sdk_list" ]; then
		echo "Installing SDKs: $sdk_list (from previous selection)"
	fi
else
	echo "Skipping SDK selection (non-interactive)"
	sdk_list=""
	echo "$sdk_list" > "$SDK_CONFIG"
fi

# Pinned versions — update via: scripts/update-versions.sh
GO_VERSION="go1.26.1"

for _var in GO_VERSION; do
	if [ -z "${!_var:-}" ]; then
		echo "Error: ${_var} is empty or unset" >&2
		exit 1
	fi
done

# install_node is defined earlier (needed by npm-based AI tools)

install_python() {
	if command -v uv &>/dev/null; then echo "uv already installed, skipping."; return 0; fi
	echo "Installing Python (via uv)..."
	# Trust boundary: the uv install script manages its own binary fetching
	# and verification. We rely on HTTPS for script integrity.
	curl -fsSL https://astral.sh/uv/install.sh | bash 2>/dev/null
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
	curl -fsSLo /tmp/go.tar.gz "https://go.dev/dl/${GO_VERSION}.linux-${SB_GOARCH}.tar.gz"
	verify_checksum /tmp/go.tar.gz "${GO_VERSION}.linux-${SB_GOARCH}.tar.gz"
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
	curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel LTS 2>&1 | grep -E '^dotnet-install: (Installed|.*finished)' || true
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

echo "🟧📦 You're in the box."
