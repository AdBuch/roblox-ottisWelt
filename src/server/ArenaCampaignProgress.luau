--!strict
-- Checkpoints belong to the exact roster, independent of temporary party IDs and join order.
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EnvironmentConfig = require(ReplicatedStorage.Shared.EnvironmentConfig)

type Progress = { cleared: number, attempts: { [string]: number } }
local Campaign = {}
Campaign.Bosses = table.freeze({ "Otti", "Kroko", "Schili" })
local mock: { [string]: Progress } = {}

local function base36(id: number): string
	local alphabet = "0123456789abcdefghijklmnopqrstuvwxyz"
	local encoded = ""
	repeat
		local digit = id % 36 + 1
		encoded = alphabet:sub(digit, digit) .. encoded
		id = math.floor(id / 36)
	until id == 0
	return encoded
end

function Campaign.key(mode: string, players: { Player }): string
	local ids = {}
	for _, player in players do table.insert(ids, player.UserId) end
	table.sort(ids)
	local encoded = {}
	for _, id in ids do
		table.insert(encoded, (if id < 0 then "~" else "") .. base36(math.abs(id)))
	end
	return (if mode == "Coop" then "c:" else "s:") .. table.concat(encoded, "-")
end

local function normalize(raw: any): Progress
	local data: Progress = { cleared = 0, attempts = {} }
	if type(raw) == "table" then
		data.cleared = math.clamp(math.floor(tonumber(raw.cleared) or 0), 0, #Campaign.Bosses)
		if type(raw.attempts) == "table" then
			for _, boss in Campaign.Bosses do
				data.attempts[boss] = math.clamp(math.floor(tonumber(raw.attempts[boss]) or 0), 0, 9999)
			end
		end
	end
	return data
end

local function store(): GlobalDataStore
	return DataStoreService:GetDataStore("OttiArenaCampaign_" .. EnvironmentConfig.name() .. "_v1")
end

local function update(key: string, transform: (Progress) -> ()): Progress?
	local function apply(raw: any): Progress
		local data = normalize(raw)
		transform(data)
		return data
	end
	if EnvironmentConfig.useMockData() then
		mock[key] = apply(mock[key])
		return mock[key]
	end
	for attempt = 1, 3 do
		local ok, result = pcall(function() return store():UpdateAsync(key, apply) end)
		if ok then return result end
		warn("[ArenaCampaign] checkpoint write failed:", result)
		if attempt < 3 then task.wait(attempt) end
	end
	return nil
end

function Campaign.loadStage(key: string): number?
	local ok, raw = pcall(function()
		return if EnvironmentConfig.useMockData() then mock[key] else store():GetAsync(key)
	end)
	if not ok then
		warn("[ArenaCampaign] checkpoint read failed:", raw)
		return nil
	end
	return math.min(normalize(raw).cleared + 1, #Campaign.Bosses)
end

function Campaign.beginBoss(key: string, stage: number): boolean
	local boss = Campaign.Bosses[stage]
	local data = update(key, function(progress)
		progress.attempts[boss] = math.min(9999, (progress.attempts[boss] or 0) + 1)
	end)
	return data == nil or data.attempts[boss] == 1
end

function Campaign.clearStage(key: string, stage: number): boolean
	local data = update(key, function(progress)
		if stage == progress.cleared + 1 then progress.cleared = stage end
	end)
	return data ~= nil and data.cleared >= stage
end

return Campaign
