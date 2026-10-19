--!strict
-- Special moves by gesture family (Special button -> one gesture -> release). Direction picks the
-- family, gesture LENGTH (relative to the pad radius, GestureDefinitions) picks the tier:
--   Tier I   100 % base special damage · 25 Momentum
--   Tier II  155 %                     · 50 Momentum
--   Tier III 205 %                     · 75 Momentum
--   Circle   the circular special at a fixed tier (II)
--   Ultimate Circle followed by Down · 100 Momentum · a unique move (not just more damage)
-- Tiers also lengthen the commitment (extra recovery) and raise the visual intensity
-- (AttackTier). PvP uses its own, flatter tier multipliers plus every move's PvP cap.
-- Families reuse the weapons' named combination moves where they fit and generated moves
-- (SpecialMoveDefinitions: <Prefix>_SpecCleave / _SpecCombination / _SpecHeavy / ...) elsewhere.

export type Family = "Left" | "Right" | "Up" | "Down" | "Circle" | "Ultimate"
export type Tier = number -- 1-3, 4 = Ultimate

export type WeaponSpecials = { [Family]: string }

local function specials(s: WeaponSpecials): WeaponSpecials
	return table.freeze(s) :: any
end

local byPrefix: { [string]: WeaponSpecials } = {
	Gladius = specials({ Left = "Gladius_SpecCleave", Right = "RebellionCombo", Up = "U_Rising", Down = "Gladius_SpecHeavy", Circle = "U_ArenaSpin", Ultimate = "Gladius_Ultimate" }),
	Legion = specials({ Left = "Legion_SpecCleave", Right = "LegionsFury", Up = "EagleOfRome", Down = "Legion_SpecHeavy", Circle = "U_ArenaSpin", Ultimate = "Legion_Ultimate" }),
	MorningStar = specials({ Left = "ChainTempest", Right = "MorningStar_SpecCombination", Up = "U_Rising", Down = "FallingMeteor", Circle = "U_ArenaSpin", Ultimate = "MorningStar_Ultimate" }),
	Trident = specials({ Left = "Trident_SpecCleave", Right = "RetiariusFury", Up = "SeaEagleDive", Down = "Trident_SpecHeavy", Circle = "U_ArenaSpin", Ultimate = "Trident_Ultimate" }),
	Hoplite = specials({ Left = "Hoplite_SpecCleave", Right = "PhalanxBreaker", Up = "SpartanVault", Down = "Hoplite_SpecHeavy", Circle = "U_ArenaSpin", Ultimate = "Hoplite_Ultimate" }),
	Daggers = specials({ Left = "Daggers_SpecCleave", Right = "ViperDance", Up = "RiverShadow", Down = "Daggers_SpecHeavy", Circle = "U_ArenaSpin", Ultimate = "Daggers_Ultimate" }),
	Axe = specials({ Left = "Axe_SpecCleave", Right = "ColosseumBreaker", Up = "U_Rising", Down = "ThunderOfMars", Circle = "U_ArenaSpin", Ultimate = "Axe_Ultimate" }),
	Bow = specials({ Left = "Bow_SpecFan", Right = "EagleShot", Up = "Bow_SpecPierce", Down = "ArrowRain", Circle = "Bow_SpecCircle", Ultimate = "Bow_Ultimate" }),
}

local WeaponSpecialDefinitions = {
	ByPrefix = table.freeze(byPrefix),
	TierDamage = table.freeze({ [1] = 1, [2] = 1.55, [3] = 2.05, [4] = 1 }) :: { [number]: number },
	TierPvPDamage = table.freeze({ [1] = 1, [2] = 1.2, [3] = 1.35, [4] = 1 }) :: { [number]: number },
	TierRecovery = table.freeze({ [1] = 0, [2] = 0.12, [3] = 0.25, [4] = 0 }) :: { [number]: number },
	TierCost = table.freeze({ [1] = 25, [2] = 50, [3] = 75, [4] = 100 }) :: { [number]: number },
	CircleTier = 2,
	FamilyCooldown = 1.5, -- seconds before the same family can be used again
	TierNames = table.freeze({ [1] = "I", [2] = "II", [3] = "III", [4] = "ULTIMATE" }) :: { [number]: string },
}

function WeaponSpecialDefinitions.forPrefix(prefix: string): WeaponSpecials?
	return byPrefix[prefix]
end

return table.freeze(WeaponSpecialDefinitions)
