#!/usr/bin/env bash
set -euo pipefail

SB_TMPDIR=$(mktemp -d)
export SB_TMPDIR
trap 'rm -rf "$SB_TMPDIR"' EXIT

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

section_header() {
	if $HAS_GUM; then
		gum style --foreground 212 --bold "$1"
	else
		echo "--- $1 ---"
	fi
}

run_with_spinner() {
	local title="$1"; shift
	if $HAS_GUM; then
		# Run command in background — gum spin can't invoke shell functions directly
		"$@" &>/dev/null &
		local cmd_pid=$!
		gum spin --spinner dot --title "$title" -- bash -c "tail --pid=$cmd_pid -f /dev/null"
		local rc=0
		wait "$cmd_pid" || rc=$?
		if [ $rc -eq 0 ]; then
			gum style --foreground 2 "✓ ${title%...}"
		fi
		return $rc
	else
		echo "$title"
		"$@"
	fi
}

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
			if $HAS_GUM; then
				name=$(gum input --placeholder "Your Name" --header "Git name:" --width 40) || true
			else
				read -rp "Git name: " name
			fi
			[ -n "$name" ] && break
			echo "Name cannot be empty."
		done
		git config --file ~/.config/git/config user.name "$name"
	else
		echo "Skipping git identity setup (non-interactive)"
	fi
fi

if [ -z "$(git config --global user.email 2>/dev/null)" ]; then
	if $INTERACTIVE; then
		while true; do
			if $HAS_GUM; then
				email=$(gum input --placeholder "you@example.com" --header "Git email:" --width 40) || true
			else
				read -rp "Git email: " email
			fi
			[ -n "$email" ] && break
			echo "Email cannot be empty."
		done
		git config --file ~/.config/git/config user.email "$email"
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
fi

if $INTERACTIVE; then
	echo
	section_header "AI Coding Assistants"
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
NVIM_VERSION="0.12.0"
ZELLIJ_VERSION="0.44.0"

for _var in OPENCODE_VERSION MICRO_VERSION EDIT_VERSION EDIT_ASSET_VERSION FRESH_VERSION NVIM_VERSION ZELLIJ_VERSION; do
	if [ -z "${!_var:-}" ]; then
		echo "Error: ${_var} is empty or unset" >&2
		exit 1
	fi
done

# Pinned SDK versions needed early (for npm-based AI tools)
NVM_VERSION="0.40.3"

# SDK path setup file (create if missing, preserve on retry)
touch ~/.squarebox-sdk-paths

_install_node_inner() {
	rm -rf "$HOME/.nvm"
	curl -fsSo "${SB_TMPDIR}/nvm-install.sh" "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh"
	verify_checksum "${SB_TMPDIR}/nvm-install.sh" "nvm-install-v${NVM_VERSION}.sh"
	bash "${SB_TMPDIR}/nvm-install.sh" >/dev/null 2>&1
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
}

