--!strict
-- Runs the lobby's walk-on matchmaking pads (LobbyPadDefinitions, built by LobbyService). Server
-- only: who stands on which pad is measured here from the character's position every
-- UpdateInterval, never reported by a client.
--   Solo pads   stepping on starts a short countdown (SoloCountdown); stepping off cancels it.
--               START NOW skips the wait. The match starts through the same function as the menu.
--   Group pads  stepping on joins the pad's group (PartyService pad party, max 4), stepping off
--               leaves it. The board lists the members (★ = leader). The start pedestals: START
--               (Co-op with the group, alone works too) and queue buttons (press again = stop).
--   Disabled    "COMING SOON": stepping on only shows a short note.
-- Every start goes through the HubMatchService handlers, which validate lobby state, loaded data,
-- loadouts, the party leader and the queue. Pressing a pad's button requires standing on it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameStates = require(ReplicatedStorage.Shared.GameStates)
local Config = require(ReplicatedStorage.Shared.Config)
local LobbyPadDefinitions = require(ReplicatedStorage.Shared.LobbyPadDefinitions)
local Server = script.Parent.Parent
local CombatUtil = require(Server.CombatUtil)
local LobbyService = require(Server.LobbyService)
local PartyService = require(script.Parent.PartyService)
local PadTeamBattleService = require(script.Parent.PadTeamBattleService)

type PadLayout = LobbyService.PadLayout

export type Handlers = {
	playSolo: (player: Player) -> (boolean, string),
	startCoop: (player: Player) -> (boolean, string),
	toggleQueue: (player: Player, mode: string) -> (boolean, string),
	message: (player: Player, text: string, ok: boolean) -> (),
}

local LobbyPadService = {}

local PAD_HEIGHT = 8 -- players up to this high above the pad count as standing on it
local BUTTON_COOLDOWN = 0.6

local pads: { PadLayout } = {}
local onPad: { [Player]: PadLayout } = {}
local countdowns: { [Player]: { pad: PadLayout, endsAt: number } } = {}
local lastPress: { [Player]: number } = {}

local function padAt(position: Vector3): PadLayout?
	for _, pad in pads do
		local offset = pad.cframe:PointToObjectSpace(position)
		if math.abs(offset.X) <= pad.size.X / 2 and math.abs(offset.Z) <= pad.size.Z / 2 and offset.Y >= -2 and offset.Y <= PAD_HEIGHT then
			return pad
		end
	end
	return nil
end

local function standingPad(player: Player): PadLayout?
	if not GameStates.isInLobby(player:GetAttribute(GameStates.StateAttribute)) then
		return nil
	end
	local _, _, root = CombatUtil.getLivingCharacter(player)
	return if root then padAt(root.Position) else nil
end

local function namesOn(pad: PadLayout): { string }
	local names = {}
	for player, current in onPad do
		if current == pad then
			table.insert(names, player.DisplayName)
		end
	end
	table.sort(names)
	return names
end

