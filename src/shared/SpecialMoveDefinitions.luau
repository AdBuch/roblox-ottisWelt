--!strict
-- Every player move as data: basic attacks (instant, no charging), one aerial attack per weapon
-- (Jump -> Attack) and the combination moves (ComboDefinitions: Attack / Block / Jump inputs
-- resolved with Execute). The server's SpecialMoveService executes them generically by Kind;
-- the client only reads names for the HUD and the info panel. Nothing here is ever charged:
-- wind-ups are short fixed telegraphs, cooldowns only start after a move ran.
--
-- Kinds:
--   Melee       wind-up, then one or more hit steps (Hits) in Range/ArcDot; steps may carry their
--               own animation, lunge, range, arc and spin (full circle)
--   Projectile  arrows (count, spread, pierce) stopped by solid geometry; falloff beyond 100 studs
--   Aerial      needs a real jump: optional air hit, fast controlled descent, landing strike with
--               an optional small shockwave, then a landing recovery based on weapon weight.
--               Combo aerials started on the ground first perform one controlled hop.
--   Volley      ARROW RAIN: a marked circle, arrows fall into it, impacts checked from above
-- PvP: damage x PvPMultiplier, at most PvPMaxTargets players, every hit capped by
-- PvPBalanceConfig (no one-hit eliminations), whole-combo damage per target capped too.

export type MoveKind = "Melee" | "Projectile" | "Aerial" | "Volley"
export type Anim =
	"Slash"
	| "Thrust"
	| "Overhead"
	| "Spin"
	| "Draw"
	| "Flurry"
	| "Bash"
	| "Low"
	| "Backhand"
	| "Rise"
	| "Dive"
	| "Guard"
	| "SlashRL" -- right-to-left diagonal (upper right -> lower left)
	| "SlashLR" -- left-to-right horizontal
	| "RetreatCut" -- step back + defensive diagonal
	| "ParryCounter" -- turn out of a deflection into a short direct thrust
	| "Wide" -- wide horizontal sweep (several enemies)
	| "Cross" -- crossing dagger cut
	| "AirSpinL"
	| "AirSpinR"
	| "SlideCut"
	| "SlideThrust"
	| "SlideRise"
	| "SlideCross"
	| "SlideReaper"
	| "SlideShot"
	| "Ultimate"

export type Height = "Low" | "Mid" | "High"

export type HitStep = {
	Delay: number, -- seconds after the wind-up
	Multiplier: number, -- of Damage (0 = no hit, animation only)
	Anim: Anim?,
	Lunge: number?, -- short forward step (client moves its own character, never through walls)
	Range: number?,
	ArcDot: number?,
	Spin: boolean?, -- full circle around the player
	Sweep: { number }?, -- { fromDegrees, toDegrees } relative to the aim (+ = right): the validated
	-- volume travels the same path as the animation
	Line: number?, -- narrow thrust: half width in studs instead of an arc
	Height: Height?,
}

export type MoveDefinition = {
	Id: string,
	Name: string,
	Kind: MoveKind,
	Anim: Anim,
	Cooldown: number, -- starts after the move executes
	Duration: number, -- the player can't start another action during this time
	WindUp: number, -- short fixed telegraph (never held / charged)
	Damage: number,
	Range: number,
	ArcDot: number, -- dot(look, toTarget) >= ArcDot; -1 = full circle
	MaxTargets: number,
	PvPMaxTargets: number,
	PvPMultiplier: number,
	Stagger: number,
	Knockback: number,
	Lunge: number?,
	Hits: { HitStep }?,
	ExecuteThreshold: number?,
	ExecuteMultiplier: number?,
	ShieldBash: boolean?,
	-- Combos
	CounterWindow: number?, -- the first seconds reduce incoming damage (counter stance) - never the whole move
	GuardBreak: boolean?, -- breaks a raised guard (stagger) instead of being stopped by it
	BasicMultiplier: number?, -- universal combos: damage = equipped basic damage x this
	Advanced: boolean?, -- a named weapon combo (crowd/Otti react)
	-- Projectiles
	ProjectileCount: number?,
	Spread: number?,
	ProjectileSpeed: number?,
	Pierce: number?,
	ExtraSpread: number?, -- air shot inaccuracy (degrees)
	-- Aerial
	AirHit: number?, -- multiplier of an extra strike while still in the air (0/nil = none)
	Forward: number?, -- studs of controlled forward travel during the descent
	Shockwave: number?, -- landing shockwave radius (0/nil = none)
	ShockwaveMultiplier: number?,
	LandingRecovery: number?,
	MissRecovery: number?, -- extra recovery when the landing strike hits nothing
	-- Volley
	Radius: number?,
	-- Hit geometry and presentation (basic chains, slides, specials)
	Sweep: { number }?, -- see HitStep.Sweep
	Line: number?,
	Height: Height?,
	ActiveTime: number?, -- seconds the sweep needs to travel (validated in slices along the path)
	Slot: string?, -- chain or gesture slot (Momentum variety): SlashRL, Thrust, Overhead, ...
	RequiresAir: boolean?, -- aerial gesture attacks (one per jump)
	Impact: number?, -- heavy ground impact radius (sand burst + small area hit)
	ImpactMultiplier: number?,
	Ultimate: boolean?,
}

local function move(def: MoveDefinition): MoveDefinition
	return table.freeze(def) :: any
