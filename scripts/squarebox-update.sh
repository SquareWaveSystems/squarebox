#!/usr/bin/env bash
set -uo pipefail

# sqrbx-update — reconcile installed Squarebox-managed tools with upstream
# releases.  Bulk modes operate only on Observed state; naming an absent tool
# explicitly is an install request.  Release metadata is cached for the run,
# image-tier checksums are mandatory, and aggregate failure is authoritative.

if [ -n "${NO_COLOR:-}" ]; then
	RED=""; GREEN=""; YELLOW=""; CYAN=""; BOLD=""; DIM=""; RESET=""
else
	RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
	CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
fi

SB_SQUAREBOX_LIB_DIR=${SB_SQUAREBOX_LIB_DIR:-/usr/local/lib/squarebox}
export SB_TOOLS_YAML=${SB_TOOLS_YAML:-"${SB_SQUAREBOX_LIB_DIR}/tools.yaml"}
TOOL_LIB=${SB_TOOL_LIB:-"${SB_SQUAREBOX_LIB_DIR}/tool-lib.sh"}
[ -r "$TOOL_LIB" ] || { echo "Error: Squarebox tool library is not readable: $TOOL_LIB" >&2; exit 1; }
SB_GH_METADATA_CACHE_DIR=$(mktemp -d) || { echo "Error: could not create release metadata cache" >&2; exit 1; }
export SB_GH_METADATA_CACHE_DIR
# shellcheck source=scripts/lib/tool-lib.sh
source "$TOOL_LIB"
sb_validate_registry || { rc=$?; rm -rf -- "$SB_GH_METADATA_CACHE_DIR"; exit "$rc"; }

SB_REPO_RAW_BASE=${SB_REPO_RAW_BASE:-https://raw.githubusercontent.com/SquareWaveSystems/squarebox}
SB_VERSION_FILE=${SB_VERSION_FILE:-/usr/local/lib/squarebox/VERSION}
SB_SOURCE_REF_FILE=${SB_SOURCE_REF_FILE:-/usr/local/lib/squarebox/SOURCE_REF}
SB_SOURCE_SHA_FILE=${SB_SOURCE_SHA_FILE:-/usr/local/lib/squarebox/SOURCE_SHA}
SB_BAKED_CHECKSUMS=${SB_BAKED_CHECKSUMS:-/usr/local/lib/squarebox/checksums.txt}
CHECKSUM_DIR=$(mktemp -d) || {
	rm -rf -- "$SB_GH_METADATA_CACHE_DIR"
	echo "Error: could not create checksum workspace" >&2
	exit 1
}
UPDATE_LOG=$(mktemp "${SB_UPDATE_LOG_DIR:-${TMPDIR:-/tmp}}/sqrbx-update-log.XXXXXX") || {
	rm -rf -- "$CHECKSUM_DIR" "$SB_GH_METADATA_CACHE_DIR"
	echo "Error: could not create update log" >&2
	exit 1
}
chmod 600 "$UPDATE_LOG" 2>/dev/null || true
CHECKSUMS_FETCHED=false
CHECKSUM_SOURCE_RESOLVED=false
CHECKSUM_SOURCE_KIND=""
CHECKSUM_SOURCE_LOCATION=""
CHECKSUM_SOURCE_DESCRIPTION=""
CHECKSUM_SOURCE_ANNOUNCED=false
KEEP_UPDATE_LOG=false

cleanup() {
	local rc=$?
	trap - EXIT HUP INT TERM
	if declare -F sb_install_transaction_pending >/dev/null 2>&1 \
		&& sb_install_transaction_pending; then
		if ! sb_rollback_install_transaction; then
			echo "CRITICAL: interrupted updater could not completely restore managed outputs." >&2
			rc=1
		fi
	fi
	rm -rf -- "$CHECKSUM_DIR" 2>/dev/null || true
	rm -rf -- "$SB_GH_METADATA_CACHE_DIR" 2>/dev/null || true
	if [ "$rc" -ne 0 ] && [ -s "$UPDATE_LOG" ] && [ "$KEEP_UPDATE_LOG" != true ]; then
		KEEP_UPDATE_LOG=true
		echo "Diagnostic log preserved at $UPDATE_LOG" >&2
	fi
	if [ "$KEEP_UPDATE_LOG" != true ]; then
		rm -f -- "$UPDATE_LOG" 2>/dev/null || true
	fi
	exit "$rc"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

is_release_source_ref() {
	local value="$1"
	[[ "$value" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z][0-9A-Za-z.-]*)?(\+[0-9A-Za-z][0-9A-Za-z.-]*)?$ ]] \
		&& [[ ! "$value" =~ -[0-9]+-g[0-9a-f]{7,40}$ ]]
}

