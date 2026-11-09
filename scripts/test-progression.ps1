param([string]$LuauPath = 'luau')
# Gladiator career (150 levels), profile migration v8, earnings counters, matchmaking gap and the
# server-side loadout path (LoadoutRequestService -> InventoryService) against the REAL Luau sources.
# Roblox services, players and remotes are small mocks; nothing here needs Studio.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

function Wrap([string]$key, [string]$path) {
    $source = Get-Content -LiteralPath (Join-Path $repo $path) -Raw
    return "`nsources[`"$key`"] = function(script)`n$source`nend`n"
}

$harness = @'
local checks = 0
local function check(ok, message) if not ok then error("FAIL: " .. message, 2) end checks += 1 end
local now = 1000
local realOs = os
local os = setmetatable({ clock = function() return now end }, { __index = realOs })
local Vector2 = { new = function(x, y) return { X = x, Y = y } end }
local Vector3 = { new = function(x, y, z) return { X = x, Y = y, Z = z } end }
local Color3 = { fromRGB = function(...) return { ... } end, new = function(...) return { ... } end }
local Enum = setmetatable({}, { __index = function(_, a) return setmetatable({}, { __index = function(_, b) return a .. "." .. b end }) end })
local function signal() return { Connect = function() return { Disconnect = function() end } end } end

local sources = {}
local loaded = {}
local mocks = {}
local function folder(prefix)
	return setmetatable({}, { __index = function(_, name) return prefix .. "/" .. name end })
end
local function require(key)
	if mocks[key] then return mocks[key] end
	if loaded[key] == nil then
		local fn = assert(sources[key], "unmapped require " .. tostring(key))
		local prefix = key:match("^(.-)/")
		loaded[key] = fn({ Parent = folder(prefix) })
	end
	return loaded[key]
end
local services = {
	ReplicatedStorage = { Shared = folder("Shared") },
	Players = { PlayerRemoving = signal(), PlayerAdded = signal(), GetPlayers = function() return {} end },
}
local game = { GetService = function(_, name) return assert(services[name], "service " .. name) end }

-- mocks for the server pieces around the loadout path
local role = "Hub"
local ready = {}
local refreshed = 0
mocks["Shared/EnvironmentConfig"] = { role = function() return role end }
mocks["Server/PlayerDataService"] = { isReady = function(p) return ready[p] ~= false end }
mocks["Server/PlayerCombatService"] = { refreshEquipment = function() refreshed += 1 end }
mocks["Server/Remotes"] = { LoadoutRequest = {} }

local function newPlayer(id)
	local p = { UserId = id, Name = "P" .. id, attrs = { GameState = "LOBBY", Location = "Lobby" } }
	function p:GetAttribute(k) return self.attrs[k] end
	function p:SetAttribute(k, v) self.attrs[k] = v end
	return p
end
'@
foreach ($name in 'ArmorDefinitions','Config','CurrencyConfig','GladiatorLevelDefinitions','PlayerDataSchema','ShieldDefinitions','WeaponDefinitions','SpecialMoveDefinitions','GameStates','WeaponBalanceConfig','WeaponSpecialDefinitions','WeaponAttackDefinitions','SpecialPracticeDefinitions','ForgeDefinitions') {
    $harness += Wrap "Shared/$name" "src/shared/$name.luau"
}
foreach ($name in 'InventoryService','LoadoutRequestService','RateLimiter') {
    $harness += Wrap "Server/$name" "src/server/$name.luau"
}
$harness += @'

local G = require("Shared/GladiatorLevelDefinitions")
local Inv = require("Server/InventoryService")
local Loadout = require("Server/LoadoutRequestService")
local Weapons = require("Shared/WeaponDefinitions")
local Shields = require("Shared/ShieldDefinitions")
local Armor = require("Shared/ArmorDefinitions")
local Balance = require("Shared/WeaponBalanceConfig")
local Schema = require("Shared/PlayerDataSchema")