end

local function hits(list: { HitStep }): { HitStep }
	return table.freeze(list) :: any
end

local Moves: { [string]: MoveDefinition } = {
	------------------------------------------------------------------ basic attacks (instant)
	Gladius_Basic = move({
		Id = "Gladius_Basic", Name = "Gladius Slash", Kind = "Melee", Anim = "Slash",
		Cooldown = 0.55, Duration = 0.45, WindUp = 0.08, Damage = 18, Range = 7, ArcDot = 0.3,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.75, Stagger = 0.1, Knockback = 8,
	}),
	Legion_Basic = move({
		Id = "Legion_Basic", Name = "Legion Slash", Kind = "Melee", Anim = "Slash",
		Cooldown = 0.65, Duration = 0.5, WindUp = 0.1, Damage = 28, Range = 7.5, ArcDot = 0.3,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.65, Stagger = 0.15, Knockback = 10,
	}),
	Bow_Basic = move({
		Id = "Bow_Basic", Name = "Arrow", Kind = "Projectile", Anim = "Draw",
		Cooldown = 0.9, Duration = 0.6, WindUp = 0.15, Damage = 24, Range = 150, ArcDot = -1,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.7, Stagger = 0.1, Knockback = 6,
		ProjectileCount = 1, ProjectileSpeed = 145, Pierce = 1,
	}),
	MorningStar_Basic = move({
		Id = "MorningStar_Basic", Name = "Mace Swing", Kind = "Melee", Anim = "Slash",
		Cooldown = 1.15, Duration = 0.9, WindUp = 0.25, Damage = 40, Range = 8, ArcDot = 0.0,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.55, Stagger = 0.45, Knockback = 18,
	}),
	Trident_Basic = move({
		Id = "Trident_Basic", Name = "Trident Thrust", Kind = "Melee", Anim = "Thrust",
		Cooldown = 0.75, Duration = 0.55, WindUp = 0.12, Damage = 24, Range = 10, ArcDot = 0.55,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.65, Stagger = 0.15, Knockback = 10,
	}),
	Hoplite_Basic = move({
		Id = "Hoplite_Basic", Name = "Spear Thrust", Kind = "Melee", Anim = "Thrust",
		Cooldown = 0.85, Duration = 0.6, WindUp = 0.15, Damage = 27, Range = 12, ArcDot = 0.6,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.6, Stagger = 0.15, Knockback = 12,
	}),
	Daggers_Basic = move({
		Id = "Daggers_Basic", Name = "Twin Strike", Kind = "Melee", Anim = "Flurry",
		Cooldown = 0.35, Duration = 0.3, WindUp = 0.05, Damage = 14, Range = 5.5, ArcDot = 0.4,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.7, Stagger = 0.05, Knockback = 4,
	}),
	Axe_Basic = move({
		Id = "Axe_Basic", Name = "Axe Cleave", Kind = "Melee", Anim = "Slash",
		Cooldown = 1.3, Duration = 1.0, WindUp = 0.3, Damage = 44, Range = 8, ArcDot = 0.25,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.5, Stagger = 0.4, Knockback = 16,
	}),

	------------------------------------------------------------------ aerial attacks (Jump -> Attack)
	Gladius_Aerial = move({
		Id = "Gladius_Aerial", Name = "FALLING SLASH", Kind = "Aerial", Anim = "Dive",
		Cooldown = 0.6, Duration = 0.5, WindUp = 0.05, Damage = 24, Range = 7, ArcDot = 0.3,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.55, Stagger = 0.2, Knockback = 10,
		Forward = 4, LandingRecovery = 0.15,
	}),
	Legion_Aerial = move({
		Id = "Legion_Aerial", Name = "EAGLE DESCENT", Kind = "Aerial", Anim = "Overhead",
		Cooldown = 0.8, Duration = 0.6, WindUp = 0.08, Damage = 34, Range = 7.5, ArcDot = 0.3,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.5, Stagger = 0.3, Knockback = 12,
		Forward = 3, Shockwave = 6, ShockwaveMultiplier = 0.4, LandingRecovery = 0.3,
	}),
	Bow_Aerial = move({
		Id = "Bow_Aerial", Name = "AIR SHOT", Kind = "Projectile", Anim = "Draw",
		Cooldown = 0.9, Duration = 0.45, WindUp = 0.1, Damage = 22, Range = 120, ArcDot = -1,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.6, Stagger = 0.1, Knockback = 6,
		ProjectileCount = 1, ProjectileSpeed = 145, Pierce = 1, ExtraSpread = 3,
	}),
	MorningStar_Aerial = move({
		Id = "MorningStar_Aerial", Name = "FALLING COMET", Kind = "Aerial", Anim = "Overhead",
		Cooldown = 1.2, Duration = 0.8, WindUp = 0.18, Damage = 48, Range = 8, ArcDot = 0,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.45, Stagger = 0.5, Knockback = 20,
		Forward = 2, Shockwave = 7, ShockwaveMultiplier = 0.45, LandingRecovery = 0.6,
	}),
	Trident_Aerial = move({
		Id = "Trident_Aerial", Name = "DIVING TRIDENT", Kind = "Aerial", Anim = "Thrust",
		Cooldown = 0.8, Duration = 0.6, WindUp = 0.08, Damage = 30, Range = 11, ArcDot = 0.6,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.5, Stagger = 0.25, Knockback = 12,
		Forward = 6, LandingRecovery = 0.3,
	}),
	Hoplite_Aerial = move({
		Id = "Hoplite_Aerial", Name = "SKY SPEAR", Kind = "Aerial", Anim = "Thrust",
		Cooldown = 0.9, Duration = 0.65, WindUp = 0.1, Damage = 38, Range = 9, ArcDot = 0.75,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.5, Stagger = 0.3, Knockback = 12,
		Forward = 3, LandingRecovery = 0.35,
	}),
	Daggers_Aerial = move({
		Id = "Daggers_Aerial", Name = "OTTER DIVE", Kind = "Aerial", Anim = "Spin",
		Cooldown = 0.5, Duration = 0.45, WindUp = 0.04, Damage = 12, Range = 6, ArcDot = 0.2,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.6, Stagger = 0.1, Knockback = 6,
		AirHit = 1, Forward = 5, LandingRecovery = 0.1,
	}),
	Axe_Aerial = move({
		Id = "Axe_Aerial", Name = "ARENA CRASH", Kind = "Aerial", Anim = "Overhead",
		Cooldown = 1.3, Duration = 0.9, WindUp = 0.2, Damage = 52, Range = 8, ArcDot = 0.2,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.45, Stagger = 0.5, Knockback = 18,
		Forward = 2, Shockwave = 8, ShockwaveMultiplier = 0.45, LandingRecovery = 0.8, MissRecovery = 0.4,
	}),

	------------------------------------------------------------------ universal combos (any weapon)
	U_Counter = move({
		Id = "U_Counter", Name = "COUNTER COMBINATION", Kind = "Melee", Anim = "Guard",
		Cooldown = 7, Duration = 1.2, WindUp = 0.05, Damage = 0, Range = 7.5, ArcDot = 0.3,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.5, Stagger = 0.2, Knockback = 8,
		BasicMultiplier = 1, CounterWindow = 0.35,
		Hits = hits({
			{ Delay = 0.35, Multiplier = 0.55, Anim = "Low" },
			{ Delay = 0.6, Multiplier = 0.55, Anim = "Backhand" },
			{ Delay = 0.9, Multiplier = 0.9, Anim = "Thrust", Lunge = 2.5 },
		}),
	}),
	U_JumpFinisher = move({
		Id = "U_JumpFinisher", Name = "JUMP FINISHER", Kind = "Aerial", Anim = "Overhead",
		Cooldown = 8, Duration = 1.0, WindUp = 0.1, Damage = 0, Range = 7.5, ArcDot = 0.2,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.45, Stagger = 0.4, Knockback = 14,
		BasicMultiplier = 1.5, Forward = 4, Shockwave = 5, ShockwaveMultiplier = 0.4, LandingRecovery = 0.4,
	}),
	U_GuardBreak = move({
		Id = "U_GuardBreak", Name = "GUARD BREAK", Kind = "Melee", Anim = "Bash",
		Cooldown = 7, Duration = 0.9, WindUp = 0.22, Damage = 0, Range = 7, ArcDot = 0.4,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.5, Stagger = 0.8, Knockback = 18,
		BasicMultiplier = 0.6, GuardBreak = true, ShieldBash = true,
	}),
	U_ArenaSpin = move({
		Id = "U_ArenaSpin", Name = "ARENA SPIN", Kind = "Melee", Anim = "Spin",
		Cooldown = 9, Duration = 1.0, WindUp = 0.12, Damage = 0, Range = 8, ArcDot = -1,
		MaxTargets = 4, PvPMaxTargets = 2, PvPMultiplier = 0.35, Stagger = 0.3, Knockback = 14,
		BasicMultiplier = 0.9,
		Hits = hits({
			{ Delay = 0, Multiplier = 0.6, Anim = "Spin", Spin = true },
			{ Delay = 0.35, Multiplier = 0.8, Anim = "Spin", Spin = true },
		}),
	}),
	U_Rising = move({
		Id = "U_Rising", Name = "RISING ATTACK", Kind = "Aerial", Anim = "Rise",
		Cooldown = 7, Duration = 0.9, WindUp = 0.06, Damage = 0, Range = 7, ArcDot = 0.3,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.5, Stagger = 0.3, Knockback = 10,
		BasicMultiplier = 1.1, AirHit = 0.7, Forward = 2, LandingRecovery = 0.25,
	}),

	------------------------------------------------------------------ Rusty Gladius
	RebellionCombo = move({
		Id = "RebellionCombo", Name = "REBELLION COMBO", Kind = "Melee", Anim = "Guard",
		Cooldown = 8, Duration = 1.25, WindUp = 0.05, Damage = 22, Range = 7, ArcDot = 0.3,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.5, Stagger = 0.25, Knockback = 8, Advanced = true,
		CounterWindow = 0.35,
		Hits = hits({
			{ Delay = 0.35, Multiplier = 0.6, Anim = "Low" },
			{ Delay = 0.6, Multiplier = 0.6, Anim = "Backhand" },
			{ Delay = 0.8, Multiplier = 0, Anim = "Spin" }, -- shoulder turn
			{ Delay = 1.0, Multiplier = 1.2, Anim = "Thrust", Lunge = 3 },
		}),
	}),
	SandViper = move({
		Id = "SandViper", Name = "SAND VIPER", Kind = "Aerial", Anim = "Spin",
		Cooldown = 8, Duration = 0.9, WindUp = 0.06, Damage = 34, Range = 7.5, ArcDot = 0.2,
		MaxTargets = 2, PvPMaxTargets = 1, PvPMultiplier = 0.45, Stagger = 0.35, Knockback = 12, Advanced = true,
		Forward = 4, Shockwave = 4, ShockwaveMultiplier = 0.4, LandingRecovery = 0.25,
	}),

	------------------------------------------------------------------ Legion Sword
	LegionsFury = move({
		Id = "LegionsFury", Name = "LEGION'S FURY", Kind = "Melee", Anim = "Slash",
		Cooldown = 9, Duration = 1.2, WindUp = 0.08, Damage = 30, Range = 7.5, ArcDot = 0.3,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.45, Stagger = 0.25, Knockback = 10, Advanced = true,
		Hits = hits({
			{ Delay = 0, Multiplier = 0.6, Anim = "Slash" },
			{ Delay = 0.3, Multiplier = 0, Anim = "Guard" }, -- shield cover
			{ Delay = 0.6, Multiplier = 0.7, Anim = "Spin", Spin = true, Range = 7 },
			{ Delay = 0.95, Multiplier = 1.0, Anim = "Thrust", Lunge = 3 },
		}),
	}),
	EagleOfRome = move({
		Id = "EagleOfRome", Name = "EAGLE OF ROME", Kind = "Aerial", Anim = "Rise",
		Cooldown = 9, Duration = 1.0, WindUp = 0.08, Damage = 38, Range = 7.5, ArcDot = 0.3,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.45, Stagger = 0.4, Knockback = 14, Advanced = true,
		AirHit = 0.6, Forward = 3, Shockwave = 5, ShockwaveMultiplier = 0.35, LandingRecovery = 0.35,
	}),

	------------------------------------------------------------------ Hunter Bow
	ArrowRain = move({
		Id = "ArrowRain", Name = "ARROW RAIN", Kind = "Volley", Anim = "Draw",
		Cooldown = 10, Duration = 0.8, WindUp = 0.25, Damage = 18, Range = 60, ArcDot = -1,
		MaxTargets = 4, PvPMaxTargets = 2, PvPMultiplier = 0.5, Stagger = 0.15, Knockback = 4, Advanced = true,
		Lunge = -2, Radius = 6,
	}),
	EagleShot = move({
		Id = "EagleShot", Name = "EAGLE SHOT", Kind = "Projectile", Anim = "Draw",
		Cooldown = 8, Duration = 0.75, WindUp = 0.2, Damage = 36, Range = 150, ArcDot = -1,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.5, Stagger = 0.3, Knockback = 10, Advanced = true,
		ProjectileCount = 1, ProjectileSpeed = 200, Pierce = 1,
	}),

	------------------------------------------------------------------ Morning Star
	ChainTempest = move({
		Id = "ChainTempest", Name = "CHAIN TEMPEST", Kind = "Melee", Anim = "Slash",
		Cooldown = 10, Duration = 1.4, WindUp = 0.15, Damage = 42, Range = 8, ArcDot = 0,
		MaxTargets = 3, PvPMaxTargets = 2, PvPMultiplier = 0.35, Stagger = 0.35, Knockback = 16, Advanced = true,
		Hits = hits({
			{ Delay = 0, Multiplier = 0.5, Anim = "Slash" },
			{ Delay = 0.35, Multiplier = 0.5, Anim = "Backhand" },
			{ Delay = 0.75, Multiplier = 0.6, Anim = "Spin", Spin = true, Range = 8.5 },
			{ Delay = 1.1, Multiplier = 0.9, Anim = "Overhead", Spin = true, Range = 6 }, -- ground impact
		}),
	}),
	FallingMeteor = move({
		Id = "FallingMeteor", Name = "FALLING METEOR", Kind = "Aerial", Anim = "Overhead",
		Cooldown = 10, Duration = 1.1, WindUp = 0.15, Damage = 55, Range = 8, ArcDot = 0,
		MaxTargets = 2, PvPMaxTargets = 1, PvPMultiplier = 0.4, Stagger = 0.6, Knockback = 22, Advanced = true,
		Forward = 2, Shockwave = 8, ShockwaveMultiplier = 0.45, LandingRecovery = 0.6,
	}),

	------------------------------------------------------------------ Trident
	RetiariusFury = move({
		Id = "RetiariusFury", Name = "RETIARIUS FURY", Kind = "Melee", Anim = "Guard",
		Cooldown = 9, Duration = 1.3, WindUp = 0.05, Damage = 26, Range = 10, ArcDot = 0.5,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.45, Stagger = 0.25, Knockback = 10, Advanced = true,
		CounterWindow = 0.3,
		Hits = hits({
			{ Delay = 0.3, Multiplier = 0.5, Anim = "Thrust" },
			{ Delay = 0.55, Multiplier = 0.5, Anim = "Thrust" },
			{ Delay = 0.8, Multiplier = 0.5, Anim = "Low", Spin = true, Range = 7 },
			{ Delay = 1.1, Multiplier = 1.0, Anim = "Thrust", Lunge = 3, Range = 12, ArcDot = 0.65 },
		}),
	}),
	SeaEagleDive = move({
		Id = "SeaEagleDive", Name = "SEA EAGLE DIVE", Kind = "Aerial", Anim = "Thrust",
		Cooldown = 9, Duration = 1.0, WindUp = 0.08, Damage = 40, Range = 11, ArcDot = 0.55,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.45, Stagger = 0.35, Knockback = 14, Advanced = true,
		Forward = 8, LandingRecovery = 0.35,
	}),

	------------------------------------------------------------------ Hoplite Spear
	PhalanxBreaker = move({
		Id = "PhalanxBreaker", Name = "PHALANX BREAKER", Kind = "Melee", Anim = "Thrust",
		Cooldown = 8, Duration = 0.95, WindUp = 0.25, Damage = 34, Range = 12, ArcDot = 0.65,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.45, Stagger = 0.8, Knockback = 26, Advanced = true,
		GuardBreak = true, Lunge = 2,
	}),
	SpartanVault = move({
		Id = "SpartanVault", Name = "SPARTAN VAULT", Kind = "Aerial", Anim = "Thrust",
		Cooldown = 9, Duration = 1.0, WindUp = 0.1, Damage = 38, Range = 9, ArcDot = 0.5,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.45, Stagger = 0.4, Knockback = 16, Advanced = true,
		Forward = 8, LandingRecovery = 0.35,
	}),

	------------------------------------------------------------------ Twin Daggers
	ViperDance = move({
		Id = "ViperDance", Name = "VIPER DANCE", Kind = "Melee", Anim = "Flurry",
		Cooldown = 9, Duration = 1.2, WindUp = 0.05, Damage = 16, Range = 6, ArcDot = 0.3,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.5, Stagger = 0.05, Knockback = 4, Advanced = true,
		Hits = hits({
			{ Delay = 0, Multiplier = 0.7, Anim = "Slash" },
			{ Delay = 0.25, Multiplier = 0, Anim = "Spin", Lunge = -2 }, -- dodge turn
			{ Delay = 0.45, Multiplier = 0.5, Anim = "Flurry" },
			{ Delay = 0.6, Multiplier = 0.5, Anim = "Flurry" },
			{ Delay = 0.75, Multiplier = 0.5, Anim = "Flurry" },
			{ Delay = 1.0, Multiplier = 1.0, Anim = "Spin", Spin = true, Range = 6 },
		}),
	}),
	RiverShadow = move({
		Id = "RiverShadow", Name = "RIVER SHADOW", Kind = "Aerial", Anim = "Spin",
		Cooldown = 9, Duration = 0.9, WindUp = 0.05, Damage = 30, Range = 6.5, ArcDot = -1,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = 0.45, Stagger = 0.3, Knockback = 8, Advanced = true,
		Forward = 7, LandingRecovery = 0.15,
	}),

	------------------------------------------------------------------ Battle Axe
	ColosseumBreaker = move({
		Id = "ColosseumBreaker", Name = "COLOSSEUM BREAKER", Kind = "Melee", Anim = "Guard",
		Cooldown = 10, Duration = 1.5, WindUp = 0.05, Damage = 50, Range = 8, ArcDot = 0.25,
		MaxTargets = 2, PvPMaxTargets = 1, PvPMultiplier = 0.4, Stagger = 0.5, Knockback = 18, Advanced = true,
		CounterWindow = 0.3,
		Hits = hits({
			{ Delay = 0.3, Multiplier = 0.4, Anim = "Backhand" }, -- axe hook
			{ Delay = 0.6, Multiplier = 0, Anim = "Spin" }, -- body turn
			{ Delay = 0.9, Multiplier = 0.8, Anim = "Overhead" },
			{ Delay = 1.25, Multiplier = 0.6, Anim = "Overhead", Spin = true, Range = 6 }, -- ground finish
		}),
	}),
	ThunderOfMars = move({
		Id = "ThunderOfMars", Name = "THUNDER OF MARS", Kind = "Aerial", Anim = "Overhead",
		Cooldown = 11, Duration = 1.2, WindUp = 0.2, Damage = 60, Range = 8, ArcDot = 0.2,
		MaxTargets = 2, PvPMaxTargets = 1, PvPMultiplier = 0.38, Stagger = 0.6, Knockback = 22, Advanced = true,
		Forward = 3, Shockwave = 9, ShockwaveMultiplier = 0.4, LandingRecovery = 0.8, MissRecovery = 0.4,
	}),
}

