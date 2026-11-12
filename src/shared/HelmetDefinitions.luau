--!strict
-- The helmets: their own equipment slot, next to the armor. The free starter is "NoHelmet" (bare
-- head, no model). A helmet adds a little damage reduction on top of the armor (PlayerCombatService
-- armorReduction, capped with the armor) and sits on the head (EquipmentModels.buildHelmet).
-- Bought at the Helm shop of Rome (ArmoryShops); the Gladiator Armory no longer holds gear.

export type HelmetDefinition = {
	Id: string,
	DisplayName: string,
	Order: number,
	Price: number, -- Denarii (CurrencyConfig)
	Tier: number, -- balance tier 1..6
	LevelRequired: number, -- gladiator level (GladiatorLevelDefinitions) needed to BUY it
	Reduction: number, -- share of incoming damage removed on top of the armor (PvE; PvP: DamageConfig)
	Description: string,
}

local function helmet(def: HelmetDefinition): HelmetDefinition
	return table.freeze(def) :: any
end

local list: { HelmetDefinition } = {
	helmet({ Id = "NoHelmet", DisplayName = "Bare Head", Order = 1, Price = 0, Tier = 1, LevelRequired = 1, Reduction = 0, Description = "No helmet: the face and hair stay visible" }),
	helmet({ Id = "Galea", DisplayName = "Galea", Order = 2, Price = 90, Tier = 2, LevelRequired = 6, Reduction = 0.04, Description = "Legionary skull cap with cheek guards" }),
	helmet({ Id = "MurmilloHelm", DisplayName = "Murmillo Helm", Order = 3, Price = 200, Tier = 3, LevelRequired = 16, Reduction = 0.08, Description = "Closed bronze helm with a visor and a fish crest" }),
	helmet({ Id = "ChampionCrest", DisplayName = "Champion Helm", Order = 4, Price = 380, Tier = 5, LevelRequired = 32, Reduction = 0.12, Description = "Gilded helm with a tall red crest" }),
}

local byId: { [string]: HelmetDefinition } = {}
for _, def in list do
	byId[def.Id] = def
end
table.sort(list, function(a, b)
	return a.Order < b.Order
end)

local HelmetDefinitions = {
	Starter = "NoHelmet",
	ById = table.freeze(byId),
	Ordered = table.freeze(list),
}

return table.freeze(HelmetDefinitions)
