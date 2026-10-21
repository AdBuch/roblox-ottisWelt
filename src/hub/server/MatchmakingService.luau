--!strict
-- Cross-server matchmaking for COOP_ZOMBIES and the three Team Battle submodes.
-- One MemoryStore sorted map per mode ("<namespace>_Queue_<MODE>"), one entry per party / solo
-- player, keyed by a server-generated queue token:
--   { token, mode, partyId, userIds, size, homeJobId, enqueuedAt, claimed }
-- * Home server: join() validates and writes the entry (expires unless refreshed), leave() removes
--   it, a poll loop picks up assignments ("<namespace>_Assign": token -> matchId, teams) and
--   teleports its own players together (HubTeleportService).
-- * Matchmaker: every Hub server runs it, but a short lease per mode ("<namespace>_Locks") lets
--   only one server match a queue at a time. It claims entries atomically (claimed = matchId);
--   if any claim fails, or the Arena can't be reserved, all claims are released again so the
--   entries are matched in a later tick (recovery from failed attempts).
--   Co-op   oldest entry first, fill up to 4; start at 4 or after CoopFillSeconds.
--   Teams   equal team sizes only (4v4 .. 1v1; smaller sizes allowed only after
--           TeamSizeWaitSeconds), parties are never split and never face themselves.
--           Levels: only entries whose average gladiator level is within a window of the oldest entry
--           (GladiatorLevelDefinitions.matchGap, widening with waiting time; MatchRatingService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local EnvironmentConfig = require(ReplicatedStorage.Shared.EnvironmentConfig)
local ExperienceConfig = require(ReplicatedStorage.Shared.ExperienceConfig)
local GameStates = require(ReplicatedStorage.Shared.GameStates)
local GladiatorLevelDefinitions = require(ReplicatedStorage.Shared.GladiatorLevelDefinitions)
local MatchDefinitions = require(ReplicatedStorage.Shared.MatchDefinitions)
local MatchTypes = require(ReplicatedStorage.Shared.MatchTypes)
local Server = script.Parent.Parent
local InventoryService = require(Server.InventoryService)
local MemoryStoreAdapter = require(Server.MemoryStoreAdapter)
local Remotes = require(Server.Remotes)
local ArenaReservationService = require(script.Parent.ArenaReservationService)
local HubTeleportService = require(script.Parent.HubTeleportService)
local MatchRatingService = require(script.Parent.MatchRatingService)
local PartyService = require(script.Parent.PartyService)

local PREFIX = "[OttiArena][Matchmaking]"
local MM = ExperienceConfig.Matchmaking
local QUEUED_MODES: { MatchTypes.MatchMode } = { "COOP_ZOMBIES", "TIME_BATTLE", "FIRST_TO", "ELIMINATION" }

type QueueEntry = {
	token: string,
	mode: MatchTypes.MatchMode,
	partyId: string,
	userIds: { number },
	size: number,
	homeJobId: string,
	enqueuedAt: number,
	level: number?, -- average gladiator level of the entry (MatchRatingService); battles match close levels
	claimed: string?,
}

type LocalEntry = {
	entry: QueueEntry,
	players: { Player },
	party: PartyService.Party?,
}

type Assignment = { matchId: string, mode: MatchTypes.MatchMode, teams: { [string]: string } }

local MatchmakingService = {}

local localEntries: { [string]: LocalEntry } = {}
local tokenOf: { [Player]: string } = {}

local function queueMap(mode: string)
	return MemoryStoreAdapter.map("Queue_" .. mode)
end

local function setStatus(players: { Player }, mode: string, waitedSince: number?)
	for _, player in players do
		if player.Parent then
			player:SetAttribute(Config.QueueStatusAttribute, mode)
			Remotes.MatchEvent:FireClient(player, "Queue", { mode = mode, since = waitedSince or 0, offerStartAfter = MM.CoopOfferStartAfterSeconds })
		end
	end
end

local function clearLocal(token: string)
	local item = localEntries[token]
	if not item then
		return
	end
	localEntries[token] = nil
	for _, player in item.players do
		if tokenOf[player] == token then
			tokenOf[player] = nil
		end
	end
	setStatus(item.players, "", nil)
	if item.party and item.party.locked then
		PartyService.setLocked(item.party, false)
	end
end

function MatchmakingService.isQueued(player: Player): boolean
	return tokenOf[player] ~= nil
end

-- Queues the player's party (leader only) or the player alone.
function MatchmakingService.join(player: Player, mode: unknown): (boolean, string)
	local definition = MatchDefinitions.get(mode)
	if not definition or not definition.Queued then
		return false, "Unknown mode"
	end
	if tokenOf[player] then
		return false, "Already queued"
	end
	if not GameStates.isInLobby(player:GetAttribute(GameStates.StateAttribute)) then
		return false, "Finish what you are doing first"
	end
	local party = PartyService.get(player)
	if party and party.members[1] ~= player then
		return false, "Only the party leader can queue"
	end
	local players = PartyService.groupOf(player)
	local maxGroup = if definition.Kind == "Team" then 4 else definition.MaxFighters
	if #players > maxGroup then
		return false, ("Parties of up to %d can queue for %s"):format(maxGroup, definition.DisplayName)
	end
	for _, member in players do
		local ok, reason = InventoryService.hasValidLoadout(member)
		if not ok then
			return false, member.DisplayName .. ": " .. reason
		end
		if tokenOf[member] then
			return false, member.DisplayName .. " is already queued"
		end
	end
	local token = MemoryStoreAdapter.newId("q")
	local userIds = {}
	for _, member in players do
		table.insert(userIds, member.UserId)
	end
	local entry: QueueEntry = {
		token = token,
		mode = definition.Id,
		partyId = if party then party.id else "solo_" .. player.UserId,
		userIds = userIds,
		size = #players,
		homeJobId = game.JobId,
		enqueuedAt = os.time(),
		level = MatchRatingService.ratingOf(players).level,
		claimed = nil,
	}
	if not queueMap(definition.Id).set(token, entry, MM.QueueEntrySeconds) then
		return false, "Matchmaking is unavailable — try again"
	end
	localEntries[token] = { entry = entry, players = players, party = party }
	for _, member in players do
		tokenOf[member] = token
	end
	if party then
		PartyService.setLocked(party, true)
	end
	setStatus(players, definition.Id, entry.enqueuedAt)
	return true, ("Searching: %s"):format(definition.DisplayName)
end

function MatchmakingService.leave(player: Player): (boolean, string)
	local token = tokenOf[player]
	local item = token and localEntries[token]
	if not token or not item then
		return false, "Not queued"
	end
	local ok, current = queueMap(item.entry.mode).get(token)
	if ok and typeof(current) == "table" and current.claimed then
		return false, "A match was just found" -- being created for this entry right now
	end
	queueMap(item.entry.mode).remove(token)
	clearLocal(token)
	return true, "Left the queue"
end

------------------------------------------------------------------------------------------
-- Matchmaker
------------------------------------------------------------------------------------------

local function acquireLease(mode: string): boolean
	local granted = false
	local ok = MemoryStoreAdapter.map("Locks").update("mm_" .. mode, function(old: any)
		local now = os.time()
		if typeof(old) == "table" and old.owner ~= game.JobId and (tonumber(old.untilAt) or 0) > now then
			return nil
		end
		granted = true
		return { owner = game.JobId, untilAt = now + MM.LeaseSeconds }
	end, MM.LeaseSeconds + 2)
	return ok and granted
end

local function claim(mode: string, entries: { QueueEntry }, matchId: string): boolean
	local claimed: { QueueEntry } = {}
	for _, entry in entries do
		local mine = false
		queueMap(mode).update(entry.token, function(old: any)
			if typeof(old) ~= "table" or old.claimed then
				return nil
			end
			old.claimed = matchId
			mine = true
			return old
		end, MM.QueueEntrySeconds)
		if not mine then
			for _, done in claimed do
				queueMap(mode).update(done.token, function(old: any)
					if typeof(old) == "table" and old.claimed == matchId then
						old.claimed = nil
						return old
					end
					return nil
				end, MM.QueueEntrySeconds)
			end
			return false
		end
		table.insert(claimed, entry)
	end
	return true
end

local function unclaim(mode: string, entries: { QueueEntry }, matchId: string)
	for _, entry in entries do
		queueMap(mode).update(entry.token, function(old: any)
			if typeof(old) == "table" and old.claimed == matchId then
				old.claimed = nil
				return old
			end
			return nil
		end, MM.QueueEntrySeconds)
	end
end

-- Two disjoint groups of entries, each summing to exactly `size`, preferring the oldest entries.
local function findTeams(entries: { QueueEntry }, size: number): ({ QueueEntry }?, { QueueEntry }?)
	local n = math.min(#entries, MM.MaxEntriesScanned)
	local assignment: { number } = table.create(n, 0) -- 0 = unused, 1 = red, 2 = blue
	local sums = { 0, 0 }
	local function search(index: number): boolean
		if sums[1] == size and sums[2] == size then
			return true
		end
		if index > n then
			return false
		end
		local entry = entries[index]
		for team = 1, 2 do
			if sums[team] + entry.size <= size then
				assignment[index] = team
				sums[team] += entry.size
				if search(index + 1) then
					return true
				end
				sums[team] -= entry.size
				assignment[index] = 0
			end
		end
		return search(index + 1)
	end
	if not search(1) then
		return nil, nil
	end
	local red, blue = {}, {}
	for i = 1, n do
		if assignment[i] == 1 then
			table.insert(red, entries[i])
		elseif assignment[i] == 2 then
			table.insert(blue, entries[i])
		end
	end
	return red, blue
end

local function createAndAssign(mode: MatchTypes.MatchMode, groups: { { entries: { QueueEntry }, team: string } })
	local all: { QueueEntry } = {}
	for _, group in groups do
		for _, entry in group.entries do
			table.insert(all, entry)
		end
	end
	local provisional = MemoryStoreAdapter.newId("claim")
	if not claim(mode, all, provisional) then
		return
	end
	local fighters: { MatchTypes.Fighter } = {}
	local teams: { [string]: string } = {}
	for _, group in groups do
		for _, entry in group.entries do
			for _, userId in entry.userIds do
				table.insert(fighters, { userId = userId, team = group.team, partyId = entry.partyId })
				teams[tostring(userId)] = group.team
			end
		end
	end
	local created = ArenaReservationService.create(mode, fighters, nil)
	if not created then
		warn(PREFIX, ("Could not create a %s match; %d queue entries released"):format(mode, #all))
		unclaim(mode, all, provisional)
		return
	end
	local assignment: Assignment = { matchId = created.record.matchId, mode = mode, teams = teams }
	for _, entry in all do
		MemoryStoreAdapter.map("Assign").set(entry.token, assignment, MM.AssignmentSeconds)
		queueMap(mode).remove(entry.token)
	end
	print(PREFIX, ("%s: matched %d entr(y/ies) into %s"):format(mode, #all, created.record.matchId))
end

local function tickMode(mode: MatchTypes.MatchMode)
	if not acquireLease(mode) then
		return
	end
	local ok, raw = queueMap(mode).list(MM.MaxEntriesScanned * 2)
	if not ok then
		return
	end
	local entries: { QueueEntry } = {}
	for _, item in raw do
		local value = item.value
		if typeof(value) == "table" and not value.claimed and typeof(value.size) == "number" and value.size >= 1 then
			table.insert(entries, value :: QueueEntry)
		end
	end
	table.sort(entries, function(a, b)
		return a.enqueuedAt < b.enqueuedAt
	end)
	if #entries == 0 then
		return
	end
	local now = os.time()
	local definition = MatchDefinitions.get(mode) :: MatchDefinitions.MatchDefinition
	if definition.Kind == "Zombies" then
		local used: { [string]: boolean } = {}
		for _, oldest in entries do
			if used[oldest.token] then
				continue
			end
			local group, total = { oldest }, oldest.size
			for _, other in entries do
				if other ~= oldest and not used[other.token] and total + other.size <= definition.MaxFighters then
					table.insert(group, other)
					total += other.size
				end
			end
			if total >= definition.MaxFighters or now - oldest.enqueuedAt >= MM.CoopFillSeconds then
				for _, entry in group do
					used[entry.token] = true
				end
				createAndAssign(mode, { { entries = group, team = "" } })
			end
		end
		return
	end
	-- Team modes: the largest equal team size the waiting time allows, among entries whose gladiator
	-- levels are close to the oldest entry's (the allowed gap widens while it waits)
	local waited = now - entries[1].enqueuedAt
	local anchorLevel = entries[1].level or 1
	local gap = GladiatorLevelDefinitions.matchGap(waited)
	local close: { QueueEntry } = {}
	for _, entry in entries do
		if math.abs((entry.level or anchorLevel) - anchorLevel) <= gap then
			table.insert(close, entry)
		end
	end
	local waits = MM.TeamSizeWaitSeconds :: { [number]: number }
	for size = 4, 1, -1 do
		if waited >= (waits[size] or 0) then
			local red, blue = findTeams(close, size)
			if red and blue then
				createAndAssign(mode, { { entries = red, team = "Red" }, { entries = blue, team = "Blue" } })
				return -- one match per tick and mode; the next tick continues
			end
		end
	end
end

------------------------------------------------------------------------------------------
-- Home server loops: refresh entries, pick up assignments
------------------------------------------------------------------------------------------

local function pollAssignments()
	for token, item in localEntries do
		local ok, value = MemoryStoreAdapter.map("Assign").get(token)
		if ok and typeof(value) == "table" and typeof(value.matchId) == "string" then
			MemoryStoreAdapter.map("Assign").remove(token)
			local assignment = value :: Assignment
			local players = {}
			for _, player in item.players do
				if player.Parent then
					table.insert(players, player)
				end
			end
			local party = item.party
			localEntries[token] = nil
			for _, player in item.players do
				tokenOf[player] = nil
			end
			setStatus(item.players, "", nil)
			local mock = not EnvironmentConfig.canTeleport()
			HubTeleportService.send(players, {
				matchId = assignment.matchId,
				role = "FIGHTER",
				mode = assignment.mode,
				mock = mock,
				onFailed = function(player: Player, _code: string)
					if party and party.locked then
						PartyService.setLocked(party, false)
					end
					player:SetAttribute(Config.QueueStatusAttribute, "")
				end,
			})
		end
	end
end

local function refreshEntries()
	for token, item in localEntries do
		local present = false
		queueMap(item.entry.mode).update(token, function(old: any)
			if typeof(old) ~= "table" then
				return nil -- never resurrect: a missing entry may just have been matched
			end
			present = true
			return old
		end, MM.QueueEntrySeconds)
		if not present then
			local ok, assignment = MemoryStoreAdapter.map("Assign").get(token)
			if ok and assignment == nil and localEntries[token] == item then
				for _, player in item.players do
					HubTeleportService.message(player, "Queue expired — search again", false)
				end
				clearLocal(token)
			end
		end
	end
end

function MatchmakingService.init()
	Players.PlayerRemoving:Connect(function(player)
		local token = tokenOf[player]
		local item = token and localEntries[token]
		if token and item then
			queueMap(item.entry.mode).remove(token) -- a member left: the whole entry leaves the queue
			clearLocal(token)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(MM.TickSeconds)
			for _, mode in QUEUED_MODES do
				local ok, err = pcall(function()
					tickMode((mode :: any) :: MatchTypes.MatchMode)
				end)
				if not ok then
					warn(PREFIX, "tick failed:", err)
				end
			end
			pcall(pollAssignments)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(MM.RefreshSeconds)
			pcall(refreshEntries)
		end
	end)
end

return MatchmakingService
