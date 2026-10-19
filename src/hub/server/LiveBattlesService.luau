--!strict
-- Builds the LIVE IN THE COLOSSEUM list for one Hub player, entirely on the server:
--   registry records (MatchRegistryService, stale / completed / incompatible already removed)
--   -> spectator policy (PUBLIC, FRIENDS_ONLY, PARTY_ONLY, PRIVATE)
--   -> friend involvement (FriendBattleService, server-side) and featured rules (server-defined)
--   -> sections FRIENDS IN BATTLE, FEATURED BATTLES, ALL LIVE BATTLES (each match appears once)
--   -> sorted: friends, featured, free spectator slots, relevance, start time; then filtered.
-- Cards are sanitized: no job ids, access codes, tickets, inventories or coordinates; only the
-- ids of the viewer's own friends are sent (for their portraits).
-- pickRandom() implements WATCH RANDOM with the configured friend / featured / normal weights.
-- Studio: ExperienceConfig.Studio.MockMatches fake battles are published to the mock registry.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnvironmentConfig = require(ReplicatedStorage.Shared.EnvironmentConfig)
local ExperienceConfig = require(ReplicatedStorage.Shared.ExperienceConfig)
local GameProtocol = require(ReplicatedStorage.Shared.GameProtocol)
local MatchDefinitions = require(ReplicatedStorage.Shared.MatchDefinitions)
local MatchTypes = require(ReplicatedStorage.Shared.MatchTypes)
local Server = script.Parent.Parent
local MatchRegistryService = require(Server.MatchRegistryService)
local SpectatorSlotService = require(Server.SpectatorSlotService)
local FriendBattleService = require(script.Parent.FriendBattleService)
local PartyService = require(script.Parent.PartyService)

type RegistryRecord = MatchTypes.RegistryRecord

export type Card = {
	matchId: string,
	mode: string,
	title: string,
	featured: string?,
	friends: { { userId: number, name: string } },
	friendExtra: number,
	score: string,
	detail: string,
	fighters: number,
	spectators: number,
	maxSpectators: number,
	joinable: boolean,
	elapsed: number,
	filters: { string },
	mock: boolean,
}

export type ListResult = { friends: { Card }, featured: { Card }, all: { Card }, total: number }

local LiveBattlesService = {}

