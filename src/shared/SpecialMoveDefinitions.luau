--!strict
-- Every weapon action (basic attack + two specials) as data. The server's SpecialMoveService
-- executes them generically by Kind; the client only reads names/cooldowns for the HUD.
--
-- Kinds:
--   Melee       wind-up, then hits the best target(s) in Range/ArcDot (Hits = multi-strike)
--   Projectile  arrows (ProjectileCount, Spread, Pierce) stopped by solid geometry
--   Net         short net projectile that slows, then an automatic follow-up thrust
--   Dash        short dash toward the aim direction (never through walls), then a strike
-- PvP: damage x PvPMultiplier, at most PvPMaxTargets players, and never more than
-- CombatConfig.PvPMaxDamageFraction of a player's max health per hit.

export type MoveKind = "Melee" | "Projectile" | "Net" | "Dash"
export type Anim = "Slash" | "Thrust" | "Overhead" | "Spin" | "Draw" | "Flurry" | "Bash"

export type HitStep = { Delay: number, Multiplier: number }

export type MoveDefinition = {
	Id: string,
	Name: string,
	Kind: MoveKind,
	Anim: Anim,
	Cooldown: number, -- seconds before this action can be used again
	Duration: number, -- the player can't start another action during this time
	WindUp: number, -- visible telegraph before the first hit
	Damage: number,
	Range: number,
	ArcDot: number, -- target must satisfy dot(look, toTarget) >= ArcDot; -1 = full circle
	MaxTargets: number,
	PvPMaxTargets: number,
	PvPMultiplier: number,
	Stagger: number,
	Knockback: number,
	Lunge: number?, -- short forward movement before the hit (studs)
	Hits: { HitStep }?, -- multi-hit; later strikes only happen while a target is in range
	ExecuteThreshold: number?, -- zombies below this health share take ExecuteMultiplier damage
	ExecuteMultiplier: number?,
	ShieldBash: boolean?, -- stagger/knockback scale with the equipped shield's BashMultiplier
	ProjectileCount: number?,
	Spread: number?, -- degrees between projectiles
	ProjectileSpeed: number?,
	Pierce: number?, -- how many targets one projectile may pass through
	SlowFactor: number?,
	SlowSeconds: number?,
	FollowUpDamage: number?,
	FollowUpRange: number?,
	DashDistance: number?,
}

local function move(def: MoveDefinition): MoveDefinition
	return table.freeze(def) :: any
end

