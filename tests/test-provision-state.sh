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

export SQUAREBOX_ENTRYPOINT_FUNCTIONS_ONLY=1
# shellcheck source=../scripts/squarebox-entrypoint.sh
source "$ROOT/scripts/squarebox-entrypoint.sh"
unset SQUAREBOX_ENTRYPOINT_FUNCTIONS_ONLY

if (validate_id PUID nope) >/dev/null 2>&1; then
	not_ok "entrypoint rejects non-numeric PUID"
else
	[ "$?" -eq 64 ] && ok "entrypoint rejects non-numeric PUID" || not_ok "entrypoint rejects non-numeric PUID"
fi
if (validate_id PGID 0) >/dev/null 2>&1; then
	not_ok "entrypoint rejects root PGID"
else
	[ "$?" -eq 64 ] && ok "entrypoint rejects root PGID" || not_ok "entrypoint rejects root PGID"
fi
assert_true "(validate_id PUID 001000) >/dev/null 2>&1" "entrypoint accepts a positive decimal PUID"

OUTSIDE_SELECTION="$TMP/outside-selection"
LINKED_SELECTION="$TMP/linked-selection"
mkdir -p "$OUTSIDE_SELECTION"
ln -s "$OUTSIDE_SELECTION" "$LINKED_SELECTION"
export SQUAREBOX_STATE_DIR="$LINKED_SELECTION/"
if validate_selection_state_dir >"$TMP/entrypoint-state-link.out" 2>&1; then
	not_ok "entrypoint rejects a symlinked Selection directory"
else
	grep -q 'Selection state directory must not be a symlink' "$TMP/entrypoint-state-link.out" \
		&& ok "entrypoint rejects a symlinked Selection directory" \
		|| not_ok "entrypoint rejects a symlinked Selection directory"
fi

BROKEN_SELECTION="$TMP/broken-selection"
BROKEN_TARGET="$TMP/missing-selection-target"
mkdir -p "$BROKEN_SELECTION"
ln -s "$BROKEN_TARGET" "$BROKEN_SELECTION/editors"
export SQUAREBOX_STATE_DIR="$BROKEN_SELECTION"
if HOME="$TMP/preflight-home" SQUAREBOX_TOOL_LIB="$TMP/not-used-tool-lib" \
	bash "$ROOT/setup.sh" --rerun editors >"$TMP/setup-state-link.out" 2>&1; then
	not_ok "setup rejects a broken Selection-file symlink"
else
	if grep -q 'Selection state file must not be a symlink' "$TMP/setup-state-link.out" \
		&& [ -L "$BROKEN_SELECTION/editors" ] && [ ! -e "$BROKEN_TARGET" ]; then
		ok "setup rejects a broken Selection-file symlink"
	else
		not_ok "setup rejects a broken Selection-file symlink"
	fi
fi

STATE="$TMP/state"
HOME_DIR="$TMP/home"
BIN="$TMP/bin"
mkdir -p "$STATE" "$HOME_DIR/.config/tmux" "$BIN"
ln -s /usr/bin/grep "$BIN/grep"
ln -s /usr/bin/cat "$BIN/cat"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/tmux"
chmod +x "$BIN/tmux"
printf 'tmux\n' > "$STATE/multiplexer"
printf 'set -g mouse off\n' > "$HOME_DIR/.config/tmux/tmux.conf"
export SQUAREBOX_STATE_DIR="$STATE" SQUAREBOX_MANAGED_HOME="$HOME_DIR"

if PATH="$BIN" box_reconcile_needed; then
	not_ok "explicit tmux mouse-off is already reconciled"
else
	ok "explicit tmux mouse-off is already reconciled"
fi

rm -f "$BIN/tmux"
if PATH="$BIN" box_reconcile_needed; then
	ok "missing Box-tier tmux requires reconciliation"
else
	not_ok "missing Box-tier tmux requires reconciliation"
fi

printf '\n' > "$STATE/multiplexer"
printf 'nvim\n' > "$STATE/editors"
printf 'true\n' > "$STATE/nvim-lazyvim"
if PATH="$BIN" box_reconcile_needed; then
	ok "LazyVim Selection reconciles its Box-tier compiler"
else
	not_ok "LazyVim Selection reconciles its Box-tier compiler"
fi
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/cc"
chmod +x "$BIN/cc"
if PATH="$BIN" box_reconcile_needed; then
	not_ok "observed LazyVim compiler needs no reconciliation"
else
	ok "observed LazyVim compiler needs no reconciliation"
fi
rm -f "$BIN/cc" "$STATE/editors" "$STATE/nvim-lazyvim"

