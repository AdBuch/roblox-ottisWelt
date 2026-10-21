--!strict
-- PvE and PvP weapon values, configured SEPARATELY (applied on the server in SpecialMoveService).
--   PvE  progression should be felt: a weapon deals more against zombies and bosses the higher its
--        gladiator level (LevelRequired). Starter weapons keep their full base damage, so beginners
--        still win their fights.
--   PvP  fair duels: every weapon's basic attack is normalized to the same damage per second
--        (PvPReferenceDPS) using its own damage, PvP multiplier and cooldown. Weapons still differ in
--        reach, speed, arc and style, and long reach / ranged weapons pay a small damage tax. Higher
--        levels therefore give MORE CHOICE in PvP, not overwhelming power.
-- PvPBalanceConfig keeps the per-hit / per-move caps on top of this.

local WeaponDefinitions = require(script.Parent.WeaponDefinitions)
local SpecialMoveDefinitions = require(script.Parent.SpecialMoveDefinitions)

local WeaponBalanceConfig = {
	-- PvE: multiplier = 1 + (LevelRequired - 1) * PvELevelStep, unless PvEOverride sets one
	PvELevelStep = 0.08,
	PvEOverride = table.freeze({}) :: { [string]: number }, -- e.g. { BattleAxe = 1.4 }

	-- PvP: basic-attack DPS every weapon is normalized to
	PvPReferenceDPS = 22,
	PvPReachTaxPerStud = 0.02, -- per stud of basic range above PvPReachFree
	PvPReachFree = 7.5,
	PvPMaxReachTax = 0.15,
	PvPRangedFactor = 0.85, -- bows (they hit from far away)
	PvPFactorMin = 0.6,
	PvPFactorMax = 1.5,
	PvPOverride = table.freeze({}) :: { [string]: number }, -- final factor per weapon id, if needed
}

local pveCache: { [string]: number } = {}
local pvpCache: { [string]: number } = {}

-- PvE damage multiplier of a weapon.
function WeaponBalanceConfig.pveFactor(weaponId: string): number
	local cached = pveCache[weaponId]
	if cached then
		return cached
	end
	local override = WeaponBalanceConfig.PvEOverride[weaponId]
	local weapon = WeaponDefinitions.ById[weaponId]
	local factor = override or (if weapon then 1 + (weapon.LevelRequired - 1) * WeaponBalanceConfig.PvELevelStep else 1)
	pveCache[weaponId] = factor
	return factor
end

-- PvP normalization factor of a weapon (applied on top of each move's PvPMultiplier).
function WeaponBalanceConfig.pvpFactor(weaponId: string): number
	local cached = pvpCache[weaponId]
	if cached then
		return cached
	end
	local override = WeaponBalanceConfig.PvPOverride[weaponId]
	local factor = 1
	local weapon = WeaponDefinitions.ById[weaponId]
	local basic = weapon and (SpecialMoveDefinitions :: any)[weapon.Basic]
	if override then
		factor = override
	elseif weapon and basic and basic.Cooldown > 0 then
		local dps = basic.Damage * basic.PvPMultiplier / basic.Cooldown
		factor = WeaponBalanceConfig.PvPReferenceDPS / math.max(1, dps)
		if weapon.Kind == "Bow" then
			factor *= WeaponBalanceConfig.PvPRangedFactor
		else
			local tax = math.clamp((basic.Range - WeaponBalanceConfig.PvPReachFree) * WeaponBalanceConfig.PvPReachTaxPerStud, 0, WeaponBalanceConfig.PvPMaxReachTax)
			factor *= 1 - tax
		end
		factor = math.clamp(factor, WeaponBalanceConfig.PvPFactorMin, WeaponBalanceConfig.PvPFactorMax)
	end
	pvpCache[weaponId] = factor
	return factor
end

return WeaponBalanceConfig
