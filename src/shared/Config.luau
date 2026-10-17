--!strict
-- Shared names: folders, attributes, remotes, shells.
-- Combat tuning: CombatConfig. Items: WeaponDefinitions / ShieldDefinitions.
-- Enemies: ZombieDefinitions. Rounds: RoundDefinitions. States: GameStates.

local Config = {
	ArenaFolderName = "GeneratedArena",
	LobbyFolderName = "GeneratedLobby",
	ZombiesFolderName = "Zombies",
	ShopItemTag = "OttiShopItem",

	-- Healing shells
	ShellCount = 4,
	ShellNamePrefix = "GoldenShell_",
	ShellPickupRange = 8,
	ShellHealAmount = 3,
	ShellRespawnSeconds = 12,

	-- Run state, published as attributes on Workspace.GeneratedArena
	RoundAttribute = "Round",
	RoundMaxAttribute = "RoundMax",
	ZombiesAliveAttribute = "ZombiesAlive",
	ZombiesTotalAttribute = "ZombiesTotal",
	WavePhaseAttribute = "WavePhase", -- Idle | Starting | Fighting | Intermission | Victory
	CountdownAttribute = "Countdown",
	ArenaBusyAttribute = "ArenaBusy",
	FighterNameAttribute = "FighterName",

	-- Player attributes (server-owned, read by the HUD and shop)
	CoinsAttribute = "Coins",
	EquippedWeaponAttribute = "EquippedWeapon",
	EquippedShieldAttribute = "EquippedShield",
	OwnedWeaponsAttribute = "OwnedWeapons", -- comma-separated ids
	OwnedShieldsAttribute = "OwnedShields",
	RunKillsAttribute = "RunKills",
	RunCoinsAttribute = "RunCoins",

	RemotesFolderName = "Remotes",
	WeaponAttackRemoteName = "WeaponAttack",
	ShieldBlockRemoteName = "ShieldBlock",
	CombatFeedbackRemoteName = "CombatFeedback",
}

return table.freeze(Config)
