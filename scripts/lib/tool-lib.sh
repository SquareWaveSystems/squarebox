#!/usr/bin/env bash
# tool-lib.sh — shared library for Squarebox tool management.
# Source this file; do not execute it directly.
#
# The install implementation is deliberately independent of caller errexit
# settings.  Every stage is checked explicitly and a failed stage prevents all
# later stages from running.  Cleanup is internal and never replaces the
# authoritative operation result.

# Set SB_TOOLS_YAML before sourcing to use another registry (primarily tests).
if [ -z "${SB_TOOLS_YAML:-}" ]; then
	SB_TOOLS_YAML="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tools.yaml"
fi

SB_GITHUB_API_BASE="${SB_GITHUB_API_BASE:-https://api.github.com}"

# Keep API metadata in a per-shell-run directory so Bash command substitutions
# and setup spinner subprocesses reuse the same exact Release JSON. setup.sh
# provides SB_TMPDIR (and owns its cleanup); standalone callers get an isolated
# temporary directory and may remove it with sb_cleanup_release_metadata.
_SB_GH_METADATA_CACHE_OWNED=false
if [ -z "${SB_GH_METADATA_CACHE_DIR:-}" ]; then
	if [ -n "${SB_TMPDIR:-}" ] && [ -d "$SB_TMPDIR" ]; then
		SB_GH_METADATA_CACHE_DIR="$SB_TMPDIR/github-release-metadata"
	else
		SB_GH_METADATA_CACHE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/squarebox-gh-metadata.XXXXXX") || {
			echo "Error: could not create GitHub metadata cache" >&2
			return 1 2>/dev/null || exit 1
		}
		_SB_GH_METADATA_CACHE_OWNED=true
	fi
	export SB_GH_METADATA_CACHE_DIR
fi
if ! mkdir -p -- "$SB_GH_METADATA_CACHE_DIR" || [ -L "$SB_GH_METADATA_CACHE_DIR" ] || [ ! -d "$SB_GH_METADATA_CACHE_DIR" ]; then
	echo "Error: GitHub metadata cache is not a safe directory: $SB_GH_METADATA_CACHE_DIR" >&2
	return 1 2>/dev/null || exit 1
fi
if [ "$(stat -c %u -- "$SB_GH_METADATA_CACHE_DIR" 2>/dev/null || printf invalid)" != "$EUID" ] \
	|| ! chmod 700 "$SB_GH_METADATA_CACHE_DIR" 2>/dev/null \
	|| [ "$(stat -c %a -- "$SB_GH_METADATA_CACHE_DIR" 2>/dev/null || printf invalid)" != 700 ]; then
	echo "Error: GitHub metadata cache is not private to the current user: $SB_GH_METADATA_CACHE_DIR" >&2
	return 1 2>/dev/null || exit 1
fi

sb_cleanup_release_metadata() {
	if [ "${_SB_GH_METADATA_CACHE_OWNED:-false}" = true ]; then
		rm -rf -- "$SB_GH_METADATA_CACHE_DIR" 2>/dev/null || true
		_SB_GH_METADATA_CACHE_OWNED=false
	fi
}

# Architecture detection is performed once.  An explicit SB_DPKG_ARCH is
# accepted for deterministic callers and tests, but only supported values pass
# metadata validation.
if [ -z "${SB_DPKG_ARCH:-}" ]; then
	_sb_dpkg=$(dpkg --print-architecture 2>/dev/null || true)
	_sb_uname=$(uname -m 2>/dev/null || true)
	case "$_sb_dpkg" in
		arm64|amd64) SB_DPKG_ARCH=$_sb_dpkg ;;
		"")
			case "$_sb_uname" in
				aarch64|arm64) SB_DPKG_ARCH=arm64 ;;
				x86_64|amd64) SB_DPKG_ARCH=amd64 ;;
				*) SB_DPKG_ARCH=$_sb_uname ;;
			esac
			;;
		*) SB_DPKG_ARCH=$_sb_dpkg ;;
	esac
	unset _sb_dpkg _sb_uname
fi

case "$SB_DPKG_ARCH" in
	arm64)
		SB_ZARCH=aarch64; SB_LARCH=arm64; SB_GOARCH=arm64
		SB_OCARCH=arm64; SB_MARCH=-arm64
		;;
	amd64)
		SB_ZARCH=x86_64; SB_LARCH=x86_64; SB_GOARCH=amd64
		SB_OCARCH=x64; SB_MARCH=64
		;;
	*)
		echo "Error: unsupported architecture: ${SB_DPKG_ARCH:-<unknown>}" >&2
		return 1 2>/dev/null || exit 1
		;;
esac

# ── YAML reader (intentionally dependency-free) ─────────────────────

sb_get() {
	[ "$#" -eq 2 ] || { echo "Error: sb_get requires TOOL FIELD" >&2; return 2; }
	local tool="$1" field="$2"
	[ -r "$SB_TOOLS_YAML" ] || { echo "Error: tool registry is not readable: $SB_TOOLS_YAML" >&2; return 1; }
	awk -v tool="  $tool:" -v field="    $field:" '
		$0 == tool { found=1; next }
		found && /^  [a-zA-Z0-9_-]+:/ { exit }
		found && index($0, field) == 1 {
			val = substr($0, length(field) + 1)
			gsub(/^ +| +$/, "", val)
			gsub(/^["'"'"']|["'"'"']$/, "", val)
			print val
			exit
		}
	' "$SB_TOOLS_YAML"
}

sb_list_tools() {
	[ -r "$SB_TOOLS_YAML" ] || { echo "Error: tool registry is not readable: $SB_TOOLS_YAML" >&2; return 1; }
	awk '/^  [a-z][a-zA-Z0-9_-]*:$/ { sub(/:$/, ""); gsub(/^ +/, ""); print }' "$SB_TOOLS_YAML"
}

sb_tool_exists() {
	local wanted="$1" tool
	while IFS= read -r tool; do
		[ "$tool" = "$wanted" ] && return 0
	done < <(sb_list_tools) || return 1
	return 1
}

sb_list_group() {
	local group="$1" tool
	while IFS= read -r tool; do
		[ "$(sb_get "$tool" group)" = "$group" ] && printf '%s\n' "$tool"
	done < <(sb_list_tools)
}

# ── Registry validation ──────────────────────────────────────────────

_sb_valid_csv_binaries() {
	local value="$1" item
	[ -n "$value" ] || return 1
	while IFS= read -r item; do
		[[ "$item" =~ ^[A-Za-z0-9._+-]+$ ]] || return 1
	done < <(printf '%s\n' "$value" | tr ',' '\n')
}

