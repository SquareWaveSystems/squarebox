#!/usr/bin/env pwsh
#Requires -Version 7.0

[CmdletBinding()]
param(
    [switch]$Purge,
    [Alias('y')][switch]$Yes,
    [switch]$Adopt,
    [switch]$Force,
    [ValidateSet('docker', 'podman')][string]$Runtime,
    [string]$InstallDir
)

$ErrorActionPreference = 'Stop'
$Repo = 'https://github.com/SquareWaveSystems/squarebox.git'
$UserHome = if ($IsWindows -and $env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
function Abort([string]$Message) { Write-Host "Error: $Message" -ForegroundColor Red; exit 1 }
$StateFields = @(
    'FORMAT', 'INSTALL_ID', 'RUNTIME', 'INSTALL_DIR', 'WORKSPACE_DIR', 'GIT_CONFIG_DIR',
    'HOME_VOLUME', 'CONTAINER_NAME', 'IMAGE_ALIAS', 'IMAGE_REPOSITORY', 'IMAGE_REF',
    'IMAGE_ID', 'IMAGE_DIGEST', 'SOURCE_REF', 'SOURCE_COMMIT', 'RELEASE_TAG',
    'REQUESTED_TAG', 'PUID', 'PGID', 'BUILD', 'EDGE', 'SHELL_INIT', 'SHELL_RC',
    'ORIGIN', 'HOME_VOLUME_ADOPTED'
)
function Test-ReleaseTag([string]$Value) {
    return $Value.Length -le 128 -and $Value -cmatch '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)(\.(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*))?$'
}
function Test-ReparsePoint([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    return $null -ne $item -and [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
}
function Test-StatePath([string]$Value) {
    if ([string]::IsNullOrEmpty($Value) -or $Value -match '[\x00-\x1f\x7f]' -or -not [IO.Path]::IsPathFullyQualified($Value)) { return $false }
    try { $full = [IO.Path]::GetFullPath($Value) } catch { return $false }
    return $Value -ceq $full
}
function Test-SamePath([string]$Left, [string]$Right) {
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    return [string]::Equals([IO.Path]::GetFullPath($Left), [IO.Path]::GetFullPath($Right), $comparison)
}
function Test-StateId([string]$Value) {
    $parsed = 0L
    return $Value -cmatch '^[0-9]{1,10}$' -and [long]::TryParse($Value, [ref]$parsed) -and $parsed -ge 1 -and $parsed -le 2147483647
}
function Assert-InstallState([hashtable]$State, [string]$Path, [string]$ExpectedInstallDir) {
    if ($State.FORMAT -ne '1' -or $State.INSTALL_ID -cnotmatch '^[A-Za-z0-9._-]{8,128}$') { Abort "Invalid Install identity: $Path" }
    if ($State.RUNTIME -cnotin @('docker', 'podman')) { Abort "Invalid Install identity: $Path (invalid RUNTIME)" }
    foreach ($name in @('INSTALL_DIR', 'WORKSPACE_DIR', 'GIT_CONFIG_DIR', 'SHELL_INIT', 'SHELL_RC')) {
        if (-not (Test-StatePath $State[$name])) { Abort "Invalid Install identity: $Path (invalid $name path)" }
    }
    if (-not (Test-SamePath $State.INSTALL_DIR $ExpectedInstallDir)) { Abort "Invalid Install identity: $Path (INSTALL_DIR mismatch)" }
    if ((Test-SamePath $State.INSTALL_DIR ([IO.Path]::GetPathRoot($State.INSTALL_DIR))) -or (Test-SamePath $State.INSTALL_DIR $UserHome)) {
        Abort "Invalid Install identity: $Path (unsafe INSTALL_DIR)"
    }
    if ((Test-SamePath $State.WORKSPACE_DIR ([IO.Path]::GetPathRoot($State.WORKSPACE_DIR))) -or
        (Test-SamePath $State.WORKSPACE_DIR $State.INSTALL_DIR) -or (Test-SamePath $State.WORKSPACE_DIR $UserHome)) {
        Abort "Invalid Install identity: $Path (unsafe WORKSPACE_DIR)"
    }
    if (-not (Test-SamePath $State.GIT_CONFIG_DIR ([IO.Path]::Combine($State.INSTALL_DIR, '.squarebox', 'identity', 'git')))) {
        Abort "Invalid Install identity: $Path (GIT_CONFIG_DIR is outside managed identity state)"
    }
    if (-not (Test-SamePath $State.SHELL_INIT $PROFILE.CurrentUserAllHosts) -or -not (Test-SamePath $State.SHELL_RC $PROFILE.CurrentUserAllHosts)) {
        Abort "Invalid Install identity: $Path (unexpected PowerShell profile path)"
    }
    if ($State.HOME_VOLUME -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$' -or
        $State.CONTAINER_NAME -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$' -or
        $State.IMAGE_ALIAS -cnotmatch '^[a-z0-9][a-z0-9._/-]*(:[A-Za-z0-9_][A-Za-z0-9_.-]{0,127})?$' -or
        $State.IMAGE_REPOSITORY -cnotmatch '^[a-z0-9][a-z0-9._/-]*$' -or
        $State.IMAGE_ID -cnotmatch '^(sha256:)?[0-9a-f]{64}$') {
        Abort "Invalid Install identity: $Path (invalid runtime or image resource identity)"
    }
    if ($State.IMAGE_DIGEST -and $State.IMAGE_DIGEST -cnotmatch '^[a-z0-9][a-z0-9._/-]*@sha256:[0-9a-f]{64}$') {
        Abort "Invalid Install identity: $Path (invalid IMAGE_DIGEST)"
    }
    if ($State.SOURCE_COMMIT -cnotmatch '^[0-9a-f]{40}$' -or -not (Test-StateId $State.PUID) -or -not (Test-StateId $State.PGID)) {
        Abort "Invalid Install identity: $Path (invalid source or host identity)"
    }
    if ($State.BUILD -notin @('0', '1') -or $State.EDGE -notin @('0', '1') -or $State.HOME_VOLUME_ADOPTED -notin @('0', '1') -or
        ($State.EDGE -eq '1' -and $State.BUILD -ne '1')) {
        Abort "Invalid Install identity: $Path (BUILD, EDGE, and HOME_VOLUME_ADOPTED must be 0 or 1)"
    }
    if ($State.ORIGIN -cne $Repo) { Abort "Invalid Install identity: $Path (noncanonical ORIGIN)" }
    if ($State.EDGE -eq '1') {
        if ($State.RELEASE_TAG -or $State.REQUESTED_TAG -or $State.SOURCE_REF -cne 'refs/remotes/origin/main') {
            Abort "Invalid Install identity: $Path (inconsistent edge source identity)"
        }
    } else {
        if (-not (Test-ReleaseTag $State.RELEASE_TAG) -or $State.SOURCE_REF -cne $State.RELEASE_TAG) {
            Abort "Invalid Install identity: $Path (invalid Release identity)"
        }
        if ($State.REQUESTED_TAG -and $State.REQUESTED_TAG -cne 'latest' -and
            (-not (Test-ReleaseTag $State.REQUESTED_TAG) -or $State.REQUESTED_TAG -cne $State.RELEASE_TAG)) {
            Abort "Invalid Install identity: $Path (invalid REQUESTED_TAG)"
        }
    }
    if ($State.BUILD -eq '1') {
        if ($State.IMAGE_REF -cne $State.IMAGE_ALIAS) { Abort "Invalid Install identity: $Path (built IMAGE_REF must equal IMAGE_ALIAS)" }
    } elseif ($State.RELEASE_TAG -cmatch '^v1\.0\.0(-rc.*)?$') {
        if ($State.IMAGE_REF -cne "$($State.IMAGE_REPOSITORY):$($State.RELEASE_TAG)" -or -not $State.IMAGE_DIGEST -or
            -not $State.IMAGE_DIGEST.StartsWith("$($State.IMAGE_REPOSITORY)@sha256:", [StringComparison]::Ordinal)) {
            Abort "Invalid Install identity: $Path (invalid legacy image identity)"
        }
    } elseif (-not $State.IMAGE_DIGEST -or $State.IMAGE_REF -cne $State.IMAGE_DIGEST -or
        -not $State.IMAGE_REF.StartsWith("$($State.IMAGE_REPOSITORY)@sha256:", [StringComparison]::Ordinal)) {
        Abort "Invalid Install identity: $Path (release image identities do not match)"
    }
}
function Read-InstallState([string]$Path, [string]$ExpectedInstallDir) {
    $state = @{}
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith('#')) { continue }
        $at = $line.IndexOf('='); if ($at -lt 1) { Abort "Malformed Install identity: $Path" }
        $key = $line.Substring(0, $at)
        if ($StateFields -cnotcontains $key) { Abort "Unknown Install identity field '$key': $Path" }
        if ($state.ContainsKey($key)) { Abort "Duplicate Install identity field '$key': $Path" }
        $value = $line.Substring($at + 1)
        if ($value -match "[`r`n]") { Abort "Malformed Install identity: $Path" }
        $state.Add($key, $value)
    }
    foreach ($key in $StateFields) {
        if (-not $state.ContainsKey($key)) { Abort "Missing Install identity field '$key': $Path" }
    }
    Assert-InstallState $state $Path $ExpectedInstallDir
    return $state
}
function Test-Origin([string]$Origin) {
    return @(
        'https://github.com/SquareWaveSystems/squarebox',
        'https://github.com/SquareWaveSystems/squarebox.git',
        'git@github.com:SquareWaveSystems/squarebox.git',
        'ssh://git@github.com/SquareWaveSystems/squarebox.git'
    ) -ccontains $Origin
}
function Assert-NoReparsePath([string]$Path) {
    $separators = [char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $current = [IO.Path]::GetFullPath($Path).TrimEnd($separators)
    while ($current) {
        if (Test-ReparsePoint $current) { Abort "Recorded purge path crosses a reparse point or symlink: $current" }
        $parent = [IO.Directory]::GetParent($current)
        if ($null -eq $parent -or (Test-SamePath $parent.FullName $current)) { break }
        $current = $parent.FullName
    }
}
function Assert-PurgeCheckout {
    if (-not (Test-Path -LiteralPath $InstallDir -PathType Container)) { return }
    Assert-NoReparsePath $InstallDir
    $origin = (& git -C $InstallDir remote get-url origin 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not (Test-Origin $origin)) {
        Abort 'Recorded install directory no longer has the expected origin; refusing purge.'
    }
}

if (-not $InstallDir) {
    if ($env:SQUAREBOX_DIR) { $InstallDir = $env:SQUAREBOX_DIR }
    elseif ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot '.squarebox\install-state'))) { $InstallDir = $PSScriptRoot }
    else { $InstallDir = Join-Path $UserHome 'squarebox' }
}
$InstallDir = [IO.Path]::GetFullPath($InstallDir)
$StateFile = Join-Path $InstallDir '.squarebox\install-state'
if ((Test-ReparsePoint (Join-Path $InstallDir '.squarebox')) -or (Test-ReparsePoint $StateFile)) {
    Abort 'Install identity state must not be reached through a reparse point or symlink.'
}
$State = $null
if (Test-Path -LiteralPath $StateFile -PathType Leaf) {
    $State = Read-InstallState $StateFile $InstallDir
} elseif ($Adopt) {
    $origin = (& git -C $InstallDir remote get-url origin 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not (Test-Origin $origin)) { Abort 'Legacy adoption requires an origin-verified squarebox checkout.' }
} else { Abort "No Install identity at $StateFile. Use -Adopt only for a verified legacy install." }

