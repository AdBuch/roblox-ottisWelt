--!strict
-- The six Roman zombie variants: stats, Aura rewards (field "Coins"), spawn availability/weights, and the
-- body/gear choices ZombieFactory builds from. All variants share the same AI (ZombieService);
-- Special selects an extra ability ("Net" throw, champion "Guard" or "Archer" ranged AI).

export type ZombieBody = {
	Scale: number, -- uniform scale applied to the whole rig
	Torso: Vector3,
	Head: Vector3,
	Arm: Vector3, -- width, length, depth
	Leg: Vector3,
	HipSpread: number,
}

export type ZombieGear = {
	Helmet: "Crested" | "Damaged" | "Cap" | "OpenFace" | "Ornate" | "Wrap",
	Shoulders: "Single" | "HeavyBoth" | "Segmented" | "None",
	Weapon: "Gladius" | "Club" | "Spear" | "LargeSword" | "Bow",
	Shield: "Round" | "Buckler" | "Ornate" | "Scutum" | "None",
	Armor: "Harness" | "Straps" | "Vest" | "Light" | "Heavy" | "Segmentata",
	ThickBelt: boolean,
	Scarf: boolean,
	Net: boolean, -- folded net in the left hand
	ClothColor: Color3,
	CrestColor: Color3,
	EyeGlow: number, -- eye light brightness
	Quiver: boolean?, -- quiver with visible arrows on the back (archer)
	WristGuard: boolean?,
}

export type ZombieSpecial = "None" | "Net" | "Guard" | "Archer"

export type ZombieDefinition = {
	Id: string,
	DisplayName: string,
	Health: number,
	Damage: number,
	WalkSpeed: number,
	AttackCooldown: number,
	WindUpSeconds: number, -- visible telegraph before every attack
	AttackRange: number, -- starts an attack inside this distance
	AttackReach: number, -- the blow only lands if the target is still this close
	KnockbackMultiplier: number, -- how far blocks/hits push it (lower = more resistant)
	StaggerSeconds: number, -- how long a shield block stuns it
	Coins: number, -- reward for the killing player
	AvailableFromRound: number,
	SpawnWeight: number, -- relative; unavailable types are filtered and the rest normalized
	Special: ZombieSpecial,
	AIProfile: string, -- personality in ZombieAIProfiles
	Role: string, -- archive plaque text
	SpecialText: string, -- archive plaque text
	-- Net fighter
	NetRange: number?,
	NetCooldown: number?,
	NetWindUp: number?,
	NetSlowFactor: number?, -- walk speed multiplier while netted
	NetSlowSeconds: number?,
	-- Champion guard
	GuardSeconds: number?,
	GuardCooldown: number?,
	-- Archer (Undead Sagittarius)
	DetectRange: number?, -- overrides the profile chase distance
	ArrowDamage: number?,
	FireCooldown: number?,
	DrawSeconds: number?, -- visible bow draw before every shot
	PreferredRangeMin: number?,
	PreferredRangeMax: number?,
	MinComfortRange: number?, -- relocates when a player gets closer than this
	AimErrorDegrees: number?, -- base inaccuracy (wounded/critical archers miss more)
	LeadFactor: number?, -- share of the target movement it predicts (slight)
	Body: ZombieBody,
	Gear: ZombieGear,
}

local RED = Color3.fromRGB(116, 24, 30)
local BLUE_GRAY = Color3.fromRGB(84, 98, 120)
local PURPLE = Color3.fromRGB(88, 30, 110)

local LegionRemnant: ZombieDefinition = {
	Id = "LegionRemnant",
	DisplayName = "Legion Remnant",
	Health = 60,
	Damage = 10,
	WalkSpeed = 12,
	AttackCooldown = 1.4,
	WindUpSeconds = 0.4,
	AttackRange = 7,
	AttackReach = 8,
	KnockbackMultiplier = 1,
	StaggerSeconds = 0.6,
	Coins = 10,
	AvailableFromRound = 1,
	SpawnWeight = 40,
	Special = "None",
	AIProfile = "Disciplined",
	Role = "Balanced fighter",
	SpecialText = "Sword and shield, blocks now and then",
	Body = {
		Scale = 1,
		Torso = Vector3.new(2.6, 2.4, 1.7),
		Head = Vector3.new(1.85, 1.75, 1.7),
		Arm = Vector3.new(1.0, 2.3, 1.0),
		Leg = Vector3.new(1.1, 2.5, 1.1),
		HipSpread = 0.62,
	},
	Gear = {
		Helmet = "Crested",
		Shoulders = "Segmented",
		Weapon = "Gladius",
		Shield = "Scutum",
		Armor = "Segmentata",
		ThickBelt = false,
		Scarf = true,
		Net = false,
		ClothColor = RED,
		CrestColor = RED,
		EyeGlow = 1.5,
	},
}

