#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DOCKERFILE="$ROOT/Dockerfile"
EXPECTED_IMAGE='ghcr.io/charmbracelet/gum@sha256:426c1e40739f11083e06d58ffaac910289eeace709a3d9bddcb8d4566140c93c'

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

mapfile -t gum_images < <(sed -n 's/^ARG GUM_IMAGE=//p' "$DOCKERFILE")
[ "${#gum_images[@]}" -eq 1 ] || fail "Dockerfile must declare exactly one Gum OCI image"
[ "${gum_images[0]}" = "$EXPECTED_IMAGE" ] \
	|| fail "Gum OCI image must remain pinned to the reviewed multi-architecture digest"
[[ "${gum_images[0]}" =~ ^ghcr\.io/charmbracelet/gum@sha256:[0-9a-f]{64}$ ]] \
	|| fail "Gum OCI image must not use a mutable tag"

grep -Fqx 'FROM ${GUM_IMAGE} AS gum-source' "$DOCKERFILE" \
	|| fail "Dockerfile does not consume the pinned Gum manifest"
grep -Fqx 'COPY --from=gum-source /usr/local/bin/gum /usr/local/bin/gum' "$DOCKERFILE" \
	|| fail "Gum binary is not copied from the pinned upstream image"
grep -Fqx 'ARG GUM_EXPECTED_VERSION=v0.17.1-devel' "$DOCKERFILE" \
	|| fail "expected Gum development version is not explicit"
grep -Fqx 'ARG GUM_EXPECTED_COMMIT=591ded2' "$DOCKERFILE" \
	|| fail "expected Gum source commit is not explicit"
grep -Fq 'gum version ${GUM_EXPECTED_VERSION} (${GUM_EXPECTED_COMMIT})' "$DOCKERFILE" \
	|| fail "image build does not assert Gum version and commit identity"

if grep -Eq '^ARG GUM_VERSION=|sb_install gum' "$DOCKERFILE"; then
	fail "obsolete Gum release-tar install path remains in Dockerfile"
fi
if grep -Eq '^  gum:|gum_[^ ]*Linux_(x86_64|arm64)[.]tar[.]gz' \
	"$ROOT/scripts/lib/tools.yaml" "$ROOT/checksums.txt"; then
	fail "obsolete Gum release-tar registry or checksum metadata remains"
fi

echo "PASS: Gum uses the reviewed immutable OCI manifest and asserted build identity"
