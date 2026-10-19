--!strict
-- The cross-server registry of live matches ("<namespace>_Registry", MemoryStore, global to all
-- Hub servers). Every Arena publishes its PUBLIC record (MatchTypes.RegistryRecord) every
-- HeartbeatSeconds with an expiration of ExpirationSeconds, so crashed / stale arenas vanish on
-- their own. Completed matches are removed immediately. No access codes, tickets, inventories or
-- job ids are ever written here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ExperienceConfig = require(ReplicatedStorage.Shared.ExperienceConfig)
local GameProtocol = require(ReplicatedStorage.Shared.GameProtocol)
local MatchDefinitions = require(ReplicatedStorage.Shared.MatchDefinitions)
local MatchTypes = require(ReplicatedStorage.Shared.MatchTypes)
local MemoryStoreAdapter = require(script.Parent.MemoryStoreAdapter)

type RegistryRecord = MatchTypes.RegistryRecord

local MatchRegistryService = {}

local cache: { records: { RegistryRecord }, at: number }? = nil

local function store()
	return MemoryStoreAdapter.map("Registry")
end

-- Arena: publish / refresh the public record (never throws; failures don't affect the match).
function MatchRegistryService.publish(record: RegistryRecord): boolean
	record.heartbeatAt = os.time()
	return store().set(record.matchId, record, ExperienceConfig.Registry.ExpirationSeconds)
end

-- Arena: completed / cleaning up -> gone from every list at once.
function MatchRegistryService.remove(matchId: string)
	store().remove(matchId)
end

local function valid(record: any): boolean
	if typeof(record) ~= "table" or typeof(record.matchId) ~= "string" or not MatchDefinitions.get(record.mode) then
		return false
	end
	if record.status ~= "ACTIVE" and record.status ~= "STARTING" then
		return false
	end
	if typeof(record.heartbeatAt) ~= "number" or os.time() - record.heartbeatAt > ExperienceConfig.Registry.ExpirationSeconds then
		return false -- stale (missed heartbeats)
	end
	return GameProtocol.isCompatible(record.protocol)
end

-- Hub: all live, compatible matches (cached for a few seconds per Hub server).
function MatchRegistryService.list(force: boolean?): { RegistryRecord }
	local now = os.clock()
	local current = cache
	if not force and current and now - current.at < ExperienceConfig.Registry.ListCacheSeconds then
		return current.records
	end
	local ok, entries = store().list(nil)
	local records: { RegistryRecord } = {}
	if ok then
		for _, entry in entries do
			if valid(entry.value) then
				table.insert(records, entry.value :: RegistryRecord)
			end
		end
	elseif current then
		return current.records -- keep showing the last good list during an outage
	end
	cache = { records = records, at = now }
	return records
end

function MatchRegistryService.find(matchId: string): RegistryRecord?
	local ok, value = store().get(matchId)
	if ok and valid(value) then
		return value :: RegistryRecord
	end
	return nil
end

-- Deterministic server-side "featured" rules (clients can never mark a match featured).
function MatchRegistryService.featuredReason(record: RegistryRecord): string?
	if record.bossPhase >= 3 then
		return "OTTI BOSS — PHASE 3"
	elseif record.bossPhase > 0 then
		return "OTTI BOSS — PHASE " .. record.bossPhase
	elseif record.suddenDeath then
		return "SUDDEN DEATH"
	elseif record.mode == "ELIMINATION" and (record.redScore == record.target - 1 or record.blueScore == record.target - 1) then
		return "MATCH POINT"
	elseif (record.mode == "SOLO_ZOMBIES" or record.mode == "COOP_ZOMBIES") and record.round >= record.maxRounds - 1 and record.round > 0 then
		return "FINAL ROUND"
	elseif record.mode == "TIME_BATTLE" and record.timeLeft >= 0 and record.timeLeft <= 60 and math.abs(record.redScore - record.blueScore) <= 1 then
		return "CLOSE FINISH"
	elseif record.mode == "FIRST_TO" and record.target > 0 and math.max(record.redScore, record.blueScore) >= record.target - 2 and math.abs(record.redScore - record.blueScore) <= 1 then
		return "CLOSE FINISH"
	elseif record.spectatorCount >= ExperienceConfig.Spectating.FeaturedSpectatorThreshold then
		return "CROWD FAVOURITE"
	end
	return nil
end

return MatchRegistryService
