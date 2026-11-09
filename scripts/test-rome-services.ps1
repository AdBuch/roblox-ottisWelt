param([string]$LuauPath = 'luau')
# Rome's counters (smith and oracle) against the REAL sources: TownServices, InventoryService
# (forge stage, one-step charge, profile v9 migration and save data), ForgeDefinitions and
# OracleDefinitions. Players, characters, remotes and the clock are small mocks.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

function Wrap([string]$key, [string]$path) {
    $source = Get-Content -LiteralPath (Join-Path $repo $path) -Raw
    return "`nsources[`"$key`"] = function(script)`n$source`nend`n"
}

$harness = @'
local checks = 0
local function check(ok, message) if not ok then error("FAIL: " .. message, 2) end checks += 1 end
local V = {}
V.__index = V
local function vec(x, y, z) return setmetatable({ X = x, Y = y, Z = z }, V) end
V.__sub = function(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V.__index = function(a, k) if k == "Magnitude" then return math.sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z) end return V[k] end
local Vector3 = { new = vec }
local Vector2 = { new = function(x, y) return { X = x, Y = y } end }
local Color3 = { fromRGB = function(...) return { ... } end, new = function(...) return { ... } end }
local Enum = setmetatable({}, { __index = function(_, a) return setmetatable({}, { __index = function(_, b) return a .. "." .. b end }) end })
local function signal() return { Connect = function() return { Disconnect = function() end } end } end
local sources, loaded, mocks = {}, {}, {}
local function folder(prefix)
	return setmetatable({}, { __index = function(_, name) return prefix .. "/" .. name end })
end
local function require(key)
	if mocks[key] then return mocks[key] end
	if loaded[key] == nil then
		local fn = assert(sources[key], "unmapped require " .. tostring(key))
		loaded[key] = fn({ Parent = folder(key:match("^(.-)/")) })
	end
	return loaded[key]
end
local services = {
	ReplicatedStorage = { Shared = folder("Shared") },
	Players = { PlayerRemoving = signal(), PlayerAdded = signal(), GetPlayers = function() return {} end },
	HttpService = { GenerateGUID = function() return "guid" end },
}
local game = { GetService = function(_, name) return assert(services[name], "service " .. name) end }
local function newPlayer(id)
	local p = { UserId = id, Name = "P" .. id, attrs = { GameState = "LOBBY", Location = "Lobby" } }
	function p:GetAttribute(k) return self.attrs[k] end
	function p:SetAttribute(k, v) self.attrs[k] = v end
	return p
end
'@
foreach ($name in 'ArmorDefinitions','Config','CurrencyConfig','GladiatorLevelDefinitions','PlayerDataSchema','ShieldDefinitions','WeaponDefinitions','SpecialMoveDefinitions','GameStates','WeaponBalanceConfig','WeaponSpecialDefinitions','WeaponAttackDefinitions','SpecialPracticeDefinitions','ForgeDefinitions','OracleDefinitions') {
    $harness += Wrap "Shared/$name" "src/shared/$name.luau"
}
$harness += Wrap "Server/InventoryService" "src/server/InventoryService.luau"
$harness += Wrap "Rome/TownServices" "src/hub/server/Rome/TownServices.luau"
$harness += @'

local Inv = require("Server/InventoryService")
local Forge = require("Shared/ForgeDefinitions")
local Oracle = require("Shared/OracleDefinitions")
local Levels = require("Shared/GladiatorLevelDefinitions")
local Weapons = require("Shared/WeaponDefinitions")
local Balance = require("Shared/WeaponBalanceConfig")
local Moves = require("Shared/SpecialMoveDefinitions")
local Town = require("Rome/TownServices")

