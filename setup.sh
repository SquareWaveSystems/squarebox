#!/usr/bin/env bash
set -euo pipefail

# ── Argument parsing ────────────────────────────────────────────────────
# When called from sqrbx-setup wrapper: setup.sh --rerun [section ...]
# When called from .bashrc first-run:   setup.sh (no args)

SB_RERUN=false
SB_SECTIONS=()

while [[ $# -gt 0 ]]; do
	case "$1" in
		--rerun) SB_RERUN=true; shift ;;
		*)       SB_SECTIONS+=("$1"); shift ;;
	esac
done

# If --rerun with no specific sections, run all sections
if $SB_RERUN && [ ${#SB_SECTIONS[@]} -eq 0 ]; then
	SB_SECTIONS=(git github ai editors tuis multiplexers sdks shell learn)
fi

should_run() {
	# In first-run mode (no --rerun), always run all sections
	$SB_RERUN || return 0
	local section="$1"
	for s in "${SB_SECTIONS[@]}"; do
		[ "$s" = "$section" ] && return 0
	done
	return 1
}

SB_TMPDIR=$(mktemp -d)
export SB_TMPDIR
trap 'rm -rf "$SB_TMPDIR"' EXIT

# Fix /workspace ownership if volume mount left it owned by a different UID
if [ -d /workspace ] && ! [ -w /workspace ]; then
	if ! command -v sudo >/dev/null 2>&1; then
		echo "ERROR: /workspace is not writable and sudo is not available to fix ownership." >&2
		echo "Please make /workspace writable for user 'dev' or rerun with appropriate privileges." >&2
		exit 1
	elif ! sudo -n chown dev:dev /workspace 2>/dev/null; then
		echo "ERROR: Failed to change ownership of /workspace to dev:dev." >&2
		echo "This can happen if passwordless sudo is not available for chown, or the volume type does not allow chown." >&2
		echo "Please run 'sudo chown dev:dev /workspace' manually or adjust the mount configuration and try again." >&2
		exit 1
	fi
fi

# Source shared tool library. Optional tools install from latest upstream
# releases over HTTPS at setup time, so the library's default no-op
# sb_verify is fine here since we don't ship checksums for these tools.
export SB_TOOLS_YAML=/usr/local/lib/squarebox/tools.yaml
source /usr/local/lib/squarebox/tool-lib.sh

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

# Install Debian packages resiliently.
#
# `apt-get update` refreshes *every* configured source, including the
# third-party repos wired up at build time (github-cli, gierens/eza). Those are
# only needed to install gh/eza during the image build — but their source lists
# linger in the image, so a transient outage of one of them (e.g. deb.gierens.de
# briefly serving no Release file) makes `apt-get update` exit non-zero. With the
# old `update && install` chaining that aborted the whole install of a base-repo
# package like tmux, failing E2E and sinking the release build.
#
# So let update fail soft — the reachable indexes (incl. the Debian base repo)
# still refresh — and gate on the install itself, which is the real requirement.
apt_install() {
	sudo apt-get update -qq || true
	# /etc/localtime is a read-only bind-mount in the running container (see
	# docker-compose.yml), so tzdata's postinst can never rewrite it: any apt
	# run that pulls a tzdata upgrade dies on a "device or resource busy" mv,
	# wedges dpkg half-configured, and cascades to every dependent (python3,
	# fish, …) — silently, since we discard output. Freeze tzdata (the host
	# owns the timezone via the mount) and install non-interactively so no
	# postinst can block on a debconf prompt in this tty-less context.
	sudo apt-mark hold tzdata >/dev/null 2>&1 || true
	local _apt_log
	if ! _apt_log=$(sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@" 2>&1); then
		echo "apt_install: failed to install: $*" >&2
		printf '%s\n' "$_apt_log" | tail -20 >&2
		return 1
	fi
}

if $SB_RERUN; then
	_sb_banner="🟧📦 squarebox setup (reconfigure)"
else
	_sb_banner="🟧📦 squarebox setup"
fi
if $HAS_GUM; then
	gum style --border double --padding "0 2" --border-foreground 208 "$_sb_banner"
else
	echo "=== $_sb_banner ==="
fi
echo

# Git identity
if should_run git; then
	# git config --file won't create parent dirs; ensure it exists before writing.
	# In the compose/GHCR pull path ~/.config/git is not bind-mounted, so it may
	# be absent inside the squarebox-home volume (issue: setup fails with
	# "could not lock config file .../.config/git/config: No such file or directory").
	mkdir -p ~/.config/git
	_current_name=$(git config --global user.name 2>/dev/null || true)
	_current_email=$(git config --global user.email 2>/dev/null || true)

	if $SB_RERUN && [ -n "$_current_name" ] && $INTERACTIVE; then
		# Existing identity on re-run: present it pre-filled so you can edit
		# inline or just accept it. Empty input (cleared gum value or a blank
		# read — i.e. hitting Enter) keeps the current value unchanged.
		if $HAS_GUM; then
			name=$(gum input --value "$_current_name" --header "Git name:" --width 40) || name="$_current_name"
		else
			read -rp "Git name [$_current_name]: " name
		fi
		[ -z "$name" ] && name="$_current_name"
		git config --file ~/.config/git/config user.name "$name"
		if $HAS_GUM; then
			email=$(gum input --value "$_current_email" --header "Git email:" --width 40) || email="$_current_email"
		else
			read -rp "Git email [$_current_email]: " email
		fi
		[ -z "$email" ] && email="$_current_email"
		# Only write email if we have a non-empty value (preserves "unset" state)
		[ -n "$email" ] && git config --file ~/.config/git/config user.email "$email"
	else
		if [ -z "$_current_name" ]; then
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

		if [ -z "$_current_email" ]; then
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
	fi
fi

# GitHub CLI config lives at ~/.config/gh (the gh default) and is preserved
# by the squarebox-home named volume. The legacy persistence path
# (/workspace/.squarebox/gh) is migrated once for users upgrading from a
# pre-named-volume install; new installs never touch it. The legacy paths
# are removed after a successful copy so the migration is self-healing and
# we don't leave stale credentials sitting in /workspace.
GH_PERSIST_LEGACY="/workspace/.squarebox/gh"
GH_SKIP_MARKER="$HOME/.squarebox-gh-skip"
GH_SKIP_MARKER_LEGACY="/workspace/.squarebox/gh-skip"
if [ -d "$GH_PERSIST_LEGACY" ] && [ ! -d ~/.config/gh ]; then
	mkdir -p ~/.config
	if cp -r "$GH_PERSIST_LEGACY" ~/.config/gh; then
		rm -rf "$GH_PERSIST_LEGACY"
	fi
fi
# Migrate legacy skip marker into $HOME so it persists with the rest of state.
if [ -f "$GH_SKIP_MARKER_LEGACY" ] && [ ! -f "$GH_SKIP_MARKER" ]; then
	touch "$GH_SKIP_MARKER"
	rm -f "$GH_SKIP_MARKER_LEGACY"
fi

# GitHub CLI (optional — users who don't use GitHub can skip this)
if should_run github; then
	if gh auth status &>/dev/null; then
		rm -f "$GH_SKIP_MARKER"
		if $SB_RERUN && $INTERACTIVE; then
			echo "GitHub CLI: already authenticated"
			gh auth status 2>&1 | head -5 || true
			if $HAS_GUM; then
				gum confirm "Re-authenticate?" --default=false && _do_reauth=true || _do_reauth=false
			else
				read -rp "Re-authenticate? [y/N]: " _reauth_reply
				case "${_reauth_reply:-N}" in
					[Yy]*) _do_reauth=true ;;
					*)     _do_reauth=false ;;
				esac
			fi
			if $_do_reauth; then
				BROWSER=echo gh auth login
			fi
		else
			echo "GitHub CLI: already authenticated"
		fi
	elif [ -f "$GH_SKIP_MARKER" ]; then
		if $SB_RERUN && $INTERACTIVE; then
			echo "GitHub CLI: previously skipped"
			if $HAS_GUM; then
				gum confirm "Sign in to GitHub?" --default=true && do_gh_login=true || do_gh_login=false
			else
				read -rp "Sign in to GitHub? [Y/n]: " gh_reply
				case "${gh_reply:-Y}" in
					[Nn]*) do_gh_login=false ;;
					*)     do_gh_login=true ;;
				esac
			fi
			if $do_gh_login; then
				echo "Logging into GitHub..."
				BROWSER=echo gh auth login
				if gh auth status &>/dev/null; then
					rm -f "$GH_SKIP_MARKER"
				else
					echo "GitHub CLI auth was not completed — skipping"
				fi
			fi
		else
			echo "GitHub CLI: sign-in skipped (run 'gh auth login' to change)"
		fi
	elif $INTERACTIVE; then
		echo
		if $HAS_GUM; then
			gum confirm "Sign in to GitHub?" --default=true && do_gh_login=true || do_gh_login=false
		else
			read -rp "Sign in to GitHub? [Y/n]: " gh_reply
			case "${gh_reply:-Y}" in
				[Nn]*) do_gh_login=false ;;
				*)     do_gh_login=true ;;
			esac
		fi
		if $do_gh_login; then
			echo "Logging into GitHub..."
			# BROWSER=echo makes gh print the auth URL instead of trying to open a browser
			BROWSER=echo gh auth login
			if gh auth status &>/dev/null; then
				rm -f "$GH_SKIP_MARKER"
			else
				echo "GitHub CLI auth was not completed — skipping"
			fi
		else
			touch "$GH_SKIP_MARKER"
			echo "Skipping GitHub CLI sign-in (run 'gh auth login' later if you change your mind)"
		fi
	else
		echo "Skipping GitHub CLI auth (non-interactive)"
	fi
