# Builds an isolated Studio test place; QA scripts are never included in the normal builds.
param([string]$OutputName = 'BossQA')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$project = Get-Content (Join-Path $repo 'places/arena.project.json') -Raw | ConvertFrom-Json -AsHashtable
# Paths are resolved from build/, at the same depth as places/.
$project.tree.ServerScriptService.HeroQA = @{ '$path' = '../scripts/boss-studio-qa.server.luau' }
$project.tree.StarterPlayer.StarterPlayerScripts.HeroQA = @{ '$path' = '../scripts/boss-studio-qa.client.luau' }
$project.tree.Workspace = @{ '$className' = 'Workspace'; '$attributes' = @{ StudioBossChoice = 'Otti' } }
New-Item -ItemType Directory -Force (Join-Path $repo 'build') | Out-Null
$path = Join-Path $repo 'build/boss-qa.project.json'
$project | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $path -Encoding utf8
& (Join-Path $HOME '.aftman/bin/rojo.exe') build $path -o (Join-Path $repo "build/$OutputName.rbxlx")
if ($LASTEXITCODE -ne 0) { throw 'Boss QA build failed' }