install_node() {
	if command -v node &>/dev/null; then echo "Node.js already installed, skipping."; return 0; fi
	run_with_spinner "Installing Node.js (via nvm v${NVM_VERSION})..." _install_node_inner
	# Source nvm in current shell (spinner runs in subshell)
	export NVM_DIR="$HOME/.nvm"
	# shellcheck source=/dev/null
	[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
	if ! command -v node &>/dev/null; then
		echo "Error: Node.js binary not found after installation" >&2
		return 1
	fi
}

# Ensure Node.js is available for npm-based AI tools
ensure_node_for_npm() {
	if command -v node &>/dev/null; then return 0; fi
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
	run_with_spinner "Installing GitHub Copilot CLI..." npm install -g --silent @githubnext/github-copilot-cli
}

install_gemini() {
	if command -v gemini &>/dev/null; then echo "Google Gemini CLI already installed, skipping."; return 0; fi
	ensure_node_for_npm
	run_with_spinner "Installing Google Gemini CLI..." npm install -g --silent @google/gemini-cli
}

install_codex() {
	if command -v codex &>/dev/null; then echo "OpenAI Codex CLI already installed, skipping."; return 0; fi
	ensure_node_for_npm
	run_with_spinner "Installing OpenAI Codex CLI..." npm install -g --silent @openai/codex
}

for ai_tool in $(echo "$ai_choice" | tr ',' ' '); do
	case "$ai_tool" in
		claude)
			# Trust boundary: the Claude Code install script manages its own binary
			# fetching and verification. We rely on HTTPS for script integrity.
			run_with_spinner "Installing Claude Code..." \
				bash -c 'curl -fsSL https://claude.ai/install.sh | bash >/dev/null 2>&1' \
				|| echo "Warning: Claude Code installation failed."
			;;
		opencode)
			if command -v opencode &>/dev/null; then
				echo "OpenCode already installed, skipping."
			else
				run_with_spinner "Installing OpenCode v${OPENCODE_VERSION}..." sb_install opencode "$OPENCODE_VERSION" \
					|| echo "Warning: OpenCode installation failed."
			fi
			;;
		copilot)  install_copilot || echo "Warning: GitHub Copilot CLI installation failed." ;;
		gemini)   install_gemini || echo "Warning: Google Gemini CLI installation failed." ;;
		codex)    install_codex || echo "Warning: OpenAI Codex CLI installation failed." ;;
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
	section_header "Text Editors"
	if $HAS_GUM; then
		# Build --selected from previously saved editors
		gum_selected=""
		for ed in $(echo "$editor_prev" | tr ',' ' '); do
			case "$ed" in
				micro) gum_selected="${gum_selected:+$gum_selected,}micro" ;;
				edit)  gum_selected="${gum_selected:+$gum_selected,}edit" ;;
				fresh) gum_selected="${gum_selected:+$gum_selected,}fresh" ;;
				nvim)  gum_selected="${gum_selected:+$gum_selected,}nvim" ;;
			esac
		done
		echo "Nano is always available as the default editor."
		gum_args=(--no-limit --header "Select text editors to install:")
		[ -n "$gum_selected" ] && gum_args+=(--selected "$gum_selected")
		selected=$(gum choose "${gum_args[@]}" \
			"micro" "edit" "fresh" "nvim") || true
		editor_list=""
		while IFS= read -r line; do
			[ -z "$line" ] && continue
			editor_list="${editor_list:+$editor_list,}${line}"
		done <<< "$selected"
	else
		echo "Select text editors to install (comma-separated, or 'all', or press Enter to skip):"
		echo "  Nano is always available as the default editor."
		for ed_item in "1:micro:micro" "2:edit:edit" "3:fresh:fresh" "4:nvim:nvim"; do
			num="${ed_item%%:*}"; rest="${ed_item#*:}"; key="${rest%%:*}"; label="${rest#*:}"
			case "$key" in
				micro) desc="modern, intuitive terminal editor" ;;
				edit)  desc="terminal text editor (Microsoft)" ;;
				fresh) desc="modern terminal text editor" ;;
				nvim)  desc="Neovim" ;;
			esac
			if [[ ",$editor_prev," == *",${key},"* ]]; then
				echo "  ${num}) ${label} — ${desc} [installed]"
			else
				echo "  ${num}) ${label} — ${desc}"
			fi
		done
		read -rp "Selection [1,2,3,4/all/skip]: " editor_selection
		if [ -z "$editor_selection" ] && [ -n "$editor_prev" ]; then
			editor_list="$editor_prev"
		else
			editor_list=""
			if [ "$editor_selection" = "all" ]; then
				editor_list="micro,edit,fresh,nvim"
			elif [ -n "$editor_selection" ]; then
				for item in $(echo "$editor_selection" | tr ',' ' '); do
					case "$item" in
						1) editor_list="${editor_list:+$editor_list,}micro" ;;
						2) editor_list="${editor_list:+$editor_list,}edit" ;;
						3) editor_list="${editor_list:+$editor_list,}fresh" ;;
						4) editor_list="${editor_list:+$editor_list,}nvim" ;;
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
	run_with_spinner "Installing Micro v${MICRO_VERSION}..." sb_install micro "$MICRO_VERSION"
}

