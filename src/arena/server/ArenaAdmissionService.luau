--!strict
-- Validates every player arriving at this reserved Arena server. TeleportData only hints the
-- match id and role; everything is checked server-side:
--   1. the match record exists, belongs to THIS reserved server (game.PrivateServerId) and uses a
--      compatible protocol (else GAME UPDATE IN PROGRESS)
--   2. the one-time ticket "<matchId>:<userId>" is consumed atomically (exists, not expired, not
--      consumed, same user / match, valid role, compatible protocol)
--   3. the role is still accepted: fighters only if listed in the match record and before the
--      start; spectators while the match is joinable and below capacity (reservation consumed)
-- Rejected players see a compact message and are sent back to the Hub. Capacity is tracked for
-- concurrent joins: admitted / connected fighters and spectators plus admissions in progress.
-- Mock mode (Studio): no tickets; the first players become fighters of the configured mock match,
-- later ones spectators.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)
local Config = require(ReplicatedStorage.Shared.Config)
local EnvironmentConfig = require(ReplicatedStorage.Shared.EnvironmentConfig)
local ExperienceConfig = require(ReplicatedStorage.Shared.ExperienceConfig)
local GameProtocol = require(ReplicatedStorage.Shared.GameProtocol)
local MatchDefinitions = require(ReplicatedStorage.Shared.MatchDefinitions)
local MatchTypes = require(ReplicatedStorage.Shared.MatchTypes)
local Server = script.Parent.Parent
local AdmissionTicketService = require(Server.AdmissionTicketService)
local MatchRecordService = require(Server.MatchRecordService)
local Remotes = require(Server.Remotes)
local SpectatorSlotService = require(Server.SpectatorSlotService)
local TeleportUtil = require(Server.TeleportUtil)
local ArenaReturnService = require(script.Parent.ArenaReturnService)

local PREFIX = "[OttiArena][Admission]"

type MatchRecord = MatchTypes.MatchRecord

export type Admitted = { role: MatchTypes.Role, team: string }

export type Hooks = {
	fighterAdmitted: (player: Player, team: string) -> (),
	spectatorAdmitted: (player: Player) -> (),
	acceptsFighters: () -> boolean, -- before the match start
	acceptsSpectators: () -> boolean, -- the match is joinable
}

local ArenaAdmissionService = {}

local record: MatchRecord? = nil
local loadingRecord = false
local admitted: { [Player]: Admitted } = {}
local pending = 0
local hooks: Hooks? = nil

local function count(role: string): number
	local n = 0
	for player, entry in admitted do
		if player.Parent and entry.role == role then
			n += 1
		end
	end
	return n
end

local function reject(player: Player, code: string, detail: string)
	warn(PREFIX, ("Rejected %s: %s (%s)"):format(player.Name, code, detail))
	local text = (MatchTypes.Messages :: any)[code] or MatchTypes.Messages.INVALID
	Remotes.CombatFeedback:FireClient(player, CombatConfig.Feedback.Shop, text, false)
	Remotes.MatchEvent:FireClient(player, "Rejected", text)
	task.delay(2, function()
		if player.Parent then
			ArenaReturnService.send({ player }, code)
		end
	end)
end

-- Loads (once) and verifies the match record this server belongs to.
local function loadRecord(matchId: string): (MatchRecord?, string?)
	local current = record
	if current then
		return if current.matchId == matchId then current else nil, "INVALID"
	end
	while loadingRecord do
		task.wait(0.1)
	end
	if record then
		return loadRecord(matchId)
	end
	loadingRecord = true
	local loaded = MatchRecordService.getMatch(matchId)
	loadingRecord = false
	if not loaded then
		return nil, "ENDED"
	end
	if loaded.privateServerId == "" or loaded.privateServerId ~= game.PrivateServerId then
		return nil, "INVALID" -- a ticket for another server
	end
	if not GameProtocol.isCompatible(loaded.protocol) or not MatchDefinitions.get(loaded.mode) then
		return nil, "UPDATE"
	end
	record = loaded
	return loaded, nil
end

local function fighterEntry(current: MatchRecord, userId: number): MatchTypes.Fighter?
	for _, fighter in current.fighters do
		if fighter.userId == userId then
			return fighter
		end
	end
	return nil
end