is_source_sha() {
	[[ "$1" =~ ^[0-9a-f]{40}$ ]]
}

read_identity_value() {
	local file="$1" value="" line_count
	[ -f "$file" ] && [ ! -L "$file" ] && [ -r "$file" ] || return 1
	line_count=$(awk 'END { print NR + 0 }' "$file") || return 1
	[ "$line_count" -eq 1 ] || return 1
	IFS= read -r value < "$file" || true
	[ -n "$value" ] && [ "${#value}" -le 128 ] && [[ "$value" != *$'\r'* ]] || return 1
	printf '%s\n' "$value"
}

resolve_checksum_source() {
	[ "$CHECKSUM_SOURCE_RESOLVED" = true ] && return 0
	local source_ref="${SQUAREBOX_SOURCE_REF:-}" source_sha="${SQUAREBOX_SOURCE_SHA:-}" version=""
	local source_ref_origin="environment" source_sha_origin="environment"

	if [ -n "${SB_CHECKSUMS_URL:-}" ]; then
		CHECKSUM_SOURCE_KIND=remote
		CHECKSUM_SOURCE_LOCATION=$SB_CHECKSUMS_URL
		CHECKSUM_SOURCE_DESCRIPTION="explicit checksum URL override"
		echo "Warning: using explicit SB_CHECKSUMS_URL override; Release source binding is bypassed." >&2
		CHECKSUM_SOURCE_RESOLVED=true
		return 0
	fi

	if [ -f "$SB_BAKED_CHECKSUMS" ]; then
		if [ -L "$SB_BAKED_CHECKSUMS" ] || [ ! -r "$SB_BAKED_CHECKSUMS" ]; then
			echo "Error: baked checksum manifest is not a readable regular file: $SB_BAKED_CHECKSUMS" >&2
			return 1
		fi
		CHECKSUM_SOURCE_KIND=baked
		CHECKSUM_SOURCE_LOCATION=$SB_BAKED_CHECKSUMS
		CHECKSUM_SOURCE_DESCRIPTION="manifest baked into this Candidate image"
		CHECKSUM_SOURCE_RESOLVED=true
		return 0
	fi

	if [ -z "$source_ref" ] && [ -e "$SB_SOURCE_REF_FILE" ]; then
		if source_ref=$(read_identity_value "$SB_SOURCE_REF_FILE"); then
			source_ref_origin=$SB_SOURCE_REF_FILE
		else
			echo "Error: invalid source-ref identity file: $SB_SOURCE_REF_FILE" >&2
			return 1
		fi
	fi
	if [ -z "$source_sha" ] && [ -e "$SB_SOURCE_SHA_FILE" ]; then
		if source_sha=$(read_identity_value "$SB_SOURCE_SHA_FILE"); then
			source_sha_origin=$SB_SOURCE_SHA_FILE
		else
			echo "Error: invalid source-SHA identity file: $SB_SOURCE_SHA_FILE" >&2
			return 1
		fi
	fi
	if [ -n "$source_sha" ] && ! is_source_sha "$source_sha"; then
		echo "Error: $source_sha_origin does not contain a full 40-character source SHA." >&2
		return 1
	fi

	if [ -n "$source_ref" ]; then
		if is_release_source_ref "$source_ref" || is_source_sha "$source_ref"; then
			CHECKSUM_SOURCE_KIND=remote
			CHECKSUM_SOURCE_LOCATION="${SB_REPO_RAW_BASE}/${source_ref}/checksums.txt"
			CHECKSUM_SOURCE_DESCRIPTION="recorded immutable source $source_ref"
			CHECKSUM_SOURCE_RESOLVED=true
			return 0
		fi
		if [ -n "$source_sha" ]; then
			echo "Warning: $source_ref_origin is not immutable; using pinned edge source SHA $source_sha for checksums." >&2
			CHECKSUM_SOURCE_KIND=remote
			CHECKSUM_SOURCE_LOCATION="${SB_REPO_RAW_BASE}/${source_sha}/checksums.txt"
			CHECKSUM_SOURCE_DESCRIPTION="pinned edge source SHA $source_sha"
			CHECKSUM_SOURCE_RESOLVED=true
			return 0
		fi
		case "$source_ref" in
			main|refs/heads/main|refs/remotes/origin/main) ;;
			*) echo "Error: $source_ref_origin is not an immutable Release ref or full source SHA: $source_ref" >&2; return 1 ;;
		esac
	fi

	if [ -e "$SB_VERSION_FILE" ]; then
		if version=$(read_identity_value "$SB_VERSION_FILE"); then :; else
			echo "Error: invalid Candidate version file: $SB_VERSION_FILE" >&2
			return 1
		fi
	fi
	if is_release_source_ref "$version" || is_source_sha "$version"; then
		CHECKSUM_SOURCE_KIND=remote
		CHECKSUM_SOURCE_LOCATION="${SB_REPO_RAW_BASE}/${version}/checksums.txt"
		CHECKSUM_SOURCE_DESCRIPTION="Candidate source $version"
		CHECKSUM_SOURCE_RESOLVED=true
		return 0
	fi
	if [ -n "$source_sha" ]; then
		echo "Notice: edge Candidate checksums are pinned to source SHA $source_sha." >&2
		CHECKSUM_SOURCE_KIND=remote
		CHECKSUM_SOURCE_LOCATION="${SB_REPO_RAW_BASE}/${source_sha}/checksums.txt"
		CHECKSUM_SOURCE_DESCRIPTION="pinned edge source SHA $source_sha"
		CHECKSUM_SOURCE_RESOLVED=true
		return 0
	fi

	# Compatibility for old/dev images that predate a recorded source identity.
	# This is intentionally noisy and never used when any immutable identity is
	# available.  New Candidates should bake the manifest or record source SHA.
	echo "WARNING: legacy checksum fallback is using mutable main; rebuild or reinstall from a published Release." >&2
	CHECKSUM_SOURCE_KIND=remote
	CHECKSUM_SOURCE_LOCATION="${SB_REPO_RAW_BASE}/main/checksums.txt"
	CHECKSUM_SOURCE_DESCRIPTION="LEGACY mutable main fallback"
	CHECKSUM_SOURCE_RESOLVED=true
}

