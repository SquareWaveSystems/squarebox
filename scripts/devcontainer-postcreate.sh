#!/usr/bin/env bash
# devcontainer-postcreate.sh — non-interactive squarebox setup for
# Dev Containers / GitHub Codespaces.
#
# The interactive first-run wizard (setup.sh via .bashrc) is skipped when
# DEVCONTAINER=1. Orchestrators may still allocate a pseudo-TTY to post-create
# commands, so this script explicitly installs a sensible default toolset
# without prompting by pre-seeding Selection files and reconciling only the
# relevant sections.
#
# Override the defaults via containerEnv in devcontainer.json (or Codespaces
# secrets/variables). Set a variable to an empty string to opt out of that
# tier entirely:
#
#   SQUAREBOX_DC_AI       AI assistants     (default: claude)
#   SQUAREBOX_DC_SDKS     language SDKs      (default: node)
#   SQUAREBOX_DC_EDITORS  text editors       (default: none)
#   SQUAREBOX_DC_TUIS     TUI tools          (default: none)
#   SQUAREBOX_DC_MULTIPLEXERS terminal multiplexers (default: none)
#
# Values are comma-separated and use the same keys as sqrbx-setup, e.g.
# SQUAREBOX_DC_AI="claude,codex" or SQUAREBOX_DC_SDKS="node,python".
set -euo pipefail

CONFIG_DIR=${SQUAREBOX_STATE_DIR:-/workspace/.squarebox}
SETUP=${SQUAREBOX_SETUP_SCRIPT:-/usr/local/lib/squarebox/setup.sh}

while [[ "$CONFIG_DIR" == */ && "$CONFIG_DIR" != / ]]; do CONFIG_DIR=${CONFIG_DIR%/}; done
if [ -L "$CONFIG_DIR" ]; then
	echo "squarebox: Selection state directory must not be a symlink: $CONFIG_DIR" >&2
	exit 1
fi
if [ -e "$CONFIG_DIR" ] && [ ! -d "$CONFIG_DIR" ]; then
	echo "squarebox: Selection state path is not a directory: $CONFIG_DIR" >&2
	exit 1
fi
mkdir -p -- "$CONFIG_DIR"
if [ -L "$CONFIG_DIR" ] || [ ! -d "$CONFIG_DIR" ]; then
	echo "squarebox: unable to create a safe Selection state directory: $CONFIG_DIR" >&2
	exit 1
fi
SELECTION_STATE_FILES=(ai-tool editors editor-default nvim-lazyvim nvim-lazyvim-sha tuis multiplexer sdks shell)
for selection_file in "${SELECTION_STATE_FILES[@]}"; do
	selection_path="$CONFIG_DIR/$selection_file"
	if [ -L "$selection_path" ]; then
		echo "squarebox: Selection state file must not be a symlink: $selection_path" >&2
		exit 1
	fi
	if [ -e "$selection_path" ] && [ ! -f "$selection_path" ]; then
		echo "squarebox: Selection state path is not a regular file: $selection_path" >&2
		exit 1
	fi
done

# Default toolset. Use ${VAR-default} (not :-) so an explicitly empty value
# opts out, while an unset value falls back to the default.
AI=${SQUAREBOX_DC_AI-claude}
SDKS=${SQUAREBOX_DC_SDKS-node}
EDITORS=${SQUAREBOX_DC_EDITORS-}
TUIS=${SQUAREBOX_DC_TUIS-}
MULTIPLEXERS=${SQUAREBOX_DC_MULTIPLEXERS-}

sections=()
new_selection_files=()
new_editor_default=false

# seed <config-file> <value> <section>
# Writes the selection file only if absent, so a user's prior sqrbx-setup
# choices win on rebuild. Queues the section for install when the value is
# non-empty (whether freshly seeded or already present).
seed() {
	local file=$1 value=$2 section=$3
	[ -z "$value" ] && return 0
	if [ ! -f "$CONFIG_DIR/$file" ]; then
		printf '%s\n' "$value" > "$CONFIG_DIR/$file"
		new_selection_files+=("$file")
		if [ "$file" = editors ] && [ ! -e "$CONFIG_DIR/editor-default" ]; then
			new_editor_default=true
		fi
	fi
	sections+=("$section")
}

seed ai-tool "$AI"      ai
seed sdks    "$SDKS"    sdks
seed editors "$EDITORS" editors
seed tuis    "$TUIS"    tuis
seed multiplexer "$MULTIPLEXERS" multiplexers

if [ ${#sections[@]} -eq 0 ]; then
	echo "squarebox: no default tools selected; run 'sqrbx-setup' to configure."
	exit 0
fi

echo "squarebox: installing default toolset (${sections[*]})..."
# Codespaces and other orchestrators may allocate a pseudo-TTY to post-create
# commands. Reconciliation is explicitly noninteractive, and closing stdin
# makes any accidental future read fail instead of hanging container creation.
new_selection_csv=$(IFS=,; printf '%s' "${new_selection_files[*]}")
if ! SQUAREBOX_RECONCILE_NEW_SELECTIONS="$new_selection_csv" \
	"$SETUP" --reconcile-selection "${sections[@]}" </dev/null; then
	# setup.sh reconciles each requested Selection independently and rewrites
	# that section to the successfully observed subset. Remove only empty files
	# that this invocation seeded: successful subsets remain committed, prior
	# user Selections are untouched, and a failed new default can retry later.
	for selection_file in "${new_selection_files[@]}"; do
		selection_path="$CONFIG_DIR/$selection_file"
		if [ -f "$selection_path" ]; then
			if grep -q '[^[:space:]]' -- "$selection_path"; then
				continue
			else
				grep_rc=$?
			fi
			if [ "$grep_rc" -eq 1 ]; then
				rm -f -- "$selection_path"
				if [ "$selection_file" = editors ] && $new_editor_default; then
					rm -f -- "$CONFIG_DIR/editor-default"
				fi
			else
				echo "squarebox: unable to inspect failed Selection: $selection_path" >&2
			fi
		fi
	done
	echo "squarebox: default tool provisioning failed" >&2
	exit 1
fi
touch "$HOME/.squarebox-setup-done"
