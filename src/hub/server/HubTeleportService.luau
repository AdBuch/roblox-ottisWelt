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
local Remotes = require(Server.Remotes)
local TeleportUtil = require(Server.TeleportUtil)

local HubTeleportService = {}
local revoking: { [string]: boolean } = {}

function HubTeleportService.isRevoking(player: Player, matchId: string): boolean
	return revoking[MatchTypes.ticketKey(matchId, player.UserId)] == true
end

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

-- Returns the players accepted for preparation.
function HubTeleportService.send(players: { Player }, options: Options): { Player }
	local function failed(player: Player, code: string)
		local key = MatchTypes.ticketKey(options.matchId, player.UserId)
		revoking[key] = true
		if player.Parent then
			HubTeleportService.message(player, (MatchTypes.Messages :: any)[code] or MatchTypes.Messages.TELEPORT_FAILED, false)
		end
		-- Clear local locks promptly, even if the ticket store is slow.
		task.spawn(options.onFailed, player, code)
		local ok = pcall(AdmissionTicketService.revoke, options.matchId, player.UserId)
		revoking[key] = nil
		if not ok then warn("[OttiArena][Hub]", "Travel ticket cleanup failed") end
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

	local payload: MatchTypes.TeleportPayload = { kind = "ToArena", matchId = options.matchId, mode = options.mode }
	local accepted = TeleportUtil.toReserved(players, function()
		local connection = MatchRecordService.getConnection(options.matchId)
		return if connection then connection.accessCode else nil
	end, payload, failed)
	local skipped: { [Player]: boolean } = {}
	for _, player in players do
		if not skipped[player] and not table.find(accepted, player) and not TeleportUtil.isForMatch(player, options.matchId) then
			skipped[player] = true
			task.spawn(failed, player, if player.Parent then "TELEPORT_FAILED" else "LEFT")
		end
	end
	return accepted
end

return HubTeleportService
