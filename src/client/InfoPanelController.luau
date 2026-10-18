--!strict
-- The optional information panel behind the small "i" button: mode, full controls, weapon,
-- shield, special moves, combos, round details, rosters and Aura rewards. Closed by default in
-- combat and closed automatically when a phone enters combat; a close button and a tap outside
-- close it; the content scrolls. When closed, nothing of it remains on screen or catches input.
-- It only pauses local presentation; the server game keeps running.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UiConfig"))

export type InfoPanel = {
	open: () -> (),
	close: () -> (),
	isOpen: () -> boolean,
	onStateChanged: (state: string, layout: { device: string, touch: boolean }) -> (),
}

local InfoPanelController = {}

function InfoPanelController.start(gui: ScreenGui, edge: Frame, content: () -> string): InfoPanel
	local button = Instance.new("TextButton")
	button.Name = "Info"
	button.Size = UDim2.fromOffset(44, 44)
	button.BackgroundColor3 = UiConfig.Panel
	button.BackgroundTransparency = 0.35
	button.Font = Enum.Font.GothamBlack
	button.TextSize = 20
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Text = "i"
	button.LayoutOrder = 2
	button.Parent = edge
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = button

	-- Tap outside closes the panel; only exists (Visible) while the panel is open
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "InfoBackdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.6
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Visible = false
	backdrop.ZIndex = 20
	backdrop.Parent = gui

	local panel = Instance.new("Frame")
	panel.Name = "InfoPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.9, 0.8)
	panel.BackgroundColor3 = UiConfig.Panel
	panel.BackgroundTransparency = 0.05
	panel.Visible = false
	panel.ZIndex = 21
	panel.Parent = gui
	local size = Instance.new("UISizeConstraint")
	size.MaxSize = Vector2.new(560, 640)
	size.Parent = panel
	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = panel

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "Close"
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -6, 0, 6)
	closeButton.Size = UDim2.fromOffset(44, 44)
	closeButton.BackgroundTransparency = 1
	closeButton.Font = Enum.Font.GothamBlack
	closeButton.TextSize = 22
	closeButton.TextColor3 = Color3.new(1, 1, 1)
	closeButton.Text = "✕"
	closeButton.ZIndex = 23
	closeButton.Parent = panel

	local scroll = Instance.new("ScrollingFrame")
	scroll.Position = UDim2.fromOffset(12, 50)
	scroll.Size = UDim2.new(1, -24, 1, -62)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ZIndex = 22
	scroll.Parent = panel
	local text = Instance.new("TextLabel")
	text.Size = UDim2.new(1, -8, 0, 0)
	text.AutomaticSize = Enum.AutomaticSize.Y
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamMedium
	text.TextSize = 14
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.TextWrapped = true
	text.RichText = true
	text.ZIndex = 22
	text.Parent = scroll

	local isOpen = false
	local function setOpen(open: boolean)
		isOpen = open
		if open then
			text.Text = content()
			scroll.CanvasPosition = Vector2.zero
		end
		panel.Visible = open
		backdrop.Visible = open
	end
	button.Activated:Connect(function()
		setOpen(not isOpen)
	end)
	closeButton.Activated:Connect(function()
		setOpen(false)
	end)
	backdrop.Activated:Connect(function()
		setOpen(false)
	end)

	local lastState = ""
	return {
		open = function()
			setOpen(true)
		end,
		close = function()
			setOpen(false)
		end,
		isOpen = function()
			return isOpen
		end,
		onStateChanged = function(state: string, layout: { device: string, touch: boolean })
			if state ~= lastState then
				local enteringCombat = state ~= "Lobby" and lastState == "Lobby"
				if isOpen and (enteringCombat or layout.touch) and state ~= "Lobby" then
					setOpen(false) -- closed in combat (always on phones)
				elseif state == "Lobby" and UiConfig.InfoPanelOpenInLobbyOnDesktop and layout.device == "Desktop" and lastState == "" then
					setOpen(true)
				end
				lastState = state
			end
		end,
	}
end

return InfoPanelController
