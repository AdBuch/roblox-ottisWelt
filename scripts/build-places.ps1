# Builds both Places of the Otti Colosseum experience into build/ (git-ignored):
#   build/OttiHub.rbxlx    (start place)   from places/hub.project.json
#   build/OttiArena.rbxlx  (reserved arenas) from places/arena.project.json
# Usage (PowerShell, repository root):  .\scripts\build-places.ps1
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$rojo = Join-Path $HOME ".aftman\bin\rojo.exe"
if (-not (Test-Path $rojo)) { $rojo = "rojo" }
New-Item -ItemType Directory -Force (Join-Path $root "build") | Out-Null
& $rojo build (Join-Path $root "places\hub.project.json") -o (Join-Path $root "build\OttiHub.rbxlx")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $rojo build (Join-Path $root "places\arena.project.json") -o (Join-Path $root "build\OttiArena.rbxlx")
exit $LASTEXITCODE
