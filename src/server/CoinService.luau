--!strict
-- Coin rewards for zombie kills. The server decides who is rewarded; clients never report kills.
-- Each reward is built as a RewardEvent so assists or shared multiplayer rewards can later be
-- added by filling in more recipients.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local Config = require(ReplicatedStorage.Shared.Config)
local ZombieDefinitions = require(ReplicatedStorage.Shared.ZombieDefinitions)
local InventoryService = require(script.Parent.InventoryService)
local Remotes = require(script.Parent.Remotes)

type ZombieDefinition = ZombieDefinitions.ZombieDefinition

export type RewardEvent = {
	zombieId: string,
	killer: Player?,
	recipients: { { player: Player, amount: number } },
}

local CoinService = {}

local function buildRewardEvent(def: ZombieDefinition, killer: Player?): RewardEvent
	local event: RewardEvent = { zombieId = def.Id, killer = killer, recipients = {} }
	-- Single-player prototype: the killing player receives the full reward.
	if killer and killer.Parent then
		table.insert(event.recipients, { player = killer, amount = def.Coins })
	end
	return event
end

-- Called exactly once per zombie death (ZombieService guarantees one death callback).
function CoinService.awardKill(def: ZombieDefinition, killer: Player?)
	local event = buildRewardEvent(def, killer)
	for _, recipient in event.recipients do
		local player = recipient.player
		InventoryService.addCoins(player, recipient.amount)
		player:SetAttribute(Config.RunCoinsAttribute, (tonumber(player:GetAttribute(Config.RunCoinsAttribute)) or 0) + recipient.amount)
		Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Coins, recipient.amount)
	end
	if killer and killer.Parent then
		killer:SetAttribute(Config.RunKillsAttribute, (tonumber(killer:GetAttribute(Config.RunKillsAttribute)) or 0) + 1)
	end
end

function CoinService.resetRunStats(player: Player)
	player:SetAttribute(Config.RunKillsAttribute, 0)
	player:SetAttribute(Config.RunCoinsAttribute, 0)
end

return CoinService
