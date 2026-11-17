# Builds a RELEASE CANDIDATE: validates the checkout for a target (Validate-Release.ps1), builds
# BOTH places with the pinned rojo, hashes them and writes a release manifest. Optionally runs
# the local Luau test suites (release/tests.json) and records their results. Uploads nothing.
#
#   .\scripts\release\Build-Release.ps1 -Target DEV [-RunTests -LuauPath <luau.exe>]
#
# Output: build\release\<TARGET>-<commit12>\
#   OttiHub.rbxlx, OttiArena.rbxlx   the artefacts (git-ignored)
#   manifest.json                    commit, target, hashes, tool versions, schema, protocol, tests
#   summary.txt                      the same for a reviewer, one page
# The manifest is what the publish script trusts: it re-builds and compares the hashes before
# it uploads, so the artefacts cannot be swapped between build and upload.
param(
    [Parameter(Mandatory = $true)][string]$Target,
    [string]$OutputDir,
    [switch]$RunTests,
    [string]$LuauPath,
    [switch]$SkipCleanCheck
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ReleaseCommon.ps1')

$root = Get-RepoRoot
$state = Test-ReleasePreconditions $root $Target ([bool]$SkipCleanCheck)
$rt = $state.target
$git = $state.git

if (-not $OutputDir) { $OutputDir = Join-Path $root ('build\release\' + $rt.name + '-' + $git.shortCommit) }
# absolute, resolved against PowerShell's location (.NET would use the process directory)
$OutputDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDir)
if (Test-Path -LiteralPath $OutputDir) { Remove-Item -LiteralPath $OutputDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

Write-Step "Building both places with rojo $($state.rojo.version)"
$places = @()
foreach ($p in $state.places) {
    $out = Join-Path $OutputDir $p.file
    & $state.rojo.path build (Join-Path $root $p.project) -o $out
    if ($LASTEXITCODE -ne 0) { Fail ("rojo build failed for " + $p.project + " (exit " + $LASTEXITCODE + ")") }
    $item = Get-Item -LiteralPath $out
    $hash = Get-Sha256 $out
    Write-Ok ("{0,-5} {1,-16} {2,10:N0} bytes sha256 {3}" -f $p.role, $p.file, $item.Length, $hash)
    $places += [pscustomobject]@{
        role = $p.role
        project = $p.project
        file = $p.file
        bytes = $item.Length
        sha256 = $hash
        universeId = $rt.universeId
        placeId = if ($p.role -eq 'Hub') { $rt.hubPlaceId } else { $rt.arenaPlaceId }
        placeName = if ($p.role -eq 'Hub') { $rt.hubName } else { $rt.arenaName }
    }
}

# the Luau sources must at least parse (the same check the local tests rely on)
$tests = @()
$luau = Find-Luau $root $LuauPath
if ($RunTests) {
    if (-not $luau) { Fail '-RunTests needs a Luau runtime: pass -LuauPath or run Install-Tools.ps1.' }
    $compile = Join-Path (Split-Path -Parent $luau) ('luau-compile' + [System.IO.Path]::GetExtension($luau))
    Write-Step "Syntax check of every Luau source ($compile)"
    if (-not (Test-Path -LiteralPath $compile)) { Fail "luau-compile not found beside $luau" }
    $bad = @()
    foreach ($f in Get-ChildItem -LiteralPath (Join-Path $root 'src') -Recurse -Filter '*.luau') {
        $null = & $compile --binary $f.FullName 2>&1
        if ($LASTEXITCODE -ne 0) { $bad += $f.FullName.Substring($root.Length + 1) }
    }
    if ($bad.Count -gt 0) { Fail ("Luau syntax errors in: " + ($bad -join ', ')) }
    Write-Ok 'all sources compile'

    Write-Step "Local test suites (release/tests.json)"
    $suites = (Read-JsonFile (Join-Path $root 'release\tests.json')).suites
    foreach ($s in $suites) {
        $script = Join-Path $root $s.script
        $suiteArgs = @{ LuauPath = $luau }
        if ($s.PSObject.Properties.Name -contains 'args') {
            foreach ($a in $s.args.PSObject.Properties) {
                $value = $a.Value
                if ($a.Name -eq 'CompilePath') { $value = $compile }
                $suiteArgs[$a.Name] = $value
            }
        }
        $started = Get-Date
        $output = ''
        $ok = $false
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue' # a suite's stderr lines are output, not a stop (PowerShell 5.1)
        try {
            $global:LASTEXITCODE = 0
            $output = (& $script @suiteArgs 2>&1 | ForEach-Object { "$_" } | Out-String)
            $ok = ($LASTEXITCODE -eq 0)
        } catch {
            $output = $output + "`n" + $_.Exception.Message
            $ok = $false
        } finally { $ErrorActionPreference = $previous }
        $last = (($output -split "`n") | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 1)
        $required = [bool]$s.required
        $tests += [pscustomobject]@{
            script = $s.script
            required = $required
            passed = $ok
            seconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
            lastLine = if ($last) { $last.Trim() } else { '' }
        }
        $mark = if ($ok) { 'PASS' } elseif ($required) { 'FAIL' } else { 'fail (not required)' }
        Write-Host ("    {0,-20} {1}" -f $mark, $s.script)
        if (-not $ok -and $required) { Fail ("required test suite failed: " + $s.script + "`n" + $output) }
    }
}

Write-Step "Release manifest"
$manifest = [ordered]@{
    manifestVersion = 1
    createdAt = (Get-Date).ToUniversalTime().ToString('o')
    builtBy = $env:USERNAME
    builtOn = $env:COMPUTERNAME
    git = [ordered]@{
        commit = $git.commit
        branch = $git.branch
        describe = $git.describe
        clean = $git.clean
        onOriginMain = $git.onOriginMain
    }
    target = [ordered]@{
        name = $rt.name
        universeId = $rt.universeId
        environment = $rt.environment
        dataStoreName = $rt.dataStoreName
        memoryStoreNamespace = $rt.memoryStoreNamespace
        publishAllowed = $rt.publishAllowed
        requiresApproval = $rt.requiresApproval
    }
    tools = [ordered]@{
        rojo = $state.rojo.version
        luau = if ($luau) { $luau } else { $null }
        luauPinned = (Get-PinnedTools $root).luau.version
    }
    profileSchemaVersion = $state.schema
    protocol = [ordered]@{ version = $state.protocol.version; minCompatible = $state.protocol.minCompatible }
    places = $places
    tests = $tests
    publishLog = @()
}
$manifestPath = Join-Path $OutputDir 'manifest.json'
Write-JsonFile $manifestPath $manifest

$summary = @()
$summary += "OTTI COLOSSEUM RELEASE CANDIDATE"
$summary += ("commit   " + $git.commit + "  (" + $git.branch + ", " + $git.describe + ", clean=" + $git.clean + ", on origin/main=" + $git.onOriginMain + ")")
$summary += ("built    " + $manifest.createdAt + " with rojo " + $state.rojo.version)
$summary += ("profile  schema v" + $state.schema + "   protocol " + $state.protocol.version + " (min " + $state.protocol.minCompatible + ")")
$summary += (Format-TargetTable $rt $places)
if ($tests.Count -gt 0) {
    $summary += "tests"
    foreach ($t in $tests) { $summary += ("  {0,-5} {1}{2}" -f ($(if ($t.passed) { 'PASS' } else { 'FAIL' }), $t.script, $(if (-not $t.required) { '  (not required)' } else { '' }))) }
} else { $summary += "tests    not run (-RunTests)" }
$summary += ("manifest " + $manifestPath)
[System.IO.File]::WriteAllText((Join-Path $OutputDir 'summary.txt'), (($summary -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))

Write-Host ''
Write-Host ($summary -join "`n")
Write-Host ''
Write-Host 'BUILT. Nothing was uploaded. Publish with scripts\release\Publish-Release.ps1 -ManifestPath <manifest.json>.'
exit 0 # not the exit code of the last (optional) suite
