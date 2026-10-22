--!strict
-- ELIMINATION rules (Best of 5, first to 3 round wins):
--   * one life per player per round: a defeated player respawns in the closed waiting box
--     (zone ELIMINATED, role ELIMINATED_SPECTATOR) and may only follow living teammates
--   * the round ends when one team has no living fighter; if the other team is wiped within
--     DrawWindowSeconds too, the round is a draw (no point)
--   * round time limit: the team with more living fighters wins the round, equal = draw
--   * between rounds: the loadout is shown and locked (LoadoutConfirmSeconds), everybody
--     respawns at the team spawns behind closed barriers, RoundCountdownSeconds, FIGHT
--   * after MaxRounds (only reachable through draws) the team with more round wins wins,
--     equal = draw
-- HUD: ELIMINATION · RED 2 — 1 BLUE · ALIVE 3 — 2.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local TeamModeDefinitions = require(ReplicatedStorage.Shared.TeamModeDefinitions)
local Server = script.Parent.Parent
local MomentumConfig = require(ReplicatedStorage.Shared.MomentumConfig)
local MomentumService = require(Server.MomentumService)
local Remotes = require(Server.Remotes)
local TeamBattleService = require(Server.TeamBattleService)

type Context = TeamBattleService.Context

local RULES = TeamModeDefinitions.ELIMINATION

local roundClock = 0
local roundEnding = false
local roundToken = 0

local startRound: (ctx: Context) -> ()

local function loadoutCard(ctx: Context)
	for player in ctx.teamOf do
		if player.Parent then
			local weapon = tostring(player:GetAttribute(Config.EquippedWeaponAttribute) or "-")
			local shield = tostring(player:GetAttribute(Config.EquippedShieldAttribute) or "-")
			local armor = tostring(player:GetAttribute(Config.EquippedArmorAttribute) or "-")
			Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Shop, ("ROUND %d · LOADOUT LOCKED: %s · %s · %s"):format(ctx.round + 1, weapon, shield, armor), true)
		end
	end
end

local function endRound(ctx: Context, winner: string?, reason: string)
	if ctx.finished then
		return
	end
	roundToken += 1
	ctx.setActive(false)
	if winner == "Red" or winner == "Blue" then
		ctx.score[winner] += 1
		ctx.broadcast(("ROUND %d: %s WINS (%s)"):format(ctx.round, winner:upper(), reason))
	else
		ctx.broadcast(("ROUND %d: DRAW"):format(ctx.round))
	end
	ctx.publish()
	if ctx.score.Red >= RULES.RoundsToWin or ctx.score.Blue >= RULES.RoundsToWin then
		ctx.finish(if ctx.score.Red > ctx.score.Blue then "Red" else "Blue", "rounds")
		return
	end
	if ctx.round >= RULES.MaxRounds then
		ctx.finish(if ctx.score.Red > ctx.score.Blue then "Red" elseif ctx.score.Blue > ctx.score.Red then "Blue" else "Draw", "round limit")
		return
	end
	loadoutCard(ctx)
	local myToken = roundToken
	task.delay(RULES.LoadoutConfirmSeconds, function()
		if ctx.stillCurrent() and roundToken == myToken then
			startRound(ctx)
		end
	end)
end

local function checkRoundEnd(ctx: Context)
	if roundEnding or not ctx.active or ctx.finished then
		return
	end
	local red, blue = ctx.livingCount("Red"), ctx.livingCount("Blue")
	if red > 0 and blue > 0 then
		return
	end
	roundEnding = true
	local myToken = roundToken
	-- Wait a moment: a nearly simultaneous wipe of the other team is a draw
	task.delay(RULES.DrawWindowSeconds, function()
		roundEnding = false
		if not ctx.stillCurrent() or roundToken ~= myToken then
			return
		end
		local r, b = ctx.livingCount("Red"), ctx.livingCount("Blue")
		if r == 0 and b == 0 then
			endRound(ctx, nil, "both teams fell")
		elseif r == 0 then
			endRound(ctx, "Blue", "team eliminated")
		elseif b == 0 then
			endRound(ctx, "Red", "team eliminated")
		end
	end)
end

startRound = function(ctx: Context)
	if ctx.finished then
		return
	end
	roundToken += 1
	local myToken = roundToken
	ctx.round += 1
	roundClock = RULES.RoundTimeLimitSeconds
	ctx.timeLeft = roundClock
	ctx.respawnAll() -- back at the team spawns (barriers closed, countdown state)
	for player in ctx.teamOf do
		MomentumService.reset(player, MomentumConfig.Start.EliminationRound) -- every round starts with an empty passive energy pool
	end
	ctx.setActive(false)
	ctx.publish()
	local folder = Workspace:FindFirstChild(Config.ArenaFolderName)
	task.spawn(function()
		for remaining = RULES.RoundCountdownSeconds, 1, -1 do
			if not ctx.stillCurrent() or roundToken ~= myToken then
				return
			end
			if folder then
				folder:SetAttribute(Config.CountdownAttribute, remaining)
			end
			task.wait(1)
		end
		if folder then
			folder:SetAttribute(Config.CountdownAttribute, 0)
		end
		if ctx.stillCurrent() and roundToken == myToken then
			ctx.setActive(true)
			ctx.broadcast(("ROUND %d — FIGHT!"):format(ctx.round))
			ctx.publish()
		end
	end)
end

local EliminationService: TeamBattleService.Rules = {
	respawns = false,
	setup = function(ctx: Context)
		ctx.target = RULES.RoundsToWin
		ctx.round = 1
		ctx.timeLeft = RULES.RoundTimeLimitSeconds
		roundClock = RULES.RoundTimeLimitSeconds
		roundEnding = false
		roundToken += 1
	end,
	onSecond = function(ctx: Context)
		if not ctx.active or ctx.finished then
			return
		end
		roundClock = math.max(0, roundClock - 1)
		ctx.timeLeft = roundClock
		if roundClock == 0 then
			local red, blue = ctx.livingCount("Red"), ctx.livingCount("Blue")
			endRound(ctx, if red > blue then "Red" elseif blue > red then "Blue" else nil, "time")
			return
		end
		checkRoundEnd(ctx)
	end,
	onDeath = function(ctx: Context, _victim: Player, _killerTeam)
		checkRoundEnd(ctx)
	end,
}

return EliminationService
