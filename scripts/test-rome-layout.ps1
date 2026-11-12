param([string]$LuauPath = 'luau')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$test = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'rome-layout-test.luau') -Raw
$layout = Get-Content -LiteralPath (Join-Path $repo 'src/hub/server/Rome/RomeLayout.luau') -Raw
$test = $test.Replace('-- INSERT_LAYOUT', "local RomeLayout = (function()`n$layout`nend)()")
$temp = Join-Path ([System.IO.Path]::GetTempPath()) ('rome-layout-' + [guid]::NewGuid() + '.luau')
try {
    [System.IO.File]::WriteAllText($temp, $test)
    & $LuauPath $temp
    if ($LASTEXITCODE -ne 0) { throw 'Rome layout check failed' }
} finally { Remove-Item -LiteralPath $temp -ErrorAction SilentlyContinue }