$InstallId = if ($State) { $State.INSTALL_ID } else { '' }
$RecordedRuntime = if ($State) { $State.RUNTIME } elseif ($env:SQUAREBOX_RUNTIME) { $env:SQUAREBOX_RUNTIME } else { '' }
if ($Runtime -and $State -and $Runtime -cne $RecordedRuntime -and -not $Force) { Abort "Runtime override differs from recorded '$RecordedRuntime'; use -Force only after verifying migration." }
if (-not $Runtime) { $Runtime = $RecordedRuntime }
if (-not $Runtime) {
    if (Get-Command docker -ErrorAction SilentlyContinue) { $Runtime = 'docker' }
    elseif (Get-Command podman -ErrorAction SilentlyContinue) { $Runtime = 'podman' }
    else { Abort 'No runtime recorded or installed; resource ownership cannot be checked.' }
}
if (-not (Get-Command $Runtime -ErrorAction SilentlyContinue)) { Abort "Recorded runtime '$Runtime' is not installed; resources were not removed." }
& $Runtime info 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Abort "$Runtime is installed but unreachable; this is not evidence that no resources exist." }

$WorkspaceDir = if ($State) { $State.WORKSPACE_DIR } else { Join-Path $InstallDir 'workspace' }
$ContainerName = if ($State) { $State.CONTAINER_NAME } else { 'squarebox' }
$ImageAlias = if ($State) { $State.IMAGE_ALIAS } else { 'squarebox' }
$ImageRef = if ($State) { $State.IMAGE_REF } else { 'squarebox' }
$ImageId = if ($State) { $State.IMAGE_ID } else { '' }
$HomeVolume = if ($State) { $State.HOME_VOLUME } elseif ($env:SQUAREBOX_HOME_VOLUME) { $env:SQUAREBOX_HOME_VOLUME } else { 'squarebox-home' }
$HomeVolumeAdopted = $State -and $State.HOME_VOLUME_ADOPTED -eq '1'
$ProfilePath = if ($State -and $State.SHELL_RC) { $State.SHELL_RC } else { $PROFILE.CurrentUserAllHosts }