sb_validate_version() {
	local version="$1"
	[[ "$version" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || {
		echo "Error: unsafe or empty version: ${version:-<empty>}" >&2
		return 1
	}
}

sb_validate_tool() {
	local tool="$1" repo prefix artifact method binaries dest group verification
	sb_tool_exists "$tool" || { echo "Error: unknown tool in registry: $tool" >&2; return 1; }
	repo=$(sb_get "$tool" repo) || return 1
	prefix=$(sb_get "$tool" version_prefix) || return 1
	artifact=$(sb_get "$tool" artifact) || return 1
	method=$(sb_get "$tool" method) || return 1
	binaries=$(sb_get "$tool" binaries) || return 1
	dest=$(sb_get "$tool" dest) || return 1
	group=$(sb_get "$tool" group) || return 1
	verification=$(sb_get "$tool" verification) || return 1

	[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || {
		echo "Error: invalid repo metadata for $tool: $repo" >&2; return 1;
	}
	[[ "$prefix" =~ ^[A-Za-z0-9._+-]*$ ]] || {
		echo "Error: invalid version_prefix metadata for $tool: $prefix" >&2; return 1;
	}
	[ -n "$artifact" ] && [[ "$artifact" =~ ^[A-Za-z0-9._+{}-]+$ ]] && [[ "$artifact" != */* ]] && [[ "$artifact" != *..* ]] || {
		echo "Error: invalid artifact metadata for $tool: $artifact" >&2; return 1;
	}
	case "$method" in
		deb|binary|tar.gz|tar.xz|tar.zst|zip|tar.gz-tree) ;;
		*) echo "Error: invalid install method for $tool: $method" >&2; return 1 ;;
	esac
	_sb_valid_csv_binaries "$binaries" || {
		echo "Error: invalid binaries metadata for $tool: $binaries" >&2; return 1;
	}
	case "$dest" in
		system|user) ;;
		*) echo "Error: invalid destination metadata for $tool: $dest" >&2; return 1 ;;
	esac
	case "$group" in
		dockerfile|setup) ;;
		*) echo "Error: invalid group metadata for $tool: $group" >&2; return 1 ;;
	esac
	case "$verification" in
		sha256|github-release-digest) ;;
		*) echo "Error: invalid verification metadata for $tool: $verification" >&2; return 1 ;;
	esac
	if [ "$group" = "dockerfile" ] && [ "$verification" != "sha256" ]; then
		echo "Error: Dockerfile-tier tool $tool must require sha256 verification" >&2
		return 1
	fi
	if [ "$group" = dockerfile ] && [ "$dest" != system ]; then
		echo "Error: Dockerfile-tier tool $tool must target the system destination" >&2
		return 1
	fi
	if [ "$group" = "setup" ] && [ "$verification" != "github-release-digest" ]; then
		echo "Error: setup-tier tool $tool must require GitHub release-asset digest verification" >&2
		return 1
	fi
	if [ "$group" = setup ] && [ "$dest" != user ]; then
		echo "Error: setup-tier tool $tool must target the user destination" >&2
		return 1
	fi
	if [ "$dest" = system ] && [[ "$binaries" == *,* ]]; then
		echo "Error: system destination supports exactly one binary for $tool" >&2
		return 1
	fi
	if [ "$group" = "dockerfile" ]; then
		local docker_arg
		docker_arg=$(sb_get "$tool" docker_arg) || return 1
		[[ "$docker_arg" =~ ^[A-Z][A-Z0-9_]*_VERSION$ ]] || {
			echo "Error: invalid Docker ARG metadata for $tool: $docker_arg" >&2; return 1;
		}
	fi

	local tar_strip tar_extract zip_subdir tree_name tree_dest symlink post find_binary asset_version_from_api
	tar_strip=$(sb_get "$tool" tar_strip) || return 1
	tar_extract=$(sb_get "$tool" tar_extract) || return 1
	zip_subdir=$(sb_get "$tool" zip_subdir) || return 1
	tree_name=$(sb_get "$tool" tree_name) || return 1
	tree_dest=$(sb_get "$tool" tree_dest) || return 1
	symlink=$(sb_get "$tool" symlink) || return 1
	post=$(sb_get "$tool" post_install) || return 1
	find_binary=$(sb_get "$tool" find_binary) || return 1
	asset_version_from_api=$(sb_get "$tool" asset_version_from_api) || return 1
	[ -z "$tar_strip" ] || [[ "$tar_strip" =~ ^[0-9]+$ ]] || {
		echo "Error: invalid tar_strip metadata for $tool: $tar_strip" >&2; return 1;
	}
	[ -z "$tar_extract" ] || { [[ "$tar_extract" =~ ^[A-Za-z0-9._+{}-]+$ ]] && [[ "$tar_extract" != -* ]]; } || {
		echo "Error: invalid tar_extract metadata for $tool: $tar_extract" >&2; return 1;
	}
	[ -z "$zip_subdir" ] || { [[ "$zip_subdir" =~ ^[A-Za-z0-9._+{}-]+$ ]] && [[ "$zip_subdir" != *..* ]]; } || {
		echo "Error: invalid zip_subdir metadata for $tool: $zip_subdir" >&2; return 1;
	}
	case "$find_binary" in ""|true) ;; *) echo "Error: invalid find_binary metadata for $tool: $find_binary" >&2; return 1 ;; esac
	case "$asset_version_from_api" in ""|true) ;; *) echo "Error: invalid asset_version_from_api metadata for $tool: $asset_version_from_api" >&2; return 1 ;; esac
	if { [ "$method" = binary ] || [ "$method" = deb ]; } && [[ "$binaries" == *,* ]]; then
		echo "Error: $method method supports exactly one binary for $tool" >&2; return 1
	fi
	if [ "$method" = "zip" ] && [ -z "$zip_subdir" ]; then
		echo "Error: zip_subdir is required for $tool" >&2; return 1
	fi
	if [ "$method" = "tar.gz-tree" ]; then
		{ [[ "$tree_name" =~ ^[A-Za-z0-9._+{}-]+$ ]] && [[ "$tree_name" != *..* ]]; } || {
			echo "Error: invalid tree_name metadata for $tool: $tree_name" >&2; return 1;
		}
		[[ "$tree_dest" == '~/'* ]] && [[ "/$tree_dest/" != *'/../'* ]] || {
			echo "Error: tree_dest for $tool must be within the managed home" >&2; return 1;
		}
		[ -z "$symlink" ] || { [[ "$symlink" == '~/'* ]] && [[ "/$symlink/" != *'/../'* ]]; } || {
			echo "Error: symlink target for $tool must be within the managed home" >&2; return 1;
		}
	fi
	case "$post" in
		""|helix_runtime) ;;
		*) echo "Error: invalid post_install metadata for $tool: $post" >&2; return 1 ;;
	esac
	if [ "$post" = helix_runtime ]; then
		[ "$dest" = user ] && { [ "$method" = tar.gz ] || [ "$method" = tar.xz ] || [ "$method" = tar.zst ]; } || {
			echo "Error: helix_runtime requires a user tar install for $tool" >&2
			return 1
		}
	fi
}

sb_validate_registry() {
	local count=0 tool
	declare -A seen_args=()
	while IFS= read -r tool; do
		[ -n "$tool" ] || continue
		count=$((count + 1))
		sb_validate_tool "$tool" || return 1
		if [ "$(sb_get "$tool" group)" = "dockerfile" ]; then
			local arg
			arg=$(sb_get "$tool" docker_arg) || return 1
			[ -z "${seen_args[$arg]+x}" ] || {
				echo "Error: duplicate Docker ARG metadata: $arg" >&2; return 1;
			}
			seen_args[$arg]="$tool"
		fi
	done < <(sb_list_tools)
	[ "$count" -gt 0 ] || { echo "Error: tool registry is empty" >&2; return 1; }
}

# ── Artifact and URL resolution ──────────────────────────────────────

_sb_resolve_arch() {
	local arch="$1" str="$2"
	case "$arch" in
		arm64)
			str="${str//\{dpkg_arch\}/arm64}"; str="${str//\{zarch\}/aarch64}"
			str="${str//\{larch\}/arm64}"; str="${str//\{goarch\}/arm64}"
			str="${str//\{ocarch\}/arm64}"; str="${str//\{march\}/-arm64}"
			;;
		amd64)
			str="${str//\{dpkg_arch\}/amd64}"; str="${str//\{zarch\}/x86_64}"
			str="${str//\{larch\}/x86_64}"; str="${str//\{goarch\}/amd64}"
			str="${str//\{ocarch\}/x64}"; str="${str//\{march\}/64}"
			;;
		*) echo "Error: unsupported architecture: $arch" >&2; return 1 ;;
	esac
	printf '%s\n' "$str"
}

sb_artifact() {
	local tool="$1" version="$2" arch="${3:-$SB_DPKG_ARCH}" pattern
	sb_validate_tool "$tool" || return 1
	sb_validate_version "$version" || return 1
	pattern=$(sb_get "$tool" artifact) || return 1
	pattern="${pattern//\{version\}/$version}"
	if [[ "$pattern" == *"{asset_version}"* ]]; then
		local asset_version="${SB_ASSET_VERSION:-$version}"
		sb_validate_version "$asset_version" || return 1
		pattern="${pattern//\{asset_version\}/$asset_version}"
	fi
	pattern=$(_sb_resolve_arch "$arch" "$pattern") || return 1
	if [[ "$pattern" == *'{'* ]] || [[ "$pattern" == *'}'* ]] || [[ "$pattern" == */* ]] || [[ "$pattern" == *..* ]]; then
		echo "Error: unresolved or unsafe artifact for $tool: $pattern" >&2
		return 1
	fi
	printf '%s\n' "$pattern"
}

sb_url() {
	local tool="$1" version="$2" arch="${3:-$SB_DPKG_ARCH}" repo prefix artifact
	sb_validate_tool "$tool" || return 1
	sb_validate_version "$version" || return 1
	repo=$(sb_get "$tool" repo) || return 1
	prefix=$(sb_get "$tool" version_prefix) || return 1
	artifact=$(sb_artifact "$tool" "$version" "$arch") || return 1
	printf 'https://github.com/%s/releases/download/%s/%s\n' "$repo" "${prefix}${version}" "$artifact"
}

# ── GitHub release metadata ──────────────────────────────────────────

# Release JSON is cached in the current shell under both the endpoint used and
# its exact tag endpoint. Callers inside this library invoke the functions
# directly (not through command substitution), so a latest lookup can be reused
# by the subsequent exact-version install without another API request.
declare -A _SB_GH_BODY_CACHE=()
declare -A _SB_GH_FAILED_CACHE=()
SB_GH_API_BODY=""
SB_GH_TAG=""
SB_LATEST_VERSION=""
SB_RESOLVED_TOOL=""
SB_RESOLVED_VERSION=""
SB_RESOLVED_TAG=""
SB_RESOLVED_ARTIFACT=""
SB_RESOLVED_URL=""
SB_EXPECTED_ASSET_SHA256=""

_sb_gh_disk_cache_path() {
	local url="$1" suffix="${2:-json}" key
	key=$(printf '%s' "$url" | sha256sum | awk '{print $1}') || return 1
	[[ "$key" =~ ^[0-9a-f]{64}$ ]] || return 1
	printf '%s/%s.%s\n' "$SB_GH_METADATA_CACHE_DIR" "$key" "$suffix"
}

_sb_gh_cache_body() {
	local url="$1" body="$2" path stage
	path=$(_sb_gh_disk_cache_path "$url") || return 1
	if stage=$(mktemp "$SB_GH_METADATA_CACHE_DIR/.metadata.XXXXXX"); then :; else return $?; fi
	chmod 600 "$stage" 2>/dev/null || true
	if printf '%s\n' "$body" > "$stage"; then :; else
		local rc=$?; rm -f -- "$stage" 2>/dev/null || true; return "$rc"
	fi
	# Metadata cache publication is not an install destination commit. Bypass a
	# caller's mv seam so transaction fault injection remains scoped to outputs.
	if /bin/mv -fT -- "$stage" "$path"; then :; else
		local rc=$?; rm -f -- "$stage" 2>/dev/null || true; return "$rc"
	fi
}

_sb_gh_cache_failure() {
	local url="$1" path stage
	path=$(_sb_gh_disk_cache_path "$url" failed) || return 0
	if stage=$(mktemp "$SB_GH_METADATA_CACHE_DIR/.failure.XXXXXX"); then :; else return 0; fi
	chmod 600 "$stage" 2>/dev/null || true
	if : > "$stage"; then :; else rm -f -- "$stage" 2>/dev/null || true; return 0; fi
	/bin/mv -fT -- "$stage" "$path" 2>/dev/null || rm -f -- "$stage" 2>/dev/null || true
}

_sb_gh_api_get() {
	local url="$1" context="$2" response curl_rc http_code body message cache_path failed_path
	if [ -n "${_SB_GH_BODY_CACHE[$url]+x}" ]; then
		SB_GH_API_BODY=${_SB_GH_BODY_CACHE[$url]}
		printf '%s\n' "$SB_GH_API_BODY"
		return 0
	fi
	[ -z "${_SB_GH_FAILED_CACHE[$url]+x}" ] || return 1
	cache_path=$(_sb_gh_disk_cache_path "$url") || return 1
	failed_path=$(_sb_gh_disk_cache_path "$url" failed) || return 1
	if [ -f "$cache_path" ] && [ ! -L "$cache_path" ]; then
		body=$(<"$cache_path")
		if printf '%s' "$body" | jq -e 'type == "object"' >/dev/null 2>&1; then
			_SB_GH_BODY_CACHE[$url]=$body
			SB_GH_API_BODY=$body
			printf '%s\n' "$body"
			return 0
		fi
		rm -f -- "$cache_path" 2>/dev/null || true
	fi
	if [ -f "$failed_path" ] && [ ! -L "$failed_path" ]; then
		_SB_GH_FAILED_CACHE[$url]=1
		return 1
	fi
	response=$(curl -sSL -w '\n%{http_code}' "$url" 2>/dev/null)
	curl_rc=$?
	if [ "$curl_rc" -ne 0 ]; then
		_SB_GH_FAILED_CACHE[$url]=1
		_sb_gh_cache_failure "$url"
		echo "Error: failed to reach GitHub API for ${context} (curl exit ${curl_rc})" >&2
		return "$curl_rc"
	fi
	http_code=${response##*$'\n'}
	body=${response%$'\n'*}
	[[ "$http_code" =~ ^[0-9]{3}$ ]] || {
		echo "Error: GitHub API returned no valid HTTP status for ${context}" >&2; return 1;
	}
	if [ "$http_code" = "200" ]; then
		printf '%s' "$body" | jq -e 'type == "object"' >/dev/null 2>&1 || {
			_SB_GH_FAILED_CACHE[$url]=1
			_sb_gh_cache_failure "$url"
			echo "Error: GitHub API returned invalid metadata for ${context}" >&2; return 1;
		}
		_SB_GH_BODY_CACHE[$url]=$body
		_sb_gh_cache_body "$url" "$body" || true
		SB_GH_API_BODY=$body
		local repo tag api_prefix rest
		api_prefix="${SB_GITHUB_API_BASE}/repos/"
		if [[ "$url" == "$api_prefix"*'/releases/'* ]]; then
			rest=${url#"$api_prefix"}
			repo=${rest%%/releases/*}
			[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || repo=""
			tag=$(printf '%s' "$body" | jq -r '.tag_name // empty' 2>/dev/null || true)
			if [ -n "$repo" ] && [ -n "$tag" ] && [[ "$tag" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]]; then
				_SB_GH_BODY_CACHE["${SB_GITHUB_API_BASE}/repos/${repo}/releases/tags/${tag}"]=$body
				_sb_gh_cache_body "${SB_GITHUB_API_BASE}/repos/${repo}/releases/tags/${tag}" "$body" || true
			fi
		fi
		printf '%s\n' "$body"
		return 0
	fi
	_SB_GH_FAILED_CACHE[$url]=1
	_sb_gh_cache_failure "$url"
	message=$(printf '%s' "$body" | jq -r '.message // empty' 2>/dev/null || true)
	if [ "$http_code" = "403" ]; then
		echo "Error: GitHub API returned HTTP 403 for ${context}${message:+: $message} (possible rate limit)" >&2
	else
		echo "Error: GitHub API returned HTTP ${http_code} for ${context}${message:+: $message}" >&2
	fi
	return 1
}

sb_gh_latest_tag() {
	local repo="$1" body tag
	[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || {
		echo "Error: invalid GitHub repository: $repo" >&2; return 1;
	}
	_sb_gh_api_get "${SB_GITHUB_API_BASE}/repos/${repo}/releases/latest" "$repo" >/dev/null || return $?
	body=$SB_GH_API_BODY
	tag=$(printf '%s' "$body" | jq -er '.tag_name | select(type == "string" and length > 0)' 2>/dev/null) || {
		echo "Error: no valid release tag for ${repo}" >&2; return 1;
	}
	[[ "$tag" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || {
		echo "Error: unsafe release tag for ${repo}: $tag" >&2; return 1;
	}
	SB_GH_TAG=$tag
	printf '%s\n' "$tag"
}

sb_latest_version() {
	local tool="$1" repo prefix tag version
	sb_validate_tool "$tool" || return 1
	repo=$(sb_get "$tool" repo) || return 1
	prefix=$(sb_get "$tool" version_prefix) || return 1
	sb_gh_latest_tag "$repo" >/dev/null || return $?
	tag=$SB_GH_TAG
	if [ -n "$prefix" ]; then
		[[ "$tag" == "$prefix"* ]] || {
			echo "Error: release tag $tag for $tool does not start with expected prefix $prefix" >&2; return 1;
		}
		version=${tag#"$prefix"}
	else
		version=$tag
	fi
	sb_validate_version "$version" || return 1
	SB_LATEST_VERSION=$version
	printf '%s\n' "$version"
}

# Resolve one exact GitHub release and one exact asset before any artifact
# download. GitHub's `digest` field is part of the release-asset metadata and
# must contain a well-formed sha256 value.
sb_prepare_release_asset() {
	local tool="$1" requested="${2:-latest}" arch="${3:-$SB_DPKG_ARCH}" repo prefix url context body tag version
	local artifact asset_version_from_api pattern prefix_part suffix_part name candidate
	local count digest
	SB_RESOLVED_TOOL=""; SB_RESOLVED_VERSION=""; SB_RESOLVED_TAG=""
	SB_RESOLVED_ARTIFACT=""; SB_RESOLVED_URL=""; SB_EXPECTED_ASSET_SHA256=""
	unset SB_ASSET_VERSION
	sb_validate_tool "$tool" || return 1
	repo=$(sb_get "$tool" repo) || return 1
	prefix=$(sb_get "$tool" version_prefix) || return 1
	if [ "$requested" = latest ]; then
		url="${SB_GITHUB_API_BASE}/repos/${repo}/releases/latest"
		context=$repo
	else
		sb_validate_version "$requested" || return 1
		tag="${prefix}${requested}"
		url="${SB_GITHUB_API_BASE}/repos/${repo}/releases/tags/${tag}"
		context="${repo}@${tag}"
	fi
	_sb_gh_api_get "$url" "$context" >/dev/null || return $?
	body=$SB_GH_API_BODY
	tag=$(printf '%s' "$body" | jq -er '.tag_name | select(type == "string" and length > 0)' 2>/dev/null) || {
		echo "Error: no valid release tag for ${context}" >&2; return 1;
	}
	[[ "$tag" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || {
		echo "Error: unsafe release tag for ${context}: $tag" >&2; return 1;
	}
	if [ "$requested" != latest ] && [ "$tag" != "${prefix}${requested}" ]; then
		echo "Error: GitHub release tag mismatch for $tool: expected ${prefix}${requested}, got $tag" >&2
		return 1
	fi
	if [ -n "$prefix" ]; then
		[[ "$tag" == "$prefix"* ]] || {
			echo "Error: release tag $tag for $tool does not start with expected prefix $prefix" >&2; return 1;
		}
		version=${tag#"$prefix"}
	else
		version=$tag
	fi
	sb_validate_version "$version" || return 1

	asset_version_from_api=$(sb_get "$tool" asset_version_from_api) || return 1
	if [ "$asset_version_from_api" = true ]; then
		pattern=$(sb_get "$tool" artifact) || return 1
		pattern="${pattern//\{version\}/$version}"
		pattern=$(_sb_resolve_arch "$arch" "$pattern") || return 1
		prefix_part=${pattern%%\{asset_version\}*}
		suffix_part=${pattern#*\{asset_version\}}
		[ "$pattern" != "$prefix_part" ] || {
			echo "Error: asset_version_from_api requires an asset_version token for $tool" >&2; return 1;
		}
		local -a asset_candidates=()
		while IFS= read -r name; do
			[[ "$name" == "$prefix_part"*"$suffix_part" ]] || continue
			candidate=${name#"$prefix_part"}
			candidate=${candidate%"$suffix_part"}
			sb_validate_version "$candidate" >/dev/null 2>&1 || continue
			SB_ASSET_VERSION=$candidate
			if [ "$(sb_artifact "$tool" "$version" "$arch")" = "$name" ]; then
				asset_candidates+=("$candidate")
			fi
		done < <(printf '%s' "$body" | jq -r '.assets[]?.name | select(type == "string")' 2>/dev/null)
		[ "${#asset_candidates[@]}" -eq 1 ] || {
			unset SB_ASSET_VERSION
			echo "Error: expected exactly one architecture-matching release asset for $tool at $tag" >&2
			return 1
		}
		SB_ASSET_VERSION=${asset_candidates[0]}
		export SB_ASSET_VERSION
	fi
	artifact=$(sb_artifact "$tool" "$version" "$arch") || return 1
	count=$(printf '%s' "$body" | jq -er --arg name "$artifact" \
		'[.assets[]? | select(.name == $name)] | length' 2>/dev/null) || {
		echo "Error: invalid release asset metadata for $tool at $tag" >&2; return 1;
	}
	[ "$count" -eq 1 ] || {
		echo "Error: expected exactly one release asset named $artifact for $tool at $tag; found $count" >&2
		return 1
	}
	digest=$(printf '%s' "$body" | jq -er --arg name "$artifact" \
		'.assets[] | select(.name == $name) | .digest | select(type == "string")' 2>/dev/null) || {
		echo "Error: missing GitHub release-asset SHA-256 digest for $tool artifact $artifact" >&2
		return 1
	}
	[[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || {
		echo "Error: malformed GitHub release-asset SHA-256 digest for $tool artifact $artifact" >&2
		return 1
	}
	SB_RESOLVED_TOOL=$tool
	SB_RESOLVED_VERSION=$version
	SB_RESOLVED_TAG=$tag
	SB_RESOLVED_ARTIFACT=$artifact
	SB_RESOLVED_URL=$(sb_url "$tool" "$version" "$arch") || return 1
	SB_EXPECTED_ASSET_SHA256=${digest#sha256:}
}

# Image-tier artifacts fail unless their caller supplies Squarebox's pinned
# checksum verifier. Setup-tier artifacts compare bytes with GitHub's exact
# release-asset digest resolved above.
sb_verify() {
	local file="$1" artifact="$2" tool="${3:-}" verification actual_line actual
	[ -n "$tool" ] || { echo "Error: verification requires tool identity" >&2; return 1; }
	verification=$(sb_get "$tool" verification) || return 1
	case "$verification" in
		github-release-digest)
			[ "$tool" = "${SB_RESOLVED_TOOL:-}" ] \
				&& [ "$artifact" = "${SB_RESOLVED_ARTIFACT:-}" ] \
				&& [[ "${SB_EXPECTED_ASSET_SHA256:-}" =~ ^[0-9a-f]{64}$ ]] || {
				echo "Error: no authoritative GitHub release-asset digest is prepared for $tool ($artifact)" >&2
				return 1
			}
			if actual_line=$(sha256sum -- "$file"); then actual=${actual_line%% *}; else return $?; fi
			[ "$actual" = "$SB_EXPECTED_ASSET_SHA256" ] || {
				echo "CHECKSUM MISMATCH for $artifact" >&2
				echo "  expected: $SB_EXPECTED_ASSET_SHA256" >&2
				echo "  actual:   $actual" >&2
				return 1
			}
			;;
		sha256)
			echo "Error: SHA256 verifier is not configured for $tool ($artifact)" >&2
			return 1
			;;
		*) echo "Error: unsupported verification policy for $tool: $verification" >&2; return 1 ;;
	esac
}

# ── Fail-closed install implementation ───────────────────────────────

_sb_archive_paths_safe() {
	local list_file="$1" entry
	while IFS= read -r entry; do
		[ -n "$entry" ] || continue
		case "$entry" in
			/*) echo "Error: archive contains an absolute path: $entry" >&2; return 1 ;;
		esac
		if [[ "/$entry/" == *'/../'* ]]; then
			echo "Error: archive contains parent traversal: $entry" >&2
			return 1
		fi
	done < "$list_file"
}

_sb_extracted_tree_safe() {
	local root="$1" canonical link target resolved special
	canonical=$(cd "$root" 2>/dev/null && pwd -P) || return 1
	special=$(find "$canonical" ! -type f ! -type d ! -type l -print -quit 2>/dev/null) || return 1
	[ -z "$special" ] || {
		echo "Error: archive contains an unsupported special file: $special" >&2
		return 1
	}
	while IFS= read -r -d '' link; do
		target=$(readlink -- "$link") || return 1
		case "$target" in
			/*) echo "Error: archive symlink has an absolute target: $link -> $target" >&2; return 1 ;;
		esac
		resolved=$(realpath -m -- "${link%/*}/$target" 2>/dev/null) || return 1
		case "$resolved" in
			"$canonical"|"$canonical"/*) ;;
			*) echo "Error: archive symlink escapes staging: $link -> $target" >&2; return 1 ;;
		esac
	done < <(find "$canonical" -type l -print0 2>/dev/null)
}

_sb_download_and_verify() {
	local tool="$1" url="$2" artifact="$3" output="$4"
	if curl -fsSLo "$output" "$url"; then
		:
	else
		local rc=$?
		echo "Error: failed to download $tool artifact: $url" >&2
		return "$rc"
	fi
	[ -s "$output" ] || { echo "Error: downloaded artifact is empty: $artifact" >&2; return 1; }
	if sb_verify "$output" "$artifact" "$tool"; then
		:
	else
		local rc=$?
		echo "Error: verification rejected $tool artifact: $artifact" >&2
		return "$rc"
	fi
}

_sb_require_regular_source() {
	local src="$1"
	[ -f "$src" ] && [ ! -L "$src" ] || {
		echo "Error: install source is missing, not regular, or a symlink: $src" >&2; return 1;
	}
}

# Stage beside the destination, then rename.  A failed copy/chmod leaves the
# previous executable untouched; rename is atomic on the destination filesystem.
_sb_do_install() {
	local src="$1" dest="$2" dest_type="$3" parent base stage
	_sb_require_regular_source "$src" || return 1
	parent=${dest%/*}; base=${dest##*/}
	if [ "$dest_type" = "system" ] && [ "$(id -u)" != "0" ]; then
		stage="${parent}/.${base}.squarebox.$$.$RANDOM"
		if sudo install -m 0755 -- "$src" "$stage"; then
			:
		else
			local rc=$?
			echo "Error: failed to stage system binary: $dest" >&2; return "$rc"
		fi
		if sudo mv -fT -- "$stage" "$dest"; then
			:
		else
			local rc=$?
			sudo rm -f -- "$stage" 2>/dev/null || true
			echo "Error: failed to replace system binary: $dest" >&2
			return "$rc"
		fi
	else
		if mkdir -p -- "$parent"; then
			:
		else
			local rc=$?
			echo "Error: failed to create destination directory: $parent" >&2; return "$rc"
		fi
		if stage=$(mktemp "${parent}/.${base}.squarebox.XXXXXX"); then :; else
			local rc=$?; echo "Error: failed to create destination staging file in $parent" >&2; return "$rc"
		fi
		if install -m 0755 -- "$src" "$stage"; then
			:
		else
			local rc=$?
			rm -f -- "$stage" 2>/dev/null || true
			echo "Error: failed to stage binary: $dest" >&2
			return "$rc"
		fi
		if mv -fT -- "$stage" "$dest"; then
			:
		else
			local rc=$?
			rm -f -- "$stage" 2>/dev/null || true
			echo "Error: failed to replace binary: $dest" >&2
			return "$rc"
		fi
	fi
}

# A serialized user-output transaction stages every file/tree/link beside its
# destination before the first mutation. Unexpected destination types fail
# without replacement. Commit uses per-destination renames and restores all
# prior Observed state if any later rename fails. This is rollback
# transactionality, not crash atomicity across multiple destinations.
declare -a _SB_TX_TYPES=() _SB_TX_SOURCES=() _SB_TX_DESTS=()
declare -a _SB_TX_STAGES=() _SB_TX_BACKUPS=()
_SB_TX_COMMITTED=false
_SB_RETAIN_INSTALL_TRANSACTION=false

_sb_user_tx_reset() {
	_SB_TX_TYPES=(); _SB_TX_SOURCES=(); _SB_TX_DESTS=()
	_SB_TX_STAGES=(); _SB_TX_BACKUPS=()
	_SB_TX_COMMITTED=false
}

_sb_user_tx_add() {
	local type="$1" source="$2" dest="$3" existing
	case "$type" in file|tree|symlink) ;; *) return 2 ;; esac
	case "$dest" in "$HOME"/*) ;; *) echo "Error: refusing transaction destination outside managed home: $dest" >&2; return 1 ;; esac
	for existing in "${_SB_TX_DESTS[@]}"; do
		[ "$existing" != "$dest" ] || { echo "Error: duplicate transaction destination: $dest" >&2; return 1; }
	done
	_SB_TX_TYPES+=("$type"); _SB_TX_SOURCES+=("$source"); _SB_TX_DESTS+=("$dest")
}

_sb_user_tx_cleanup_stages() {
	local stage
	for stage in "${_SB_TX_STAGES[@]}"; do
		[ -z "$stage" ] || rm -rf -- "$stage" 2>/dev/null || true
	done
}

_sb_user_tx_stage() {
	local i type source dest parent base stage
	_SB_TX_STAGES=(); _SB_TX_BACKUPS=()
	# Validate the complete output set before creating any destination-local
	# stage. A bad later output therefore cannot leave an earlier output staged.
	for i in "${!_SB_TX_DESTS[@]}"; do
		type=${_SB_TX_TYPES[$i]}; source=${_SB_TX_SOURCES[$i]}; dest=${_SB_TX_DESTS[$i]}
		case "$type" in
			file)
				_sb_require_regular_source "$source" || return 1
				if { [ -e "$dest" ] || [ -L "$dest" ]; } \
					&& [ ! -f "$dest" ] && [ ! -L "$dest" ]; then
					echo "Error: refusing to replace non-file destination: $dest" >&2
					return 1
				fi
				;;
			tree)
				[ -d "$source" ] && [ ! -L "$source" ] || {
					echo "Error: managed tree source is invalid: $source" >&2; return 1;
				}
				if { [ -e "$dest" ] || [ -L "$dest" ]; } \
					&& { [ ! -d "$dest" ] || [ -L "$dest" ]; }; then
					echo "Error: refusing to replace non-tree destination: $dest" >&2
					return 1
				fi
				;;
			symlink)
				[ -n "$source" ] || return 1
				if { [ -e "$dest" ] || [ -L "$dest" ]; } \
					&& [ ! -f "$dest" ] && [ ! -L "$dest" ]; then
					echo "Error: refusing to replace non-file link destination: $dest" >&2
					return 1
				fi
				;;
		esac
	done
	for i in "${!_SB_TX_DESTS[@]}"; do
		type=${_SB_TX_TYPES[$i]}; source=${_SB_TX_SOURCES[$i]}; dest=${_SB_TX_DESTS[$i]}
		parent=${dest%/*}; base=${dest##*/}
		if mkdir -p -- "$parent"; then :; else
			local rc=$?; _sb_user_tx_cleanup_stages; return "$rc"
		fi
		case "$type" in
			file)
				if stage=$(mktemp "${parent}/.${base}.squarebox.XXXXXX"); then :; else
					local rc=$?; _sb_user_tx_cleanup_stages; return "$rc"
				fi
				_SB_TX_STAGES+=("$stage")
				if install -m 0755 -- "$source" "$stage"; then :; else
					local rc=$?; _sb_user_tx_cleanup_stages; return "$rc"
				fi
				;;
			tree)
				if stage=$(mktemp -d "${parent}/.${base}.squarebox.XXXXXX"); then :; else
					local rc=$?; _sb_user_tx_cleanup_stages; return "$rc"
				fi
				_SB_TX_STAGES+=("$stage")
				if cp -a -- "$source/." "$stage/"; then :; else
					local rc=$?; _sb_user_tx_cleanup_stages; return "$rc"
				fi
				;;
			symlink)
				stage="${parent}/.${base}.squarebox-link.$$.$RANDOM"
				[ ! -e "$stage" ] && [ ! -L "$stage" ] || { _sb_user_tx_cleanup_stages; return 1; }
				_SB_TX_STAGES+=("$stage")
				if ln -s -- "$source" "$stage"; then :; else
					local rc=$?; _sb_user_tx_cleanup_stages; return "$rc"
				fi
				;;
		esac
	done
}

