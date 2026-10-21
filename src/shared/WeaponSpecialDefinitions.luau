--!strict
-- Each weapon's special moves, grouped in families (Left, Right, Up, Down, Circle, Ultimate).
-- SpecialChargeDefinitions picks the family by charge tier (I -> Right, II -> Left, III -> Down,
-- full charge with full Momentum -> Ultimate) and owns the damage multipliers and cooldowns.
-- Families reuse the weapons' named combination moves where they fit and generated moves
-- (SpecialMoveDefinitions: <Prefix>_SpecCleave / _SpecCombination / _SpecHeavy / ...) elsewhere.

export type Family = "Left" | "Right" | "Up" | "Down" | "Circle" | "Ultimate"

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
}

function WeaponSpecialDefinitions.forPrefix(prefix: string): WeaponSpecials?
	return byPrefix[prefix]
end

return table.freeze(WeaponSpecialDefinitions)
