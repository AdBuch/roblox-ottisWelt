param([string]$RojoExe = 'rojo')
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$buildRoot = Join-Path $repoRoot 'build'
New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null
$project = Get-Content (Join-Path $repoRoot 'places/arena.project.json') -Raw | ConvertFrom-Json -AsHashtable
$project.name = 'KrokoArenaTest'
$project.tree.Workspace = @{
    '$className' = 'Workspace'
    '$attributes' = @{ StudioBossChoice = 'Kroko' }
}
# build/ and places/ are siblings, so all project-relative source paths remain valid.
$testProject = Join-Path $buildRoot 'kroko-test.project.json'
$project | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $testProject -Encoding utf8
& $RojoExe build $testProject -o (Join-Path $buildRoot 'KrokoArenaTest.rbxlx')
if ($LASTEXITCODE -ne 0) { throw "Rojo build failed ($LASTEXITCODE)" }
