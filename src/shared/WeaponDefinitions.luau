--!strict
-- The eight player weapons. Exactly one is equipped (right hand). Each weapon names its basic
-- attack and two specials in SpecialMoveDefinitions; combos live in ComboDefinitions.
-- Shop stats (Damage/Cooldown/Range) are read from the basic move, so there is one source of truth.

local SpecialMoveDefinitions = require(script.Parent.SpecialMoveDefinitions)

export type WeaponKind = "Melee" | "Bow"

export type WeaponDefinition = {
	Id: string,
	DisplayName: string,
	Kind: WeaponKind,
	Order: number,
	Price: number,
	TwoHanded: boolean, -- uses both hands: no shield, built-in parry instead
	Basic: string,
	Special1: string,
	Special2: string,
	Description: string,
	-- derived from the basic move (display only)
	Damage: number,
	Cooldown: number,
	Range: number,
}

type WeaponSpec = {
	Id: string,
	DisplayName: string,
	Kind: WeaponKind,
	Price: number,
	TwoHanded: boolean,
	Basic: string,
	Special1: string,
	Special2: string,
	Description: string,
}

local specs: { WeaponSpec } = {
	{ Id = "RustyGladius", DisplayName = "Rusty Gladius", Kind = "Melee", Price = 0, TwoHanded = false, Basic = "Gladius_Basic", Special1 = "QuickThrust", Special2 = "ShieldCounter", Description = "Starter sword" },
	{ Id = "LegionSword", DisplayName = "Legion Sword", Kind = "Melee", Price = 80, TwoHanded = false, Basic = "Legion_Basic", Special1 = "LegionCombo", Special2 = "RisingSlash", Description = "Polished bronze and steel" },
	{ Id = "HunterBow", DisplayName = "Hunter Bow", Kind = "Bow", Price = 130, TwoHanded = false, Basic = "Bow_Basic", Special1 = "TripleShot", Special2 = "PiercingArrow", Description = "Ranged, blocked by walls" },
	{ Id = "MorningStar", DisplayName = "Gladiator Morning Star", Kind = "Melee", Price = 190, TwoHanded = false, Basic = "MorningStar_Basic", Special1 = "HeavyCrush", Special2 = "ChainSweep", Description = "Wide, heavy swings" },
	{ Id = "Trident", DisplayName = "Gladiator Trident", Kind = "Melee", Price = 260, TwoHanded = false, Basic = "Trident_Basic", Special1 = "TridentRush", Special2 = "NetAndStrike", Description = "Long thrusts and a net" },
	{ Id = "HopliteSpear", DisplayName = "Hoplite Spear", Kind = "Melee", Price = 300, TwoHanded = false, Basic = "Hoplite_Basic", Special1 = "PhalanxThrust", Special2 = "SpearSweep", Description = "Longest reach" },
	{ Id = "TwinDaggers", DisplayName = "Twin Arena Daggers", Kind = "Melee", Price = 340, TwoHanded = true, Basic = "Daggers_Basic", Special1 = "ViperFlurry", Special2 = "ShadowStep", Description = "Two-handed: no shield, built-in parry" },
	{ Id = "BattleAxe", DisplayName = "Arena Battle Axe", Kind = "Melee", Price = 380, TwoHanded = false, Basic = "Axe_Basic", Special1 = "ExecutionArc", Special2 = "Whirlwind", Description = "Slow, heavy, devastating" },
}

local byId: { [string]: WeaponDefinition } = {}
local ordered: { WeaponDefinition } = {}
for order, spec in specs do
	local basic = SpecialMoveDefinitions[spec.Basic]
	assert(basic and SpecialMoveDefinitions[spec.Special1] and SpecialMoveDefinitions[spec.Special2], "missing move for " .. spec.Id)
	local def: WeaponDefinition = {
		Id = spec.Id,
		DisplayName = spec.DisplayName,
		Kind = spec.Kind,
		Order = order,
		Price = spec.Price,
		TwoHanded = spec.TwoHanded,
		Basic = spec.Basic,
		Special1 = spec.Special1,
		Special2 = spec.Special2,
		Description = spec.Description,
		Damage = basic.Damage,
		Cooldown = basic.Cooldown,
		Range = basic.Range,
	}
	table.freeze(def)
	byId[def.Id] = def
	table.insert(ordered, def)
end

local WeaponDefinitions = {
	Starter = "RustyGladius",
	ById = table.freeze(byId),
	Ordered = table.freeze(ordered),
}

-- The move id for an action ("Basic" | "Special1" | "Special2") of a weapon.
function WeaponDefinitions.moveFor(weapon: WeaponDefinition, action: string): string?
	if action == "Basic" then
		return weapon.Basic
	elseif action == "Special1" then
		return weapon.Special1
	elseif action == "Special2" then
		return weapon.Special2
	end
	return nil
end

return WeaponDefinitions
