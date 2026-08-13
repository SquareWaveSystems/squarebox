#!/usr/bin/env pwsh
#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateSet('PowerShell', 'GitBash')][string]$Target,
    [string]$InstallDir = $env:SQUAREBOX_DIR,
    [string]$PowerShellProfile = $PROFILE.CurrentUserAllHosts,
    [string]$PowerShellCurrentHostProfile = $PROFILE.CurrentUserCurrentHost,
    [string]$UserHomePath = $(if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }),
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$Fields = @(
    'FORMAT', 'INSTALL_ID', 'RUNTIME', 'INSTALL_DIR', 'WORKSPACE_DIR', 'GIT_CONFIG_DIR',
    'HOME_VOLUME', 'CONTAINER_NAME', 'IMAGE_ALIAS', 'IMAGE_REPOSITORY', 'IMAGE_REF',
    'IMAGE_ID', 'IMAGE_DIGEST', 'SOURCE_REF', 'SOURCE_COMMIT', 'RELEASE_TAG',
    'REQUESTED_TAG', 'PUID', 'PGID', 'BUILD', 'EDGE', 'SHELL_INIT', 'SHELL_RC',
    'ORIGIN', 'HOME_VOLUME_ADOPTED'
)
$UserHome = [IO.Path]::GetFullPath($UserHomePath)
if (-not $InstallDir) { $InstallDir = Join-Path $UserHome 'squarebox' }
$InstallDir = [IO.Path]::GetFullPath($InstallDir)
$StateFile = Join-Path $InstallDir '.squarebox\install-state'
$IdentityLabel = 'io.squarebox.install-id'

