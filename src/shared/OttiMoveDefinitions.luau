--!strict
-- Otti's attacks as data. BossAttackService runs them on the server (wind-up -> active window ->
-- recovery, range/arc/height/line-of-sight checks, one hit per target per hit phase); the client
-- animator reads the same timings, so poses and validated hit volumes stay in sync.
--
-- Kinds:
--   Melee      sword/shield strike in an arc in front (Steps = multi-step combination)
--   TailSweep  the body turns `SweepDegrees` during the active window; the tail volume (Radius)
--              hits players inside the swept sector who are not airborne (jumpable)
--   TailSlam   ground marker during the wind-up; direct + shockwave damage at impact
--   Bite       low lunge; a facing shield stops it completely; a miss adds MissRecovery
--   Grapple    grab -> controlled throw (BossGrappleService)
--   RiverDash  curved four-legged run; contact damage only during the active window
--   Roar       battle cry: no damage, crowd reaction

export type MoveKind = "Melee" | "TailSweep" | "TailSlam" | "Bite" | "Grapple" | "RiverDash" | "Roar"
export type Stance = "Biped" | "Quad" | "Any"

export type MoveStep = {
	Pose: string, -- client pose key
	WindUp: number,
	Active: number,
	Damage: number,
	Range: number,
	ArcDot: number,
}

export type FollowUp = { Move: string, Chance: number, MinPhase: number, OnlyIfHit: boolean? }

export type OttiMove = {
	Id: string,
	Name: string,
	Kind: MoveKind,
	Stance: Stance,
	WindUp: number,
	Active: number,
	Recovery: number,
	Cooldown: number,
	StartRange: number, -- the AI starts it when the target is this close
	MinRange: number?,
	Damage: number,
	Range: number, -- validated reach at the active moment (melee/bite)
	ArcDot: number, -- -1 = full circle
	Radius: number?, -- tail volume / shockwave radius
	DirectRadius: number?,
	DirectDamage: number?,
	SweepDegrees: number?,
	Knockback: number,
	KnockbackIfBlocked: boolean?, -- tail sweeps push you back even through a shield
	KnockdownSeconds: number?,
	PlayerSlowSeconds: number?, -- strong stagger (shield bash)
	Blockable: boolean,
	BlockStops: boolean?, -- a facing shield stops all damage (bite)
	BlockPierce: number?,
	Jumpable: boolean?,
	Lunge: number?,
	MissRecovery: number?,
	MultiTarget: boolean?,
	Warning: string?, -- major attacks show a HUD warning
	Steps: { MoveStep }?,
	FollowUp: FollowUp?,
}

local function move(def: OttiMove): OttiMove
	return table.freeze(def) :: any
end

