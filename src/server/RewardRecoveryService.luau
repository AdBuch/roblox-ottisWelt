--!strict
-- Durable per-player inbox. Profile evidence makes replay after an ambiguous acknowledgement safe.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EnvironmentConfig = require(ReplicatedStorage.Shared.EnvironmentConfig)
local RewardTypes = require(ReplicatedStorage.Shared.RewardTypes)
local InventoryService = require(script.Parent.InventoryService)
local PlayerDataService = require(script.Parent.PlayerDataService)

type Claim = RewardTypes.Claim
type Inbox = { [string]: Claim }
local Recovery = {}
local mock: { [string]: Inbox } = {}
local queued: { [number]: Inbox } = {}
local working: { [Player]: boolean } = {}
local initialized = false
local closing = false
local active = 0
local function waitForAnswer(work: () -> boolean, deadline: number): boolean
	local answer: boolean? = nil
	task.spawn(function()
		local ok, value = pcall(work)
		if not ok then warn("[RewardRecovery]", "Recovery worker failed:", value) end
		answer = ok and value and os.clock() <= deadline
	end)
	while answer == nil and os.clock() < deadline do task.wait(0.1) end
	return answer == true
end

local function update(userId: number, transform: (Inbox) -> Inbox): (boolean, any)
	local key = "player_" .. tostring(userId)
	if EnvironmentConfig.useMockData() then
		mock[key] = transform(table.clone(mock[key] or {}))
		return true, mock[key]
	end
	local last: any = nil
	for attempt = 1, 3 do
		local ok, value = pcall(function()
			local store = DataStoreService:GetDataStore("OttiRewardInbox_" .. EnvironmentConfig.name() .. "_v1")
			return store:UpdateAsync(key, function(old: any)
				return transform(if typeof(old) == "table" then table.clone(old) else {})
			end)
		end)
		if ok and typeof(value) == "table" then return true, value end
		last = value
		if attempt < 3 then task.wait(attempt) end
	end
	warn("[RewardRecovery]", "Inbox operation unconfirmed for", userId, last)
	return false, nil
end

local function same(a: Claim, b: Claim): boolean
	if a.id ~= b.id or a.matchId ~= b.matchId or a.aura ~= b.aura or a.denarii ~= b.denarii or a.campaign ~= b.campaign or a.stage ~= b.stage then return false end
	for key, value in a.stats do if b.stats[key] ~= value then return false end end
	for key, value in b.stats do if a.stats[key] ~= value then return false end end
	return true
end

function Recovery.submit(userId: number, claim: Claim): boolean
	-- Queue before any yield. A timed-out caller still leaves the intent tracked for retry.
	local waiting = queued[userId] or {}
	waiting[claim.id] = claim
	queued[userId] = waiting
	active += 1
	return waitForAnswer(function()
		local ok, inbox = update(userId, function(old)
			if not old[claim.id] then old[claim.id] = claim end
			return old
		end)
		active -= 1
		local confirmed = ok and inbox[claim.id] ~= nil and same(inbox[claim.id], claim)
		local pending = queued[userId]
		if confirmed and pending then
			pending[claim.id] = nil
			if next(pending) == nil then queued[userId] = nil end
		end
		return confirmed
	end, os.clock() + 20)
end

function Recovery.recover(player: Player): (boolean, Inbox?)
	local deadline = os.clock() + 20
	while working[player] and os.clock() < deadline do task.wait(0.1) end
	if working[player] then return false end
	local mockData = EnvironmentConfig.useMockData()
	if not player.Parent or (not PlayerDataService.canPersist(player) and not (mockData and PlayerDataService.getStatus(player) == "Mock")) then
		return false
	end
	working[player] = true
	active += 1
	local newClaims: Inbox = {}
	local result = waitForAnswer(function()
		local success, committed = pcall(function()
			-- UpdateAsync avoids a cached inbox. A concurrent enqueue is preserved at ack.
			local ok, inbox = update(player.UserId, function(old) return old end)
			if not ok then return false end
			for _, claim in inbox do
				local applied, isNew = InventoryService.applyReward(player, claim)
				if not applied then return false end
				if isNew then newClaims[claim.id] = claim end
			end
			if not mockData and not PlayerDataService.flush(player) then return false end
			if next(inbox) then
				update(player.UserId, function(old)
					for id, claim in inbox do
						if old[id] and same(old[id], claim) then old[id] = nil end
					end
					return old
				end)
			end
			return true
		end)
		active -= 1
		working[player] = nil
		if not success then warn("[RewardRecovery]", "Profile recovery failed:", committed) end
		return success and committed
	end, deadline)
	return result, if result then newClaims else nil
end

function Recovery.init()
	if initialized then return end
	initialized = true
	task.spawn(function()
		while not closing do
			for userId, inbox in queued do
				for _, claim in table.clone(inbox) do Recovery.submit(userId, claim) end
			end
			for _, player in Players:GetPlayers() do task.spawn(Recovery.recover, player) end
			task.wait(15)
		end
	end)
	game:BindToClose(function()
		closing = true
		for userId, inbox in queued do
			for _, claim in inbox do task.spawn(Recovery.submit, userId, claim) end
		end
		local deadline = os.clock() + 20
		while (active > 0 or next(queued) ~= nil) and os.clock() < deadline do task.wait(0.1) end
		if active > 0 or next(queued) ~= nil then warn("[RewardRecovery]", "Shutdown has unconfirmed claims") end
	end)
end

return Recovery
