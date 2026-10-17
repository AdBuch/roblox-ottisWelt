--!strict
-- Combat tuning and shared combat names. Only the server applies these numbers to
-- gameplay; the client reads them for display.

export type FeedbackKind = "Swing" | "SwordHit" | "Block" | "PlayerHit"
export type CombatState = "READY" | "ATTACKING" | "BLOCKING" | "HIT" | "VICTORY"

local CombatConfig = {
	-- Roman zombie
	ZombieName = "RomanZombie",
	ZombieMaxHealth = 60,
	ZombieRespawnSeconds = 5,
	ZombieWalkSpeed = 12,
	ZombieDetectRadius = 60,
	ZombieAttackRange = 5, -- starts an attack inside this distance
	ZombieAttackReach = 6.5, -- the blow only lands if the target is still this close
	ZombieAttackDamage = 10,
	ZombieAttackCooldown = 1.4,
	ZombieWindUpSeconds = 0.35,
	ZombieThinkInterval = 0.1,
	ZombiePathInterval = 0.6,

	-- Arena folder attributes mirrored for the HUD
	ZombieHealthAttribute = "ZombieHealth",
	ZombieMaxHealthAttribute = "ZombieMaxHealth",
	ZombieAliveAttribute = "ZombieAlive",

	-- Player tools (built from Parts by the server)
	ToolAttribute = "OttiTool",
	SwordToolName = "Roman Sword",
	SwordDamage = 15,
	SwordCooldown = 0.65,
	SwordRange = 7,
	SwordFacingDot = 0.3, -- target must be within ~72° of where the player faces

	ShieldToolName = "Roman Shield",
	ShieldDamageReduction = 0.8,
	ShieldFacingDot = 0.5, -- attacker must be within 60° of where the player faces
	ShieldBlockDistance = 10,
	ShieldMaxBlockSeconds = 4, -- exploit safeguard: block drops after this; click again to re-raise
	ShieldPushBackSpeed = 40,
	ShieldStunSeconds = 0.6,

	-- Built-in Studio sounds (rbxasset://, no uploaded asset IDs). Placeholders, swap freely.
	SwordSoundId = "rbxasset://sounds/swordslash.wav",
	ShieldSoundId = "rbxasset://sounds/unsheath.wav",

	-- Server -> client messages on Remotes.CombatFeedback
	Feedback = table.freeze({
		Swing = "Swing" :: FeedbackKind,
		SwordHit = "SwordHit" :: FeedbackKind,
		Block = "Block" :: FeedbackKind,
		PlayerHit = "PlayerHit" :: FeedbackKind,
	}),
}

return table.freeze(CombatConfig)
