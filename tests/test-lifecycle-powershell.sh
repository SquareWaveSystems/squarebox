#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
if ! command -v pwsh >/dev/null 2>&1; then
	echo 'ok - native PowerShell lifecycle contracts (SKIP: pwsh unavailable)'
	exit 0
fi

pwsh -NoLogo -NoProfile -NonInteractive -File "$ROOT/tests/test-lifecycle-powershell.ps1"
