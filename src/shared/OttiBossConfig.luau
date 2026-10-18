--!strict
-- Otti the Gladiator: the living otter champion and final boss (Round 7) of Solo and Co-op.
-- He is NOT a zombie: no zombie tags, damage states, limb loss or archive logic ever apply.
-- Attacks: OttiMoveDefinitions. Phases: BossPhaseDefinitions.

local OttiBossConfig = {
	DisplayName = "OTTI",
	Title = "CHAMPION OF THE COLOSSEUM",
	RoundTitle = "ROUND 7 — FINAL BOSS",

	-- Health by number of participating players (1-4). Damage never scales with players.
	HealthByPlayers = table.freeze({ 1200, 1850, 2450, 3000 }),

	-- Rewards (paid exactly once per encounter)
	SoloReward = 500,
	CoopSurvivorReward = 400,
	CoopContributorReward = 250, -- defeated co-op participants who damaged Otti

	-- Intro
	PreIntroSeconds = 6, -- after the last Round 6 zombie dies
	SilenceTextAt = 2.5, -- "THE CROWD FALLS SILENT..." appears this long into the wait
	WalkInDistance = 22,
	WalkInSeconds = 3.2,
	DefeatReturnSeconds = 12,

	-- Body
	Scale = 1.15, -- about 9.5 studs tall standing; a champion, not a giant
	WalkSpeedBiped = 10,
	StrafeSpeed = 9,
	RunSpeedQuad = 30,
	DashSpeed = 40,
	TurnRateQuad = 9, -- radians per second (fast otter turns)
	TurnRateBiped = 5,
	TailReach = 10.5, -- from the root centre to the tail tip during sweeps (validated volume)
	ContactRadius = 3.6, -- River Dash contact volume
	JumpClearance = 1.8, -- a player whose root is this high above standing height clears low tail attacks

	-- Defense
	GuardSeconds = 1.1, -- frontal hits are blocked while guarding (shield glow)
	GuardReduction = 0.85, -- share of damage the raised shield stops
	GuardFacingDot = 0.35,
	PredictableHits = 3, -- this many frontal hits from one player within PredictableWindow -> guard
	PredictableWindow = 4,
	PoiseMax = 100, -- accumulated hit impact; breaking it staggers Otti
	PoiseDecayPerSecond = 18,
	StaggerSeconds = 0.9,
	KnockdownSeconds = 1.6, -- every third poise break within KnockdownWindow
	KnockdownWindow = 25,
	PhaseChangeSeconds = 2.2, -- shield strike + sand burst; Otti can't be hurt hard during it (50 %)

	-- Targeting
	RetargetInterval = 1.3,
	MaxFocusSeconds = 7, -- after this long on one player, others score higher
	RecentAttackPenaltySeconds = 4,
	RangedAttackerDistance = 22,
	ThreatDecayPerSecond = 0.12,

	-- Grapple / throw safety
	ThrowDistanceMin = 13,
	ThrowDistanceMax = 20,
	ThrowHeight = 7, -- clamped arc height
	ThrowSeconds = 0.75,
	LandingImmunitySeconds = 1.5,
	LandingMargin = 9, -- landing points stay this far inside the arena wall
	LandingPlayerClearance = 7, -- never land right next to another player
	GrappleSafetyTimeout = 4, -- control is always restored after this long

	-- Knockdown on players (tail trip, throw landing): never longer than this
	MaxKnockdownSeconds = 1.2,
	KnockdownProtectionSeconds = 1.0,

	-- Authored animations can replace the procedural ones later: fill in Animation asset IDs
	-- the project owns (keys = locomotion states / move ids). Empty = procedural poses.
	AnimationIds = table.freeze({}) :: { [string]: string },
}

return table.freeze(OttiBossConfig)
