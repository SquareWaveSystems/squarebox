#!/usr/bin/env pwsh
#Requires -Version 7.0

$ErrorActionPreference = 'Stop'
$Root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "lifecycle PowerShell regression: $Message" }
}

foreach ($name in @('install.ps1', 'uninstall.ps1')) {
    $path = Join-Path $Root $name
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    Assert-True ($errors.Count -eq 0) "$name has parser errors: $($errors -join '; ')"

    $releaseFunction = $ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Test-ReleaseTag'
    }, $true)
    Assert-True ($null -ne $releaseFunction) "$name has no Test-ReleaseTag function"
    Invoke-Expression $releaseFunction.Extent.Text
    Assert-True (Test-ReleaseTag 'v1.1.0') "$name rejects a stable tag"
    Assert-True (Test-ReleaseTag 'v1.1.0-rc.1') "$name rejects a prerelease tag"
    Assert-True (-not (Test-ReleaseTag 'v1.1.0-01')) "$name accepts a leading-zero prerelease"
    Assert-True (-not (Test-ReleaseTag 'v1.1.0+build-1')) "$name accepts excluded build metadata"
    Assert-True (-not (Test-ReleaseTag ("v1.1.0-" + ('a' * 122)))) "$name accepts a tag longer than 128 characters"
}

$installTokens = $null; $installErrors = $null
$installAst = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $Root 'install.ps1'), [ref]$installTokens, [ref]$installErrors)
Assert-True ($installErrors.Count -eq 0) "install.ps1 has parser errors: $($installErrors -join '; ')"
$digestFunction = $installAst.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -ceq 'Select-ImageRepoDigest'
}, $true)
Assert-True ($null -ne $digestFunction) 'install.ps1 has no exact RepoDigests selector'
Invoke-Expression $digestFunction.Extent.Text
$expectedDigest = 'ghcr.io/squarewavesystems/squarebox@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
$decoyDigest = 'ghcr.io/squarewavesystems/squarebox@sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'
Assert-True ((Select-ImageRepoDigest @($decoyDigest, $expectedDigest) $expectedDigest) -ceq $expectedDigest) `
    'multi-entry RepoDigests does not select the exact Candidate reference'
Assert-True (-not (Select-ImageRepoDigest @($decoyDigest) $expectedDigest)) `
    'RepoDigests selector accepts a different digest when the Candidate is absent'

$install = [IO.File]::ReadAllText((Join-Path $Root 'install.ps1'))
$uninstall = [IO.File]::ReadAllText((Join-Path $Root 'uninstall.ps1'))
Assert-True ($install.Contains('--userns=keep-id:uid=1000,gid=1000')) 'rootless Podman does not map host identity to dev'
Assert-True ($install.Contains("'--security-opt', 'label=disable'")) 'Podman does not disable private SELinux relabeling'
Assert-True (-not ($install -match ':ro,Z|BindSuffix.*:Z')) 'PowerShell adapter still emits private :Z binds'
Assert-True ($install.Contains('$HomeVolume -cne $State.HOME_VOLUME')) 'Managed-home identity comparison is not case-sensitive'
Assert-True ($install.Contains('$owner.Trim() -cne ''__INSTALL_ID__''')) 'generated adapter case-folds Install identity'
Assert-True (-not (($install + $uninstall) -match '\$owner(?:\.Trim\(\))?\s+-ne\s+\$InstallId')) 'ownership comparison uses case-insensitive -ne'
Assert-True ($install.Contains('Unable to verify ownership label')) 'installer does not fail closed on label inspection'
Assert-True ($uninstall.Contains('changed ownership after confirmation')) 'uninstaller does not revalidate ownership after planning'
Assert-True ($install.Contains('$script:RollbackArmed')) 'installer has no pre-state rollback transaction'
Assert-True ($install.Contains('$script:CandidateName')) 'installer has no temporary Candidate Box identity'
Assert-True ($install.Contains('& $Runtime rename $ContainerName $script:RollbackName')) 'installer does not preserve the prior Box before promotion'
Assert-True ($install.Contains('& $Runtime rename $script:CandidateName $ContainerName')) 'installer does not promote the Candidate Box by rename'
foreach ($boundary in @('checkout', 'image-alias', 'managed-home-create', 'managed-config', 'candidate-create', 'provision', 'old-box-preserved', 'candidate-promoted', 'state-publish')) {
    Assert-True ($install.Contains("Invoke-FailureInjection '$boundary'")) "installer lacks deterministic failure boundary '$boundary'"
}
Assert-True ($install.Contains('Malformed squarebox marker block') -and $uninstall.Contains('Malformed squarebox marker block')) 'profile marker validation is absent'
Assert-True ($install.Contains('[regex]::Replace($profileBlock')) 'profile interpolation can rescan inserted path placeholders'
Assert-True ($uninstall.Contains('Assert-PurgeCheckout')) 'purge does not revalidate checkout identity'
Assert-True ($install.Contains('Get-BoundedJson') -and $install.Contains('MaximumRetryCount 3')) 'release metadata HTTP is unbounded or lacks retries'
Assert-True ($install.Contains('{{range .RepoDigests}}{{println .}}{{end}}') -and -not $install.Contains('index .RepoDigests 0')) 'PowerShell trusts the first repository digest instead of enumerating identities'
Assert-True ($install -match '\$repoDigestOutput = @\(\)\s+if \(-not \$Build\)') 'local builds still derive identity from unordered RepoDigests'
Assert-True ($install.Contains('$SelectionStateFiles') -and $install.Contains('Selection state file must not be a reparse point or symlink')) 'PowerShell seeding can follow Workspace Selection links'

