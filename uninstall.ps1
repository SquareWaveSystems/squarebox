#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Windows uninstaller for squarebox.
.DESCRIPTION
    Removes the squarebox container, image, PowerShell profile sentinel block,
    and (optionally, via -Purge) the install directory.

    Usage:
      .\uninstall.ps1                       # remove container, image, profile block; keep ~/squarebox
      .\uninstall.ps1 -Purge                # additionally rm -rf ~/squarebox
      .\uninstall.ps1 -Yes                  # skip all confirmations
      .\uninstall.ps1 -Runtime podman       # force podman

    Broken-state recovery: run "%USERPROFILE%\squarebox\uninstall.ps1" directly
    if the sqrbx-uninstall function is not available.

    Idempotent: safe to run when nothing is installed.
#>
#Requires -Version 7.0

param(
    [switch]$Purge,
    [Alias('y')][switch]$Yes,
    [ValidateSet('docker', 'podman')]
    [string]$Runtime
)

$ErrorActionPreference = 'Stop'

$ImageName     = 'squarebox'
$ContainerName = 'squarebox'
$InstallDir    = Join-Path $env:USERPROFILE 'squarebox'

function Abort([string]$msg) {
    Write-Host "Error: $msg" -ForegroundColor Red
    exit 1
}

function Test-RuntimeHasState([string]$rt) {
    $names = & $rt ps -a --format '{{.Names}}' 2>$null
    if ($LASTEXITCODE -eq 0 -and $names -and ($names -split "`n" | Where-Object { $_.Trim() -eq $ContainerName })) {
        return $true
    }
    $images = & $rt images --format '{{.Repository}}' 2>$null
    if ($LASTEXITCODE -eq 0 -and $images -and ($images -split "`n" | Where-Object { $_.Trim() -eq $ImageName })) {
        return $true
    }
    return $false
}

# Runtime detection: -Runtime > $env:SQUAREBOX_RUNTIME > auto-detect. Auto-detect
# prefers the runtime that has squarebox state; if both do, prefer docker and
# warn about podman (matches install.ps1's preference).
$hasDocker = [bool](Get-Command docker -ErrorAction SilentlyContinue)
$hasPodman = [bool](Get-Command podman -ErrorAction SilentlyContinue)

$SelectedRuntime  = $null
$SecondaryRuntime = $null

if ($Runtime) {
    $SelectedRuntime = $Runtime
    if (-not (Get-Command $SelectedRuntime -ErrorAction SilentlyContinue)) {
        Abort "-Runtime $SelectedRuntime but '$SelectedRuntime' is not installed."
    }
} elseif ($env:SQUAREBOX_RUNTIME) {
    if ($env:SQUAREBOX_RUNTIME -notin @('docker', 'podman')) {
        Abort "SQUAREBOX_RUNTIME must be 'docker' or 'podman' (got '$($env:SQUAREBOX_RUNTIME)')."
    }
    $SelectedRuntime = $env:SQUAREBOX_RUNTIME
    if (-not (Get-Command $SelectedRuntime -ErrorAction SilentlyContinue)) {
        Abort "SQUAREBOX_RUNTIME=$SelectedRuntime but '$SelectedRuntime' is not installed."
    }
} else {
    $dockerState = $hasDocker -and (Test-RuntimeHasState 'docker')
    $podmanState = $hasPodman -and (Test-RuntimeHasState 'podman')

    if ($dockerState -and $podmanState) {
        $SelectedRuntime  = 'docker'
        $SecondaryRuntime = 'podman'
    } elseif ($dockerState) {
        $SelectedRuntime = 'docker'
    } elseif ($podmanState) {
        $SelectedRuntime = 'podman'
    } elseif ($hasDocker) {
        $SelectedRuntime = 'docker'
    } elseif ($hasPodman) {
        $SelectedRuntime = 'podman'
    }
}

# Probe state.
$hasContainer = $false
$hasImage     = $false
if ($SelectedRuntime) {
    $names = & $SelectedRuntime ps -a --format '{{.Names}}' 2>$null
    if ($LASTEXITCODE -eq 0 -and $names) {
        $hasContainer = [bool]($names -split "`n" | Where-Object { $_.Trim() -eq $ContainerName })
    }
    $images = & $SelectedRuntime images --format '{{.Repository}}' 2>$null
    if ($LASTEXITCODE -eq 0 -and $images) {
        $hasImage = [bool]($images -split "`n" | Where-Object { $_.Trim() -eq $ImageName })
    }
}

$hasProfileBlock = $false
if (Test-Path $PROFILE) {
    $hasProfileBlock = [bool](Select-String -Path $PROFILE -Pattern '^# >>> squarebox >>>' -Quiet)
    if (-not $hasProfileBlock) {
        # Also scrub orphan function defs from a legacy install with no sentinel.
        $hasProfileBlock = [bool](Select-String -Path $PROFILE -Pattern '^\s*function\s+(sqrbx|squarebox|sqrbx-rebuild|squarebox-rebuild|sqrbx-uninstall|squarebox-uninstall)\s*(\{|$)' -Quiet)
    }
}

$hasInstallDir = Test-Path $InstallDir

# Summary.
Write-Host "squarebox uninstall"
Write-Host "==================="
Write-Host ""

if ($SelectedRuntime) {
    Write-Host "Container runtime: $SelectedRuntime"
} else {
    Write-Host "Container runtime: none detected (skipping container/image cleanup)"
}

