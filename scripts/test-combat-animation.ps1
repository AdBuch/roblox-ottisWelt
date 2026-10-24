param([string]$LuauPath = 'luau', [string]$CompilePath = 'luau-compile')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$animator = Get-Content -LiteralPath (Join-Path $repo 'src/client/PlayerAnimator.luau') -Raw
$combat = Get-Content -LiteralPath (Join-Path $repo 'src/server/PlayerCombatService.luau') -Raw
$harness = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'combat-animation-harness.luau') -Raw
$harness = $harness.Replace('-- ANIMATOR_MODULE', "local function loadAnimator()`n$animator`nend`nlocal animator = loadAnimator()")
$animate = [regex]::Match($combat, '(?ms)^local function animate\(.*?^end').Value
if (-not $animate) { throw 'Missing server animation function' }
$harness = $harness.Replace('-- SERVER_ANIMATE', $animate)
$output = Join-Path $repo 'build/combat-animation-tests.luau'
New-Item -ItemType Directory -Path (Split-Path $output) -Force | Out-Null
[System.IO.File]::WriteAllText($output, $harness, [System.Text.UTF8Encoding]::new($false))
& $CompilePath (Join-Path $repo 'src/client/PlayerAnimator.luau') --null
if ($LASTEXITCODE -ne 0) { throw 'Animator syntax failed' }
& $CompilePath (Join-Path $repo 'src/server/PlayerCombatService.luau') --null
if ($LASTEXITCODE -ne 0) { throw 'Combat service syntax failed' }
& $LuauPath $output
if ($LASTEXITCODE -ne 0) { throw 'Animation behavior tests failed' }

if ($combat -match 'tweenWeld|TweenService|SHIELD_BASH|SHIELD_BRACE') { throw 'Equipment grip animation returned' }
if ($combat -notmatch 'weld.Part0 = limb' -or $combat -notmatch 'leftGrip \* SHIELD_GRIP') { throw 'Hand grip attachment missing' }
$moves = Get-Content -LiteralPath (Join-Path $repo 'src/shared/SpecialMoveDefinitions.luau') -Raw
$module = $animator.Substring(0, $animator.IndexOf('-- Block poses:'))
foreach ($name in ([regex]::Matches($moves, 'Anim = "([A-Za-z]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)) {
    if ($module -notmatch ([regex]::Escape($name) + '\s*=')) { throw "Missing body animation: $name" }
}
Write-Host 'PASS: fixed hand welds and all move animation names covered'
