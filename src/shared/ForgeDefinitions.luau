--!strict
-- THE FORGE OF ROME (Hub · Schmiede an der Handwerksgasse): one first improvement stage for an
-- OWNED weapon. The stage is saved in the profile (PlayerDataSchema v9, `forge`) and read by the
-- server in every fight (SpecialMoveService through PlayerCombatService), in the Hub and in the
-- Arena place alike.
--
-- Effect: the weapon's PvE damage factor grows by PvEBonus (zombies, bosses, training dummies).
-- PvP stays normalized: SpecialMoveService divides the whole PvE factor out again before the
-- PvP normalization (WeaponBalanceConfig.pvpFactor), so a forged weapon deals exactly the same
-- damage to players as before. Helmets have no equipment slot yet: the forge only shows them.
--
-- Price: PriceShare of the weapon's shop price, rounded to 5, at least MinPrice (the free starter
-- sword can be forged as well). All values the dialog shows come from this module, the weapon's
-- basic move (SpecialMoveDefinitions) and WeaponBalanceConfig: the same numbers the server uses.

local SpecialMoveDefinitions = require(script.Parent.SpecialMoveDefinitions)
local WeaponBalanceConfig = require(script.Parent.WeaponBalanceConfig)
local WeaponDefinitions = require(script.Parent.WeaponDefinitions)

export type Offer = {
	weaponId: string,
	name: string,
	level: number, -- current forge stage (0 = not improved)
	maxLevel: number,
	price: number, -- Denarii for the next stage (0 at the top)
	basicNow: number, -- basic hit against zombies today (rounded)
	basicNext: number, -- basic hit against zombies after the next stage (rounded)
	factorNow: number, -- whole PvE damage factor today
	factorNext: number,
}

local ForgeDefinitions = {
	MaxLevel = 1,
	PvEBonus = 0.1, -- +10 % PvE damage per stage
	PriceShare = 0.5,
	MinPrice = 40,
	-- Who may use the forge: the smith must be this close (server check, studs)
	UseDistance = 16,
	-- The attribute mirrored for displays: "WeaponId:stage,WeaponId:stage"
	Attribute = "ForgeLevels",
}

-- Clamp a saved stage.
function ForgeDefinitions.clampLevel(value: unknown): number
	local n = tonumber(value) or 0
	if n ~= n then
		return 0
	end
	return math.clamp(math.floor(n), 0, ForgeDefinitions.MaxLevel)
end

-- Weapons the forge can improve (every weapon definition).
function ForgeDefinitions.isSupported(weaponId: unknown): boolean
	return typeof(weaponId) == "string" and WeaponDefinitions.ById[weaponId] ~= nil
end

-- Price of the stage after `level` (0 when the weapon is at the top).
function ForgeDefinitions.price(weaponId: string, level: number): number
	local weapon = WeaponDefinitions.ById[weaponId]
	if not weapon or level >= ForgeDefinitions.MaxLevel then
		return 0
	end
	local raw = weapon.Price * ForgeDefinitions.PriceShare * (level + 1)
	return math.max(ForgeDefinitions.MinPrice, math.floor(raw / 5 + 0.5) * 5)
end

-- Extra PvE factor of a forge stage (1 = none).
function ForgeDefinitions.pveFactor(level: number): number
	return 1 + ForgeDefinitions.clampLevel(level) * ForgeDefinitions.PvEBonus
end

-- The weapon's basic hit against zombies with a given forge stage (whole factor, rounded).
local function basicAgainstZombies(weaponId: string, level: number): (number, number)
	local weapon = WeaponDefinitions.ById[weaponId]
	local basic = weapon and (SpecialMoveDefinitions :: any)[weapon.Basic]
	local damage = if basic then basic.Damage else (if weapon then weapon.Damage else 0)
	local factor = WeaponBalanceConfig.pveFactor(weaponId) * ForgeDefinitions.pveFactor(level)
	return math.floor(damage * factor + 0.5), factor
end

-- Everything the forge dialog shows for one weapon at the given stage.
function ForgeDefinitions.offer(weaponId: string, level: number): Offer?
	local weapon = WeaponDefinitions.ById[weaponId]
	if not weapon then
		return nil
	end
	local current = ForgeDefinitions.clampLevel(level)
	local nextLevel = math.min(current + 1, ForgeDefinitions.MaxLevel)
	local now, factorNow = basicAgainstZombies(weaponId, current)
	local after, factorNext = basicAgainstZombies(weaponId, nextLevel)
	return {
		weaponId = weaponId,
		name = weapon.DisplayName,
		level = current,
		maxLevel = ForgeDefinitions.MaxLevel,
		price = ForgeDefinitions.price(weaponId, current),
		basicNow = now,
		basicNext = after,
		factorNow = factorNow,
		factorNext = factorNext,
	}
end

-- "Id:1,Id:1" for the display attribute (sorted, only improved weapons).
function ForgeDefinitions.encode(levels: { [string]: number }): string
	local parts = {}
	for id, level in levels do
		if level > 0 then
			table.insert(parts, ("%s:%d"):format(id, level))
		end
	end
	table.sort(parts)
	return table.concat(parts, ",")
end

function ForgeDefinitions.decode(value: unknown): { [string]: number }
	local levels: { [string]: number } = {}
	if typeof(value) == "string" then
		for id, level in value:gmatch("([%w_]+):(%d+)") do
			if ForgeDefinitions.isSupported(id) then
				levels[id] = ForgeDefinitions.clampLevel(tonumber(level))
			end
		end
	end
	return levels
end

return table.freeze(ForgeDefinitions)
