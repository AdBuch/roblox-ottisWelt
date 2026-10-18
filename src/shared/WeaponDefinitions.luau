--!strict
-- The eight player weapons. Exactly one is equipped (right hand). Each weapon names its basic
-- attack and its aerial attack (Jump -> Attack) in SpecialMoveDefinitions; combination moves live
-- in ComboDefinitions (Attack / Block / Jump inputs + Execute).
-- Shop stats (Damage/Cooldown/Range) are read from the basic move, so there is one source of truth.

local SpecialMoveDefinitions = require(script.Parent.SpecialMoveDefinitions)

export type WeaponKind = "Melee" | "Bow"
-- Gladiator Armory row: Blades (fast / balanced), Heavy (heavy / long reach), Ranged (ranged / special)
export type DisplayRow = "Blades" | "Heavy" | "Ranged"

export type WeaponDefinition = {
	Id: string,
	DisplayName: string,
	Kind: WeaponKind,
	Order: number,
	Price: number,
	TwoHanded: boolean, -- uses both hands: no shield, built-in parry instead
	Basic: string,
	Aerial: string,
	Description: string,
	Row: DisplayRow,
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
	Aerial: string,
	Description: string,
	Row: DisplayRow?, -- default: Ranged for bows, otherwise from the basic move's range
}

local specs: { WeaponSpec } = {
	{ Id = "RustyGladius", DisplayName = "Rusty Gladius", Kind = "Melee", Price = 0, TwoHanded = false, Basic = "Gladius_Basic", Aerial = "Gladius_Aerial", Description = "Starter sword", Row = "Blades" },
	{ Id = "LegionSword", DisplayName = "Legion Sword", Kind = "Melee", Price = 80, TwoHanded = false, Basic = "Legion_Basic", Aerial = "Legion_Aerial", Description = "Polished bronze and steel", Row = "Blades" },
	{ Id = "HunterBow", DisplayName = "Hunter Bow", Kind = "Bow", Price = 130, TwoHanded = false, Basic = "Bow_Basic", Aerial = "Bow_Aerial", Description = "Ranged, blocked by walls", Row = "Ranged" },
	{ Id = "MorningStar", DisplayName = "Gladiator Morning Star", Kind = "Melee", Price = 190, TwoHanded = false, Basic = "MorningStar_Basic", Aerial = "MorningStar_Aerial", Description = "Wide, heavy swings", Row = "Heavy" },
	{ Id = "Trident", DisplayName = "Gladiator Trident", Kind = "Melee", Price = 260, TwoHanded = false, Basic = "Trident_Basic", Aerial = "Trident_Aerial", Description = "Long thrusts and a net", Row = "Heavy" },
	{ Id = "HopliteSpear", DisplayName = "Hoplite Spear", Kind = "Melee", Price = 300, TwoHanded = false, Basic = "Hoplite_Basic", Aerial = "Hoplite_Aerial", Description = "Longest reach", Row = "Heavy" },
	{ Id = "TwinDaggers", DisplayName = "Twin Arena Daggers", Kind = "Melee", Price = 340, TwoHanded = true, Basic = "Daggers_Basic", Aerial = "Daggers_Aerial", Description = "Two-handed: no shield, built-in parry", Row = "Blades" },
	{ Id = "BattleAxe", DisplayName = "Arena Battle Axe", Kind = "Melee", Price = 380, TwoHanded = false, Basic = "Axe_Basic", Aerial = "Axe_Aerial", Description = "Slow, heavy, devastating", Row = "Heavy" },
}

local byId: { [string]: WeaponDefinition } = {}
local ordered: { WeaponDefinition } = {}
for order, spec in specs do
	local basic = SpecialMoveDefinitions[spec.Basic]
	assert(basic and SpecialMoveDefinitions[spec.Aerial], "missing move for " .. spec.Id)
	local def: WeaponDefinition = {
		Id = spec.Id,
		DisplayName = spec.DisplayName,
		Kind = spec.Kind,
		Order = order,
		Price = spec.Price,
		TwoHanded = spec.TwoHanded,
		Basic = spec.Basic,
		Aerial = spec.Aerial,
		Description = spec.Description,
		Row = spec.Row or (if spec.Kind == "Bow" then "Ranged" elseif basic.Range >= 9 then "Heavy" else "Blades"),
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

-- The move id for "Basic" or "Aerial" of a weapon (combination moves: ComboDefinitions).
function WeaponDefinitions.moveFor(weapon: WeaponDefinition, action: string): string?
	if action == "Basic" then
		return weapon.Basic
	elseif action == "Aerial" then
		return weapon.Aerial
	end
	return nil
end

return WeaponDefinitions