-- Board text of one pad (set only when it changed)
local function refreshBoard(pad: PadLayout)
	local def = pad.def
	if not def.Enabled then
		return
	end
	local text: string
	if def.Kind == "Group" then
		local party = PartyService.padParty(def.Id)
		if not party and not def.Team then
			for player,current in onPad do
				if current==pad then party=PartyService.get(player); if party then break end end
			end
		end
		if party and #party.members > 0 then
			local lines = {}
			for i, member in party.members do
				table.insert(lines, (if i == 1 then "★ " else "") .. member.DisplayName .. (if party.ready[member] then " · READY" else " · waiting"))
			end
			table.insert(lines, if party.locked then "STARTING…" elseif def.Team then (PadTeamBattleService.status(def.Id) or ("%d / %d · captain presses READY"):format(#party.members, LobbyPadDefinitions.MaxGroup)) else ("%d / %d · leader presses START"):format(#party.members, LobbyPadDefinitions.MaxGroup))
			local queue=party.members[1]:GetAttribute(Config.QueueStatusAttribute)
			if typeof(queue)=="string" and queue~="" then table.insert(lines,"QUEUE · "..queue) end
			text = table.concat(lines, "\n")
		else
			text = if def.Team then "Stand on the mosaic to join this team" else "Stand on the mosaic to form a group"
		end
	else
		local waiting = {}
		local now = os.clock()
		for player, pending in countdowns do
			if pending.pad == pad then
				table.insert(waiting, ("%s · %d"):format(player.DisplayName, math.max(1, math.ceil(pending.endsAt - now))))
			end
		end
		table.sort(waiting)
		text = if #waiting > 0 then "STARTING\n" .. table.concat(waiting, "\n") else "Walk on the pad to start"
	end
	if pad.status.Text ~= text then
		pad.status.Text = text
	end
	local occupied = #namesOn(pad) > 0
	local transparency = if occupied then 0 else 0.35
	if pad.ring.Transparency ~= transparency then
		pad.ring.Transparency = transparency
	end
end

local function enter(player: Player, pad: PadLayout, handlers: Handlers)
	local def = pad.def
	if def.Team then PadTeamBattleService.invalidate() end
	if not def.Enabled then
		handlers.message(player, ("%s · COMING SOON"):format(def.Title), false)
		return
	end
	if def.Kind == "Solo" then
		countdowns[player] = { pad = pad, endsAt = os.clock() + LobbyPadDefinitions.SoloCountdown }
		handlers.message(player, ("%s starts in %d · stay on the pad"):format(def.Title, LobbyPadDefinitions.SoloCountdown), true)
	else
		local ok, text = PartyService.joinPadParty(player, def.Id)
		if text ~= "" then
			handlers.message(player, text, ok)
		end
	end
end

local function leave(player: Player, pad: PadLayout, handlers: Handlers)
	local def = pad.def
	if def.Team then PadTeamBattleService.invalidate() end
	if def.Kind == "Solo" then
		if countdowns[player] and countdowns[player].pad == pad then
			countdowns[player] = nil
			if player.Parent and GameStates.isInLobby(player:GetAttribute(GameStates.StateAttribute)) then
				handlers.message(player, "Start cancelled", false)
			end
		end
	elseif def.Enabled then
		if PartyService.leavePadParty(player, def.Id) and player.Parent then
			handlers.message(player, "You left the group", true)
		end
	end
end

local function startSolo(player: Player, pad: PadLayout, handlers: Handlers)
	countdowns[player] = nil
	local ok, text
	if pad.def.Mode == "SOLO_ZOMBIES" then
		ok, text = handlers.playSolo(player)
	else
		ok, text = false, pad.def.Title .. " is not available yet"
	end
	if text ~= "" then
		handlers.message(player, text, ok)
	end
end

local function addButton(pad: PadLayout, action: string, part: BasePart, handlers: Handlers)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = if action == "Ready" then "Ready / not ready" elseif action == "LeaveGroup" then "Leave group" elseif action == "ConfirmTeam" then "Ready team" elseif action == "StartCoop" or action == "StartNow" then "Start" else "Search / Stop"
	prompt.ObjectText = pad.def.Title
	prompt.HoldDuration = 0.3
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.DPadUp
	prompt.Parent = part
	prompt.Triggered:Connect(function(player: Player)
		local now = os.clock()
		if now - (lastPress[player] or 0) < BUTTON_COOLDOWN then
			return
		end
		lastPress[player] = now
		local _,_,root=CombatUtil.getLivingCharacter(player)
		if not root or (root.Position-part.Position).Magnitude>15 then return end
		if standingPad(player) ~= pad then
			handlers.message(player, "Step on the " .. pad.def.Title .. " pad first", false)
			return
		end
		local ok, text
		if action == "StartNow" then
			startSolo(player, pad, handlers)
			return
		elseif action == "Ready" then
			ok, text = PartyService.setReady(player, nil)
		elseif action == "LeaveGroup" then
			ok = PartyService.leavePadParty(player, pad.def.Id)
			text = if ok then "You left the group" else "Leave the queue first, or use your party menu"
		elseif action == "ConfirmTeam" then
			ok, text = PadTeamBattleService.confirm(player, pad.def.Id)
		elseif action == "StartCoop" then
			ok, text = handlers.startCoop(player)
		else
			ok, text = handlers.toggleQueue(player, action)
		end
		if text ~= "" then
			handlers.message(player, text, ok)
		end
	end)
end

function LobbyPadService.init(layouts: { PadLayout }, handlers: Handlers)
	pads = layouts
	PadTeamBattleService.init(layouts)
	for _, pad in pads do
		for _, button in pad.buttons do
			addButton(pad, button.action, button.part, handlers)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		onPad[player] = nil
		countdowns[player] = nil
		lastPress[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(LobbyPadDefinitions.UpdateInterval)
			local now = os.clock()
			for _, player in Players:GetPlayers() do
				local current = standingPad(player)
				local previous = onPad[player]
				if current ~= previous then
					if current then
						onPad[player] = current
					else
						onPad[player] = nil
					end
					if previous then
						leave(player, previous, handlers)
					end
					if current then
						enter(player, current, handlers)
					end
				end
				local pending = countdowns[player]
				if pending and now >= pending.endsAt then
					if onPad[player] == pending.pad then
						startSolo(player, pending.pad, handlers)
					else
						countdowns[player] = nil
					end
				end
			end
			for _, pad in pads do
				refreshBoard(pad)
			end
		end
	end)
end

return LobbyPadService
