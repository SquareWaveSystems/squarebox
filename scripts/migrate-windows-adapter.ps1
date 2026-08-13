#!/usr/bin/env pwsh
#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateSet('PowerShell', 'GitBash')][string]$Target,
    [string]$InstallDir = $env:SQUAREBOX_DIR,
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
$UserHome = if ($env:USERPROFILE) { [IO.Path]::GetFullPath($env:USERPROFILE) } else { [IO.Path]::GetFullPath($HOME) }
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
    }
    if (-not [string]::Equals([IO.Path]::GetFullPath($state.INSTALL_DIR), $InstallDir, [StringComparison]::OrdinalIgnoreCase)) {
        Fail 'INSTALL_DIR does not identify this checkout'
    }
    $expectedGit = Join-Path $InstallDir '.squarebox\identity\git'
    if (-not [string]::Equals([IO.Path]::GetFullPath($state.GIT_CONFIG_DIR), [IO.Path]::GetFullPath($expectedGit), [StringComparison]::OrdinalIgnoreCase)) { Fail 'GIT_CONFIG_DIR escaped managed identity state' }
    return $state
}
function Format-Path([string]$Path, [string]$Adapter) {
    $native = [IO.Path]::GetFullPath($Path)
    if ($Adapter -ceq 'GitBash') { return $native.Replace('\', '/') }
    return $native
}
function Test-Block([string]$Path, [string]$Start, [string]$End) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
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
    [IO.File]::WriteAllLines($Path, $lines, [Text.UTF8Encoding]::new($false))
}
function Write-Atomic([string]$Path, [string[]]$Lines) {
    [IO.Directory]::CreateDirectory((Split-Path $Path)) | Out-Null
    $temp = Join-Path (Split-Path $Path) ".migration.$([guid]::NewGuid().ToString('N'))"
    try { [IO.File]::WriteAllLines($temp, $Lines, [Text.UTF8Encoding]::new($false)); [IO.File]::Move($temp, $Path, $true) }
    finally { Remove-Item -Force -LiteralPath $temp -ErrorAction SilentlyContinue }
}

$State = Read-State $StateFile
$PowerShellProfile = $PROFILE.CurrentUserAllHosts
$GitBashInit = Format-Path (Join-Path $UserHome '.squarebox-shell-init') GitBash
$GitBashRc = Format-Path (Join-Path $UserHome '.bashrc') GitBash
$PowerShellStatePath = Format-Path $PowerShellProfile PowerShell
$source = if ([string]::Equals([IO.Path]::GetFullPath($State.SHELL_INIT), [IO.Path]::GetFullPath($PowerShellProfile), [StringComparison]::OrdinalIgnoreCase)) { 'PowerShell' }
    elseif ($State.SHELL_INIT.Replace('\', '/') -ceq $GitBashInit -and $State.SHELL_RC.Replace('\', '/') -ceq $GitBashRc) { 'GitBash' }
    else { Fail 'state is foreign to both supported Windows adapters' }
if ($source -ceq $Target) { Fail "Install identity already belongs to $Target" }

if (-not (Get-Command $State.RUNTIME -ErrorAction SilentlyContinue)) { Fail "runtime '$($State.RUNTIME)' is unavailable" }
$owner = (& $State.RUNTIME inspect -f '{{ index .Config.Labels "io.squarebox.install-id" }}' $State.CONTAINER_NAME 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $owner -or $owner.Trim() -cne $State.INSTALL_ID) { Fail 'Box ownership check failed' }
$volumeOwner = (& $State.RUNTIME volume inspect -f '{{ index .Labels "io.squarebox.install-id" }}' $State.HOME_VOLUME 2>$null)
if ($LASTEXITCODE -ne 0) { Fail 'Managed-home ownership check failed' }
if ($volumeOwner) { $volumeOwner = $volumeOwner.Trim() }
if ($volumeOwner -cne $State.INSTALL_ID -and -not (-not $volumeOwner -and $State.HOME_VOLUME_ADOPTED -ceq '1')) { Fail 'Managed home is foreign' }

$paths = @($StateFile, $PowerShellProfile, $PROFILE.CurrentUserCurrentHost, $GitBashInit, $GitBashRc) | Select-Object -Unique
$backupRoot = Join-Path ([IO.Path]::GetTempPath()) "squarebox-migration-$([guid]::NewGuid().ToString('N'))"
[IO.Directory]::CreateDirectory($backupRoot) | Out-Null
$backups = @()
foreach ($path in $paths) {
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    $backup = Join-Path $backupRoot ([string]$backups.Count)
    if ($exists) { [IO.File]::Copy($path, $backup, $true) }
    $backups += [pscustomobject]@{ Path = $path; Backup = $backup; Exists = $exists }
}

if (-not $Yes -and -not $PSCmdlet.ShouldContinue("Convert $source Install identity '$($State.INSTALL_ID)' to $Target?", 'Squarebox adapter migration')) { exit 0 }
try {
    if ($Target -ceq 'PowerShell') {
        foreach ($path in @($GitBashRc, (Format-Path (Join-Path $UserHome '.zshrc') GitBash))) { Remove-Block $path '# >>> squarebox >>>' '# <<< squarebox <<<' }
        Remove-Block (Format-Path (Join-Path $UserHome '.bash_profile') GitBash) '# >>> squarebox bashrc bridge >>>' '# <<< squarebox bashrc bridge <<<'
        Remove-Item -Force -LiteralPath $GitBashInit -ErrorAction SilentlyContinue
        $block = @(
            '# >>> squarebox >>>', '# Managed by squarebox using the recorded Install identity.', "# squarebox-install-id=$($State.INSTALL_ID)",
            "function sqrbx { & '$($InstallDir.Replace("'", "''"))\install.ps1' @args }", 'function squarebox { sqrbx @args }',
            "function sqrbx-rebuild { & '$($InstallDir.Replace("'", "''"))\install.ps1' @args }", 'function squarebox-rebuild { sqrbx-rebuild @args }',
            "function sqrbx-uninstall { & '$($InstallDir.Replace("'", "''"))\uninstall.ps1' @args }", 'function squarebox-uninstall { sqrbx-uninstall @args }', '# <<< squarebox <<<'
        )
        [IO.Directory]::CreateDirectory((Split-Path $PowerShellProfile)) | Out-Null
        Remove-Block $PowerShellProfile '# >>> squarebox >>>' '# <<< squarebox <<<'
        [IO.File]::AppendAllLines($PowerShellProfile, $block, [Text.UTF8Encoding]::new($false))
        $State.SHELL_INIT = $PowerShellStatePath; $State.SHELL_RC = $PowerShellStatePath
    } else {
        foreach ($path in @($PowerShellProfile, $PROFILE.CurrentUserCurrentHost)) { Remove-Block $path '# >>> squarebox >>>' '# <<< squarebox <<<' }
        $install = Format-Path $InstallDir GitBash
		$bashSingleQuote = "'" + '"' + "'" + '"' + "'"
		$quotedInstall = $install.Replace("'", $bashSingleQuote)
        Write-Atomic $GitBashInit @(
            "# squarebox-install-id=$($State.INSTALL_ID)", "_sq_install='$quotedInstall'",
            'sqrbx() { if [ "${1:-}" = uninstall ]; then shift; "${_sq_install}/uninstall.sh" "$@"; else "${_sq_install}/install.sh" "$@"; fi; }',
            'squarebox() { sqrbx "$@"; }', 'sqrbx-rebuild() { "${_sq_install}/install.sh" "$@"; }', 'squarebox-rebuild() { sqrbx-rebuild "$@"; }',
            'sqrbx-uninstall() { "${_sq_install}/uninstall.sh" "$@"; }', 'squarebox-uninstall() { sqrbx-uninstall "$@"; }'
        )
        Remove-Block $GitBashRc '# >>> squarebox >>>' '# <<< squarebox <<<'
        [IO.Directory]::CreateDirectory((Split-Path $GitBashRc)) | Out-Null
        [IO.File]::AppendAllLines($GitBashRc, @('# >>> squarebox >>>', '[ -f "$HOME/.squarebox-shell-init" ] && . "$HOME/.squarebox-shell-init"', '# <<< squarebox <<<'), [Text.UTF8Encoding]::new($false))
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
