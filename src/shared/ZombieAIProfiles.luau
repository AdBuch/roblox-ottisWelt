--!strict
-- Personalities for the shared zombie AI (ZombieService). One base AI reads these values,
-- so every type behaves differently without duplicating the implementation.
--
-- Target score per living arena player (higher wins):
--   Threat * threat (damage dealt to this zombie, blocks)   Proximity * closeness
--   LowHealth * missing health                              Moving * how fast the player moves
--   Equipment * gear value                                   Exposed * not blocking / facing away
--   - crowding (players already chased by many zombies score lower)
--   + a small bonus for the current target (no flip-flopping)

export type TargetWeights = {
	Threat: number,
	Proximity: number,
	LowHealth: number,
	Moving: number,
	Equipment: number,
	Exposed: number,
}

export type ZombieAIProfile = {
	Id: string,
	Summary: string,
	PreferredDistance: number, -- 0 = fight from a melee slot; > 0 keep this distance (until ability used)
	Aggression: number, -- 0..1 chance to start an attack when allowed
	TargetWeights: TargetWeights,
	MaxChaseDistance: number, -- players farther away are ignored
	CircleTendency: number, -- 0..1: how much it drifts around its target while waiting
	DriftChangeInterval: number, -- seconds between direction changes while circling
	RetreatAfterAttack: number, -- seconds it backs off after attacking (0 = never)
	BlockChance: number, -- chance to raise its own guard when a player is attacking nearby
	GuardSeconds: number,
	ShieldBashChance: number, -- chance to shield-bash a blocking player instead of a normal attack
	BlockPierce: number, -- share of the player's shield reduction its attacks ignore
	RoarChance: number, -- chance of an extra roar telegraph before an attack
	AvoidHeavyShields: boolean, -- moves around players blocking with big shields
	AvoidSlotsUntilAbilityUsed: boolean, -- stays at range until its ability is on cooldown
	YieldToHeavies: boolean, -- steps away when a brute/champion occupies the same space
	ExposedAfterMiss: number, -- stunned this long when an attack misses
}

local function profile(def: ZombieAIProfile): ZombieAIProfile
	return table.freeze(def) :: any
end

local ZombieAIProfiles: { [string]: ZombieAIProfile } = {
	-- Disciplined basic fighter: direct, nearest player, occasional shield block, keeps formation.
	Disciplined = profile({
		Id = "Disciplined",
		Summary = "Approaches directly, blocks occasionally, keeps formation",
		PreferredDistance = 0,
		Aggression = 0.8,
		TargetWeights = { Threat = 0.6, Proximity = 1.4, LowHealth = 0.2, Moving = 0, Equipment = 0, Exposed = 0.2 },
		MaxChaseDistance = 160,
		CircleTendency = 0.2,
		DriftChangeInterval = 4,
		RetreatAfterAttack = 0,
		BlockChance = 0.25,
		GuardSeconds = 0.9,
		ShieldBashChance = 0,
		BlockPierce = 0,
		RoarChance = 0,
		AvoidHeavyShields = false,
		AvoidSlotsUntilAbilityUsed = false,
		YieldToHeavies = false,
		ExposedAfterMiss = 0,
	}),

	-- Impatient skirmisher: circles, changes direction, hunts low-health/exposed players, hit and run.
	Skirmisher = profile({
		Id = "Skirmisher",
		Summary = "Circles, hunts weak or exposed players, retreats after attacking",
		PreferredDistance = 0,
		Aggression = 0.9,
		TargetWeights = { Threat = 0.2, Proximity = 0.8, LowHealth = 1.6, Moving = 0.2, Equipment = 0, Exposed = 1.2 },
		MaxChaseDistance = 160,
		CircleTendency = 0.9,
		DriftChangeInterval = 1.2,
		RetreatAfterAttack = 1.2,
		BlockChance = 0,
		GuardSeconds = 0,
		ShieldBashChance = 0,
		BlockPierce = 0,
		RoarChance = 0,
		AvoidHeavyShields = true,
		AvoidSlotsUntilAbilityUsed = false,
		YieldToHeavies = false,
		ExposedAfterMiss = 0,
	}),

	-- Slow aggressive tank: punishes damage dealers nearby, breaks blocks, roars, won't chase far.
	Tank = profile({
		Id = "Tank",
		Summary = "Targets nearby damage dealers, breaks blocks, roars before heavy hits",
		PreferredDistance = 0,
		Aggression = 0.7,
		TargetWeights = { Threat = 1.6, Proximity = 1.6, LowHealth = 0, Moving = 0, Equipment = 0, Exposed = 0 },
		MaxChaseDistance = 35,
		CircleTendency = 0,
		DriftChangeInterval = 6,
		RetreatAfterAttack = 0,
		BlockChance = 0,
		GuardSeconds = 0,
		ShieldBashChance = 0,
		BlockPierce = 0.5,
		RoarChance = 0.5,
		AvoidHeavyShields = false,
		AvoidSlotsUntilAbilityUsed = false,
		YieldToHeavies = false,
		ExposedAfterMiss = 0,
	}),

	-- Tactical controller: keeps medium range, nets moving players first, then closes in.
	Controller = profile({
		Id = "Controller",
		Summary = "Keeps distance, nets moving players, then closes in",
		PreferredDistance = 9,
		Aggression = 0.75,
		TargetWeights = { Threat = 0.4, Proximity = 0.6, LowHealth = 0.3, Moving = 1.6, Equipment = 0, Exposed = 0.3 },
		MaxChaseDistance = 160,
		CircleTendency = 0.5,
		DriftChangeInterval = 2.5,
		RetreatAfterAttack = 0.6,
		BlockChance = 0,
		GuardSeconds = 0,
		ShieldBashChance = 0,
		BlockPierce = 0,
		RoarChance = 0,
		AvoidHeavyShields = false,
		AvoidSlotsUntilAbilityUsed = true,
		YieldToHeavies = true,
		ExposedAfterMiss = 0,
	}),

	-- Defensive elite: guards against predictable fronts, picks threats/well-equipped players,
	-- bashes blockers, and is exposed after a missed heavy attack.
	Elite = profile({
		Id = "Elite",
		Summary = "Guards, picks dangerous or well-equipped players, bashes blockers",
		PreferredDistance = 0,
		Aggression = 0.6,
		TargetWeights = { Threat = 1.2, Proximity = 0.8, LowHealth = 0, Moving = 0, Equipment = 1.5, Exposed = 0 },
		MaxChaseDistance = 160,
		CircleTendency = 0.15,
		DriftChangeInterval = 5,
		RetreatAfterAttack = 0,
		BlockChance = 0,
		GuardSeconds = 1.6,
		ShieldBashChance = 0.5,
		BlockPierce = 0.3,
		RoarChance = 0,
		AvoidHeavyShields = false,
		AvoidSlotsUntilAbilityUsed = false,
		YieldToHeavies = false,
		ExposedAfterMiss = 1.2,
	}),
}

return table.freeze(ZombieAIProfiles)
