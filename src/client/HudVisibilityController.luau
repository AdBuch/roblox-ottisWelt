--!strict
-- Decides what is visible: a HUD group shows only if the current UI state allows it
-- (UiStateDefinitions.States), the HUD mode allows it (Full / Minimal / Hidden) and the element
-- itself has something to show. Some elements are "forced" (low-health warning, critical
-- warnings): they show in every mode.
-- Mode control: a small eye button on the right edge and the H key (desktop). The chosen mode is
-- a saved preference (Main sends changes to the server, which stores them with the profile).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UiConfig = require(Shared:WaitForChild("UiConfig"))
local UiStateDefinitions = require(Shared:WaitForChild("UiStateDefinitions"))

export type Visibility = {
	register: (group: string, element: GuiObject, wanted: (() -> boolean)?, forced: (() -> boolean)?) -> (),
	allowed: (group: string) -> boolean,
	setState: (state: string) -> (),
	getState: () -> string,
	getMode: () -> string,
	cycleMode: () -> (),
	setMode: (mode: string) -> (), -- silent (saved preference)
	onModeChanged: (callback: (mode: string) -> ()) -> (), -- player changed the mode
	refresh: () -> (),
	onChanged: (callback: () -> ()) -> (),
	button: TextButton,
}

type Entry = { group: string, element: GuiObject, wanted: (() -> boolean)?, forced: (() -> boolean)? }

local HudVisibilityController = {}

local sessionMode: string? = nil -- remembered while the client runs

function HudVisibilityController.create(edge: Frame, notify: (text: string) -> ()): Visibility
	local entries: { Entry } = {}
	local listeners: { () -> () } = {}
	local modeListeners: { (mode: string) -> () } = {}
	local state = "Lobby"
	local mode = sessionMode or UiConfig.DefaultHudMode

	local button = Instance.new("TextButton")
	button.Name = "HudMode"
	button.Size = UDim2.fromOffset(44, 44)
	button.BackgroundColor3 = UiConfig.Panel
	button.BackgroundTransparency = 0.35
	button.Font = Enum.Font.GothamBold
	button.TextSize = 20
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Text = "👁"
	button.LayoutOrder = 1
	button.Parent = edge
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = button

	local function allowed(group: string): boolean
		local states = UiStateDefinitions.States :: any
		local modes = UiStateDefinitions.Modes :: any
		local stateGroups = states[state]
		local modeGroups = modes[mode]
		return stateGroups ~= nil and stateGroups[group] == true and modeGroups ~= nil and modeGroups[group] == true
	end

	local function refresh(fire: boolean?)
		for _, entry in entries do
			local forced = entry.forced ~= nil and entry.forced()
			local wanted = entry.wanted == nil or entry.wanted()
			entry.element.Visible = forced or (wanted and allowed(entry.group))
		end
		button.TextTransparency = if mode == "Full" then 0 elseif mode == "Minimal" then 0.35 else 0.7
		if fire ~= false then
			for _, callback in listeners do
				callback()
			end
		end
	end

	local function cycleMode()
		local order = UiStateDefinitions.ModeOrder
		local index = table.find(order, mode) or 1
		mode = order[index % #order + 1]
		sessionMode = mode
		notify("HUD: " .. mode:upper())
		for _, callback in modeListeners do
			callback(mode)
		end
		refresh()
	end

	button.Activated:Connect(cycleMode)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed and input.KeyCode == UiConfig.HudToggleKey then
			cycleMode()
		end
	end)
	-- Time-based elements (round line timeout, low-health warning) refresh a few times per second
	task.spawn(function()
		while true do
			task.wait(0.25)
			refresh(false)
		end
	end)

	return {
		register = function(group: string, element: GuiObject, wanted: (() -> boolean)?, forced: (() -> boolean)?)
			table.insert(entries, { group = group, element = element, wanted = wanted, forced = forced })
			refresh()
		end,
		allowed = allowed,
		setState = function(newState: string)
			if newState ~= state then
				state = newState
				refresh()
			end
		end,
		getState = function()
			return state
		end,
		getMode = function()
			return mode
		end,
		cycleMode = cycleMode,
		setMode = function(newMode: string)
			if newMode ~= mode and table.find(UiStateDefinitions.ModeOrder, newMode) then
				mode = newMode
				sessionMode = newMode
				refresh()
			end
		end,
		onModeChanged = function(callback: (mode: string) -> ())
			table.insert(modeListeners, callback)
		end,
		refresh = function()
			refresh()
		end,
		onChanged = function(callback: () -> ())
			table.insert(listeners, callback)
		end,
		button = button,
	}
end

return HudVisibilityController
