# Shared helpers of the release scripts (dot-sourced). Windows PowerShell 5.1 and PowerShell 7.
#   * repository, git state, pinned tools (release/tools.json, aftman.toml)
#   * the publish targets (release/targets.json) and their check against ExperienceConfig
#   * the versions the saved profile and the Hub/Arena protocol carry
# Nothing here uploads anything, and nothing here prints a secret.
Set-StrictMode -Version Latest

function Get-RepoRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Read-JsonFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "Missing file: $Path" }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Write-JsonFile([string]$Path, $Object) {
    $json = $Object | ConvertTo-Json -Depth 12
    [System.IO.File]::WriteAllText($Path, $json + "`n", [System.Text.UTF8Encoding]::new($false))
}

function Write-Step([string]$Text) { Write-Host ("==> " + $Text) }
function Write-Ok([string]$Text) { Write-Host ("    OK   " + $Text) }
function Write-Warn2([string]$Text) { Write-Host ("    WARN " + $Text) -ForegroundColor Yellow }
function Fail([string]$Text) { throw ("RELEASE CHECK FAILED: " + $Text) }

# ---------------------------------------------------------------- git
# Runs git and returns its output lines. Windows PowerShell 5.1 turns stderr lines into errors
# under $ErrorActionPreference = 'Stop', so the preference is relaxed for the call itself; the
# exit code decides. (`AllowFailure`: return the exit code instead of throwing.)
function Invoke-Git([string]$Root, [string[]]$Arguments, [switch]$AllowFailure) {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $raw = @(& git -C $Root @Arguments 2>&1)
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previous }
    $lines = @($raw | ForEach-Object { "$_" } | Where-Object { $_ -notmatch 'commit-graph' })
    if ($AllowFailure) { return $code }
    if ($code -ne 0) { throw ("git " + ($Arguments -join ' ') + " failed: " + ($lines -join "`n")) }
    return $lines
}

function Get-GitState([string]$Root) {
    $commit = [string]@(Invoke-Git $Root @('rev-parse', 'HEAD'))[0]
    $branch = [string]@(Invoke-Git $Root @('rev-parse', '--abbrev-ref', 'HEAD'))[0]
    $status = @(Invoke-Git $Root @('status', '--porcelain', '--untracked-files=normal'))
    $describe = ''
    try { $describe = [string]@(Invoke-Git $Root @('describe', '--tags', '--always', '--dirty'))[0] } catch { $describe = $commit.Substring(0, 12) }
    $onOriginMain = ((Invoke-Git $Root @('merge-base', '--is-ancestor', $commit, 'origin/main') -AllowFailure) -eq 0)
    return [pscustomobject]@{
        commit = $commit
        shortCommit = $commit.Substring(0, 12)
        branch = $branch
        describe = $describe
        dirtyEntries = $status
        clean = ($status.Count -eq 0)
        onOriginMain = $onOriginMain
    }
}

# ---------------------------------------------------------------- tools
function Get-PinnedTools([string]$Root) {
    return Read-JsonFile (Join-Path $Root 'release\tools.json')
}

function Get-ToolsDir([string]$Root) { return (Join-Path $Root '.tools') }

# Finds rojo: the repository's .tools (Install-Tools.ps1), then Aftman's bin, then PATH.
function Find-Rojo([string]$Root) {
    $candidates = @(
        (Join-Path (Get-ToolsDir $Root) 'rojo.exe'),
        (Join-Path (Get-ToolsDir $Root) 'rojo'),
        (Join-Path $HOME '.aftman\bin\rojo.exe'),
        (Join-Path $HOME '.aftman/bin/rojo')
    )
    foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { return $c } }
    $cmd = Get-Command rojo -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    Fail "rojo not found. Run scripts/release/Install-Tools.ps1 or 'aftman install'."
}

function Get-RojoVersion([string]$Rojo) {
    $text = (& $Rojo --version 2>&1 | Out-String).Trim()
    if ($text -match '(\d+\.\d+\.\d+)') { return $Matches[1] }
    Fail "Could not read the rojo version from '$text'."
}

