--!strict
-- FIRST TO rules: the first team to the target wins. The target depends on the larger team at
-- match start (TeamModeDefinitions.FIRST_TO.Targets: 1v1 10, 2v2 15, 3v3 / 4v4 20). Respawn after
-- 4 s with 2 s protection. Optional safety timeout (12 min): the higher score wins, a tie goes to
-- SUDDEN DEATH. HUD: FIRST TO 20 · RED 13 — 11 BLUE.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TeamModeDefinitions = require(ReplicatedStorage.Shared.TeamModeDefinitions)
local TeamBattleService = require(script.Parent.Parent.TeamBattleService)

type Context = TeamBattleService.Context

local FirstToKillsService: TeamBattleService.Rules = {
	respawns = true,
	setup = function(ctx: Context)
		ctx.target = TeamModeDefinitions.firstToTarget(ctx.teamSize)
		local timeout = TeamModeDefinitions.FIRST_TO.SafetyTimeoutSeconds
		ctx.timeLeft = if timeout > 0 then timeout else -1
	end,
	onSecond = function(ctx: Context)
		if ctx.timeLeft < 0 or ctx.suddenDeath or ctx.finished then
			return
		end
		ctx.timeLeft = math.max(0, ctx.timeLeft - 1)
		if ctx.timeLeft == 0 then
			if ctx.score.Red ~= ctx.score.Blue then
				ctx.finish(if ctx.score.Red > ctx.score.Blue then "Red" else "Blue", "timeout")
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
		elseif ctx.score[killerTeam] >= ctx.target then
			ctx.finish(killerTeam, "target reached")
		end
	end,
}

return FirstToKillsService