------------------------------------------------------------------------------------------
-- Generated weapon moves: the basic attack CHAIN, movement / gesture variants, slide attacks,
-- parry counters, aerial gesture attacks, generated Specials and every weapon's Ultimate.
-- Each is derived from the weapon's basic attack (damage / range / tempo) through a template, so
-- tuning a weapon's basic attack keeps all its variants consistent. Ids: <Prefix>_<Slot>
-- (e.g. Gladius_SlashRL, Axe_Slide, Bow_Ultimate). WeaponAttackDefinitions / WeaponSpecialDefinitions
-- map controls and gestures onto these ids.
------------------------------------------------------------------------------------------

type Template = {
	Name: string,
	Anim: Anim,
	Damage: number, -- x basic damage
	RangeAdd: number?,
	Wind: number, -- wind-up seconds (x weapon tempo)
	Duration: number, -- busy seconds (x weapon tempo)
	Sweep: { number }?,
	Line: number?,
	Height: Height?,
	Lunge: number?,
	Stagger: number?,
	Knockback: number?,
	MaxTargets: number?,
	PvPMaxTargets: number?,
	PvP: number?, -- PvP multiplier (x the basic attack's)
	Hits: { HitStep }?,
	RequiresAir: boolean?,
	Impact: number?,
	ImpactMultiplier: number?,
	MissRecovery: number?,
}

-- Prefix -> style. Tempo scales wind-ups / durations (heavy weapons are slower).
local STYLE: { [string]: { style: string, tempo: number } } = {
	Gladius = { style = "Sword", tempo = 1 },
	Legion = { style = "Sword", tempo = 1.05 },
	Daggers = { style = "Daggers", tempo = 0.75 },
	MorningStar = { style = "Heavy", tempo = 1.35 },
	Axe = { style = "Heavy", tempo = 1.45 },
	Trident = { style = "Spear", tempo = 1.1 },
	Hoplite = { style = "Spear", tempo = 1.15 },
	Bow = { style = "Bow", tempo = 1 },
}

local MELEE_TEMPLATES: { [string]: Template } = {
	SlashRL = { Name = "RIGHT SLASH", Anim = "SlashRL", Damage = 1, Wind = 0.1, Duration = 0.42, Sweep = { 70, -70 }, Height = "Mid", Lunge = 0.8 },
	SlashLR = { Name = "LEFT SLASH", Anim = "SlashLR", Damage = 1, Wind = 0.1, Duration = 0.42, Sweep = { -75, 75 }, Height = "Mid", Lunge = 0.8 },
	Thrust = { Name = "THRUST", Anim = "Thrust", Damage = 1.15, RangeAdd = 1.5, Wind = 0.12, Duration = 0.46, Line = 1.4, Height = "Mid", Lunge = 2.2 },
	Overhead = { Name = "OVERHEAD", Anim = "Overhead", Damage = 1.35, Wind = 0.22, Duration = 0.62, Sweep = { 14, -14 }, Height = "High", Lunge = 1, Stagger = 0.15 },
	Retreat = { Name = "RETREATING CUT", Anim = "RetreatCut", Damage = 0.8, Wind = 0.06, Duration = 0.45, Sweep = { 50, -50 }, Height = "Mid", Lunge = -3.5 },
	Counter = { Name = "PARRY COUNTER", Anim = "ParryCounter", Damage = 1.6, RangeAdd = 1, Wind = 0.03, Duration = 0.42, Line = 1.8, Height = "Mid", Lunge = 2.5, Stagger = 0.35 },
	Wide = { Name = "WIDE SWEEP", Anim = "Wide", Damage = 0.85, Wind = 0.14, Duration = 0.55, Sweep = { -110, 110 }, Height = "Mid", MaxTargets = 3, PvPMaxTargets = 2, PvP = 0.85 },
	Spin = { Name = "WHIRL", Anim = "Spin", Damage = 0.9, Wind = 0.12, Duration = 0.6, Sweep = { -180, 180 }, Height = "Mid", MaxTargets = 4, PvPMaxTargets = 2, PvP = 0.8 },
	AirLeft = { Name = "AIR SWEEP LEFT", Anim = "AirSpinL", Damage = 0.95, Wind = 0.06, Duration = 0.4, Sweep = { 80, -90 }, Height = "Mid", RequiresAir = true, PvP = 0.85 },
	AirRight = { Name = "AIR SWEEP RIGHT", Anim = "AirSpinR", Damage = 0.95, Wind = 0.06, Duration = 0.4, Sweep = { -80, 90 }, Height = "Mid", RequiresAir = true, PvP = 0.85 },
	AirUp = { Name = "RISING STRIKE", Anim = "Rise", Damage = 1, Wind = 0.06, Duration = 0.42, Line = 1.6, Height = "High", RequiresAir = true, PvP = 0.85 },
	-- Generated Specials (Tier I values; tiers scale them, WeaponSpecialDefinitions)
	SpecCleave = { Name = "GLADIATOR CLEAVE", Anim = "Wide", Damage = 1.5, Wind = 0.2, Duration = 0.85, Sweep = { 100, -120 }, Height = "Mid", MaxTargets = 5, PvPMaxTargets = 2, PvP = 0.6, Lunge = 1.5 },
	SpecCombination = {
		Name = "GLADIATOR COMBINATION", Anim = "SlashRL", Damage = 1, Wind = 0.08, Duration = 1.05, Height = "Mid", PvP = 0.55,
		Hits = hits({ { Delay = 0, Multiplier = 0.55, Anim = "SlashRL", Sweep = { 70, -70 } }, { Delay = 0.28, Multiplier = 0.55, Anim = "SlashLR", Sweep = { -70, 70 }, Lunge = 1 }, { Delay = 0.58, Multiplier = 0.85, Anim = "Thrust", Line = 1.5, Lunge = 2 } }),
	},
	SpecHeavy = { Name = "HEAVY DESCENT", Anim = "Overhead", Damage = 2, Wind = 0.34, Duration = 1.1, Sweep = { 12, -12 }, Height = "High", Lunge = 1.5, Stagger = 0.4, Knockback = 18, PvP = 0.5, Impact = 6, ImpactMultiplier = 0.4, MissRecovery = 0.35 },
}

local SLIDE_TEMPLATES: { [string]: Template } = {
	Gladius = { Name = "LOW SAND CUT", Anim = "SlideCut", Damage = 1, Wind = 0.05, Duration = 0.4, Sweep = { -70, 70 }, Height = "Low", PvP = 0.75 },
	Legion = { Name = "GLADIATOR ENTRY", Anim = "SlideThrust", Damage = 1.15, RangeAdd = 1.5, Wind = 0.06, Duration = 0.45, Line = 1.5, Height = "Low", Stagger = 0.25, PvP = 0.75 },
	MorningStar = {
		Name = "CHAIN DRAG", Anim = "SlideRise", Damage = 1, Wind = 0.08, Duration = 0.65, Height = "Low", PvP = 0.65, MissRecovery = 0.5,
		Hits = hits({ { Delay = 0, Multiplier = 0.45, Sweep = { -35, 35 }, Height = "Low" }, { Delay = 0.28, Multiplier = 0.9, Anim = "Rise", Sweep = { 25, -25 }, Height = "Mid" } }),
	},
	Trident = { Name = "RETIARIUS SLIDE", Anim = "SlideThrust", Damage = 1.1, RangeAdd = 2, Wind = 0.06, Duration = 0.5, Line = 1.1, Height = "Low", PvP = 0.7 },
	Hoplite = { Name = "SPEAR ENTRY", Anim = "SlideThrust", Damage = 1.15, RangeAdd = 1.5, Wind = 0.07, Duration = 0.5, Line = 1.3, Height = "Low", PvP = 0.7 },
	Daggers = {
		Name = "RIVER SLIP", Anim = "SlideCross", Damage = 1, Wind = 0.03, Duration = 0.35, Height = "Low", PvP = 0.75,
		Hits = hits({ { Delay = 0, Multiplier = 0.6, Sweep = { 45, -45 }, Height = "Low" }, { Delay = 0.14, Multiplier = 0.6, Sweep = { -45, 45 }, Height = "Low" } }),
	},
	Axe = { Name = "LOW REAPER", Anim = "SlideReaper", Damage = 1.1, Wind = 0.14, Duration = 0.7, Sweep = { -100, 100 }, Height = "Low", MaxTargets = 3, PvPMaxTargets = 2, PvP = 0.6, MissRecovery = 0.6 },
}

local ULTIMATE_NAMES: { [string]: string } = {
	Gladius = "REBEL'S FINALE",
	Legion = "IMPERIAL VERDICT",
	MorningStar = "COMET OF ROME",
	Trident = "NEPTUNE'S JUDGEMENT",
	Hoplite = "SPARTAN THUNDER",
	Daggers = "RIVER STORM",
	Axe = "WRATH OF MARS",
	Bow = "STORM OF ARROWS",
}

local function fromTemplate(prefix: string, slot: string, template: Template, basic: MoveDefinition, tempo: number): MoveDefinition
	local wind = template.Wind * tempo
	local duration = template.Duration * tempo
	local stepList: { HitStep }? = nil
	if template.Hits then
		local list = {}
		for _, step in template.Hits do
			local copy = table.clone(step)
			copy.Delay = step.Delay * tempo
			table.insert(list, table.freeze(copy))
		end
		stepList = table.freeze(list) :: any
	end
	return move({
		Id = prefix .. "_" .. slot,
		Name = template.Name,
		Kind = "Melee",
		Anim = template.Anim,
		Cooldown = duration, -- the same variant can't fire twice in a row faster than its own length
		Duration = duration,
		WindUp = wind,
		Damage = math.floor(basic.Damage * template.Damage + 0.5),
		Range = basic.Range + (template.RangeAdd or 0),
		ArcDot = if template.Line then 0.6 else -1,
		MaxTargets = template.MaxTargets or math.max(1, basic.MaxTargets),
		PvPMaxTargets = template.PvPMaxTargets or 1,
		PvPMultiplier = basic.PvPMultiplier * (template.PvP or 1),
		Stagger = basic.Stagger + (template.Stagger or 0),
		Knockback = template.Knockback or basic.Knockback,
		Lunge = template.Lunge,
		Hits = stepList,
		Sweep = template.Sweep,
		Line = template.Line,
		Height = template.Height,
		ActiveTime = math.clamp(0.1 * tempo, 0.08, 0.16),
		Slot = slot,
		RequiresAir = template.RequiresAir,
		Impact = template.Impact,
		ImpactMultiplier = template.ImpactMultiplier,
		MissRecovery = template.MissRecovery,
	})
end

local function projectile(prefix: string, slot: string, name: string, basic: MoveDefinition, damage: number, wind: number, duration: number, extra: { [string]: any }): MoveDefinition
	local def: { [string]: any } = {
		Id = prefix .. "_" .. slot, Name = name, Kind = "Projectile", Anim = "Draw",
		Cooldown = duration, Duration = duration, WindUp = wind, Damage = math.floor(basic.Damage * damage + 0.5), Range = basic.Range, ArcDot = -1,
		MaxTargets = 1, PvPMaxTargets = 1, PvPMultiplier = basic.PvPMultiplier, Stagger = basic.Stagger, Knockback = basic.Knockback,
		ProjectileCount = 1, ProjectileSpeed = basic.ProjectileSpeed or 145, Pierce = 1, Slot = slot,
	}
	for key, value in extra do
		def[key] = value
	end
	return move(def :: any)
end

local generated: { MoveDefinition } = {}
for prefix, info in STYLE do
	local basic = Moves[prefix .. "_Basic"]
	if not basic then
		continue
	end
	if info.style == "Bow" then
		table.insert(generated, projectile(prefix, "Shot", "ARROW", basic, 1, 0.15, 0.6, {}))
		table.insert(generated, projectile(prefix, "QuickShot", "QUICK SHOT", basic, 0.7, 0.07, 0.42, { ExtraSpread = 2 }))
		table.insert(generated, projectile(prefix, "PowerShot", "POWER SHOT", basic, 1.5, 0.32, 0.85, { Pierce = 2, Stagger = 0.25 }))
		table.insert(generated, projectile(prefix, "Retreat", "STEP-BACK SHOT", basic, 0.9, 0.1, 0.6, { Lunge = -3.5 }))
		table.insert(generated, projectile(prefix, "Counter", "COUNTER SHOT", basic, 1.4, 0.04, 0.5, {}))
		table.insert(generated, projectile(prefix, "Wide", "FAN SHOT", basic, 0.75, 0.16, 0.7, { ProjectileCount = 3, Spread = 9 }))
		table.insert(generated, projectile(prefix, "Spin", "ARROW CIRCLE", basic, 0.6, 0.2, 0.8, { ProjectileCount = 8, Spread = 45 }))
		table.insert(generated, projectile(prefix, "Slide", "SLIDING SHOT", basic, 0.9, 0.06, 0.45, { ExtraSpread = 4, PvPMultiplier = basic.PvPMultiplier * 0.75 }))
		table.insert(generated, projectile(prefix, "AirLeft", "AIR SHOT", basic, 0.9, 0.06, 0.4, { ExtraSpread = 3, RequiresAir = true }))
		table.insert(generated, projectile(prefix, "AirRight", "AIR SHOT", basic, 0.9, 0.06, 0.4, { ExtraSpread = 3, RequiresAir = true }))
		table.insert(generated, projectile(prefix, "AirUp", "AIR SHOT", basic, 0.9, 0.06, 0.4, { ExtraSpread = 3, RequiresAir = true }))
		table.insert(generated, projectile(prefix, "SpecFan", "VOLLEY FAN", basic, 0.85, 0.2, 0.85, { ProjectileCount = 5, Spread = 8, PvPMultiplier = basic.PvPMultiplier * 0.6 }))
		table.insert(generated, projectile(prefix, "SpecPierce", "PIERCING SHOT", basic, 1.6, 0.3, 0.9, { Pierce = 3, Stagger = 0.3, PvPMultiplier = basic.PvPMultiplier * 0.6 }))
		table.insert(generated, projectile(prefix, "SpecCircle", "ARROW STORM CIRCLE", basic, 0.7, 0.25, 0.95, { ProjectileCount = 8, Spread = 45, PvPMultiplier = basic.PvPMultiplier * 0.55 }))
		table.insert(generated, move({
			Id = prefix .. "_Ultimate", Name = ULTIMATE_NAMES[prefix], Kind = "Volley", Anim = "Ultimate",
			Cooldown = 3, Duration = 1.6, WindUp = 0.35, Damage = math.floor(basic.Damage * 2.6 + 0.5), Range = 60, ArcDot = -1,
			MaxTargets = 8, PvPMaxTargets = 3, PvPMultiplier = basic.PvPMultiplier * 0.35, Stagger = 0.4, Knockback = 12,
			Radius = 11, Slot = "Ultimate", Ultimate = true,
		}))
		continue
	end
	for slot, template in MELEE_TEMPLATES do
		local t = template
		if info.style == "Daggers" and slot == "Overhead" then
			t = table.clone(template)
			t.Name, t.Anim, t.Sweep, t.Height = "CROSS CUT", "Cross", { 45, -45 }, "Mid"
		elseif info.style == "Heavy" and slot == "Thrust" then
			t = table.clone(template)
			t.Name, t.Damage, t.Line = "SHOVE", 0.8, 1.7
		end
		table.insert(generated, fromTemplate(prefix, slot, t, basic, info.tempo))
	end
	local slide = SLIDE_TEMPLATES[prefix]
	if slide then
		table.insert(generated, fromTemplate(prefix, "Slide", slide, basic, info.tempo))
	end
	-- The Ultimate: a telegraphed leap and a crushing landing; capped in PvP, punishable if missed
	table.insert(generated, move({
		Id = prefix .. "_Ultimate", Name = ULTIMATE_NAMES[prefix] or "ULTIMATE", Kind = "Aerial", Anim = "Ultimate",
		Cooldown = 3, Duration = 1.4, WindUp = 0.35, Damage = math.floor(basic.Damage * 3.2 + 0.5), Range = basic.Range + 1, ArcDot = 0,
		MaxTargets = 5, PvPMaxTargets = 3, PvPMultiplier = basic.PvPMultiplier * 0.3, Stagger = 0.6, Knockback = 22,
		Forward = 6, Shockwave = 10, ShockwaveMultiplier = 0.5, LandingRecovery = 0.9, MissRecovery = 0.8,
		Slot = "Ultimate", Ultimate = true, Height = "High",
	}))
end
for _, def in generated do
	Moves[def.Id] = def
end

return table.freeze(Moves)