_sb_user_tx_rollback() {
	local last="$1" i dest backup rollback_failed=false
	for ((i=last; i>=0; i--)); do
		dest=${_SB_TX_DESTS[$i]}; backup=${_SB_TX_BACKUPS[$i]:-}
		if [ -e "$dest" ] || [ -L "$dest" ]; then
			rm -rf -- "$dest" 2>/dev/null || rollback_failed=true
		fi
		if [ -n "$backup" ] && { [ -e "$backup" ] || [ -L "$backup" ]; }; then
			mv -T -- "$backup" "$dest" 2>/dev/null || rollback_failed=true
		fi
	done
	if [ "$rollback_failed" = false ]; then
		return 0
	fi
	echo "Error: user-output rollback was incomplete" >&2
	return 1
}

_sb_user_tx_finalize() {
	local backup cleanup_failed=false
	for backup in "${_SB_TX_BACKUPS[@]}"; do
		[ -z "$backup" ] || rm -rf -- "$backup" 2>/dev/null || cleanup_failed=true
	done
	_sb_user_tx_reset
	if [ "$cleanup_failed" = true ]; then
		echo "Warning: failed to remove one or more transaction backups" >&2
	fi
	return 0
}

_sb_user_tx_commit() {
	_sb_user_tx_stage || return $?
	local i dest parent base stage backup rc
	for i in "${!_SB_TX_DESTS[@]}"; do
		dest=${_SB_TX_DESTS[$i]}; stage=${_SB_TX_STAGES[$i]}
		parent=${dest%/*}; base=${dest##*/}; backup=""
		if [ -e "$dest" ] || [ -L "$dest" ]; then
			backup="${parent}/.${base}.squarebox-backup.$$.$RANDOM"
			if mv -T -- "$dest" "$backup"; then :; else
				rc=$?; _sb_user_tx_rollback "$((i - 1))"; _sb_user_tx_cleanup_stages; return "$rc"
			fi
		fi
		_SB_TX_BACKUPS[$i]=$backup
		if mv -T -- "$stage" "$dest"; then
			_SB_TX_STAGES[$i]=""
		else
			rc=$?; _sb_user_tx_rollback "$i"; _sb_user_tx_cleanup_stages; return "$rc"
		fi
	done
	_SB_TX_COMMITTED=true
	[ "${_SB_RETAIN_INSTALL_TRANSACTION:-false}" = true ] || _sb_user_tx_finalize
}

