#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

bash -n install.sh uninstall.sh
! grep -Eq '(source|\.)[[:space:]]+.*install-state' install.sh uninstall.sh
python3 -m json.tool .devcontainer/devcontainer.json >/dev/null

grep -q 'workspaceMount.*target=/workspace' .devcontainer/devcontainer.json
grep -q '"workspaceFolder": "/workspace"' .devcontainer/devcontainer.json
grep -q 'name: ${SQUAREBOX_HOME_VOLUME:-squarebox-home}' docker-compose.yml
grep -q 'image: ${SQUAREBOX_IMAGE_REF:-ghcr.io/squarewavesystems/squarebox:latest}' docker-compose.yml
grep -q 'io.squarebox.managed: "true"' docker-compose.yml
grep -q 'io.squarebox.install-id: ${SQUAREBOX_INSTALL_ID:-compose-squarebox}' docker-compose.yml
grep -q '^SQUAREBOX_IMAGE_REF=' .env.example
grep -q '^SQUAREBOX_HOME_VOLUME=' .env.example
grep -q '^SQUAREBOX_INSTALL_ID=' .env.example

for file in install.ps1 uninstall.ps1; do
  grep -q 'Read-InstallState' "$file"
  grep -q 'Duplicate Install identity field' "$file"
  grep -q 'Unknown Install identity field' "$file"
  grep -q 'Missing Install identity field' "$file"
  grep -q 'HOME_VOLUME_ADOPTED.*0.*1' "$file"
  grep -q 'io.squarebox.install-id' "$file"
	grep -q 'CurrentUserAllHosts' "$file"
	grep -q 'squarebox-install-id' "$file"
	grep -q 'Get-ResourceOwner' "$file"
	grep -q 'Unable to verify ownership label' "$file"
	grep -q 'Malformed squarebox marker block' "$file"
done
grep -q 'release.json' install.ps1
grep -q 'Get-BoundedJson' install.ps1
grep -q 'MaximumRetryCount 3' install.ps1
grep -q 'image_ref' install.ps1
grep -q '\$Runtime pull \$ImageRef' install.ps1
grep -q '{{range .RepoDigests}}{{println .}}{{end}}' install.sh
grep -q '{{range .RepoDigests}}{{println .}}{{end}}' install.ps1
! grep -q 'index .RepoDigests 0' install.sh install.ps1
grep -q 'Select-ImageRepoDigest' install.ps1
grep -q 'Selection state directory must not be a symlink' install.sh
grep -q 'Selection state directory must not be a reparse point or symlink' install.ps1
grep -q '\[ "$WINDOWS_BASH" = 1 \] || return 1' install.sh uninstall.sh
grep -q -- '--userns=keep-id:uid=1000,gid=1000' install.sh
grep -q -- '--security-opt label=disable' install.sh
! grep -q 'ro,Z\|bind_mode=Z' install.sh
grep -q -- '--userns=keep-id:uid=1000,gid=1000' install.ps1
grep -q "'--security-opt', 'label=disable'" install.ps1
! grep -Eq ':ro,Z|BindSuffix.*:Z' install.ps1
grep -q 'GIT_CONFIG_DIR\|GitConfigDir' install.ps1
! grep -Fq "Join-Path \$env:USERPROFILE '.config\git'" install.ps1
grep -q "if (\$LASTEXITCODE -ne 0) { Abort 'Managed Box failed to start.' }" install.ps1
grep -q 'installed but unreachable' uninstall.ps1
grep -q 'does not match the recorded image' uninstall.ps1
grep -q 'Persisted adopted-home authority' install.ps1
grep -Fq '($Adopt -or ($State -and $State.HOME_VOLUME_ADOPTED -eq '"'"'1'"'"'))' install.ps1
grep -Fq '($HomeVolumeAdopted -or -not $State) -and -not $Force' uninstall.ps1
grep -q 'Update-ManagedFile' install.ps1
grep -q 'Test-ReparsePoint' install.ps1
grep -q 'Write-CandidateLazygitDefault' install.ps1
[ "$(grep -cxF '# squarebox-lazygit-default-begin' install.sh)" = 1 ]
[ "$(grep -cxF '# squarebox-lazygit-default-end' install.sh)" = 1 ]
grep -q '\[scriptblock\]::Create(\$profileBlock)' install.ps1
grep -q '\$HomeVolume -cne \$State.HOME_VOLUME' install.ps1
grep -q '\$owner.Trim() -cne '\''__INSTALL_ID__' install.ps1
grep -q '\$script:RollbackArmed' install.ps1
grep -q 'changed ownership after confirmation' uninstall.ps1
! grep -Eq '\$owner([.]Trim[(][)])?[[:space:]]+-ne[[:space:]]+\$InstallId' install.ps1 uninstall.ps1
! grep -Eq 'sudo[[:space:]]+rm[[:space:]]+-rf' uninstall.sh
for file in install.sh uninstall.sh; do
  grep -q 'WINDOWS_BASH' "$file"
  grep -q 'same_state_path' "$file"