function Assert-RojoPinned([string]$Root) {
    $pinned = (Get-PinnedTools $Root).rojo.version
    $aftman = Get-Content -LiteralPath (Join-Path $Root 'aftman.toml') -Raw
    if ($aftman -notmatch ('rojo-rbx/rojo@' + [regex]::Escape($pinned))) { Fail "aftman.toml and release/tools.json disagree about the rojo version ($pinned)." }
    $rojo = Find-Rojo $Root
    $version = Get-RojoVersion $rojo
    if ($version -ne $pinned) { Fail "rojo $version found at $rojo, but the release pipeline is pinned to rojo $pinned." }
    return [pscustomobject]@{ path = $rojo; version = $version }
}

# Finds the Luau runtime (for the test suites): -LuauPath, the repository's .tools, PATH.
function Find-Luau([string]$Root, [string]$Preferred) {
    if ($Preferred -and (Test-Path -LiteralPath $Preferred)) { return (Resolve-Path -LiteralPath $Preferred).Path }
    if ($Preferred -and (Get-Command $Preferred -ErrorAction SilentlyContinue)) { return (Get-Command $Preferred).Source }
    foreach ($c in @((Join-Path (Get-ToolsDir $Root) 'luau.exe'), (Join-Path (Get-ToolsDir $Root) 'luau'))) { if (Test-Path -LiteralPath $c) { return $c } }
    $cmd = Get-Command luau -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

# ---------------------------------------------------------------- sources: versions and ids
function Get-ExperienceConfigEnvironments([string]$Root) {
    $source = Get-Content -LiteralPath (Join-Path $Root 'src\shared\ExperienceConfig.luau') -Raw
    $result = @{}
    foreach ($name in @('DEV', 'PROD')) {
        $m = [regex]::Match($source, ('(?s)' + $name + '\s*=\s*table\.freeze\(\{(.*?)\}\s*::'))
        if (-not $m.Success) { Fail "ExperienceConfig.luau: environment ${name} not found." }
        $block = $m.Groups[1].Value
        $hub = [regex]::Match($block, 'HubPlaceId\s*=\s*(\d+)')
        $arena = [regex]::Match($block, 'ArenaPlaceId\s*=\s*(\d+)')
        $data = [regex]::Match($block, 'DataStoreName\s*=\s*"([^"]+)"')
        $memory = [regex]::Match($block, 'MemoryStoreNamespace\s*=\s*"([^"]+)"')
        if (-not ($hub.Success -and $arena.Success -and $data.Success -and $memory.Success)) { Fail "ExperienceConfig.luau: environment ${name} is incomplete." }
        $result[$name] = [pscustomobject]@{
            hubPlaceId = $hub.Groups[1].Value
            arenaPlaceId = $arena.Groups[1].Value
            dataStoreName = $data.Groups[1].Value
            memoryStoreNamespace = $memory.Groups[1].Value
        }
    }
    return $result
}

function Get-ProfileSchemaVersion([string]$Root) {
    $source = Get-Content -LiteralPath (Join-Path $Root 'src\shared\PlayerDataSchema.luau') -Raw
    $m = [regex]::Match($source, 'Version\s*=\s*(\d+)\s*,')
    if (-not $m.Success) { Fail 'PlayerDataSchema.luau: Version not found.' }
    return [int]$m.Groups[1].Value
}

function Get-ProtocolVersion([string]$Root) {
    $source = Get-Content -LiteralPath (Join-Path $Root 'src\shared\GameProtocol.luau') -Raw
    $v = [regex]::Match($source, 'Version\s*=\s*(\d+)\s*,')
    $min = [regex]::Match($source, 'MinCompatible\s*=\s*(\d+)\s*,')
    if (-not ($v.Success -and $min.Success)) { Fail 'GameProtocol.luau: Version / MinCompatible not found.' }
    return [pscustomobject]@{ version = [int]$v.Groups[1].Value; minCompatible = [int]$min.Groups[1].Value }
}

# ---------------------------------------------------------------- targets (the allowlist)
function Test-PlaceId([object]$Value) {
    return ($null -ne $Value) -and ("$Value" -match '^[1-9]\d{6,19}$')
}

# The target as configured, after every check that needs no network. Throws on anything unknown
# or incomplete, so a typo or a missing id stops long before an upload.
function Resolve-ReleaseTarget([string]$Root, [string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name)) { Fail 'No target given (-Target DEV | STAGING | PROD).' }
    $config = Read-JsonFile (Join-Path $Root 'release\targets.json')
    $names = @($config.targets.PSObject.Properties | ForEach-Object { $_.Name })
    $key = $names | Where-Object { $_ -ceq $Name }
    if (-not $key) { Fail ("Unknown target '" + $Name + "'. Allowed: " + ($names -join ', ') + " (release/targets.json).") }
    $t = $config.targets.$key
    foreach ($field in @('universeId', 'environment', 'dataStoreName', 'memoryStoreNamespace', 'apiKeyEnv')) {
        if (-not ($t.PSObject.Properties.Name -contains $field)) { Fail "Target $key has no field '$field'." }
    }
    if (-not (Test-PlaceId $t.universeId)) { Fail "Target ${key}: universeId is missing or malformed ('$($t.universeId)'). Fill release/targets.json first." }
    if (-not (Test-PlaceId $t.hub.placeId)) { Fail "Target ${key}: hub.placeId is missing or malformed ('$($t.hub.placeId)')." }
    if (-not (Test-PlaceId $t.arena.placeId)) { Fail "Target ${key}: arena.placeId is missing or malformed ('$($t.arena.placeId)')." }
    if ("$($t.hub.placeId)" -eq "$($t.arena.placeId)") { Fail "Target ${key}: hub and arena have the same place id." }
    if ($t.environment -notin @('DEV', 'PROD')) { Fail "Target ${key}: environment must be DEV or PROD." }

    $envs = Get-ExperienceConfigEnvironments $Root
    $env = $envs[$t.environment]
    if ($env.dataStoreName -ne $t.dataStoreName) { Fail "Target ${key}: dataStoreName '$($t.dataStoreName)' differs from ExperienceConfig $($t.environment) ('$($env.dataStoreName)')." }
    if ($env.memoryStoreNamespace -ne $t.memoryStoreNamespace) { Fail "Target ${key}: memoryStoreNamespace differs from ExperienceConfig $($t.environment)." }
    if ($key -in @('DEV', 'PROD')) {
        # the code must select exactly this environment on these places
        if ($env.hubPlaceId -ne "$($t.hub.placeId)") { Fail "Target ${key}: hub.placeId $($t.hub.placeId) is not the $($t.environment) HubPlaceId of ExperienceConfig ($($env.hubPlaceId))." }
        if ($env.arenaPlaceId -ne "$($t.arena.placeId)") { Fail "Target ${key}: arena.placeId $($t.arena.placeId) is not the $($t.environment) ArenaPlaceId of ExperienceConfig ($($env.arenaPlaceId))." }
    } else {
        # a staging experience must never carry PROD or DEV place ids: its servers would pick the wrong data
        foreach ($e in $envs.Values) {
            foreach ($id in @($e.hubPlaceId, $e.arenaPlaceId)) {
                if ($id -ne '0' -and ($id -eq "$($t.hub.placeId)" -or $id -eq "$($t.arena.placeId)")) { Fail "Target $key reuses place id $id of ExperienceConfig." }
            }
        }
    }
    if ($t.environment -eq 'PROD' -and ($env.hubPlaceId -eq '0' -or $env.arenaPlaceId -eq '0')) { Fail 'ExperienceConfig PROD place ids are 0: PROD is not configured in the code.' }
    if ($t.environment -eq 'DEV' -and ($env.hubPlaceId -eq '0' -or $env.arenaPlaceId -eq '0')) { Fail 'ExperienceConfig DEV place ids are 0.' }

    return [pscustomobject]@{
        name = $key
        description = $t.description
        universeId = "$($t.universeId)"
        hubPlaceId = "$($t.hub.placeId)"
        hubName = $t.hub.name
        arenaPlaceId = "$($t.arena.placeId)"
        arenaName = $t.arena.name
        environment = $t.environment
        dataStoreName = $t.dataStoreName
        memoryStoreNamespace = $t.memoryStoreNamespace
        publishAllowed = [bool]$t.publishAllowed
        requiresApproval = [bool]$t.requiresApproval
        requireCommitOnOriginMain = [bool]$t.requireCommitOnOriginMain
        apiKeyEnv = $t.apiKeyEnv
    }
}

