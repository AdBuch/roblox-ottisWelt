# Builds an isolated Studio test place for the lobby menu, inventory and touch rhombus.
# The QA scripts are never part of the normal builds (places/*.project.json).
# Works with Windows PowerShell 5.1 and PowerShell 7.
param([string]$OutputName = 'MenuQA', [string]$RojoExe = 'rojo')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$project = Get-Content (Join-Path $repo 'places/hub.project.json') -Raw | ConvertFrom-Json
$project.name = $OutputName
# Paths are resolved from build/, at the same depth as places/.
$project.tree.ServerScriptService | Add-Member -NotePropertyName MenuQA -NotePropertyValue ([pscustomobject]@{ '$path' = '../scripts/menu-studio-qa.server.luau' }) -Force
$project.tree.StarterPlayer.StarterPlayerScripts | Add-Member -NotePropertyName MenuQA -NotePropertyValue ([pscustomobject]@{ '$path' = '../scripts/menu-studio-qa.client.luau' }) -Force
New-Item -ItemType Directory -Force (Join-Path $repo 'build') | Out-Null
$path = Join-Path $repo 'build/menu-qa.project.json'
[System.IO.File]::WriteAllText($path, ($project | ConvertTo-Json -Depth 30), [System.Text.UTF8Encoding]::new($false))
& $RojoExe build $path -o (Join-Path $repo "build/$OutputName.rbxlx")
if ($LASTEXITCODE -ne 0) { throw 'Menu QA build failed' }