local mockIds: { [string]: boolean } = {}

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return ("%02d:%02d"):format(seconds // 60, seconds % 60)
end

local function visible(record: RegistryRecord, viewer: Player, isFriendMatch: boolean): boolean
	local policy = record.policy
	if policy == "PRIVATE" then
		return false
	elseif policy == "FRIENDS_ONLY" then
		return isFriendMatch
	elseif policy == "PARTY_ONLY" then
		local party = PartyService.get(viewer)
		return party ~= nil and table.find(record.partyIds or {}, party.id) ~= nil
	end
	return true
end

local function describe(record: RegistryRecord): (string, string, string)
	local definition = MatchDefinitions.get(record.mode)
	local title = if definition then definition.DisplayName else record.mode
	if record.mode == "FIRST_TO" then
		title = ("FIRST TO %d"):format(record.target)
	end
	if record.bossPhase > 0 then
		return "OTTI BOSS", ("%s · Phase %d"):format(title, record.bossPhase), "Round 7 / 7"
	end
	if record.mode == "SOLO_ZOMBIES" or record.mode == "COOP_ZOMBIES" then
		local detail = if record.round >= record.maxRounds - 1 and record.round > 0 then "Final Round" else ""
		return title, ("Round %d / %d"):format(math.max(1, record.round), record.maxRounds), detail
	end
	local score = ("Red %d — %d Blue"):format(record.redScore, record.blueScore)
	local detail = ""
	if record.suddenDeath then
		detail = "Sudden Death"
	elseif record.mode == "ELIMINATION" then
		detail = if record.redScore == record.target - 1 and record.blueScore == record.target - 1 then "Final Round" else ("Alive %d — %d"):format(record.redAlive, record.blueAlive)
	elseif record.timeLeft >= 0 then
		detail = clock(record.timeLeft) .. " Remaining"
	end
	return title, score, detail
end

local function toCard(record: RegistryRecord, friendIds: { number }, friendNames: FriendBattleService.FriendSet, featured: string?): Card
	local title, score, detail = describe(record)
	local friends = {}
	for i, userId in friendIds do
		if i > 3 then
			break
		end
		table.insert(friends, { userId = userId, name = friendNames[userId] or "Friend" })
	end
	local definition = MatchDefinitions.get(record.mode)
	local filters = { "All" }
	if definition then
		table.insert(filters, definition.Filter)
	end
	if record.bossPhase > 0 then
		table.insert(filters, "Otti")
	end
	if #friendIds > 0 then
		table.insert(filters, "Friends")
	end
	return {
		matchId = record.matchId,
		mode = record.mode,
		title = title,
		featured = featured,
		friends = friends,
		friendExtra = math.max(0, #friendIds - 3),
		score = score,
		detail = detail,
		fighters = record.fighterCount,
		spectators = record.spectatorCount,
		maxSpectators = record.maxSpectators,
		joinable = record.joinableAsSpectator and record.spectatorCount < record.maxSpectators,
		elapsed = math.max(0, os.time() - record.startedAt),
		filters = filters,
		mock = mockIds[record.matchId] == true,
	}
end

type Scored = { card: Card, record: RegistryRecord, friend: boolean }

local function collect(viewer: Player): { Scored }
	local friendNames = FriendBattleService.friendsOf(viewer)
	local scored: { Scored } = {}
	for _, record in MatchRegistryService.list(false) do
		local friendIds = {}
		for _, userId in (record.publicParticipantIds or {}) :: { number } do
			if friendNames[userId] and userId ~= viewer.UserId then
				table.insert(friendIds, userId)
			end
		end
		local isFriend = #friendIds > 0
		if visible(record, viewer, isFriend) then
			table.insert(scored, { card = toCard(record, friendIds, friendNames, MatchRegistryService.featuredReason(record)), record = record, friend = isFriend })
		end
	end
	table.sort(scored, function(a, b)
		if a.friend ~= b.friend then
			return a.friend
		end
		if (a.card.featured ~= nil) ~= (b.card.featured ~= nil) then
			return a.card.featured ~= nil
		end
		if a.card.joinable ~= b.card.joinable then
			return a.card.joinable
		end
		if a.card.spectators ~= b.card.spectators then
			return a.card.spectators > b.card.spectators
		end
		return a.record.startedAt < b.record.startedAt
	end)
	return scored
end

function LiveBattlesService.list(viewer: Player, filter: unknown): ListResult
	local chosen = if typeof(filter) == "string" and table.find(MatchDefinitions.Filters, filter) then filter else "All"
	local result: ListResult = { friends = {}, featured = {}, all = {}, total = 0 }
	for _, item in collect(viewer) do
		if not table.find(item.card.filters, chosen) then
			continue
		end
		result.total += 1
		if item.friend then
			table.insert(result.friends, item.card)
		elseif item.card.featured then
			table.insert(result.featured, item.card)
		else
			table.insert(result.all, item.card)
		end
	end
	return result
end

-- Weighted random choice among joinable matches (friend / featured / normal weights).
function LiveBattlesService.pickRandom(viewer: Player): RegistryRecord?
	local config = ExperienceConfig.Spectating
	local pool: { { record: RegistryRecord, weight: number } } = {}
	local total = 0
	for _, item in collect(viewer) do
		if item.card.joinable then
			-- Applicable bonuses combine by WeightRule; a match without any bonus has NormalWeight
			local parts: { number } = {}
			if item.friend then
				table.insert(parts, config.FriendWeight)
			end
			if item.card.featured then
				table.insert(parts, config.FeaturedWeight)
			end
			local weight = config.NormalWeight
			if #parts > 0 then
				weight = if config.WeightRule == "Product" then 1 else 0
				for _, value in parts do
					if config.WeightRule == "Sum" then
						weight += value
					elseif config.WeightRule == "Product" then
						weight *= value
					else -- "Max"
						weight = math.max(weight, value)
					end
				end
			end
			total += weight
			table.insert(pool, { record = item.record, weight = weight })
		end
	end
	if total <= 0 then
		return nil
	end
	local roll = math.random() * total
	for _, entry in pool do
		roll -= entry.weight
		if roll <= 0 then
			return entry.record
		end
	end
	return pool[#pool].record
end

function LiveBattlesService.isMock(matchId: string): boolean
	return mockIds[matchId] == true
end

------------------------------------------------------------------------------------------
-- Studio mock battles
------------------------------------------------------------------------------------------

local function mockRecord(index: number): RegistryRecord
	local modes: { MatchTypes.MatchMode } = { "COOP_ZOMBIES", "TIME_BATTLE", "ELIMINATION", "FIRST_TO", "SOLO_ZOMBIES" }
	local mode: MatchTypes.MatchMode = (modes[(index - 1) % #modes + 1] :: any) :: MatchTypes.MatchMode
	local now = os.time()
	local record: RegistryRecord = {
		matchId = "mock_battle_" .. index,
		mode = mode,
		subMode = nil,
		status = "ACTIVE",
		protocol = GameProtocol.Version,
		policy = "PUBLIC",
		round = if mode == "COOP_ZOMBIES" then 7 else 5,
		maxRounds = 7,
		phase = "",
		bossPhase = if mode == "COOP_ZOMBIES" then 2 else 0,
		redScore = 8,
		blueScore = 7,
		target = if mode == "ELIMINATION" then 3 elseif mode == "FIRST_TO" then 15 else 0,
		timeLeft = if mode == "TIME_BATTLE" then 252 else -1,
		redAlive = 3,
		blueAlive = 2,
		suddenDeath = false,
		fighterCount = if mode == "SOLO_ZOMBIES" then 1 else 4,
		maxFighters = 8,
		spectatorCount = index * 3,
		maxSpectators = ExperienceConfig.Capacity.MaxSpectators,
		joinableAsSpectator = true,
		startedAt = now - 60 * index,
		heartbeatAt = now,
		publicParticipantIds = if index == 1 then { FriendBattleService.MockFriendId, 2 } else { 100 + index },
		partyIds = {},
	}
	if mode == "ELIMINATION" then
		record.redScore, record.blueScore = 2, 1
	end
	return record
end

function LiveBattlesService.init()
	if not EnvironmentConfig.useMockMemoryStore() or ExperienceConfig.Studio.MockMatches <= 0 then
		return
	end
	task.spawn(function()
		while true do
			for i = 1, ExperienceConfig.Studio.MockMatches do
				local record = mockRecord(i)
				mockIds[record.matchId] = true
				MatchRegistryService.publish(record)
				SpectatorSlotService.heartbeat(record.matchId, true, record.spectatorCount, record.maxSpectators)
			end
			task.wait(ExperienceConfig.Registry.HeartbeatSeconds)
		end
	end)
end

return LiveBattlesService
