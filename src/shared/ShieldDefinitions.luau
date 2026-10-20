--!strict
-- The eight shields. Exactly one is equipped (left hand); hold right click to block.
-- Blocking only protects inside the shield's frontal angle (FacingDot) and only after the
-- shield is fully raised (RaiseSeconds).

export type ShieldDefinition = {
	Id: string,
	DisplayName: string,
	Order: number,
	Price: number, -- Denarii (CurrencyConfig)
	AuraRequired: number, -- Aura needed before it can be bought or equipped (Aura is never spent)
	Reduction: number, -- share of frontal melee damage removed while blocking
	ProjectileReduction: number, -- share of frontal arrow damage removed while blocking
	FacingDot: number, -- block angle: attacker must satisfy dot(look, toAttacker) >= this (lower = wider)
	BlockSpeedMultiplier: number, -- multiplies the blocking walk speed (>1 = faster)
	RaiseSeconds: number, -- time until a raised shield protects
	StaggerMultiplier: number, -- how hard a blocked zombie is pushed back / staggered
	BashMultiplier: number, -- strength of shield-bash moves (e.g. SHIELD COUNTER)
	Description: string,
}

-- Gladiator Armory sections (display only)
export type ShieldClass = "Light" | "Balanced" | "Heavy"

local function shield(def: ShieldDefinition): ShieldDefinition
	return table.freeze(def) :: any
end

local list: { ShieldDefinition } = {
	shield({ Id = "WoodenBuckler", DisplayName = "Wooden Buckler", Order = 1, Price = 0, AuraRequired = 0, Reduction = 0.5, ProjectileReduction = 0.5, FacingDot = 0.5, BlockSpeedMultiplier = 1, RaiseSeconds = 0.1, StaggerMultiplier = 1, BashMultiplier = 1, Description = "Starter, small" }),
	shield({ Id = "LegionShield", DisplayName = "Legion Shield", Order = 2, Price = 60, AuraRequired = 60, Reduction = 0.65, ProjectileReduction = 0.6, FacingDot = 0.5, BlockSpeedMultiplier = 1, RaiseSeconds = 0.12, StaggerMultiplier = 1, BashMultiplier = 1.1, Description = "Red wood, bronze rim" }),
	shield({ Id = "ParmaEquestris", DisplayName = "Parma Equestris", Order = 3, Price = 180, AuraRequired = 180, Reduction = 0.6, ProjectileReduction = 0.6, FacingDot = 0.6, BlockSpeedMultiplier = 1.1, RaiseSeconds = 0.05, StaggerMultiplier = 1, BashMultiplier = 1, Description = "Light, quick to raise, narrow angle" }),
	shield({ Id = "TowerShield", DisplayName = "Arena Tower Shield", Order = 4, Price = 120, AuraRequired = 120, Reduction = 0.78, ProjectileReduction = 0.85, FacingDot = 0.35, BlockSpeedMultiplier = 0.8, RaiseSeconds = 0.2, StaggerMultiplier = 1.2, BashMultiplier = 1.2, Description = "Large, slower while blocking" }),
	shield({ Id = "ChampionShield", DisplayName = "Champion Shield", Order = 5, Price = 200, AuraRequired = 200, Reduction = 0.88, ProjectileReduction = 0.8, FacingDot = 0.5, BlockSpeedMultiplier = 1, RaiseSeconds = 0.15, StaggerMultiplier = 2, BashMultiplier = 1.3, Description = "Ornate bronze, strong stagger" }),
	shield({ Id = "Scutum", DisplayName = "Scutum", Order = 6, Price = 250, AuraRequired = 250, Reduction = 0.82, ProjectileReduction = 0.95, FacingDot = 0.25, BlockSpeedMultiplier = 0.75, RaiseSeconds = 0.2, StaggerMultiplier = 1.3, BashMultiplier = 1.2, Description = "Tall curved Roman shield, wide angle, best vs arrows" }),
	shield({ Id = "Hoplon", DisplayName = "Hoplon", Order = 7, Price = 280, AuraRequired = 280, Reduction = 0.72, ProjectileReduction = 0.75, FacingDot = 0.4, BlockSpeedMultiplier = 0.85, RaiseSeconds = 0.15, StaggerMultiplier = 1.4, BashMultiplier = 1.8, Description = "Large round bronze shield, strongest bash" }),
	shield({ Id = "ThraexShield", DisplayName = "Thraex Shield", Order = 8, Price = 320, AuraRequired = 320, Reduction = 0.84, ProjectileReduction = 0.8, FacingDot = 0.65, BlockSpeedMultiplier = 1.15, RaiseSeconds = 0.04, StaggerMultiplier = 1.2, BashMultiplier = 1.1, Description = "Small high shield, very fast, narrow angle" }),
}

local byId: { [string]: ShieldDefinition } = {}
for _, def in list do
	byId[def.Id] = def
end
table.sort(list, function(a, b)
	return a.Order < b.Order
end)

local classes: { [string]: ShieldClass } = {
	WoodenBuckler = "Light",
	ParmaEquestris = "Light",
	ThraexShield = "Light",
	LegionShield = "Balanced",
	ChampionShield = "Balanced",
	TowerShield = "Heavy",
	Scutum = "Heavy",
	Hoplon = "Heavy",
}

local ShieldDefinitions = {
	Starter = "WoodenBuckler",
	ById = table.freeze(byId),
	Ordered = table.freeze(list),
	ClassOrder = table.freeze({ "Light" :: ShieldClass, "Balanced" :: ShieldClass, "Heavy" :: ShieldClass }),
}

-- Armory section of a shield; new shields without an entry are sorted by their block slowdown.
function ShieldDefinitions.classOf(def: ShieldDefinition): ShieldClass
	local class = classes[def.Id]
	if class then
		return (class :: any) :: ShieldClass
	end
	if def.BlockSpeedMultiplier >= 1.1 then
		return "Light"
	elseif def.BlockSpeedMultiplier <= 0.85 then
		return "Heavy"
	end
	return "Balanced"
end

return table.freeze(ShieldDefinitions)
