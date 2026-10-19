--!strict
-- Atomic spectator slots per match ("<namespace>_Slots", one record per match).
--   Hub    reserve(matchId, userId): UpdateAsync -> joinable, connected + live reservations below
--          the cap -> add a reservation that expires on its own; release() on teleport failure.
--   Arena  heartbeat(): writes joinable / connected count and drops expired reservations;
--          consume(): the arriving spectator's reservation is turned into a connected seat.
-- Several Hub servers can never overfill one Arena: the menu's spectator count is display only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ExperienceConfig = require(ReplicatedStorage.Shared.ExperienceConfig)
local MatchTypes = require(ReplicatedStorage.Shared.MatchTypes)
local MemoryStoreAdapter = require(script.Parent.MemoryStoreAdapter)

type SlotRecord = MatchTypes.SlotRecord
export type ReserveResult = "OK" | "FULL" | "ENDED" | "STORE"

local SpectatorSlotService = {}

local function store()
	return MemoryStoreAdapter.map("Slots")
end

local function ttl(): number
	return ExperienceConfig.Registry.ExpirationSeconds + 30
end

local function prune(record: SlotRecord): number
	local now = os.time()
	local live = 0
	for key, expires in record.reservations do
		if expires < now then
			record.reservations[key] = nil
		else
			live += 1
		end
	end
	return live
end

function SpectatorSlotService.reserve(matchId: string, userId: number): ReserveResult
	local result: ReserveResult = "ENDED"
	local ok = store().update(matchId, function(old: any)
		if typeof(old) ~= "table" or old.joinable ~= true then
			result = "ENDED"
			return nil
		end
		local record = old :: SlotRecord
		record.reservations = if typeof(record.reservations) == "table" then record.reservations else {}
		local key = tostring(userId)
		local live = prune(record)
		if record.reservations[key] == nil and (tonumber(record.connectedSpectators) or 0) + live >= (tonumber(record.maxSpectators) or 0) then
			result = "FULL"
			return nil
		end
		record.reservations[key] = os.time() + ExperienceConfig.Tickets.SpectatorReservationSeconds
		result = "OK"
		return record
	end, ttl())
	if not ok then
		return "STORE"
	end
	return result
end

function SpectatorSlotService.release(matchId: string, userId: number)
	store().update(matchId, function(old: any)
		if typeof(old) ~= "table" or typeof(old.reservations) ~= "table" then
			return nil
		end
		old.reservations[tostring(userId)] = nil
		return old
	end, ttl())
end

-- Arena: is there a live reservation for this spectator? Removes it (the seat is now connected).
function SpectatorSlotService.consume(matchId: string, userId: number): boolean
	local had = false
	store().update(matchId, function(old: any)
		if typeof(old) ~= "table" or typeof(old.reservations) ~= "table" then
			return nil
		end
		local key = tostring(userId)
		local expires = old.reservations[key]
		had = typeof(expires) == "number" and expires >= os.time()
		old.reservations[key] = nil
		if had then
			old.connectedSpectators = (tonumber(old.connectedSpectators) or 0) + 1
		end
		return old
	end, ttl())
	return had
end

-- Arena heartbeat: current truth about joinability and connected spectators.
function SpectatorSlotService.heartbeat(matchId: string, joinable: boolean, connected: number, maxSpectators: number)
	store().update(matchId, function(old: any)
		local record: SlotRecord = if typeof(old) == "table"
			then old :: SlotRecord
			else { matchId = matchId, joinable = joinable, maxSpectators = maxSpectators, connectedSpectators = connected, reservations = {} }
		record.reservations = if typeof(record.reservations) == "table" then record.reservations else {}
		prune(record)
		record.joinable = joinable
		record.connectedSpectators = connected
		record.maxSpectators = maxSpectators
		return record
	end, ttl())
end

function SpectatorSlotService.close(matchId: string)
	store().remove(matchId)
end

return SpectatorSlotService