function Get-ResourceOwner([ValidateSet('container', 'volume')][string]$Kind, [string]$Name) {
    if ($Kind -ceq 'container') {
        $value = (& $Runtime inspect -f '{{ index .Config.Labels "io.squarebox.install-id" }}' $Name 2>$null)
    } else {
        $value = (& $Runtime volume inspect -f '{{ index .Labels "io.squarebox.install-id" }}' $Name 2>$null)
    }
    if ($LASTEXITCODE -ne 0) { Abort "Unable to verify ownership label for $Kind '$Name'." }
    if ($value) { $value = $value.Trim() }
    if ($value -cin @('<no value>', '<nil>')) { return '' }
    return [string]$value
}

$ContainerOwned = $false; $ImageOwned = $false; $VolumeOwned = $false
& $Runtime container inspect $ContainerName 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
    $owner = Get-ResourceOwner container $ContainerName
    if ($State) {
        if ($owner -cne $InstallId) { Abort "Box '$ContainerName' is not owned by this Install identity." }
    } elseif ($owner) { Abort 'Legacy Box is labeled for another Install identity.' }
    $ContainerOwned = $true
}
& $Runtime image inspect $ImageAlias 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
    $observedImage = (& $Runtime image inspect -f '{{.Id}}' $ImageAlias).Trim()
    if ($State -and (-not $ImageId -or $observedImage -cne $ImageId)) { Abort "Image alias '$ImageAlias' does not match the recorded image." }
    $ImageOwned = $true
}
& $Runtime volume inspect $HomeVolume 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) {
    $owner = Get-ResourceOwner volume $HomeVolume
    if ($State -and -not $HomeVolumeAdopted) {
        if ($owner -cne $InstallId) { Abort "Managed home '$HomeVolume' is not owned by this Install identity." }
    } elseif ($owner -and (-not $State -or $owner -cne $InstallId)) { Abort 'Legacy adoption cannot claim a volume labeled for another identity.' }
    $VolumeOwned = $true
}