validate_checksum_manifest() {
	local file="$1"
	[ -s "$file" ] || { echo "Error: checksum manifest is empty" >&2; return 1; }
	if ! awk '
		/^#/ || NF == 0 { next }
		NF != 2 || $1 !~ /^[0-9a-f]{64}$/ { bad=1 }
		END { exit bad ? 1 : 0 }
	' "$file"; then
		echo "Error: checksum manifest is malformed" >&2
		return 1
	fi
}

fetch_checksums() {
	[ "$CHECKSUMS_FETCHED" = true ] && return 0
	local destination="$CHECKSUM_DIR/checksums.txt"
	resolve_checksum_source || return $?
	if [ "$CHECKSUM_SOURCE_KIND" = baked ]; then
		if cp -- "$CHECKSUM_SOURCE_LOCATION" "$destination"; then :; else
			local rc=$?; echo "Error: could not read baked checksum manifest" >&2; return "$rc"
		fi
	else
		if curl -fsSLo "$destination" "$CHECKSUM_SOURCE_LOCATION"; then :; else
			local rc=$?
			echo "Error: could not fetch required checksum manifest: $CHECKSUM_SOURCE_LOCATION" >&2
			return "$rc"
		fi
	fi
	validate_checksum_manifest "$destination" || return $?
	CHECKSUMS_FETCHED=true
}

# Extend tool-lib's verifier with Squarebox's pinned manifest policy for the
# image tier. The setup tier keeps tool-lib's exact GitHub release-asset digest
# verifier.
eval "$(declare -f sb_verify | sed '1s/^sb_verify /_sb_tool_lib_verify /')"
sb_verify() {
	local file="$1" artifact="$2" tool="${3:-${SB_CURRENT_TOOL:-}}" policy expected actual_line actual
	[ -n "$tool" ] || { echo "Error: updater verifier has no tool identity" >&2; return 1; }
	policy=$(sb_get "$tool" verification) || return 1
	case "$policy" in
		github-release-digest)
			_sb_tool_lib_verify "$file" "$artifact" "$tool"
			;;
		sha256)
			fetch_checksums || return $?
			mapfile -t matches < <(awk -v name="$artifact" \
				'NF == 2 && $1 ~ /^[0-9a-f]{64}$/ && $2 == name { print $1 }' \
				"$CHECKSUM_DIR/checksums.txt")
			[ "${#matches[@]}" -eq 1 ] || {
				if [ "${#matches[@]}" -eq 0 ]; then
					echo "Error: no vetted checksum for $tool artifact $artifact" >&2
				else
					echo "Error: ambiguous checksums for $tool artifact $artifact" >&2
				fi
				return 1
			}
			expected=${matches[0]}
			if actual_line=$(sha256sum -- "$file"); then actual=${actual_line%% *}; else return $?; fi
			[ "$actual" = "$expected" ] || {
				echo "CHECKSUM MISMATCH for $artifact" >&2
				echo "  expected: $expected" >&2
				echo "  actual:   $actual" >&2
				return 1
			}
			;;
		*) echo "Error: unsupported verification policy for $tool: $policy" >&2; return 1 ;;
	esac
}

