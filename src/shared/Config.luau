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
