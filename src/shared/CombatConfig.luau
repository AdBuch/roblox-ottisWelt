--!strict
-- Combat tuning and shared combat names. Only the server applies these numbers to
-- gameplay; the client reads them for display.

export type FeedbackKind = "Swing" | "Hit" | "Block" | "PlayerHit" | "Heal" | "Coins" | "Shop" | "Slowed"

local CombatConfig = {
	-- Zombies (per-variant stats live in ZombieDefinitions)
	ZombieTag = "EnemyZombie", -- CollectionService tag on every LIVING zombie model
	ZombieCollisionGroup = "Zombies",
	MaxActiveZombies = 32, -- hard cap for this version (Round 6 = 32)
	ZombieDamageMultiplier = 1, -- global difficulty knob for zombie hits
	ZombieDetectRadius = 160, -- covers the whole Colosseum floor
	ZombieRetargetInterval = 1,
	ZombieThinkInterval = 0.15,
	ZombiePathInterval = 1.0,
	ZombieDirectMoveDistance = 30, -- move straight (no pathfinding) when the goal is this close and visible
	ZombieDespawnSeconds = 1.0, -- death effect length before the model is removed

	-- Crowd control around the fighter
	MaxSimultaneousAttackers = 4,
	AttackStartSpacing = 0.25, -- at most one new wind-up per target every this many seconds
	CrowdSlotCount = 10,
	CrowdSlotRadius = 4.4, -- melee slots around the player
	CrowdWaitRadius = 11, -- zombies without a slot circle at this distance
	CrowdApproachRadius = 16, -- claim a slot when this close
	SeparationRadius = 3.8, -- zombies steer apart inside this distance

	-- Player
	PlayerMaxHealth = 120,
	PlayerWalkSpeed = 16,
	BlockingWalkSpeed = 11,
	HitImmunitySeconds = 0.35, -- after a landed zombie hit, further hits are ignored briefly

	-- Shield (reduction values are per shield in ShieldDefinitions)
	ShieldFacingDot = 0.5, -- attacker must be within 60° of where the player faces
	ShieldBlockDistance = 12,
	ShieldMaxBlockSeconds = 4, -- exploit safeguard: release and press again to re-raise
	ShieldPushBackSpeed = 34,

	-- Temporary diagnostics for rejected attacks (rate limited per player and reason)
	DebugRejectedAttacks = true,
	RejectLogInterval = 2,

	-- Built-in Studio sounds (rbxasset://, no uploaded asset IDs). Placeholders, swap freely.
	SwingSoundId = "rbxasset://sounds/swordslash.wav",
	ShieldSoundId = "rbxasset://sounds/unsheath.wav",
	FanfareSoundId = "rbxasset://sounds/electronicpingshort.wav",

	-- Server -> client messages on Remotes.CombatFeedback
	Feedback = table.freeze({
		Swing = "Swing" :: FeedbackKind, -- ()
		Hit = "Hit" :: FeedbackKind, -- (zombieModel, damage, blockedByChampion)
		Block = "Block" :: FeedbackKind, -- (isBlocking)
		PlayerHit = "PlayerHit" :: FeedbackKind, -- (damage, wasBlocked)
		Heal = "Heal" :: FeedbackKind, -- (amount)
		Coins = "Coins" :: FeedbackKind, -- (amount)
		Shop = "Shop" :: FeedbackKind, -- (message, success)
		Slowed = "Slowed" :: FeedbackKind, -- (seconds)
	}),
}

return table.freeze(CombatConfig)
