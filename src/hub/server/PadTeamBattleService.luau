--!strict
-- Local, explicit opponents: Schili (Blue) versus Krokero (Red), 1v1 through 4v4.
-- Both captains confirm unchanged equal-size teams. No client supplies members or team IDs.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameStates = require(ReplicatedStorage.Shared.GameStates)
local MatchTypes = require(ReplicatedStorage.Shared.MatchTypes)
local Server = script.Parent.Parent
local CombatUtil = require(Server.CombatUtil)
local InventoryService = require(Server.InventoryService)
local PlayerDataService = require(Server.PlayerDataService)
local LobbyService = require(Server.LobbyService)
local PartyService = require(script.Parent.PartyService)
local MatchmakingService = require(script.Parent.MatchmakingService)
local ArenaReservationService = require(script.Parent.ArenaReservationService)
local HubTeleportService = require(script.Parent.HubTeleportService)

type Pad = LobbyService.PadLayout
type Party = PartyService.Party
local PadTeamBattleService = {}
local layouts: { [string]: Pad } = {}
local confirmations: { [string]: { signature: string, expiresAt: number } } = {}
local busy = false
local IDS = { "TeamSchili", "TeamKrokero" }
local MODE: MatchTypes.MatchMode = "TIME_BATTLE"

local function contains(player: Player, padId: string): boolean
	local pad = layouts[padId]
	local _, _, root = CombatUtil.getLivingCharacter(player)
	if not pad or not root then return false end
	local offset = pad.cframe:PointToObjectSpace(root.Position)
	return math.abs(offset.X) <= pad.size.X / 2 and math.abs(offset.Z) <= pad.size.Z / 2
		and offset.Y >= -2 and offset.Y <= 8
end

function PadTeamBattleService.invalidate()
	table.clear(confirmations)
	for _, player in Players:GetPlayers() do
		player:SetAttribute("TeamPadReady", false)
	end
end

local function members(party: Party, padId: string): ({ Player }?, string)
	if party.locked or #party.members < 1 or #party.members > 4 then
		return nil, "This team is busy or full"
	end
	local result: { Player } = {}
	for _, member in party.members do
		if not member.Parent or not contains(member, padId)
			or not GameStates.isInLobby(member:GetAttribute(GameStates.StateAttribute))
			or not PlayerDataService.isReady(member) or MatchmakingService.isQueued(member) then
			return nil, "Everybody must be on their team mosaic, loaded and outside a queue"
		end
		local valid, reason = InventoryService.hasValidLoadout(member)
		if not valid then return nil, member.DisplayName .. ": " .. reason end
		table.insert(result, member)
	end
	return result, ""
end

function PadTeamBattleService.status(padId: string): string?
	if busy then return "PREPARING TEAM BATTLE" end
	local ready = confirmations[padId]
	if ready and os.clock() >= ready.expiresAt then
		PadTeamBattleService.invalidate()
		return nil
	end
	return if ready then "READY · waiting for the other captain" else nil
end

function PadTeamBattleService.confirm(player: Player, padId: string): (boolean, string)
	if busy then return false, "A team battle is already starting" end
	if not layouts[padId] or not contains(player, padId) then return false, "Stand on your team's mosaic" end
	local own = PartyService.padParty(padId)
	if not own or own.members[1] ~= player then return false, "Your team captain presses READY" end
	local schili = PartyService.padParty(IDS[1])
	local krokero = PartyService.padParty(IDS[2])
	if not schili or not krokero then return false, "Both mosaics need a team first" end
	local blue, blueError = members(schili, IDS[1])
	if not blue then return false, blueError end
	local red, redError = members(krokero, IDS[2])
	if not red then return false, redError end
	if #blue ~= #red then return false, "Use equal teams: 1v1, 2v2, 3v3 or 4v4" end
	local fighters: { MatchTypes.Fighter } = {}
	local all: { Player } = {}
	local seen: { [Player]: boolean } = {}
	local pieces = { schili.id, krokero.id }
	for _, group in { { members = blue, team = "Blue", party = schili }, { members = red, team = "Red", party = krokero } } do
		for _, member in group.members do
			if seen[member] then return false, "A player cannot be on both teams" end
			seen[member] = true
			table.insert(all, member)
			table.insert(pieces, group.team .. ":" .. member.UserId)
			table.insert(fighters, { userId = member.UserId, team = group.team, partyId = group.party.id })
		end
	end
	local signature = table.concat(pieces, "|")
	confirmations[padId] = { signature = signature, expiresAt = os.clock() + 30 }
	for _, member in own.members do member:SetAttribute("TeamPadReady", true) end
	for _, id in IDS do
		local ready = confirmations[id]
		if not ready or ready.signature ~= signature or os.clock() >= ready.expiresAt then
			return true, "Your team is ready · the other captain must confirm"
		end
	end
	busy = true
	PadTeamBattleService.invalidate()
	local function cleanup()
		busy = false
		for _, party in { schili, krokero } do PartyService.setLocked(party, false) end
		for _, member in all do
			if member.Parent and member:GetAttribute(GameStates.StateAttribute) == GameStates.Countdown then
				member:SetAttribute(GameStates.StateAttribute, GameStates.PartyForming)
			end
		end
	end
	for _, party in { schili, krokero } do PartyService.setLocked(party, true) end
	for _, member in all do member:SetAttribute(GameStates.StateAttribute, GameStates.Countdown) end
	local ok, created = pcall(ArenaReservationService.create, MODE, fighters, nil)
	if not ok or not created then
		cleanup()
		return false, "The arena could not be reserved · try again"
	end
	-- Reservation yields: reject a team that has walked away or disconnected meanwhile.
	for _, group in { { members = blue, id = IDS[1] }, { members = red, id = IDS[2] } } do
		for _, member in group.members do
			if not member.Parent or not contains(member, group.id) then
				ArenaReservationService.discard(created.record)
				cleanup()
				return false, "A team changed or left the mosaic · ready up again"
			end
		end
	end
	if not created.mock then task.delay(25, cleanup) end
	local options: HubTeleportService.Options = {
		matchId = created.record.matchId, role = "FIGHTER", mode = MODE, mock = created.mock,
		onFailed = function(member: Player, _code: string)
			if member.Parent then member:SetAttribute(GameStates.StateAttribute, GameStates.PartyForming) end
		end,
	}
	local sentOk = pcall(HubTeleportService.send, all, options)
	if created.mock then
		cleanup()
	end
	if not sentOk then return false, "Travel failed · the teams will unlock shortly" end
	return true, if created.mock then "STUDIO MOCK: Schili versus Krokero created" else "Schili versus Krokero · entering the arena"
end

function PadTeamBattleService.init(pads: { Pad })
	for _, pad in pads do
		if pad.def.Team then layouts[pad.def.Id] = pad end
	end
	Players.PlayerRemoving:Connect(PadTeamBattleService.invalidate)
end
return PadTeamBattleService