local now = 100
local ready = {}
local roots = {}
local events = {}
local tokens = 0
Town.init({
	inventory = Inv,
	isReady = function(p) return ready[p] ~= false end,
	rootOf = function(p) return roots[p] end,
	fire = function(p, kind, payload) table.insert(events, { player = p, kind = kind, payload = payload }) end,
	now = function() return now end,
	token = function() tokens += 1 return "T" .. tokens end,
}, function() return vec(0, 0, 0) end, function() return vec(100, 0, 0) end)
local function last() return events[#events] end
local function tick() now += 1 end

local p = newPlayer(1)
Inv.load(p, nil, 0, 0, nil)
roots[p] = { Position = vec(40, 0, 0) }
-- FORGE: too far away -> refused, no offer
Town.openForge(p)
check(last().kind == "Refused", "smith refuses a player far away")
roots[p] = { Position = vec(5, 0, 0) }
Town.openForge(p)
local offer = last().payload
check(last().kind == "ForgeOffer" and #offer.items == 1 and offer.items[1].weaponId == Weapons.Starter, "offer lists the owned starter weapon only")
local item = offer.items[1]
local basic = Moves[Weapons.ById[item.weaponId].Basic].Damage
check(item.price == Forge.price(item.weaponId, 0) and item.price >= Forge.MinPrice, "server price shown")
check(item.basicNow == math.floor(basic * Balance.pveFactor(item.weaponId) + 0.5) and item.basicNext == math.floor(basic * Balance.pveFactor(item.weaponId) * (1 + Forge.PvEBonus) + 0.5) and item.basicNext > item.basicNow, "real values now and after the improvement")
-- not enough Denarii: nothing changes
local r = Town.request(p, "ForgeUpgrade", { token = offer.token, weaponId = item.weaponId, level = 0 })
check(not r.ok and Inv.getDenarii(p) == 0 and Inv.forgeLevel(p, item.weaponId) == 0, "no upgrade without Denarii")
tick()
Inv.addDenarii(p, 100)
r = Town.request(p, "ForgeUpgrade", { token = offer.token, weaponId = item.weaponId, level = 0 })
check(r.ok and Inv.getDenarii(p) == 100 - item.price and Inv.forgeLevel(p, item.weaponId) == 1, "upgrade charges once and raises the stage")
check(p.attrs.ForgeLevels == item.weaponId .. ":1" and r.items[1].level == 1, "stage published and returned")
-- a second confirmation of the same offer: refused, no second charge
r = Town.request(p, "ForgeUpgrade", { token = offer.token, weaponId = item.weaponId, level = 0 })
check(not r.ok and r.message:find("Moment"), "a double click inside the interval is held back")
tick()
r = Town.request(p, "ForgeUpgrade", { token = offer.token, weaponId = item.weaponId, level = 0 })
check(not r.ok and Inv.getDenarii(p) == 100 - item.price and Inv.forgeLevel(p, item.weaponId) == 1, "repeated confirmation is refused without a second charge")
tick()
r = Town.request(p, "ForgeUpgrade", { token = offer.token, weaponId = item.weaponId, level = 1 })
check(not r.ok and Inv.getDenarii(p) == 100 - item.price, "no stage above the maximum")
-- invalid requests: not owned, unknown, wrong types, wrong / missing / expired token, wrong state
local balance = Inv.getDenarii(p)
for _, bad in {
	{ "ForgeUpgrade", { token = offer.token, weaponId = "LegionSword", level = 0 } },
	{ "ForgeUpgrade", { token = offer.token, weaponId = "NoSuchBlade", level = 0 } },
	{ "ForgeUpgrade", { token = offer.token, weaponId = 5, level = 0 } },
	{ "ForgeUpgrade", { token = "nope", weaponId = item.weaponId, level = 0 } },
	{ "ForgeUpgrade", { weaponId = item.weaponId, level = 0 } },
	{ "ForgeUpgrade", "text" },
	{ "Steal", { token = offer.token } },
} do
	tick()
	r = Town.request(p, bad[1], bad[2])
	check(not r.ok and Inv.getDenarii(p) == balance, "invalid request refused: " .. tostring(bad[1]))
end
-- a second weapon: owned, but the player is in the wrong state / data not ready / too far / offer expired
Inv.addDenarii(p, 500)
Inv.unlockAll(p)
balance = Inv.getDenarii(p)
Town.openForge(p)
offer = last().payload
check(#offer.items == #Weapons.Ordered, "every owned weapon is offered")
p.attrs.GameState = "FIGHTING"
tick()
r = Town.request(p, "ForgeUpgrade", { token = offer.token, weaponId = "LegionSword", level = 0 })
check(not r.ok and Inv.forgeLevel(p, "LegionSword") == 0 and Inv.getDenarii(p) == balance, "no forging outside the lobby state")
p.attrs.GameState = "LOBBY"
ready[p] = false
tick()
r = Town.request(p, "ForgeUpgrade", { token = offer.token, weaponId = "LegionSword", level = 0 })
check(not r.ok and Inv.getDenarii(p) == balance, "no forging before the data is loaded")
ready[p] = nil
roots[p] = { Position = vec(30, 0, 0) }
tick()
r = Town.request(p, "ForgeUpgrade", { token = offer.token, weaponId = "LegionSword", level = 0 })
check(not r.ok and Inv.getDenarii(p) == balance, "no forging from a distance")
roots[p] = { Position = vec(5, 0, 0) }
now += Oracle.OfferSeconds + 1
r = Town.request(p, "ForgeUpgrade", { token = offer.token, weaponId = "LegionSword", level = 0 })
check(not r.ok and Inv.getDenarii(p) == balance, "an expired offer is refused")
-- save data: the stage survives a rejoin / teleport, old profiles migrate, bad data is cleaned
local saved = Inv.serialize(p)
check(saved.version == 9 and saved.forge[item.weaponId] == 1, "stage in the saved profile (v9)")
local q = newPlayer(2)
Inv.load(q, saved, 0, 0, nil)
check(Inv.forgeLevel(q, item.weaponId) == 1, "stage after rejoin")
local old = table.clone(saved)
old.version, old.forge = 8, nil
local o = newPlayer(3)
Inv.load(o, old, 0, 0, nil)
check(Inv.forgeLevel(o, item.weaponId) == 0 and Inv.serialize(o).version == 9, "v8 profile migrates without a forged weapon")
local junk = table.clone(saved)
junk.forge = { [item.weaponId] = 7, Fake = 1, LegionSword = "x" }
local j = newPlayer(4)
Inv.load(j, junk, 0, 0, nil)
check(Inv.forgeLevel(j, item.weaponId) == Forge.MaxLevel and Inv.serialize(j).forge.Fake == nil and Inv.forgeLevel(j, "LegionSword") == 0, "bad forge data is clamped and cleaned")
-- PvE only: the whole PvE factor is divided out against players, so the forge never changes PvP
for _, level in { 0, 1 } do
	local pve = Balance.pveFactor(item.weaponId) * Forge.pveFactor(level)
	local combo, pvp = 1.3, Balance.pvpFactor(item.weaponId)
	local damage = basic * combo * pve
	local pvpMultiplier = 0.8 * pvp * combo / (combo * pve)
	check(math.abs(damage * pvpMultiplier - basic * 0.8 * pvp * combo) < 1e-9, "PvP damage independent of the forge stage (stage " .. level .. ")")
end

-- ORACLE
local a = newPlayer(10)
Inv.load(a, nil, 0, 0, nil)
roots[a] = { Position = vec(90, 0, 0) }
Inv.addDenarii(a, 3)
Town.openOracle(a)
local ask = last().payload
check(last().kind == "OracleOffer" and ask.price == Oracle.Price, "oracle offer shows the price")
tick()
r = Town.request(a, "Oracle", { token = ask.token })
check(not r.ok and Inv.getDenarii(a) == 3, "too few Denarii: nothing is charged")
Inv.addDenarii(a, 57)
tick()
r = Town.request(a, "Oracle", { token = ask.token })
local progress = Levels.progressFor(Inv.getAura(a))
check(r.ok and Inv.getDenarii(a) == 60 - Oracle.Price and r.hint:find(tostring(progress.remaining)) and r.hint:find(progress.nextLevel.Title, 1, true), "paid once, the hint names the missing Aura and the next title")
tick()
r = Town.request(a, "Oracle", { token = ask.token })
check(not r.ok and Inv.getDenarii(a) == 60 - Oracle.Price, "the same offer can't be paid twice")
roots[a] = { Position = vec(0, 0, 0) }
Town.openOracle(a)
check(last().kind == "Refused", "the oracle refuses a player far away")
roots[a] = { Position = vec(90, 0, 0) }
Inv.unlockAll(a)
Town.openOracle(a)
ask = last().payload
tick()
r = Town.request(a, "Oracle", { token = ask.token })
check(r.ok and r.isMax and r.hint:find("Kein Titel"), "at the highest rank the oracle says so")
print("PASS: " .. checks .. " checks, smith and oracle against the actual Luau sources (mock Roblox services).")
'@
$target = Join-Path ([System.IO.Path]::GetTempPath()) ("OttiRome-" + [guid]::NewGuid().ToString() + ".luau")
[System.IO.File]::WriteAllText($target, $harness, [System.Text.UTF8Encoding]::new($false))
try {
    & $LuauPath $target
    $testExit = $LASTEXITCODE
} finally {
    Remove-Item -LiteralPath $target -ErrorAction SilentlyContinue
}
exit $testExit