local RottenVelite: ZombieDefinition = {
	Id = "RottenVelite",
	DisplayName = "Rotten Velite",
	Health = 40,
	Damage = 7,
	WalkSpeed = 15,
	AttackCooldown = 0.95,
	WindUpSeconds = 0.3,
	AttackRange = 9,
	AttackReach = 11, -- spear
	KnockbackMultiplier = 1.3,
	StaggerSeconds = 0.8,
	Coins = 8,
	AvailableFromRound = 2,
	SpawnWeight = 25,
	Special = "None",
	AIProfile = "Skirmisher",
	Role = "Fast skirmisher",
	SpecialText = "Quick spear jabs, then runs off",
	Body = {
		Scale = 0.88,
		Torso = Vector3.new(2.2, 2.1, 1.5),
		Head = Vector3.new(1.9, 1.8, 1.7),
		Arm = Vector3.new(0.9, 1.9, 0.9),
		Leg = Vector3.new(1.0, 2.0, 1.0),
		HipSpread = 0.52,
	},
	Gear = {
		Helmet = "Cap",
		Shoulders = "None",
		Weapon = "Spear",
		Shield = "Buckler",
		Armor = "Vest",
		ThickBelt = false,
		Scarf = true,
		Net = false,
		ClothColor = RED,
		CrestColor = RED,
		EyeGlow = 1.5,
	},
}

local ArenaBrute: ZombieDefinition = {
	Id = "ArenaBrute",
	DisplayName = "Arena Brute",
	Health = 100,
	Damage = 18,
	WalkSpeed = 8.5,
	AttackCooldown = 2.1,
	WindUpSeconds = 0.6,
	AttackRange = 8,
	AttackReach = 9,
	KnockbackMultiplier = 0.4, -- heavy: barely pushed back...
	StaggerSeconds = 0.3, -- ...and recovers quickly
	Coins = 18,
	AvailableFromRound = 3,
	SpawnWeight = 17,
	Special = "None",
	AIProfile = "Tank",
	Role = "Heavy attacker",
	SpecialText = "Beware the crushing strike",
	Body = {
		Scale = 1.18,
		Torso = Vector3.new(3.4, 2.6, 2.3),
		Head = Vector3.new(2.1, 1.9, 1.9),
		Arm = Vector3.new(1.35, 2.3, 1.35),
		Leg = Vector3.new(1.4, 2.1, 1.4),
		HipSpread = 0.8,
	},
	Gear = {
		Helmet = "Damaged",
		Shoulders = "HeavyBoth",
		Weapon = "Club",
		Shield = "None",
		Armor = "Straps",
		ThickBelt = true,
		Scarf = false,
		Net = false,
		ClothColor = RED,
		CrestColor = RED,
		EyeGlow = 1.5,
	},
}

local NetFighter: ZombieDefinition = {
	Id = "NetFighter",
	DisplayName = "Zombie Retiarius",
	Health = 55,
	Damage = 8,
	WalkSpeed = 11.5,
	AttackCooldown = 1.3,
	WindUpSeconds = 0.4,
	AttackRange = 7,
	AttackReach = 8,
	KnockbackMultiplier = 1,
	StaggerSeconds = 0.6,
	Coins = 14,
	AvailableFromRound = 3,
	SpawnWeight = 13,
	Special = "Net",
	AIProfile = "Controller",
	Role = "Tactical controller",
	SpecialText = "Throws a net that slows you",
	NetRange = 16,
	NetCooldown = 7,
	NetWindUp = 0.7,
	NetSlowFactor = 0.75, -- 25 % slower
	NetSlowSeconds = 2,
	Body = {
		Scale = 0.98,
		Torso = Vector3.new(2.5, 2.3, 1.7),
		Head = Vector3.new(1.95, 1.85, 1.75),
		Arm = Vector3.new(1.0, 2.1, 1.0),
		Leg = Vector3.new(1.1, 2.2, 1.1),
		HipSpread = 0.6,
	},
	Gear = {
		Helmet = "OpenFace",
		Shoulders = "None",
		Weapon = "Gladius",
		Shield = "None",
		Armor = "Light",
		ThickBelt = false,
		Scarf = true,
		Net = true,
		ClothColor = BLUE_GRAY,
		CrestColor = BLUE_GRAY,
		EyeGlow = 1.5,
	},
}