_sb_extract_tar() {
	local tool="$1" tmp="$2" dest_dir="$3" dest_type="$4" compression="$5" archive="$6"
	local strip find_bin binaries tar_extract list_file bin src post hdir
	strip=$(sb_get "$tool" tar_strip) || return 1
	find_bin=$(sb_get "$tool" find_binary) || return 1
	binaries=$(sb_get "$tool" binaries) || return 1
	tar_extract=$(sb_get "$tool" tar_extract) || return 1
	list_file="$tmp/archive.list"
	if tar "${compression}tf" "$archive" > "$list_file"; then
		:
	else
		local rc=$?
		echo "Error: failed to read $tool archive" >&2; return "$rc"
	fi
	_sb_archive_paths_safe "$list_file" || return 1
	local -a args=("${compression}xf" "$archive" -C "$tmp")
	[ -n "$strip" ] && args+=("--strip-components=$strip")
	[ -n "$tar_extract" ] && args+=(-- "$tar_extract")
	if tar "${args[@]}"; then
		:
	else
		local rc=$?
		echo "Error: failed to extract $tool archive" >&2; return "$rc"
	fi
	_sb_extracted_tree_safe "$tmp" || return 1
	local -a sources=() names=()
	while IFS= read -r bin; do
		if [ "$find_bin" = "true" ]; then
			local -a matches=()
			mapfile -d '' -t matches < <(find "$tmp" -name "$bin" -type f -perm /111 -print0 2>/dev/null)
			[ "${#matches[@]}" -eq 1 ] || {
				echo "Error: expected exactly one executable named $bin in $tool archive; found ${#matches[@]}" >&2
				return 1
			}
			src=${matches[0]}
		else
			src="$tmp/$bin"
		fi
		_sb_require_regular_source "$src" || { echo "Error: $bin not found safely in $tool archive" >&2; return 1; }
		sources+=("$src"); names+=("$bin")
	done < <(printf '%s\n' "$binaries" | tr ',' '\n')
	local i
	post=$(sb_get "$tool" post_install) || return 1
	if [ "$dest_type" = user ]; then
		_sb_user_tx_reset
		for i in "${!sources[@]}"; do
			_sb_user_tx_add file "${sources[$i]}" "$dest_dir/${names[$i]}" || return $?
		done
		if [ "$post" = helix_runtime ]; then
			local -a helix_dirs=()
			mapfile -d '' -t helix_dirs < <(find "$tmp" -type d -name 'helix-*-linux' -print0 2>/dev/null)
			[ "${#helix_dirs[@]}" -eq 1 ] || {
				echo "Error: expected exactly one Helix release tree; found ${#helix_dirs[@]}" >&2
				return 1
			}
			hdir=${helix_dirs[0]}
			[ -n "$hdir" ] && [ -d "$hdir/runtime" ] && [ ! -L "$hdir/runtime" ] || {
				echo "Error: Helix runtime missing after extraction" >&2
				return 1
			}
			_sb_user_tx_add tree "$hdir/runtime" "$HOME/.config/helix/runtime" || return $?
		fi
		_sb_user_tx_commit || return $?
	else
		[ -z "$post" ] || { echo "Error: post-install output is unsupported for system tool $tool" >&2; return 1; }
		for i in "${!sources[@]}"; do
			_sb_do_install "${sources[$i]}" "$dest_dir/${names[$i]}" "$dest_type" || return $?
		done
	fi
}

