#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home/squarebox" "$TMP/custom/.git" "$TMP/custom/.squarebox" "$TMP/external-workspace"
printf keep >"$TMP/home/squarebox/DO-NOT-DELETE"
printf code >"$TMP/external-workspace/project.txt"
printf '# >>> squarebox >>>\nmanaged\n# <<< squarebox <<<\n' >"$TMP/home/.bashrc"
printf '# squarebox-install-id=test-install-123\nmanaged\n' >"$TMP/home/.squarebox-shell-init"

cat >"$TMP/custom/.squarebox/install-state" <<EOF
FORMAT=1
INSTALL_ID=test-install-123
RUNTIME=docker
INSTALL_DIR=$TMP/custom
WORKSPACE_DIR=$TMP/external-workspace
GIT_CONFIG_DIR=$TMP/custom/.squarebox/identity/git
HOME_VOLUME=custom-home
CONTAINER_NAME=squarebox
IMAGE_ALIAS=squarebox
IMAGE_REPOSITORY=ghcr.io/squarewavesystems/squarebox
IMAGE_REF=ghcr.io/squarewavesystems/squarebox@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
IMAGE_ID=sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
IMAGE_DIGEST=ghcr.io/squarewavesystems/squarebox@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
SOURCE_REF=v1.1.0
SOURCE_COMMIT=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
RELEASE_TAG=v1.1.0
REQUESTED_TAG=
PUID=1000
PGID=1000
BUILD=0
EDGE=0
SHELL_INIT=$TMP/home/.squarebox-shell-init
SHELL_RC=$TMP/home/.bashrc
ORIGIN=https://github.com/SquareWaveSystems/squarebox.git
HOME_VOLUME_ADOPTED=1
EOF

cat >"$TMP/bin/git" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = -C ] && [ "$3" = remote ]; then
  count_file="$MOCK_STATE/origin-count"; count=0
  [ -f "$count_file" ] && count=$(cat "$count_file")
  count=$((count + 1)); printf '%s\n' "$count" >"$count_file"
  if [ "${FLIP_ORIGIN:-0}" = 1 ] && [ "$count" -ge 2 ]; then echo https://example.test/other.git
  else echo https://github.com/SquareWaveSystems/squarebox.git
  fi
  exit 0
fi
exit 2
EOF
cat >"$TMP/bin/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$MOCK_LOG"
label_value() {
  local kind="$1" value="$2" counter="$MOCK_STATE/$kind-label-count" count=0
  [ -f "$counter" ] && count=$(cat "$counter")
  count=$((count + 1)); printf '%s\n' "$count" >"$counter"
  case "$kind" in
    container) [ "${FAIL_CONTAINER_LABEL:-0}" != 1 ] || exit 42
      [ "${FLIP_CONTAINER_OWNER:-0}" != 1 ] || [ "$count" -lt 2 ] || value=some-other-install ;;
    volume) [ "${FAIL_VOLUME_LABEL:-0}" != 1 ] || exit 42
      [ "${FLIP_VOLUME_OWNER:-0}" != 1 ] || [ "$count" -lt 2 ] || value=some-other-install ;;
  esac
  printf '%s\n' "$value"
}
case "$1" in
  info) [ "${UNREACHABLE:-0}" != 1 ] ;;
  container) [ "$2" = inspect ] ;;
  inspect)
    if [[ "$*" == *Labels* ]]; then label_value container "${CONTAINER_OWNER:-test-install-123}"; else echo '{}'; fi ;;
  image)
    [ "$2" = inspect ] || exit 2
    if [[ "$*" == *'{{.Id}}'* ]]; then echo sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc; else echo '{}'; fi ;;
  volume)
    case "$2" in
      inspect) if [[ "$*" == *Labels* ]]; then label_value volume "${VOLUME_OWNER:-}"; else echo '{}'; fi ;;
      rm) ;;
      *) exit 2 ;;
    esac ;;
  rm|rmi) ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$TMP/bin/"*
mkdir -p "$TMP/mock-state"
export PATH="$TMP/bin:$PATH" HOME="$TMP/home" SQUAREBOX_DIR="$TMP/custom" MOCK_LOG="$TMP/runtime.log" MOCK_STATE="$TMP/mock-state"

assert_uninstall_rejects_state() {
  local name="$1" expression="$2"
  cp "$TMP/custom/.squarebox/install-state" "$TMP/state.good"
  eval "$expression"
  if "$ROOT/uninstall.sh" --yes >"$TMP/$name.out" 2>&1; then
    echo "uninstaller accepted invalid state fixture: $name" >&2; exit 1
  fi
  grep -q 'invalid Install identity\|malformed Install identity' "$TMP/$name.out"
  mv "$TMP/state.good" "$TMP/custom/.squarebox/install-state"
}
assert_uninstall_rejects_state duplicate "printf 'HOME_VOLUME=other\\n' >>\"\$TMP/custom/.squarebox/install-state\""
assert_uninstall_rejects_state unknown "printf 'DELETE_THIS=/\\n' >>\"\$TMP/custom/.squarebox/install-state\""
assert_uninstall_rejects_state missing "sed -i '/^WORKSPACE_DIR=/d' \"\$TMP/custom/.squarebox/install-state\""
assert_uninstall_rejects_state unsafe_workspace "sed -i 's#^WORKSPACE_DIR=.*#WORKSPACE_DIR=/#' \"\$TMP/custom/.squarebox/install-state\""

export CONTAINER_OWNER=some-other-install
if "$ROOT/uninstall.sh" --yes >"$TMP/owner.out" 2>&1; then
  echo 'uninstaller removed a Box owned by another identity' >&2; exit 1
