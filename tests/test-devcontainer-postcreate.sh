#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

STATE="$TMP/state"
HOME_DIR="$TMP/home"
FAKE_SETUP="$TMP/setup.sh"
mkdir -p "$STATE" "$HOME_DIR"

cat > "$FAKE_SETUP" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "$SQUAREBOX_FAKE_SETUP_CALL"
# Model independent setup outcomes: assistant failed and was not committed;
# SDK succeeded and remains observed/selected.
: > "$SQUAREBOX_STATE_DIR/ai-tool"
printf 'node\n' > "$SQUAREBOX_STATE_DIR/sdks"
exit 42
EOF
chmod +x "$FAKE_SETUP"

# Workspace Selection state is untrusted repository content. Reject both a
# redirected directory and a broken known-file symlink before seeding or setup.
OUTSIDE_STATE="$TMP/outside-state"
LINKED_STATE="$TMP/linked-state"
mkdir -p "$OUTSIDE_STATE"
ln -s "$OUTSIDE_STATE" "$LINKED_STATE"
if HOME="$HOME_DIR" SQUAREBOX_STATE_DIR="$LINKED_STATE/" \
	SQUAREBOX_SETUP_SCRIPT="$FAKE_SETUP" SQUAREBOX_FAKE_SETUP_CALL="$TMP/symlink-dir.call" \
	SQUAREBOX_DC_AI=claude SQUAREBOX_DC_SDKS=node \
	bash "$ROOT/scripts/devcontainer-postcreate.sh" >"$TMP/symlink-dir.out" 2>&1; then
	echo "FAIL: post-create followed a symlinked Selection directory" >&2
	exit 1
fi
grep -q 'Selection state directory must not be a symlink' "$TMP/symlink-dir.out"
test ! -e "$OUTSIDE_STATE/ai-tool"
test ! -e "$TMP/symlink-dir.call"

BROKEN_STATE="$TMP/broken-state"
BROKEN_TARGET="$TMP/missing-selection-target"
mkdir -p "$BROKEN_STATE"
ln -s "$BROKEN_TARGET" "$BROKEN_STATE/ai-tool"
if HOME="$HOME_DIR" SQUAREBOX_STATE_DIR="$BROKEN_STATE" \
	SQUAREBOX_SETUP_SCRIPT="$FAKE_SETUP" SQUAREBOX_FAKE_SETUP_CALL="$TMP/symlink-file.call" \
	SQUAREBOX_DC_AI=claude SQUAREBOX_DC_SDKS=node \
	bash "$ROOT/scripts/devcontainer-postcreate.sh" >"$TMP/symlink-file.out" 2>&1; then
	echo "FAIL: post-create followed a broken Selection-file symlink" >&2
	exit 1
fi
grep -q 'Selection state file must not be a symlink' "$TMP/symlink-file.out"
test -L "$BROKEN_STATE/ai-tool"
test ! -e "$BROKEN_TARGET"
test ! -e "$TMP/symlink-file.call"

if HOME="$HOME_DIR" SQUAREBOX_STATE_DIR="$STATE" \
	SQUAREBOX_SETUP_SCRIPT="$FAKE_SETUP" \
	SQUAREBOX_FAKE_SETUP_CALL="$TMP/setup.call" \
	SQUAREBOX_DC_AI=claude SQUAREBOX_DC_SDKS=node \
	SQUAREBOX_DC_EDITORS= SQUAREBOX_DC_TUIS= \
	bash "$ROOT/scripts/devcontainer-postcreate.sh" >"$TMP/failure.out" 2>&1; then
	echo "FAIL: post-create accepted a failed setup" >&2
	exit 1
fi
grep -qx -- '--rerun ai sdks' "$TMP/setup.call"
test -f "$STATE/ai-tool" && test ! -s "$STATE/ai-tool"
grep -qx node "$STATE/sdks"
test ! -e "$HOME_DIR/.squarebox-setup-done"

# Existing user choices win over defaults and are still passed for reconcile.
printf 'python\n' > "$STATE/sdks"
cat > "$FAKE_SETUP" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
grep -qx python "$SQUAREBOX_STATE_DIR/sdks"
EOF
chmod +x "$FAKE_SETUP"
HOME="$HOME_DIR" SQUAREBOX_STATE_DIR="$STATE" \
	SQUAREBOX_SETUP_SCRIPT="$FAKE_SETUP" \
	SQUAREBOX_DC_AI= SQUAREBOX_DC_SDKS=node \
	SQUAREBOX_DC_EDITORS= SQUAREBOX_DC_TUIS= \
	bash "$ROOT/scripts/devcontainer-postcreate.sh" >"$TMP/success.out" 2>&1
grep -qx python "$STATE/sdks"
test -e "$HOME_DIR/.squarebox-setup-done"

echo "PASS: Dev Container provisioning preserves independent section outcomes and prior Selections"
