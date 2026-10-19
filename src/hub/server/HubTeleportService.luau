--!strict
-- Hub -> Arena travel for fighters and spectators. For every player:
--   1. the profile is flushed and frozen (PlayerDataService.beginTransfer)
--   2. TeleportUtil.toReserved with the access code read from the server-only ConnectionRecord
--   3. on failure: the profile unfreezes, the ticket is revoked, the caller's onFailed releases
--      reservations / party locks, and the player gets a compact message
-- Mock mode never teleports: it reports "STUDIO MOCK" and undoes everything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local MatchTypes = require(ReplicatedStorage.Shared.MatchTypes)
local Server = script.Parent.Parent
local AdmissionTicketService = require(Server.AdmissionTicketService)
local MatchRecordService = require(Server.MatchRecordService)
local PlayerDataService = require(Server.PlayerDataService)
local Remotes = require(Server.Remotes)
local TeleportUtil = require(Server.TeleportUtil)

local PREFIX = "[OttiArena][Hub]"

local HubTeleportService = {}

function HubTeleportService.message(player: Player, text: string, ok: boolean?)
	Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Shop, text, ok == true)
	Remotes.MatchEvent:FireClient(player, "Status", text, ok == true)
end

export type Options = {
	matchId: string,
	role: MatchTypes.Role,
	mode: string,
	mock: boolean,
	onFailed: (player: Player, code: string) -> (), -- release slots / unlock party / requeue
}

-- Sends `players` to the reserved server of `matchId`. Returns the players that were sent.
function HubTeleportService.send(players: { Player }, options: Options): { Player }
	local function failed(player: Player, code: string)
		PlayerDataService.cancelTransfer(player)
		AdmissionTicketService.revoke(options.matchId, player.UserId)
		HubTeleportService.message(player, (MatchTypes.Messages :: any)[code] or MatchTypes.Messages.TELEPORT_FAILED, false)
		Remotes.MatchEvent:FireClient(player, "Teleport", "Failed", code)
		options.onFailed(player, code)
	end

	if options.mock then
		for _, player in players do
			HubTeleportService.message(player, ("STUDIO MOCK: %s match %s created — no teleport in Studio. Open the Arena place to test the match."):format(options.mode, options.matchId:sub(1, 14)), true)
			Remotes.MatchEvent:FireClient(player, "Teleport", "Mock", options.mode)
			AdmissionTicketService.revoke(options.matchId, player.UserId)
			options.onFailed(player, "MOCK")
		end
		return {}
	end

	local connection = MatchRecordService.getConnection(options.matchId)
	if not connection then
		for _, player in players do
			failed(player, "UNREACHABLE")
		end
		return {}
	end
	local ready = {}
	for _, player in players do
		if player.Parent and PlayerDataService.beginTransfer(player) then
			table.insert(ready, player)
			Remotes.MatchEvent:FireClient(player, "Teleport", "Travelling", options.mode)
		elseif player.Parent then
			failed(player, "TELEPORT_FAILED")
		end
	end
	if #ready == 0 then
		return {}
	end
	local payload: MatchTypes.TeleportPayload = { kind = "ToArena", matchId = options.matchId, role = options.role, mode = options.mode }
	if not TeleportUtil.toReserved(ready, connection.accessCode, payload, failed) then
		-- toReserved already reported each failed player (or we are in mock mode)
		print(PREFIX, ("Teleport to %s did not start for %d player(s)"):format(options.matchId, #ready))
	end
	return ready
end

return HubTeleportService