fi

# Shared infrastructure (needed by multiple sections)
mkdir -p /workspace/.squarebox ~/.local/bin

# Optional tools install the latest upstream release at setup time.
# Pinned versions live only in the Dockerfile tier (checksums.txt).
#
# SDKs are managed by mise (jdx/mise) — a single polyglot version manager
# replaces the previous per-language grab-bag (nvm, uv, Go tarball, .NET
# script, rustup). mise itself is installed in the Dockerfile tier and
# activated by ~/.bashrc. We write tool selections to ~/.config/mise/config.toml
# via `mise use -g`, which both registers the tool and triggers install.

# Make mise-installed binaries visible in *this* shell. dotfiles/bashrc
# already runs `mise activate bash`, but setup.sh on first launch may execute
# in an environment where mise wasn't yet on PATH (or the shims dir is empty
# and gets repopulated mid-script). Re-eval is cheap and idempotent.
_squarebox_mise_activate() {
	command -v mise >/dev/null 2>&1 || return 0
	eval "$(mise activate bash --shims)"
	export PATH="$HOME/.local/share/mise/shims:$PATH"
}

_install_mise_sdk_inner() {
	mise use -g "$1@latest" >/dev/null 2>&1
}

_install_mise_sdk() {
	local tool="$1" label="$2"
	if ! command -v mise >/dev/null 2>&1; then
		echo "Error: mise is not installed (expected at /usr/local/bin/mise)" >&2
		return 1
	fi
	if mise which "$tool" >/dev/null 2>&1; then
		echo "${label} already installed, skipping."
		return 0
	fi
	run_with_spinner "Installing ${label} (via mise)..." _install_mise_sdk_inner "$tool"
	_squarebox_mise_activate
	if ! mise which "$tool" >/dev/null 2>&1; then
		echo "Error: ${label} not available after mise install" >&2
		return 1
	fi
}

