# Validates that THIS checkout may be built for a publish target, without building or uploading
# anything. Every check stops the pipeline before an upload could happen:
#   * the target is in the allowlist (release/targets.json), complete and consistent with
#     src/shared/ExperienceConfig.luau (place ids, data store and memory store names)
#   * the working tree is clean (no uncommitted or untracked files) - unless -SkipCleanCheck for
#     a local dry run; the publish script never accepts an unclean state
#   * for targets with requireCommitOnOriginMain: HEAD is contained in origin/main
#   * rojo is exactly the pinned version (aftman.toml, release/tools.json)
#   * the profile schema and the Hub/Arena protocol versions can be read
# Prints what would be published where. Exit code 0 = valid.
#
#   .\scripts\release\Validate-Release.ps1 -Target DEV
param(
    [Parameter(Mandatory = $true)][string]$Target,
    [switch]$SkipCleanCheck
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ReleaseCommon.ps1')

$root = Get-RepoRoot
$state = Test-ReleasePreconditions $root $Target ([bool]$SkipCleanCheck)
Write-Host ''
Write-Host (Format-TargetTable $state.target $state.places)
Write-Host ''
if (-not $state.target.publishAllowed) { Write-Warn2 ("publishAllowed is false for " + $state.target.name + ": builds are possible, uploads are refused.") }
Write-Host 'VALID: this checkout may be built for the target above.'
exit 0
