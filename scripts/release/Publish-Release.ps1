# Uploads a built release candidate (Build-Release.ps1 manifest) to its target through the Roblox
# Open Cloud API. The upload is the ONLY step of the pipeline that talks to Roblox, and it stops
# before any upload when something is off:
#   * the manifest's target is allowlisted, publishAllowed, and matches ExperienceConfig again
#   * the checkout is clean and HEAD is the manifest's commit (no -SkipCleanCheck here)
#   * both places are REBUILT with the pinned rojo and their hashes equal the manifest's: an
#     artefact that does not reproduce is never uploaded
#   * targets with requiresApproval need -ApprovalReference (who approved, where) in the log
#   * the API key comes from the environment variable the target names (targets.json apiKeyEnv),
#     or from a hidden prompt; it is sent as a header, never put on a command line, never printed
#
# Modes:
#   default           SAVE a new version of both places (versionType=Saved): nothing goes live.
#                     A reviewer can open the saved versions in Studio / the version history.
#   -Publish          PUBLISH both places (versionType=Published): new servers use the version.
#   -DryRun           no network at all: print exactly which file would go to which place.
#   -Only Hub|Arena   retry one place after a partial failure (see "partial failure" below).
#
# Partial failure between the two uploads: the Hub is uploaded first, the Arena second. If the
# Arena upload fails after the Hub was published, the Hub is live with the new version and the
# Arena with the old one. The log records state "PARTIAL" with the Hub's new version number;
# the Arena's protocol check (GameProtocol.MinCompatible) keeps incompatible tickets out until
# either the Arena is published too (-Only Arena with the same manifest) or the Hub is rolled
# back to its previous version in the Creator Hub (docs/RELEASE_PROCESS.md, "Rollback").
#
#   .\scripts\release\Publish-Release.ps1 -ManifestPath build\release\DEV-abc123\manifest.json -DryRun
#   .\scripts\release\Publish-Release.ps1 -ManifestPath ... -Target DEV            (save only)
#   .\scripts\release\Publish-Release.ps1 -ManifestPath ... -Target DEV -Publish   (go live)
param(
    [Parameter(Mandatory = $true)][string]$ManifestPath,
    [string]$Target,
    [switch]$Publish,
    [switch]$DryRun,
    [ValidateSet('Both', 'Hub', 'Arena')][string]$Only = 'Both',
    [string]$ApprovalReference,
    [int]$TimeoutSeconds = 600
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ReleaseCommon.ps1')

$root = Get-RepoRoot
$ManifestPath = (Resolve-Path -LiteralPath $ManifestPath).Path
$manifest = Read-JsonFile $ManifestPath
$outputDir = Split-Path -Parent $ManifestPath
if ($manifest.manifestVersion -ne 1) { Fail "unsupported manifest version $($manifest.manifestVersion)" }
if (-not $Target) { $Target = $manifest.target.name }
if ($Target -cne $manifest.target.name) { Fail ("the manifest was built for target " + $manifest.target.name + ", not " + $Target + ". Build again for the right target.") }

Write-Step "Target and allowlist"
$rt = Resolve-ReleaseTarget $root $Target
foreach ($pair in @(@('universeId', $manifest.target.universeId), @('environment', $manifest.target.environment), @('dataStoreName', $manifest.target.dataStoreName))) {
    if ("$($rt.($pair[0]))" -ne "$($pair[1])") { Fail ("manifest " + $pair[0] + " '" + $pair[1] + "' differs from release/targets.json '" + $rt.($pair[0]) + "'") }
}
foreach ($p in $manifest.places) {
    $expected = if ($p.role -eq 'Hub') { $rt.hubPlaceId } else { $rt.arenaPlaceId }
    if ("$($p.placeId)" -ne $expected) { Fail ("manifest place id " + $p.placeId + " for " + $p.role + " differs from the allowlist (" + $expected + ")") }
}
if (-not $rt.publishAllowed) { Fail ("publishAllowed is false for " + $rt.name + " (release/targets.json). Nothing is uploaded.") }
if ($rt.requiresApproval -and -not $DryRun) {
    if ([string]::IsNullOrWhiteSpace($ApprovalReference)) { Fail ("target " + $rt.name + " requires -ApprovalReference (who approved this release and where it is recorded).") }
}
Write-Ok ("target " + $rt.name + " allowlisted, publishAllowed")

Write-Step "Git state against the manifest"
$git = Get-GitState $root
if (-not $git.clean) { Fail ("the working tree is not clean:`n      " + (($git.dirtyEntries | Select-Object -First 15) -join "`n      ")) }
if ($git.commit -ne $manifest.git.commit) { Fail ("HEAD is " + $git.shortCommit + " but the manifest was built from " + $manifest.git.commit.Substring(0, 12) + ". Check out that commit or build again.") }
if ($rt.requireCommitOnOriginMain -and -not $git.onOriginMain) { Fail ("target " + $rt.name + " requires a commit contained in origin/main.") }
if ($manifest.git.clean -ne $true) { Fail 'the manifest was built from an unclean tree (SkipCleanCheck). Build again from a clean checkout.' }
Write-Ok ("HEAD " + $git.shortCommit + " equals the manifest, tree clean")

Write-Step "Rebuilding both places and comparing with the manifest"
$rojo = Assert-RojoPinned $root
if ($rojo.version -ne $manifest.tools.rojo) { Fail ("rojo " + $rojo.version + " now, but the manifest was built with rojo " + $manifest.tools.rojo) }
$check = Join-Path $outputDir ('rebuild-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $check | Out-Null
try {
    foreach ($p in $manifest.places) {
        $out = Join-Path $check $p.file
        & $rojo.path build (Join-Path $root $p.project) -o $out
        if ($LASTEXITCODE -ne 0) { Fail ("rojo build failed for " + $p.project) }
        $hash = Get-Sha256 $out
        $artefact = Join-Path $outputDir $p.file
        if (-not (Test-Path -LiteralPath $artefact)) { Fail ("artefact missing: " + $artefact) }
        $onDisk = Get-Sha256 $artefact
        if ($hash -ne $p.sha256) { Fail ($p.role + ": the rebuild (sha256 " + $hash + ") differs from the manifest (" + $p.sha256 + "). The build does not reproduce; nothing is uploaded.") }
        if ($onDisk -ne $p.sha256) { Fail ($p.role + ": the artefact on disk (sha256 " + $onDisk + ") differs from the manifest (" + $p.sha256 + ").") }
        Write-Ok ("{0,-5} reproduces: sha256 {1}" -f $p.role, $hash)
    }
} finally { Remove-Item -LiteralPath $check -Recurse -Force -ErrorAction SilentlyContinue }

$versionType = if ($Publish) { 'Published' } else { 'Saved' }
$selected = @($manifest.places | Where-Object { $Only -eq 'Both' -or $_.role -eq $Only })
Write-Host ''
Write-Host (Format-TargetTable $rt $selected)
Write-Host ("  mode: " + $(if ($DryRun) { 'DRY RUN (no network)' } else { $versionType + ' version' }) + ", places: " + $Only)
Write-Host ''
if ($DryRun) {
    Write-Host 'DRY RUN: nothing was uploaded.'
    exit 0
}

# ---------------------------------------------------------------- the API key (never printed)
$apiKey = [Environment]::GetEnvironmentVariable($rt.apiKeyEnv)
$keySource = 'environment variable ' + $rt.apiKeyEnv
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    if ([Environment]::UserInteractive -and -not $env:CI) {
        $secure = Read-Host ("Open Cloud API key for " + $rt.name + " (input hidden; or set " + $rt.apiKeyEnv + ")") -AsSecureString
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try { $apiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        $keySource = 'hidden prompt'
    }
}
if ([string]::IsNullOrWhiteSpace($apiKey)) { Fail ("no API key: set the environment variable " + $rt.apiKeyEnv + " (see docs/RELEASE_PROCESS.md, Secrets).") }
if ($apiKey.Length -lt 20) { Fail 'the API key looks truncated.' }

# ---------------------------------------------------------------- upload
$log = @()
function Add-Log([string]$Role, [string]$Step, [string]$State, [string]$Detail, $Version) {
    $entry = [ordered]@{ at = (Get-Date).ToUniversalTime().ToString('o'); role = $Role; step = $Step; state = $State; detail = $Detail; versionNumber = $Version }
    $script:log += [pscustomobject]$entry
    Write-Host ("    {0,-8} {1,-5} {2,-10} {3}{4}" -f $State, $Role, $Step, $Detail, $(if ($null -ne $Version) { ' version ' + $Version } else { '' }))
}
function Save-Log([string]$State) {
    $entry = [ordered]@{
        at = (Get-Date).ToUniversalTime().ToString('o')
        target = $rt.name
        mode = $versionType
        only = $Only
        state = $State
        approvalReference = $ApprovalReference
        keySource = $keySource
        operator = $env:USERNAME
        steps = $script:log
    }
    $existing = @()
    if ($manifest.PSObject.Properties.Name -contains 'publishLog' -and $null -ne $manifest.publishLog) { $existing = @($manifest.publishLog) }
    $manifest.publishLog = @($existing + [pscustomobject]$entry)
    Write-JsonFile $ManifestPath $manifest
    [System.IO.File]::AppendAllText((Join-Path $outputDir 'publish-log.jsonl'), (([pscustomobject]$entry | ConvertTo-Json -Depth 8 -Compress) + "`n"), [System.Text.UTF8Encoding]::new($false))
}

function Invoke-PlaceUpload($Place, [string]$Type) {
    $uri = "https://apis.roblox.com/universes/v1/$($rt.universeId)/places/$($Place.placeId)/versions?versionType=$Type"
    $file = Join-Path $outputDir $Place.file
    $headers = @{ 'x-api-key' = $apiKey; 'Content-Type' = 'application/xml' }
    $previous = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -InFile $file -TimeoutSec $TimeoutSeconds
    } catch {
        $status = ''
        try { $status = [int]$_.Exception.Response.StatusCode } catch { }
        $message = $_.Exception.Message -replace [regex]::Escape($apiKey), '***'
        throw ("upload of " + $Place.role + " failed (HTTP " + $status + "): " + $message)
    } finally { $ProgressPreference = $previous }
    if ($null -eq $response -or -not ($response.PSObject.Properties.Name -contains 'versionNumber')) { throw ("upload of " + $Place.role + ": the API returned no versionNumber") }
    return [int]$response.versionNumber
}

Write-Step ("Uploading (" + $versionType + ") to " + $rt.name + " - key from " + $keySource)
$state = 'OK'
$done = 0
try {
    foreach ($p in $selected) {
        $version = Invoke-PlaceUpload $p $versionType
        Add-Log $p.role $versionType 'OK' ("place " + $p.placeId + " sha256 " + $p.sha256.Substring(0, 12)) $version
        $done += 1
    }
} catch {
    $failedRole = if ($done -lt $selected.Count) { $selected[$done].role } else { '?' }
    $detail = $_.Exception.Message -replace [regex]::Escape($apiKey), '***'
    Add-Log $failedRole $versionType 'FAILED' $detail $null
    $state = if ($done -gt 0 -and $Only -eq 'Both') { 'PARTIAL' } else { 'FAILED' }
}
$apiKey = $null
Save-Log $state
Write-Host ''
if ($state -eq 'OK') {
    Write-Host ("DONE: " + $selected.Count + " place(s) " + $versionType.ToLower() + " on " + $rt.name + ". Log: " + (Join-Path $outputDir 'publish-log.jsonl'))
    exit 0
}
if ($state -eq 'PARTIAL') {
    Write-Host ("PARTIAL: the " + $selected[0].role + " upload succeeded, the " + $selected[1].role + " upload failed.") -ForegroundColor Yellow
    if ($Publish) {
        Write-Host ("  The " + $selected[0].role + " is LIVE with the new version while the " + $selected[1].role + " still runs the old one.") -ForegroundColor Yellow
        Write-Host ("  Either retry:   Publish-Release.ps1 -ManifestPath '" + $ManifestPath + "' -Publish -Only " + $selected[1].role + $(if ($ApprovalReference) { " -ApprovalReference '" + $ApprovalReference + "'" } else { '' })) -ForegroundColor Yellow
        Write-Host ("  or roll back the " + $selected[0].role + " to its previous version in the Creator Hub (docs/RELEASE_PROCESS.md, Rollback).") -ForegroundColor Yellow
    } else {
        Write-Host ("  Nothing is live (saved versions only). Retry with -Only " + $selected[1].role + ".") -ForegroundColor Yellow
    }
    exit 2
}
Write-Host 'FAILED: nothing was changed on the target.' -ForegroundColor Red
exit 1
