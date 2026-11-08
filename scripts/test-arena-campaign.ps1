param([string]$LuauPath = 'luau')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$source = @'
local modules = {}
local function require(name) return assert(modules[name], name) end
local script = { Parent = setmetatable({}, { __index = function(_, key) return key end }) }
local Vector3 = { new = function(...) return {...} end }
local Color3 = { fromRGB = function(...) return {...} end }
local records = {}
local store = {
    GetAsync = function(_, key) return records[key] end,
    UpdateAsync = function(_, key, transform)
        records[key] = transform(records[key])
        return records[key]
    end,
}
local mock = false
modules.EnvironmentConfig = { useMockData = function() return mock end, name = function() return "DEV" end }
local services = {
    ReplicatedStorage = { Shared = script.Parent },
    DataStoreService = { GetDataStore = function(_, name)
        assert(name == "OttiArenaCampaign_DEV_v1")
        return store
    end },
}
local game = { GetService = function(_, name) return assert(services[name]) end }
'@
foreach ($entry in @('shared/GameModeDefinitions','shared/ZombieDefinitions','shared/ZombieAttackDefinitions','shared/RoundDefinitions','server/ArenaCampaignProgress')) {
    $name = Split-Path -Leaf $entry
    $module = Get-Content -LiteralPath (Join-Path $repo "src/$entry.luau") -Raw
    $source += "`nmodules.$name = (function()`n$module`nend)()`n"
}
$source += @'
local campaign = modules.ArenaCampaignProgress
local first, second, third = {UserId = 24}, {UserId = 55}, {UserId = 124}
local pair = campaign.key("Coop", {first, second})
local otherPair = campaign.key("Coop", {first, third})
local solo = campaign.key("Solo", {first})
assert(pair == campaign.key("Coop", {second, first}))
assert(solo ~= campaign.key("Coop", {first}))
assert(campaign.loadStage(pair) == 1)
assert(campaign.beginBoss(pair, 1) and not campaign.beginBoss(pair, 1))
assert(not campaign.clearStage(pair, 2), "cannot skip Otti")
assert(campaign.clearStage(pair, 1) and campaign.clearStage(pair, 1))
assert(campaign.loadStage(pair) == 2 and campaign.loadStage(otherPair) == 1 and campaign.loadStage(solo) == 1)
assert(campaign.beginBoss(pair, 2), "first attempt is tracked independently per boss")
assert(campaign.clearStage(pair, 2) and campaign.loadStage(pair) == 3)
assert(campaign.clearStage(pair, 1) and campaign.loadStage(pair) == 3, "an older server cannot regress progress")
assert(campaign.clearStage(pair, 3) and campaign.loadStage(pair) == 3)
mock = true
assert(campaign.loadStage(pair) == 1 and campaign.clearStage(pair, 1), "Studio mock data is isolated")
mock = false
assert(campaign.loadStage(pair) == 3)

local waves = modules.RoundDefinitions
assert(waves.campaignVariant(1, 1, 1) == nil)
for round, total in { 4, 9, 16, 18, 20, 22 } do
    assert(waves.zombieCount("Solo", round, 1, 2) == total)
    assert(waves.zombieCount("Coop", round, 4, 2) == total)
    for i = 1, total do
        local expected = if i > 16 then "MountedPraetorian" else "TestudoLegionary"
        assert(waves.campaignVariant(2, round, i).Id == expected)
    end
end
local seen = {}
for i = 1, waves.zombieCount("Solo", 3, 1, 3) do
    seen[waves.campaignVariant(3, 3, i).Id] = true
end
assert(seen.ZombieNinja and seen.NunchakuNinja and seen.NinjaArcher and seen.TerracottaSamurai)
local zombies = modules.ZombieDefinitions.ById
assert(zombies.NinjaArcher.Special == "Archer" and zombies.NunchakuNinja.Gear.Weapon == "Nunchaku")
assert(zombies.TerracottaSamurai.Health > zombies.ZombieNinja.Health and zombies.TerracottaSamurai.WalkSpeed < zombies.ZombieNinja.WalkSpeed)
assert(modules.ZombieAttackDefinitions.forZombie("NunchakuNinja")[1].Steps[1].KnockdownSeconds > 0)
print("PASS: roster checkpoints, boss attempts and chapter wave rosters")
'@
$temp = Join-Path ([System.IO.Path]::GetTempPath()) ('arena-campaign-' + [guid]::NewGuid() + '.luau')
try {
    [System.IO.File]::WriteAllText($temp, $source)
    & $LuauPath $temp
    if ($LASTEXITCODE -ne 0) { throw 'Arena campaign checks failed' }
} finally {
    Remove-Item -LiteralPath $temp -ErrorAction SilentlyContinue
}
