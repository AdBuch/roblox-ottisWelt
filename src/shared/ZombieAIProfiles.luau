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

-- Behaviour changes by condition (ZombieDamageStateService): Healthy uses the base values, Wounded
-- below 65 % and Critical below 30 % health apply these modifiers on top.
export type ConditionMods = {
	AggressionAdd: number,
	BlockMultiplier: number,
	CooldownMultiplier: number, -- attack cooldown
	SpeedMultiplier: number,
	RetreatAdd: number, -- extra seconds of backing off after an attack
	BashChanceAdd: number,
	NetCooldownMultiplier: number,
	PreferredDistanceAdd: number,
	AimErrorMultiplier: number, -- archers
	FireCooldownMultiplier: number, -- archers
	BurstSeconds: number, -- > 0: moves in short bursts ...
	RestSeconds: number, -- ... followed by rests this long
	HeavySwingChance: number, -- slow, very visible, harder last swing
	ComboChance: number, -- chance of a quick second strike right after an attack
	AvoidMelee: boolean, -- keeps away and only fights when cornered
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
	Wounded: ConditionMods,
	Critical: ConditionMods,
}

local function profile(def: ZombieAIProfile): ZombieAIProfile
	return table.freeze(def) :: any
end

-- Condition modifiers: anything not given stays neutral.
local function mods(overrides: { [string]: any }): ConditionMods
	local base: { [string]: any } = {
		AggressionAdd = 0,
		BlockMultiplier = 1,
		CooldownMultiplier = 1,
		SpeedMultiplier = 1,
		RetreatAdd = 0,
		BashChanceAdd = 0,
		NetCooldownMultiplier = 1,
		PreferredDistanceAdd = 0,
		AimErrorMultiplier = 1,
		FireCooldownMultiplier = 1,
		BurstSeconds = 0,
		RestSeconds = 0,
		HeavySwingChance = 0,
		ComboChance = 0,
		AvoidMelee = false,
	}
	for key, value in overrides do
		base[key] = value
	end
	return table.freeze(base) :: any
end

