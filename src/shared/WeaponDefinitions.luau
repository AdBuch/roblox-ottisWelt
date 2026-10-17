--!strict
-- The four player weapons. Exactly one is equipped (right hand); left click attacks.
-- Melee weapons hit the closest valid zombie inside their arc (one target per attack).

export type WeaponKind = "Melee" | "Bow"

export type WeaponDefinition = {
	Id: string,
	DisplayName: string,
	Kind: WeaponKind,
	Order: number,
	Price: number,
	Damage: number,
	Cooldown: number,
	Range: number, -- melee reach, or the bow's maximum arrow distance
	FacingDot: number, -- melee arc: target must satisfy dot(look, toTarget) >= this
	Stagger: number, -- seconds the zombie is staggered on hit
	Knockback: number, -- push speed on hit (scaled by the zombie's knockback multiplier)
	ProjectileSpeed: number?, -- bow only
}

local RustyGladius: WeaponDefinition = {
	Id = "RustyGladius",
	DisplayName = "Rusty Gladius",
	Kind = "Melee",
	Order = 1,
	Price = 0,
	Damage = 18,
	Cooldown = 0.55,
	Range = 7,
	FacingDot = 0.3,
	Stagger = 0.1,
	Knockback = 8,
}

local LegionSword: WeaponDefinition = {
	Id = "LegionSword",
	DisplayName = "Legion Sword",
	Kind = "Melee",
	Order = 2,
	Price = 80,
	Damage = 28,
	Cooldown = 0.65,
	Range = 7.5,
	FacingDot = 0.3,
	Stagger = 0.15,
	Knockback = 10,
}

local HunterBow: WeaponDefinition = {
	Id = "HunterBow",
	DisplayName = "Hunter Bow",
	Kind = "Bow",
	Order = 3,
	Price = 130,
	Damage = 24,
	Cooldown = 0.9,
	Range = 90,
	FacingDot = -1,
	Stagger = 0.1,
	Knockback = 6,
	ProjectileSpeed = 110,
}

local MorningStar: WeaponDefinition = {
	Id = "MorningStar",
	DisplayName = "Gladiator Morning Star",
	Kind = "Melee",
	Order = 4,
	Price = 190,
	Damage = 40,
	Cooldown = 1.15,
	Range = 8,
	FacingDot = 0.0, -- wider arc (~90° to each side)
	Stagger = 0.45,
	Knockback = 18,
}

local WeaponDefinitions = {
	Starter = "RustyGladius",
	ById = table.freeze({
		RustyGladius = RustyGladius,
		LegionSword = LegionSword,
		HunterBow = HunterBow,
		MorningStar = MorningStar,
	}) :: { [string]: WeaponDefinition },
	Ordered = table.freeze({ RustyGladius, LegionSword, HunterBow, MorningStar }) :: { WeaponDefinition },
}

return table.freeze(WeaponDefinitions)
