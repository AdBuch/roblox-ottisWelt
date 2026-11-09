param([string]$LuauPath = 'luau')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$harness = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'rome-geometry-harness.luau') -Raw
$modules = ''
foreach ($m in @(@('ColosseumLayout','src/shared/ColosseumLayout.luau'),@('RomeLayout','src/hub/server/Rome/RomeLayout.luau'),@('RomeParts','src/hub/server/Rome/RomeParts.luau'),@('StreetBuilder','src/hub/server/Rome/StreetBuilder.luau'),@('Smithy','src/hub/server/Rome/Smithy.luau'),@('HouseKit','src/hub/server/Rome/HouseKit.luau'),@('ForumTemple','src/hub/server/Rome/ForumTemple.luau'),@('CityShell','src/hub/server/Rome/CityShell.luau'),@('Harbor','src/hub/server/Rome/Harbor.luau'),@('IslandBuilder','src/hub/server/Rome/IslandBuilder.luau'))) {
    $source = Get-Content -LiteralPath (Join-Path $repo $m[1]) -Raw
    $modules += "modules." + $m[0] + " = (function()`n$source`nend)()`n"
}
$harness = $harness.Replace('-- INSERT_MODULES', $modules)
$temp = Join-Path ([System.IO.Path]::GetTempPath()) ('rome-geometry-' + [guid]::NewGuid() + '.luau')
try {
    [System.IO.File]::WriteAllText($temp, $harness)
    & $LuauPath $temp
    if ($LASTEXITCODE -ne 0) { throw 'Rome geometry check failed' }
} finally { Remove-Item -LiteralPath $temp -ErrorAction SilentlyContinue }
