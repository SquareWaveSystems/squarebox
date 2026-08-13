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
[ ! -t 0 ]
if IFS= read -r _unexpected_input; then exit 97; fi
printf '%s\n' "$*" > "$SQUAREBOX_FAKE_SETUP_CALL"
# Model independent setup outcomes: assistant failed and was not committed;
# SDK and multiplexer succeeded and remain observed/selected.
: > "$SQUAREBOX_STATE_DIR/ai-tool"
printf 'node\n' > "$SQUAREBOX_STATE_DIR/sdks"
printf 'zellij\n' > "$SQUAREBOX_STATE_DIR/multiplexer"
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
	SQUAREBOX_DC_MULTIPLEXERS=zellij \
	bash "$ROOT/scripts/devcontainer-postcreate.sh" >"$TMP/failure.out" 2>&1; then
	echo "FAIL: post-create accepted a failed setup" >&2
	exit 1
fi
grep -qx -- '--reconcile-selection ai sdks multiplexers' "$TMP/setup.call"
test ! -e "$STATE/ai-tool"
grep -qx node "$STATE/sdks"
grep -qx zellij "$STATE/multiplexer"
test ! -e "$HOME_DIR/.squarebox-setup-done"

# Existing user choices win over defaults and are still passed for reconcile.
printf 'python\n' > "$STATE/sdks"
printf 'tmux\n' > "$STATE/multiplexer"
cat > "$FAKE_SETUP" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ ! -t 0 ]
if IFS= read -r _unexpected_input; then exit 97; fi
grep -qx python "$SQUAREBOX_STATE_DIR/sdks"
grep -qx tmux "$SQUAREBOX_STATE_DIR/multiplexer"
EOF
chmod +x "$FAKE_SETUP"
HOME="$HOME_DIR" SQUAREBOX_STATE_DIR="$STATE" \
	SQUAREBOX_SETUP_SCRIPT="$FAKE_SETUP" \
	SQUAREBOX_DC_AI= SQUAREBOX_DC_SDKS=node \
	SQUAREBOX_DC_EDITORS= SQUAREBOX_DC_TUIS= \
	SQUAREBOX_DC_MULTIPLEXERS=zellij \
	bash "$ROOT/scripts/devcontainer-postcreate.sh" >"$TMP/success.out" 2>&1
grep -qx python "$STATE/sdks"
grep -qx tmux "$STATE/multiplexer"
test -e "$HOME_DIR/.squarebox-setup-done"

# Codespaces runs postCreateCommand with a pseudo-TTY. Prove the call site
# closes stdin independently of setup's reconciliation-mode implementation.
PTY_STATE="$TMP/pty-state"
PTY_HOME="$TMP/pty-home"
PTY_SETUP="$TMP/pty-setup.sh"
mkdir -p "$PTY_STATE" "$PTY_HOME"
cat > "$PTY_SETUP" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ ! -t 0 ]
if IFS= read -r _unexpected_input; then exit 97; fi
test "$*" = '--reconcile-selection ai sdks'
grep -qx claude "$SQUAREBOX_STATE_DIR/ai-tool"
grep -qx node "$SQUAREBOX_STATE_DIR/sdks"
printf 'called\n' > "$SQUAREBOX_FAKE_SETUP_CALL"
EOF
chmod +x "$PTY_SETUP"
timeout 5s script -qec "env HOME='$PTY_HOME' SQUAREBOX_STATE_DIR='$PTY_STATE' SQUAREBOX_SETUP_SCRIPT='$PTY_SETUP' SQUAREBOX_FAKE_SETUP_CALL='$TMP/pty-setup.called' SQUAREBOX_DC_AI=claude SQUAREBOX_DC_SDKS=node SQUAREBOX_DC_EDITORS= SQUAREBOX_DC_TUIS= SQUAREBOX_DC_MULTIPLEXERS= bash '$ROOT/scripts/devcontainer-postcreate.sh'" /dev/null \
	>"$TMP/pty-postcreate.out" 2>&1
test -e "$TMP/pty-setup.called"
test -e "$PTY_HOME/.squarebox-setup-done"

# Independently exercise the real reconciliation mode under a live PTY and
# without stdin redirection. Observed npm- and mise-hosted assistants must be
# found through mise shims, with no Gum prompt or reinstall command.
RECON_STATE="$TMP/reconcile-state"
RECON_HOME="$TMP/reconcile-home"
RECON_BIN="$TMP/reconcile-bin"
RECON_SHIMS="$RECON_HOME/.local/share/mise/shims"
RECON_TOOL_LIB="$TMP/reconcile-tool-lib.sh"
mkdir -p "$RECON_STATE" "$RECON_HOME" "$RECON_BIN" "$RECON_SHIMS"
printf 'copilot,omp\n' > "$RECON_STATE/ai-tool"
printf 'node\n' > "$RECON_STATE/sdks"
printf ':\n' > "$RECON_TOOL_LIB"
printf '#!/usr/bin/env bash\nexit 0\n' > "$RECON_SHIMS/copilot"
printf '#!/usr/bin/env bash\nexit 0\n' > "$RECON_SHIMS/omp"
cat > "$RECON_BIN/mise" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SQUAREBOX_FAKE_MISE_LOG"
case "${1:-}" in
	activate) printf 'export PATH="%s/.local/share/mise/shims:$PATH"\n' "$HOME" ;;
	which) exit 0 ;;
	use) printf 'called\n' > "$SQUAREBOX_FAKE_INSTALL_CALLED"; exit 99 ;;
	*) exit 0 ;;
