--!strict
-- TIME BATTLE rules: the clock runs TeamModeDefinitions.TIME_BATTLE.DurationSeconds; every valid
-- opposing elimination scores; respawn after 4 s with 2 s protection (core + MatchSpawnService).
-- When time runs out the higher score wins; a tie goes to SUDDEN DEATH (next valid opposing
-- elimination wins). HUD: RED 8 — 7 BLUE  04:12.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TeamModeDefinitions = require(ReplicatedStorage.Shared.TeamModeDefinitions)
local TeamBattleService = require(script.Parent.Parent.TeamBattleService)

type Context = TeamBattleService.Context

local TimeBattleService: TeamBattleService.Rules = {
	respawns = true,
	setup = function(ctx: Context)
		ctx.timeLeft = TeamModeDefinitions.TIME_BATTLE.DurationSeconds
	end,
	onSecond = function(ctx: Context)
		if ctx.suddenDeath or ctx.finished then
			return
		end
		ctx.timeLeft = math.max(0, ctx.timeLeft - 1)
		if ctx.timeLeft == 0 then
			if ctx.score.Red ~= ctx.score.Blue then
				ctx.finish(if ctx.score.Red > ctx.score.Blue then "Red" else "Blue", "time")
			else
				ctx.suddenDeath = true
				ctx.broadcast("SUDDEN DEATH: next elimination wins!")
				ctx.publish()
			end
		end
	end,
	onDeath = function(ctx: Context, _victim: Player, killerTeam)
		if not killerTeam or ctx.finished then
			return
		end
		ctx.score[killerTeam] += 1
		if ctx.suddenDeath then
			ctx.finish(killerTeam, "sudden death")
		end
	end,
}

return TimeBattleService
