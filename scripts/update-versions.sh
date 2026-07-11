#!/usr/bin/env bash
set -uo pipefail

# Refresh image-tier versions as one serialized transaction. Exact GitHub
# release-asset digests, downloaded bytes, registry mappings, and generated
# files are validated in a private workspace before either tracked destination
# is replaced. Concurrent edits abort the run; destination-local originals make
# rollback a same-filesystem rename rather than a fallible copy-over write.

REPO_ROOT=${SB_REPO_ROOT:-"$(cd "$(dirname "$0")/.." && pwd)"}
DOCKERFILE=${SB_DOCKERFILE:-"${REPO_ROOT}/Dockerfile"}
CHECKSUMS=${SB_CHECKSUMS_FILE:-"${REPO_ROOT}/checksums.txt"}
TOOLS_YAML=${SB_TOOLS_YAML:-"${REPO_ROOT}/scripts/lib/tools.yaml"}
TOOL_LIB=${SB_TOOL_LIB:-"${REPO_ROOT}/scripts/lib/tool-lib.sh"}

WORK=$(mktemp -d) || { echo "Error: could not create refresh workspace" >&2; exit 1; }
COMMITTING=false
BACKUP_DOCKERFILE=""
BACKUP_CHECKSUMS=""
CHECKSUM_STAGE=""
DOCKER_STAGE=""
REFRESH_LOCK_FD=""
INITIAL_DOCKERFILE_SHA=""
INITIAL_CHECKSUMS_SHA=""