------------------------------------------------------------------ 150 levels
check(#G.Levels == 150 and G.MaxLevel == 150, "exactly 150 levels")
check(G.Levels[1].Aura == 0, "level 1 at 0 Aura")
local titles = {}
for i, def in G.Levels do
	check(def.Level == i, "level numbers in order")
	check(type(def.Title) == "string" and #def.Title > 0, "every level has a visible title")
	check(titles[def.Title] == nil, "titles are unique: " .. def.Title)
	titles[def.Title] = true
	if i > 1 then check(def.Aura > G.Levels[i - 1].Aura, "threshold strictly higher at " .. i) end
	if i > 2 then
		check(def.Aura - G.Levels[i - 1].Aura >= G.Levels[i - 1].Aura - G.Levels[i - 2].Aura, "steps never shrink at " .. i)
	end
	check((def.Title == "CÄSAR") == (i == 150), "CÄSAR only at level 150")
end
check(G.Levels[2].Aura <= 150, "level 2 comes quickly")
-- before / on / after every boundary
for i = 2, 150 do
	local t = G.Levels[i].Aura
	check(G.levelFor(t - 1).Level == i - 1, "one Aura before level " .. i)
	check(G.levelFor(t).Level == i, "exactly on level " .. i)
	check(G.levelFor(t + 1).Level == i, "one Aura after level " .. i)
	local p = G.progressFor(t - 1)
	check(p.remaining == 1, "exactly 1 Aura remaining before level " .. i)
	check(p.inLevel + p.remaining == p.needed, "in-level + remaining = needed")
end
-- 149 -> 150 and above the top
local top = G.Levels[150].Aura
local p149 = G.progressFor(top - 1)
check(p149.level.Level == 149 and p149.nextLevel.Level == 150 and p149.nextLevel.Title == "CÄSAR", "149 -> 150 is CÄSAR")
for _, aura in { top, top + 1, top * 10 } do
	local p = G.progressFor(aura)
	check(p.level.Level == 150 and p.isMax and p.nextLevel == nil, "level 150 above the last threshold")
	check(p.remaining == 0 and p.needed == 0 and p.share == 1 and p.nextRank == nil, "no invalid next level at 150")
end
check(G.levelFor(-5).Level == 1 and G.levelFor(0 / 0).Level == 1, "negative / NaN Aura stays level 1")
check(G.progressFor(0).nextRank.Title == "NOVICIUS I", "next rank shown from level 1")
check(#G.Groups == 14 and G.groupOf(150).Name == "CÄSAR", "14 rank groups")

------------------------------------------------------------------ matchmaking window
check(G.matchGap(0, 1) >= 5, "start gap is not 1 level any more")
check(G.matchGap(0, 100) > G.matchGap(0, 10), "gap scales with the level")
check(G.matchGap(60, 50) > G.matchGap(0, 50), "gap widens with waiting")
check(G.matchGap(60, 100) > 6, "no longer capped at the old 7-level span")
check(G.matchGap(G.MatchLevelGap.OpenSeconds, 1) == 149, "anybody may meet after OpenSeconds")

------------------------------------------------------------------ gear requirements
for _, list in { Weapons.Ordered, Shields.Ordered, Armor.Ordered } do
	for _, def in list do
		check(def.LevelRequired >= 1 and def.LevelRequired <= 150 and G.get(def.LevelRequired) ~= nil, "gear level in 1..150")
		check(type(def.Tier) == "number", "gear keeps its balance tier")
	end
end
check(Weapons.ById[Weapons.Starter].LevelRequired == 1 and Shields.ById[Shields.Starter].LevelRequired == 1 and Armor.ById[Armor.Starter].LevelRequired == 1, "starters at level 1")
check(math.abs(Balance.pveFactor("BattleAxe") - (1 + 4 * Balance.PvELevelStep)) < 1e-9, "PvE damage unchanged by the new level numbers (tier 5)")

------------------------------------------------------------------ migration of older profiles
check(Schema.Version == 9, "schema v9")
local v6 = { version = 6, auraPoints = 3200, denarii = 540, ownedWeapons = "RustyGladius,BattleAxe", ownedShields = "WoodenBuckler,ThraexShield", ownedArmor = "RecruitLeather,ChampionArmor", equippedWeapon = "BattleAxe", equippedShield = "ThraexShield", equippedArmor = "ChampionArmor", preferences = { HudMode = "Minimal" }, stats = { zombieKills = 40 } }
Inv.migrateProfile(v6)
check(v6.auraPoints == 3200 and v6.denarii == 540, "v6 keeps Aura and Denarii")
check(v6.ownedWeapons.BattleAxe and v6.ownedArmor.ChampionArmor and v6.equippedArmor == "ChampionArmor", "v6 keeps items and the loadout")
check(v6.earnings.aura == 0 and v6.earnings.denarii == 0 and v6.earnings.complete == false, "no invented history: since tracking began")
local since = v6.earnings.since
Inv.migrateProfile(v6)
Inv.migrateProfile(v6)
check(v6.auraPoints == 3200 and v6.denarii == 540 and v6.earnings.aura == 0 and v6.earnings.since == since, "migration repeatable without double values")
local v7 = { version = 7, specialAttempts = { ["RustyGladius:Gladius_SpecCleave"] = 12 } }
Inv.migrateProfile(v7)
check(v7.version == 9 and v7.specialAttempts["RustyGladius:Gladius_SpecCleave"] == 12 and v7.earnings.complete == false, "v7 keeps special practice and starts earnings tracking")
local v4 = { version = 4, auraPoints = 300, ownedWeapons = "RustyGladius,LegionSword", ownedShields = "", ownedArmor = "" }
Inv.migrateProfile(v4)
check(v4.denarii == 300 and v4.auraPoints == 380 and v4.earnings.complete == false, "v4 -> v8 keeps the Denarii conversion")
local v1 = { version = 1, coins = 50 }
Inv.migrateProfile(v1)
Inv.migrateProfile(v1)
check(v1.coins == nil and v1.auraPoints == 50 + 0 and v1.denarii == 50, "v1 coins counted once")

------------------------------------------------------------------ owned gear stays usable, buying stays level-gated
local a = newPlayer(1)
Inv.load(a, v6, 0, 0, nil)
check(Inv.getLevel(a) < Armor.ById.ChampionArmor.LevelRequired, "the old champion is below the new armor requirement")
local ok, msg = Inv.equip(a, "Armor", "RecruitLeather")
check(ok, "switch to owned starter armor")
ok, msg = Inv.equip(a, "Armor", "ChampionArmor")
check(ok, "legitimately bought armor stays equippable after the re-balance: " .. tostring(msg))
ok = Inv.purchase(a, "Weapon", "HopliteSpear")
check(not ok and Inv.getDenarii(a) == 540, "not unlocked yet: no purchase, no Denarii spent")

------------------------------------------------------------------ earnings counters
local b = newPlayer(2)
Inv.load(b, nil, 0, 0, nil)
check(b.attrs.EarnedComplete == true, "a new profile tracks lifetime totals")
Inv.beginBattle(b, "Solo")
Inv.addReward(b, 300, 300)
Inv.addReward(b, 10, 15)
check(Inv.getAura(b) == 310 and Inv.getDenarii(b) == 315, "balance grows")
ok = Inv.purchase(b, "Weapon", "LegionSword") -- level 3 at 225 Aura
check(ok and Inv.getDenarii(b) == 235, "purchase spends Denarii")
check(b.attrs.EarnedDenarii == 315 and b.attrs.EarnedAura == 310, "earned total ignores spending (own counter, not the balance)")
check(b.attrs.SessionAura == 310 and b.attrs.SessionDenarii == 315, "session counters")
check(b.attrs.LastBattleAura == 310 and b.attrs.LastBattleDenarii == 315 and b.attrs.LastBattleMode == "Solo", "last battle rewards")
check(b.attrs.AuraPerActiveHour == 0, "no estimate from too little data")
for _ = 1, Schema.Estimate.MinRewards do Inv.addReward(b, 10, 10) end
check(b.attrs.AuraPerActiveHour == 0, "no estimate without active play time")
Inv.addActiveSeconds(b, Schema.Estimate.MinActiveSeconds)
check(b.attrs.AuraPerActiveHour > 0, "estimate once enough real data exists")

------------------------------------------------------------------ 149 -> 150 and beyond
local c = newPlayer(3)
Inv.load(c, nil, 0, 0, nil)
Inv.addReward(c, top - 1, 0)
check(Inv.getLevel(c) == 149, "level 149 one Aura before the top")
Inv.addReward(c, 1, 1)
check(Inv.getLevel(c) == 150 and G.levelFor(Inv.getAura(c)).Title == "CÄSAR", "level 150 CÄSAR")
Inv.addReward(c, 500, 500)
check(Inv.getLevel(c) == 150 and Inv.getAura(c) == top + 500 and Inv.getDenarii(c) == 501, "Aura and Denarii still earned at 150")

------------------------------------------------------------------ loadout requests (server-side checks)
local d = newPlayer(4)
Inv.load(d, { version = 7, auraPoints = 50000, denarii = 77, ownedWeapons = "RustyGladius,TwinDaggers,LegionSword", ownedShields = "WoodenBuckler,LegionShield", ownedArmor = "RecruitLeather" }, 0, 0, nil)
local function ask(kind, id) now += 1; return Loadout.handle(d, "Equip", kind, id) end
local r = ask("Weapon", "LegionSword")
check(r.ok and r.code == "EQUIPPED" and d.attrs.EquippedWeapon == "LegionSword" and refreshed == 1, "equip an owned weapon in the lobby")
check(Inv.getDenarii(d) == 77, "equipping costs no Denarii")
r = ask("Weapon", "BattleAxe")
check(not r.ok and r.code == "NOT_OWNED" and d.attrs.EquippedWeapon == "LegionSword", "not owned: refused")
r = ask("Weapon", "Excalibur")
check(not r.ok and r.code == "INVALID", "unknown id refused")
r = ask("Hat", "RustyGladius")
check(not r.ok and r.code == "INVALID", "unknown kind refused")
r = ask(nil, nil)
check(not r.ok and r.code == "INVALID", "malformed request refused")
now += 1
r = Loadout.handle(d, "Sell", "Weapon", "LegionSword")
check(not r.ok, "unknown action refused")
d.attrs.GameState = "MATCH_ACTIVE"; d.attrs.Location = "Arena"
r = ask("Weapon", "RustyGladius")
check(not r.ok and r.code == "IN_BATTLE" and d.attrs.EquippedWeapon == "LegionSword", "locked during a fight")
d.attrs.GameState = "COUNTDOWN"; d.attrs.Location = "Lobby"
r = ask("Weapon", "RustyGladius")
check(not r.ok and r.code == "IN_BATTLE", "locked in the countdown into a fight")
d.attrs.GameState = "LOBBY"; d.attrs.MatchTransition = true
r = ask("Weapon", "RustyGladius")
check(not r.ok and r.code == "TRANSITION", "locked while the match is prepared")
d.attrs.MatchTransition = false; ready[d] = false
r = ask("Weapon", "RustyGladius")
check(not r.ok and r.code == "LOADING", "locked while data loads / teleports")
ready[d] = nil; role = "Arena"
r = ask("Weapon", "RustyGladius")
check(not r.ok and r.code == "NOT_LOBBY", "never in the Arena place")
role = "Hub"
r = ask("Weapon", "TwinDaggers")
check(r.ok and d.attrs.EquippedWeapon == "TwinDaggers", "two-handed weapon equipped")
check(Inv.getActiveShield(d) == nil, "two-handed: no shield in use")
r = ask("Shield", "LegionShield")
check(r.ok and d.attrs.EquippedShield == "LegionShield" and Inv.getActiveShield(d) == nil, "shield choice kept but unused with a two-handed weapon")
r = ask("Weapon", "RustyGladius")
check(r.ok and Inv.getActiveShield(d).Id == "LegionShield", "one-handed again: the kept shield is used")
r = ask("Weapon", "RustyGladius")
check(r.ok and r.code == "ALREADY", "already equipped")
local before = refreshed
r = Loadout.handle(d, "Equip", "Weapon", "LegionSword") -- same clock: rate limited
check(not r.ok and r.code == "RATE" and refreshed == before, "rate limited")

------------------------------------------------------------------ saved and carried into the Arena / rejoin
local saved = Inv.serialize(d)
local e = newPlayer(4)
Inv.forget(d)
Inv.load(e, saved, 0, 0, nil)
check(e.attrs.EquippedWeapon == "RustyGladius" and e.attrs.EquippedShield == "LegionShield", "loadout survives a rejoin / the trip to the Arena")
check(Inv.getAura(e) == 50000 and Inv.getDenarii(e) == 77, "balance survives")
local savedB = Inv.serialize(b)
local f = newPlayer(9)
Inv.load(f, savedB, 0, 0, nil)
check(f.attrs.EarnedDenarii == b.attrs.EarnedDenarii and f.attrs.LastBattleMode == "Solo" and f.attrs.SessionAura == b.attrs.SessionAura, "earnings, session and last battle survive the teleport")

print("PASS: " .. checks .. " checks against the actual Luau sources (mock Roblox services).")
'@
$target = Join-Path ([System.IO.Path]::GetTempPath()) ("OttiProgression-" + [guid]::NewGuid().ToString() + ".luau")
[System.IO.File]::WriteAllText($target, $harness, [System.Text.UTF8Encoding]::new($false))
try {
    & $LuauPath $target
    $testExit = $LASTEXITCODE
} finally {
    Remove-Item -LiteralPath $target -ErrorAction SilentlyContinue
}
exit $testExit
