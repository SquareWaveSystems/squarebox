#!/usr/bin/env bash
# devcontainer-postcreate.sh — non-interactive squarebox setup for
# Dev Containers / GitHub Codespaces.
#
# The interactive first-run wizard (setup.sh via .bashrc) is skipped when
# DEVCONTAINER=1, because there is no TTY at container-create time and the
# gum-based picker can't run. This script installs a sensible default toolset
# non-interactively instead, by pre-seeding the selection files that
# setup.sh reads and then running the relevant sections in --rerun mode.
#
# Override the defaults via containerEnv in devcontainer.json (or Codespaces
# secrets/variables). Set a variable to an empty string to opt out of that
# tier entirely:
#
#   SQUAREBOX_DC_AI       AI assistants     (default: claude)
#   SQUAREBOX_DC_SDKS     language SDKs      (default: node)
#   SQUAREBOX_DC_EDITORS  text editors       (default: none)
#   SQUAREBOX_DC_TUIS     TUI tools          (default: none)
#
# Values are comma-separated and use the same keys as sqrbx-setup, e.g.
# SQUAREBOX_DC_AI="claude,codex" or SQUAREBOX_DC_SDKS="node,python".
set -euo pipefail

CONFIG_DIR=/workspace/.squarebox
SETUP=/usr/local/lib/squarebox/setup.sh

mkdir -p "$CONFIG_DIR"

# Default toolset. Use ${VAR-default} (not :-) so an explicitly empty value
# opts out, while an unset value falls back to the default.
AI=${SQUAREBOX_DC_AI-claude}
SDKS=${SQUAREBOX_DC_SDKS-node}
EDITORS=${SQUAREBOX_DC_EDITORS-}
TUIS=${SQUAREBOX_DC_TUIS-}

sections=()

# seed <config-file> <value> <section>
# Writes the selection file only if absent, so a user's prior sqrbx-setup
# choices win on rebuild. Queues the section for install when the value is
# non-empty (whether freshly seeded or already present).
seed() {
	local file=$1 value=$2 section=$3
	[ -z "$value" ] && return 0
	[ -f "$CONFIG_DIR/$file" ] || printf '%s\n' "$value" > "$CONFIG_DIR/$file"
	sections+=("$section")
}

seed ai-tool "$AI"      ai
seed sdks    "$SDKS"    sdks
seed editors "$EDITORS" editors
seed tuis    "$TUIS"    tuis

if [ ${#sections[@]} -eq 0 ]; then
	echo "squarebox: no default tools selected; run 'sqrbx-setup' to configure."
	exit 0
fi

echo "squarebox: installing default toolset (${sections[*]})..."
"$SETUP" --rerun "${sections[@]}"
