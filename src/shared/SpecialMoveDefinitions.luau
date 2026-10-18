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

export type HitStep = {
	Delay: number, -- seconds after the wind-up
	Multiplier: number, -- of Damage (0 = no hit, animation only)
	Anim: Anim?,
	Lunge: number?, -- short forward step (client moves its own character, never through walls)
	Range: number?,
	ArcDot: number?,
	Spin: boolean?, -- full circle around the player
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

return table.freeze(Moves)