# ── Observed version probes ──────────────────────────────────────────

_extract_first_version() {
	awk '
		match($0, /v?[0-9]+\.[0-9]+(\.[0-9]+)?([.+-][0-9A-Za-z.-]+)?/) {
			version = substr($0, RSTART, RLENGTH)
			sub(/^v/, "", version)
			print version
			exit
		}
	'
}

delta_current() { delta --version 2>/dev/null | _extract_first_version; }
yq_current() { yq --version 2>/dev/null | _extract_first_version; }
lazygit_current() {
	lazygit --version 2>/dev/null | awk '
		{
			start = index($0, "version=")
			if (start > 0) {
				value = substr($0, start + 8)
				if (match(value, /^v?[0-9]+\.[0-9]+(\.[0-9]+)?([.+-][0-9A-Za-z.-]+)?/)) {
					value = substr(value, RSTART, RLENGTH); sub(/^v/, "", value); print value; exit
				}
			}
		}
	'
}
xh_current() { xh --version 2>/dev/null | _extract_first_version; }
yazi_current() { yazi --version 2>/dev/null | _extract_first_version; }
starship_current() { starship --version 2>/dev/null | _extract_first_version; }
ghdash_current() { gh-dash --version 2>/dev/null | _extract_first_version; }
glow_current() { glow --version 2>/dev/null | _extract_first_version; }
gum_current() { gum --version 2>/dev/null | _extract_first_version; }
micro_current() { micro --version 2>/dev/null | _extract_first_version; }
fresh_current() { fresh --version 2>/dev/null | _extract_first_version; }
edit_current() { edit --version 2>/dev/null | _extract_first_version; }
helix_current() { hx --version 2>/dev/null | _extract_first_version; }
nvim_current() { nvim --version 2>/dev/null | _extract_first_version; }
opencode_current() { opencode --version 2>/dev/null | _extract_first_version; }
zellij_current() { zellij --version 2>/dev/null | _extract_first_version; }
just_current() { just --version 2>/dev/null | _extract_first_version; }
difftastic_current() { difft --version 2>/dev/null | _extract_first_version; }
mise_current() { mise --version 2>/dev/null | _extract_first_version; }

