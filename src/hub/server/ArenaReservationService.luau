--!strict
-- Creates a match: unique Match ID, one reserved Arena server (TeleportService:ReserveServerAsync),
-- the authoritative MatchRecord, the server-only ConnectionRecord (access code) and one admission
-- ticket per fighter. Nothing of this reaches a client except the public match id.
-- Mock mode (Studio / Place IDs not configured): no server is reserved; the records are written to
-- the mock MemoryStore so the flow can be followed locally, and the caller reports
-- "STUDIO MOCK" instead of pretending a teleport happened.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local EnvironmentConfig = require(ReplicatedStorage.Shared.EnvironmentConfig)
local ExperienceConfig = require(ReplicatedStorage.Shared.ExperienceConfig)
local GameProtocol = require(ReplicatedStorage.Shared.GameProtocol)
local MatchDefinitions = require(ReplicatedStorage.Shared.MatchDefinitions)
local MatchTypes = require(ReplicatedStorage.Shared.MatchTypes)
local Server = script.Parent.Parent
local AdmissionTicketService = require(Server.AdmissionTicketService)
local MatchRecordService = require(Server.MatchRecordService)
local MemoryStoreAdapter = require(Server.MemoryStoreAdapter)

local PREFIX = "[OttiArena][Hub]"

type Fighter = MatchTypes.Fighter
type MatchRecord = MatchTypes.MatchRecord

export type Created = { record: MatchRecord, accessCode: string, mock: boolean }

local ArenaReservationService = {}

local function reserve(): (string?, string?)
	local placeId = EnvironmentConfig.get().ArenaPlaceId
	for attempt = 1, ExperienceConfig.Teleport.Retries do
		local ok, code, privateServerId = pcall(function()
			return TeleportService:ReserveServerAsync(placeId)
		end)
		if ok and typeof(code) == "string" then
			return code, if typeof(privateServerId) == "string" then privateServerId else ""
		end
		warn(PREFIX, ("ReserveServerAsync failed (attempt %d): %s"):format(attempt, tostring(code)))
		task.wait(ExperienceConfig.Teleport.RetryDelaySeconds)
	end
	return nil, nil
end

-- Creates the match for `fighters` (user ids with team and party). Returns nil on failure: the
-- caller keeps the players in the Hub (queue entries are released for a new attempt).
function ArenaReservationService.create(mode: MatchTypes.MatchMode, fighters: { Fighter }, policy: string?, boss: string?): Created?
	local definition = MatchDefinitions.get(mode)
	if not definition or #fighters < 1 or #fighters > definition.MaxFighters then
		return nil
	end
	local mock = not EnvironmentConfig.canTeleport()
	local accessCode, privateServerId = "", ""
	if not mock then
		local code, serverId = reserve()
		if not code then
			return nil
		end
		accessCode, privateServerId = code, serverId or ""
	end
	local matchId = MemoryStoreAdapter.newId("match")
	local record: MatchRecord = {
		matchId = matchId,
		mode = mode,
		protocol = GameProtocol.Version,
		privateServerId = privateServerId,
		fighters = fighters,
		policy = policy or ExperienceConfig.Spectating.DefaultPolicy,
		createdAt = os.time(),
		createdBy = game.JobId,
		boss = boss,
	}
	if not MatchRecordService.saveMatch(record) then
		return nil
	end
	if not mock and not MatchRecordService.saveConnection({ matchId = matchId, accessCode = accessCode, placeId = EnvironmentConfig.get().ArenaPlaceId }) then
		MatchRecordService.remove(matchId)
		return nil
	end
	for _, fighter in fighters do
		if not AdmissionTicketService.issue(matchId, fighter.userId, "FIGHTER", fighter.team, mode) then
			MatchRecordService.remove(matchId)
			return nil
		end
	end
	print(PREFIX, ("Match %s created: %s, %d fighter(s)%s"):format(matchId, mode, #fighters, if mock then " [MOCK]" else ""))
	local created: Created = { record = record, accessCode = accessCode, mock = mock :: boolean }
	return created
end

-- Undo after a failed start before anybody arrived.
function ArenaReservationService.discard(record: MatchRecord)
	for _, fighter in record.fighters do
		AdmissionTicketService.revoke(record.matchId, fighter.userId)
	end
	MatchRecordService.remove(record.matchId)
end

return ArenaReservationService
