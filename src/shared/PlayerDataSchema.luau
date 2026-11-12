--!strict
-- The saved player profile schema, used by BOTH places (InventoryService migrates and validates,
-- PlayerDataService stores). Saved data is independent of code builds and GameProtocol:
--   * the DataStore name per environment never changes for normal updates (ExperienceConfig)
--   * Version only increases; InventoryService.migrateProfile moves every older profile forward,
--     keeps Aura and owned items, adds missing fields and re-validates equipped items
-- Persisted: Aura (progress), Denarii (money), owned + equipped weapon/shield/armor, statistics,
-- victories, preferences.
-- Never persisted: health, round, match score, match id, cooldowns, projectiles, buffs, positions.
--
-- History: v1 coins -> v2 auraPoints -> v3 armor + preferences -> v4 statistics -> v5 Denarii (Aura
-- becomes progress that unlocks gear, Denarii buy it; CurrencyConfig) -> v6 Aura is experience for the
-- gladiator level (GladiatorLevelDefinitions; levels are derived, not stored), the ControlMode and
-- BloodFx preferences are gone (dropped on load), optional resetToken (PlayerDataResetConfig).
-- v5 -> v6 needs no data change. A controlled test-data reset is prepared (off by default).
-- v7: per-weapon special practice attempts.
-- v8: the career grows to 150 levels (still derived from Aura: nobody loses Aura, Denarii or items;
-- owned gear stays usable even if its LevelRequired rose) and the profile gets its own earnings
-- history: `earnings` (Aura / Denarii EARNED since `since`; `complete` only for profiles tracked
-- from their start), `session` (current play session across teleports), `lastBattle` and
-- `activity` (active fighting seconds + Aura for the play-time estimate). Old profiles start these
-- at 0 - no invented history. The migration only creates missing tables, so it can run repeatedly.
-- v9: `forge` (weapon id -> improvement stage from the forge of Rome, ForgeDefinitions). Older
-- profiles start with no improved weapon; unknown ids are dropped and stages are clamped.
-- v10: weapon COPIES (`weaponCopies`: weapon id -> list of { uid, forge, wear, design, job }),
-- `activeCopy`, `nextCopy`, `shieldDesigns`, `forgeCredits` (Robux-bought Skip / Design) and
-- `receipts` (processed Robux purchase ids). The v9 `forge` stage moves onto each owned weapon's
-- first copy; every owned weapon gets one copy. Nothing is taken away.

local PlayerDataSchema = {
	Version = 10,

	-- A new play session starts when the profile was not seen for this long (teleports take seconds)
	SessionGapSeconds = 20 * 60,

	-- The optional play-time estimate needs real data: at least this many rewards AND this much
	-- active fighting time (lobby waiting never counts). Below that the UI shows no time at all.
	Estimate = table.freeze({ MinRewards = 25, MinActiveSeconds = 15 * 60 }),

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
		"introSeen", -- Hub intro: the last stage shown (LobbyIntroService)
	}),

	-- Preferences a client may store (value must be one of the listed strings)
	Preferences = table.freeze({
		HudMode = table.freeze({ "Full", "Minimal", "Hidden" }),
		BossIntro = table.freeze({ "Seen", "" }),
		CameraShake = table.freeze({ "Full", "Reduced", "Off" }),
	}),
}

function PlayerDataSchema.isStat(key: unknown): boolean
	return typeof(key) == "string" and table.find(PlayerDataSchema.Stats, key) ~= nil
end

return table.freeze(PlayerDataSchema)
