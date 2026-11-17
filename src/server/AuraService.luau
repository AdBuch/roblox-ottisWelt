--!strict
-- Each event writes a stable per-player claim before changing the persistent balance.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local GameStates = require(ReplicatedStorage.Shared.GameStates)
local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local Config = require(ReplicatedStorage.Shared.Config)
local CurrencyConfig = require(ReplicatedStorage.Shared.CurrencyConfig)
local RewardTypes = require(ReplicatedStorage.Shared.RewardTypes)
local Recovery = require(script.Parent.RewardRecoveryService)
local InventoryService = require(script.Parent.InventoryService)
local Remotes = require(script.Parent.Remotes)

local AuraService = {}
local ACTIVITY_INTERVAL = 5

function AuraService.grant(player: Player, matchId: string, outcome: string, aura: number, denarii: number, stats: { [string]: number }?, campaign: string?, stage: number?): boolean
	local claim: RewardTypes.Claim = {
		id = RewardTypes.id(matchId, outcome, player.UserId), matchId = matchId,
		aura = aura, denarii = denarii, stats = stats or {}, campaign = campaign, stage = stage,
	}
	if not Recovery.submit(player.UserId, claim) then
		if player.Parent then
			Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Shop, "Reward claim is not confirmed yet.", false)
		end
		return false
	end
	if not player.Parent then return true end
	local committed, newClaims = Recovery.recover(player)
	if committed and newClaims and newClaims[claim.id] and aura > 0 and player.Parent then
		local kind = if outcome:find("^boss/") then "boss" elseif outcome:find("^round/") then "round"
			elseif outcome:find("^zombie/") then (if claim.stats.zombieKills then "kill" else "assist") else "match"
		Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Aura, aura, kind, denarii)
	end
	return committed
end

function AuraService.awardZombieKill(matchId: string, deathId: string, reward: number, killer: Player?, damagers: { Player }, assistFraction: number)
	local recipients: { [Player]: number } = {}
	if killer then recipients[killer] = reward end
	if assistFraction > 0 then
		for _, player in damagers do
			if not recipients[player] then recipients[player] = math.max(1, math.floor(reward * assistFraction + 0.5)) end
		end
	end
	for player, amount in recipients do
		AuraService.grant(player, matchId, "zombie/" .. deathId, amount, CurrencyConfig.denariiFor(amount),
			if player == killer then { zombieKills = 1 } else {})
	end
end

function AuraService.awardRoundComplete(players: { Player }, matchId: string, round: number)
	for _, player in players do
		AuraService.grant(player, matchId, "round/" .. tostring(round), CurrencyConfig.RoundCompleteAura, CurrencyConfig.RoundCompleteDenarii)
	end
end

function AuraService.awardBossVictory(rewards: { { player: Player, amount: number } }, matchId: string, stage: number, campaign: string?): boolean
	local confirmed = true
	for _, reward in rewards do
		local ok = AuraService.grant(reward.player, matchId, "boss/" .. tostring(stage), reward.amount,
			CurrencyConfig.denariiFor(reward.amount), if reward.amount > 0 then { bossDefeats = 1 } else {}, campaign, if campaign then stage else nil)
		confirmed = ok and confirmed
	end
	return confirmed
end

-- A battle starts for `player`: the run counters reset and the saved "last battle" begins (`mode`).
function AuraService.resetRunStats(player: Player, mode: string?, matchId: string?)
	player:SetAttribute(Config.RunKillsAttribute, 0)
	player:SetAttribute(Config.RunAuraAttribute, 0)
	player:SetAttribute(Config.RunDenariiAttribute, 0)
	if mode then
		InventoryService.beginBattle(player, mode, matchId)
	end
end

-- Active play time for the optional play-time estimate: only seconds in a fighting state
-- (MATCH_ACTIVE / ROUND_COMPLETE) count - never lobby, countdown, spectating or results.
local tracking = false
function AuraService.startActivityTracking()
	if tracking then
		return
	end
	tracking = true
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(ACTIVITY_INTERVAL)
			local now = os.clock()
			local elapsed = math.min(now - last, ACTIVITY_INTERVAL * 3) -- a stalled server never adds hours
			last = now
			for _, player in Players:GetPlayers() do
				if GameStates.isFighter(player:GetAttribute(GameStates.StateAttribute)) then
					InventoryService.addActiveSeconds(player, elapsed)
				end
			end
		end
	end)
end

return AuraService
