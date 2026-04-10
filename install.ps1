#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Windows installer for squarebox. Pure PowerShell — no Git Bash required.
.DESCRIPTION
    Run this from PowerShell 7+ to install squarebox. Handles clone, build,
    container creation, and PowerShell profile setup natively.

    First install:  irm https://raw.githubusercontent.com/SquareWaveSystems/squarebox/main/install.ps1 | iex
    Re-install:     .\install.ps1
    Edge:           .\install.ps1 -Edge
    Verbose:        .\install.ps1 -Verbose
#>
#Requires -Version 7.0

param(
    [switch]$Edge,
    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'

$Repo        = 'https://github.com/SquareWaveSystems/squarebox.git'
$InstallDir  = Join-Path $env:USERPROFILE 'squarebox'
$ImageName   = 'squarebox'
$ContainerName = 'squarebox'

# --- Verify prerequisites ---
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error "Git is not installed. See https://git-scm.com/download/win"
    exit 1
}
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "Docker is not installed. See https://docs.docker.com/get-docker/"
    exit 1
}
try { docker info 2>$null | Out-Null } catch {}
if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker daemon is not running or current user lacks permissions."
    exit 1
}

# --- Clone or update ---
if (Test-Path (Join-Path $InstallDir '.git')) {
    Write-Host "Updating existing install..."
    $gitQuiet = if ($Verbose) { @() } else { @('--quiet') }
    git -C $InstallDir fetch --tags --force @gitQuiet origin
} else {
    Write-Host "Cloning squarebox..."
    $gitQuiet = if ($Verbose) { @() } else { @('--quiet') }
    git clone @gitQuiet $Repo $InstallDir
}

# --- Select version ---
if ($Edge) {
    Write-Host "Using latest main (edge)..."
    git -C $InstallDir checkout main --quiet
    git -C $InstallDir reset --hard --quiet origin/main
} else {
    $latestTag = git -C $InstallDir tag --sort=-v:refname |
        Where-Object { $_ -notmatch '-rc' } |
        Select-Object -First 1
    if ($latestTag) {
        Write-Host "Using release $latestTag..."
        git -C $InstallDir checkout $latestTag --quiet
    } else {
        Write-Host "No releases found, using main branch..."
        git -C $InstallDir checkout main --quiet
        git -C $InstallDir reset --hard --quiet origin/main
    }
}

# --- Build ---
Write-Host "Building image... " -NoNewline
if ($Verbose) {
    Write-Host ""
    docker build -t $ImageName $InstallDir
} else {
    $buildLog = docker build -t $ImageName $InstallDir 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAILED" -ForegroundColor Red
        Write-Error "Build output:`n$($buildLog -join "`n")"
        exit 1
    }
    Write-Host "done"
}

# --- Remove old container ---
$existing = docker ps -a --format '{{.Names}}' | Where-Object { $_ -eq $ContainerName }
if ($existing) {
    Write-Host "Removing old container..."
    docker stop $ContainerName 2>$null | Out-Null
    docker rm $ContainerName | Out-Null
}

# --- Propagate host git identity ---
$gitCfgDir = Join-Path $env:USERPROFILE '.config\git'
if (-not (Test-Path $gitCfgDir)) { New-Item -ItemType Directory -Path $gitCfgDir -Force | Out-Null }
$gitCfgFile = Join-Path $gitCfgDir 'config'

$hostName  = git config --global user.name 2>$null
$hostEmail = git config --global user.email 2>$null
if ($hostName)  { git config --file $gitCfgFile user.name $hostName }
if ($hostEmail) { git config --file $gitCfgFile user.email $hostEmail }

# --- Seed default configs ---
$configDir = Join-Path $InstallDir '.config'
$workspaceDir = Join-Path $InstallDir 'workspace'
foreach ($dir in @($configDir, $workspaceDir)) {
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}

$starshipDest = Join-Path $configDir 'starship.toml'
if (-not (Test-Path $starshipDest)) {
    Copy-Item (Join-Path $InstallDir 'starship.toml') $starshipDest
}

$lazygitDir = Join-Path $configDir 'lazygit'
if (-not (Test-Path $lazygitDir)) { New-Item -ItemType Directory -Path $lazygitDir -Force | Out-Null }
$lazygitCfg = Join-Path $lazygitDir 'config.yml'
if (-not (Test-Path $lazygitCfg)) {
    @"
git:
  paging:
    colorArg: always
    pager: delta --dark --paging=never
"@ | Set-Content -Path $lazygitCfg
}

# --- Create container ---
Write-Host "Creating container..."

$dockerVolumes = @(
    '-v', "$workspaceDir`:/workspace"
    '-v', "$gitCfgDir`:/home/dev/.config/git"
    '-v', "${starshipDest}:/home/dev/.config/starship.toml"
    '-v', "${lazygitDir}:/home/dev/.config/lazygit"
)

# SSH: mount ~/.ssh read-only so git/ssh inside the container can use the
# host's keys and config. Windows named-pipe agent forwarding (\\.\pipe\...)
# into a Linux container's Unix socket is not reliably supported by Docker
# Desktop, so we don't attempt pipe forwarding — keys are available directly.
$sshDir = Join-Path $env:USERPROFILE '.ssh'
if (Test-Path $sshDir) {
    $dockerVolumes += @('-v', "${sshDir}:/home/dev/.ssh:ro")
}

# Drop all capabilities except those needed for scoped sudo
$dockerOpts = @(
    '--cap-drop=ALL'
    '--cap-add=CHOWN', '--cap-add=DAC_OVERRIDE', '--cap-add=FOWNER'
    '--cap-add=SETUID', '--cap-add=SETGID', '--cap-add=KILL'
)

$createResult = docker create -it --name $ContainerName @dockerOpts @dockerVolumes $ImageName 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create container '$ContainerName':`n$createResult"
    exit 1
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

# Append managed block. Use a single-quoted here-string so $PROFILE variables
# like @args aren't expanded at install time, then substitute the install path.
$profileBlock = @'
# >>> squarebox >>>
# squarebox shell integration - managed by install.ps1.
Remove-Item Alias:sqrbx, Alias:squarebox, Alias:sqrbx-rebuild, Alias:squarebox-rebuild -ErrorAction SilentlyContinue
function sqrbx { docker start -ai squarebox }
function squarebox { docker start -ai squarebox }
function sqrbx-rebuild { & "__INSTALL_DIR__\install.ps1" @args }
function squarebox-rebuild { sqrbx-rebuild @args }
# <<< squarebox <<<
'@
$profileBlock = $profileBlock -replace '__INSTALL_DIR__', $InstallDir
$profileBlock | Add-Content -Path $PROFILE

Write-Host "Installed squarebox shell integration -> $PROFILE"

# --- Start container ---
if ([System.Console]::IsInputRedirected) {
    Write-Host "Install complete. Run 'squarebox' (or 'sqrbx') to start."
} else {
    docker start -ai $ContainerName
}