local Moves: { [string]: MoveDefinition } = {
	------------------------------------------------------------------ Rusty Gladius
	Gladius_Basic = move({
		Id = "Gladius_Basic", Name = "Gladius Slash", Kind = "Melee", Anim = "Slash",
		Cooldown = 0.55, Duration = 0.45, WindUp = 0.08, Damage = 18, Range = 7, ArcDot = 0.3,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.75, Stagger = 0.1, Knockback = 8,
	}),
	QuickThrust = move({
		Id = "QuickThrust", Name = "QUICK THRUST", Kind = "Melee", Anim = "Thrust",
		Cooldown = 4, Duration = 0.5, WindUp = 0.12, Damage = 22, Range = 8.5, ArcDot = 0.6,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.7, Stagger = 0.25, Knockback = 10, Lunge = 3,
	}),
	ShieldCounter = move({
		Id = "ShieldCounter", Name = "SHIELD COUNTER", Kind = "Melee", Anim = "Bash",
		Cooldown = 7, Duration = 0.55, WindUp = 0.15, Damage = 16, Range = 6, ArcDot = 0.2,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.7, Stagger = 0.8, Knockback = 22, ShieldBash = true,
	}),

	------------------------------------------------------------------ Legion Sword
	Legion_Basic = move({
		Id = "Legion_Basic", Name = "Legion Slash", Kind = "Melee", Anim = "Slash",
		Cooldown = 0.65, Duration = 0.5, WindUp = 0.1, Damage = 28, Range = 7.5, ArcDot = 0.3,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.65, Stagger = 0.15, Knockback = 10,
	}),
	LegionCombo = move({
		Id = "LegionCombo", Name = "LEGION COMBO", Kind = "Melee", Anim = "Flurry",
		Cooldown = 6, Duration = 0.9, WindUp = 0.1, Damage = 28, Range = 7.5, ArcDot = 0.3,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.55, Stagger = 0.15, Knockback = 6,
		Hits = { { Delay = 0, Multiplier = 0.6 }, { Delay = 0.25, Multiplier = 0.6 }, { Delay = 0.5, Multiplier = 0.9 } },
	}),
	RisingSlash = move({
		Id = "RisingSlash", Name = "RISING SLASH", Kind = "Melee", Anim = "Overhead",
		Cooldown = 8, Duration = 0.65, WindUp = 0.2, Damage = 34, Range = 7, ArcDot = 0.3,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.6, Stagger = 0.8, Knockback = 16,
	}),

	------------------------------------------------------------------ Hunter Bow
	Bow_Basic = move({
		Id = "Bow_Basic", Name = "Arrow", Kind = "Projectile", Anim = "Draw",
		Cooldown = 0.9, Duration = 0.6, WindUp = 0.15, Damage = 24, Range = 90, ArcDot = -1,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.7, Stagger = 0.1, Knockback = 6,
		ProjectileCount = 1, ProjectileSpeed = 110, Pierce = 1,
	}),
	TripleShot = move({
		Id = "TripleShot", Name = "TRIPLE SHOT", Kind = "Projectile", Anim = "Draw",
		Cooldown = 7, Duration = 0.7, WindUp = 0.25, Damage = 16, Range = 80, ArcDot = -1,
		MaxTargets = 3, PvPMaxTargets = 2, PvPMultiplier = 0.6, Stagger = 0.1, Knockback = 6,
		ProjectileCount = 3, Spread = 9, ProjectileSpeed = 110, Pierce = 1,
	}),
	PiercingArrow = move({
		Id = "PiercingArrow", Name = "PIERCING ARROW", Kind = "Projectile", Anim = "Draw",
		Cooldown = 9, Duration = 0.8, WindUp = 0.4, Damage = 34, Range = 100, ArcDot = -1,
		MaxTargets = 3, PvPMaxTargets = 2, PvPMultiplier = 0.6, Stagger = 0.3, Knockback = 10,
		ProjectileCount = 1, ProjectileSpeed = 160, Pierce = 3,
	}),

	------------------------------------------------------------------ Gladiator Morning Star
	MorningStar_Basic = move({
		Id = "MorningStar_Basic", Name = "Mace Swing", Kind = "Melee", Anim = "Slash",
		Cooldown = 1.15, Duration = 0.9, WindUp = 0.25, Damage = 40, Range = 8, ArcDot = 0.0,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.55, Stagger = 0.45, Knockback = 18,
	}),
	HeavyCrush = move({
		Id = "HeavyCrush", Name = "HEAVY CRUSH", Kind = "Melee", Anim = "Overhead",
		Cooldown = 9, Duration = 1.0, WindUp = 0.45, Damage = 55, Range = 8, ArcDot = 0.3,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.5, Stagger = 0.9, Knockback = 24,
	}),
	ChainSweep = move({
		Id = "ChainSweep", Name = "CHAIN SWEEP", Kind = "Melee", Anim = "Spin",
		Cooldown = 11, Duration = 0.9, WindUp = 0.35, Damage = 30, Range = 9, ArcDot = -1,
		MaxTargets = 3, PvPMaxTargets = 2, PvPMultiplier = 0.5, Stagger = 0.4, Knockback = 20,
	}),

	------------------------------------------------------------------ Gladiator Trident
	Trident_Basic = move({
		Id = "Trident_Basic", Name = "Trident Thrust", Kind = "Melee", Anim = "Thrust",
		Cooldown = 0.75, Duration = 0.55, WindUp = 0.12, Damage = 24, Range = 10, ArcDot = 0.55,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.65, Stagger = 0.15, Knockback = 10,
	}),
	TridentRush = move({
		Id = "TridentRush", Name = "TRIDENT RUSH", Kind = "Melee", Anim = "Thrust",
		Cooldown = 6, Duration = 0.7, WindUp = 0.1, Damage = 24, Range = 10, ArcDot = 0.55,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.55, Stagger = 0.2, Knockback = 10, Lunge = 3,
		Hits = { { Delay = 0, Multiplier = 1.0 }, { Delay = 0.25, Multiplier = 1.25 } },
	}),
	NetAndStrike = move({
		Id = "NetAndStrike", Name = "NET AND STRIKE", Kind = "Net", Anim = "Thrust",
		Cooldown = 11, Duration = 0.9, WindUp = 0.2, Damage = 0, Range = 14, ArcDot = 0.5,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.6, Stagger = 0.3, Knockback = 8,
		SlowFactor = 0.6, SlowSeconds = 1.5, FollowUpDamage = 26, FollowUpRange = 10,
	}),

	------------------------------------------------------------------ Hoplite Spear
	Hoplite_Basic = move({
		Id = "Hoplite_Basic", Name = "Spear Thrust", Kind = "Melee", Anim = "Thrust",
		Cooldown = 0.85, Duration = 0.6, WindUp = 0.15, Damage = 27, Range = 12, ArcDot = 0.6,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.6, Stagger = 0.15, Knockback = 12,
	}),
	PhalanxThrust = move({
		Id = "PhalanxThrust", Name = "PHALANX THRUST", Kind = "Melee", Anim = "Thrust",
		Cooldown = 7, Duration = 0.75, WindUp = 0.3, Damage = 36, Range = 13, ArcDot = 0.7,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.55, Stagger = 0.5, Knockback = 30,
	}),
	SpearSweep = move({
		Id = "SpearSweep", Name = "SPEAR SWEEP", Kind = "Melee", Anim = "Spin",
		Cooldown = 12, Duration = 0.8, WindUp = 0.3, Damage = 22, Range = 9, ArcDot = -1,
		MaxTargets = 3, PvPMaxTargets = 2, PvPMultiplier = 0.55, Stagger = 0.4, Knockback = 14,
	}),

	------------------------------------------------------------------ Twin Arena Daggers
	Daggers_Basic = move({
		Id = "Daggers_Basic", Name = "Twin Strike", Kind = "Melee", Anim = "Flurry",
		Cooldown = 0.35, Duration = 0.3, WindUp = 0.05, Damage = 14, Range = 5.5, ArcDot = 0.4,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.7, Stagger = 0.05, Knockback = 4,
	}),
	ViperFlurry = move({
		Id = "ViperFlurry", Name = "VIPER FLURRY", Kind = "Melee", Anim = "Flurry",
		Cooldown = 8, Duration = 0.8, WindUp = 0.08, Damage = 14, Range = 6, ArcDot = 0.3,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.6, Stagger = 0.05, Knockback = 3,
		Hits = {
			{ Delay = 0, Multiplier = 0.8 },
			{ Delay = 0.15, Multiplier = 0.8 },
			{ Delay = 0.3, Multiplier = 0.8 },
			{ Delay = 0.45, Multiplier = 0.8 },
		},
	}),
	ShadowStep = move({
		Id = "ShadowStep", Name = "SHADOW STEP", Kind = "Dash", Anim = "Thrust",
		Cooldown = 10, Duration = 0.6, WindUp = 0.05, Damage = 24, Range = 6, ArcDot = 0.2,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.6, Stagger = 0.3, Knockback = 8, DashDistance = 10,
	}),

	------------------------------------------------------------------ Arena Battle Axe
	Axe_Basic = move({
		Id = "Axe_Basic", Name = "Axe Cleave", Kind = "Melee", Anim = "Slash",
		Cooldown = 1.3, Duration = 1.0, WindUp = 0.3, Damage = 44, Range = 8, ArcDot = 0.25,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.5, Stagger = 0.4, Knockback = 16,
	}),
	ExecutionArc = move({
		Id = "ExecutionArc", Name = "EXECUTION ARC", Kind = "Melee", Anim = "Overhead",
		Cooldown = 9, Duration = 1.1, WindUp = 0.5, Damage = 50, Range = 8, ArcDot = 0.35,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.5, Stagger = 0.7, Knockback = 18,
		ExecuteThreshold = 0.3, ExecuteMultiplier = 2,
	}),
	Whirlwind = move({
		Id = "Whirlwind", Name = "WHIRLWIND", Kind = "Melee", Anim = "Spin",
		Cooldown = 14, Duration = 1.0, WindUp = 0.35, Damage = 32, Range = 8.5, ArcDot = -1,
		MaxTargets = 4, PvPMaxTargets = 3, PvPMultiplier = 0.4, Stagger = 0.4, Knockback = 18,
	}),
}

return table.freeze(Moves)
