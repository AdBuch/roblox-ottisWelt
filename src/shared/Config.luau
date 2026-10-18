--!strict
-- Shared names: folders, tags, attributes, remotes, shells.
-- Combat tuning: CombatConfig. Items: WeaponDefinitions / ShieldDefinitions / SpecialMoveDefinitions /
-- ComboDefinitions. Enemies: ZombieDefinitions / ZombieAIProfiles. Modes: GameModeDefinitions.

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
	ShellHealAmount = 3,
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
	BossHealthAttribute = "BossHealth",
	BossMaxHealthAttribute = "BossMaxHealth",
	BossPhaseAttribute = "BossPhase", -- 1..3
	BossWarningAttribute = "BossWarning", -- current major attack warning ("" = none)
	BossWarningIdAttribute = "BossWarningId", -- increments with every new warning
	BossDefeatedAttribute = "BossDefeated",
	ArenaLightAttribute = "ArenaLight", -- -1 dark .. 0 normal .. 1 bright (client color correction)
	CrowdMoodAttribute = "CrowdMood", -- Idle | Silent | Cheer | Roar | Gasp | Celebrate
	CrowdPulseAttribute = "CrowdPulse", -- increments with every crowd reaction
	DamageFxModeAttribute = "DamageFxMode", -- STYLIZED | REDUCED | OFF (HUD display)
	OttiTag = "OttiBoss", -- the living boss model (never a zombie)
	CrowdSpectatorTag = "CrowdSpectator", -- animal spectators in the stands (client animates them)
	IntroSeenAttribute = "BossIntroSeen", -- player attribute: may skip the intro

	-- Lobby state, published as attributes on Workspace.GeneratedLobby
	CoopRosterAttribute = "CoopRoster", -- "Name|ready|leader;..."
	RedRosterAttribute = "RedRoster", -- "Name|ready;..."
	BlueRosterAttribute = "BlueRoster",
	TeamCountdownAttribute = "TeamCountdown",

	-- Player attributes (server-owned, read by the HUD and shop)
	AuraAttribute = "Aura",
	EquippedWeaponAttribute = "EquippedWeapon",
	EquippedShieldAttribute = "EquippedShield",
	OwnedWeaponsAttribute = "OwnedWeapons", -- comma-separated ids
	OwnedShieldsAttribute = "OwnedShields",
	RunKillsAttribute = "RunKills",
	RunAuraAttribute = "RunAura",
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
}

return table.freeze(Config)
