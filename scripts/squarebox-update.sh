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

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Source shared tool library ─────────────────────────────────────────

export SB_TOOLS_YAML=/usr/local/lib/squarebox/tools.yaml
source /usr/local/lib/squarebox/tool-lib.sh

mkdir -p "$HOME/.local/bin"

AUTH_HEADER=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
	AUTH_HEADER=(-H "Authorization: token ${GITHUB_TOKEN}")
fi

# ── Checksum verification ──────────────────────────────────────────────
# Fetches checksums.txt and setup-checksums.txt from the repo's main branch.
# Only versions that have been vetted (committed to the repo) can be installed.

REPO_RAW="https://raw.githubusercontent.com/SquareWaveSystems/SquareBox/main"
CHECKSUM_DIR=$(mktemp -d)
CHECKSUMS_FETCHED=false

fetch_checksums() {
	if [ "$CHECKSUMS_FETCHED" = true ]; then return 0; fi
	if curl -fsSLo "$CHECKSUM_DIR/checksums.txt" "$REPO_RAW/checksums.txt" 2>/dev/null \
		&& curl -fsSLo "$CHECKSUM_DIR/setup-checksums.txt" "$REPO_RAW/setup-checksums.txt" 2>/dev/null; then
		# Merge both files
		cat "$CHECKSUM_DIR/checksums.txt" "$CHECKSUM_DIR/setup-checksums.txt" > "$CHECKSUM_DIR/all-checksums.txt"
		CHECKSUMS_FETCHED=true
	else
		echo -e "${RED}Warning: Could not fetch checksums from repo. Updates will be skipped.${RESET}" >&2
		return 1
	fi
}

# Override the library's no-op sb_verify with checksum verification.
# Returns 0 on match, 1 on mismatch, 2 if no checksum found (version not vetted).
sb_verify() {
	local file="$1" name="$2"
	if [ "$CHECKSUMS_FETCHED" != true ]; then return 2; fi
	local expected
	expected=$(grep -E "^[0-9a-f]{64}  ${name}$" "$CHECKSUM_DIR/all-checksums.txt" | awk '{print $1}') || true
	if [ -z "$expected" ]; then
		echo -e "    ${YELLOW}No checksum found for ${name} — version not yet vetted in repo${RESET}" >&2
		return 2
	fi
	local actual
	actual=$(sha256sum "$file" | awk '{print $1}')
	if [ "$actual" != "$expected" ]; then
		echo -e "    ${RED}CHECKSUM MISMATCH for ${name}${RESET}" >&2
		echo -e "    ${RED}  expected: ${expected}${RESET}" >&2
		echo -e "    ${RED}  actual:   ${actual}${RESET}" >&2
		return 1
	fi
	return 0
}

UPDATE_LOG=$(mktemp /tmp/sqrbx-update-log.XXXXXX)
TEMP_DIRS=("$CHECKSUM_DIR" "$UPDATE_LOG")

cleanup_temp() {
	for d in "${TEMP_DIRS[@]}"; do
		rm -rf "$d" 2>/dev/null || true
	done
}
trap cleanup_temp EXIT

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

# ── Current version detection ──────────────────────────────────────────
# Each tool's --version output is unique; not worth abstracting.

delta_current() { delta --version 2>/dev/null | awk '{print $2}' || echo "not installed"; }
yq_current() { yq --version 2>/dev/null | grep -oP 'v[\d.]+' | head -1 | sed 's/^v//' || echo "not installed"; }
lazygit_current() { lazygit --version 2>/dev/null | grep -oP ', version=\K[\d.]+' | head -1 || echo "not installed"; }
xh_current() { xh --version 2>/dev/null | head -1 | awk '{print $2}' || echo "not installed"; }
yazi_current() { yazi --version 2>/dev/null | head -1 | awk '{print $2}' || echo "not installed"; }
starship_current() { starship --version 2>/dev/null | head -1 | awk '{print $2}' || echo "not installed"; }
ghdash_current() { local ver; ver=$(gh-dash --version 2>/dev/null | grep -oP 'module version: v\K[\d.]+' | head -1) || ver="not installed"; echo "$ver"; }
glow_current() { glow --version 2>/dev/null | head -1 | grep -oP '[\d.]+' | head -1 || echo "not installed"; }
micro_current() { micro --version 2>/dev/null | head -1 | awk '{print $2}' || echo "not installed"; }
fresh_current() { fresh --version 2>/dev/null | grep -oP '[\d.]+' | head -1 || echo "not installed"; }
edit_current() { edit --version 2>/dev/null | grep -oP '[\d.]+' | head -1 || echo "not installed"; }
helix_current() { hx --version 2>/dev/null | head -1 | awk '{print $2}' || echo "not installed"; }
nvim_current() { nvim --version 2>/dev/null | head -1 | awk '{print $2}' | sed 's/^v//' || echo "not installed"; }
opencode_current() { opencode --version 2>/dev/null | grep -oP '[\d.]+' | head -1 || echo "not installed"; }
zellij_current() { zellij --version 2>/dev/null | head -1 | awk '{print $2}' || echo "not installed"; }