cleanup() {
	local rc=$?
	trap - EXIT HUP INT TERM
	local rollback_failed=false
	if [ "$COMMITTING" = true ]; then
		if [ -n "$BACKUP_DOCKERFILE" ]; then
			if [ -f "$BACKUP_DOCKERFILE" ] \
				&& /bin/mv -fT -- "$BACKUP_DOCKERFILE" "$DOCKERFILE" 2>/dev/null; then
				BACKUP_DOCKERFILE=""
			else
				rollback_failed=true
			fi
		fi
		if [ -n "$BACKUP_CHECKSUMS" ]; then
			if [ -f "$BACKUP_CHECKSUMS" ] \
				&& /bin/mv -fT -- "$BACKUP_CHECKSUMS" "$CHECKSUMS" 2>/dev/null; then
				BACKUP_CHECKSUMS=""
			else
				rollback_failed=true
			fi
		fi
		if [ "$rollback_failed" = true ]; then
			echo "CRITICAL: version-refresh rollback was incomplete; inspect Dockerfile and checksums.txt before continuing." >&2
			[ -z "$BACKUP_DOCKERFILE" ] || echo "Original Dockerfile backup retained at $BACKUP_DOCKERFILE" >&2
			[ -z "$BACKUP_CHECKSUMS" ] || echo "Original checksum backup retained at $BACKUP_CHECKSUMS" >&2
			rc=1
		fi
	fi
	[ -z "$CHECKSUM_STAGE" ] || rm -f -- "$CHECKSUM_STAGE" 2>/dev/null || true
	[ -z "$DOCKER_STAGE" ] || rm -f -- "$DOCKER_STAGE" 2>/dev/null || true
	if [ "$rollback_failed" = false ]; then
		[ -z "$BACKUP_CHECKSUMS" ] || rm -f -- "$BACKUP_CHECKSUMS" 2>/dev/null || true
		[ -z "$BACKUP_DOCKERFILE" ] || rm -f -- "$BACKUP_DOCKERFILE" 2>/dev/null || true
	fi
	rm -rf -- "$WORK" 2>/dev/null || true
	if [ -n "$REFRESH_LOCK_FD" ]; then
		flock -u "$REFRESH_LOCK_FD" 2>/dev/null || true
		exec {REFRESH_LOCK_FD}>&-
		REFRESH_LOCK_FD=""
	fi
	exit "$rc"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

for command_name in curl jq sha256sum awk sed flock; do
	command -v "$command_name" >/dev/null 2>&1 || {
		echo "Error: required command is unavailable: $command_name" >&2
		exit 1
	}
done
[ -r "$TOOL_LIB" ] || { echo "Error: tool library is not readable: $TOOL_LIB" >&2; exit 1; }
[ -f "$DOCKERFILE" ] || { echo "Error: Dockerfile is missing: $DOCKERFILE" >&2; exit 1; }
[ -f "$CHECKSUMS" ] || { echo "Error: checksum manifest is missing: $CHECKSUMS" >&2; exit 1; }
[ -d "$REPO_ROOT" ] && [ ! -L "$REPO_ROOT" ] || {
	echo "Error: repository root is not a safe directory: $REPO_ROOT" >&2
	exit 1
}
if exec {REFRESH_LOCK_FD}< "$REPO_ROOT"; then :; else
	rc=$?; echo "Error: could not open repository refresh lock: $REPO_ROOT" >&2; exit "$rc"
fi
if flock -x "$REFRESH_LOCK_FD"; then :; else
	rc=$?; echo "Error: could not acquire repository refresh lock: $REPO_ROOT" >&2; exit "$rc"
fi
INITIAL_DOCKERFILE_SHA=$(sha256sum -- "$DOCKERFILE" | awk '{print $1}') || exit $?
INITIAL_CHECKSUMS_SHA=$(sha256sum -- "$CHECKSUMS" | awk '{print $1}') || exit $?

export SB_TOOLS_YAML="$TOOLS_YAML"
export SB_GH_METADATA_CACHE_DIR="$WORK/github-release-metadata"
# shellcheck source=scripts/lib/tool-lib.sh
source "$TOOL_LIB"
sb_validate_registry || exit $?

mapfile -t IMAGE_TOOLS < <(sb_list_group dockerfile)
[ "${#IMAGE_TOOLS[@]}" -gt 0 ] || { echo "Error: no Dockerfile-tier tools in registry" >&2; exit 1; }

declare -A VERSIONS=()
declare -A ARTIFACTS=()
declare -A HASHES=()
declare -A SEEN_ARTIFACTS=()

echo "Fetching latest release metadata (Dockerfile tier)..."
for tool in "${IMAGE_TOOLS[@]}"; do
	if version=$(sb_latest_version "$tool"); then
		VERSIONS[$tool]=$version
	else
		rc=$?
		echo "Error: could not resolve latest version for $tool" >&2
		exit "$rc"
	fi
done

echo
echo "Versions:"
for tool in "${IMAGE_TOOLS[@]}"; do
	printf '  %-12s %s\n' "$tool" "${VERSIONS[$tool]}"
done

mkdir -p "$WORK/downloads" || exit 1
echo
echo "Downloading and hashing both supported architectures..."
for tool in "${IMAGE_TOOLS[@]}"; do
	version=${VERSIONS[$tool]}
	for arch in amd64 arm64; do
		artifact=$(sb_artifact "$tool" "$version" "$arch") || exit $?
		url=$(sb_url "$tool" "$version" "$arch") || exit $?
		if sb_prepare_release_asset "$tool" "$version" "$arch"; then :; else
			rc=$?; echo "Error: could not resolve exact release asset for $tool/$arch" >&2; exit "$rc"
		fi
		[ "$SB_RESOLVED_TOOL" = "$tool" ] \
			&& [ "$SB_RESOLVED_VERSION" = "$version" ] \
			&& [ "$SB_RESOLVED_ARTIFACT" = "$artifact" ] \
			&& [ "$SB_RESOLVED_URL" = "$url" ] \
			&& [[ "$SB_EXPECTED_ASSET_SHA256" =~ ^[0-9a-f]{64}$ ]] || {
			echo "Error: inconsistent release-asset identity for $tool/$arch" >&2
			exit 1
		}
		if [ -n "${SEEN_ARTIFACTS[$artifact]+x}" ]; then
			echo "Error: duplicate artifact filename in registry: $artifact" >&2
			exit 1
		fi
		SEEN_ARTIFACTS[$artifact]="$tool/$arch"
		download="$WORK/downloads/${tool}-${arch}"
		if curl -fsSLo "$download" "$url"; then
			:
		else
			rc=$?
			echo "Error: failed to download $tool/$arch: $url" >&2
			exit "$rc"
		fi
		[ -s "$download" ] || { echo "Error: empty artifact for $tool/$arch" >&2; exit 1; }
		if hash_line=$(sha256sum -- "$download"); then
			hash=${hash_line%% *}
		else
			rc=$?; echo "Error: failed to hash $tool/$arch" >&2; exit "$rc"
		fi
		[[ "$hash" =~ ^[0-9a-f]{64}$ ]] || { echo "Error: invalid SHA256 for $tool/$arch" >&2; exit 1; }
		[ "$hash" = "$SB_EXPECTED_ASSET_SHA256" ] || {
			echo "Error: GitHub release-asset digest mismatch for $tool/$arch ($artifact)" >&2
			echo "  expected: $SB_EXPECTED_ASSET_SHA256" >&2
			echo "  actual:   $hash" >&2
			exit 1
		}
		ARTIFACTS["$tool/$arch"]=$artifact
		HASHES["$tool/$arch"]=$hash
		printf '  %-12s %-5s %s  %s\n' "$tool" "$arch" "$hash" "$artifact"
	done
done

NEW_CHECKSUMS="$WORK/checksums.txt"
{
	printf '%s\n' '# SHA256 checksums for Dockerfile binary tool downloads.'
	printf '%s\n' '# Format: sha256  filename'
	printf '%s\n' '# Generated by scripts/update-versions.sh — do not edit manually.'
	printf '\n'
	for tool in "${IMAGE_TOOLS[@]}"; do
		display=${tool//-/ }
		printf '# %s %s\n' "${display^}" "${VERSIONS[$tool]}"
		for arch in amd64 arm64; do
			printf '%s  %s\n' "${HASHES[$tool/$arch]}" "${ARTIFACTS[$tool/$arch]}"
		done
	done
} > "$NEW_CHECKSUMS" || { echo "Error: failed to generate checksum manifest" >&2; exit 1; }

expected_entries=$((${#IMAGE_TOOLS[@]} * 2))
actual_entries=$(awk '$1 ~ /^[0-9a-f]{64}$/ && NF == 2 { count++ } END { print count + 0 }' "$NEW_CHECKSUMS")
[ "$actual_entries" -eq "$expected_entries" ] || {
	echo "Error: generated checksum manifest has $actual_entries entries; expected $expected_entries" >&2
	exit 1
}

NEW_DOCKERFILE="$WORK/Dockerfile"
cp -p -- "$DOCKERFILE" "$NEW_DOCKERFILE" || { echo "Error: failed to stage Dockerfile" >&2; exit 1; }
for tool in "${IMAGE_TOOLS[@]}"; do
	arg=$(sb_get "$tool" docker_arg) || exit $?
	count=$(awk -v prefix="ARG ${arg}=" 'index($0, prefix) == 1 { count++ } END { print count + 0 }' "$NEW_DOCKERFILE")
	[ "$count" -eq 1 ] || {
		echo "Error: expected exactly one ARG ${arg}= line in Dockerfile; found $count" >&2
		exit 1
	}
	if ! sed -i "s|^ARG ${arg}=.*|ARG ${arg}=${VERSIONS[$tool]}|" "$NEW_DOCKERFILE"; then
		echo "Error: failed to stage Docker ARG $arg" >&2
		exit 1
	fi
	docker_value=$(awk -v prefix="ARG ${arg}=" 'index($0, prefix) == 1 { print substr($0, length(prefix) + 1) }' "$NEW_DOCKERFILE")
	[ "$docker_value" = "${VERSIONS[$tool]}" ] || {
		echo "Error: Docker ARG validation failed for $tool" >&2
		exit 1
	}
done

# Prepare destination-local stages and backups so both promotion and rollback
# use same-filesystem renames. A failed copy-over rollback must never leave a
# new checksum manifest paired with an old Dockerfile (or vice versa).
case "$CHECKSUMS" in */*) CHECKSUM_PARENT=${CHECKSUMS%/*} ;; *) CHECKSUM_PARENT=. ;; esac
case "$DOCKERFILE" in */*) DOCKER_PARENT=${DOCKERFILE%/*} ;; *) DOCKER_PARENT=. ;; esac
CHECKSUM_BASE=${CHECKSUMS##*/}
DOCKER_BASE=${DOCKERFILE##*/}
CHECKSUM_STAGE=$(mktemp "${CHECKSUM_PARENT}/.${CHECKSUM_BASE}.squarebox.XXXXXX") || exit 1
DOCKER_STAGE=$(mktemp "${DOCKER_PARENT}/.${DOCKER_BASE}.squarebox.XXXXXX") || { rm -f -- "$CHECKSUM_STAGE"; exit 1; }
cp -p -- "$NEW_CHECKSUMS" "$CHECKSUM_STAGE" || exit 1
cp -p -- "$NEW_DOCKERFILE" "$DOCKER_STAGE" || exit 1
chmod --reference="$CHECKSUMS" "$CHECKSUM_STAGE" || exit 1
chmod --reference="$DOCKERFILE" "$DOCKER_STAGE" || exit 1

CURRENT_DOCKERFILE_SHA=$(sha256sum -- "$DOCKERFILE" | awk '{print $1}') || exit $?
CURRENT_CHECKSUMS_SHA=$(sha256sum -- "$CHECKSUMS" | awk '{print $1}') || exit $?
if [ "$CURRENT_DOCKERFILE_SHA" != "$INITIAL_DOCKERFILE_SHA" ] \
	|| [ "$CURRENT_CHECKSUMS_SHA" != "$INITIAL_CHECKSUMS_SHA" ]; then
	echo "Error: Dockerfile or checksums.txt changed during version refresh; preserving the concurrent edits." >&2
	exit 1
fi

BACKUP_CHECKSUMS=$(mktemp "${CHECKSUM_PARENT}/.${CHECKSUM_BASE}.squarebox-backup.XXXXXX") || exit 1
BACKUP_DOCKERFILE=$(mktemp "${DOCKER_PARENT}/.${DOCKER_BASE}.squarebox-backup.XXXXXX") || exit 1
cp -p -- "$CHECKSUMS" "$BACKUP_CHECKSUMS" || exit 1
cp -p -- "$DOCKERFILE" "$BACKUP_DOCKERFILE" || exit 1
BACKUP_CHECKSUMS_SHA=$(sha256sum -- "$BACKUP_CHECKSUMS" | awk '{print $1}') || exit $?
BACKUP_DOCKERFILE_SHA=$(sha256sum -- "$BACKUP_DOCKERFILE" | awk '{print $1}') || exit $?
if [ "$BACKUP_CHECKSUMS_SHA" != "$INITIAL_CHECKSUMS_SHA" ] \
	|| [ "$BACKUP_DOCKERFILE_SHA" != "$INITIAL_DOCKERFILE_SHA" ]; then
	echo "Error: tracked inputs changed while preparing rollback backups; preserving the concurrent edits." >&2
	exit 1
fi

COMMITTING=true
if mv -fT -- "$CHECKSUM_STAGE" "$CHECKSUMS"; then
	CHECKSUM_STAGE=""
	:
else
	rc=$?; echo "Error: failed to replace checksum manifest" >&2; exit "$rc"
fi
if mv -fT -- "$DOCKER_STAGE" "$DOCKERFILE"; then
	DOCKER_STAGE=""
	:
else
	rc=$?; echo "Error: failed to replace Dockerfile; restoring originals" >&2; exit "$rc"
fi
COMMITTING=false

echo
echo "Version refresh complete. Review changes with: git diff -- Dockerfile checksums.txt"