install_node()   { _install_mise_sdk node   "Node.js"; }
install_python() { _install_mise_sdk python "Python"; }
install_go()     { _install_mise_sdk go     "Go"; }
install_dotnet() { _install_mise_sdk dotnet ".NET"; }
install_rust()   { _install_mise_sdk rust   "Rust"; }

# Ensure Node.js is available for npm-based AI tools
ensure_node_for_npm() {
	_squarebox_mise_activate
	if command -v node &>/dev/null; then return 0; fi
	install_node
	_squarebox_mise_activate
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

# AI coding assistant
if should_run ai; then
AI_CONFIG="/workspace/.squarebox/ai-tool"

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
				pi)       gum_selected="${gum_selected:+$gum_selected,}Pi Coding Agent" ;;
				paseo)    gum_selected="${gum_selected:+$gum_selected,}Paseo" ;;
			esac
		done
		gum_args=(--no-limit --header "Select AI coding assistants (space=toggle, enter=confirm):")
		[ -n "$gum_selected" ] && gum_args+=(--selected "$gum_selected")
		selected=$(gum choose "${gum_args[@]}" \
			"Claude Code" "GitHub Copilot CLI" "Google Gemini CLI" \
			"OpenAI Codex CLI" "OpenCode" "Pi Coding Agent" "Paseo") || true
		ai_choice=""
		while IFS= read -r line; do
			case "$line" in
				"Claude Code")        ai_choice="${ai_choice:+$ai_choice,}claude" ;;
				"GitHub Copilot CLI") ai_choice="${ai_choice:+$ai_choice,}copilot" ;;
				"Google Gemini CLI")  ai_choice="${ai_choice:+$ai_choice,}gemini" ;;
				"OpenAI Codex CLI")   ai_choice="${ai_choice:+$ai_choice,}codex" ;;
				"OpenCode")           ai_choice="${ai_choice:+$ai_choice,}opencode" ;;
				"Pi Coding Agent")    ai_choice="${ai_choice:+$ai_choice,}pi" ;;
				"Paseo")              ai_choice="${ai_choice:+$ai_choice,}paseo" ;;
			esac
		done <<< "$selected"
	else
		echo "Select AI coding assistants (comma-separated, 'all', or press Enter to skip):"
		for ai_item in "1:claude:Claude Code" "2:copilot:GitHub Copilot CLI" "3:gemini:Google Gemini CLI" "4:codex:OpenAI Codex CLI" "5:opencode:OpenCode" "6:pi:Pi Coding Agent" "7:paseo:Paseo"; do
			num="${ai_item%%:*}"; rest="${ai_item#*:}"; key="${rest%%:*}"; label="${rest#*:}"
			if [[ ",$ai_prev," == *",${key},"* ]]; then
				echo "  ${num}) ${label} [installed]"
			else
				echo "  ${num}) ${label}"
			fi
		done
		read -rp "Selection [1-7/all/skip]: " ai_selection
		if [ -z "$ai_selection" ] && [ -n "$ai_prev" ]; then
			ai_choice="$ai_prev"
		else
			ai_choice=""
			if [ "$ai_selection" = "all" ]; then
				ai_choice="claude,copilot,gemini,codex,opencode,pi,paseo"
			elif [ -n "$ai_selection" ]; then
				for item in $(echo "$ai_selection" | tr ',' ' '); do
					case "$item" in
						1) ai_choice="${ai_choice:+$ai_choice,}claude" ;;
						2) ai_choice="${ai_choice:+$ai_choice,}copilot" ;;
						3) ai_choice="${ai_choice:+$ai_choice,}gemini" ;;
						4) ai_choice="${ai_choice:+$ai_choice,}codex" ;;
						5) ai_choice="${ai_choice:+$ai_choice,}opencode" ;;
						6) ai_choice="${ai_choice:+$ai_choice,}pi" ;;
					7) ai_choice="${ai_choice:+$ai_choice,}paseo" ;;
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

install_pi() {
	if command -v pi &>/dev/null; then echo "Pi Coding Agent already installed, skipping."; return 0; fi
	ensure_node_for_npm
	# --ignore-scripts is the upstream-recommended install flag (see pi.dev).
	run_with_spinner "Installing Pi Coding Agent..." npm install -g --silent --ignore-scripts @earendil-works/pi-coding-agent
}

install_paseo() {
	if command -v paseo &>/dev/null; then echo "Paseo already installed, skipping."; return 0; fi
	ensure_node_for_npm
	run_with_spinner "Installing Paseo..." npm install -g --silent @getpaseo/cli
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
				run_with_spinner "Installing OpenCode..." sb_install opencode latest \
					|| echo "Warning: OpenCode installation failed."
			fi
			;;
		copilot)  install_copilot || echo "Warning: GitHub Copilot CLI installation failed." ;;
		gemini)   install_gemini || echo "Warning: Google Gemini CLI installation failed." ;;
		codex)    install_codex || echo "Warning: OpenAI Codex CLI installation failed." ;;
		pi)       install_pi || echo "Warning: Pi Coding Agent installation failed." ;;
		paseo)    install_paseo || echo "Warning: Paseo installation failed." ;;
	esac
done

