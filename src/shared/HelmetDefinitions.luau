--!strict
-- The helmets: their own equipment slot, next to the armor. The free starter is "NoHelmet" (bare
-- head, no model). A helmet adds a little damage reduction on top of the armor (PlayerCombatService
-- armorReduction, capped with the armor) and sits on the head (EquipmentModels.buildHelmet).
-- Bought at the Helm shop of Rome (ArmoryShops, shop menu):
--   * 3 helmets for DENARII (Sparta, Gladiator, Roman general), unlocked by the gladiator level
--   * 10 helmets for ROBUX (`Robux` > 0): the heads of the three friends (Otti, Schili, Kroko), of
--     animals (dragon, rhino, bull, monkey) and of foreign fighters (samurai, WW2 soldier, Inca).
--     One developer product per helmet (create it in the Creator Hub and enter its id as
--     `ProductId`; 0 = not created yet, Studio test purchases only). A Robux helmet needs no level
--     and never protects better than the best Denarii helmet: Robux buy the look, not an advantage.

export type HelmetDefinition = {
	Id: string,
	DisplayName: string,
	Order: number,
	Price: number, -- Denarii (CurrencyConfig); 0 for Robux helmets
	Robux: number, -- price in Robux; 0 = sold for Denarii
	ProductId: number, -- developer product of a Robux helmet (0 = not created yet)
	Tier: number, -- balance tier 1..6
	LevelRequired: number, -- gladiator level (GladiatorLevelDefinitions) needed to BUY it
	Reduction: number, -- share of incoming damage removed on top of the armor (PvE; PvP: DamageConfig)
	Description: string,
}

local function helmet(def: { [string]: any }): HelmetDefinition
	def.Robux = def.Robux or 0
	def.ProductId = def.ProductId or 0
	def.Price = def.Price or 0
	return table.freeze(def) :: any
end

local ROBUX_REDUCTION = 0.08 -- every Robux helmet: the middle Denarii tier

local list: { HelmetDefinition } = {
	helmet({ Id = "NoHelmet", DisplayName = "Kein Helm", Order = 1, Price = 0, Tier = 1, LevelRequired = 1, Reduction = 0, Description = "Ohne Helm: Gesicht und Haare bleiben sichtbar" }),
	-- DENARII
	helmet({ Id = "SpartaHelm", DisplayName = "Spartaner", Order = 2, Price = 90, Tier = 2, LevelRequired = 6, Reduction = 0.04, Description = "Korinthischer Bronzehelm mit Nasenschutz und Rosshaarkamm" }),
	helmet({ Id = "MurmilloHelm", DisplayName = "Gladiator", Order = 3, Price = 200, Tier = 3, LevelRequired = 16, Reduction = 0.08, Description = "Geschlossener Murmillo-Helm mit Visier, breiter Krempe und Fischkamm" }),
	helmet({ Id = "ChampionCrest", DisplayName = "Römischer General", Order = 4, Price = 380, Tier = 5, LevelRequired = 32, Reduction = 0.12, Description = "Vergoldeter Legatenhelm mit Wangenklappen und hohem roten Querkamm" }),
	-- ROBUX: the three friends
	helmet({ Id = "OttiHead", DisplayName = "Otti-Kopf", Order = 10, Robux = 99, Tier = 3, LevelRequired = 1, Reduction = ROBUX_REDUCTION, Description = "Der Kopf des Otters Otti: braunes Fell, helle Schnauze, runde Ohren" }),
	helmet({ Id = "SchiliHead", DisplayName = "Schili-Kopf", Order = 11, Robux = 99, Tier = 3, LevelRequired = 1, Reduction = ROBUX_REDUCTION, Description = "Der Kopf der Schildkröte Schili mit einem Stück Panzer im Nacken" }),
	helmet({ Id = "KrokoHead", DisplayName = "Kroko-Kopf", Order = 12, Robux = 99, Tier = 3, LevelRequired = 1, Reduction = ROBUX_REDUCTION, Description = "Der Kopf des Krokodils Kroko: lange Schnauze, Zähne, Bernsteinaugen" }),
	-- ROBUX: animals
	helmet({ Id = "DragonHead", DisplayName = "Drachenkopf", Order = 13, Robux = 149, Tier = 3, LevelRequired = 1, Reduction = ROBUX_REDUCTION, Description = "Roter Drachenkopf mit Hörnern, Rückenkamm und glühenden Augen" }),
	helmet({ Id = "RhinoHead", DisplayName = "Nashornkopf", Order = 14, Robux = 119, Tier = 3, LevelRequired = 1, Reduction = ROBUX_REDUCTION, Description = "Grauer Nashornkopf mit zwei Hörnern" }),
	helmet({ Id = "ToroHead", DisplayName = "Toro", Order = 15, Robux = 119, Tier = 3, LevelRequired = 1, Reduction = ROBUX_REDUCTION, Description = "Schwarzer Stierkopf mit geschwungenen Hörnern und goldenem Nasenring" }),
	helmet({ Id = "MonkeyHead", DisplayName = "Affenkopf", Order = 16, Robux = 99, Tier = 3, LevelRequired = 1, Reduction = ROBUX_REDUCTION, Description = "Affenkopf mit hellem Gesicht und grossen Ohren" }),
	-- ROBUX: foreign fighters
	helmet({ Id = "SamuraiHelm", DisplayName = "Samurai", Order = 17, Robux = 129, Tier = 3, LevelRequired = 1, Reduction = ROBUX_REDUCTION, Description = "Kabuto: schwarzer Lackhelm mit Nackenschirm und goldenem Halbmond" }),
	helmet({ Id = "SoldierHelm", DisplayName = "Soldat 1944", Order = 18, Robux = 99, Tier = 3, LevelRequired = 1, Reduction = ROBUX_REDUCTION, Description = "Olivgrüner Stahlhelm eines Soldaten aus dem Zweiten Weltkrieg mit Tarnnetz und Kinnriemen" }),
	helmet({ Id = "IncaHelm", DisplayName = "Inka", Order = 19, Robux = 129, Tier = 3, LevelRequired = 1, Reduction = ROBUX_REDUCTION, Description = "Goldener Inka-Kopfschmuck mit Sonnenscheibe und bunten Federn" }),
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
	-- helmets that no longer exist -> the helmet an owner gets instead (InventoryService migration)
	Renamed = table.freeze({ Galea = "SpartaHelm" }) :: { [string]: string },
}

-- Key of a Robux helmet's developer product (ForgeDefinitions.Products).
function HelmetDefinitions.productKey(id: string): string
	return "Helmet_" .. id
end

return table.freeze(HelmetDefinitions)
