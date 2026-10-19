--!strict
-- Rules of the three Team Battle submodes (1v1 to 4v4, no friendly fire in every mode).
--   TIME_BATTLE  respawn after 4 s (2 s protection); more eliminations when the clock runs out
--                wins; a tie goes to SUDDEN DEATH (next valid opposing elimination wins).
--   FIRST_TO     respawn as above; first team to the target wins (target by team size); after
--                the safety timeout the higher score wins, a tie goes to SUDDEN DEATH.
--   ELIMINATION  one life per player per round, Best of 5 (first to 3 round wins); the round ends
--                when a team has no living fighter; near-simultaneous wipes are a draw. Eliminated
--                players follow living teammates only; everyone returns next round.

local TeamModeDefinitions = {
	Common = table.freeze({
		MinPerTeam = 1,
		MaxPerTeam = 4,
		ArenaCountdownSeconds = 5, -- protected team spawns behind barriers
		RespawnSeconds = 4,
		SpawnProtectionSeconds = 2,
		AssistWindowSeconds = 10,
		WinAura = 80,
		LoseAura = 25,
		DrawAura = 40,
		ResultSeconds = 8,
		ShellsEnabled = false,
		ShellCount = 4,
	}),

	TIME_BATTLE = table.freeze({
		DurationSeconds = 8 * 60,
	}),

	FIRST_TO = table.freeze({
		-- target by the larger team size at match start
		Targets = table.freeze({ [1] = 10, [2] = 15, [3] = 20, [4] = 20 }),
		SafetyTimeoutSeconds = 12 * 60, -- 0 = no timeout
	}),

	ELIMINATION = table.freeze({
		RoundsToWin = 3, -- Best of 5
		MaxRounds = 9, -- safety cap when rounds keep ending in draws
		RoundCountdownSeconds = 5,
		LoadoutConfirmSeconds = 6, -- between rounds: equipment shown and locked
		RoundTimeLimitSeconds = 150, -- then the team with more living fighters wins (equal: draw)
		DrawWindowSeconds = 0.75, -- both teams wiped within this window = draw
	}),
}

-- Target score for FIRST_TO with the given team size.
function TeamModeDefinitions.firstToTarget(teamSize: number): number
	local targets = TeamModeDefinitions.FIRST_TO.Targets :: { [number]: number }
	return targets[math.clamp(teamSize, 1, 4)] or 20
end

return table.freeze(TeamModeDefinitions)
