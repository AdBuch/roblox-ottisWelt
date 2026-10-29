param([string]$LuauPath = 'luau')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$harness = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'lobby-ring-harness.luau') -Raw
$defs = Get-Content -LiteralPath (Join-Path $repo 'src/shared/LobbyPadDefinitions.luau') -Raw
$builder = Get-Content -LiteralPath (Join-Path $repo 'src/server/LobbyService.luau') -Raw
$mosaics = Get-Content -LiteralPath (Join-Path $repo 'src/server/ShopBattleMosaics.luau') -Raw
$harness = $harness.Replace('-- INSERT_DEFINITIONS', "modules.LobbyPadDefinitions = (function()`n$defs`nend)()")
$harness = $harness.Replace('-- INSERT_BUILDER', "modules.LobbyService = (function()`n$builder`nend)()")
$harness = $harness.Replace('-- INSERT_BATTLE_MOSAICS', "modules.ShopBattleMosaics = (function()`n$mosaics`nend)()")
foreach ($module in @(@('LAYOUT','src/shared/ColosseumLayout.luau','ColosseumLayout'),@('GATE','src/server/ColosseumGate.luau','ColosseumGate'),@('ARENA','src/server/Arena.luau','Arena'),@('ARCHITECTURE','src/server/LobbyArchitecture.luau','LobbyArchitecture'))) {
    $source = Get-Content -LiteralPath (Join-Path $repo $module[1]) -Raw
    $harness = $harness.Replace(('-- INSERT_' + $module[0]), ('modules.' + $module[2] + " = (function()`n$source`nend)()"))
}
$temp = Join-Path ([System.IO.Path]::GetTempPath()) ('lobby-ring-' + [guid]::NewGuid() + '.luau')
try {
    [System.IO.File]::WriteAllText($temp, $harness)
    & $LuauPath $temp
    if ($LASTEXITCODE -ne 0) { throw 'Lobby ring geometry check failed' }
} finally { Remove-Item -LiteralPath $temp -ErrorAction SilentlyContinue }