function Test-SquareboxProfileBlock([string]$Path) {
    if (Test-ReparsePoint $Path) { Abort "PowerShell profile must not be a reparse point or symlink: $Path" }
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { Abort "PowerShell profile is not a regular file: $Path" }
    $inside = $false; $blocks = 0
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if ($line -ceq '# >>> squarebox >>>') {
            if ($inside -or $blocks -gt 0) { Abort "Malformed squarebox marker block in $Path; the profile was preserved." }
            $inside = $true; $blocks++; continue
        }
        if ($line -ceq '# <<< squarebox <<<') {
            if (-not $inside) { Abort "Malformed squarebox marker block in $Path; the profile was preserved." }
            $inside = $false
        }
    }
    if ($inside) { Abort "Malformed squarebox marker block in $Path; the profile was preserved." }
    return $blocks -eq 1
}
function Remove-SquareboxProfileBlock([string]$Path) {
    if (-not (Test-SquareboxProfileBlock $Path)) { return }
    $filtered = [Collections.Generic.List[string]]::new(); $inside = $false
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if ($line -ceq '# >>> squarebox >>>') { $inside = $true; continue }
        if ($line -ceq '# <<< squarebox <<<') { $inside = $false; continue }
        if (-not $inside) { $filtered.Add($line) }
    }
    $temp = Join-Path (Split-Path $Path) ".squarebox-profile.$PID.$([guid]::NewGuid().ToString('N'))"
    try {
        [IO.File]::WriteAllLines($temp, $filtered, [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temp, $Path, $true)
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -Force -LiteralPath $temp }
    }
}
$ProfilePaths = @($ProfilePath, $PROFILE.CurrentUserCurrentHost) | Select-Object -Unique
$ProfileBlocks = [Collections.Generic.List[string]]::new()
foreach ($path in $ProfilePaths) {
    if (Test-SquareboxProfileBlock $path) {
        if ($State -and -not ([IO.File]::ReadAllLines($path) -ccontains "# squarebox-install-id=$InstallId")) {
            Abort "Recorded PowerShell adapter '$path' is not owned by this Install identity."
        }
        $ProfileBlocks.Add($path)
    }
}
$HasProfile = $ProfileBlocks.Count -gt 0
Write-Host 'squarebox uninstall'
Write-Host '==================='
Write-Host "Install identity: $(if ($InstallId) { $InstallId } else { 'legacy adoption' })"
Write-Host "Runtime:          $Runtime (reachable)"
Write-Host "Install dir:      $InstallDir"
Write-Host ''
Write-Host 'Will remove:'
$Anything = $false
if ($ContainerOwned) { Write-Host "  - Managed Box: $ContainerName"; $Anything = $true }
if ($ImageOwned) { Write-Host "  - Recorded image refs: $ImageAlias and $ImageRef"; $Anything = $true }
if ($HasProfile) { Write-Host "  - PowerShell adapter(s): $($ProfilePaths -join ', ')"; $Anything = $true }
if ($Purge -and (Test-Path $InstallDir)) { Write-Host "  - Recorded install directory: $InstallDir"; $Anything = $true }
if ($Purge -and $VolumeOwned) { Write-Host "  - Managed home: $HomeVolume"; $Anything = $true }
if (-not $Anything) { Write-Host '  (nothing)'; exit 0 }