$schema = Get-Content -Raw (Join-Path $Root 'scripts/lib/install-state-schema.json') | ConvertFrom-Json
$cases = Get-Content -Raw (Join-Path $Root 'tests/fixtures/install-state-cases.json') | ConvertFrom-Json
$StateFields = @($schema.fields)
$Repo = 'https://github.com/SquareWaveSystems/squarebox.git'
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) "squarebox-state-$([guid]::NewGuid().ToString('N'))"
$UserHome = Join-Path $fixtureRoot 'home'
$fixtureInstall = Join-Path $fixtureRoot 'squarebox'
$stateDir = Join-Path $fixtureInstall '.squarebox'
[void](New-Item -ItemType Directory -Force $UserHome, $stateDir)

function Abort([string]$Message) { throw $Message }
try {
    foreach ($adapter in @('install.ps1', 'uninstall.ps1')) {
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $Root $adapter), [ref]$tokens, [ref]$errors)
        Assert-True ($errors.Count -eq 0) "$adapter has parser errors"
        foreach ($functionName in @('Test-ReleaseTag', 'Test-StatePath', 'Test-SamePath', 'Test-StateId', 'Assert-InstallState', 'Read-InstallState')) {
            $definition = $ast.Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                    $node.Name -ceq $functionName
            }, $true)
            Assert-True ($null -ne $definition) "$adapter has no $functionName function"
            Invoke-Expression $definition.Extent.Text
        }
        foreach ($case in $cases) {
            $values = [ordered]@{
                FORMAT = '1'; INSTALL_ID = 'test-install-123'; RUNTIME = 'docker'
                INSTALL_DIR = $fixtureInstall; WORKSPACE_DIR = (Join-Path $fixtureRoot 'workspace')
                GIT_CONFIG_DIR = (Join-Path $fixtureInstall '.squarebox/identity/git')
                HOME_VOLUME = 'squarebox-home'; CONTAINER_NAME = 'squarebox'; IMAGE_ALIAS = 'squarebox'
                IMAGE_REPOSITORY = 'ghcr.io/squarewavesystems/squarebox'
                IMAGE_REF = 'ghcr.io/squarewavesystems/squarebox@sha256:' + ('b' * 64)
                IMAGE_ID = 'sha256:' + ('c' * 64)
                IMAGE_DIGEST = 'ghcr.io/squarewavesystems/squarebox@sha256:' + ('b' * 64)
                SOURCE_REF = 'v1.2.3'; SOURCE_COMMIT = 'a' * 40; RELEASE_TAG = 'v1.2.3'
                REQUESTED_TAG = 'latest'; PUID = '1000'; PGID = '1000'; BUILD = '0'; EDGE = '0'
                SHELL_INIT = $PROFILE.CurrentUserAllHosts; SHELL_RC = $PROFILE.CurrentUserAllHosts
                ORIGIN = $Repo; HOME_VOLUME_ADOPTED = '0'
            }
            foreach ($property in $case.set.PSObject.Properties) {
                $fixtureValue = [string]$property.Value
                if ($fixtureValue.StartsWith('{ROOT}/', [StringComparison]::Ordinal)) {
                    $values[$property.Name] = $fixtureRoot + $fixtureValue.Substring('{ROOT}'.Length).Replace(
                        '/', [IO.Path]::DirectorySeparatorChar)
                } else {
                    $values[$property.Name] = $fixtureValue.Replace('{ROOT}', $fixtureRoot)
                }
            }
            $removed = @($case.remove)
            $lines = @($StateFields | Where-Object { $_ -cnotin $removed } | ForEach-Object { "$_=$($values[$_])" })
            $lines += @($case.append)
            $separator = if ($case.encoding -ceq 'crlf') { "`r`n" } else { [Environment]::NewLine }
            $stateFile = Join-Path $stateDir 'install-state'
            [IO.File]::WriteAllText($stateFile, (($lines -join $separator) + $separator), [Text.UTF8Encoding]::new($false))
            $accepted = $true
            try { [void](Read-InstallState $stateFile $fixtureInstall) } catch { $accepted = $false }
            Assert-True ($accepted -eq [bool]$case.accept) "$adapter fixture '$($case.name)' had unexpected result"
        }
    }
} finally {
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "ok - native PowerShell lifecycle syntax, safety, and $($cases.Count) shared state fixtures"
