#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home"

cat >"$TMP/bin/git" <<'EOF'
#!/usr/bin/env bash
set -e
if [ "$1" = clone ]; then
  target="${@: -1}"; mkdir -p "$target/.git" "$target/dotfiles"
  printf '# mock\n' >"$target/dotfiles/bashrc"; printf 'x\n' >"$target/starship.toml"
  exit 0
fi
if [ "$1" = -C ]; then
  shift 2
  case "$1" in
    rev-parse) echo aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ;;
    checkout|fetch|reset) ;;
    remote) echo https://github.com/SquareWaveSystems/squarebox.git ;;
    *) exit 0 ;;
  esac
  exit 0
fi
if [ "$1" = config ]; then exit 0; fi
exit 2
EOF

cat >"$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -e
out=''; url=''
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;; -H|--retry|--connect-timeout) shift 2 ;; -*) shift ;; *) url="$1"; shift ;;
  esac
done
if [[ "$url" != */release.json ]]; then printf '{\n  "tag_name": "%s"\n}\n' "${MOCK_RELEASE_TAG:-v1.1.0}"; exit 0; fi
if [ "$MOCK_MANIFEST" = missing ]; then exit 22; fi
cat >"$out" <<JSON
{
  "schema": 1,
  "version": "v1.1.0",
  "source_ref": "v1.1.0",
  "source_sha": "cccccccccccccccccccccccccccccccccccccccc",
  "image_repository": "ghcr.io/squarewavesystems/squarebox",
  "image_digest": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
  "image_ref": "ghcr.io/squarewavesystems/squarebox@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
}
JSON
EOF
chmod +x "$TMP/bin/"*
export PATH="$TMP/bin:$PATH" HOME="$TMP/home" SHELL=/bin/bash SQUAREBOX_TAG=v1.1.0

# Stable discovery is untrusted input too: a malformed latest tag must fail
# before it can influence a checkout, URL, or image reference.
long_tag="v1.1.0-$(printf 'a%.0s' {1..122})"
for invalid_tag in v1.1.0-01 v1.1.0+build-1 "$long_tag"; do
  export MOCK_RELEASE_TAG="$invalid_tag" SQUAREBOX_TAG=latest SQUAREBOX_DIR="$TMP/invalid-latest-${invalid_tag//[^A-Za-z0-9]/-}"
  if "$ROOT/install.sh" </dev/null >"$TMP/invalid-latest.out" 2>&1; then
    echo "installer accepted an unpublishable latest Release tag: $invalid_tag" >&2; exit 1
  fi
  grep -q 'invalid published Release tag' "$TMP/invalid-latest.out"
  test ! -e "$SQUAREBOX_DIR"
done
unset MOCK_RELEASE_TAG

export MOCK_MANIFEST=missing SQUAREBOX_TAG=v1.1.0 SQUAREBOX_DIR="$TMP/missing-manifest"
if "$ROOT/install.sh" </dev/null >"$TMP/missing.out" 2>&1; then
  echo 'installer accepted a v1.1 Release without release.json' >&2; exit 1
fi
grep -q 'no verifiable release.json' "$TMP/missing.out"
test ! -e "$SQUAREBOX_DIR"

export MOCK_MANIFEST=mismatch SQUAREBOX_DIR="$TMP/mismatched-source"
if "$ROOT/install.sh" </dev/null >"$TMP/mismatch.out" 2>&1; then
  echo 'installer accepted source that differs from release.json' >&2; exit 1
fi
grep -q 'checked-out source does not match release.json' "$TMP/mismatch.out"
test ! -e "$SQUAREBOX_DIR"

# Compatibility is intentionally narrow and stable discovery never sorts raw
# local tags (which can exist before publication has completed).
grep -q 'v1\.0\.0|v1\.0\.0-rc\*' "$ROOT/install.sh"
! grep -q 'tag --sort' "$ROOT/install.sh"

echo 'ok - lifecycle release identity fails closed outside explicit v1.0 compatibility'