local Moves: { [string]: OttiMove } = {
	GladiusSlash = move({
		Id = "GladiusSlash", Name = "GLADIUS SLASH", Kind = "Melee", Stance = "Biped",
		WindUp = 0.45, Active = 0.15, Recovery = 0.45, Cooldown = 2.2, StartRange = 7.5,
		Damage = 14, Range = 7.5, ArcDot = 0.4, Knockback = 10, Blockable = true,
	}),
	GladiatorCombination = move({
		Id = "GladiatorCombination", Name = "GLADIATOR COMBINATION", Kind = "Melee", Stance = "Biped",
		WindUp = 0, Active = 0, Recovery = 0.6, Cooldown = 6, StartRange = 7.5,
		Damage = 0, Range = 7.5, ArcDot = 0.4, Knockback = 8, Blockable = true,
		Steps = {
			{ Pose = "Feint", WindUp = 0.35, Active = 0, Damage = 0, Range = 0, ArcDot = 1 },
			{ Pose = "SlashH", WindUp = 0.3, Active = 0.12, Damage = 8, Range = 7.5, ArcDot = 0.3 },
			{ Pose = "SlashH2", WindUp = 0.25, Active = 0.12, Damage = 10, Range = 7.5, ArcDot = 0.3 },
			{ Pose = "Thrust", WindUp = 0.3, Active = 0.12, Damage = 14, Range = 9.5, ArcDot = 0.75 },
		},
	}),
	ShieldBash = move({
		Id = "ShieldBash", Name = "SHIELD BASH", Kind = "Melee", Stance = "Biped",
		WindUp = 0.4, Active = 0.15, Recovery = 0.5, Cooldown = 4.5, StartRange = 6,
		Damage = 8, Range = 6, ArcDot = 0.5, Knockback = 36, KnockbackIfBlocked = true, PlayerSlowSeconds = 0.6,
		Blockable = true, BlockPierce = 0.5,
		FollowUp = { Move = "TailSweep", Chance = 0.6, MinPhase = 3 }, -- Phase 3: bash into a tail sweep
	}),
	TailSweep = move({
		Id = "TailSweep", Name = "BROAD TAIL SWEEP", Kind = "TailSweep", Stance = "Any",
		WindUp = 0.9, Active = 0.5, Recovery = 0.7, Cooldown = 7, StartRange = 9,
		Damage = 12, Range = 0, ArcDot = -1, Radius = 10.5, SweepDegrees = 360,
		Knockback = 34, KnockbackIfBlocked = true, Blockable = true, Jumpable = true, MultiTarget = true,
		Warning = "TAIL SWEEP — JUMP!",
	}),
	TailTrip = move({
		Id = "TailTrip", Name = "TAIL TRIP", Kind = "TailSweep", Stance = "Quad",
		WindUp = 0.6, Active = 0.35, Recovery = 0.6, Cooldown = 8, StartRange = 8.5,
		Damage = 6, Range = 0, ArcDot = -1, Radius = 9.5, SweepDegrees = 220,
		Knockback = 8, KnockdownSeconds = 1.0, Blockable = false, Jumpable = true, MultiTarget = true,
		Warning = "TAIL TRIP — JUMP!",
	}),
	TailSlam = move({
		Id = "TailSlam", Name = "TAIL SLAM", Kind = "TailSlam", Stance = "Biped",
		WindUp = 1.0, Active = 0.12, Recovery = 0.8, Cooldown = 9, StartRange = 11,
		Damage = 10, Range = 7, ArcDot = -1, Radius = 10, DirectRadius = 3.5, DirectDamage = 20,
		Knockback = 20, Blockable = true, MultiTarget = true,
		Warning = "TAIL SLAM — MOVE!",
	}),
	OtterBite = move({
		Id = "OtterBite", Name = "OTTER BITE", Kind = "Bite", Stance = "Quad",
		WindUp = 0.55, Active = 0.2, Recovery = 0.6, Cooldown = 5, StartRange = 7, MinRange = 2,
		Damage = 16, Range = 4.5, ArcDot = 0.55, Knockback = 6, Blockable = true, BlockStops = true,
		Lunge = 5.5, MissRecovery = 0.7,
		FollowUp = { Move = "GrappleThrow", Chance = 0.35, MinPhase = 2, OnlyIfHit = true }, -- bite-and-throw
	}),
	GrappleThrow = move({
		Id = "GrappleThrow", Name = "GRAPPLE AND ARENA THROW", Kind = "Grapple", Stance = "Biped",
		WindUp = 0.7, Active = 0.25, Recovery = 0.8, Cooldown = 14, StartRange = 5.5,
		Damage = 18, Range = 5.5, ArcDot = 0.5, Knockback = 0, Blockable = false,
		Warning = "GRAPPLE — DODGE!",
	}),
	RiverDash = move({
		Id = "RiverDash", Name = "RIVER DASH", Kind = "RiverDash", Stance = "Quad",
		WindUp = 0.35, Active = 1.3, Recovery = 0.4, Cooldown = 7, StartRange = 40, MinRange = 10,
		Damage = 8, Range = 0, ArcDot = -1, Radius = 3.6, Knockback = 18, Blockable = true, MultiTarget = true,
		FollowUp = { Move = "TailTrip", Chance = 0.45, MinPhase = 2 },
	}),
	ShieldTailCounter = move({
		Id = "ShieldTailCounter", Name = "SHIELD-AND-TAIL COUNTER", Kind = "TailSweep", Stance = "Biped",
		WindUp = 0.25, Active = 0.3, Recovery = 0.6, Cooldown = 9, StartRange = 9,
		Damage = 11, Range = 0, ArcDot = -1, Radius = 9, SweepDegrees = 200,
		Knockback = 28, KnockbackIfBlocked = true, Blockable = true, Jumpable = true, MultiTarget = true,
	}),
	BattleCry = move({
		Id = "BattleCry", Name = "BATTLE CRY", Kind = "Roar", Stance = "Biped",
		WindUp = 0.3, Active = 0.9, Recovery = 0.3, Cooldown = 18, StartRange = 40,
		Damage = 0, Range = 0, ArcDot = -1, Knockback = 0, Blockable = false,
	}),
}

return table.freeze(Moves)