# Exercise the real non-interactive reconcile path with a fixture tmux as the
# observed package and a fixture tool library (this path performs no network).
FIXTURE_LIB="$TMP/tool-lib.sh"
printf ':\n' > "$FIXTURE_LIB"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/tmux"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/micro"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/fresh"
chmod +x "$BIN/tmux"
chmod +x "$BIN/micro" "$BIN/fresh"
printf 'tmux\n' > "$STATE/multiplexer"
printf 'bash\n' > "$STATE/shell"
printf 'micro,fresh\n' > "$STATE/editors"
printf 'fresh\n' > "$STATE/editor-default"
printf "export EDITOR='fresh'\n" > "$HOME_DIR/.squarebox-editor-aliases"
printf '# legacy config without a mouse choice\n' > "$HOME_DIR/.config/tmux/tmux.conf"
HOME="$HOME_DIR" SQUAREBOX_STATE_DIR="$STATE" \
	SQUAREBOX_TOOL_LIB="$FIXTURE_LIB" SQUAREBOX_TOOLS_YAML=/dev/null \
	PATH="$BIN:$PATH" bash "$ROOT/setup.sh" --reconcile-box >"$TMP/reconcile.out" 2>"$TMP/reconcile.err"
assert_true "grep -qx 'set -g mouse on' '$HOME_DIR/.config/tmux/tmux.conf'" "reconcile migrates a legacy tmux config"
assert_true "[ \"\$(cat '$STATE/multiplexer')\" = tmux ]" "successful reconciliation preserves the saved Selection"
assert_true "[ \"\$(cat '$STATE/editor-default')\" = fresh ] && grep -qx \"export EDITOR='fresh'\" '$HOME_DIR/.squarebox-editor-aliases'" "reconcile preserves a non-first default editor Selection"

printf 'set -g mouse off\n' > "$HOME_DIR/.config/tmux/tmux.conf"
HOME="$HOME_DIR" SQUAREBOX_STATE_DIR="$STATE" \
	SQUAREBOX_TOOL_LIB="$FIXTURE_LIB" SQUAREBOX_TOOLS_YAML=/dev/null \
	PATH="$BIN:$PATH" bash "$ROOT/setup.sh" --reconcile-box >"$TMP/reconcile-off.out" 2>"$TMP/reconcile-off.err"
assert_true "! grep -q 'mouse on' '$HOME_DIR/.config/tmux/tmux.conf'" "tmux migration never overrides explicit mouse-off"

# A gum cancellation and a confirmed empty multi-select are different state
# transitions: cancel preserves prior files; empty intentionally clears them.
if command -v script >/dev/null 2>&1; then
	GUM_BIN="$TMP/gum-bin"
	mkdir -p "$GUM_BIN"
	cat > "$GUM_BIN/gum" <<-'GUM'
	#!/usr/bin/env bash
	case "${1:-}" in
		choose)
			[ "${FAKE_GUM_RESULT:-cancel}" = empty ] && exit 0
			exit 130
			;;
		*) exit 0 ;;
	esac
	GUM
	chmod +x "$GUM_BIN/gum"
	printf 'codex\n' > "$STATE/ai-tool"
	printf "alias c='codex'\n" > "$HOME_DIR/.squarebox-ai-aliases"
	set +e
	script -qec "env HOME='$HOME_DIR' SQUAREBOX_STATE_DIR='$STATE' SQUAREBOX_TOOL_LIB='$FIXTURE_LIB' SQUAREBOX_TOOLS_YAML=/dev/null PATH='$GUM_BIN:/usr/bin:/bin' FAKE_GUM_RESULT=cancel bash '$ROOT/setup.sh' --rerun ai" /dev/null \
		>"$TMP/cancel.out" 2>"$TMP/cancel.err"
	CANCEL_RC=$?
	set -e
	assert_true "[ '$CANCEL_RC' -eq 130 ] && [ \"\$(cat '$STATE/ai-tool')\" = codex ] && grep -qx \"alias c='codex'\" '$HOME_DIR/.squarebox-ai-aliases'" "cancel preserves the prior Selection and aliases"

	script -qec "env HOME='$HOME_DIR' SQUAREBOX_STATE_DIR='$STATE' SQUAREBOX_TOOL_LIB='$FIXTURE_LIB' SQUAREBOX_TOOLS_YAML=/dev/null PATH='$GUM_BIN:/usr/bin:/bin' FAKE_GUM_RESULT=empty bash '$ROOT/setup.sh' --rerun ai" /dev/null \
		>"$TMP/empty.out" 2>"$TMP/empty.err"
	assert_true "[ -z \"\$(cat '$STATE/ai-tool')\" ] && [ ! -s '$HOME_DIR/.squarebox-ai-aliases' ]" "confirmed empty selection clears Selection and aliases"
else
	ok "cancel/empty pseudo-terminal test skipped (script utility unavailable)"
fi

printf '1..%d\n' "$((PASS + FAIL))"
[ "$FAIL" -eq 0 ]
