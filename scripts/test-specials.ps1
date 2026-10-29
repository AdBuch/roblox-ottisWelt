param([string]$LuauPath = 'luau')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$modules = @('SpecialMoveDefinitions', 'WeaponAttackDefinitions', 'WeaponSpecialDefinitions', 'SpecialPracticeDefinitions', 'SpecialAnimationDefinitions', 'WeaponDefinitions', 'GladiatorLevelDefinitions', 'PlayerDataSchema', 'ArmorDefinitions', 'ShieldDefinitions', 'CurrencyConfig', 'Config')
$source = @'
local modules = {}
local paths = setmetatable({}, { __index = function(_, key) return key end })
local script = { Parent = paths }
local require = function(key) assert(modules[key], "Missing " .. tostring(key)); return modules[key] end
local Color3 = { fromRGB = function(...) return {...} end, new = function(...) return {...} end }
local Vector3 = { new = function(x, y, z) return { X = x, Y = y, Z = z } end }
local Enum = setmetatable({}, { __index = function() return paths end })
local typeof = type
local task = { spawn = function(fn, ...) fn(...) end }
local game = { GetService = function() return { Shared = paths } end }
'@
foreach ($name in $modules) {
    $body = Get-Content (Join-Path $repo "src/shared/$name.luau") -Raw
    $source += "`nmodules['$name'] = (function()`n$body`nend)()`n"
}
$inventory = Get-Content (Join-Path $repo 'src/server/InventoryService.luau') -Raw
$source += "`nlocal Inventory = (function()`n$inventory`nend)()`n"
$source += Get-Content (Join-Path $PSScriptRoot 'specials-harness.luau') -Raw
$output = Join-Path $repo 'build/specials-tests.luau'
New-Item -ItemType Directory -Path (Split-Path $output) -Force | Out-Null
[IO.File]::WriteAllText($output, $source, [Text.UTF8Encoding]::new($false))
& $LuauPath $output
if ($LASTEXITCODE -ne 0) { throw 'Special tests failed' }
