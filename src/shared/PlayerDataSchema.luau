--!strict
-- The saved player profile schema, used by BOTH places (InventoryService migrates and validates,
-- PlayerDataService stores). Saved data is independent of code builds and GameProtocol:
--   * the DataStore name per environment never changes for normal updates (ExperienceConfig)
--   * Version only increases; InventoryService.migrateProfile moves every older profile forward,
--     keeps Aura and owned items, adds missing fields and re-validates equipped items
-- Persisted: Aura, owned + equipped weapon/shield/armor, statistics, victories, preferences.
-- Never persisted: health, round, match score, match id, cooldowns, projectiles, buffs, positions.
--
-- History: v1 coins -> v2 auraPoints -> v3 armor + preferences -> v4 statistics.

local PlayerDataSchema = {
	Version = 4,

	-- Statistics (whole numbers, only ever increased by the server)
	Stats = table.freeze({
		"zombieKills",
		"bossDefeats",
		"zombieRuns",
		"soloVictories",
		"coopVictories",
		"teamMatches",
		"teamVictories",
		"eliminations",
		"deaths",
		"matchesSpectated",
	}),

	-- Preferences a client may store (value must be one of the listed strings)
	Preferences = table.freeze({
		HudMode = table.freeze({ "Full", "Minimal", "Hidden" }),
		BossIntro = table.freeze({ "Seen", "" }),
		ControlMode = table.freeze({ "Classic", "Wild" }),
		BloodFx = table.freeze({ "Auto", "Stylized", "Reduced", "Off" }),
		CameraShake = table.freeze({ "Full", "Reduced", "Off" }),
	}),
}

function PlayerDataSchema.isStat(key: unknown): boolean
	return typeof(key) == "string" and table.find(PlayerDataSchema.Stats, key) ~= nil
end

return table.freeze(PlayerDataSchema)