fi
grep -q 'not owned by this Install identity' "$TMP/owner.out"
test -d "$TMP/custom"

export CONTAINER_OWNER=test-install-123
printf '# squarebox-install-id=other-install\n' >"$TMP/home/.squarebox-shell-init"
if "$ROOT/uninstall.sh" --yes >"$TMP/shell-owner.out" 2>&1; then
  echo 'uninstaller removed a shell adapter owned by another identity' >&2; exit 1
fi
grep -q 'shell adapter.*is not owned' "$TMP/shell-owner.out"
printf '# squarebox-install-id=test-install-123\nmanaged\n' >"$TMP/home/.squarebox-shell-init"

export UNREACHABLE=1
if "$ROOT/uninstall.sh" --yes >"$TMP/unreachable.out" 2>&1; then
  echo 'uninstaller treated an unreachable runtime as empty' >&2; exit 1
fi
grep -q 'installed but unreachable' "$TMP/unreachable.out"
unset UNREACHABLE

# A label-format query is authority, not an optional diagnostic. In particular,
# adopted resources must not turn an inspect failure into an empty-label grant.
rm -f "$MOCK_STATE/"* "$MOCK_LOG"
export FAIL_VOLUME_LABEL=1
if "$ROOT/uninstall.sh" --purge --yes --force >"$TMP/label-query.out" 2>&1; then
  echo 'uninstaller treated a failed volume-label query as an unlabeled volume' >&2; exit 1
fi
grep -q 'unable to verify ownership label' "$TMP/label-query.out"
! grep -q '^volume rm ' "$MOCK_LOG"
unset FAIL_VOLUME_LABEL

# Ownership values are byte identities. A case-folded label is another Install
# identity, even on a case-insensitive host filesystem.
rm -f "$MOCK_STATE/"* "$MOCK_LOG"
export CONTAINER_OWNER=TEST-INSTALL-123
if "$ROOT/uninstall.sh" --yes >"$TMP/case-owner.out" 2>&1; then
  echo 'uninstaller case-folded an Install identity label' >&2; exit 1
fi
grep -q 'not owned by this Install identity' "$TMP/case-owner.out"
unset CONTAINER_OWNER

# Interactive planning creates a race window. Re-read authority immediately
# before deletion and refuse a resource whose owner changed after the summary.
rm -f "$MOCK_STATE/"* "$MOCK_LOG"
export FLIP_CONTAINER_OWNER=1
if "$ROOT/uninstall.sh" --yes >"$TMP/recheck-owner.out" 2>&1; then
  echo 'uninstaller removed a Box whose owner changed after planning' >&2; exit 1
fi
grep -q 'changed ownership after confirmation' "$TMP/recheck-owner.out"
! grep -q '^rm -f ' "$MOCK_LOG"
unset FLIP_CONTAINER_OWNER
rm -f "$MOCK_STATE/"* "$MOCK_LOG"

printf 'user-before\n# >>> squarebox >>>\nmanaged\nuser-after\n' >"$TMP/home/.bashrc"
if "$ROOT/uninstall.sh" --yes >"$TMP/malformed-profile.out" 2>&1; then
  echo 'uninstaller accepted an unmatched shell-profile marker' >&2; exit 1
fi
grep -q 'malformed shell profile marker block' "$TMP/malformed-profile.out"
grep -qxF user-after "$TMP/home/.bashrc"
! grep -q '^rm -f ' "$MOCK_LOG"
printf '# >>> squarebox >>>\nmanaged\n# <<< squarebox <<<\n' >"$TMP/home/.bashrc"
rm -f "$MOCK_STATE/"* "$MOCK_LOG"

mv "$TMP/custom" "$TMP/custom-real"; ln -s "$TMP/custom-real" "$TMP/custom"
if "$ROOT/uninstall.sh" --purge --yes --force >"$TMP/symlink-purge.out" 2>&1; then
  echo 'uninstaller accepted a symlinked recorded purge path' >&2; exit 1
fi
grep -q 'purge path is a symlink\|crosses a symlinked' "$TMP/symlink-purge.out"
test -f "$TMP/custom-real/.squarebox/install-state"
rm "$TMP/custom"; mv "$TMP/custom-real" "$TMP/custom"

rm -f "$MOCK_STATE/"* "$MOCK_LOG"
export FLIP_ORIGIN=1
if "$ROOT/uninstall.sh" --purge --yes --force >"$TMP/origin-recheck.out" 2>&1; then
  echo 'uninstaller failed to revalidate checkout origin after planning' >&2; exit 1
fi
grep -q 'expected origin' "$TMP/origin-recheck.out"
! grep -q '^rm -f \|^volume rm ' "$MOCK_LOG"
unset FLIP_ORIGIN
rm -f "$MOCK_STATE/"* "$MOCK_LOG"

if "$ROOT/uninstall.sh" --purge --yes >"$TMP/force.out" 2>&1; then
  echo 'uninstaller purged an adopted unlabeled volume without --force' >&2; exit 1
fi
grep -q -- '--force is required' "$TMP/force.out"
test -d "$TMP/custom"

"$ROOT/uninstall.sh" --purge --yes --force
test ! -e "$TMP/custom"
test -f "$TMP/home/squarebox/DO-NOT-DELETE"
test -f "$TMP/external-workspace/project.txt"
test ! -e "$TMP/home/.squarebox-shell-init"
! grep -qF '# >>> squarebox >>>' "$TMP/home/.bashrc"
grep -q '^rm -f squarebox$' "$TMP/runtime.log"
grep -q '^rmi squarebox$' "$TMP/runtime.log"
grep -q '^volume rm custom-home$' "$TMP/runtime.log"

echo 'ok - lifecycle deletion requires identity, reachability, adoption force, and recorded paths'