local function admit(player: Player)
	local payload = TeleportUtil.joinPayload(player)
	local matchId = if payload and typeof(payload.matchId) == "string" then payload.matchId else nil
	if not matchId or #matchId > 64 then
		reject(player, "INVALID", "no match id")
		return
	end
	local current, problem = loadRecord(matchId)
	if not current then
		reject(player, problem or "INVALID", "match record")
		return
	end
	local ticket, rejection = AdmissionTicketService.consume(matchId, player.UserId)
	if not ticket then
		reject(player, if rejection == "PROTOCOL" then "UPDATE" elseif rejection == "EXPIRED" or rejection == "CONSUMED" then "INVALID" else "UNREACHABLE", tostring(rejection))
		return
	end
	local currentHooks = hooks :: Hooks
	local capacity = ExperienceConfig.Capacity
	if ticket.role == "FIGHTER" then
		local entry = fighterEntry(current, player.UserId)
		if not entry or not currentHooks.acceptsFighters() then
			reject(player, "ENDED", "fighter not expected / match already started")
			return
		end
		if count("FIGHTER") >= math.min(capacity.MaxFighters, #current.fighters) then
			reject(player, "FULL", "fighters full")
			return
		end
		admitted[player] = { role = "FIGHTER", team = entry.team }
		player:SetAttribute(Config.ArenaRoleAttribute, "FIGHTER")
		currentHooks.fighterAdmitted(player, entry.team)
	else
		if not currentHooks.acceptsSpectators() then
			reject(player, "ENDED", "not joinable")
			return
		end
		SpectatorSlotService.consume(matchId, player.UserId)
		if count("SPECTATOR") >= capacity.MaxSpectators then
			reject(player, "FULL", "spectators full")
			return
		end
		admitted[player] = { role = "SPECTATOR", team = "" }
		currentHooks.spectatorAdmitted(player)
	end
	print(PREFIX, ("%s admitted as %s"):format(player.Name, ticket.role))
end

local function admitMock(player: Player)
	local currentHooks = hooks :: Hooks
	if currentHooks.acceptsFighters() and count("FIGHTER") < ExperienceConfig.Capacity.MaxFighters then
		local team = if count("FIGHTER") % 2 == 0 then "Red" else "Blue"
		admitted[player] = { role = "FIGHTER", team = team }
		player:SetAttribute(Config.ArenaRoleAttribute, "FIGHTER")
		currentHooks.fighterAdmitted(player, team)
	else
		admitted[player] = { role = "SPECTATOR", team = "" }
		currentHooks.spectatorAdmitted(player)
	end
end

local function onPlayerAdded(player: Player)
	pending += 1
	local ok, err = pcall(if EnvironmentConfig.isMockMode() then admitMock else admit, player)
	pending -= 1
	if not ok then
		warn(PREFIX, "Admission error:", err)
		reject(player, "UNREACHABLE", "error")
	end
end

function ArenaAdmissionService.getRecord(): MatchRecord?
	return record
end

function ArenaAdmissionService.roleOf(player: Player): MatchTypes.Role?
	local entry = admitted[player]
	return if entry then entry.role else nil
end

function ArenaAdmissionService.fighterCount(): number
	return count("FIGHTER")
end

function ArenaAdmissionService.pendingCount(): number
	return pending
end

-- Fighters admitted so far, with their teams.
function ArenaAdmissionService.fighters(): { { player: Player, team: string } }
	local list = {}
	for player, entry in admitted do
		if player.Parent and entry.role == "FIGHTER" then
			table.insert(list, { player = player, team = entry.team })
		end
	end
	return list
end

-- A fighter whose part is over watches as a spectator from now on.
function ArenaAdmissionService.demote(player: Player)
	local entry = admitted[player]
	if entry then
		entry.role = "SPECTATOR"
	end
end

-- Mock mode only: a fresh local match with the players already here (first `maxFighters` fight).
function ArenaAdmissionService.reassignMock(maxFighters: number): { { player: Player, role: MatchTypes.Role, team: string } }
	local result = {}
	local fighters = 0
	for _, player in Players:GetPlayers() do
		local entry: Admitted
		if fighters < maxFighters then
			entry = { role = "FIGHTER", team = if fighters % 2 == 0 then "Red" else "Blue" }
			fighters += 1
		else
			entry = { role = "SPECTATOR", team = "" }
		end
		admitted[player] = entry
		player:SetAttribute(Config.ArenaRoleAttribute, entry.role)
		table.insert(result, { player = player, role = entry.role, team = entry.team })
	end
	return result
end

function ArenaAdmissionService.init(newHooks: Hooks)
	hooks = newHooks
	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		admitted[player] = nil
	end)
end

return ArenaAdmissionService