function Fail([string]$Message) { throw "Windows adapter migration: $Message" }
function Read-State([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Fail "Install identity not found: $Path" }
    $state = [ordered]@{}
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if (-not $line -or $line.StartsWith('#', [StringComparison]::Ordinal)) { continue }
        $at = $line.IndexOf('=')
        if ($at -lt 1) { Fail "malformed Install identity: $Path" }
        $key = $line.Substring(0, $at); $value = $line.Substring($at + 1)
        if ($Fields -cnotcontains $key) { Fail "unknown field '$key'" }
        if ($state.Contains($key)) { Fail "duplicate field '$key'" }
        if ($value -match '[\x00-\x1f\x7f]') { Fail "control character in '$key'" }
        $state[$key] = $value
    }
    foreach ($field in $Fields) { if (-not $state.Contains($field)) { Fail "missing field '$field'" } }
    if ($state.FORMAT -cne '1' -or $state.INSTALL_ID -cnotmatch '^[A-Za-z0-9._-]{8,128}$') { Fail 'invalid FORMAT or INSTALL_ID' }
    if ($state.RUNTIME -cnotin @('docker', 'podman')) { Fail 'invalid runtime' }
    if ($state.ORIGIN -cne 'https://github.com/SquareWaveSystems/squarebox.git') { Fail 'noncanonical origin' }
    foreach ($name in @('HOME_VOLUME', 'CONTAINER_NAME')) {
        if ($state[$name] -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$') { Fail "invalid $name" }
    }
    if ($state.IMAGE_ALIAS -cnotmatch '^[a-z0-9][a-z0-9._/-]*(:[A-Za-z0-9_][A-Za-z0-9_.-]{0,127})?$' -or
        $state.IMAGE_REPOSITORY -cnotmatch '^[a-z0-9][a-z0-9._/-]*$' -or $state.IMAGE_ID -cnotmatch '^(sha256:)?[0-9a-f]{64}$' -or
        ($state.IMAGE_DIGEST -and $state.IMAGE_DIGEST -cnotmatch '^[a-z0-9][a-z0-9._/-]*@sha256:[0-9a-f]{64}$') -or
        $state.SOURCE_COMMIT -cnotmatch '^[0-9a-f]{40}$') { Fail 'invalid image or source identity' }
    foreach ($name in @('PUID', 'PGID')) {
        $number = 0L
        if ($state[$name] -cnotmatch '^[0-9]{1,10}$' -or -not [long]::TryParse($state[$name], [ref]$number) -or $number -lt 1 -or $number -gt 2147483647) { Fail "invalid $name" }
    }
    if ($state.BUILD -cnotin @('0', '1') -or $state.EDGE -cnotin @('0', '1') -or $state.HOME_VOLUME_ADOPTED -cnotin @('0', '1') -or
        ($state.EDGE -ceq '1' -and $state.BUILD -cne '1')) { Fail 'invalid lifecycle flags' }
    foreach ($name in @('INSTALL_DIR', 'WORKSPACE_DIR', 'GIT_CONFIG_DIR', 'SHELL_INIT', 'SHELL_RC')) {
		if (-not [IO.Path]::IsPathFullyQualified($state[$name])) { Fail "non-absolute $name" }
		$full = [IO.Path]::GetFullPath($state[$name])
		$normalizedInput = $state[$name].Replace('/', '\')
		if (-not [string]::Equals($full, $normalizedInput, [StringComparison]::OrdinalIgnoreCase)) { Fail "unnormalized $name" }
    }
    if (-not [string]::Equals([IO.Path]::GetFullPath($state.INSTALL_DIR), $InstallDir, [StringComparison]::OrdinalIgnoreCase)) {
        Fail 'INSTALL_DIR does not identify this checkout'
    }
	if ([string]::Equals($InstallDir, [IO.Path]::GetPathRoot($InstallDir), [StringComparison]::OrdinalIgnoreCase) -or
		[string]::Equals($InstallDir, $UserHome, [StringComparison]::OrdinalIgnoreCase)) { Fail 'unsafe INSTALL_DIR' }
	$workspace = [IO.Path]::GetFullPath($state.WORKSPACE_DIR)
	if ([string]::Equals($workspace, [IO.Path]::GetPathRoot($workspace), [StringComparison]::OrdinalIgnoreCase) -or
		[string]::Equals($workspace, $InstallDir, [StringComparison]::OrdinalIgnoreCase) -or
		[string]::Equals($workspace, $UserHome, [StringComparison]::OrdinalIgnoreCase)) { Fail 'unsafe WORKSPACE_DIR' }
    $expectedGit = Join-Path $InstallDir '.squarebox\identity\git'
    if (-not [string]::Equals([IO.Path]::GetFullPath($state.GIT_CONFIG_DIR), [IO.Path]::GetFullPath($expectedGit), [StringComparison]::OrdinalIgnoreCase)) { Fail 'GIT_CONFIG_DIR escaped managed identity state' }
    return $state
}
function Format-Path([string]$Path, [string]$Adapter) {
    $native = [IO.Path]::GetFullPath($Path)
    if ($Adapter -ceq 'GitBash') { return $native.Replace('\', '/') }
    return $native
}
function Assert-SafeFile([string]$Path, [string]$Description) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint -or $item.PSIsContainer) { Fail "$Description is not a regular file: $Path" }
}
function Test-Block([string]$Path, [string]$Start, [string]$End) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    Assert-SafeFile $Path 'profile'
    $inside = $false; $count = 0
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if ($line -ceq $Start) { if ($inside -or $count) { Fail "malformed marker block in $Path" }; $inside = $true; $count++; continue }
        if ($line -ceq $End) { if (-not $inside) { Fail "malformed marker block in $Path" }; $inside = $false }
    }
    if ($inside) { Fail "unterminated marker block in $Path" }
    return $count -eq 1
}
function Remove-Block([string]$Path, [string]$Start, [string]$End) {
    if (-not (Test-Block $Path $Start $End)) { return }
    $inside = $false
    $lines = foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if ($line -ceq $Start) { $inside = $true; continue }
        if ($line -ceq $End) { $inside = $false; continue }
        if (-not $inside) { $line }
    }
    Write-Atomic $Path @($lines)
}
function Write-Atomic([string]$Path, [string[]]$Lines) {
    [IO.Directory]::CreateDirectory((Split-Path $Path)) | Out-Null
    $temp = Join-Path (Split-Path $Path) ".migration.$([guid]::NewGuid().ToString('N'))"
    try { [IO.File]::WriteAllLines($temp, $Lines, [Text.UTF8Encoding]::new($false)); [IO.File]::Move($temp, $Path, $true) }
    finally { Remove-Item -Force -LiteralPath $temp -ErrorAction SilentlyContinue }
}
function Add-Block([string]$Path, [string[]]$Block) {
    Assert-SafeFile $Path 'profile'
    $lines = if (Test-Path -LiteralPath $Path -PathType Leaf) { @([IO.File]::ReadAllLines($Path)) } else { @() }
    Write-Atomic $Path @($lines + $Block)
}

