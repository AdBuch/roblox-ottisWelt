--!strict
-- Arena -> Hub. After the result sequence (or on request) every player is sent back:
--   flush validated rewards (PlayerDataService.flush) -> freeze the profile (beginTransfer) ->
--   TeleportUtil.toHub (retries) -> on failure the client shows the emergency RETURN TO HUB button
-- Rewards are already paid once by MatchService; nothing here grants anything. Spectators return
-- near the live-battle board (payload.fromSpectating, display hint only).
-- Mock mode (Studio): nothing is teleported; players stay and see "STUDIO MOCK".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local Config = require(ReplicatedStorage.Shared.Config)
local EnvironmentConfig = require(ReplicatedStorage.Shared.EnvironmentConfig)
local MatchTypes = require(ReplicatedStorage.Shared.MatchTypes)
local Server = script.Parent.Parent
local PlayerDataService = require(Server.PlayerDataService)
local Remotes = require(Server.Remotes)
local TeleportUtil = require(Server.TeleportUtil)

local PREFIX = "[OttiArena][Arena]"

local ArenaReturnService = {}

local returning: { [Player]: boolean } = {}

local function message(player: Player, text: string, ok: boolean)
	Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Shop, text, ok)
	Remotes.MatchEvent:FireClient(player, "Status", text, ok)
end

-- Sends one group back (same payload). `code` = a MatchTypes.Messages key shown in the Hub.
function ArenaReturnService.send(players: { Player }, code: string?)
	if not EnvironmentConfig.canTeleport() then
		for _, player in players do
			message(player, "STUDIO MOCK: the return to the Hub is skipped in Studio", true)
		end
		return
	end
	local spectators, fighters = {}, {}
	for _, player in players do
		if player.Parent and not returning[player] then
			returning[player] = true
			PlayerDataService.flush(player)
			PlayerDataService.beginTransfer(player)
			Remotes.MatchEvent:FireClient(player, "Teleport", "Returning", "HUB")
			local role = player:GetAttribute(Config.ArenaRoleAttribute)
			table.insert(if role == "FIGHTER" then fighters else spectators, player)
		end
	end
	local function failed(player: Player, failCode: string)
		returning[player] = nil
		PlayerDataService.cancelTransfer(player)
		message(player, (MatchTypes.Messages :: any)[failCode] or MatchTypes.Messages.TELEPORT_FAILED, false)
		Remotes.MatchEvent:FireClient(player, "ReturnFailed")
	end
	if #fighters > 0 then
		TeleportUtil.toHub(fighters, { kind = "ToHub", message = code, fromSpectating = false }, failed)
	end
	if #spectators > 0 then
		TeleportUtil.toHub(spectators, { kind = "ToHub", message = code, fromSpectating = true }, failed)
	end
end

-- Everyone on this server goes back; anyone still here is retried a few times.
function ArenaReturnService.returnAll(code: string?)
	ArenaReturnService.send(Players:GetPlayers(), code)
	if not EnvironmentConfig.canTeleport() then
		return
	end
	task.spawn(function()
		for _ = 1, 6 do
			task.wait(15)
			local left = {}
			for _, player in Players:GetPlayers() do
				if not returning[player] then
					table.insert(left, player)
				end
			end
			if #left == 0 then
				return
			end
			print(PREFIX, ("Retrying the return of %d player(s)"):format(#left))
			ArenaReturnService.send(left, code)
		end
	end)
end

-- RETURN TO HUB button / door (spectators any time, fighters after their part is over).
function ArenaReturnService.request(player: Player)
	returning[player] = nil -- emergency retry allowed
	ArenaReturnService.send({ player }, nil)
end

function ArenaReturnService.init()
	Players.PlayerRemoving:Connect(function(player)
		returning[player] = nil
	end)
end

return ArenaReturnService