# Set aliases based on selection — c maps to first selected tool in priority order
{
	c_target=""
	for ai_tool in claude copilot gemini codex opencode pi paseo; do
		if [[ ",$ai_choice," == *",$ai_tool,"* ]]; then
			[ -z "$c_target" ] && c_target="$ai_tool"
			case "$ai_tool" in
				claude)   echo "alias claude-yolo='claude --dangerously-skip-permissions'" ;;
				opencode) echo "alias opencode-yolo='opencode --dangerously-skip-permissions'" ;;
			esac
		fi
	done
	if [ -n "$c_target" ]; then
		case "$c_target" in
			copilot) echo "alias c='github-copilot-cli'" ;;
			*)       echo "alias c='$c_target'" ;;
		esac
	fi
} > ~/.squarebox-ai-aliases
fi # should_run ai

# Text editors
if should_run editors; then
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

# LazyVim starter — offered when Neovim is among the selected editors
LAZYVIM_CONFIG="/workspace/.squarebox/nvim-lazyvim"
lazyvim_prev=""
[ -f "$LAZYVIM_CONFIG" ] && lazyvim_prev=$(cat "$LAZYVIM_CONFIG")
lazyvim_choice=false
if [[ ",$editor_list," == *",nvim,"* ]]; then
	if $INTERACTIVE; then
		lv_default=true
		[ "$lazyvim_prev" = "false" ] && lv_default=false
		echo
		echo "LazyVim turns Neovim into a preconfigured IDE (needs a Nerd Font in your terminal for icons)."
		if $HAS_GUM; then
			gum confirm "Install the LazyVim starter config for Neovim?" --default="$lv_default" && lazyvim_choice=true || lazyvim_choice=false
		else
			if $lv_default; then _lv_hint="Y/n"; else _lv_hint="y/N"; fi
			read -rp "Install the LazyVim starter config for Neovim? [$_lv_hint]: " _lv_reply
			if [ -z "$_lv_reply" ]; then
				lazyvim_choice=$lv_default
			else
				case "$_lv_reply" in [Yy]*) lazyvim_choice=true ;; *) lazyvim_choice=false ;; esac
			fi
		fi
		echo "$lazyvim_choice" > "$LAZYVIM_CONFIG"
	elif [ -n "$lazyvim_prev" ]; then
		lazyvim_choice="$lazyvim_prev"
	fi
fi

install_micro() {
	if command -v micro &>/dev/null; then echo "Micro already installed, skipping."; return 0; fi
	run_with_spinner "Installing Micro..." sb_install micro latest
}

install_edit() {
	if command -v edit &>/dev/null; then echo "Edit already installed, skipping."; return 0; fi
	run_with_spinner "Installing Edit..." sb_install edit latest
}

install_fresh() {
	if command -v fresh &>/dev/null; then echo "Fresh already installed, skipping."; return 0; fi
	run_with_spinner "Installing Fresh..." sb_install fresh latest
}

install_nvim() {
	if command -v nvim &>/dev/null; then echo "Neovim already installed, skipping."; return 0; fi
	run_with_spinner "Installing Neovim..." sb_install nvim latest
}

install_lazyvim() {
	if [ -e ~/.config/nvim ]; then
		echo "~/.config/nvim already exists, skipping LazyVim starter clone."
		return 0
	fi
	run_with_spinner "Installing LazyVim starter..." _install_lazyvim_inner
}

_install_lazyvim_inner() {
	# nvim-treesitter compiles parsers on first launch, which needs a C compiler
	if ! command -v cc &>/dev/null && ! command -v gcc &>/dev/null; then
		apt_install build-essential || return 1
	fi
	git clone --depth 1 https://github.com/LazyVim/starter ~/.config/nvim >/dev/null 2>&1 || return 1
	rm -rf ~/.config/nvim/.git
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

# Bootstrap LazyVim starter config when chosen and Neovim is available
if [ "$lazyvim_choice" = "true" ] && command -v nvim &>/dev/null; then
	install_lazyvim || echo "Warning: LazyVim starter setup failed."
fi

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
fi # should_run editors

# TUI tools
if should_run tuis; then
TUI_CONFIG="/workspace/.squarebox/tuis"

tui_prev=""
if [ -f "$TUI_CONFIG" ]; then
	tui_prev=$(cat "$TUI_CONFIG")
fi

if $INTERACTIVE; then
	echo
	section_header "TUI Tools"
	if $HAS_GUM; then
		# Build --selected from previously saved TUI tools
		gum_selected=""
		for tui in $(echo "$tui_prev" | tr ',' ' '); do
			case "$tui" in
				lazygit) gum_selected="${gum_selected:+$gum_selected,}lazygit" ;;
				gh-dash) gum_selected="${gum_selected:+$gum_selected,}gh-dash" ;;
				yazi)    gum_selected="${gum_selected:+$gum_selected,}yazi" ;;
			esac
		done
		gum_args=(--no-limit --header "Select TUI tools to install:")
		[ -n "$gum_selected" ] && gum_args+=(--selected "$gum_selected")
		selected=$(gum choose "${gum_args[@]}" \
			"lazygit" "gh-dash" "yazi") || true
		tui_list=""
		while IFS= read -r line; do
			[ -z "$line" ] && continue
			tui_list="${tui_list:+$tui_list,}${line}"
		done <<< "$selected"
	else
		echo "Select TUI tools to install (comma-separated, or 'all', or press Enter to skip):"
		for tui_item in "1:lazygit:git terminal UI" "2:gh-dash:GitHub dashboard for the terminal" "3:yazi:terminal file manager"; do
			num="${tui_item%%:*}"; rest="${tui_item#*:}"; key="${rest%%:*}"; desc="${rest#*:}"
			if [[ ",$tui_prev," == *",${key},"* ]]; then
				echo "  ${num}) ${key} — ${desc} [installed]"
			else
				echo "  ${num}) ${key} — ${desc}"
			fi
		done
		read -rp "Selection [1,2,3/all/skip]: " tui_selection
		if [ -z "$tui_selection" ] && [ -n "$tui_prev" ]; then
			tui_list="$tui_prev"
		else
			tui_list=""
			if [ "$tui_selection" = "all" ]; then
				tui_list="lazygit,gh-dash,yazi"
			elif [ -n "$tui_selection" ]; then
				for item in $(echo "$tui_selection" | tr ',' ' '); do
					case "$item" in
						1) tui_list="${tui_list:+$tui_list,}lazygit" ;;
						2) tui_list="${tui_list:+$tui_list,}gh-dash" ;;
						3) tui_list="${tui_list:+$tui_list,}yazi" ;;
					esac
				done
			fi
		fi
	fi
	echo "$tui_list" > "$TUI_CONFIG"
