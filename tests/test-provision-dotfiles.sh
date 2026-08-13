#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); printf 'ok %d - %s\n' "$((PASS + FAIL))" "$1"; }
not_ok() { FAIL=$((FAIL + 1)); printf 'not ok %d - %s\n' "$((PASS + FAIL))" "$1"; }
assert_true() { if eval "$1"; then ok "$2"; else not_ok "$2"; fi; }

SRC="$TMP/source"
HOME_DIR="$TMP/home"
OUTSIDE="$TMP/outside"
mkdir -p "$SRC" "$HOME_DIR" "$OUTSIDE"
printf 'managed bashrc\n' > "$SRC/bashrc"
printf 'managed starship\n' > "$SRC/starship.toml"

SQUAREBOX_DOTFILES_SOURCE="$SRC" SQUAREBOX_MANAGED_HOME="$HOME_DIR" \
	bash "$ROOT/scripts/squarebox-refresh-dotfiles.sh"
assert_true "[ \"\$(cat '$HOME_DIR/.bashrc')\" = 'managed bashrc' ]" "managed bashrc refreshes into the Managed home"
assert_true "[ \"\$(cat '$HOME_DIR/.config/starship.toml')\" = 'managed starship' ]" "managed starship config refreshes into the Managed home"

rm -rf "$HOME_DIR/.config"
printf 'outside sentinel\n' > "$OUTSIDE/starship.toml"
ln -s "$OUTSIDE" "$HOME_DIR/.config"
set +e
SQUAREBOX_DOTFILES_SOURCE="$SRC" SQUAREBOX_MANAGED_HOME="$HOME_DIR" \
	bash "$ROOT/scripts/squarebox-refresh-dotfiles.sh" >"$TMP/symlink.out" 2>"$TMP/symlink.err"
RC=$?
set -e
assert_true "[ '$RC' -ne 0 ]" "refresh rejects a symlinked destination parent"
assert_true "[ \"\$(cat '$OUTSIDE/starship.toml')\" = 'outside sentinel' ]" "symlink rejection cannot overwrite an outside target"
assert_true "grep -q 'refusing to refresh symlinked dotfile destination' '$TMP/symlink.err'" "symlink rejection is visible"

set +e
SQUAREBOX_DOTFILES_SOURCE="$SRC" SQUAREBOX_MANAGED_HOME="$HOME_DIR" \
	bash "$ROOT/scripts/squarebox-refresh-dotfiles.sh" not-an-owner >/dev/null 2>"$TMP/owner.err"
RC=$?
set -e
assert_true "[ '$RC' -eq 2 ] && grep -q 'invalid dotfile owner' '$TMP/owner.err'" "refresh validates its optional uid:gid owner"

printf '1..%d\n' "$((PASS + FAIL))"
[ "$FAIL" -eq 0 ]