normalize_tool() {
	local normalized=${1//-/}
	printf '%s\n' "$normalized"
}

tool_command() {
	local binaries
	binaries=$(sb_get "$1" binaries) || return 1
	printf '%s\n' "${binaries%%,*}"
}

OUTPUTS_PRESENT=false
OUTPUTS_COMPLETE=true
inspect_managed_outputs() {
	local tool="$1" dest_type method binaries post bin path tree_dest tree_target link_dest
	OUTPUTS_PRESENT=false
	OUTPUTS_COMPLETE=true
	dest_type=$(sb_get "$tool" dest) || return 1
	[ "$dest_type" = user ] || return 0
	method=$(sb_get "$tool" method) || return 1
	binaries=$(sb_get "$tool" binaries) || return 1
	post=$(sb_get "$tool" post_install) || return 1

	# Multi-binary archives are one logical Managed-home output set. Observing a
	# primary command elsewhere on PATH does not make a missing managed sibling
	# (for example Yazi's `ya`) complete.
	if [[ "$binaries" == *,* ]]; then
		while IFS= read -r bin; do
			path="$HOME/.local/bin/$bin"
			if [ -e "$path" ] || [ -L "$path" ]; then OUTPUTS_PRESENT=true; fi
			[ -f "$path" ] && [ ! -L "$path" ] || OUTPUTS_COMPLETE=false
		done < <(printf '%s\n' "$binaries" | tr ',' '\n')
	fi

	if [ "$post" = helix_runtime ]; then
		path="$HOME/.config/helix/runtime"
		if [ -e "$path" ] || [ -L "$path" ]; then OUTPUTS_PRESENT=true; fi
		[ -d "$path" ] && [ ! -L "$path" ] || OUTPUTS_COMPLETE=false
	fi

	if [ "$method" = tar.gz-tree ]; then
		tree_dest=$(sb_get "$tool" tree_dest) || return 1
		tree_target=$(sb_get "$tool" symlink) || return 1
		tree_dest="${tree_dest/#\~/$HOME}"
		tree_target="${tree_target/#\~/$HOME}"
		bin=${binaries%%,*}
		link_dest="$HOME/.local/bin/$bin"
		if [ -e "$tree_dest" ] || [ -L "$tree_dest" ] \
			|| [ -e "$link_dest" ] || [ -L "$link_dest" ]; then
			OUTPUTS_PRESENT=true
		fi
		[ -d "$tree_dest" ] && [ ! -L "$tree_dest" ] \
			&& [ -f "$tree_target" ] && [ ! -L "$tree_target" ] \
			&& [ -L "$link_dest" ] && [ "$(readlink "$link_dest")" = "$tree_target" ] \
			|| OUTPUTS_COMPLETE=false
	fi
}

CURRENT_STATE=""
CURRENT_VERSION=""
probe_current() {
	local tool="$1" command_name probe value
	command_name=$(tool_command "$tool") || return 1
	inspect_managed_outputs "$tool" || return 1
	if ! command -v "$command_name" >/dev/null 2>&1; then
		if [ "$OUTPUTS_PRESENT" = true ]; then
			CURRENT_STATE=incomplete; CURRENT_VERSION="unknown"; return 0
		fi
		CURRENT_STATE=absent; CURRENT_VERSION="not installed"; return 0
	fi
	probe="$(normalize_tool "$tool")_current"
	value=""
	if declare -F "$probe" >/dev/null 2>&1; then
		if value=$("$probe"); then :; else value=""; fi
	fi
	if [ -z "$value" ]; then
		local raw
		if raw=$("$command_name" --version 2>/dev/null); then
			value=$(printf '%s\n' "$raw" | _extract_first_version)
		fi
	fi
	value=${value%%$'\n'*}; value=${value#v}
	if [ -z "$value" ]; then
		CURRENT_STATE=broken; CURRENT_VERSION="unknown"; return 0
	fi
	CURRENT_VERSION="$value"
	if [ "$OUTPUTS_COMPLETE" != true ]; then
		CURRENT_STATE=incomplete
	else
		CURRENT_STATE=installed
	fi
}

# ── Cached release metadata ──────────────────────────────────────────

declare -A LATEST_CACHE=()
declare -A LATEST_FAILED=()

resolve_latest() {
	local tool="$1" repo prefix tag version
	[ -z "${LATEST_CACHE[$tool]+x}" ] || return 0
	[ -z "${LATEST_FAILED[$tool]+x}" ] || return 1
	repo=$(sb_get "$tool" repo) || { LATEST_FAILED[$tool]=1; return 1; }
	prefix=$(sb_get "$tool" version_prefix) || { LATEST_FAILED[$tool]=1; return 1; }
	if sb_gh_latest_tag "$repo" >/dev/null; then
		tag=$SB_GH_TAG
	else
		LATEST_FAILED[$tool]=1; return 1
	fi
	if [ -n "$prefix" ]; then
		if [[ "$tag" != "$prefix"* ]]; then
			echo "Error: latest tag $tag for $tool lacks expected prefix $prefix" >&2
			LATEST_FAILED[$tool]=1; return 1
		fi
		version=${tag#"$prefix"}
	else
		version=$tag
	fi
	if ! sb_validate_version "$version"; then LATEST_FAILED[$tool]=1; return 1; fi
	LATEST_CACHE[$tool]=$version
}

verification_note() {
	case "$(sb_get "$1" verification)" in
		sha256) printf '%s' "${DIM}[SHA256 required]${RESET}" ;;
		github-release-digest) printf '%s' "${DIM}[GitHub asset SHA256 required]${RESET}" ;;
	esac
}

IMAGE_PREFLIGHT_STATUS=""
IMAGE_PREFLIGHT_ARTIFACT=""
preflight_image_target() {
	local tool="$1" version="$2" expected
	local -a matches=()
	IMAGE_PREFLIGHT_STATUS=error
	IMAGE_PREFLIGHT_ARTIFACT=$(sb_artifact "$tool" "$version" "$SB_DPKG_ARCH") || return 1
	fetch_checksums || return $?
	mapfile -t matches < <(awk -v name="$IMAGE_PREFLIGHT_ARTIFACT" \
		'NF == 2 && $1 ~ /^[0-9a-f]{64}$/ && $2 == name { print $1 }' \
		"$CHECKSUM_DIR/checksums.txt")
	if [ "${#matches[@]}" -eq 0 ]; then
		IMAGE_PREFLIGHT_STATUS=candidate
		return 0
	fi
	[ "${#matches[@]}" -eq 1 ] || {
		echo "Error: ambiguous checksums for $tool artifact $IMAGE_PREFLIGHT_ARTIFACT" >&2
		return 1
	}
	expected=${matches[0]}
	sb_prepare_release_asset "$tool" "$version" "$SB_DPKG_ARCH" || return $?
	[ "$SB_RESOLVED_TOOL" = "$tool" ] \
		&& [ "$SB_RESOLVED_VERSION" = "$version" ] \
		&& [ "$SB_RESOLVED_ARTIFACT" = "$IMAGE_PREFLIGHT_ARTIFACT" ] \
		&& [[ "$SB_EXPECTED_ASSET_SHA256" =~ ^[0-9a-f]{64}$ ]] || {
		echo "Error: inconsistent release-asset identity for $tool/$version" >&2
		return 1
	}
	if [ "$expected" != "$SB_EXPECTED_ASSET_SHA256" ]; then
		IMAGE_PREFLIGHT_STATUS=candidate
		return 0
	fi
	IMAGE_PREFLIGHT_STATUS=authorized
}

CHECK_STATUS=""
CHECK_CURRENT=""
CHECK_LATEST=""
check_tool() {
	local tool="$1" explicit="${2:-false}" policy note
	policy=$(sb_get "$tool" verification) || { CHECK_STATUS=unchecked; return 1; }
	note=$(verification_note "$tool")
	if probe_current "$tool"; then :; else
		printf "  %-12s ${RED}%s${RESET} ${DIM}(installed, version probe failed)${RESET}\n" "$tool" "$CURRENT_VERSION"
		CHECK_STATUS=unchecked; CHECK_CURRENT="$CURRENT_VERSION"; CHECK_LATEST=""
		return 1
	fi
	CHECK_CURRENT=$CURRENT_VERSION
	if [ "$CURRENT_STATE" = absent ] && [ "$explicit" != true ]; then
		printf "  %-12s ${DIM}not installed (skipped)${RESET}\n" "$tool"
		CHECK_STATUS=absent; CHECK_LATEST=""
		return 0
	fi
	if ! resolve_latest "$tool"; then
		printf "  %-12s ${RED}%s${RESET} ${DIM}(latest version unchecked)${RESET}\n" "$tool" "$CURRENT_VERSION"
		CHECK_STATUS=unchecked; CHECK_LATEST=""
		return 1
	fi
	CHECK_LATEST=${LATEST_CACHE[$tool]}
	if [ "$policy" = sha256 ] \
		&& { [ "$CURRENT_STATE" != installed ] || [ "${CURRENT_VERSION#v}" != "${CHECK_LATEST#v}" ]; }; then
		if preflight_image_target "$tool" "$CHECK_LATEST"; then :; else
			printf "  %-12s ${RED}%s${RESET} ${DIM}(Candidate authorization unchecked)${RESET}\n" "$tool" "$CURRENT_VERSION"
			CHECK_STATUS=unchecked
			return 1
		fi
		if [ "$IMAGE_PREFLIGHT_STATUS" = candidate ]; then
			printf "  %-12s ${YELLOW}%s${RESET}  ->  ${DIM}%s (new Candidate required; exact asset is not authorized)${RESET}\n" \
				"$tool" "$CURRENT_VERSION" "$CHECK_LATEST"
			CHECK_STATUS=candidate
			return 0
		fi
	fi
	if [ "$CURRENT_STATE" = absent ]; then
		printf "  %-12s ${DIM}not installed${RESET}  ->  ${GREEN}%s${RESET} %s\n" "$tool" "$CHECK_LATEST" "$note"
		CHECK_STATUS=update
	elif [ "$CURRENT_STATE" = broken ]; then
		printf "  %-12s ${RED}broken${RESET}  ->  ${GREEN}%s${RESET} ${DIM}(repair)${RESET} %s\n" "$tool" "$CHECK_LATEST" "$note"
		CHECK_STATUS=update
	elif [ "$CURRENT_STATE" = incomplete ]; then
		printf "  %-12s ${YELLOW}%s${RESET}  ->  ${GREEN}%s${RESET} ${DIM}(incomplete; repair)${RESET} %s\n" \
			"$tool" "$CURRENT_VERSION" "$CHECK_LATEST" "$note"
		CHECK_STATUS=update
	elif [ "${CURRENT_VERSION#v}" = "${CHECK_LATEST#v}" ]; then
		printf "  %-12s ${GREEN}%s${RESET} ${DIM}(up to date)${RESET} %s\n" "$tool" "$CURRENT_VERSION" "$note"
		CHECK_STATUS=current
	else
		printf "  %-12s ${YELLOW}%s${RESET}  ->  ${GREEN}%s${RESET} %s\n" "$tool" "$CURRENT_VERSION" "$CHECK_LATEST" "$note"
		CHECK_STATUS=update
	fi
}

update_tool() {
	local tool="$1" latest policy dest_type rc observed expected_observed rollback_rc
	resolve_latest "$tool" || return 1
	latest=${LATEST_CACHE[$tool]}
	policy=$(sb_get "$tool" verification) || return 1
	dest_type=$(sb_get "$tool" dest) || return 1
	if [ "$policy" = sha256 ]; then
		if fetch_checksums; then
			:
		else
			local checksum_rc=$?
			printf "  ${RED}Cannot update %s: its Release-bound checksum manifest is unavailable.${RESET}\n" "$tool" >&2
			return "$checksum_rc"
		fi
		if [ "$CHECKSUM_SOURCE_ANNOUNCED" != true ]; then
			printf '  Checksum source: %s\n' "$CHECKSUM_SOURCE_DESCRIPTION"
			CHECKSUM_SOURCE_ANNOUNCED=true
		fi
	fi
	printf "  ${CYAN}Installing %s %s...${RESET}" "$tool" "$latest"
	{
		printf '\n== %s %s ==\n' "$tool" "$latest"
		printf 'verification-policy: %s\n' "$policy"
	} >> "$UPDATE_LOG"
	SB_CURRENT_TOOL=$tool
	unset SB_ASSET_VERSION
	_SB_RETAIN_INSTALL_TRANSACTION=false
	[ "$dest_type" != user ] || _SB_RETAIN_INSTALL_TRANSACTION=true
	if sb_install "$tool" "$latest" >> "$UPDATE_LOG" 2>&1; then
		rc=0
	else
		rc=$?
	fi
	SB_CURRENT_TOOL=""
	if [ "$rc" -eq 0 ]; then
		expected_observed=$latest
		if [ "$(sb_get "$tool" asset_version_from_api)" = true ] && [ -n "${SB_ASSET_VERSION:-}" ]; then
			expected_observed=$SB_ASSET_VERSION
		fi
		if probe_current "$tool" && [ "$CURRENT_STATE" = installed ]; then
			observed=${CURRENT_VERSION#v}
			if [ "$observed" != "${expected_observed#v}" ]; then
				printf 'Error: post-install version for %s is %s; expected %s\n' "$tool" "$observed" "$expected_observed" >> "$UPDATE_LOG"
				rc=1
			fi
		else
			printf 'Error: %s is not observable after installation\n' "$tool" >> "$UPDATE_LOG"
			rc=1
		fi
	fi
	if [ "$rc" -eq 0 ]; then
		sb_finalize_install_transaction >> "$UPDATE_LOG" 2>&1 || true
	else
		if sb_install_transaction_pending; then
			if sb_rollback_install_transaction >> "$UPDATE_LOG" 2>&1; then
				printf 'Rolled back managed outputs for %s after failed post-install verification\n' "$tool" >> "$UPDATE_LOG"
			else
				rollback_rc=$?
				printf 'Error: rollback for %s was incomplete (status %s)\n' "$tool" "$rollback_rc" >> "$UPDATE_LOG"
				rc=1
			fi
		else
			sb_finalize_install_transaction >> "$UPDATE_LOG" 2>&1 || true
		fi
	fi
	if [ "$rc" -eq 0 ]; then
		printf " ${GREEN}done${RESET}\n"
		return 0
	fi
	KEEP_UPDATE_LOG=true
	printf " ${RED}failed${RESET}\n"
	echo "    Diagnostic log preserved at $UPDATE_LOG" >&2
	return "$rc"
}

usage() {
	cat <<-EOF
	${BOLD}sqrbx-update${RESET} — update Squarebox-managed tools

	${BOLD}Usage:${RESET}
	  sqrbx-update              Check installed tools (dry run)
	  sqrbx-update --apply      Apply authorized in-place updates to installed tools
	  sqrbx-update <tool>       Update, or explicitly install, one named tool
	  sqrbx-update --list       List observed tool versions without network access
	  sqrbx-update --help       Show this help
	EOF
}

mapfile -t TOOLS < <(sb_list_tools)

find_tool() {
	local requested normalized tool
	requested=$1; normalized=$(normalize_tool "$requested")
	for tool in "${TOOLS[@]}"; do
		if [ "$(normalize_tool "$tool")" = "$normalized" ]; then
			FOUND_TOOL=$tool; return 0
		fi
	done
	return 1
}

main() {
	local mode=check single_tool=""
	if [ "$#" -gt 1 ]; then usage >&2; return 2; fi
	case "${1:-}" in
		"") mode=check ;;
		--apply) mode=apply ;;
		--list) mode=list ;;
		--help|-h) usage; return 0 ;;
		--*) echo "Unknown option: $1" >&2; usage >&2; return 2 ;;
		*) mode=single; single_tool=$1 ;;
	esac

	if [ "$mode" = list ]; then
		echo "${BOLD}Observed tools:${RESET}"
		local list_failures=0 tool
		for tool in "${TOOLS[@]}"; do
			if probe_current "$tool"; then
				case "$CURRENT_STATE" in
					installed|absent) printf '  %-12s %s\n' "$tool" "$CURRENT_VERSION" ;;
					*) printf '  %-12s %s (%s)\n' "$tool" "$CURRENT_VERSION" "$CURRENT_STATE" ;;
				esac
			else
				printf '  %-12s unknown (version probe failed)\n' "$tool"
				list_failures=$((list_failures + 1))
			fi
		done
		[ "$list_failures" -eq 0 ]
		return
	fi

	if [ "$mode" = single ]; then
		if ! find_tool "$single_tool"; then
			echo "Unknown tool: $single_tool" >&2
			echo "Available: ${TOOLS[*]}" >&2
			return 1
		fi
		echo "${BOLD}Checking ${FOUND_TOOL}...${RESET}"
		if check_tool "$FOUND_TOOL" true; then :; else return 1; fi
		case "$CHECK_STATUS" in
			current) echo "${GREEN}${FOUND_TOOL} is already current.${RESET}"; return 0 ;;
			update) update_tool "$FOUND_TOOL"; return $? ;;
			candidate)
				echo "Error: ${FOUND_TOOL} is image-tier state; publish and rebuild from a newer Candidate to advance it." >&2
				return 1
				;;
			*) echo "Error: ${FOUND_TOOL} could not be checked safely" >&2; return 1 ;;
		esac
	fi

	echo "${BOLD}Checking installed tools for updates...${RESET}"
	local -a updates=()
	local check_failures=0 install_failures=0 candidate_required=0 tool
	for tool in "${TOOLS[@]}"; do
		if check_tool "$tool" false; then :; else check_failures=$((check_failures + 1)); fi
		[ "$CHECK_STATUS" = update ] && updates+=("$tool")
		[ "$CHECK_STATUS" = candidate ] && candidate_required=$((candidate_required + 1))
	done

	echo
	if [ "${#updates[@]}" -eq 0 ] && [ "$check_failures" -eq 0 ] && [ "$candidate_required" -eq 0 ]; then
		echo "${GREEN}All installed tools are up to date.${RESET}"
		return 0
	fi
	[ "${#updates[@]}" -eq 0 ] || echo "${YELLOW}${#updates[@]} installed tool update(s) available.${RESET}"
	[ "$candidate_required" -eq 0 ] || echo "${YELLOW}${candidate_required} image-tier tool update(s) require a newer Squarebox Candidate and rebuild.${RESET}"
	[ "$check_failures" -eq 0 ] || echo "${RED}${check_failures} installed tool(s) could not be checked.${RESET}" >&2

	if [ "$mode" = check ]; then
		[ "${#updates[@]}" -eq 0 ] || echo "Run ${BOLD}sqrbx-update --apply${RESET} to install them."
		[ "$check_failures" -eq 0 ]
		return
	fi

	for tool in "${updates[@]}"; do
		if update_tool "$tool"; then :; else install_failures=$((install_failures + 1)); fi
	done
	if [ "$check_failures" -ne 0 ] || [ "$install_failures" -ne 0 ] || [ "$candidate_required" -ne 0 ]; then
		echo "${RED}Update incomplete: ${check_failures} check failure(s), ${install_failures} install failure(s), ${candidate_required} image-tier update(s) requiring a Candidate rebuild.${RESET}" >&2
		return 1
	fi
	echo "${GREEN}All available installed-tool updates completed.${RESET}"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	main "$@"
fi