install_edit() {
	if command -v edit &>/dev/null; then echo "Edit already installed, skipping."; return 0; fi
	SB_ASSET_VERSION="$EDIT_ASSET_VERSION" run_with_spinner "Installing Edit v${EDIT_VERSION}..." sb_install edit "$EDIT_VERSION"
}

install_fresh() {
	if command -v fresh &>/dev/null; then echo "Fresh already installed, skipping."; return 0; fi
	run_with_spinner "Installing Fresh v${FRESH_VERSION}..." sb_install fresh "$FRESH_VERSION"
}

install_nvim() {
	if command -v nvim &>/dev/null; then echo "Neovim already installed, skipping."; return 0; fi
	run_with_spinner "Installing Neovim v${NVIM_VERSION}..." sb_install nvim "$NVIM_VERSION"
}

installed_editors=()
for editor in $(echo "$editor_list" | tr ',' ' '); do
	case "$editor" in
		micro) install_micro && installed_editors+=("micro") || echo "Warning: Micro installation failed." ;;
		edit) install_edit && installed_editors+=("edit") || echo "Warning: Edit installation failed." ;;
		fresh) install_fresh && installed_editors+=("fresh") || echo "Warning: Fresh installation failed." ;;
		nvim) install_nvim && installed_editors+=("nvim") || echo "Warning: Neovim installation failed." ;;
	esac
done

