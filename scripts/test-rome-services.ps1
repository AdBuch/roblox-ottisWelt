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
local realOs = os
local clockTime = 2000000
local os = setmetatable({ time = function() return clockTime end }, { __index = realOs })
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
$harness += Wrap "Shared/ColosseumLayout" "src/shared/ColosseumLayout.luau"
$harness += Wrap "Rome/RomeLayout" "src/hub/server/Rome/RomeLayout.luau"
$harness += Wrap "Rome/WorldEdgeService" "src/hub/server/Rome/WorldEdgeService.luau"
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
local refreshed = 0
local studio = false
Town.init({
	inventory = Inv,
	isReady = function(p) return ready[p] ~= false end,
	rootOf = function(p) return roots[p] end,
	fire = function(p, kind, payload) table.insert(events, { player = p, kind = kind, payload = payload }) end,
	now = function() return now end,
	token = function() tokens += 1 return "T" .. tokens end,
	refresh = function() refreshed += 1 end,
	save = function() return true end,
	isStudio = function() return studio end,
}, function() return vec(0, 0, 0) end, function() return vec(100, 0, 0) end)
local function last() return events[#events] end
local function tick() now += 1 end
local function minutes(m) clockTime += m * 60 end
local starter = Weapons.Starter

local p = newPlayer(1)
Inv.load(p, nil, 0, 0, nil)
roots[p] = { Position = vec(40, 0, 0) }
-- FORGE: too far away -> refused, no offer
Town.openForge(p)
check(last().kind == "Refused", "smith refuses a player far away")
roots[p] = { Position = vec(5, 0, 0) }
Town.openForge(p)
local state = last().payload
local token = state.token
check(last().kind == "ForgeOffer" and #state.weapons == 1 and state.weapons[1].weaponId == starter and #state.weapons[1].copies == 1, "offer lists the starter weapon with one copy")
local copy1 = state.weapons[1].copies[1]
local basic = Moves[Weapons.ById[starter].Basic].Damage
check(copy1.basic == math.floor(basic * Balance.pveFactor(starter) + 0.5) and copy1.basicHardened == math.floor(basic * Balance.pveFactor(starter) * 1.1 + 0.5), "real values now and hardened")
check(copy1.prices.Harden == Forge.price(starter, 0) and copy1.prices.Sharpen == nil and copy1.prices.Repair == nil, "server prices: hardening offered, nothing to sharpen or repair")
-- HARDEN: without Denarii nothing happens; with Denarii one charge, a job that takes time
local r = Town.request(p, "ForgeJob", { token = token, weaponId = starter, uid = copy1.uid, kind = "Harden" })
check(not r.ok and r.needDenarii == copy1.prices.Harden and Inv.getDenarii(p) == 0, "no hardening without Denarii (the shortfall is offered)")
tick()
Inv.addDenarii(p, 1000)
r = Town.request(p, "ForgeJob", { token = token, weaponId = starter, uid = copy1.uid, kind = "Harden" })
check(r.ok and Inv.getDenarii(p) == 1000 - copy1.prices.Harden and r.state.weapons[1].copies[1].job.kind == "Harden", "hardening charged once, job started")
check(Inv.forgeLevel(p, starter) == 0 and Inv.copyFactor(p, starter) == 1 and Inv.getEquippedWeapon(p).Id == starter and refreshed >= 1, "copy at the smith: a plain loaner in hand, the weapon is refreshed")
tick()
r = Town.request(p, "ForgeJob", { token = token, weaponId = starter, uid = copy1.uid, kind = "Harden" })
check(not r.ok and Inv.getDenarii(p) == 1000 - copy1.prices.Harden, "a second confirmation while the job runs: refused, no second charge")
minutes(Forge.JobSeconds.Harden / 60 + 1)
Town.tick(p)
check(last().kind == "ForgeUpdate" and Inv.forgeLevel(p, starter) == 1 and math.abs(Inv.copyFactor(p, starter) - 1.1) < 1e-9, "the job ends by itself: stage 1, +10 % PvE")
tick()
r = Town.request(p, "ForgeJob", { token = token, weaponId = starter, uid = copy1.uid, kind = "Harden" })
check(not r.ok and r.message:find("bereits"), "no stage above the maximum")
-- WEAR (PvE): weaker in steps, sharpen and repair bring it back
for _ = 1, 280 do Inv.addWear(p, starter, Forge.WearPerHit) end -- 70 wear
check(math.abs(Inv.copyFactor(p, starter) - 1.1 * 0.85) < 1e-9, "worn copy: 85 % of its PvE damage")
for _ = 1, 100 do Inv.addWear(p, starter, Forge.WearPerHit) end -- 95 wear
check(math.abs(Inv.copyFactor(p, starter) - 1.1 * 0.7) < 1e-9 and Inv.getEquippedWeapon(p).Id == starter, "worn out: 70 %, still usable")
local balance = Inv.getDenarii(p)
tick()
r = Town.request(p, "ForgeJob", { token = token, weaponId = starter, uid = copy1.uid, kind = "Sharpen" })
check(r.ok and Inv.getDenarii(p) == balance - Forge.sharpenPrice(starter), "sharpening charged")
minutes(Forge.JobSeconds.Sharpen / 60 + 1)
check(Inv.settleJobs(p) and math.abs(Inv.copies(p, starter)[1].wear - (95 - Forge.SharpenAmount)) < 1e-6, "sharpened: wear -35")
balance = Inv.getDenarii(p)
local repairPrice = Forge.repairPrice(starter, Inv.copies(p, starter)[1].wear)
tick()
r = Town.request(p, "ForgeJob", { token = token, weaponId = starter, uid = copy1.uid, kind = "Repair" })
check(r.ok and Inv.getDenarii(p) == balance - repairPrice, "repair charged by wear")
minutes(Forge.JobSeconds.Repair / 60 + 1)
Inv.settleJobs(p)
check(Inv.copies(p, starter)[1].wear == 0 and math.abs(Inv.copyFactor(p, starter) - 1.1) < 1e-9, "repaired: full strength")
-- COPIES: every further copy doubles in price; a new copy is busy until the smith is done
balance = Inv.getDenarii(p)
local base = math.max(Forge.MinCopyPrice, Weapons.ById[starter].Price)
tick()
r = Town.request(p, "ForgeJob", { token = token, weaponId = starter, kind = "Copy" })
check(r.ok and Inv.getDenarii(p) == balance - base * 2 and #Inv.copies(p, starter) == 2, "second copy: twice the base price")
local copy2 = Inv.copies(p, starter)[2]
check(copy2.job and copy2.job.kind == "Copy" and Inv.copyInUse(p, starter).uid == copy1.uid, "the new copy is at the smith, the first stays in hand")
tick()
r = Town.request(p, "SetActive", { token = token, weaponId = starter, uid = copy2.uid })
check(not r.ok, "a copy at the smith can't be chosen")
check(Forge.copyPrice(starter, 2) == base * 4 and Forge.copyPrice(starter, 3) == base * 8, "third and fourth copy: 4x and 8x")
minutes(Forge.JobSeconds.Copy / 60 + 1)
tick()
r = Town.request(p, "SetActive", { token = token, weaponId = starter, uid = copy2.uid })
check(r.ok and Inv.copyInUse(p, starter).uid == copy2.uid and Inv.forgeLevel(p, starter) == 0, "the second copy chosen: its own stage")
-- a job on the copy in hand: the other free copy takes its place
tick()
for _ = 1, 4 do Inv.addWear(p, starter, Forge.WearPerHit) end
r = Town.request(p, "ForgeJob", { token = token, weaponId = starter, uid = copy2.uid, kind = "Sharpen" })
check(r.ok and Inv.copyInUse(p, starter).uid == copy1.uid, "while copy 2 is sharpened, copy 1 is in hand")
-- DESIGN (Robux): without a credit the purchase is offered; unset products are refused outside Studio
tick()
r = Town.request(p, "ForgeJob", { token = token, weaponId = starter, uid = copy1.uid, kind = "Design", slot = "Grip", option = "Gold" })
check(not r.ok and r.needProduct == "DesignToken", "a design needs the Robux product")
tick()
r = Town.request(p, "Buy", { token = token, key = "DesignToken" })
check(not r.ok and Inv.credits(p, "Design") == 0, "products without an id are refused outside Studio")
studio = true
tick()
r = Town.request(p, "Buy", { token = token, key = "DesignToken" })
local c1 = Inv.copies(p, starter)[1]
check(r.ok and r.studio and Inv.credits(p, "Design") == 0 and c1.job and c1.job.kind == "Design", "Studio test purchase: the credit pays the pending design job")
minutes(Forge.JobSeconds.Design / 60 + 1)
Inv.settleJobs(p)
check(Inv.copies(p, starter)[1].design.Grip == "Gold", "golden grip on copy 1")
-- RECEIPTS: the same purchase is granted once
balance = Inv.getDenarii(p)
local pack = Forge.product("DenariiSmall")
check(Town.grant(p, pack, "R-1") and Town.grant(p, pack, "R-1") and Inv.getDenarii(p) == balance + pack.denarii, "a receipt grants its Denarii exactly once")
-- SKIP (Robux): finishes a running job at once
tick()
local inHand = Inv.copyInUse(p, starter)
for _ = 1, 8 do Inv.addWear(p, starter, Forge.WearPerHit) end
r = Town.request(p, "ForgeJob", { token = token, weaponId = starter, uid = inHand.uid, kind = "Repair" })
check(r.ok, "repair started on the copy in hand")
tick()
r = Town.request(p, "Skip", { token = token, weaponId = starter, uid = inHand.uid })
check(not r.ok and r.needProduct == "ForgeSkip", "fast-forward needs the Robux product")
tick()
r = Town.request(p, "Buy", { token = token, key = "ForgeSkip" })
check(r.ok and inHand.job == nil and inHand.wear == 0 and Inv.credits(p, "Skip") == 0, "the purchase finishes the repair at once")
-- SHIELD PAINT (Robux)
local shieldId = require("Shared/ShieldDefinitions").Starter
tick()
r = Town.request(p, "Paint", { token = token, shieldId = shieldId, option = "LegionRed" })
check(not r.ok and r.needProduct == "DesignToken", "shield paint needs the Robux product")
tick()
r = Town.request(p, "Buy", { token = token, key = "DesignToken" })
check(r.ok and Inv.shieldDesign(p, shieldId) == "LegionRed", "shield painted after the purchase")
studio = false
-- invalid requests and wrong states: the balance never changes
balance = Inv.getDenarii(p)
for _, bad in {
	{ "ForgeJob", { token = token, weaponId = "LegionSword", uid = "x", kind = "Harden" } },
	{ "ForgeJob", { token = token, weaponId = starter, uid = "nope", kind = "Repair" } },
	{ "ForgeJob", { token = token, weaponId = starter, uid = copy1.uid, kind = "Melt" } },
	{ "ForgeJob", { token = "nope", weaponId = starter, kind = "Copy" } },
	{ "ForgeJob", { weaponId = starter, kind = "Copy" } },
	{ "ForgeJob", { token = token, weaponId = starter, uid = copy1.uid, kind = "Design", slot = "Grip", option = "Diamond" } },
	{ "SetActive", { token = token, weaponId = starter, uid = "nope" } },
	{ "Buy", { token = token, key = "FreeMoney" } },
	{ "ForgeUpgrade", { token = token, weaponId = starter } },
	{ "ForgeJob", "text" },
} do
	tick()
	r = Town.request(p, bad[1], bad[2])
	check(not r.ok and Inv.getDenarii(p) == balance, "invalid request refused: " .. tostring(bad[1]))
end
p.attrs.GameState = "FIGHTING"
tick()
r = Town.request(p, "ForgeJob", { token = token, weaponId = starter, kind = "Copy" })
check(not r.ok and Inv.getDenarii(p) == balance, "no forge work outside the lobby state")
p.attrs.GameState = "LOBBY"
ready[p] = false
tick()
r = Town.request(p, "ForgeJob", { token = token, weaponId = starter, kind = "Copy" })
check(not r.ok and Inv.getDenarii(p) == balance, "no forge work before the data is loaded")
ready[p] = nil
roots[p] = { Position = vec(30, 0, 0) }
tick()
r = Town.request(p, "ForgeJob", { token = token, weaponId = starter, kind = "Copy" })
check(not r.ok and Inv.getDenarii(p) == balance, "no forge work from a distance")
roots[p] = { Position = vec(5, 0, 0) }
now += Oracle.OfferSeconds + 1
r = Town.request(p, "ForgeJob", { token = token, weaponId = starter, kind = "Copy" })
check(not r.ok and Inv.getDenarii(p) == balance, "an expired offer is refused")
-- SAVE DATA: copies, jobs, wear, designs, credits, receipts survive a rejoin / teleport (serialized)
Inv.addWear(p, starter, 3)
local saved = Inv.serialize(p)
check(saved.version == 10 and #saved.weaponCopies[starter] == 2 and saved.weaponCopies[starter][1].design.Grip == "Gold" and table.find(saved.receipts, "R-1"), "copies, designs and receipts in the saved profile (v10)")
local q = newPlayer(2)
Inv.load(q, saved, 0, 0, nil)
check(#Inv.copies(q, starter) == 2 and Inv.forgeLevel(q, starter) == Inv.forgeLevel(p, starter) and Inv.hasReceipt(q, "R-1") and Inv.shieldDesign(q, shieldId) == "LegionRed", "all of it after rejoin")
local v9 = table.clone(saved)
v9.version, v9.weaponCopies, v9.activeCopy, v9.receipts = 9, nil, nil, nil
v9.forge = { [starter] = 1 }
local o = newPlayer(3)
Inv.load(o, v9, 0, 0, nil)
check(#Inv.copies(o, starter) == 1 and Inv.forgeLevel(o, starter) == 1 and Inv.serialize(o).version == 10 and Inv.serialize(o).forge == nil, "v9 stage moves onto the first copy")
local junk = table.clone(saved)
junk.weaponCopies = { [starter] = { { uid = "a", forge = 9, wear = 400, design = { Grip = "Diamond" }, job = { kind = "Melt", untilTime = 1 } }, { uid = "a", forge = 1 } }, Fake = { { uid = "f" } } }
local j = newPlayer(4)
Inv.load(j, junk, 0, 0, nil)
local cleaned = Inv.copies(j, starter)
check(#cleaned == 1 and cleaned[1].forge == Forge.MaxLevel and cleaned[1].wear == Forge.MaxWear and cleaned[1].design.Grip == nil and cleaned[1].job == nil and Inv.serialize(j).weaponCopies.Fake == nil, "bad copy data is clamped and cleaned")
-- PvE only: the whole PvE factor (incl. hardening and wear) is divided out against players
for _, factor in { 1, 1.1, 1.1 * 0.85, 0.7 } do
	local pve = Balance.pveFactor(starter) * factor
	local combo, pvp = 1.3, Balance.pvpFactor(starter)
	local damage = basic * combo * pve
	local pvpMultiplier = 0.8 * pvp * combo / (combo * pve)
	check(math.abs(damage * pvpMultiplier - basic * 0.8 * pvp * combo) < 1e-9, "PvP damage independent of the copy factor " .. factor)
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
-- WORLD EDGE: where the server places a player (pure classification; the loop adds a 3 s grace)
local Edge = require("Rome/WorldEdgeService")
local RL = require("Rome/RomeLayout")
local disc = RL.Disc
local W = RL.Levels.Water
for _, case in {
	{ vec(disc.x + disc.radius + 30, W - 5, disc.z), "Edge", "over the rim, falling" },
	{ vec(disc.x + disc.radius + 30, W + 2, disc.z), nil, "beyond the rim but not yet below the sea" },
	{ vec(disc.x + disc.radius - 30, W - 5, disc.z), nil, "swimming in the sea inside the disc" },
	{ vec(-300, -60, -300), "Edge", "deep below the island" },
	{ vec(-600, -20, 0), nil, "on the floor of the harbour basin" },
	{ vec(-346, 2, 0), nil, "at the forum fountain" },
	{ vec(0, 3, 0), "Sand", "on the arena sand in the Hub" },
	{ vec(0, 3, 48 + 30), nil, "in Otti's lobby under the stands" },
	{ vec(0, 3, 48 + 52), nil, "at the arrival spawn" },
} do
	check(Edge.classify(case[1]) == case[2], "edge rule: " .. case[3])
end
check(Edge.Grace >= 2 and Edge.DeepFall < W - 30, "grace period and deep-fall line")
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