elif [ -n "$tui_prev" ]; then
	tui_list="$tui_prev"
	[ -n "$tui_list" ] && echo "Installing TUI tools: $tui_list (from previous selection)"
else
	echo "Skipping TUI tool selection (non-interactive)"
	tui_list=""
	echo "$tui_list" > "$TUI_CONFIG"
fi

install_lazygit() {
	if command -v lazygit &>/dev/null; then echo "Lazygit already installed, skipping."; return 0; fi
	run_with_spinner "Installing Lazygit..." sb_install lazygit latest
	# Install default lazygit config if missing
	if [ ! -f ~/.config/lazygit/config.yml ]; then
		mkdir -p ~/.config/lazygit
		printf 'git:\n  paging:\n    colorArg: always\n    pager: delta --dark --paging=never\n' > ~/.config/lazygit/config.yml
	fi
}

install_gh_dash() {
	if command -v gh-dash &>/dev/null; then echo "gh-dash already installed, skipping."; return 0; fi
	run_with_spinner "Installing gh-dash..." sb_install gh-dash latest
}

install_yazi() {
	if command -v yazi &>/dev/null; then echo "Yazi already installed, skipping."; return 0; fi
	run_with_spinner "Installing Yazi..." sb_install yazi latest
}

installed_tuis=()
for tui in $(echo "$tui_list" | tr ',' ' '); do
	case "$tui" in
		lazygit) install_lazygit && installed_tuis+=("lazygit") || echo "Warning: Lazygit installation failed." ;;
		gh-dash) install_gh_dash && installed_tuis+=("gh-dash") || echo "Warning: gh-dash installation failed." ;;
		yazi)    install_yazi    && installed_tuis+=("yazi")    || echo "Warning: Yazi installation failed." ;;
	esac
done

# Set TUI aliases (lg for lazygit) only when installed
{
	for tui in "${installed_tuis[@]}"; do
		case "$tui" in
			lazygit) echo "alias lg='lazygit'" ;;
		esac
	done
} > ~/.squarebox-tui-aliases
fi # should_run tuis

# Terminal multiplexer
if should_run multiplexers; then
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
	apt_install tmux || return 1
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

# Self-heal tmux settings that older configs may predate. The config heredoc in
# _install_tmux_inner only runs when no tmux.conf exists, so upgraded containers
# never picked up newly-added defaults (e.g. `set -g mouse on`, needed for scroll
# to work in Blink/mobile terminals instead of leaking mouse escapes to the prompt).
_ensure_tmux_defaults() {
	local conf="$HOME/.config/tmux/tmux.conf"
	[ -f "$conf" ] || return 0
	grep -q '^set -g mouse on' "$conf" || echo 'set -g mouse on' >> "$conf"
}

install_tmux() {
	if command -v tmux &>/dev/null; then echo "Tmux already installed, skipping."; _ensure_tmux_defaults; return 0; fi
	run_with_spinner "Installing tmux..." _install_tmux_inner
	_ensure_tmux_defaults
}

_install_zellij_inner() {
	sb_install zellij latest
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
		// "detach" not "quit" — a dropped client (ssh/mosh dying) must not kill
		// the session and everything running in it
		on_force_close "detach"
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

		        // Keybinding help — floating configuration plugin
		        bind "?" { LaunchOrFocusPlugin "configuration" { floating true; }; SwitchToMode "Normal"; }
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

_ensure_zellij_defaults() {
	local conf="$HOME/.config/zellij/config.kdl"
	[ -f "$conf" ] || return 0
	sed -i 's/^on_force_close "quit"/on_force_close "detach"/' "$conf"
	if ! grep -q 'bind "?"' "$conf"; then
		sed -i '/bind "\[" { SwitchToMode "Scroll"; }/a\        bind "?" { LaunchOrFocusPlugin "configuration" { floating true; }; SwitchToMode "Normal"; }' "$conf"
	fi
}

install_zellij() {
	if command -v zellij &>/dev/null; then echo "Zellij already installed, skipping."; _ensure_zellij_defaults; return 0; fi
	run_with_spinner "Installing Zellij..." _install_zellij_inner
	_ensure_zellij_defaults
}

for mux in $(echo "$mux_list" | tr ',' ' '); do
	case "$mux" in
		tmux) install_tmux || echo "Warning: tmux installation failed." ;;
		zellij) install_zellij || echo "Warning: Zellij installation failed." ;;
	esac
done
fi # should_run multiplexers

