#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat >&2 <<'EOF'
Usage:
  release-identity.sh inspect <vMAJOR.MINOR.PATCH[-prerelease]>
  release-identity.sh create <output.json> <vMAJOR.MINOR.PATCH[-prerelease]> <source-sha> <image-repository> <sha256-digest>
  release-identity.sh verify <release.json>
EOF
	exit 2
}

validate_version() {
	local version="$1" prerelease identifier
	# Squarebox release tags deliberately exclude SemVer build metadata: `+` is
	# not valid in an OCI tag, and build metadata has no precedence with which
	# to select one authoritative GitHub/GHCR "latest" release.
	[ "${#version}" -le 128 ] \
		&& [[ "$version" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$ ]] || {
		echo "Invalid release version: $version" >&2
		return 1
	}
	[[ "$version" == *-* ]] || return 0
	prerelease=${version#*-}
	while IFS= read -r identifier; do
		if [[ "$identifier" =~ ^[0-9]+$ ]] && [ "${#identifier}" -gt 1 ] && [[ "$identifier" == 0* ]]; then
			echo "Invalid release version: $version" >&2
			return 1
		fi
	done < <(printf '%s\n' "$prerelease" | tr '.' '\n')
}

is_prerelease() {
	[[ "$1" == *-* ]]
}

inspect() {
	local version="$1" prerelease=false
	validate_version "$version"
	is_prerelease "$version" && prerelease=true
	jq -cn \
		--arg version "$version" \
		--argjson prerelease "$prerelease" \
		'{version: $version, source_ref: $version, prerelease: $prerelease}'
}

create_identity() {
	local output="$1" version="$2" source_sha="$3" image_repository="$4" image_digest="$5"
	local prerelease=false output_dir tmp
	validate_version "$version"
	[[ "$source_sha" =~ ^[0-9a-f]{40}$ ]] || {
		echo "Invalid source SHA: $source_sha" >&2
		return 1
	}
	[[ "$image_repository" =~ ^[a-z0-9][a-z0-9._/-]*$ ]] || {
		echo "Invalid image repository: $image_repository" >&2
		return 1
	}
	[[ "$image_digest" =~ ^sha256:[0-9a-f]{64}$ ]] || {
		echo "Invalid image digest: $image_digest" >&2
		return 1
	}
	is_prerelease "$version" && prerelease=true

	output_dir=$(dirname "$output")
	mkdir -p "$output_dir"
	tmp=$(mktemp "$output_dir/.release-identity.XXXXXX")
	trap 'rm -f "$tmp"' EXIT
	jq -n \
		--argjson schema 1 \
		--arg version "$version" \
		--argjson prerelease "$prerelease" \
		--arg source_sha "$source_sha" \
		--arg source_ref "$version" \
		--arg image_repository "$image_repository" \
		--arg image_digest "$image_digest" \
		'{
			schema: $schema,
			version: $version,
			prerelease: $prerelease,
			source_sha: $source_sha,
			source_ref: $source_ref,
			image_repository: $image_repository,
			image_digest: $image_digest,
			image_ref: ($image_repository + "@" + $image_digest)
		}' > "$tmp"
	mv -f "$tmp" "$output"
	trap - EXIT
}

verify_identity() {
	local file="$1" version expected_prerelease=false
	version=$(jq -er '.version | select(type == "string")' "$file") || return 1
	validate_version "$version" || return 1
	is_prerelease "$version" && expected_prerelease=true
	jq -e --arg version "$version" --argjson expected_prerelease "$expected_prerelease" '
		.schema == 1 and
		(.version == $version) and
		(.prerelease | type == "boolean") and
		(.source_sha | type == "string" and test("^[0-9a-f]{40}$")) and
		(.source_ref == .version) and
		(.image_repository | type == "string" and test("^[a-z0-9][a-z0-9._/-]*$")) and
		(.image_digest | type == "string" and test("^sha256:[0-9a-f]{64}$")) and
		(.image_ref == (.image_repository + "@" + .image_digest)) and
		(.prerelease == $expected_prerelease)
	' "$file" >/dev/null
}

case "${1:-}" in
	inspect)
		[ "$#" -eq 2 ] || usage
		inspect "$2"
		;;
	create)
		[ "$#" -eq 6 ] || usage
		create_identity "$2" "$3" "$4" "$5" "$6"
		;;
	verify)
		[ "$#" -eq 2 ] || usage
		verify_identity "$2"
		;;
	*) usage ;;
esac
