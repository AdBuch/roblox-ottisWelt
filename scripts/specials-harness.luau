local count = 0
local function check(ok, label) assert(ok, label); count += 1 end
local Practice = modules.SpecialPracticeDefinitions
local Levels = modules.GladiatorLevelDefinitions
check(Practice.family("Right", false, true, true, 4) == "Right", "locked context falls back")
check(Practice.family("Left", false, true, false, 5) == "Up", "air unlock at 5")
check(Practice.family("Down", false, false, true, 8) == "Down", "block locked until 9")
check(Practice.family("Down", false, false, true, 9) == "Circle", "block unlock at 9")
check(Practice.family("Right", true, true, true, 9) == "Ultimate", "ultimate precedence")
check(Practice.family("Right", false, true, true, 9) == "Up", "air precedence")
check(Levels.levelFor(6999).Level == 8 and Levels.levelFor(7000).Level == 9, "elite reachable")
check(Practice.failure(0) == 0.5 and Practice.failure(50) == 0 and Practice.failure(500) == 0, "practice bounds")
local attrs = {}
-- Like Roblox: attribute names allow only letters, digits and _ (at most 100 characters)
local player = { UserId = 42, SetAttribute = function(_, k, v)
	assert(#k <= 100 and k:match("^[%w_]+$"), "invalid attribute name " .. k)
	attrs[k] = v
end, GetAttribute = function(_, k) return attrs[k] end }
local dirty = 0
Inventory.onChanged(function() dirty += 1 end)
Inventory.load(player, nil, 0, 0)
check(Inventory.practiceSpecial(player, "RustyGladius", "RebellionCombo") == 0.5, "first roll uses 50 percent")
check(Inventory.practiceSpecial(player, "RustyGladius", "RebellionCombo") == 0.49, "next roll improves")
check(dirty == 2, "practice marks profile dirty")
check(attrs[Practice.attribute(Practice.key("RustyGladius", "RebellionCombo"))] == 2, "attempts published under a valid attribute name")
check(Practice.label(player :: any, "RustyGladius", "RebellionCombo") == "fail 48%", "label reads the published attempts")
local saved = Inventory.serialize(player)
Inventory.forget(player)
Inventory.load(player, saved, 0, 0)
check(Inventory.practiceSpecial(player, "RustyGladius", "RebellionCombo") == 0.48, "practice survives save/load")
check(Inventory.practiceSpecial(player, "LegionSword", "Legion_SpecCleave") == 0.5, "weapons train independently")
local malformed = table.clone(saved)
malformed.specialAttempts = { [Practice.key("RustyGladius", "RebellionCombo")] = 9999, bogus = 12 }
Inventory.load(player, malformed, 0, 0)
local clean = Inventory.serialize(player).specialAttempts
check(clean.bogus == nil and clean[Practice.key("RustyGladius", "RebellionCombo")] == 50, "migration caps and validates ids")
malformed.specialAttempts = nil
malformed.version = 6
Inventory.load(player, malformed, 0, 0)
check(Inventory.practiceSpecial(player, "RustyGladius", "RebellionCombo") == 0.5, "v6 migration grants no mastery")
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