# SDKs
if should_run sdks; then
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
				rust)   gum_selected="${gum_selected:+$gum_selected,}Rust" ;;
			esac
		done
		gum_args=(--no-limit --header "Select SDKs to install:")
		[ -n "$gum_selected" ] && gum_args+=(--selected "$gum_selected")
		selected=$(gum choose "${gum_args[@]}" \
			"Node.js" "Python" "Go" ".NET" "Rust") || true
		sdk_list=""
		while IFS= read -r line; do
			case "$line" in
				"Node.js") sdk_list="${sdk_list:+$sdk_list,}node" ;;
				"Python")  sdk_list="${sdk_list:+$sdk_list,}python" ;;
				"Go")      sdk_list="${sdk_list:+$sdk_list,}go" ;;
				".NET")    sdk_list="${sdk_list:+$sdk_list,}dotnet" ;;
				"Rust")    sdk_list="${sdk_list:+$sdk_list,}rust" ;;
			esac
		done <<< "$selected"
		# Empty gum output means nothing selected
		[ -z "$selected" ] && sdk_list=""
	else
		echo "Select SDKs to install (comma-separated, 'all', or 'none' to skip):"
		for sdk_item in "1:node:Node.js" "2:python:Python" "3:go:Go" "4:dotnet:.NET" "5:rust:Rust"; do
			num="${sdk_item%%:*}"; rest="${sdk_item#*:}"; key="${rest%%:*}"; label="${rest#*:}"
			if [[ ",$sdk_prev," == *",${key},"* ]]; then
				echo "  ${num}) ${label} [installed]"
			else
				echo "  ${num}) ${label}"
			fi
		done
		read -rp "Selection [1,2,3,4,5/all/none]: " sdk_selection
		if [ -z "$sdk_selection" ] && [ -n "$sdk_prev" ]; then
			sdk_list="$sdk_prev"
		else
			sdk_list=""
			if [ "$sdk_selection" = "all" ]; then
				sdk_list="node,python,go,dotnet,rust"
			elif [ "$sdk_selection" != "none" ] && [ -n "$sdk_selection" ]; then
				for item in $(echo "$sdk_selection" | tr ',' ' '); do
					case "$item" in
						1) sdk_list="${sdk_list:+$sdk_list,}node" ;;
						2) sdk_list="${sdk_list:+$sdk_list,}python" ;;
						3) sdk_list="${sdk_list:+$sdk_list,}go" ;;
						4) sdk_list="${sdk_list:+$sdk_list,}dotnet" ;;
						5) sdk_list="${sdk_list:+$sdk_list,}rust" ;;
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

# All SDK installers (install_node/python/go/dotnet/rust) are defined earlier
# in setup.sh and delegate to mise via _install_mise_sdk.

for sdk in $(echo "$sdk_list" | tr ',' ' '); do
	case "$sdk" in
		node)   install_node   || echo "Warning: Node.js installation failed." ;;
		python) install_python || echo "Warning: Python installation failed." ;;
		go)     install_go     || echo "Warning: Go installation failed." ;;
		dotnet) install_dotnet || echo "Warning: .NET installation failed." ;;
		rust)   install_rust   || echo "Warning: Rust installation failed." ;;
	esac
done
fi # should_run sdks

# Shell (experimental) — offer Zsh + Oh My Zsh or Fish as alternatives to Bash
if should_run shell; then
SHELL_CONFIG="/workspace/.squarebox/shell"

shell_prev=""
if [ -f "$SHELL_CONFIG" ]; then
	shell_prev=$(cat "$SHELL_CONFIG")
fi

if $INTERACTIVE; then
	echo
	section_header "Shell"
	if $HAS_GUM; then
		gum_selected=""
		case "$shell_prev" in
			zsh)  gum_selected="zsh (experimental)" ;;
			fish) gum_selected="fish (experimental)" ;;
			bash) gum_selected="bash" ;;
		esac
		gum_args=(--header "Select default shell:")
		[ -n "$gum_selected" ] && gum_args+=(--selected "$gum_selected")
		shell_pick=$(gum choose "${gum_args[@]}" "bash" "zsh (experimental)" "fish (experimental)") || shell_pick=""
		case "$shell_pick" in
			"zsh (experimental)")  shell_choice="zsh" ;;
			"fish (experimental)") shell_choice="fish" ;;
			"bash")                shell_choice="bash" ;;
			*)                     shell_choice="$shell_prev" ;;
		esac
	else
		echo "Select default shell:"
		for sh_item in \
			"1:bash:GNU Bash (default)" \
			"2:zsh:Zsh + Oh My Zsh + autosuggestions + syntax highlighting (experimental)" \
			"3:fish:Fish shell with built-in autosuggestions and syntax highlighting (experimental)"; do
			num="${sh_item%%:*}"; rest="${sh_item#*:}"; key="${rest%%:*}"; desc="${rest#*:}"
			if [ "$key" = "$shell_prev" ]; then
				echo "  ${num}) ${key} — ${desc} [current]"
			else
				echo "  ${num}) ${key} — ${desc}"
			fi
		done
		read -rp "Selection [1,2,3/skip]: " shell_selection
		if [ -z "$shell_selection" ] && [ -n "$shell_prev" ]; then
			shell_choice="$shell_prev"
		else
			case "$shell_selection" in
				1) shell_choice="bash" ;;
				2) shell_choice="zsh" ;;
				3) shell_choice="fish" ;;
				*) shell_choice="${shell_prev:-bash}" ;;
			esac
		fi
	fi
	[ -z "$shell_choice" ] && shell_choice="bash"
	echo "$shell_choice" > "$SHELL_CONFIG"
elif [ -n "$shell_prev" ]; then
	shell_choice="$shell_prev"
	case "$shell_choice" in
		zsh)  echo "Configuring shell: zsh (from previous selection)" ;;
		fish) echo "Configuring shell: fish (from previous selection)" ;;
	esac
