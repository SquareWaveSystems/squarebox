#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/release-identity.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

sha=0123456789abcdef0123456789abcdef01234567
digest=sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef

"$SCRIPT" inspect v1.1.0 | jq -e '.prerelease == false and .source_ref == "v1.1.0"' >/dev/null
"$SCRIPT" inspect v1.1.0-rc5 | jq -e '.prerelease == true' >/dev/null

for invalid in 1.1.0 v1.1 v1.01.0 v1.1.0- v1.1.0_rc1 v1.1.0-01 v1.1.0-rc..1 v1.1.0+ v1.1.0+build-1 v1.1.0-rc.1+build-1; do
	if "$SCRIPT" inspect "$invalid" >/dev/null 2>&1; then
		echo "FAIL: accepted invalid version $invalid" >&2
		exit 1
	fi
done

long_version="v1.1.0-$(printf 'a%.0s' {1..122})"
if "$SCRIPT" inspect "$long_version" >/dev/null 2>&1; then
	echo "FAIL: accepted a release version longer than the OCI tag limit" >&2
	exit 1
fi

"$SCRIPT" create "$TMP/release.json" v1.1.0-rc5 "$sha" \
	ghcr.io/squarewavesystems/squarebox "$digest"
"$SCRIPT" verify "$TMP/release.json"
jq -e --arg digest "$digest" '
	.version == "v1.1.0-rc5" and
	.prerelease == true and
	.source_ref == .version and
	.image_digest == $digest and
	.image_ref == ("ghcr.io/squarewavesystems/squarebox@" + $digest)
' "$TMP/release.json" >/dev/null

jq '.image_digest = "sha256:bad"' "$TMP/release.json" > "$TMP/bad.json"
if "$SCRIPT" verify "$TMP/bad.json"; then
	echo "FAIL: accepted malformed release identity" >&2
	exit 1
fi

echo "PASS: release identity validates publishable versions and binds source to image digest"