if ($SecondaryRuntime) {
    Write-Host ""
    Write-Host "Note: squarebox state also detected in $SecondaryRuntime."
    Write-Host "      This run will clean $SelectedRuntime only. To also clean ${SecondaryRuntime}:"
    Write-Host "        `$env:SQUAREBOX_RUNTIME = '$SecondaryRuntime'; .\uninstall.ps1"
}

$anythingToDo = $false

Write-Host ""
Write-Host "Will remove:"
if ($hasContainer)    { Write-Host "  - Container:      $ContainerName ($SelectedRuntime)"; $anythingToDo = $true }
if ($hasImage)        { Write-Host "  - Image:          $ImageName ($SelectedRuntime)";     $anythingToDo = $true }
if ($hasProfileBlock) { Write-Host "  - Profile block:  $PROFILE";                          $anythingToDo = $true }
if ($Purge -and $hasInstallDir) {
    Write-Host "  - Install dir:    $InstallDir"
    $anythingToDo = $true
}
if (-not $anythingToDo) {
    Write-Host "  (nothing)"
}

if (-not $Purge -and $hasInstallDir) {
    Write-Host ""
    Write-Host "Will KEEP:"
    Write-Host "  - $InstallDir (re-run with -Purge to remove, including workspace)"
}

Write-Host ""

if (-not $anythingToDo) {
    Write-Host "Nothing to do - squarebox appears to be already uninstalled."
    exit 0
}

# Confirmation.
if (-not $Yes -and [System.Console]::IsInputRedirected) {
    Abort "stdin is not a terminal; pass -Yes to run non-interactively."
}

if (-not $Yes) {
    $answer = Read-Host "Proceed? [y/N]"
    if ($answer -notmatch '^[yY]([eE][sS])?$') {
        Write-Host "Aborted." -ForegroundColor Yellow
        exit 1
    }
}

if ($Purge -and $hasInstallDir -and -not $Yes) {
    $workspaceDir = Join-Path $InstallDir 'workspace'
    if (Test-Path $workspaceDir) {
        $items = @(Get-ChildItem -Force -LiteralPath $workspaceDir -ErrorAction SilentlyContinue)
        if ($items.Count -gt 0) {
            Write-Host ""
            Write-Host "Warning: $workspaceDir contains $($items.Count) item(s)." -ForegroundColor Yellow
            Write-Host "         Purging will permanently delete them."
            $answer = Read-Host "Really purge workspace? [y/N]"
            if ($answer -notmatch '^[yY]([eE][sS])?$') {
                Write-Host "Aborted." -ForegroundColor Yellow
                exit 1
            }
        }
    }
}

# Perform the work. Set-Location away from the install dir so a later remove
# doesn't fail on "directory in use" (or succeed and leave the process in a
# deleted cwd).
Set-Location $env:USERPROFILE

$removedContainer    = $false
$removedImage        = $false
$removedProfileBlock = $false
$removedInstallDir   = $false

if ($hasContainer) {
    Write-Host "Stopping container..."
    & $SelectedRuntime stop $ContainerName 2>$null | Out-Null
    Write-Host "Removing container..."
    & $SelectedRuntime rm -f $ContainerName 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $removedContainer = $true }
}

if ($hasImage) {
    Write-Host "Removing image..."
    & $SelectedRuntime rmi -f $ImageName 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $removedImage = $true }
}

# Scrub profile. Mirrors install.ps1's strip logic at install.ps1:211-223,
# extended to match -uninstall function names.
if ($hasProfileBlock -and (Test-Path $PROFILE)) {
    $lines    = Get-Content $PROFILE
    $filtered = [System.Collections.Generic.List[string]]::new()
    $skip     = $false
    foreach ($line in $lines) {
        if ($line -match '^# >>> squarebox >>>') { $skip = $true; continue }
        if ($line -match '^# <<< squarebox <<<') { $skip = $false; continue }
        if ($skip) { continue }
        if ($line -match '^\s*function\s+(sqrbx|squarebox|sqrbx-rebuild|squarebox-rebuild|sqrbx-uninstall|squarebox-uninstall)\s*(\{|$)') { continue }
        $filtered.Add($line)
    }
    Set-Content -Path $PROFILE -Value ($filtered -join "`n")
    $removedProfileBlock = $true
}

if ($Purge -and $hasInstallDir) {
    Write-Host "Removing install directory..."
    Remove-Item -Recurse -Force -LiteralPath $InstallDir
    $removedInstallDir = $true
}

Write-Host ""
Write-Host "Done."
if ($removedContainer)    { Write-Host "  Removed container $ContainerName from $SelectedRuntime." }
if ($removedImage)        { Write-Host "  Removed image $ImageName from $SelectedRuntime." }
if ($removedProfileBlock) { Write-Host "  Scrubbed squarebox block from $PROFILE." }
if ($removedInstallDir)   { Write-Host "  Removed $InstallDir." }

if (-not $Purge -and $hasInstallDir) {
    Write-Host ""
    Write-Host "Kept $InstallDir (including workspace). Remove manually with:"
    Write-Host "  Remove-Item -Recurse -Force $InstallDir"
}

Write-Host ""
Write-Host "Note: sqrbx, squarebox, and related functions may still be defined in"
Write-Host "      your current shell. Start a new PowerShell session to drop them."