# Prompt for default editor if multiple were installed
editor_cmd=""
if [ ${#installed_editors[@]} -gt 1 ] && $INTERACTIVE; then
	echo
	if $HAS_GUM; then
		editor_cmd=$(gum choose --header "Select default editor (\$EDITOR):" \
			"nano" "${installed_editors[@]}") || true
	else
		echo "Select default editor (\$EDITOR):"
		echo "  0) nano"
		for i in "${!installed_editors[@]}"; do
			echo "  $((i+1))) ${installed_editors[$i]}"
		done
		read -rp "Selection [0-${#installed_editors[@]}]: " ed_sel
		if [ -n "$ed_sel" ] && [ "$ed_sel" -ge 1 ] 2>/dev/null && [ "$ed_sel" -le ${#installed_editors[@]} ]; then
			editor_cmd="${installed_editors[$((ed_sel-1))]}"
		fi
	fi
	[ "$editor_cmd" = "nano" ] && editor_cmd=""
elif [ ${#installed_editors[@]} -ge 1 ]; then
	editor_cmd="${installed_editors[0]}"
fi

# Set EDITOR (nano is the default if nothing chosen)
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
	section_header "Terminal Multiplexers"
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

_install_tmux_inner() {
	sudo apt-get update -qq && sudo apt-get install -y -qq tmux >/dev/null 2>&1
	# Install default config (Omarchy-inspired defaults)
	mkdir -p ~/.config/tmux
	if [ ! -f ~/.config/tmux/tmux.conf ]; then
		cat > ~/.config/tmux/tmux.conf <<-'TMUXCONF'
		# Prefix
		set -g prefix C-Space
		set -g prefix2 C-b
		bind C-Space send-prefix

		# Reload config
		bind q source-file ~/.config/tmux/tmux.conf \; display "Configuration reloaded"

		# Vi mode for copy
		setw -g mode-keys vi
		bind -T copy-mode-vi v send -X begin-selection
		bind -T copy-mode-vi y send -X copy-selection-and-cancel

		# Pane Controls
		bind h split-window -v -c "#{pane_current_path}"
		bind v split-window -h -c "#{pane_current_path}"
		bind x kill-pane

		bind -n C-M-Left select-pane -L
		bind -n C-M-Right select-pane -R
		bind -n C-M-Up select-pane -U
		bind -n C-M-Down select-pane -D

		bind -n C-M-S-Left resize-pane -L 5
		bind -n C-M-S-Down resize-pane -D 5
		bind -n C-M-S-Up resize-pane -U 5
		bind -n C-M-S-Right resize-pane -R 5

		# Window navigation
		bind r command-prompt -I "#W" "rename-window -- '%%'"
		bind c new-window -c "#{pane_current_path}"
		bind k kill-window

		bind -n M-1 select-window -t 1
		bind -n M-2 select-window -t 2
		bind -n M-3 select-window -t 3
		bind -n M-4 select-window -t 4
		bind -n M-5 select-window -t 5
		bind -n M-6 select-window -t 6
		bind -n M-7 select-window -t 7
		bind -n M-8 select-window -t 8
		bind -n M-9 select-window -t 9

		bind -n M-Left select-window -t -1
		bind -n M-Right select-window -t +1
		bind -n M-S-Left swap-window -t -1 \; select-window -t -1
		bind -n M-S-Right swap-window -t +1 \; select-window -t +1

		# Session controls
		bind R command-prompt -I "#S" "rename-session -- '%%'"
		bind C new-session -c "#{pane_current_path}"
		bind K kill-session
		bind P switch-client -p
		bind N switch-client -n

		bind -n M-Up switch-client -p
		bind -n M-Down switch-client -n

		# General
		set -g default-terminal "tmux-256color"
		set -ag terminal-overrides ",*:RGB"
		set -g mouse on
		set -g base-index 1
		setw -g pane-base-index 1
		set -g renumber-windows on
		set -g history-limit 50000
		set -g escape-time 0
		set -g focus-events on
		set -g set-clipboard on
		set -g allow-passthrough on
		setw -g aggressive-resize on
		set -g detach-on-destroy off

		# Status bar
		set -g status-position top
		set -g status-interval 5
		set -g status-left-length 30
		set -g status-right-length 50
		set -g window-status-separator ""
		set -gw automatic-rename on
		set -gw automatic-rename-format '#{b:pane_current_path}'

		# Theme
		set -g status-style "bg=default,fg=default"
		set -g status-left "#[fg=black,bg=blue,bold] #S #[bg=default] "
		set -g status-right "#[fg=blue]#{?pane_in_mode,COPY ,}#{?client_prefix,PREFIX ,}#{?window_zoomed_flag,ZOOM ,}#[fg=brightblack]#h "
		set -g window-status-format "#[fg=brightblack] #I:#W "
		set -g window-status-current-format "#[fg=blue,bold] #I:#W "
		set -g pane-border-style "fg=brightblack"
		set -g pane-active-border-style "fg=blue"
		set -g message-style "bg=default,fg=blue"
		set -g message-command-style "bg=default,fg=blue"
		set -g mode-style "bg=blue,fg=black"
		setw -g clock-mode-colour blue
		TMUXCONF
	fi
}

install_tmux() {
	if command -v tmux &>/dev/null; then echo "Tmux already installed, skipping."; return 0; fi
	run_with_spinner "Installing tmux..." _install_tmux_inner
}

_install_zellij_inner() {
	sb_install zellij "$ZELLIJ_VERSION"
	# Install default config (Omarchy-inspired defaults to match tmux)
	mkdir -p ~/.config/zellij
	if [ ! -f ~/.config/zellij/config.kdl ]; then
		cat > ~/.config/zellij/config.kdl <<-'ZELLIJCONF'
		// squarebox — Omarchy-inspired defaults (mirroring tmux keybindings)

		// ── General options ─────────────────────────────────────────────
		mouse_mode true
		copy_on_select true
		scroll_buffer_size 50000
		pane_frames false
		auto_layout true
		on_force_close "quit"
		simplified_ui true
		session_serialization true
		support_kitty_keyboard_protocol true

		// ── Theme — blue accent, minimal styling, transparent bg ────────
		themes {
		    squarebox {
		        fg "#c0caf5"
		        bg "#1a1b26"
		        black "#15161e"
		        red "#f7768e"
		        green "#9ece6a"
		        yellow "#e0af68"
		        blue "#7aa2f7"
		        magenta "#bb9af7"
		        cyan "#7dcfff"
		        white "#a9b1d6"
		        orange "#ff9e64"
		    }
		}
		theme "squarebox"

		// ── Plugins ─────────────────────────────────────────────────────
		plugins {
		    tab-bar location="zellij:tab-bar"
		    status-bar location="zellij:status-bar"
		    compact-bar location="zellij:compact-bar"
		    session-manager location="zellij:session-manager"
		    configuration location="zellij:configuration"
		}

		// ── Keybindings ─────────────────────────────────────────────────
		keybinds clear-defaults=true {
		    normal {
		        // Pane navigation — Ctrl+Alt+Arrow
		        bind "Ctrl Alt Left" { MoveFocus "Left"; }
		        bind "Ctrl Alt Right" { MoveFocus "Right"; }
		        bind "Ctrl Alt Up" { MoveFocus "Up"; }
		        bind "Ctrl Alt Down" { MoveFocus "Down"; }

		        // Pane resizing — Ctrl+Alt+Shift+Arrow
		        bind "Ctrl Alt Shift Left" { Resize "Left"; }
		        bind "Ctrl Alt Shift Right" { Resize "Right"; }
		        bind "Ctrl Alt Shift Up" { Resize "Up"; }
		        bind "Ctrl Alt Shift Down" { Resize "Down"; }

		        // Tab navigation — Alt+1-9 (base index 1)
		        bind "Alt 1" { GoToTab 1; }
		        bind "Alt 2" { GoToTab 2; }
		        bind "Alt 3" { GoToTab 3; }
		        bind "Alt 4" { GoToTab 4; }
		        bind "Alt 5" { GoToTab 5; }
		        bind "Alt 6" { GoToTab 6; }
		        bind "Alt 7" { GoToTab 7; }
		        bind "Alt 8" { GoToTab 8; }
		        bind "Alt 9" { GoToTab 9; }

		        // Tab cycling — Alt+Left/Right
		        bind "Alt Left" { GoToPreviousTab; }
		        bind "Alt Right" { GoToNextTab; }

		        // Tab reordering — Alt+Shift+Left/Right
		        bind "Alt Shift Left" { MoveTab "Left"; }
		        bind "Alt Shift Right" { MoveTab "Right"; }

		        // Session switching — Alt+Up/Down (launches session manager)
		        bind "Alt Up" {
		            LaunchOrFocusPlugin "session-manager" {
		                floating true
		                move_to_focused_tab true
		            };
		        }
		        bind "Alt Down" {
		            LaunchOrFocusPlugin "session-manager" {
		                floating true
		                move_to_focused_tab true
		            };
		        }

		        // Prefix-style bindings via Ctrl+Space (tmux-like leader)
		        bind "Ctrl Space" { SwitchToMode "Tmux"; }
		    }

		    locked {
		        bind "Ctrl Space" { SwitchToMode "Normal"; }
		    }

		    tmux {
		        bind "Ctrl Space" { SwitchToMode "Normal"; }
		        bind "Esc" { SwitchToMode "Normal"; }

		        // Pane splitting (h=horizontal, v=vertical — matching tmux)
		        bind "h" { NewPane "Down"; SwitchToMode "Normal"; }
		        bind "v" { NewPane "Right"; SwitchToMode "Normal"; }
		        bind "x" { CloseFocus; SwitchToMode "Normal"; }

		        // Tab/window management
		        bind "c" { NewTab; SwitchToMode "Normal"; }
		        bind "k" { CloseTab; SwitchToMode "Normal"; }
		        bind "r" { SwitchToMode "RenameTab"; TabNameInput 0; }

		        // Session management
		        bind "d" { Detach; }
		        bind "w" {
		            LaunchOrFocusPlugin "session-manager" {
		                floating true
		                move_to_focused_tab true
		            };
		            SwitchToMode "Normal";
		        }

		        // Rename pane
		        bind "R" { SwitchToMode "RenamePane"; PaneNameInput 0; }

		        // Tab navigation (1-9 in prefix mode)
		        bind "1" { GoToTab 1; SwitchToMode "Normal"; }
		        bind "2" { GoToTab 2; SwitchToMode "Normal"; }
		        bind "3" { GoToTab 3; SwitchToMode "Normal"; }
		        bind "4" { GoToTab 4; SwitchToMode "Normal"; }
		        bind "5" { GoToTab 5; SwitchToMode "Normal"; }
		        bind "6" { GoToTab 6; SwitchToMode "Normal"; }
		        bind "7" { GoToTab 7; SwitchToMode "Normal"; }
		        bind "8" { GoToTab 8; SwitchToMode "Normal"; }
		        bind "9" { GoToTab 9; SwitchToMode "Normal"; }

		        // Pane navigation (arrow keys in prefix mode)
		        bind "Left" { MoveFocus "Left"; SwitchToMode "Normal"; }
		        bind "Right" { MoveFocus "Right"; SwitchToMode "Normal"; }
		        bind "Up" { MoveFocus "Up"; SwitchToMode "Normal"; }
		        bind "Down" { MoveFocus "Down"; SwitchToMode "Normal"; }

		        // Toggle fullscreen/floating
		        bind "z" { ToggleFocusFullscreen; SwitchToMode "Normal"; }
		        bind "f" { ToggleFloatingPanes; SwitchToMode "Normal"; }

		        // Enter scroll/copy mode (vi-style — like tmux [ )
		        bind "[" { SwitchToMode "Scroll"; }
		    }

		    // ── Scroll mode (vi-style copy mode) ────────────────────────
		    scroll {
		        bind "Esc" { SwitchToMode "Normal"; }
		        bind "q" { ScrollToBottom; SwitchToMode "Normal"; }
		        bind "j" "Down" { ScrollDown; }
		        bind "k" "Up" { ScrollUp; }
		        bind "Ctrl f" "PageDown" { PageScrollDown; }
		        bind "Ctrl b" "PageUp" { PageScrollUp; }
		        bind "d" { HalfPageScrollDown; }
		        bind "u" { HalfPageScrollUp; }
		        bind "G" { ScrollToBottom; }
		        bind "g" { ScrollToTop; }
		        bind "/" { SwitchToMode "EnterSearch"; SearchInput 0; }
		    }

		    search {
		        bind "Esc" { SwitchToMode "Normal"; }
		        bind "q" { ScrollToBottom; SwitchToMode "Normal"; }
		        bind "j" "Down" { ScrollDown; }
		        bind "k" "Up" { ScrollUp; }
		        bind "Ctrl f" "PageDown" { PageScrollDown; }
		        bind "Ctrl b" "PageUp" { PageScrollUp; }
		        bind "d" { HalfPageScrollDown; }
		        bind "u" { HalfPageScrollUp; }
		        bind "n" { Search "down"; }
		        bind "N" { Search "up"; }
		        bind "c" { SearchToggleOption "CaseSensitivity"; }
		        bind "w" { SearchToggleOption "Wrap"; }
		        bind "o" { SearchToggleOption "WholeWord"; }
		        bind "G" { ScrollToBottom; }
		        bind "g" { ScrollToTop; }
		    }

		    entersearch {
		        bind "Esc" { SwitchToMode "Scroll"; }
		        bind "Ctrl c" { SwitchToMode "Scroll"; }
		        bind "Enter" { SwitchToMode "Search"; }
		    }

		    renametab {
		        bind "Esc" { UndoRenameTab; SwitchToMode "Normal"; }
		        bind "Ctrl c" { UndoRenameTab; SwitchToMode "Normal"; }
		        bind "Enter" { SwitchToMode "Normal"; }
		    }

		    renamepane {
		        bind "Esc" { UndoRenamePane; SwitchToMode "Normal"; }
		        bind "Ctrl c" { UndoRenamePane; SwitchToMode "Normal"; }
		        bind "Enter" { SwitchToMode "Normal"; }
		    }

		    // Allow Ctrl+Space to return to normal from any non-normal mode
		    shared_except "normal" "locked" "tmux" {
		        bind "Ctrl Space" { SwitchToMode "Normal"; }
		    }
		}
		ZELLIJCONF

		# Create a default layout with the compact bar at the top
		mkdir -p ~/.config/zellij/layouts
		if [ ! -f ~/.config/zellij/layouts/default.kdl ]; then
			cat > ~/.config/zellij/layouts/default.kdl <<-'ZELLIJLAYOUT'
			layout {
			    pane size=1 borderless=true {
			        plugin location="compact-bar"
			    }
			    pane
			}
			ZELLIJLAYOUT
		fi
	fi
}

install_zellij() {
	if command -v zellij &>/dev/null; then echo "Zellij already installed, skipping."; return 0; fi
	run_with_spinner "Installing Zellij v${ZELLIJ_VERSION}..." _install_zellij_inner
}

for mux in $(echo "$mux_list" | tr ',' ' '); do
	case "$mux" in
		tmux) install_tmux || echo "Warning: tmux installation failed." ;;
		zellij) install_zellij || echo "Warning: Zellij installation failed." ;;
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
	section_header "SDKs"
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

_install_python_inner() {
	# Trust boundary: the uv install script manages its own binary fetching
	# and verification. We rely on HTTPS for script integrity.
	curl -fsSL https://astral.sh/uv/install.sh | bash &>/dev/null
	if ! grep -q '\.local/bin' ~/.squarebox-sdk-paths 2>/dev/null; then
		cat <<'PATHS' >> ~/.squarebox-sdk-paths
export PATH="$HOME/.local/bin:$PATH"
PATHS
	fi
}

install_python() {
	if command -v uv &>/dev/null; then echo "uv already installed, skipping."; return 0; fi
	run_with_spinner "Installing Python (via uv)..." _install_python_inner
	export PATH="$HOME/.local/bin:$PATH"
	if ! command -v uv &>/dev/null; then
		echo "Error: uv binary not found after installation" >&2
		return 1
	fi
}

_install_go_inner() {
	rm -rf "$HOME/.local/go"
	curl -fsSLo "${SB_TMPDIR}/go.tar.gz" "https://go.dev/dl/${GO_VERSION}.linux-${SB_GOARCH}.tar.gz"
	verify_checksum "${SB_TMPDIR}/go.tar.gz" "${GO_VERSION}.linux-${SB_GOARCH}.tar.gz"
	tar xzf "${SB_TMPDIR}/go.tar.gz" -C ~/.local
	if ! grep -q 'GOROOT' ~/.squarebox-sdk-paths 2>/dev/null; then
		cat <<'PATHS' >> ~/.squarebox-sdk-paths
export GOROOT="$HOME/.local/go"
export GOPATH="$HOME/go"
export PATH="$GOROOT/bin:$GOPATH/bin:$PATH"
PATHS
	fi
}

install_go() {
	if [ -x "${HOME}/.local/go/bin/go" ]; then echo "Go already installed, skipping."; return 0; fi
	run_with_spinner "Installing Go ${GO_VERSION}..." _install_go_inner
	if [ ! -x "${HOME}/.local/go/bin/go" ]; then
		echo "Error: Go binary not found after installation" >&2
		return 1
	fi
}

_install_dotnet_inner() {
	rm -rf "$HOME/.dotnet"
	# Trust boundary: the .NET install script manages its own binary fetching
	# and verification. We rely on HTTPS for script integrity.
	curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel LTS >/dev/null 2>&1
	if ! grep -q 'DOTNET_ROOT' ~/.squarebox-sdk-paths 2>/dev/null; then
		cat <<'PATHS' >> ~/.squarebox-sdk-paths
export DOTNET_ROOT="$HOME/.dotnet"
export PATH="$DOTNET_ROOT:$DOTNET_ROOT/tools:$PATH"
PATHS
	fi
}

install_dotnet() {
	if [ -x "${HOME}/.dotnet/dotnet" ]; then echo ".NET already installed, skipping."; return 0; fi
	run_with_spinner "Installing .NET..." _install_dotnet_inner
	if [ ! -x "${HOME}/.dotnet/dotnet" ]; then
		echo "Error: .NET binary not found after installation" >&2
		return 1
	fi
}

for sdk in $(echo "$sdk_list" | tr ',' ' '); do
	case "$sdk" in
		node) install_node || echo "Warning: Node.js installation failed." ;;
		python) install_python || echo "Warning: Python (uv) installation failed." ;;
		go) install_go || echo "Warning: Go installation failed." ;;
		dotnet) install_dotnet || echo "Warning: .NET installation failed." ;;
	esac
done

echo

if $HAS_GUM; then
	gum style --border double --padding "0 2" --border-foreground 212 "🟧📦 You're in the box."
else
	echo "🟧📦 You're in the box."
fi