local ArenaChampion: ZombieDefinition = {
	Id = "ArenaChampion",
	DisplayName = "Zombie Arena Champion",
	Health = 130,
	Damage = 15,
	WalkSpeed = 9,
	AttackCooldown = 1.6,
	WindUpSeconds = 0.55,
	AttackRange = 8,
	AttackReach = 9,
	KnockbackMultiplier = 0.3,
	StaggerSeconds = 0.35,
	Coins = 25,
	AvailableFromRound = 4,
	SpawnWeight = 5, -- rare
	Special = "Guard",
	AIProfile = "Elite",
	Role = "Rare elite",
	SpecialText = "Raises a shield that blocks frontal hits",
	GuardSeconds = 1.6, -- shield raised (visible glow): frontal hits are blocked
	GuardCooldown = 4.5, -- exposed time before it can guard again
	Body = {
		Scale = 1.3,
		Torso = Vector3.new(3.2, 2.7, 2.2),
		Head = Vector3.new(2.15, 2.0, 1.95),
		Arm = Vector3.new(1.3, 2.4, 1.3),
		Leg = Vector3.new(1.35, 2.3, 1.35),
		HipSpread = 0.78,
	},
	Gear = {
		Helmet = "Ornate",
		Shoulders = "HeavyBoth",
		Weapon = "LargeSword",
		Shield = "Ornate",
		Armor = "Heavy",
		ThickBelt = true,
		Scarf = true,
		Net = false,
		ClothColor = PURPLE,
		CrestColor = PURPLE,
		EyeGlow = 3,
	},
}

local UndeadSagittarius: ZombieDefinition = {
	Id = "UndeadSagittarius",
	DisplayName = "Undead Sagittarius",
	Health = 45,
	Damage = 5, -- weak close-range strike when cornered
	WalkSpeed = 12,
	AttackCooldown = 1.6,
	WindUpSeconds = 0.45,
	AttackRange = 5,
	AttackReach = 6,
	KnockbackMultiplier = 1.25,
	StaggerSeconds = 0.7,
	Coins = 12,
	AvailableFromRound = 3,
	SpawnWeight = 10, -- less common than melee zombies; active count is capped per player count
	Special = "Archer",
	AIProfile = "Marksman",
	Role = "Ranged support",
	SpecialText = "Draws its bow before every shot. Block or dodge!",
	DetectRange = 140,
	ArrowDamage = 8,
	FireCooldown = 2.2,
	DrawSeconds = 0.75,
	PreferredRangeMin = 55,
	PreferredRangeMax = 85,
	MinComfortRange = 25,
	AimErrorDegrees = 2.2,
	LeadFactor = 0.35,
	Body = {
		Scale = 0.92,
		Torso = Vector3.new(2.2, 2.3, 1.5),
		Head = Vector3.new(1.9, 1.8, 1.75),
		Arm = Vector3.new(0.9, 2.1, 0.9),
		Leg = Vector3.new(1.0, 2.25, 1.0),
		HipSpread = 0.52,
	},
	Gear = {
		Helmet = "Wrap",
		Shoulders = "None",
		Weapon = "Bow",
		Shield = "None",
		Armor = "Vest",
		ThickBelt = false,
		Scarf = true,
		Net = false,
		ClothColor = Color3.fromRGB(78, 98, 132), -- faded blue scarf
		CrestColor = RED,
		EyeGlow = 2,
		Quiver = true,
		WristGuard = true,
	},
}

local ZombieDefinitions = {
	ById = table.freeze({
		LegionRemnant = LegionRemnant,
		RottenVelite = RottenVelite,
		ArenaBrute = ArenaBrute,
		NetFighter = NetFighter,
		ArenaChampion = ArenaChampion,
		UndeadSagittarius = UndeadSagittarius,
	}) :: { [string]: ZombieDefinition },
	Ordered = table.freeze({ LegionRemnant, RottenVelite, ArenaBrute, NetFighter, ArenaChampion, UndeadSagittarius }) :: { ZombieDefinition },
}

return table.freeze(ZombieDefinitions)
