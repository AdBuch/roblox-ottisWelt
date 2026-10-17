--!strict
-- Shared names and arena/shell values used by both server and client.
-- Combat tuning lives in CombatConfig.

local Config = {
	ArenaFolderName = "GeneratedArena",
	ArenaRadius = 40,

	ShellCount = 3,
	ShellNamePrefix = "GoldenShell_",
	-- Player attribute set by the server per collected shell, e.g. "CollectedShell_2"
	ShellAttributePrefix = "CollectedShell_",
	ShellPickupRange = 8,

	-- Player attribute set by the server once the player helped defeat the zombie
	ZombieDefeatedAttribute = "DefeatedZombie",

	RemotesFolderName = "Remotes",
	SwordAttackRemoteName = "SwordAttack",
	ShieldBlockRemoteName = "ShieldBlock",
	CombatFeedbackRemoteName = "CombatFeedback",
}

return table.freeze(Config)
