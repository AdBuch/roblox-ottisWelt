--!strict
-- Shared names: folders, tags, attributes, remotes, shells.
-- Combat tuning: CombatConfig. Items: WeaponDefinitions / ShieldDefinitions / SpecialMoveDefinitions /
-- WeaponSpecialDefinitions. Enemies: ZombieDefinitions / ZombieAIProfiles. Modes: GameModeDefinitions.

local Config = {
	ArenaFolderName = "GeneratedArena",
	LobbyFolderName = "GeneratedLobby",
	ZombiesFolderName = "Zombies",
	ProjectilesFolderName = "Projectiles",
	ShopItemTag = "OttiShopItem",
	ZombieDisplayTag = "ZombieDisplay", -- archive cage zombies: never combat targets
	TrainingDummyTag = "TrainingDummy",

	-- Healing shells (counts per mode live in GameModeDefinitions)
	ShellNamePrefix = "GoldenShell_",
	ShellPickupRange = 8,
	ShellHealAmount = 10,
	ShellRespawnSeconds = 12,

	-- Match state, published as attributes on Workspace.GeneratedArena
	MatchModeAttribute = "MatchMode", -- "" | Solo | Coop | TeamBattle
	MatchStateAttribute = "MatchState",
	RoundAttribute = "Round",
	RoundMaxAttribute = "RoundMax",
	ZombiesAliveAttribute = "ZombiesAlive",
	ZombiesTotalAttribute = "ZombiesTotal",
	PlayersAliveAttribute = "PlayersAlive",
	PlayersTotalAttribute = "PlayersTotal",
	WavePhaseAttribute = "WavePhase", -- Idle | Starting | Fighting | Intermission | Victory
	CountdownAttribute = "Countdown",
	ArenaBusyAttribute = "ArenaBusy",
	RedScoreAttribute = "RedScore",
	BlueScoreAttribute = "BlueScore",
	TimeLeftAttribute = "TimeLeft",
	SuddenDeathAttribute = "SuddenDeath",
	ResultAttribute = "Result", -- text shown on the result screen

	-- Final boss (Round 7), published on Workspace.GeneratedArena
	BossActiveAttribute = "BossActive", -- the encounter runs (intro, fight or defeat scene)
	BossIntroAttribute = "BossIntro", -- "" | Silence | Reveal (intro text stage)
	BossNameAttribute = "BossName",
	BossTitleAttribute = "BossTitle",
	BossHealthAttribute = "BossHealth",
	BossMaxHealthAttribute = "BossMaxHealth",
	BossPhaseAttribute = "BossPhase", -- 1..3
	BossWarningAttribute = "BossWarning", -- current major attack warning ("" = none)
	BossWarningIdAttribute = "BossWarningId", -- increments with every new warning
	BossDefeatedAttribute = "BossDefeated",
	ArenaLightAttribute = "ArenaLight", -- -1 dark .. 0 normal .. 1 bright (client color correction)
	CrowdMoodAttribute = "CrowdMood", -- Idle | Silent | Cheer | Roar | Gasp | Celebrate
	CrowdPulseAttribute = "CrowdPulse", -- increments with every crowd reaction
	OttiTag = "OttiBoss", -- the living boss model (never a zombie)
	OttiSpectatorTag = "OttiSpectator", -- Otti watching from the imperial box (never a target)
	BossLandingAttribute = "BossLanding", -- increments when Otti lands (client camera shake)
	CrowdSpectatorTag = "CrowdSpectator", -- animal spectators in the stands (client animates them)
	IntroSeenAttribute = "BossIntroSeen", -- player attribute: may skip the intro

	-- Lobby state, published as attributes on Workspace.GeneratedLobby
	CoopRosterAttribute = "CoopRoster", -- "Name|ready|leader;..."
	RedRosterAttribute = "RedRoster", -- "Name|ready;..."
	BlueRosterAttribute = "BlueRoster",
	TeamCountdownAttribute = "TeamCountdown",

	-- Player attributes (server-owned, read by the HUD and shop)
	AuraAttribute = "Aura", -- progress, never spent: unlocks gear (CurrencyConfig)
	DenariiAttribute = "Denarii", -- money: buys unlocked gear
	EquippedWeaponAttribute = "EquippedWeapon",
	EquippedShieldAttribute = "EquippedShield",
	OwnedWeaponsAttribute = "OwnedWeapons", -- comma-separated ids
	OwnedShieldsAttribute = "OwnedShields",
	EquippedArmorAttribute = "EquippedArmor",
	OwnedArmorAttribute = "OwnedArmor",
	PreferencePrefix = "Pref_", -- saved player preferences, e.g. Pref_HudMode
	DataStatusAttribute = "DataStatus", -- Loading | Loaded | Unsaved (DataStore unavailable)
	RunKillsAttribute = "RunKills",
	RunAuraAttribute = "RunAura",
	RunDenariiAttribute = "RunDenarii",
	TeamAttribute = "Team", -- "" | Red | Blue
	InPartyAttribute = "InParty",
	ReadyAttribute = "Ready",
	EliminationsAttribute = "Eliminations",
	DeathsAttribute = "Deaths",
	AssistsAttribute = "Assists",

	RemotesFolderName = "Remotes",
	CombatActionRemoteName = "CombatAction",
	ShieldBlockRemoteName = "ShieldBlock",
	CombatFeedbackRemoteName = "CombatFeedback",
	PreferenceRemoteName = "SavePreference",
	MatchRequestRemoteName = "MatchRequest", -- RemoteFunction: Hub menu / Arena spectator requests
	MatchEventRemoteName = "MatchEvent", -- RemoteEvent: server -> client match / teleport status

	-- Multi-place (Hub / Arena)
	ArenaRoleAttribute = "ArenaRole", -- FIGHTER | SPECTATOR | ELIMINATED_SPECTATOR (server-set)
	QueueStatusAttribute = "QueueStatus", -- "" | mode id while queued (server-set)
	PartyIdAttribute = "PartyId", -- "" | party id (server-set)
	LiveBattleCountAttribute = "LiveBattles", -- Hub lobby folder: number of joinable live battles
	TeamSubModeAttribute = "TeamSubMode", -- arena folder: TIME_BATTLE | FIRST_TO | ELIMINATION
	ScoreTargetAttribute = "ScoreTarget", -- arena folder: FIRST_TO target / ELIMINATION rounds to win
	RedAliveAttribute = "RedAlive",
	BlueAliveAttribute = "BlueAlive",
	EliminationRoundAttribute = "ElimRound",
	ArenaMatchIdAttribute = "ArenaMatchId", -- arena folder: public match id (display only)
	SpectatorCountAttribute = "SpectatorCount",
	SpectatorCollisionGroup = "Spectators",
	ProjectileCollisionGroup = "ArenaProjectiles",
	EliminatedBoxTag = "EliminationBox",

	-- Combat (server-set player / character attributes, display only on clients)
	MomentumAttribute = "Momentum", -- player: 0..100
	BattleIntensityAttribute = "BattleIntensity", -- arena folder: 0..1, crowd leans in
}

return table.freeze(Config)