if ($Purge -and $VolumeOwned -and ($HomeVolumeAdopted -or -not $State) -and -not $Force) {
    Abort "'$HomeVolume' is an adopted unlabeled volume; -Force is required to purge it."
}
if ($Purge -and (Test-Path $InstallDir)) {
    if ((Test-SamePath $InstallDir ([IO.Path]::GetPathRoot($InstallDir))) -or (Test-SamePath $InstallDir ([IO.Path]::GetFullPath($UserHome)))) { Abort "Unsafe recorded purge path '$InstallDir'." }
    Assert-PurgeCheckout
}
if (-not $Yes) {
    if ([Console]::IsInputRedirected) { Abort 'stdin is not a terminal; pass -Yes.' }
    if ((Read-Host 'Proceed? [y/N]') -notmatch '^[yY]([eE][sS])?$') { Write-Host 'Aborted.'; exit 1 }
}
if ($Purge -and -not $Yes -and (Test-Path -LiteralPath $WorkspaceDir -PathType Container)) {
    $workspaceCount = @(Get-ChildItem -Force -LiteralPath $WorkspaceDir -ErrorAction Stop).Count
    if ($workspaceCount -gt 0) {
        Write-Warning "Recorded Workspace contains $workspaceCount item(s): $WorkspaceDir"
        $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
        if ($WorkspaceDir.StartsWith($InstallDir + [IO.Path]::DirectorySeparatorChar, $comparison)) {
            Write-Host 'It will be removed with the install directory.'
        } else { Write-Host 'It is outside the install directory and will be preserved.' }
        if ((Read-Host 'Continue? [y/N]') -notmatch '^[yY]([eE][sS])?$') { Write-Host 'Aborted.'; exit 1 }
    }
}