else
	shell_choice="bash"
	echo "$shell_choice" > "$SHELL_CONFIG"
fi

_install_zsh_inner() {
	apt_install zsh || return 1
	command -v zsh >/dev/null 2>&1 || return 1
	# Trust boundary: the Oh My Zsh installer manages its own files via HTTPS.
	# We resolve the latest release tag at setup time (matching the trust model
	# used elsewhere in setup.sh for optional tools) instead of tracking master,
	# so the fetched installer is pinned to a known release rather than a
	# moving branch. RUNZSH=no prevents launching a subshell, CHSH=no skips the
	# chsh prompt (we handle shell switching via the .squarebox-use-zsh
	# marker), and KEEP_ZSHRC=yes prevents it from writing a .zshrc we'd
	# immediately overwrite.
	if [ ! -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]; then
		local omz_tag omz_ref
		omz_tag=$(sb_gh_latest_tag ohmyzsh/ohmyzsh 2>/dev/null || true)
		omz_ref="${omz_tag:-master}"
		RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
			sh -c "$(curl -fsSL "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/${omz_ref}/tools/install.sh")" "" --unattended >/dev/null 2>&1 || return 1
	fi
	[ -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ] || return 1
	local custom="$HOME/.oh-my-zsh/custom"
	if [ ! -d "$custom/plugins/zsh-autosuggestions" ]; then
		git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions \
			"$custom/plugins/zsh-autosuggestions" >/dev/null 2>&1 || return 1
	fi
	if [ ! -d "$custom/plugins/zsh-syntax-highlighting" ]; then
		git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting \
			"$custom/plugins/zsh-syntax-highlighting" >/dev/null 2>&1 || return 1
	fi
	[ -d "$custom/plugins/zsh-autosuggestions" ] || return 1
	[ -d "$custom/plugins/zsh-syntax-highlighting" ] || return 1
	# Generate ~/.zshrc that mirrors ~/.bashrc, layered on Oh My Zsh.
	cat > "$HOME/.zshrc" <<-'ZSHRC' || return 1
		# squarebox zsh config (experimental) — mirrors ~/.bashrc
		export ZSH="$HOME/.oh-my-zsh"
		ZSH_THEME=""
		plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
		[ -f "$ZSH/oh-my-zsh.sh" ] && source "$ZSH/oh-my-zsh.sh"

		eval "$(starship init zsh)"
		eval "$(zoxide init zsh)"
		alias ls='eza --icons'
		alias ll='eza -la --icons'
		alias lsa='ls -a'
		alias lt='eza --tree --level=2 --long --icons --git'
		alias lta='lt -a'
		alias cat='bat --paging=never'
		alias ff="fzf --preview 'bat --style=numbers --color=always {}'"
		alias eff='$EDITOR "$(ff)"'
		alias ..='cd ..'
		alias ...='cd ../..'
		alias ....='cd ../../..'
		export EDITOR='nano'
		[ -f ~/.squarebox-ai-aliases ] && source ~/.squarebox-ai-aliases
		[ -f ~/.squarebox-editor-aliases ] && source ~/.squarebox-editor-aliases
		[ -f ~/.squarebox-tui-aliases ] && source ~/.squarebox-tui-aliases
		command -v mise >/dev/null 2>&1 && eval "$(mise activate zsh)"
		alias g='git'
		alias gcm='git commit -m'
		alias gcam='git commit -a -m'
		alias gcad='git commit -a --amend'
		export PATH="$HOME/.local/bin:$PATH"
		[ -x /usr/local/lib/squarebox/motd.sh ] && /usr/local/lib/squarebox/motd.sh
	ZSHRC
	[ -f "$HOME/.zshrc" ] || return 1
}

install_zsh() {
	# Always invoke the inner installer: each step is idempotent (guards with
	# `-d` / `-f` before apt/curl/clone), and running it every time ensures any
	# missing plugins from a previous partial install get re-cloned.
	run_with_spinner "Installing Zsh + Oh My Zsh..." _install_zsh_inner
}

# Translate one bash-syntax line from a ~/.squarebox-* alias file into its
# fish equivalent on stdout. Handles:
#   export PATH="A:B:$PATH"          → set -x PATH A B $PATH
#   export NAME='value'              → set -x NAME value
#   alias name='cmd'                 → passed through (fish accepts this form)
# Other constructs are dropped. SDK PATHs are now handled by `mise activate
# fish` directly — this translator is only used for AI/editor/TUI aliases.
_squarebox_bash_line_to_fish() {
	local line="$1"
	case "$line" in
		"export PATH="*)
			local val="${line#export PATH=}"
			val="${val#\"}"; val="${val%\"}"
			val="${val#\'}"; val="${val%\'}"
			echo "set -x PATH ${val//:/ }"
			;;
		"export "*=*)
			local rest="${line#export }"
			local name="${rest%%=*}"
			local val="${rest#*=}"
			val="${val#\"}"; val="${val%\"}"
			val="${val#\'}"; val="${val%\'}"
			echo "set -x $name $val"
			;;
		"alias "*=*)
			echo "$line"
			;;
	esac
}

