--!strict
-- The four shields. Exactly one is equipped (left hand); hold right click to block.
-- Blocking only reduces damage from attacks in front of the player.

export type ShieldDefinition = {
	Id: string,
	DisplayName: string,
	Order: number,
	Price: number,
	Reduction: number, -- share of frontal damage removed while blocking (0.5 = 50 %)
	BlockSpeedMultiplier: number, -- multiplies the blocking walk speed
	StaggerMultiplier: number, -- how hard a blocked zombie is pushed back / staggered
}

local WoodenBuckler: ShieldDefinition = {
	Id = "WoodenBuckler",
	DisplayName = "Wooden Buckler",
	Order = 1,
	Price = 0,
	Reduction = 0.5,
	BlockSpeedMultiplier = 1,
	StaggerMultiplier = 1,
}

local LegionShield: ShieldDefinition = {
	Id = "LegionShield",
	DisplayName = "Legion Shield",
	Order = 2,
	Price = 60,
	Reduction = 0.65,
	BlockSpeedMultiplier = 1,
	StaggerMultiplier = 1,
}

local TowerShield: ShieldDefinition = {
	Id = "TowerShield",
	DisplayName = "Arena Tower Shield",
	Order = 3,
	Price = 120,
	Reduction = 0.78,
	BlockSpeedMultiplier = 0.8, -- heavy: slower while blocking
	StaggerMultiplier = 1.2,
}

local ChampionShield: ShieldDefinition = {
	Id = "ChampionShield",
	DisplayName = "Champion Shield",
	Order = 4,
	Price = 200,
	Reduction = 0.88,
	BlockSpeedMultiplier = 1,
	StaggerMultiplier = 2, -- stronger stagger on blocked attackers
}

local ShieldDefinitions = {
	Starter = "WoodenBuckler",
	ById = table.freeze({
		WoodenBuckler = WoodenBuckler,
		LegionShield = LegionShield,
		TowerShield = TowerShield,
		ChampionShield = ChampionShield,
	}) :: { [string]: ShieldDefinition },
	Ordered = table.freeze({ WoodenBuckler, LegionShield, TowerShield, ChampionShield }) :: { ShieldDefinition },
}

return table.freeze(ShieldDefinitions)