local ZombieAIProfiles: { [string]: ZombieAIProfile } = {
	-- Disciplined basic fighter: direct, nearest player, occasional shield block, keeps formation.
	Disciplined = profile({
		Id = "Disciplined",
		Summary = "Approaches directly, blocks occasionally, keeps formation",
		PreferredDistance = 0,
		Aggression = 0.8,
		TargetWeights = { Threat = 0.6, Proximity = 1.4, LowHealth = 0.2, Moving = 0, Equipment = 0, Exposed = 0.2 },
		MaxChaseDistance = 90,
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
		-- Wounded: blocks less, attacks more. Critical: slower, desperate short combinations.
		Wounded = mods({ AggressionAdd = 0.15, BlockMultiplier = 0.4, CooldownMultiplier = 0.85 }),
		Critical = mods({ AggressionAdd = 0.2, BlockMultiplier = 0, SpeedMultiplier = 0.7, ComboChance = 0.45 }),
	}),

	-- Impatient skirmisher: circles, changes direction, hunts low-health/exposed players, hit and run.
	Skirmisher = profile({
		Id = "Skirmisher",
		Summary = "Circles, hunts weak or exposed players, retreats after attacking",
		PreferredDistance = 0,
		Aggression = 0.9,
		TargetWeights = { Threat = 0.2, Proximity = 0.8, LowHealth = 1.6, Moving = 0.2, Equipment = 0, Exposed = 1.2 },
		MaxChaseDistance = 90,
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
		-- Wounded: more aggressive. Critical: fast in short bursts, then rests longer.
		Wounded = mods({ AggressionAdd = 0.1, RetreatAdd = -0.7, CooldownMultiplier = 0.8 }),
		Critical = mods({ BurstSeconds = 1.4, RestSeconds = 1.6, SpeedMultiplier = 1.1, RetreatAdd = -0.4 }),
	}),

	-- Slow aggressive tank: punishes damage dealers nearby, breaks blocks, roars, won't chase far.
	Tank = profile({
		Id = "Tank",
		Summary = "Targets nearby damage dealers, breaks blocks, roars before heavy hits",
		PreferredDistance = 0,
		Aggression = 0.7,
		TargetWeights = { Threat = 1.6, Proximity = 1.6, LowHealth = 0, Moving = 0, Equipment = 0, Exposed = 0 },
		MaxChaseDistance = 90,
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
		-- Wounded: enraged, attacks more often. Critical: much slower, dangerous last heavy swings.
		Wounded = mods({ AggressionAdd = 0.2, CooldownMultiplier = 0.7, SpeedMultiplier = 1.1 }),
		Critical = mods({ SpeedMultiplier = 0.6, CooldownMultiplier = 1.2, HeavySwingChance = 0.6 }),
	}),

	-- Tactical controller: keeps medium range, nets moving players first, then closes in.
	Controller = profile({
		Id = "Controller",
		Summary = "Keeps distance, nets moving players, then closes in",
		PreferredDistance = 9,
		Aggression = 0.75,
		TargetWeights = { Threat = 0.4, Proximity = 0.6, LowHealth = 0.3, Moving = 1.6, Equipment = 0, Exposed = 0.3 },
		MaxChaseDistance = 90,
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
		-- Wounded: throws the net sooner. Critical: retreats more and avoids direct fighting.
		Wounded = mods({ NetCooldownMultiplier = 0.6, PreferredDistanceAdd = 2 }),
		Critical = mods({ NetCooldownMultiplier = 0.7, PreferredDistanceAdd = 6, RetreatAdd = 1.2, AvoidMelee = true, AggressionAdd = -0.25 }),
	}),

	-- Defensive elite: guards against predictable fronts, picks threats/well-equipped players,
	-- bashes blockers, and is exposed after a missed heavy attack.
	Elite = profile({
		Id = "Elite",
		Summary = "Guards, picks dangerous or well-equipped players, bashes blockers",
		PreferredDistance = 0,
		Aggression = 0.6,
		TargetWeights = { Threat = 1.2, Proximity = 0.8, LowHealth = 0, Moving = 0, Equipment = 1.5, Exposed = 0 },
		MaxChaseDistance = 90,
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
		-- Wounded: shield-bashes more. Critical: loses its discipline, aggressive combinations.
		Wounded = mods({ BashChanceAdd = 0.3 }),
		Critical = mods({ BlockMultiplier = 0, AggressionAdd = 0.3, ComboChance = 0.55, CooldownMultiplier = 0.8 }),
	}),

	-- Ranged support (Undead Sagittarius, ZombieArcherAI): keeps 55-85 studs, seeks clear firing
	-- positions, relocates when approached, weak strike only when cornered.
	Marksman = profile({
		Id = "Marksman",
		Summary = "Keeps its distance, draws its bow, relocates when approached",
		PreferredDistance = 70,
		Aggression = 0.85,
		TargetWeights = { Threat = 0.6, Proximity = 0.6, LowHealth = 0.4, Moving = 0, Equipment = 0, Exposed = 1.0 },
		MaxChaseDistance = 140,
		CircleTendency = 0.4,
		DriftChangeInterval = 3,
		RetreatAfterAttack = 2,
		BlockChance = 0,
		GuardSeconds = 0,
		ShieldBashChance = 0,
		BlockPierce = 0,
		RoarChance = 0,
		AvoidHeavyShields = false,
		AvoidSlotsUntilAbilityUsed = false,
		YieldToHeavies = true,
		ExposedAfterMiss = 0,
		-- Wounded: fires faster but less accurately. Critical: slow, inaccurate, may strike up close.
		Wounded = mods({ FireCooldownMultiplier = 0.75, AimErrorMultiplier = 1.8 }),
		Critical = mods({ SpeedMultiplier = 0.6, AimErrorMultiplier = 2.6, FireCooldownMultiplier = 1.1, AggressionAdd = 0.1 }),
	}),
}

return table.freeze(ZombieAIProfiles)