_install_fish_inner() {
	apt_install fish || return 1
	command -v fish >/dev/null 2>&1 || return 1
	mkdir -p "$HOME/.config/fish/conf.d" || return 1
	# Generate ~/.config/fish/config.fish mirroring the default bashrc in
	# fish-native syntax. Fish has built-in autosuggestions and syntax
	# highlighting, so no plugins are needed.
	cat > "$HOME/.config/fish/config.fish" <<-'FISHRC' || return 1
		# squarebox fish config (experimental) — mirrors ~/.bashrc
		# Use `return` (not `exit`) so non-interactive invocations like
		# `fish -c '…'` skip this config without terminating the shell.
		status is-interactive; or return

		starship init fish | source
		zoxide init fish | source

		alias ls='eza --icons'
		alias ll='eza -la --icons'
		alias lsa='ls -a'
		alias lt='eza --tree --level=2 --long --icons --git'
		alias lta='lt -a'
		alias cat='bat --paging=never'
		alias ff="fzf --preview 'bat --style=numbers --color=always {}'"
		alias eff='$EDITOR (ff)'
		alias ..='cd ..'
		alias ...='cd ../..'
		alias ....='cd ../../..'
		alias g='git'
		alias gcm='git commit -m'
		alias gcam='git commit -a -m'
		alias gcad='git commit -a --amend'

		set -x EDITOR nano
		fish_add_path -g $HOME/.local/bin

		# mise (SDK manager) wires PATH and shims for whatever the user
		# selected during setup. Safe to run unconditionally — fish-native.
		command -v mise >/dev/null 2>&1; and mise activate fish | source

		# User AI/editor/TUI selections translated from bash files at install time.
		test -f $HOME/.config/fish/conf.d/squarebox-selections.fish
			and source $HOME/.config/fish/conf.d/squarebox-selections.fish

		test -x /usr/local/lib/squarebox/motd.sh; and /usr/local/lib/squarebox/motd.sh
	FISHRC
	[ -f "$HOME/.config/fish/config.fish" ] || return 1

	# Translate AI/editor/TUI bash-syntax files into a single fish conf.d
	# snippet. Regenerated each install to reflect current selections.
	# (SDK paths are no longer translated — mise handles that natively.)
	local sel_out="$HOME/.config/fish/conf.d/squarebox-selections.fish"
	{
		echo "# Generated by setup.sh from ~/.squarebox-* bash files."
		for src in \
			"$HOME/.squarebox-ai-aliases" \
			"$HOME/.squarebox-editor-aliases" \
			"$HOME/.squarebox-tui-aliases"; do
			[ -f "$src" ] || continue
			echo "# --- from $(basename "$src") ---"
			while IFS= read -r _sq_line; do
				_squarebox_bash_line_to_fish "$_sq_line"
			done < "$src"
		done
	} > "$sel_out" || return 1
}

install_fish() {
	run_with_spinner "Installing Fish..." _install_fish_inner
}

case "$shell_choice" in
	zsh)
		if install_zsh; then
			touch ~/.squarebox-use-zsh
			rm -f ~/.squarebox-use-fish
			echo "Zsh will take over at the end of this setup (next interactive shell)."
		else
			echo "Warning: Zsh installation failed; staying on bash."
			rm -f ~/.squarebox-use-zsh ~/.squarebox-use-fish
		fi
		;;
	fish)
		if install_fish; then
			touch ~/.squarebox-use-fish
			rm -f ~/.squarebox-use-zsh
			echo "Fish will take over at the end of this setup (next interactive shell)."
		else
			echo "Warning: Fish installation failed; staying on bash."
			rm -f ~/.squarebox-use-zsh ~/.squarebox-use-fish
		fi
		;;
	bash|*)
		rm -f ~/.squarebox-use-zsh ~/.squarebox-use-fish
		;;
esac
fi # should_run shell

# ── Learn mode ───────────────────────────────────────────────────────────────
if should_run learn; then

LEARN_CONFIG="/workspace/.squarebox/learn"

learn_prev=""
if [ -f "$LEARN_CONFIG" ]; then
	learn_prev=$(cat "$LEARN_CONFIG")
fi

if $INTERACTIVE; then
	echo
	if $HAS_GUM; then
		gum style --foreground 212 --bold "Learn Mode"
	else
		echo "── Learn Mode ──────────────────────────────────────────────────────────────"
	fi
	echo "sqrbx-learn is an interactive guide to the tools in your squarebox,"
	echo "covering their history and how to use them effectively. It can also"
	echo "launch your AI agent in a hands-on coach mode that teaches as you work."
	echo

	if $HAS_GUM; then
		gum_selected=""
		[ "$learn_prev" = "enabled" ] && gum_selected="Enable learn mode (sqrbx-learn)"
		gum_args=(--header "Enable learn mode?")
		[ -n "$gum_selected" ] && gum_args+=(--selected "$gum_selected")
		learn_pick=$(gum choose "${gum_args[@]}" \
			"Enable learn mode (sqrbx-learn)" \
			"Skip") || learn_pick=""
		case "$learn_pick" in
			"Enable"*) learn_choice="enabled" ;;
			*)         learn_choice="" ;;
		esac
	else
		if [ "$learn_prev" = "enabled" ]; then
			read -rp "Keep learn mode enabled? [Y/n]: " _lr
			case "${_lr:-Y}" in [Nn]*) learn_choice="" ;; *) learn_choice="enabled" ;; esac
		else
			read -rp "Enable learn mode (sqrbx-learn)? [y/N]: " _lr
			case "${_lr:-N}" in [Yy]*) learn_choice="enabled" ;; *) learn_choice="" ;; esac
		fi
	fi
else
	learn_choice="$learn_prev"
fi

mkdir -p "$(dirname "$LEARN_CONFIG")"
echo "$learn_choice" > "$LEARN_CONFIG"

fi # should_run learn

echo

if $HAS_GUM; then
	gum style --border double --padding "0 2" --border-foreground 208 "All boxed up 📦"
else
	echo "All boxed up 📦"
fi
