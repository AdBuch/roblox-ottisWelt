--!strict
-- WATCH (a chosen match) and WATCH RANDOM, all server-side:
--   1. re-read the registry record (joinable, not stale / completed / private, compatible)
--   2. reserve one spectator slot atomically (SpectatorSlotService, MemoryStore UpdateAsync)
--   3. issue a one-time SPECTATOR ticket, flush + freeze the profile, teleport
--   4. any failure releases the slot, revokes the ticket and shows a compact message
-- Spectators earn nothing and change nothing in their progression.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnvironmentConfig = require(ReplicatedStorage.Shared.EnvironmentConfig)
local GameStates = require(ReplicatedStorage.Shared.GameStates)
local MatchTypes = require(ReplicatedStorage.Shared.MatchTypes)
local Server = script.Parent.Parent
local AdmissionTicketService = require(Server.AdmissionTicketService)
local MatchRegistryService = require(Server.MatchRegistryService)
local SpectatorSlotService = require(Server.SpectatorSlotService)
local HubTeleportService = require(script.Parent.HubTeleportService)
local LiveBattlesService = require(script.Parent.LiveBattlesService)
local MatchmakingService = require(script.Parent.MatchmakingService)
local PartyService = require(script.Parent.PartyService)

local SpectatorJoinService = {}

local busy: { [Player]: boolean } = {}

local function watchRecord(player: Player, record: MatchTypes.RegistryRecord): (boolean, string)
	local result = SpectatorSlotService.reserve(record.matchId, player.UserId)
	if result == "FULL" then
		return false, MatchTypes.Messages.FULL
	elseif result == "ENDED" then
		return false, MatchTypes.Messages.ENDED
	elseif result ~= "OK" then
		return false, MatchTypes.Messages.UNREACHABLE
	end
	if not AdmissionTicketService.issue(record.matchId, player.UserId, "SPECTATOR", "", record.mode) then
		SpectatorSlotService.release(record.matchId, player.UserId)
		return false, MatchTypes.Messages.UNREACHABLE
	end
	local mock = LiveBattlesService.isMock(record.matchId) or not EnvironmentConfig.canTeleport()
	HubTeleportService.send({ player }, {
		matchId = record.matchId,
		role = "SPECTATOR",
		mode = record.mode,
		mock = mock,
		onFailed = function(failedPlayer: Player, _code: string)
			SpectatorSlotService.release(record.matchId, failedPlayer.UserId)
		end,
	})
	return true, if mock then "STUDIO MOCK: spectator slot reserved and released" else "Travelling to the Colosseum…"
end

-- matchId = a public id from the list, or "RANDOM".
function SpectatorJoinService.watch(player: Player, matchId: unknown): (boolean, string)
	if busy[player] then
		return false, "Please wait…"
	end
	if not GameStates.isInLobby(player:GetAttribute(GameStates.StateAttribute)) then
		return false, "Finish what you are doing first"
	end
	if MatchmakingService.isQueued(player) then
		return false, "Leave the queue first"
	end
	local party = PartyService.get(player)
	if party and party.locked then
		return false, "Your party is queued"
	end
	busy[player] = true
	local ok, success, text = pcall(function(): (boolean, string)
		local record: MatchTypes.RegistryRecord? = nil
		if matchId == "RANDOM" then
			record = LiveBattlesService.pickRandom(player)
			if not record then
				return false, MatchTypes.Messages.NO_BATTLES
			end
		elseif typeof(matchId) == "string" and #matchId <= 64 then
			-- Must be in the list this player may see (policy / friends checked there)
			local allowed = false
			local list = LiveBattlesService.list(player, "All")
			for _, section in { list.friends, list.featured, list.all } do
				for _, card in section do
					if card.matchId == matchId then
						allowed = true
					end
				end
			end
			record = if allowed then MatchRegistryService.find(matchId) else nil
			if not record then
				return false, MatchTypes.Messages.ENDED
			end
		else
			return false, "Unknown battle"
		end
		local found = record :: MatchTypes.RegistryRecord
		if not found.joinableAsSpectator or found.spectatorCount >= found.maxSpectators then
			return false, MatchTypes.Messages.FULL
		end
		return watchRecord(player, found)
	end)
	busy[player] = nil
	if not ok then
		return false, MatchTypes.Messages.TELEPORT_FAILED
	end
	return success == true, if typeof(text) == "string" then text else MatchTypes.Messages.TELEPORT_FAILED
end

return SpectatorJoinService
