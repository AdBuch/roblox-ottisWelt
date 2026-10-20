--!strict
-- The armor sets. Exactly one is equipped; Recruit Leather is free and owned by default, so every
-- player always enters the arena with armor. Armor reduces incoming damage after the shield
-- (DamageConfig: PvP uses only part of it) and may slow the wearer a little.
-- Armor can only be changed in the lobby / Gladiator Armory, never during a match.
-- Look: EquipmentModels.buildArmor (pieces on the torso, shoulders, arms and legs; no helmet,
-- so the player stays recognisable). Cloth pieces take the team color in Team Battle.

export type ArmorDefinition = {
	Id: string,
	DisplayName: string,
	Order: number,
	Price: number, -- Denarii (CurrencyConfig)
	AuraRequired: number, -- Aura needed before it can be bought or equipped (Aura is never spent)
	Reduction: number, -- share of incoming damage removed (PvE; PvP: DamageConfig.PvPArmorEffectiveness)
	MovePenalty: number, -- share of walk speed lost while wearing it
	Description: string,
}

local function armor(def: ArmorDefinition): ArmorDefinition
	return table.freeze(def) :: any
end

local list: { ArmorDefinition } = {
	armor({ Id = "RecruitLeather", DisplayName = "Recruit Leather", Order = 1, Price = 0, AuraRequired = 0, Reduction = 0.05, MovePenalty = 0, Description = "Leather straps, belt and light bracers" }),
	armor({ Id = "MurmilloArmor", DisplayName = "Murmillo Armor", Order = 2, Price = 180, AuraRequired = 180, Reduction = 0.15, MovePenalty = 0.02, Description = "Bronze shoulder guard, reinforced leather, leg guards" }),
	armor({ Id = "HopliteBronze", DisplayName = "Hoplite Bronze", Order = 3, Price = 320, AuraRequired = 320, Reduction = 0.25, MovePenalty = 0.06, Description = "Bronze chest plate over layered leather" }),
	armor({ Id = "ChampionArmor", DisplayName = "Champion Armor", Order = 4, Price = 520, AuraRequired = 520, Reduction = 0.35, MovePenalty = 0.10, Description = "Ornate battle-worn bronze of a Colosseum champion" }),
}

local byId: { [string]: ArmorDefinition } = {}
for _, def in list do
	byId[def.Id] = def
end
table.sort(list, function(a, b)
	return a.Order < b.Order
end)

local ArmorDefinitions = {
	Starter = "RecruitLeather",
	ById = table.freeze(byId),
	Ordered = table.freeze(list),
}

return table.freeze(ArmorDefinitions)
