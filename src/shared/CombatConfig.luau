--!strict
-- Combat tuning and shared combat names. Only the server applies these numbers to
-- gameplay; the client reads them for display.

export type FeedbackKind =
	"Action"
	| "Hit"
	| "Block"
	| "Parry"
	| "PlayerHit"
	| "Heal"
	| "Aura"
	| "Shop"
	| "Slowed"
	| "Dash"
	| "Knockback"
	| "Elimination"
	| "DamageFx"
	| "Knockdown"
	| "Leap"
	| "Dive"
	| "ComboFail"
	| "Dodge"
	| "PerfectBlock"
	| "Slide"
	| "SpecialCharge"

export type ActionName = "Basic" | "Jump" | "Execute"

local CombatConfig = {
	-- Zombies (per-variant stats: ZombieDefinitions, personalities: ZombieAIProfiles)
	ZombieTag = "EnemyZombie", -- CollectionService tag on every LIVING arena zombie
	ZombieCollisionGroup = "Zombies",
	ZombieDamageMultiplier = 1, -- global difficulty knob for zombie hits
	ZombieDetectRadius = 90, -- general melee target detection (per-profile MaxChaseDistance)
	ArcherDetectRadius = 140, -- Undead Sagittarius target detection
	ZombieRetargetInterval = 1.2,
	ZombieThinkInterval = 0.15,
	ZombiePathInterval = 1.0,
	PathRequestsPerSecond = 12, -- global pathfinding budget for all zombies together
	ZombieDirectMoveDistance = 30,
	ZombieDespawnSeconds = 1.0,
	ThreatDecayPerSecond = 0.15, -- threat fades by this share each second

	-- Crowd control around each player
	MaxSimultaneousAttackers = 4,
	AttackStartSpacing = 0.25,
	CrowdSlotCount = 10,
	CrowdSlotRadius = 4.4, -- minimum; long weapons stand farther out (AttackRange - 2.5)
	CrowdSlotMaxRadius = 8,
	CrowdWaitRadius = 13,
	CrowdApproachRadius = 22,
	SeparationRadius = 3.8,

	-- Player
	PlayerMaxHealth = 120,
	PlayerWalkSpeed = 16,
	HitImmunitySeconds = 0.35, -- after a landed zombie hit, further zombie hits are ignored briefly
	CoopRespawnHealthFraction = 0.6,
	PvPMaxDamageFraction = 0.45, -- no single PvP hit removes more than this share of max health
	SpawnProtectionSeconds = 2,

	-- Shields / parry (per-shield values: ShieldDefinitions)
	ShieldBlockDistance = 12,
	ShieldPushBackSpeed = 34,
	ParryWindowSeconds = 0.4, -- twin daggers: built-in parry instead of a shield
	ParryCooldownSeconds = 1.2,
	ParryReduction = 0.7,

	-- Combos
	ComboWindowSeconds = 0.8, -- max time between the end of one move and the next input
	ComboHistoryLength = 4,

	-- Remote rate limits (requests per second, per player)
	ActionRateLimit = 10,
	BlockRateLimit = 10,

	-- Temporary diagnostics for rejected attacks (rate limited per player and reason)
	DebugRejectedAttacks = true,
	RejectLogInterval = 2,

	-- Built-in Studio sounds (rbxasset://, no uploaded asset IDs). Placeholders, swap freely.
	SwingSoundId = "rbxasset://sounds/swordslash.wav",
	ShieldSoundId = "rbxasset://sounds/unsheath.wav",
	FanfareSoundId = "rbxasset://sounds/electronicpingshort.wav",

	-- Server -> client messages on Remotes.CombatFeedback
	Feedback = table.freeze({
		Action = "Action" :: FeedbackKind, -- (action, moveName, cooldownSeconds, comboName?)
		Hit = "Hit" :: FeedbackKind, -- (targetModel, damage, blocked)
		Block = "Block" :: FeedbackKind, -- (isBlocking)
		Parry = "Parry" :: FeedbackKind, -- ()
		PlayerHit = "PlayerHit" :: FeedbackKind, -- (damage, wasBlocked, fromPosition?)
		Heal = "Heal" :: FeedbackKind, -- (amount)
		Aura = "Aura" :: FeedbackKind, -- (auraAmount, reason, denariiAmount)
		Shop = "Shop" :: FeedbackKind, -- (message, success)
		Slowed = "Slowed" :: FeedbackKind, -- (seconds)
		Dash = "Dash" :: FeedbackKind, -- (direction, distance) client moves its own character
		Knockback = "Knockback" :: FeedbackKind, -- (velocity)
		Elimination = "Elimination" :: FeedbackKind, -- (text)
		DamageFx = "DamageFx" :: FeedbackKind, -- (position, kind "Zombie"|"Player"|"Boss", scale, direction?) to everyone
		Knockdown = "Knockdown" :: FeedbackKind, -- (seconds) short controlled knockdown on your own character
		Leap = "Leap" :: FeedbackKind, -- (upVelocity, direction, distance) one controlled hop for a combo aerial
		Dive = "Dive" :: FeedbackKind, -- (direction, distance, downVelocity) aerial descent
		ComboFail = "ComboFail" :: FeedbackKind, -- (text) NO COMBO / NOT READY
		Dodge = "Dodge" :: FeedbackKind, -- () a slide dodged an attack
		PerfectBlock = "PerfectBlock" :: FeedbackKind, -- () a perfect block / parry: counter window open
		Slide = "Slide" :: FeedbackKind, -- (direction, distance, duration) approved slide: the client moves its character
		SpecialCharge = "SpecialCharge" :: FeedbackKind, -- ("start" | "cancel" | "fire", reason or tier)
	}),
}

return table.freeze(CombatConfig)
