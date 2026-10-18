--!strict
-- CO-OP LEGIONS party in the lobby (1-4 players). Prompts at the party posts:
--   JOIN / LEAVE PARTY, READY / UNREADY, START (leader only, needs >= 1 ready member).
-- The first member is the leader; leadership passes on when the leader leaves.
-- Only READY members enter the match. Server-validated; rosters are published to the lobby
-- folder (for the HUD) and to the board above the co-op gate.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local Config = require(ReplicatedStorage.Shared.Config)
local GameModeDefinitions = require(ReplicatedStorage.Shared.GameModeDefinitions)
local GameStates = require(ReplicatedStorage.Shared.GameStates)
local InventoryService = require(script.Parent.InventoryService)
local Remotes = require(script.Parent.Remotes)

export type Hooks = {
	onJoin: (player: Player) -> (), -- leave other lobby groups (teams)
	isArenaBusy: () -> boolean,
	start: (players: { Player }) -> boolean,
}

type Member = { player: Player, ready: boolean }

local PartyService = {}

local members: { Member } = {}
local lobbyFolder: Instance? = nil
local board: TextLabel? = nil
local hooks: Hooks? = nil

local function message(player: Player, text: string, ok: boolean)
	Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Shop, text, ok)
end

local function indexOf(player: Player): number?
	for i, member in members do
		if member.player == player then
			return i
		end
	end
	return nil
end

local function publish()
	local parts, lines = {}, {}
	for i, member in members do
		table.insert(parts, ("%s|%s|%s"):format(member.player.DisplayName, if member.ready then "ready" else "", if i == 1 then "leader" else ""))
		table.insert(lines, ("%s%s  %s"):format(if i == 1 then "★ " else "", member.player.DisplayName, if member.ready then "READY" else "…"))
		member.player:SetAttribute(Config.InPartyAttribute, true)
		member.player:SetAttribute(Config.ReadyAttribute, member.ready)
		member.player:SetAttribute(GameStates.StateAttribute, if member.ready then GameStates.ReadyCheck else GameStates.PartyForming)
	end
	if lobbyFolder then
		lobbyFolder:SetAttribute(Config.CoopRosterAttribute, table.concat(parts, ";"))
	end
	if board then
		board.Text = if #lines > 0 then table.concat(lines, "\n") else "No party yet · hold F at JOIN"
	end
end

local function clearPlayer(player: Player)
	if player.Parent then
		player:SetAttribute(Config.InPartyAttribute, false)
		player:SetAttribute(Config.ReadyAttribute, false)
		if player:GetAttribute(GameStates.StateAttribute) == GameStates.PartyForming or player:GetAttribute(GameStates.StateAttribute) == GameStates.ReadyCheck then
			player:SetAttribute(GameStates.StateAttribute, GameStates.Lobby)
		end
	end
end

-- Removes a player from the party (leaving, joining a team, starting a match, ...).
function PartyService.remove(player: Player)
	local index = indexOf(player)
	if index then
		table.remove(members, index)
		clearPlayer(player)
		publish()
	end
end

local function toggleJoin(player: Player)
	if indexOf(player) then
		PartyService.remove(player)
		message(player, "You left the co-op party", true)
		return
	end
	if not GameStates.isInLobby(player:GetAttribute(GameStates.StateAttribute)) then
		return
	end
	if #members >= GameModeDefinitions.Coop.MaxPlayers then
		message(player, "The party is full (4 players)", false)
		return
	end
	if hooks then
		hooks.onJoin(player)
	end
	table.insert(members, { player = player, ready = false })
	publish()
	message(player, if #members == 1 then "You lead the co-op party" else "You joined the co-op party", true)
end

local function toggleReady(player: Player)
	local index = indexOf(player)
	if not index then
		message(player, "Join the party first", false)
		return
	end
	local member = members[index]
	if not member.ready then
		local ok, reason = InventoryService.hasValidLoadout(player)
		if not ok then
			message(player, reason, false)
			return
		end
	end
	member.ready = not member.ready
	publish()
end

local function startParty(player: Player)
	local index = indexOf(player)
	if index ~= 1 then
		message(player, "Only the party leader can start", false)
		return
	end
	local currentHooks = hooks
	if not currentHooks then
		return
	end
	if currentHooks.isArenaBusy() then
		message(player, "The arena is busy. Watch from the TRIBUNES!", false)
		return
	end
	local ready = {}
	for _, member in members do
		if member.ready and member.player.Parent then
			table.insert(ready, member.player)
		end
	end
	if #ready == 0 then
		message(player, "At least one member must be READY", false)
		return
	end
	if currentHooks.start(ready) then
		for _, participant in ready do
			PartyService.remove(participant)
		end
	end
end

local function prompt(host: BasePart, action: string, objectText: string, callback: (Player) -> ())
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = objectText
	p.HoldDuration = 0.3
	p.MaxActivationDistance = 9
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.F
	p.GamepadKeyCode = Enum.KeyCode.DPadUp
	p.Parent = host
	local last: { [Player]: number } = {}
	p.Triggered:Connect(function(player)
		local now = os.clock()
		if last[player] and now - last[player] < 0.6 then
			return -- no accidental double activation
		end
		last[player] = now
		callback(player)
	end)
end

function PartyService.init(folder: Instance, joinPost: BasePart, readyPost: BasePart, startPost: BasePart, boardLabel: TextLabel, newHooks: Hooks)
	lobbyFolder = folder
	board = boardLabel
	hooks = newHooks
	prompt(joinPost, "Join / Leave", "CO-OP PARTY", toggleJoin)
	prompt(readyPost, "Ready / Unready", "CO-OP PARTY", toggleReady)
	prompt(startPost, "Start Co-op", "PARTY LEADER", startParty)
	Players.PlayerRemoving:Connect(PartyService.remove)
	publish()
end

function PartyService.isMember(player: Player): boolean
	return indexOf(player) ~= nil
end

return PartyService
