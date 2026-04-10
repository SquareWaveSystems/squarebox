#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Windows installer for squarebox. Writes PowerShell profile aliases
    and delegates Docker/bash setup to install.sh via Git Bash.
.DESCRIPTION
    Run this from PowerShell 7+ to install squarebox with working PowerShell
    aliases. Equivalent to running install.sh from Git Bash, but also sets up
    your PowerShell profile so sqrbx/squarebox commands work in PowerShell.

    First install:  irm https://raw.githubusercontent.com/SquareWaveSystems/squarebox/main/install.ps1 | iex
    Re-install:     .\install.ps1
    Edge:           .\install.ps1 -Edge
#>
#Requires -Version 7.0

param(
    [switch]$Edge,
    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'

# --- Find Git Bash ---
$bashCandidates = @(
    "$env:PROGRAMFILES\Git\bin\bash.exe"
    "${env:PROGRAMFILES(x86)}\Git\bin\bash.exe"
)
$gcm = Get-Command bash.exe -ErrorAction SilentlyContinue
if ($gcm) { $bashCandidates += $gcm.Source }

$bash = $bashCandidates | Where-Object { $_ -and (Test-Path $_) } |
    Select-Object -First 1
if (-not $bash) {
    Write-Error "Git Bash not found. Install Git for Windows: https://git-scm.com/download/win"
    exit 1
}

# --- Run install.sh (clone, build, container, bash profile) ---
$installArgs = @('--no-pwsh')
if ($Edge)    { $installArgs += '--edge' }
if ($Verbose) { $installArgs += '--verbose' }

$InstallDir = Join-Path $env:USERPROFILE 'squarebox'
$installSh  = Join-Path $InstallDir 'install.sh'

if (Test-Path $installSh) {
    & $bash $installSh @installArgs
} else {
    # First install: download install.sh to a temp file and execute it.
    # Piping a string through PowerShell to bash can introduce CRLF / encoding
    # changes that break bash parsing. Using a temp file keeps the script
    # byte-identical to what the server sent.
    $url = 'https://raw.githubusercontent.com/SquareWaveSystems/squarebox/main/install.sh'
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) 'squarebox-install.sh'
    try {
        Invoke-WebRequest -Uri $url -UseBasicParsing -OutFile $tmp
        & $bash $tmp @installArgs
    } finally {
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }
}
if ($LASTEXITCODE -ne 0) {
    Write-Error "install.sh failed (exit code $LASTEXITCODE)"
    exit $LASTEXITCODE
}

# --- PowerShell profile setup ---
$profileDir = Split-Path $PROFILE
if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}

# Strip existing managed block and legacy function defs
if (Test-Path $PROFILE) {
    $lines = Get-Content $PROFILE
    $filtered = [System.Collections.Generic.List[string]]::new()
    $skip = $false
    foreach ($line in $lines) {
        if ($line -match '^# >>> squarebox >>>') { $skip = $true; continue }
        if ($line -match '^# <<< squarebox <<<') { $skip = $false; continue }
        if ($skip) { continue }
        if ($line -match '^\s*function\s+(sqrbx|squarebox|sqrbx-rebuild|squarebox-rebuild)\s*(\{|$)') { continue }
        $filtered.Add($line)
    }
    Set-Content -Path $PROFILE -Value ($filtered -join "`n")
}

# Append managed block
@'
# >>> squarebox >>>
# squarebox shell integration — managed by install.ps1.
Remove-Item Alias:sqrbx, Alias:squarebox, Alias:sqrbx-rebuild, Alias:squarebox-rebuild -ErrorAction SilentlyContinue
function sqrbx { docker start -ai squarebox }
function squarebox { docker start -ai squarebox }
function sqrbx-rebuild { & "$env:USERPROFILE\squarebox\install.ps1" @args }
function squarebox-rebuild { sqrbx-rebuild @args }
# <<< squarebox <<<
'@ | Add-Content -Path $PROFILE

Write-Host "Installed squarebox shell integration -> $PROFILE"
