--!strict
-- Hub parties (1-4 players, any number of parties per Hub server). Server-owned:
--   create / invite (players in this Hub server) / accept / leave / ready, leader = first member;
--   leadership passes on when the leader leaves. A party is LOCKED while it is queued or being
--   teleported: membership can't change until the queue / teleport ends.
-- The CO-OP LEGIONS posts in the basement use the "open" post party (JOIN joins it, READY,
-- START = leader starts Co-op with the READY members). The menu (MatchRequest) offers the same
-- for private parties plus invites. Friends outside the server are invited with Roblox's own
-- game-invite prompt (client), they then join here and accept.
-- Published to clients: PartyId / InParty / Ready attributes and a MatchEvent "Party" snapshot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local Config = require(ReplicatedStorage.Shared.Config)
local GameStates = require(ReplicatedStorage.Shared.GameStates)
local Server = script.Parent.Parent
local InventoryService = require(Server.InventoryService)
local MemoryStoreAdapter = require(Server.MemoryStoreAdapter)
local Remotes = require(Server.Remotes)

local MAX_MEMBERS = 4
local INVITE_SECONDS = 60

export type Party = {
	id: string,
	members: { Player },
	ready: { [Player]: boolean },
	invites: { [Player]: number },
	locked: boolean,
	open: boolean, -- the CO-OP posts' party
}

local PartyService = {}

local parties: { [string]: Party } = {}
local partyOf: { [Player]: Party } = {}
local board: TextLabel? = nil
local lobbyFolder: Instance? = nil

local function message(player: Player, text: string, ok: boolean)
	Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Shop, text, ok)
end

local function snapshot(party: Party?, viewer: Player): { [string]: any }
	local invitesForMe = {}
	for _, other in parties do
		local expires = other.invites[viewer]
		if expires and expires > os.clock() and other.members[1] then
			table.insert(invitesForMe, { partyId = other.id, leader = other.members[1].DisplayName })
		end
	end
	if not party then
		return { inParty = false, invites = invitesForMe }
	end
	local members = {}
	for i, member in party.members do
		table.insert(members, { userId = member.UserId, name = member.DisplayName, ready = party.ready[member] == true, leader = i == 1 })
	end
	return {
		inParty = true,
		partyId = party.id,
		leader = party.members[1] == viewer,
		locked = party.locked,
		open = party.open,
		members = members,
		invites = invitesForMe,
	}
end

local function publish(party: Party?)
	if party then
		local roster = {}
		for i, member in party.members do
			table.insert(roster, ("%s|%s|%s"):format(member.DisplayName, if party.ready[member] then "ready" else "", if i == 1 then "leader" else ""))
		end
		local rosterText = table.concat(roster, ";")
		for _, member in party.members do
			member:SetAttribute(Config.PartyIdAttribute, party.id)
			member:SetAttribute(Config.InPartyAttribute, true)
			member:SetAttribute(Config.ReadyAttribute, party.ready[member] == true)
			member:SetAttribute("PartyRoster", rosterText)
			local state = member:GetAttribute(GameStates.StateAttribute)
			if GameStates.isInLobby(state) then
				member:SetAttribute(GameStates.StateAttribute, if party.ready[member] then GameStates.ReadyCheck else GameStates.PartyForming)
			end
			Remotes.MatchEvent:FireClient(member, "Party", snapshot(party, member))
		end
		for invited in party.invites do
			if invited.Parent then
				Remotes.MatchEvent:FireClient(invited, "Party", snapshot(partyOf[invited], invited))
			end
		end
	end
	-- The CO-OP board shows the open post party
	local openParty: Party? = nil
	for _, p in parties do
		if p.open then
			openParty = p
			break
		end
	end
	local lines, roster = {}, {}
	if openParty then
		for i, member in openParty.members do
			table.insert(lines, ("%s%s  %s"):format(if i == 1 then "★ " else "", member.DisplayName, if openParty.ready[member] then "READY" else "…"))
			table.insert(roster, ("%s|%s|%s"):format(member.DisplayName, if openParty.ready[member] then "ready" else "", if i == 1 then "leader" else ""))
		end
	end
	local currentBoard = board
	if currentBoard then
		currentBoard.Text = if #lines > 0 then table.concat(lines, "\n") else "No party yet · hold F at JOIN"
	end
	if lobbyFolder then
		lobbyFolder:SetAttribute(Config.CoopRosterAttribute, table.concat(roster, ";"))
	end
end

local function clearPlayer(player: Player)
	if player.Parent then
		player:SetAttribute(Config.PartyIdAttribute, "")
		player:SetAttribute(Config.InPartyAttribute, false)
		player:SetAttribute(Config.ReadyAttribute, false)
		player:SetAttribute("PartyRoster", "")
		local state = player:GetAttribute(GameStates.StateAttribute)
		if state == GameStates.PartyForming or state == GameStates.ReadyCheck then
			player:SetAttribute(GameStates.StateAttribute, GameStates.Lobby)
		end
		Remotes.MatchEvent:FireClient(player, "Party", snapshot(nil, player))
	end
end

local function newParty(leader: Player, open: boolean): Party
	local party: Party = { id = MemoryStoreAdapter.newId("p"), members = { leader }, ready = {}, invites = {}, locked = false, open = open }
	parties[party.id] = party
	partyOf[leader] = party
	return party
