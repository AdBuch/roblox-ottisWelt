--!strict
-- The three game modes. Only one arena match runs per server at a time.

export type ModeId = "Solo" | "Coop" | "TeamBattle"

local GameModeDefinitions = {
	Solo = table.freeze({
		Id = "Solo" :: ModeId,
		DisplayName = "SOLO ARENA",
		MinPlayers = 1,
		MaxPlayers = 1,
		RoundCounts = table.freeze({ 1, 2, 4, 8, 16, 32 }),
		MaxActiveZombies = 32,
		ShellCount = 8,
	}),

	Coop = table.freeze({
		Id = "Coop" :: ModeId,
		DisplayName = "CO-OP LEGIONS",
		MinPlayers = 1,
		MaxPlayers = 4,
		BaseRoundCounts = table.freeze({ 2, 4, 8, 12, 20, 32 }),
		-- zombie count multiplier by number of participating players (rounded up)
		PlayerScaling = table.freeze({ 0.75, 1.0, 1.25, 1.5 }),
		MaxActiveZombies = 48, -- simultaneous cap; the rest spawn as others die
		AssistRewardFraction = 0.3,
		BaseShellCount = 4,
		ShellsPerPlayer = 2,
		MaxShellCount = 12,
	}),

	TeamBattle = table.freeze({
		Id = "TeamBattle" :: ModeId,
		DisplayName = "TEAM BATTLE",
		MinPerTeam = 1,
		MaxPerTeam = 4,
		StartCountdownSeconds = 15, -- lobby: both teams ready
		ArenaCountdownSeconds = 5, -- arena: players wait at their protected team spawns
		ScoreToWin = 20,
		MatchSeconds = 8 * 60,
		RespawnSeconds = 4,
		AssistWindowSeconds = 10,
		WinAura = 80,
		LoseAura = 25,
		ShellsEnabled = false, -- competitive default; set true for symmetrical PvP healing
		ShellCount = 4,
		ResultSeconds = 8,
	}),

	VictoryReturnSeconds = 12,
	DefeatReturnSeconds = 6,
}

return table.freeze(GameModeDefinitions)
