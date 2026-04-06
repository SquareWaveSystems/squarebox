#!/usr/bin/env bash
set -euo pipefail

# sqrbx-update — update SquareBox tools in-place from GitHub releases.
#
# Usage:
#   sqrbx-update              Show available updates (dry run)
#   sqrbx-update --apply      Download and install updates
#   sqrbx-update <tool>       Update a single tool
#   sqrbx-update --list       List all managed tools and versions
#   sqrbx-update --help       Show this help

INSTALL_DIR="/usr/local/bin"
mkdir -p "$HOME/.local/bin"

AUTH_HEADER=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
	AUTH_HEADER=(-H "Authorization: token ${GITHUB_TOKEN}")
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# Architecture detection (done once)
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ]; then
	ZARCH="aarch64"; LARCH="arm64"; GOARCH="arm64"; DPKG_ARCH="arm64"; OCARCH="arm64"
else
	ZARCH="x86_64"; LARCH="x86_64"; GOARCH="amd64"; DPKG_ARCH="amd64"; OCARCH="x64"
fi

# ── GitHub helpers ──────────────────────────────────────────────────

check_rate_limit() {
	local info remaining limit
	info=$(curl -fsSL "${AUTH_HEADER[@]}" "https://api.github.com/rate_limit" 2>/dev/null) || return 0
	remaining=$(echo "$info" | jq -r '.rate.remaining' 2>/dev/null) || return 0
	limit=$(echo "$info" | jq -r '.rate.limit' 2>/dev/null) || return 0
	if [[ "${remaining:-0}" =~ ^[0-9]+$ ]] && [ "$remaining" -lt 20 ]; then
		echo -e "${RED}Warning: Only ${remaining}/${limit} GitHub API requests remaining.${RESET}" >&2
		if [ -z "${GITHUB_TOKEN:-}" ]; then
			echo -e "${YELLOW}Set GITHUB_TOKEN to authenticate (5000 req/hr instead of 60).${RESET}" >&2
		fi
		echo >&2
	fi
}