esac
EOF
cat > "$RECON_BIN/npm" <<'EOF'
#!/usr/bin/env bash
printf 'called\n' > "$SQUAREBOX_FAKE_INSTALL_CALLED"
exit 99
EOF
cat > "$RECON_BIN/gum" <<'EOF'
#!/usr/bin/env bash
printf 'called\n' > "$SQUAREBOX_FAKE_GUM_CALLED"
exit 99
EOF
chmod +x "$RECON_BIN/mise" "$RECON_BIN/npm" "$RECON_BIN/gum" \
	"$RECON_SHIMS/copilot" "$RECON_SHIMS/omp"

timeout 5s script -qec "env HOME='$RECON_HOME' SQUAREBOX_STATE_DIR='$RECON_STATE' SQUAREBOX_TOOL_LIB='$RECON_TOOL_LIB' SQUAREBOX_TOOLS_YAML=/dev/null SQUAREBOX_FAKE_GUM_CALLED='$TMP/gum.called' SQUAREBOX_FAKE_INSTALL_CALLED='$TMP/install.called' SQUAREBOX_FAKE_MISE_LOG='$TMP/mise.log' PATH='$RECON_BIN:/usr/bin:/bin' bash '$ROOT/setup.sh' --reconcile-selection ai sdks" /dev/null \
	>"$TMP/tty-reconcile.out" 2>&1
test ! -e "$TMP/gum.called"
test ! -e "$TMP/install.called"
grep -qx 'copilot,omp' "$RECON_STATE/ai-tool"
grep -qx node "$RECON_STATE/sdks"
! grep -q '^use ' "$TMP/mise.log"

if bash "$ROOT/setup.sh" --reconcile-selection >"$TMP/reconcile-no-sections.out" 2>&1; then
	echo "FAIL: selection reconciliation accepted no sections" >&2
	exit 1
fi
grep -q -- '--reconcile-selection requires at least one section' "$TMP/reconcile-no-sections.out"

# Exercise the real postCreate -> setup transaction for a newly seeded default.
# A failed install must leave the Selection absent so the next postCreate can
# retry it, while a pre-existing user Selection must remain preserved.
DEFAULT_FAILURE_STATE="$TMP/default-failure-state"
DEFAULT_FAILURE_HOME="$TMP/default-failure-home"
DEFAULT_FAILURE_BIN="$TMP/default-failure-bin"
DEFAULT_FAILURE_TOOL_LIB="$TMP/default-failure-tool-lib.sh"
DEFAULT_FAILURE_LOG="$TMP/default-failure-install.log"
mkdir -p "$DEFAULT_FAILURE_STATE" "$DEFAULT_FAILURE_HOME" "$DEFAULT_FAILURE_BIN"
cat > "$DEFAULT_FAILURE_TOOL_LIB" <<'EOF'
# Keep the probe independent of optional tools installed on the test host.
command() {
	if [ "${1:-}" = -v ]; then
		case "${2:-}" in
			yazi|ya|elio|hx)
				[ -x "$SQUAREBOX_FAKE_BIN/${2}" ] || return 1
				;;
		esac
	fi
	builtin command "$@"
}

sb_install() {
	printf '%s\n' "$*" >> "$SQUAREBOX_FAKE_INSTALL_LOG"
	if [ "$SQUAREBOX_FAKE_INSTALL_MODE" = success ]; then
		case "$1" in
			yazi)
				for tool in yazi ya; do
					printf '#!/usr/bin/env bash\nexit 0\n' > "$SQUAREBOX_FAKE_BIN/$tool"
					chmod +x "$SQUAREBOX_FAKE_BIN/$tool"
				done
				return 0
				;;
			helix)
				printf '#!/usr/bin/env bash\nexit 0\n' > "$SQUAREBOX_FAKE_BIN/hx"
				chmod +x "$SQUAREBOX_FAKE_BIN/hx"
				mkdir -p "$HOME/.config/helix/runtime"
				return 0
				;;
		esac
	fi
	return 1
}
EOF