$State = Read-State $StateFile
$GitBashInit = Format-Path (Join-Path $UserHome '.squarebox-shell-init') GitBash
$GitBashRc = Format-Path (Join-Path $UserHome '.bashrc') GitBash
$PowerShellStatePath = Format-Path $PowerShellProfile PowerShell
$source = if ([string]::Equals([IO.Path]::GetFullPath($State.SHELL_INIT), [IO.Path]::GetFullPath($PowerShellProfile), [StringComparison]::OrdinalIgnoreCase)) { 'PowerShell' }
    elseif ($State.SHELL_INIT.Replace('\', '/') -ceq $GitBashInit -and $State.SHELL_RC.Replace('\', '/') -ceq $GitBashRc) { 'GitBash' }
    else { Fail 'state is foreign to both supported Windows adapters' }
if ($source -ceq $Target) { Fail "Install identity already belongs to $Target" }
if ($source -ceq 'GitBash') {
    Assert-SafeFile $GitBashInit 'Git Bash adapter'
    if (-not (Test-Path -LiteralPath $GitBashInit -PathType Leaf) -or
        -not ([IO.File]::ReadAllLines($GitBashInit) -ccontains "# squarebox-install-id=$($State.INSTALL_ID)")) { Fail 'Git Bash adapter ownership check failed' }
} else {
    if (-not (Test-Block $PowerShellProfile '# >>> squarebox >>>' '# <<< squarebox <<<') -or
        -not ([IO.File]::ReadAllLines($PowerShellProfile) -ccontains "# squarebox-install-id=$($State.INSTALL_ID)")) { Fail 'PowerShell adapter ownership check failed' }
}
foreach ($path in @($PowerShellProfile, $PowerShellCurrentHostProfile)) {
    if ((Test-Block $path '# >>> squarebox >>>' '# <<< squarebox <<<') -and
        -not ([IO.File]::ReadAllLines($path) -ccontains "# squarebox-install-id=$($State.INSTALL_ID)")) { Fail "foreign PowerShell profile block: $path" }
}
if ((Test-Path -LiteralPath $GitBashInit -PathType Leaf) -and
    -not ([IO.File]::ReadAllLines($GitBashInit) -ccontains "# squarebox-install-id=$($State.INSTALL_ID)")) { Fail 'foreign Git Bash adapter' }

if (-not (Get-Command $State.RUNTIME -ErrorAction SilentlyContinue)) { Fail "runtime '$($State.RUNTIME)' is unavailable" }
$owner = (& $State.RUNTIME inspect -f '{{ index .Config.Labels "io.squarebox.install-id" }}' $State.CONTAINER_NAME 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $owner -or $owner.Trim() -cne $State.INSTALL_ID) { Fail 'Box ownership check failed' }
$volumeOwner = (& $State.RUNTIME volume inspect -f '{{ index .Labels "io.squarebox.install-id" }}' $State.HOME_VOLUME 2>$null)
if ($LASTEXITCODE -ne 0) { Fail 'Managed-home ownership check failed' }
if ($volumeOwner) { $volumeOwner = $volumeOwner.Trim() }
if ($volumeOwner -cne $State.INSTALL_ID -and -not (-not $volumeOwner -and $State.HOME_VOLUME_ADOPTED -ceq '1')) { Fail 'Managed home is foreign' }

$paths = @(
    $StateFile, $PowerShellProfile, $PowerShellCurrentHostProfile, $GitBashInit, $GitBashRc,
    (Format-Path (Join-Path $UserHome '.zshrc') GitBash), (Format-Path (Join-Path $UserHome '.bash_profile') GitBash)
) | Select-Object -Unique
if (-not $Yes -and -not $PSCmdlet.ShouldContinue("Convert $source Install identity '$($State.INSTALL_ID)' to $Target?", 'Squarebox adapter migration')) { exit 0 }
$backupRoot = Join-Path ([IO.Path]::GetTempPath()) "squarebox-migration-$([guid]::NewGuid().ToString('N'))"
[IO.Directory]::CreateDirectory($backupRoot) | Out-Null
$backups = @()
foreach ($path in $paths) {
    Assert-SafeFile $path 'migration target'
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    $backup = Join-Path $backupRoot ([string]$backups.Count)
    if ($exists) { [IO.File]::Copy($path, $backup, $true) }
    $backups += [pscustomobject]@{ Path = $path; Backup = $backup; Exists = $exists }
}
try {
    if ($Target -ceq 'PowerShell') {
        foreach ($path in @($GitBashRc, (Format-Path (Join-Path $UserHome '.zshrc') GitBash))) { Remove-Block $path '# >>> squarebox >>>' '# <<< squarebox <<<' }
        Remove-Block (Format-Path (Join-Path $UserHome '.bash_profile') GitBash) '# >>> squarebox bashrc bridge >>>' '# <<< squarebox bashrc bridge <<<'
        Remove-Item -Force -LiteralPath $GitBashInit -ErrorAction SilentlyContinue
        $block = @(
            '# >>> squarebox >>>', '# Managed by squarebox using the recorded Install identity.', "# squarebox-install-id=$($State.INSTALL_ID)",
            'function sqrbx {',
            "    if (`$args.Count -gt 0 -and `$args[0] -eq 'uninstall') { & '$($InstallDir.Replace("'", "''"))\uninstall.ps1' @(`$args | Select-Object -Skip 1); return }",
            "    `$owner = (& $($State.RUNTIME) inspect -f '{{ index .Config.Labels `"io.squarebox.install-id`" }}' '$($State.CONTAINER_NAME)' 2>`$null)",
            "    if (-not `$owner -or `$owner.Trim() -cne '$($State.INSTALL_ID)') { throw 'squarebox Install identity mismatch; refusing to start.' }",
            "    `$running = (& $($State.RUNTIME) inspect -f '{{.State.Running}}' '$($State.CONTAINER_NAME)' 2>`$null)",
            "    if (`$running -and `$running.Trim() -ceq 'true') { & $($State.RUNTIME) stop '$($State.CONTAINER_NAME)' | Out-Null }",
            "    & $($State.RUNTIME) start -ai '$($State.CONTAINER_NAME)'", '}', 'function squarebox { sqrbx @args }',
            "function sqrbx-rebuild { & '$($InstallDir.Replace("'", "''"))\install.ps1' @args }", 'function squarebox-rebuild { sqrbx-rebuild @args }',
            "function sqrbx-uninstall { & '$($InstallDir.Replace("'", "''"))\uninstall.ps1' @args }", 'function squarebox-uninstall { sqrbx-uninstall @args }', '# <<< squarebox <<<'
        )
        Remove-Block $PowerShellProfile '# >>> squarebox >>>' '# <<< squarebox <<<'
        Add-Block $PowerShellProfile $block
        foreach ($name in @('INSTALL_DIR', 'WORKSPACE_DIR', 'GIT_CONFIG_DIR')) { $State[$name] = Format-Path $State[$name] PowerShell }
        $State.SHELL_INIT = $PowerShellStatePath; $State.SHELL_RC = $PowerShellStatePath
    } else {
        foreach ($path in @($PowerShellProfile, $PowerShellCurrentHostProfile)) { Remove-Block $path '# >>> squarebox >>>' '# <<< squarebox <<<' }
        $install = Format-Path $InstallDir GitBash
		$bashSingleQuote = "'" + '"' + "'" + '"' + "'"
		$quotedInstall = $install.Replace("'", $bashSingleQuote)
		$quotedRuntime = $State.RUNTIME.Replace("'", $bashSingleQuote)
		$quotedContainer = $State.CONTAINER_NAME.Replace("'", $bashSingleQuote)
		$quotedInstallId = $State.INSTALL_ID.Replace("'", $bashSingleQuote)
        Write-Atomic $GitBashInit @(
            "# squarebox-install-id=$($State.INSTALL_ID)", "_sq_install='$quotedInstall'",
            "_sq_runtime='$quotedRuntime'", "_sq_container='$quotedContainer'", "_sq_install_id='$quotedInstallId'",
            'sqrbx() {', '  if [ "${1:-}" = uninstall ]; then shift; "${_sq_install}/uninstall.sh" "$@"; return; fi',
            '  _sq_owner="$("${_sq_runtime}" inspect -f ''{{ index .Config.Labels "io.squarebox.install-id" }}'' "${_sq_container}" 2>/dev/null || true)"',
            '  [ "$_sq_owner" = "$_sq_install_id" ] || { echo "squarebox: Install identity mismatch; refusing to start" >&2; return 1; }',
            '  if [ "$("${_sq_runtime}" inspect -f ''{{.State.Running}}'' "${_sq_container}" 2>/dev/null)" = true ]; then "${_sq_runtime}" stop "${_sq_container}" >/dev/null; fi',
            '  "${_sq_runtime}" start -ai "${_sq_container}"', '}',
            'squarebox() { sqrbx "$@"; }', 'sqrbx-rebuild() { "${_sq_install}/install.sh" "$@"; }', 'squarebox-rebuild() { sqrbx-rebuild "$@"; }',
            'sqrbx-uninstall() { "${_sq_install}/uninstall.sh" "$@"; }', 'squarebox-uninstall() { sqrbx-uninstall "$@"; }'
        )
        Remove-Block $GitBashRc '# >>> squarebox >>>' '# <<< squarebox <<<'
        Add-Block $GitBashRc @('# >>> squarebox >>>', '[ -f "$HOME/.squarebox-shell-init" ] && . "$HOME/.squarebox-shell-init"', '# <<< squarebox <<<')
        foreach ($name in @('INSTALL_DIR', 'WORKSPACE_DIR', 'GIT_CONFIG_DIR')) { $State[$name] = Format-Path $State[$name] GitBash }
        $State.SHELL_INIT = $GitBashInit; $State.SHELL_RC = $GitBashRc
    }
    Write-Atomic $StateFile @($Fields | ForEach-Object { "$_=$($State[$_])" })
} catch {
    foreach ($backup in $backups) {
        if ($backup.Exists) { [IO.Directory]::CreateDirectory((Split-Path $backup.Path)) | Out-Null; [IO.File]::Copy($backup.Backup, $backup.Path, $true) }
        else { Remove-Item -Force -LiteralPath $backup.Path -ErrorAction SilentlyContinue }
    }
    throw
} finally { Remove-Item -Recurse -Force -LiteralPath $backupRoot -ErrorAction SilentlyContinue }

Write-Output "Migrated Squarebox Install identity $($State.INSTALL_ID) from $source to $Target."