# ── Latest version fetching ────────────────────────────────────────────
# Uses repo from tools.yaml via sb_get; strips v prefix where needed.

tool_latest() {
	local tool="$1"
	local repo prefix tag
	repo=$(sb_get "$tool" repo)
	prefix=$(sb_get "$tool" version_prefix)
	tag=$(gh_latest_tag "$repo") || return 1
	if [ -n "$prefix" ]; then
		strip_v "$tag"
	else
		echo "$tag"
	fi
}

# ── Edit special handling ──────────────────────────────────────────────
# Edit's asset version may differ from its tag version. Query the API to
# determine the actual asset name and set SB_ASSET_VERSION before installing.

edit_prepare_asset_version() {
	local api_response api_code asset_name
	api_response=$(curl -fsSL -w '\n%{http_code}' "${AUTH_HEADER[@]}" \
		"https://api.github.com/repos/microsoft/edit/releases/latest" 2>/dev/null) || true
	api_code=$(echo "$api_response" | tail -1)
	if [ "$api_code" = "403" ]; then
		echo "  GitHub API rate limit exceeded. Set GITHUB_TOKEN to authenticate." >&2
		return 1
	elif [ "$api_code" != "200" ]; then
		echo "  GitHub API returned HTTP ${api_code} for microsoft/edit." >&2
		return 1
	fi
	asset_name=$(echo "$api_response" | sed '$d' | jq -r '.assets[].name' | grep "${SB_ZARCH}-linux-gnu" | head -1)
	if [ -z "$asset_name" ]; then
		echo "  Could not find edit asset for ${SB_ZARCH}" >&2
		return 1
	fi
	# Extract asset version from filename: edit-1.2.0-x86_64-linux-gnu.tar.zst → 1.2.0
	SB_ASSET_VERSION=$(echo "$asset_name" | sed -E 's/^edit-([0-9]+\.[0-9]+\.[0-9]+)-.*/\1/')
	export SB_ASSET_VERSION
}

# ── Tool registry ──────────────────────────────────────────────────────

TOOLS=(delta yq lazygit xh yazi starship ghdash glow micro fresh edit helix nvim opencode zellij)
TOOL_DISPLAY_NAMES=(delta yq lazygit xh yazi starship gh-dash glow micro fresh edit helix nvim opencode zellij)

# Map display names to tools.yaml names (ghdash → gh-dash)
yaml_name() {
	case "$1" in
		ghdash) echo "gh-dash" ;;
		*)      echo "$1" ;;
	esac
}

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
	  delta, yq, lazygit, xh, yazi, starship, gh-dash, glow, micro, fresh, edit, helix, nvim, opencode, zellij

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
	local yname
	yname=$(yaml_name "$tool")

	local current latest
	current=$("${tool}_current")
	if ! latest=$(tool_latest "$yname"); then
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
	local yname
	yname=$(yaml_name "$tool")

	local latest
	if ! latest=$(tool_latest "$yname"); then
		printf "  ${RED}Skipping %s (could not fetch latest version)${RESET}\n" "$display"
		return
	fi
	local latest_clean
	latest_clean=$(echo "$latest" | sed 's/^v//')

	printf "  ${CYAN}Updating %s to %s...${RESET}" "$display" "$latest_clean"

	# Special handling for edit's asset version
	if [ "$tool" = "edit" ]; then
		edit_prepare_asset_version || { printf " ${RED}failed${RESET}\n"; return; }
	fi

	# Ensure xz-utils is available for helix
	if [ "$tool" = "helix" ] && ! command -v xz &>/dev/null; then
		sudo apt-get update -qq && sudo apt-get install -y -qq xz-utils >/dev/null 2>&1
	fi

	# Ensure zstd is available for edit
	local cleanup_zstd=""
	if [ "$tool" = "edit" ] && ! command -v zstd &>/dev/null; then
		sudo apt-get update -qq && sudo apt-get install -y -qq zstd >/dev/null 2>&1
		cleanup_zstd=1
	fi

	if (set -e; sb_install "$yname" "$latest_clean") &>"$UPDATE_LOG"; then
		printf " ${GREEN}done${RESET}\n"
	else
		printf " ${RED}failed${RESET}\n"
		echo "    See ${UPDATE_LOG} for details" >&2
	fi

	if [ "$cleanup_zstd" = "1" ]; then
		sudo apt-get purge -y -qq --auto-remove zstd 2>/dev/null || true
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

	# Fetch checksums before any install operations
	if [ "$mode" != "list" ] && [ "$mode" != "check" ]; then
		fetch_checksums || { echo -e "${RED}Cannot verify downloads without checksums. Aborting.${RESET}"; exit 1; }
	fi

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