run_default() {
	local mode=$1 state=${2:-$DEFAULT_FAILURE_STATE} home=${3:-$DEFAULT_FAILURE_HOME}
	HOME="$home" \
		PATH="$DEFAULT_FAILURE_BIN:/usr/bin:/bin" \
		SQUAREBOX_STATE_DIR="$state" \
		SQUAREBOX_SETUP_SCRIPT="$ROOT/setup.sh" \
		SQUAREBOX_TOOL_LIB="$DEFAULT_FAILURE_TOOL_LIB" \
		SQUAREBOX_TOOLS_YAML=/dev/null \
		SQUAREBOX_FAKE_BIN="$DEFAULT_FAILURE_BIN" \
		SQUAREBOX_FAKE_INSTALL_MODE="$mode" \
		SQUAREBOX_FAKE_INSTALL_LOG="$DEFAULT_FAILURE_LOG" \
		SQUAREBOX_DC_AI= SQUAREBOX_DC_SDKS= \
		SQUAREBOX_DC_EDITORS= SQUAREBOX_DC_TUIS=yazi \
		SQUAREBOX_DC_MULTIPLEXERS= \
		bash "$ROOT/scripts/devcontainer-postcreate.sh" \
		>"$TMP/default-$mode.out" 2>&1
}

if run_default fail; then
	echo "FAIL: post-create accepted a failed newly seeded default" >&2
	exit 1
fi
test ! -e "$DEFAULT_FAILURE_STATE/tuis"
run_default success
grep -qx yazi "$DEFAULT_FAILURE_STATE/tuis"
test -x "$DEFAULT_FAILURE_BIN/yazi"
test -x "$DEFAULT_FAILURE_BIN/ya"
test "$(wc -l < "$DEFAULT_FAILURE_LOG")" -eq 2
test -e "$DEFAULT_FAILURE_HOME/.squarebox-setup-done"

rm -f -- "$DEFAULT_FAILURE_BIN/yazi" "$DEFAULT_FAILURE_BIN/ya"
PRIOR_STATE="$TMP/prior-selection-state"
PRIOR_HOME="$TMP/prior-selection-home"
mkdir -p "$PRIOR_STATE" "$PRIOR_HOME"
printf 'elio\n' > "$PRIOR_STATE/tuis"
if run_default fail "$PRIOR_STATE" "$PRIOR_HOME"; then
	echo "FAIL: post-create accepted a failed prior Selection" >&2
	exit 1
fi
grep -qx elio "$PRIOR_STATE/tuis"
test "$(wc -l < "$DEFAULT_FAILURE_LOG")" -eq 3
tail -n 1 "$DEFAULT_FAILURE_LOG" | grep -qx 'elio latest'
test ! -e "$PRIOR_HOME/.squarebox-setup-done"

EDITOR_FAILURE_STATE="$TMP/editor-failure-state"
EDITOR_FAILURE_HOME="$TMP/editor-failure-home"
EDITOR_FAILURE_LOG="$TMP/editor-failure-install.log"
mkdir -p "$EDITOR_FAILURE_STATE" "$EDITOR_FAILURE_HOME"
run_editor_default() {
	local mode=$1
	HOME="$EDITOR_FAILURE_HOME" \
		PATH="$DEFAULT_FAILURE_BIN:/usr/bin:/bin" \
		SQUAREBOX_STATE_DIR="$EDITOR_FAILURE_STATE" \
		SQUAREBOX_SETUP_SCRIPT="$ROOT/setup.sh" \
		SQUAREBOX_TOOL_LIB="$DEFAULT_FAILURE_TOOL_LIB" \
		SQUAREBOX_TOOLS_YAML=/dev/null \
		SQUAREBOX_FAKE_BIN="$DEFAULT_FAILURE_BIN" \
		SQUAREBOX_FAKE_INSTALL_MODE="$mode" \
		SQUAREBOX_FAKE_INSTALL_LOG="$EDITOR_FAILURE_LOG" \
		SQUAREBOX_DC_AI= SQUAREBOX_DC_SDKS= \
		SQUAREBOX_DC_EDITORS=helix SQUAREBOX_DC_TUIS= \
		SQUAREBOX_DC_MULTIPLEXERS= \
		bash "$ROOT/scripts/devcontainer-postcreate.sh" \
		>"$TMP/editor-$mode.out" 2>&1
}

if run_editor_default fail; then
	echo "FAIL: post-create accepted a failed newly seeded editor" >&2
	exit 1
fi
test ! -e "$EDITOR_FAILURE_STATE/editors"
test ! -e "$EDITOR_FAILURE_STATE/editor-default"
run_editor_default success
grep -qx helix "$EDITOR_FAILURE_STATE/editors"
grep -qx hx "$EDITOR_FAILURE_STATE/editor-default"
test -e "$EDITOR_FAILURE_HOME/.squarebox-setup-done"
test "$(wc -l < "$EDITOR_FAILURE_LOG")" -eq 2

echo "PASS: Dev Container provisioning preserves independent section outcomes and prior Selections"
