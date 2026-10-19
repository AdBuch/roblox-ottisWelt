--!strict
-- Server-only match records in MemoryStore:
--   "<namespace>_Matches"  MatchRecord: mode, fighters + teams, policy, protocol, privateServerId
--   "<namespace>_Private"  ConnectionRecord: the reserved-server access code (never leaves servers)
-- Both expire after ExperienceConfig.Registry.MatchRecordSeconds and are removed at match end.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ExperienceConfig = require(ReplicatedStorage.Shared.ExperienceConfig)
local MatchTypes = require(ReplicatedStorage.Shared.MatchTypes)
local MemoryStoreAdapter = require(script.Parent.MemoryStoreAdapter)

type MatchRecord = MatchTypes.MatchRecord
type ConnectionRecord = MatchTypes.ConnectionRecord

local MatchRecordService = {}

local function ttl(): number
	return ExperienceConfig.Registry.MatchRecordSeconds
end

function MatchRecordService.saveMatch(record: MatchRecord): boolean
	return MemoryStoreAdapter.map("Matches").set(record.matchId, record, ttl())
end

function MatchRecordService.getMatch(matchId: string): MatchRecord?
	local ok, value = MemoryStoreAdapter.map("Matches").get(matchId)
	if ok and typeof(value) == "table" and value.matchId == matchId then
		return value :: MatchRecord
	end
	return nil
end

function MatchRecordService.saveConnection(record: ConnectionRecord): boolean
	return MemoryStoreAdapter.map("Private").set(record.matchId, record, ttl())
end

function MatchRecordService.getConnection(matchId: string): ConnectionRecord?
	local ok, value = MemoryStoreAdapter.map("Private").get(matchId)
	if ok and typeof(value) == "table" and typeof(value.accessCode) == "string" and value.accessCode ~= "" then
		return value :: ConnectionRecord
	end
	return nil
end

function MatchRecordService.remove(matchId: string)
	MemoryStoreAdapter.map("Matches").remove(matchId)
	MemoryStoreAdapter.map("Private").remove(matchId)
end

return MatchRecordService
