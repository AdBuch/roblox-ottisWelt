--!strict
-- Arena return policy and feedback. TeleportUtil owns profile preparation and retries.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local Config = require(ReplicatedStorage.Shared.Config)
local EnvironmentConfig = require(ReplicatedStorage.Shared.EnvironmentConfig)
local MatchTypes = require(ReplicatedStorage.Shared.MatchTypes)
local Server = script.Parent.Parent
local Remotes = require(Server.Remotes)
local TeleportUtil = require(Server.TeleportUtil)

local ArenaReturnService = {}

local function failed(player: Player, code: string)
	if player.Parent then
		local text = (MatchTypes.Messages :: any)[code] or MatchTypes.Messages.TELEPORT_FAILED
		Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Shop, text, false)
		Remotes.MatchEvent:FireClient(player, "ReturnFailed", text)
	end
end

function ArenaReturnService.send(players: { Player }, code: string?)
	if not EnvironmentConfig.canTeleport() then
		for _, player in players do
			Remotes.MatchEvent:FireClient(player, "Teleport", "Mock")
		end
		return
	end
	local spectators, fighters = {}, {}
	for _, player in players do
		local role = player:GetAttribute(Config.ArenaRoleAttribute)
		table.insert(if role == "FIGHTER" then fighters else spectators, player)
	end
	if #fighters > 0 then
		TeleportUtil.toHub(fighters, { kind = "ToHub", message = code, fromSpectating = false }, failed)
	end
	if #spectators > 0 then
		TeleportUtil.toHub(spectators, { kind = "ToHub", message = code, fromSpectating = true }, failed)
	end
end

function ArenaReturnService.returnAll(code: string?)
	ArenaReturnService.send(Players:GetPlayers(), code)
end

function ArenaReturnService.request(player: Player)
	if player:GetAttribute(Config.TeleportStateAttribute) == "Failed" and TeleportUtil.isPending(player) then
		failed(player, "TELEPORT_TIMEOUT")
		return
	end
	ArenaReturnService.send({ player }, nil)
end

return ArenaReturnService