gh_latest_tag() {
	local repo="$1"
	local response http_code body
	response=$(curl -fsSL -w '\n%{http_code}' "${AUTH_HEADER[@]}" \
		"https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null) || true
	http_code=$(echo "$response" | tail -1)
	body=$(echo "$response" | sed '$d')
	if [ "$http_code" = "403" ]; then
		echo "Error: GitHub API rate limit exceeded (${repo}). Set GITHUB_TOKEN to authenticate." >&2
		return 1
	elif [ "$http_code" != "200" ]; then
		echo "Error: GitHub API returned HTTP ${http_code} for ${repo}." >&2
		return 1
	fi
	echo "$body" | jq -r '.tag_name'
}

strip_v() { echo "${1#v}"; }

# ── Tool definitions ────────────────────────────────────────────────
# Each tool has: get_current_version, get_latest_version, do_install

# --- delta ---
delta_repo="dandavison/delta"
delta_current() { delta --version 2>/dev/null | awk '{print $2}' || echo "not installed"; }
delta_latest() { gh_latest_tag "$delta_repo"; }
delta_install() {
	local ver="$1"
	local tmp=$(mktemp -d)
	curl -fsSLo "$tmp/delta.deb" "https://github.com/${delta_repo}/releases/download/${ver}/git-delta_${ver}_${DPKG_ARCH}.deb"
	sudo dpkg -i "$tmp/delta.deb" 2>/dev/null || dpkg -i "$tmp/delta.deb"
	rm -rf "$tmp"
}

# --- yq ---
yq_repo="mikefarah/yq"
yq_current() { yq --version 2>/dev/null | grep -oP 'v[\d.]+' | head -1 | sed 's/^v//' || echo "not installed"; }
yq_latest() { strip_v "$(gh_latest_tag "$yq_repo")"; }
yq_install() {
	local ver="$1"
	curl -fsSLo "/tmp/yq" "https://github.com/${yq_repo}/releases/download/v${ver}/yq_linux_${DPKG_ARCH}"
	sudo install /tmp/yq "${INSTALL_DIR}/yq"
	rm -f /tmp/yq
}

# --- lazygit ---
lazygit_repo="jesseduffield/lazygit"
lazygit_current() { lazygit --version 2>/dev/null | grep -oP 'version=[\d.]+' | cut -d= -f2 || echo "not installed"; }
lazygit_latest() { strip_v "$(gh_latest_tag "$lazygit_repo")"; }
lazygit_install() {
	local ver="$1"
	local tmp=$(mktemp -d)
	curl -fsSLo "$tmp/lazygit.tar.gz" "https://github.com/${lazygit_repo}/releases/download/v${ver}/lazygit_${ver}_Linux_${LARCH}.tar.gz"
	tar xf "$tmp/lazygit.tar.gz" -C "$tmp" lazygit
	sudo install "$tmp/lazygit" "${INSTALL_DIR}/lazygit"
	rm -rf "$tmp"
}

# --- xh ---
xh_repo="ducaale/xh"
xh_current() { xh --version 2>/dev/null | head -1 | awk '{print $2}' || echo "not installed"; }
xh_latest() { strip_v "$(gh_latest_tag "$xh_repo")"; }
xh_install() {
	local ver="$1"
	local tmp=$(mktemp -d)
	curl -fsSLo "$tmp/xh.tar.gz" "https://github.com/${xh_repo}/releases/download/v${ver}/xh-v${ver}-${ZARCH}-unknown-linux-musl.tar.gz"
	tar xzf "$tmp/xh.tar.gz" --strip-components=1 -C "$tmp"
	sudo install "$tmp/xh" "${INSTALL_DIR}/xh"
	rm -rf "$tmp"
}

# --- yazi ---
yazi_repo="sxyazi/yazi"
yazi_current() { yazi --version 2>/dev/null | awk '{print $2}' || echo "not installed"; }
yazi_latest() { strip_v "$(gh_latest_tag "$yazi_repo")"; }
yazi_install() {
	local ver="$1"
	local tmp=$(mktemp -d)
	curl -fsSLo "$tmp/yazi.zip" "https://github.com/${yazi_repo}/releases/download/v${ver}/yazi-${ZARCH}-unknown-linux-musl.zip"
	unzip -q "$tmp/yazi.zip" -d "$tmp"
	sudo install "$tmp/yazi-${ZARCH}-unknown-linux-musl/yazi" "${INSTALL_DIR}/yazi"
	sudo install "$tmp/yazi-${ZARCH}-unknown-linux-musl/ya" "${INSTALL_DIR}/ya"
	rm -rf "$tmp"
}

# --- starship ---
starship_repo="starship/starship"
starship_current() { starship --version 2>/dev/null | awk '{print $2}' || echo "not installed"; }
starship_latest() { strip_v "$(gh_latest_tag "$starship_repo")"; }
starship_install() {
	local ver="$1"
	local tmp=$(mktemp -d)
	curl -fsSLo "$tmp/starship.tar.gz" "https://github.com/${starship_repo}/releases/download/v${ver}/starship-${ZARCH}-unknown-linux-musl.tar.gz"
	tar xf "$tmp/starship.tar.gz" -C "$tmp"
	sudo install "$tmp/starship" "${INSTALL_DIR}/starship"
	rm -rf "$tmp"
}

# --- gh-dash ---
ghdash_repo="dlvhdr/gh-dash"
ghdash_current() {
	local ver
	ver=$(gh-dash --version 2>/dev/null | grep -oP '[\d.]+' | head -1) || ver="not installed"
	echo "$ver"
}
ghdash_latest() { strip_v "$(gh_latest_tag "$ghdash_repo")"; }
ghdash_install() {
	local ver="$1"
	curl -fsSLo "/tmp/gh-dash" "https://github.com/${ghdash_repo}/releases/download/v${ver}/gh-dash_v${ver}_linux-${GOARCH}"
	sudo install /tmp/gh-dash "${INSTALL_DIR}/gh-dash"
	rm -f /tmp/gh-dash
}

# --- glow ---
glow_repo="charmbracelet/glow"
glow_current() { glow --version 2>/dev/null | grep -oP '[\d.]+' | head -1 || echo "not installed"; }
glow_latest() { strip_v "$(gh_latest_tag "$glow_repo")"; }
glow_install() {
	local ver="$1"
	local tmp=$(mktemp -d)
	curl -fsSLo "$tmp/glow.tar.gz" "https://github.com/${glow_repo}/releases/download/v${ver}/glow_${ver}_Linux_${LARCH}.tar.gz"
	tar xzf "$tmp/glow.tar.gz" -C "$tmp"
	find "$tmp" -name 'glow' -type f -executable -exec sudo install {} "${INSTALL_DIR}/glow" \;
	rm -rf "$tmp"
}

# --- micro (user-installed, in ~/.local/bin) ---
micro_repo="micro-editor/micro"
micro_current() { micro --version 2>/dev/null | head -1 | awk '{print $2}' || echo "not installed"; }
micro_latest() { strip_v "$(gh_latest_tag "$micro_repo")"; }
micro_install() {
	local ver="$1"
	local march; if [ "$ZARCH" = "aarch64" ]; then march="-arm64"; else march="64"; fi
	local tmp=$(mktemp -d)
	curl -fsSLo "$tmp/micro.tar.gz" "https://github.com/${micro_repo}/releases/download/v${ver}/micro-${ver}-linux${march}.tar.gz"
	tar xzf "$tmp/micro.tar.gz" --strip-components=1 -C "$tmp"
	install "$tmp/micro" "$HOME/.local/bin/micro"
	rm -rf "$tmp"
}

# --- fresh (user-installed, in ~/.local/bin) ---
fresh_repo="sinelaw/fresh"
fresh_current() { fresh --version 2>/dev/null | grep -oP '[\d.]+' | head -1 || echo "not installed"; }
fresh_latest() { strip_v "$(gh_latest_tag "$fresh_repo")"; }
fresh_install() {
	local ver="$1"
	local tmp=$(mktemp -d)
	curl -fsSLo "$tmp/fresh.tar.gz" "https://github.com/${fresh_repo}/releases/download/v${ver}/fresh-editor-${ZARCH}-unknown-linux-musl.tar.gz"
	tar xf "$tmp/fresh.tar.gz" -C "$tmp"
	find "$tmp" -name 'fresh' -type f -executable -exec install {} "$HOME/.local/bin/fresh" \;
	rm -rf "$tmp"
}

# --- edit (user-installed, in ~/.local/bin) ---
edit_repo="microsoft/edit"
edit_current() { edit --version 2>/dev/null | grep -oP '[\d.]+' | head -1 || echo "not installed"; }
edit_latest() { strip_v "$(gh_latest_tag "$edit_repo")"; }
edit_install() {
	local ver="$1"
	# Edit has a quirk: asset version may differ from tag version. Query the actual asset name.
	local asset_name
	local api_response
	api_response=$(curl -fsSL -w '\n%{http_code}' "${AUTH_HEADER[@]}" \
		"https://api.github.com/repos/${edit_repo}/releases/latest" 2>/dev/null) || true
	local api_code
	api_code=$(echo "$api_response" | tail -1)
	if [ "$api_code" = "403" ]; then
		echo "  GitHub API rate limit exceeded. Set GITHUB_TOKEN to authenticate." >&2
		return 1
	elif [ "$api_code" != "200" ]; then
		echo "  GitHub API returned HTTP ${api_code} for ${edit_repo}." >&2
		return 1
	fi
	asset_name=$(echo "$api_response" | sed '$d' | jq -r '.assets[].name' | grep "${ZARCH}-linux-gnu" | head -1)
	if [ -z "$asset_name" ]; then
		echo "  Could not find edit asset for ${ZARCH}" >&2
		return 1
	fi
	local tmp=$(mktemp -d)
	curl -fsSLo "$tmp/edit.tar.zst" "https://github.com/${edit_repo}/releases/download/v${ver}/${asset_name}"
	# Check if zstd is available; install temporarily if not
	if ! command -v zstd &>/dev/null; then
		echo "  Installing zstd (needed for edit)..."
		sudo apt-get update -qq && sudo apt-get install -y -qq zstd
		local CLEANUP_ZSTD=1
	fi
	zstd -d "$tmp/edit.tar.zst" -o "$tmp/edit.tar"
	tar xf "$tmp/edit.tar" -C "$tmp"
	find "$tmp" -name 'edit' -type f -executable -exec install {} "$HOME/.local/bin/edit" \;
	rm -rf "$tmp"
	if [ "${CLEANUP_ZSTD:-}" = "1" ]; then
		sudo apt-get purge -y -qq --auto-remove zstd
	fi
}

# --- helix (user-installed, in ~/.local/bin) ---
helix_repo="helix-editor/helix"
helix_current() { hx --version 2>/dev/null | awk '{print $2}' || echo "not installed"; }
helix_latest() { gh_latest_tag "$helix_repo"; }
helix_install() {
	local ver="$1"
	local tmp=$(mktemp -d)
	if ! command -v xz &>/dev/null; then
		sudo apt-get update -qq && sudo apt-get install -y -qq xz-utils >/dev/null 2>&1
	fi
	curl -fsSLo "$tmp/helix.tar.xz" "https://github.com/${helix_repo}/releases/download/${ver}/helix-${ver}-${ZARCH}-linux.tar.xz"
	tar xJf "$tmp/helix.tar.xz" -C "$tmp"
	install "$tmp/helix-${ver}-${ZARCH}-linux/hx" "$HOME/.local/bin/hx"
	mkdir -p "$HOME/.config/helix"
	rm -rf "$HOME/.config/helix/runtime"
	mv "$tmp/helix-${ver}-${ZARCH}-linux/runtime" "$HOME/.config/helix/runtime"
	rm -rf "$tmp"
}

# --- nvim (user-installed, in ~/.local) ---
nvim_repo="neovim/neovim"
nvim_current() { nvim --version 2>/dev/null | head -1 | awk '{print $2}' | sed 's/^v//' || echo "not installed"; }
nvim_latest() { strip_v "$(gh_latest_tag "$nvim_repo")"; }
nvim_install() {
	local ver="$1"
	local narch; if [ "$ZARCH" = "aarch64" ]; then narch="arm64"; else narch="x86_64"; fi
	local tmp=$(mktemp -d)
	curl -fsSLo "$tmp/nvim.tar.gz" "https://github.com/${nvim_repo}/releases/download/v${ver}/nvim-linux-${narch}.tar.gz"
	tar xzf "$tmp/nvim.tar.gz" -C "$tmp"
	rm -rf "$HOME/.local/nvim"
	mv "$tmp/nvim-linux-${narch}" "$HOME/.local/nvim"
	ln -sf "$HOME/.local/nvim/bin/nvim" "$HOME/.local/bin/nvim"
	rm -rf "$tmp"
}

# --- opencode (user-installed, in ~/.local/bin) ---
opencode_repo="anomalyco/opencode"
opencode_current() { opencode --version 2>/dev/null | grep -oP '[\d.]+' | head -1 || echo "not installed"; }
opencode_latest() { strip_v "$(gh_latest_tag "$opencode_repo")"; }
opencode_install() {
	local ver="$1"
	local tmp=$(mktemp -d)
	curl -fsSLo "$tmp/opencode.tar.gz" "https://github.com/${opencode_repo}/releases/download/v${ver}/opencode-linux-${OCARCH}.tar.gz"
	tar xzf "$tmp/opencode.tar.gz" -C "$tmp"
	find "$tmp" -name 'opencode' -type f -executable -exec install {} "$HOME/.local/bin/opencode" \;
	rm -rf "$tmp"
}

# ── Tool registry ──────────────────────────────────────────────────

TOOLS=(delta yq lazygit xh yazi starship ghdash glow micro fresh edit helix nvim opencode)
TOOL_DISPLAY_NAMES=(delta yq lazygit xh yazi starship gh-dash glow micro fresh edit helix nvim opencode)

# ── Main logic ──────────────────────────────────────────────────────

usage() {
	cat <<-EOF
	${BOLD}sqrbx-update${RESET} — update SquareBox tools from GitHub releases

	${BOLD}Usage:${RESET}
	  sqrbx-update              Show available updates (dry run)
	  sqrbx-update --apply      Download and install all available updates
	  sqrbx-update <tool>       Update a single tool (e.g. lazygit, starship)
	  sqrbx-update --list       List all managed tools and current versions
	  sqrbx-update --help       Show this help

	${BOLD}Tools:${RESET}
	  delta, yq, lazygit, xh, yazi, starship, gh-dash, glow, micro, fresh, edit, helix, nvim, opencode

	${DIM}Set GITHUB_TOKEN to avoid API rate limits.${RESET}
	EOF
}

# Normalize tool name (gh-dash -> ghdash)
normalize_tool() {
	echo "$1" | tr '-' ''
}

get_tool_index() {
	local name="$1"
	local normalized
	normalized=$(normalize_tool "$name")
	for i in "${!TOOLS[@]}"; do
		if [ "${TOOLS[$i]}" = "$normalized" ]; then
			echo "$i"
			return
		fi
	done
	echo "-1"
}

check_tool() {
	local idx="$1"
	local tool="${TOOLS[$idx]}"
	local display="${TOOL_DISPLAY_NAMES[$idx]}"

	local current latest
	current=$("${tool}_current")
	if ! latest=$("${tool}_latest"); then
		printf "  %-12s ${RED}%s${RESET} ${DIM}(could not check latest)${RESET}\n" "$display" "$current"
		echo "skip"
		return
	fi

	# Normalize: strip leading v for comparison
	local current_clean latest_clean
	current_clean=$(echo "$current" | sed 's/^v//')
	latest_clean=$(echo "$latest" | sed 's/^v//')

	if [ "$current_clean" = "not installed" ]; then
		printf "  %-12s ${DIM}not installed${RESET}  ->  ${GREEN}%s${RESET}\n" "$display" "$latest_clean"
		echo "update"
	elif [ "$current_clean" = "$latest_clean" ]; then
		printf "  %-12s ${GREEN}%s${RESET} ${DIM}(up to date)${RESET}\n" "$display" "$current_clean"
		echo "current"
	else
		printf "  %-12s ${YELLOW}%s${RESET}  ->  ${GREEN}%s${RESET}\n" "$display" "$current_clean" "$latest_clean"
		echo "update"
	fi
}

update_tool() {
	local idx="$1"
	local tool="${TOOLS[$idx]}"
	local display="${TOOL_DISPLAY_NAMES[$idx]}"

	local latest
	if ! latest=$("${tool}_latest"); then
		printf "  ${RED}Skipping %s (could not fetch latest version)${RESET}\n" "$display"
		return
	fi
	local latest_clean
	latest_clean=$(echo "$latest" | sed 's/^v//')

	printf "  ${CYAN}Updating %s to %s...${RESET}" "$display" "$latest_clean"
	if "${tool}_install" "$latest_clean" &>/tmp/sqrbx-update-log.txt; then
		printf " ${GREEN}done${RESET}\n"
	else
		printf " ${RED}failed${RESET}\n"
		echo "    See /tmp/sqrbx-update-log.txt for details" >&2
	fi
}

# ── Entry point ─────────────────────────────────────────────────────

main() {
	check_rate_limit

	local mode="check"
	local single_tool=""

	case "${1:-}" in
		--help|-h)
			usage
			exit 0
			;;
		--apply)
			mode="apply"
			;;
		--list)
			mode="list"
			;;
		"")
			mode="check"
			;;
		*)
			# Single tool update
			mode="single"
			single_tool="$1"
			;;
	esac

	if [ "$mode" = "single" ]; then
		local idx
		idx=$(get_tool_index "$single_tool")
		if [ "$idx" = "-1" ]; then
			echo "Unknown tool: $single_tool" >&2
			echo "Available: ${TOOL_DISPLAY_NAMES[*]}" >&2
			exit 1
		fi
		echo
		echo "${BOLD}Checking ${single_tool}...${RESET}"
		local result
		result=$(check_tool "$idx" | tail -1)
		if [ "$result" = "update" ]; then
			update_tool "$idx"
		fi
		echo
		return
	fi

	echo
	echo "${BOLD}SquareBox Tool Updater${RESET}"
	echo

	if [ "$mode" = "list" ]; then
		echo "${BOLD}Installed tools:${RESET}"
		echo
		for i in "${!TOOLS[@]}"; do
			local tool="${TOOLS[$i]}"
			local display="${TOOL_DISPLAY_NAMES[$i]}"
			local current
			current=$("${tool}_current")
			printf "  %-12s %s\n" "$display" "$current"
		done
		echo
		return
	fi

	echo "${BOLD}Checking for updates...${RESET}"
	echo

	local updates=()
	for i in "${!TOOLS[@]}"; do
		# check_tool prints a status line, then "update" or "current" on the last line
		local output
		output=$(check_tool "$i")
		# Print all lines except the last (the status indicator)
		echo "$output" | head -n -1
		local status
		status=$(echo "$output" | tail -1)
		if [ "$status" = "update" ]; then
			updates+=("$i")
		fi
	done

	echo

	if [ ${#updates[@]} -eq 0 ]; then
		echo "${GREEN}All tools are up to date.${RESET}"
		echo
		return
	fi

	echo "${YELLOW}${#updates[@]} update(s) available.${RESET}"

	if [ "$mode" = "check" ]; then
		echo
		echo "Run ${BOLD}sqrbx-update --apply${RESET} to install updates."
		echo
		return
	fi

	# mode = apply
	echo
	echo "${BOLD}Installing updates...${RESET}"
	echo
	for idx in "${updates[@]}"; do
		update_tool "$idx"
	done
	echo
	echo "${GREEN}Done.${RESET}"
	echo
}

main "$@"