if ($Purge) { Assert-PurgeCheckout }

Set-Location $UserHome
if ($ContainerOwned) {
    & $Runtime container inspect $ContainerName 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { Abort "Box '$ContainerName' changed after confirmation; refusing removal." }
    $owner = Get-ResourceOwner container $ContainerName
    if (($State -and $owner -cne $InstallId) -or (-not $State -and $owner)) {
        Abort "Box '$ContainerName' changed ownership after confirmation."
    }
    & $Runtime rm -f $ContainerName | Out-Null
    if ($LASTEXITCODE -ne 0) { Abort "Failed to remove managed Box '$ContainerName'." }
}
if ($ImageOwned) {
    foreach ($ref in @($ImageAlias, $ImageRef) | Select-Object -Unique) {
        & $Runtime image inspect $ref 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { continue }
        $refId = (& $Runtime image inspect -f '{{.Id}}' $ref).Trim()
        if ($State -and $refId -cne $ImageId) { Abort "Image ref '$ref' changed ownership during uninstall." }
        & $Runtime rmi $ref | Out-Null
        if ($LASTEXITCODE -ne 0) { Abort "Image ref '$ref' is still in use or could not be removed." }
    }
}
if ($HasProfile) {
    foreach ($path in $ProfileBlocks) { Remove-SquareboxProfileBlock $path }
}
if ($Purge -and $VolumeOwned) {
    & $Runtime volume inspect $HomeVolume 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { Abort "Managed home '$HomeVolume' changed after confirmation; refusing removal." }
    $owner = Get-ResourceOwner volume $HomeVolume
    if ($State -and -not $HomeVolumeAdopted) {
        if ($owner -cne $InstallId) { Abort 'Managed home changed ownership after confirmation.' }
    } elseif ($owner -and (-not $State -or $owner -cne $InstallId)) {
        Abort 'Adopted Managed home changed ownership after confirmation.'
    }
    & $Runtime volume rm $HomeVolume | Out-Null
    if ($LASTEXITCODE -ne 0) { Abort "Failed to remove Managed home '$HomeVolume'; it may still be in use." }
}
if ($Purge -and (Test-Path $InstallDir)) {
    Assert-PurgeCheckout
    Remove-Item -Recurse -Force -LiteralPath $InstallDir
}

Write-Host 'Uninstall complete.'
if (-not $Purge) {
    Write-Host "Preserved install identity and Workspace at $InstallDir."
    if ($VolumeOwned) { Write-Host "Preserved Managed home $HomeVolume." }
} elseif ((Test-Path $WorkspaceDir) -and -not $WorkspaceDir.StartsWith($InstallDir + [IO.Path]::DirectorySeparatorChar)) {
    Write-Host "Preserved external Workspace $WorkspaceDir."
}
Write-Host 'Start a new PowerShell session to drop loaded functions.'