done
for file in install.ps1 uninstall.ps1; do
  grep -q '\$IsWindows -and \$env:USERPROFILE' "$file"
done
grep -q 'LEGACY_STARSHIP_BLOB' install.sh
grep -q '\$LegacyStarshipBlob' install.ps1
! grep -Fq '$STATE_FILE.tmp.$$' install.sh
grep -Fq '.install-state.$([guid]::NewGuid' install.ps1
grep -q 'Recorded Workspace contains' uninstall.ps1
grep -q "Read-Host 'Continue? \[y/N\]'" uninstall.ps1

# FORMAT=1 is deliberately adapter-native. Both readers accept CRLF, but a
# Git-Bash C:/... path is not promised to be interchangeable with a native
# PowerShell C:\\... path; each lifecycle adapter must consume its own state.
grep -q 'ReadAllLines' install.ps1
grep -Fq 'line="${line%$'"'"'\r'"'"'}"' install.sh

python3 - <<'PY'
import re
from pathlib import Path

expected = [
    'FORMAT', 'INSTALL_ID', 'RUNTIME', 'INSTALL_DIR', 'WORKSPACE_DIR',
    'GIT_CONFIG_DIR', 'HOME_VOLUME', 'CONTAINER_NAME', 'IMAGE_ALIAS',
    'IMAGE_REPOSITORY', 'IMAGE_REF', 'IMAGE_ID', 'IMAGE_DIGEST', 'SOURCE_REF',
    'SOURCE_COMMIT', 'RELEASE_TAG', 'REQUESTED_TAG', 'PUID', 'PGID', 'BUILD',
    'EDGE', 'SHELL_INIT', 'SHELL_RC', 'ORIGIN', 'HOME_VOLUME_ADOPTED',
]
for name in ('install.ps1', 'uninstall.ps1'):
    text = Path(name).read_text()
    match = re.search(r'\$StateFields = @\((.*?)\n\)', text, re.S)
    assert match, f'{name}: no closed state schema'
    fields = re.findall(r"'([A-Z_]+)'", match.group(1))
    assert fields == expected, f'{name}: state schema differs: {fields}'

writer = Path('install.ps1').read_text().split('$stateLines = @(', 1)[1].split('\n)', 1)[0]
emitted = re.findall(r'["\']([A-Z_]+)=', writer)
assert emitted == expected, f'install.ps1: emitted state differs: {emitted}'
PY

if command -v pwsh >/dev/null 2>&1; then
  pwsh -NoProfile -NonInteractive -Command \
    '[void][scriptblock]::Create((Get-Content -Raw ./install.ps1)); [void][scriptblock]::Create((Get-Content -Raw ./uninstall.ps1))'
else
  echo '# PowerShell parser unavailable; lifecycle PowerShell UAT remains platform-gated.'
fi

echo 'ok - lifecycle adapters, Compose identity, and Dev Container state alignment'
