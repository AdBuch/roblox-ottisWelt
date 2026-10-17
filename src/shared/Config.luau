--!strict
-- Shared tuning values and names used by both server and client.

local Config = {
	ArenaFolderName = "GeneratedArena",
	ArenaRadius = 40,

	ShellCount = 3,
	ShellNamePrefix = "GoldenShell_",
	-- Player attribute set by the server per collected shell, e.g. "CollectedShell_2"
	ShellAttributePrefix = "CollectedShell_",
	ShellPickupRange = 8,

	DummyName = "RomanZombie",
	DummyMaxHealth = 30,
	DummyRespawnSeconds = 5,
	-- Player attribute set by the server once the player helped defeat the dummy
	ZombieDefeatedAttribute = "DefeatedZombie",

	AttackDamage = 10,
	AttackRange = 8,
	AttackCooldown = 0.5,

	RemotesFolderName = "Remotes",
	AttackRemoteName = "Attack",
}

return table.freeze(Config)
