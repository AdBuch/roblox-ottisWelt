--!strict
-- Play rewards: every reward pays Aura (experience -> gladiator level) AND Denarii (money, buys gear;
-- CurrencyConfig.denariiFor). The server decides who is rewarded; clients never report kills.
--   Zombie kills: the killer gets 100 %, every other player who damaged that zombie gets an
--   assist share (Co-op). A player is rewarded at most once per zombie.
--   Team Battle: fixed rewards for the winning and losing team at the end of a match.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local Config = require(ReplicatedStorage.Shared.Config)
local CurrencyConfig = require(ReplicatedStorage.Shared.CurrencyConfig)
local InventoryService = require(script.Parent.InventoryService)
local Remotes = require(script.Parent.Remotes)

export type RewardEvent = {
	reason: string,
	recipients: { { player: Player, amount: number, kind: string } },
}

local AuraService = {}

-- Pays every recipient its Aura and Denarii (`fixedDenarii` overrides the Aura-based amount).
local function grant(event: RewardEvent, fixedDenarii: number?)
	for _, recipient in event.recipients do
		local player = recipient.player
		if player.Parent and recipient.amount > 0 then
			local denarii = fixedDenarii or CurrencyConfig.denariiFor(recipient.amount)
			InventoryService.addAura(player, recipient.amount)
			InventoryService.addDenarii(player, denarii)
			player:SetAttribute(Config.RunAuraAttribute, (tonumber(player:GetAttribute(Config.RunAuraAttribute)) or 0) + recipient.amount)
			player:SetAttribute(Config.RunDenariiAttribute, (tonumber(player:GetAttribute(Config.RunDenariiAttribute)) or 0) + denarii)
			Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Aura, recipient.amount, recipient.kind, denarii)
		end
	end
end

-- Called exactly once per zombie death. `damagers` are the players who hit it (any order).
function AuraService.awardZombieKill(reward: number, killer: Player?, damagers: { Player }, assistFraction: number)
	local event: RewardEvent = { reason = "zombie", recipients = {} }
	local rewarded: { [Player]: boolean } = {}
	if killer and killer.Parent then
		table.insert(event.recipients, { player = killer, amount = reward, kind = "kill" })
		rewarded[killer] = true
		killer:SetAttribute(Config.RunKillsAttribute, (tonumber(killer:GetAttribute(Config.RunKillsAttribute)) or 0) + 1)
	end
	if assistFraction > 0 then
		for _, player in damagers do
			if not rewarded[player] and player.Parent then
				rewarded[player] = true -- once per zombie
				table.insert(event.recipients, { player = player, amount = math.max(1, math.floor(reward * assistFraction + 0.5)), kind = "assist" })
			end
		end
	end
	grant(event)
end

-- Team Battle result rewards.
function AuraService.awardMatchResult(winners: { Player }, losers: { Player }, winAmount: number, loseAmount: number)
	local event: RewardEvent = { reason = "match", recipients = {} }
	for _, player in winners do
		table.insert(event.recipients, { player = player, amount = winAmount, kind = "victory" })
	end
	for _, player in losers do
		table.insert(event.recipients, { player = player, amount = loseAmount, kind = "match" })
	end
	grant(event)
end

-- A completed zombie round: every fighter still in it gets the round reward ONCE (match id + round
-- + player are remembered, so a repeated call can never pay twice).
local paidRounds: { [string]: boolean } = {}
local paidMatch = -1

function AuraService.awardRoundComplete(players: { Player }, matchId: number, round: number)
	if matchId ~= paidMatch then
		table.clear(paidRounds) -- only the current match needs remembering
		paidMatch = matchId
	end
	local event: RewardEvent = { reason = "round", recipients = {} }
	for _, player in players do
		local key = ("%d:%d"):format(round, player.UserId)
		if player.Parent and not paidRounds[key] then
			paidRounds[key] = true
			table.insert(event.recipients, { player = player, amount = CurrencyConfig.RoundCompleteAura, kind = "round" })
		end
	end
	grant(event, CurrencyConfig.RoundCompleteDenarii)
end

-- Otti defeated (called exactly once per match by MatchService).
function AuraService.awardBossVictory(rewards: { { player: Player, amount: number } })
	local event: RewardEvent = { reason = "boss", recipients = {} }
	for _, reward in rewards do
		table.insert(event.recipients, { player = reward.player, amount = reward.amount, kind = "boss" })
	end
	grant(event)
end

function AuraService.resetRunStats(player: Player)
	player:SetAttribute(Config.RunKillsAttribute, 0)
	player:SetAttribute(Config.RunAuraAttribute, 0)
	player:SetAttribute(Config.RunDenariiAttribute, 0)
end

return AuraService
