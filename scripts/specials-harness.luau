local count = 0
local function check(ok, label) assert(ok, label); count += 1 end
local Practice = modules.SpecialPracticeDefinitions
local Levels = modules.GladiatorLevelDefinitions
check(Practice.family("Right", false, true, true, 1) == "Right", "locked context falls back")
check(Practice.family("Left", false, true, false, 2) == "Up", "air unlock at stage 2")
check(Practice.family("Down", false, false, false, 2) == "Left", "Down locked until stage 3")
check(Practice.family("Down", false, false, false, 3) == "Down", "Down unlock at stage 3")
check(Practice.family("Down", false, false, true, 3) == "Down", "block locked until stage 4")
check(Practice.family("Down", false, false, true, 4) == "Circle", "block unlock at stage 4")
check(Practice.family("Right", true, false, false, 5) == "Right", "ultimate locked until stage 6")
check(Practice.family("Right", true, false, false, 6) == "Ultimate", "ultimate unlock at stage 6")
check(Practice.family("Right", false, true, true, 4) == "Up", "air precedence over block")
check(Practice.unlocked(4, "Counter") == false and Practice.unlocked(5, "Counter") == true, "parry counter unlocks at stage 5")
check(Practice.unlocked(1, "Left") and Practice.unlocked(1, "Right"), "Left and Right always open")
check(Practice.weaponStage({ 0, 56 }) == 2 and Practice.weaponStage({}) == 1, "weapon stage is its best move")
check(Levels.levelFor(6999).Level == 8 and Levels.levelFor(7000).Level == 9, "elite reachable")
local function near(a: number, b: number): boolean return math.abs(a - b) < 1e-9 end
check(Practice.MaxSteps == 296, "74 points of Perfect at 0.25 per step")
check(near(Practice.failure(0), 0.25) and near(Practice.failure(134), 0.05) and near(Practice.failure(5000), 0.05), "fail: 25 % start, 5 % floor")
check(near(Practice.perfect(0), 0.01) and near(Practice.perfect(296), 0.75) and near(Practice.perfect(5000), 0.75), "perfect: 1 % start, 75 % ceiling")
check(Practice.stage(0) == 1 and Practice.stage(55) == 1 and Practice.stage(56) == 2, "stage 2 from 15 % Perfect")
check(Practice.stage(296) == 6 and #Practice.Stages == 6, "six stages, Meister at 75 %")
check(Practice.outcome(0.25, 0.01, 0.1) == "Fail" and Practice.outcome(0.25, 0.01, 0.255) == "Perfect" and Practice.outcome(0.25, 0.01, 0.9) == "Normal", "outcome bands")
local attrs = {}
-- Like Roblox: attribute names allow only letters, digits and _ (at most 100 characters)
local player = { UserId = 42, SetAttribute = function(_, k, v)
	assert(#k <= 100 and k:match("^[%w_]+$"), "invalid attribute name " .. k)
	attrs[k] = v
end, GetAttribute = function(_, k) return attrs[k] end }
local dirty = 0
Inventory.onChanged(function() dirty += 1 end)
Inventory.load(player, nil, 0, 0)
local key = Practice.key("RustyGladius", "RebellionCombo")
local f, p = Inventory.practiceSpecial(player, "RustyGladius", "RebellionCombo", "Training")
check(near(f, 0.25) and near(p, 0.01), "first execution uses the start odds")
f, p = Inventory.practiceSpecial(player, "RustyGladius", "RebellionCombo", "Training")
check(near(f, 0.2485) and near(p, 0.0125), "next execution already improved by one step")
check(dirty == 2, "practice marks profile dirty")
check(attrs[Practice.attribute(key)] == 2, "steps published under a valid attribute name")
check(Practice.label(player :: any, "RustyGladius", "RebellionCombo") == "Ungeübt 1/6 · Fehl 24.7% · Perfekt 1.50%", "label shows stage, fail and perfect")
local saved = Inventory.serialize(player)
Inventory.forget(player)
Inventory.load(player, saved, 0, 0)
f, p = Inventory.practiceSpecial(player, "RustyGladius", "RebellionCombo", "Training")
check(near(f, 0.2470) and near(p, 0.015), "progress survives save/load")
f, p = Inventory.practiceSpecial(player, "LegionSword", "Legion_SpecCleave", "Training")
check(near(f, 0.25) and near(p, 0.01), "weapons train independently")
check(Inventory.weaponStage(player, "RustyGladius") == 1, "two steps keep the weapon in stage 1")
-- Daily allowance: 5 points in the training yard = 20 steps a day, arena 15 points = 60 steps
Inventory.forget(player)
Inventory.load(player, nil, 0, 0)
for _ = 1, 25 do Inventory.practiceSpecial(player, "RustyGladius", "RebellionCombo", "Training") end
check(attrs[Practice.attribute(key)] == 20, "training stops at 5 points a day")
for _ = 1, 25 do Inventory.practiceSpecial(player, "RustyGladius", "RebellionCombo", "Arena") end
check(attrs[Practice.attribute(key)] == 45, "arena has its own 15 point allowance")
local day = Inventory.serialize(player)
day.specialDaily[key].day -= 1
Inventory.forget(player)
Inventory.load(player, day, 0, 0)
Inventory.practiceSpecial(player, "RustyGladius", "RebellionCombo", "Training")
check(attrs[Practice.attribute(key)] == 46, "the allowance resets on a new day")
local malformed = table.clone(saved)
malformed.specialAttempts = { [key] = 9999, bogus = 12 }
Inventory.load(player, malformed, 0, 0)
local clean = Inventory.serialize(player).specialAttempts
check(clean.bogus == nil and clean[key] == 296, "migration caps and validates ids")
malformed.specialAttempts = nil
malformed.version = 6
Inventory.load(player, malformed, 0, 0)
f, p = Inventory.practiceSpecial(player, "RustyGladius", "RebellionCombo", "Training")
check(near(f, 0.25) and near(p, 0.01), "v6 migration grants no mastery")
-- Studio test switch: everything owned, ELITE level (Up and Circle unlocked)
Inventory.forget(player)
Inventory.load(player, nil, 0, 0)
Inventory.unlockAll(player)
local unlocked = Inventory.serialize(player)
for id in modules.WeaponDefinitions.ById do
	check(table.find(string.split(unlocked.ownedWeapons, ","), id) ~= nil, "unlockAll owns " .. id)
end
check(Inventory.getLevel(player) == 9, "unlockAll reaches ELITE")
-- Choreography: every assignment has its own key track, synchronised with the server's hits
local function finalSpin(keys)
	local spin = 0
	for _, key in keys do
		spin = key.s or spin
	end
	return spin
end
local function natural(p, label)
	for _, elbow in { p.re, p.le } do
		check(elbow == nil or (elbow >= 0 and elbow <= 120), label .. " elbow within 0-120")
	end
	for _, wrist in { p.rw, p.lw } do
		check(wrist == nil or (math.abs(wrist.X) <= 95 and math.abs(wrist.Y) <= 95 and math.abs(wrist.Z) <= 95), label .. " wrist within 95")
	end
	for _, shoulder in { p.rs, p.ls } do
		check(shoulder == nil or (shoulder.X >= -60 and shoulder.X <= 180), label .. " shoulder pitch natural")
	end
	check(p.c == nil or (p.c >= 0 and p.c <= 1.1), label .. " crouch within reach")
end
local families = 0
local distinct = {}
for prefix, list in modules.WeaponSpecialDefinitions.ByPrefix do
	for family, id in list do
		families += 1
		local label = prefix .. "/" .. family .. " " .. id
		local track = modules.SpecialAnimationDefinitions[prefix .. ":" .. id]
		check(track ~= nil and #track.Keys >= 2 and track.Length > 0, label .. " has a key track")
		local previous = -1
		for _, key in track.Keys do
			check(key.t >= previous, label .. " ordered keys")
			previous = key.t
			natural(key.p, label)
		end
		if #track.Hits > 1 then
			for index, at in track.Hits do
				local near = false
				for _, key in track.Keys do
					if math.abs(key.t - at) <= 0.15 then near = true end
				end
				check(near, label .. " key at hit " .. index)
			end
		end
		check(finalSpin(track.Keys) % 360 == 0, label .. " spin ends on a whole turn")
		if track.Aerial then
			check(track.Land ~= nil and #track.Land >= 2, label .. " has a landing")
			for _, key in track.Land do natural(key.p, label .. " land") end
			check(finalSpin(track.Land) % 360 == 0, label .. " landing spin whole")
		end
		if family == "Circle" then
			check(finalSpin(track.Keys) >= (if prefix == "Bow" then 360 else 720), label .. " Circle turns all the way round")
		end
		distinct[track.Keys] = true
	end
end
check(families == 48, "all 48 weapon/family assignments covered")
local tracksSeen = 0
for _ in distinct do tracksSeen += 1 end
check(tracksSeen == 48, "every weapon/family has its own key track")
local sword, spear = modules.SpecialAnimationDefinitions["Gladius:Gladius_SpecCleave"], modules.SpecialAnimationDefinitions["Trident:Trident_SpecCleave"]
check(sword.Keys[1].p.rs.Z ~= spear.Keys[1].p.rs.Z, "shared moves differ by weapon style")
local rebellion = modules.SpecialAnimationDefinitions["Gladius:RebellionCombo"]
check(finalSpin(rebellion.Keys) == 360, "REBELLION COMBO makes a full shoulder turn")
print("PASS: " .. count .. " special progression, persistence and timeline checks")
