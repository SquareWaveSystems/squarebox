#!/usr/bin/env bash
# Records the demo GIF using VHS.
#
# Usage:
#   demo/record.sh
#
# Requires: vhs, gum, toilet
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

for cmd in vhs gum toilet; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd is required but not installed." >&2
        exit 1
    fi
done

cd "$REPO_DIR"
vhs demo/demo.tape
echo
ls -lh demo/squarebox-setup.gif