# The two places as the Rojo projects define them.
function Get-PlaceDefinitions([string]$Root) {
    return @(
        [pscustomobject]@{ role = 'Hub'; project = 'places/hub.project.json'; file = 'OttiHub.rbxlx'; roleModule = 'src/hub/PlaceRole.luau' },
        [pscustomobject]@{ role = 'Arena'; project = 'places/arena.project.json'; file = 'OttiArena.rbxlx'; roleModule = 'src/arena/PlaceRole.luau' }
    )
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

# ---------------------------------------------------------------- the checks before any build
# Everything Validate-Release.ps1 prints and Build-Release.ps1 relies on. Throws on the first
# failed check; returns target, git state, rojo, versions and the place definitions.
function Test-ReleasePreconditions([string]$Root, [string]$TargetName, [bool]$AllowDirty) {
    Write-Step "Target allowlist (release/targets.json) and ExperienceConfig"
    $target = Resolve-ReleaseTarget $Root $TargetName
    Write-Ok ("target " + $target.name + " is allowlisted and matches ExperienceConfig " + $target.environment)

    Write-Step "Git state"
    $git = Get-GitState $Root
    Write-Ok ("commit " + $git.commit + " on " + $git.branch + " (" + $git.describe + ")")
    if (-not $git.clean) {
        $list = ($git.dirtyEntries | Select-Object -First 15) -join "`n      "
        if ($AllowDirty) { Write-Warn2 ("working tree is NOT clean (allowed for this local run only):`n      " + $list) }
        else { Fail ("the working tree is not clean. Commit or stash first:`n      " + $list) }
    } else { Write-Ok 'working tree clean' }
    if ($target.requireCommitOnOriginMain -and -not $git.onOriginMain) {
        Fail ("target " + $target.name + " requires a commit that is contained in origin/main; " + $git.shortCommit + " is not (push, review and merge it first).")
    }

    Write-Step "Pinned tools"
    $rojo = Assert-RojoPinned $Root
    Write-Ok ("rojo " + $rojo.version + " at " + $rojo.path)

    Write-Step "Versions in the sources"
    $schema = Get-ProfileSchemaVersion $Root
    $protocol = Get-ProtocolVersion $Root
    Write-Ok ("profile schema v" + $schema + ", protocol " + $protocol.version + " (min compatible " + $protocol.minCompatible + ")")

    Write-Step "Place projects"
    $places = Get-PlaceDefinitions $Root
    foreach ($p in $places) {
        foreach ($f in @($p.project, $p.roleModule)) {
            if (-not (Test-Path -LiteralPath (Join-Path $Root $f))) { Fail "missing $f" }
        }
        $roleSource = Get-Content -LiteralPath (Join-Path $Root $p.roleModule) -Raw
        if ($roleSource -notmatch ('return\s+"' + $p.role + '"')) { Fail ($p.roleModule + " does not return the role " + $p.role) }
    }
    Write-Ok 'both Rojo projects and their PlaceRole modules present'

    return [pscustomobject]@{ target = $target; git = $git; rojo = $rojo; schema = $schema; protocol = $protocol; places = $places }
}

# One line per place: which artefact goes to which place of which experience.
function Format-TargetTable($Target, $Places) {
    $lines = @()
    $lines += ("Target {0} ({1}): universe {2}, environment {3}, data {4}, memory {5}" -f $Target.name, $Target.description, $Target.universeId, $Target.environment, $Target.dataStoreName, $Target.memoryStoreNamespace)
    foreach ($p in $Places) {
        $placeId = if ($p.role -eq 'Hub') { $Target.hubPlaceId } else { $Target.arenaPlaceId }
        $placeName = if ($p.role -eq 'Hub') { $Target.hubName } else { $Target.arenaName }
        $hash = if ($p.PSObject.Properties.Name -contains 'sha256') { ' sha256 ' + $p.sha256 } else { '' }
        $lines += ("  {0,-5} {1,-28} -> place {2} ({3}){4}" -f $p.role, $p.file, $placeId, $placeName, $hash)
    }
    return ($lines -join "`n")
}
