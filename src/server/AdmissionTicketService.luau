--!strict
-- One-time admission tickets (server only, MemoryStore "<namespace>_Tickets").
-- The Hub issues one ticket per fighter / spectator, keyed "<matchId>:<userId>", short-lived.
-- The Arena consumes it atomically (UpdateAsync): it must exist, not be expired or consumed,
-- belong to this user and match, carry a valid role and a compatible protocol version.
-- TeleportData only carries the match id and requested role, both re-checked against the ticket.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ExperienceConfig = require(ReplicatedStorage.Shared.ExperienceConfig)
local GameProtocol = require(ReplicatedStorage.Shared.GameProtocol)
local MatchDefinitions = require(ReplicatedStorage.Shared.MatchDefinitions)
local MatchTypes = require(ReplicatedStorage.Shared.MatchTypes)
local MemoryStoreAdapter = require(script.Parent.MemoryStoreAdapter)

type AdmissionTicket = MatchTypes.AdmissionTicket
export type Rejection = "MISSING" | "EXPIRED" | "CONSUMED" | "WRONG_USER" | "WRONG_MATCH" | "BAD_ROLE" | "PROTOCOL" | "STORE"

local AdmissionTicketService = {}

local function store()
	return MemoryStoreAdapter.map("Tickets")
end

function AdmissionTicketService.issue(matchId: string, userId: number, role: MatchTypes.Role, team: string, mode: MatchTypes.MatchMode): AdmissionTicket?
	local now = os.time()
	local lifetime = ExperienceConfig.Tickets.LifetimeSeconds
	local ticket: AdmissionTicket = {
		ticketId = MemoryStoreAdapter.newId("t"),
		matchId = matchId,
		userId = userId,
		role = role,
		team = team,
		mode = mode,
		issuedAt = now,
		expiresAt = now + lifetime,
		consumed = false,
		protocol = GameProtocol.Version,
	}
	if store().set(MatchTypes.ticketKey(matchId, userId), ticket, lifetime + 10) then
		return ticket
	end
	return nil
end

function AdmissionTicketService.revoke(matchId: string, userId: number)
	store().remove(MatchTypes.ticketKey(matchId, userId))
end

-- Validates and consumes the ticket of `userId` for `matchId` in one atomic update.
function AdmissionTicketService.consume(matchId: string, userId: number): (AdmissionTicket?, Rejection?)
	local rejection: Rejection? = nil
	local ok, result = store().update(MatchTypes.ticketKey(matchId, userId), function(old: any)
		if typeof(old) ~= "table" then
			rejection = "MISSING"
			return nil
		end
		if old.consumed == true then
			rejection = "CONSUMED"
			return nil
		end
		if typeof(old.expiresAt) ~= "number" or old.expiresAt < os.time() then
			rejection = "EXPIRED"
			return nil
		end
		if old.userId ~= userId then
			rejection = "WRONG_USER"
			return nil
		end
		if old.matchId ~= matchId then
			rejection = "WRONG_MATCH"
			return nil
		end
		if not MatchDefinitions.isRole(old.role) then
			rejection = "BAD_ROLE"
			return nil
		end
		if not GameProtocol.isCompatible(old.protocol) then
			rejection = "PROTOCOL"
			return nil
		end
		old.consumed = true
		return old
	end, 60)
	if not ok then
		return nil, "STORE"
	end
	if rejection or typeof(result) ~= "table" then
		return nil, rejection or "MISSING"
	end
	return result :: AdmissionTicket, nil
end

return AdmissionTicketService