end

function PartyService.get(player: Player): Party?
	return partyOf[player]
end

function PartyService.isLeader(player: Player): boolean
	local party = partyOf[player]
	return party ~= nil and party.members[1] == player
end

-- Members of the player's party, or just the player.
function PartyService.groupOf(player: Player): { Player }
	local party = partyOf[player]
	return if party then table.clone(party.members) else { player }
end

function PartyService.readyMembers(party: Party): { Player }
	local list = {}
	for _, member in party.members do
		if party.ready[member] and member.Parent then
			table.insert(list, member)
		end
	end
	return list
end

function PartyService.setLocked(party: Party, locked: boolean)
	party.locked = locked
	publish(party)
end

function PartyService.leave(player: Player, silent: boolean?): boolean
	local party = partyOf[player]
	if not party then
		return true
	end
	if party.locked and player.Parent then
		if not silent then
			message(player, "Your party is queued or travelling: leave the queue first", false)
		end
		return false
	end
	local index = table.find(party.members, player)
	if index then
		table.remove(party.members, index)
	end
	party.ready[player] = nil
	partyOf[player] = nil
	clearPlayer(player)
	if #party.members == 0 then
		parties[party.id] = nil
		publish(nil)
	else
		publish(party)
	end
	if not silent and player.Parent then
		message(player, "You left the party", true)
	end
	return true
end

function PartyService.create(player: Player): (boolean, string)
	if partyOf[player] then
		return false, "You are already in a party"
	end
	if not GameStates.isInLobby(player:GetAttribute(GameStates.StateAttribute)) or player:GetAttribute(Config.QueueStatusAttribute) ~= "" and player:GetAttribute(Config.QueueStatusAttribute) ~= nil then
		return false, "Leave the queue first"
	end
	publish(newParty(player, false))
	return true, "Party created · invite players or start"
end

function PartyService.invite(leader: Player, target: Player): (boolean, string)
	local party = partyOf[leader]
	if not party then
		local ok, text = PartyService.create(leader)
		if not ok then
			return false, text
		end
		party = partyOf[leader]
	end
	local current = party :: Party
	if current.members[1] ~= leader then
		return false, "Only the party leader can invite"
	end
	if current.locked then
		return false, "The party is queued"
	end
	if target == leader or partyOf[target] == current then
		return false, "Already in your party"
	end
	if #current.members >= MAX_MEMBERS then
		return false, "The party is full (4 players)"
	end
	current.invites[target] = os.clock() + INVITE_SECONDS
	publish(current)
	message(target, ("%s invites you to a party"):format(leader.DisplayName), true)
	return true, ("Invited %s"):format(target.DisplayName)
end

function PartyService.accept(player: Player, partyId: string): (boolean, string)
	local party = parties[partyId]
	if not party or (party.invites[player] or 0) < os.clock() then
		return false, "The invite has expired"
	end
	if party.locked or #party.members >= MAX_MEMBERS then
		return false, "The party can't take you right now"
	end
	if not GameStates.isInLobby(player:GetAttribute(GameStates.StateAttribute)) then
		return false, "Finish what you are doing first"
	end
	if partyOf[player] and not PartyService.leave(player, true) then
		return false, "Leave your current party first"
	end
	party.invites[player] = nil
	table.insert(party.members, player)
	partyOf[player] = party
	publish(party)
	return true, "You joined the party"
end

function PartyService.setReady(player: Player, ready: boolean?): (boolean, string)
	local party = partyOf[player]
	if not party then
		return false, "Join a party first"
	end
	local value = if ready == nil then not party.ready[player] else ready
	if value then
		local ok, reason = InventoryService.hasValidLoadout(player)
		if not ok then
			return false, reason
		end
	end
	party.ready[player] = value
	publish(party)
	return true, if value then "READY" else "Not ready"
end

-- CO-OP posts: JOIN / LEAVE the open post party.
function PartyService.togglePostParty(player: Player): (boolean, string)
	local current = partyOf[player]
	if current then
		return PartyService.leave(player), "You left the party"
	end
	if not GameStates.isInLobby(player:GetAttribute(GameStates.StateAttribute)) then
		return false, "Finish what you are doing first"
	end
	for _, party in parties do
		if party.open and not party.locked and #party.members < MAX_MEMBERS then
			table.insert(party.members, player)
			partyOf[player] = party
			publish(party)
			return true, "You joined the co-op party"
		end
	end
	publish(newParty(player, true))
	return true, "You lead the co-op party"
end

-- Snapshot for the menu (MatchRequest "Party").
function PartyService.snapshotFor(player: Player): { [string]: any }
	return snapshot(partyOf[player], player)
end

function PartyService.init(folder: Instance, coopBoard: TextLabel)
	lobbyFolder = folder
	board = coopBoard
	Players.PlayerRemoving:Connect(function(player)
		local party = partyOf[player]
		if party then
			party.locked = false -- a leaving member always leaves
			PartyService.leave(player, true)
		end
		for _, p in parties do
			p.invites[player] = nil
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		player:SetAttribute(Config.PartyIdAttribute, "")
	end)
	publish(nil)
end

return PartyService