_sb_install_pipeline() {
	local tool="$1" version="$2" tmp="$3" method="$4" dest_type="$5" artifact="$6" url="$7" binaries="$8"
	local dest_dir
	# SB_SYSTEM_BIN_DIR is a deterministic test seam; production callers leave it
	# unset so system outputs remain constrained to /usr/local/bin.
	if [ "$dest_type" = "system" ]; then dest_dir=${SB_SYSTEM_BIN_DIR:-/usr/local/bin}; else dest_dir="$HOME/.local/bin"; fi

	case "$method" in
		deb)
			_sb_download_and_verify "$tool" "$url" "$artifact" "$tmp/pkg.deb" || return $?
			if [ "$(id -u)" != "0" ]; then
				sudo dpkg -i "$tmp/pkg.deb" || { local rc=$?; echo "Error: dpkg failed for $tool" >&2; return "$rc"; }
			else
				dpkg -i "$tmp/pkg.deb" || { local rc=$?; echo "Error: dpkg failed for $tool" >&2; return "$rc"; }
			fi
			;;
		binary)
			local bname="${binaries%%,*}"
			[ "$binaries" = "$bname" ] || { echo "Error: binary method supports one binary for $tool" >&2; return 1; }
			_sb_download_and_verify "$tool" "$url" "$artifact" "$tmp/$bname" || return $?
			if [ "$dest_type" = user ]; then
				_sb_user_tx_reset
				_sb_user_tx_add file "$tmp/$bname" "$dest_dir/$bname" || return $?
				_sb_user_tx_commit || return $?
			else
				_sb_do_install "$tmp/$bname" "$dest_dir/$bname" "$dest_type" || return $?
			fi
			;;
		tar.gz|tar.xz)
			_sb_download_and_verify "$tool" "$url" "$artifact" "$tmp/archive" || return $?
			local compression=z
			[ "$method" = "tar.xz" ] && compression=J
			_sb_extract_tar "$tool" "$tmp" "$dest_dir" "$dest_type" "$compression" "$tmp/archive" || return $?
			;;
		tar.zst)
			command -v zstd >/dev/null 2>&1 || { echo "Error: zstd is required to install $tool" >&2; return 1; }
			_sb_download_and_verify "$tool" "$url" "$artifact" "$tmp/archive.tar.zst" || return $?
			zstd -qd "$tmp/archive.tar.zst" -o "$tmp/archive.tar" || { local rc=$?; echo "Error: failed to decompress $tool archive" >&2; return "$rc"; }
			_sb_extract_tar "$tool" "$tmp" "$dest_dir" "$dest_type" "" "$tmp/archive.tar" || return $?
			;;
		zip)
			command -v unzip >/dev/null 2>&1 || { echo "Error: unzip is required to install $tool" >&2; return 1; }
			_sb_download_and_verify "$tool" "$url" "$artifact" "$tmp/archive.zip" || return $?
			local list_file="$tmp/archive.list"
			unzip -Z1 "$tmp/archive.zip" > "$list_file" || { local rc=$?; echo "Error: failed to read $tool zip" >&2; return "$rc"; }
			_sb_archive_paths_safe "$list_file" || return 1
			unzip -q "$tmp/archive.zip" -d "$tmp/extracted" || { local rc=$?; echo "Error: failed to extract $tool zip" >&2; return "$rc"; }
			_sb_extracted_tree_safe "$tmp/extracted" || return 1
			local subdir bin src
			subdir=$(_sb_resolve_arch "$SB_DPKG_ARCH" "$(sb_get "$tool" zip_subdir)") || return 1
			local -a zip_sources=() zip_names=()
			while IFS= read -r bin; do
				src="$tmp/extracted/${subdir:+$subdir/}$bin"
				_sb_require_regular_source "$src" || { echo "Error: $bin not found safely in $tool zip" >&2; return 1; }
				zip_sources+=("$src"); zip_names+=("$bin")
			done < <(printf '%s\n' "$binaries" | tr ',' '\n')
			local i
			if [ "$dest_type" = user ]; then
				_sb_user_tx_reset
				for i in "${!zip_sources[@]}"; do
					_sb_user_tx_add file "${zip_sources[$i]}" "$dest_dir/${zip_names[$i]}" || return $?
				done
				_sb_user_tx_commit || return $?
			else
				for i in "${!zip_sources[@]}"; do
					_sb_do_install "${zip_sources[$i]}" "$dest_dir/${zip_names[$i]}" "$dest_type" || return $?
				done
			fi
			;;
		tar.gz-tree)
			_sb_download_and_verify "$tool" "$url" "$artifact" "$tmp/archive.tar.gz" || return $?
			local list_file="$tmp/archive.list"
			tar ztf "$tmp/archive.tar.gz" > "$list_file" || { local rc=$?; echo "Error: failed to read $tool archive" >&2; return "$rc"; }
			_sb_archive_paths_safe "$list_file" || return 1
			mkdir -p "$tmp/extracted" || return $?
			tar xzf "$tmp/archive.tar.gz" -C "$tmp/extracted" || { local rc=$?; echo "Error: failed to extract $tool archive" >&2; return "$rc"; }
			_sb_extracted_tree_safe "$tmp/extracted" || return 1
			local tree_name tree_dest symlink
			tree_name=$(_sb_resolve_arch "$SB_DPKG_ARCH" "$(sb_get "$tool" tree_name)") || return 1
			tree_dest=$(sb_get "$tool" tree_dest) || return 1; tree_dest="${tree_dest/#\~/$HOME}"
			[ -d "$tmp/extracted/$tree_name" ] && [ ! -L "$tmp/extracted/$tree_name" ] || {
				echo "Error: managed tree source is invalid for $tool" >&2; return 1;
			}
			_sb_user_tx_reset
			_sb_user_tx_add tree "$tmp/extracted/$tree_name" "$tree_dest" || return $?
			symlink=$(sb_get "$tool" symlink) || return 1
			if [ -n "$symlink" ]; then
				symlink="${symlink/#\~/$HOME}"
				case "$symlink" in
					"$tree_dest"/*) ;;
					*) echo "Error: tree entry target is outside the managed tree for $tool" >&2; return 1 ;;
				esac
				local tree_relative=${symlink#"$tree_dest"/}
				_sb_require_regular_source "$tmp/extracted/$tree_name/$tree_relative" || {
					echo "Error: tree entry target is missing for $tool: $tree_relative" >&2; return 1;
				}
				_sb_user_tx_add symlink "$symlink" "$dest_dir/${binaries%%,*}" || return $?
			fi
			_sb_user_tx_commit || return $?
			;;
		*) echo "Error: unsupported install method for $tool: $method" >&2; return 1 ;;
	esac

}

_SB_INSTALL_LOCK_FD=""

_sb_acquire_install_lock() {
	local lock_dir=${SB_INSTALL_LOCK_DIR:-"$HOME/.cache/squarebox/artifact-install.lock"}
	command -v flock >/dev/null 2>&1 || {
		echo "Error: flock is required for serialized artifact installation" >&2
		return 1
	}
	if mkdir -p -- "$lock_dir"; then :; else
		local rc=$?; echo "Error: could not create artifact-install lock: $lock_dir" >&2; return "$rc"
	fi
	[ -d "$lock_dir" ] && [ ! -L "$lock_dir" ] || {
		echo "Error: artifact-install lock is not a safe directory: $lock_dir" >&2
		return 1
	}
	chmod 700 "$lock_dir" || {
		local rc=$?; echo "Error: could not secure artifact-install lock: $lock_dir" >&2; return "$rc"
	}
	if exec {_SB_INSTALL_LOCK_FD}< "$lock_dir"; then :; else
		local rc=$?; echo "Error: could not open artifact-install lock: $lock_dir" >&2; return "$rc"
	fi
	if flock -x "$_SB_INSTALL_LOCK_FD"; then :; else
		local rc=$?
		exec {_SB_INSTALL_LOCK_FD}>&-
		_SB_INSTALL_LOCK_FD=""
		echo "Error: could not acquire artifact-install lock: $lock_dir" >&2
		return "$rc"
	fi
}

_sb_release_install_lock() {
	[ -n "${_SB_INSTALL_LOCK_FD:-}" ] || return 0
	flock -u "$_SB_INSTALL_LOCK_FD" 2>/dev/null || true
	exec {_SB_INSTALL_LOCK_FD}>&-
	_SB_INSTALL_LOCK_FD=""
}

sb_install_transaction_pending() {
	[ "${_SB_TX_COMMITTED:-false}" = true ]
}

sb_finalize_install_transaction() {
	local rc=0
	if sb_install_transaction_pending; then
		_sb_user_tx_finalize || rc=$?
	fi
	_SB_RETAIN_INSTALL_TRANSACTION=false
	_sb_release_install_lock
	return "$rc"
}

sb_rollback_install_transaction() {
	local rc=0 last backup
	if sb_install_transaction_pending; then
		last=$((${#_SB_TX_DESTS[@]} - 1))
		if _sb_user_tx_rollback "$last"; then
			_sb_user_tx_reset
		else
			rc=$?
			_SB_TX_COMMITTED=false
			for backup in "${_SB_TX_BACKUPS[@]}"; do
				if [ -n "$backup" ] && { [ -e "$backup" ] || [ -L "$backup" ]; }; then
					echo "Original managed output backup retained at $backup" >&2
				fi
			done
		fi
		_sb_user_tx_cleanup_stages
	fi
	_SB_RETAIN_INSTALL_TRANSACTION=false
	_sb_release_install_lock
	return "$rc"
}

_sb_install_locked() {
	local tool="$1" requested="${2:-latest}" version verification
	sb_validate_tool "$tool" || return 1
	verification=$(sb_get "$tool" verification) || return 1
	if [ "$verification" = github-release-digest ]; then
		sb_prepare_release_asset "$tool" "$requested" || return $?
		version=$SB_RESOLVED_VERSION
	else
		if [ "$requested" = latest ]; then
			sb_latest_version "$tool" >/dev/null || return $?
			version=$SB_LATEST_VERSION
		else
			version=$requested
			sb_validate_version "$version" || return 1
		fi
	fi

	local method dest_type artifact url binaries tmp rc
	method=$(sb_get "$tool" method) || return 1
	dest_type=$(sb_get "$tool" dest) || return 1
	if [ "$verification" = github-release-digest ]; then
		artifact=$SB_RESOLVED_ARTIFACT
		url=$SB_RESOLVED_URL
	else
		artifact=$(sb_artifact "$tool" "$version") || return 1
		url=$(sb_url "$tool" "$version") || return 1
	fi
	binaries=$(sb_get "$tool" binaries) || return 1
	if tmp=$(mktemp -d); then :; else local tmp_rc=$?; echo "Error: failed to create install staging directory" >&2; return "$tmp_rc"; fi

	if _sb_install_pipeline "$tool" "$version" "$tmp" "$method" "$dest_type" "$artifact" "$url" "$binaries"; then
		rc=0
	else
		rc=$?
	fi
	if ! rm -rf -- "$tmp"; then
		echo "Warning: failed to clean install staging directory: $tmp" >&2
	fi
	return "$rc"
}

sb_install() {
	[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo "Error: sb_install requires TOOL [VERSION|latest]" >&2; return 2; }
	local rc
	_sb_acquire_install_lock || return $?
	if _sb_install_locked "$@"; then rc=0; else rc=$?; fi
	if [ "$rc" -ne 0 ] \
		|| [ "${_SB_RETAIN_INSTALL_TRANSACTION:-false}" != true ] \
		|| ! sb_install_transaction_pending; then
		_sb_release_install_lock
	fi
	return "$rc"
}
