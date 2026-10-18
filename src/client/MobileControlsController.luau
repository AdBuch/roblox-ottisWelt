--!strict
-- Combat controls (presentation only; InputController sends the actions):
--   touch    ATTACK, BLOCK and the two special buttons in an arc around Roblox's jump button
--            (UiConfig.TouchLayoutPhone / Tablet), 50-56 px targets, short labels, dark
--            cooldown overlay; never on the thumbstick side, never on the health bar
--   desktop  two small special cards bottom-right (key + short name + cooldown)
-- Touch combat buttons belong to the "Controls" group, which every HUD mode keeps.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UiConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UiConfig"))

type Visibility = {
	register: (group: string, element: GuiObject, wanted: (() -> boolean)?, forced: (() -> boolean)?) -> (),
}
type Layout = { device: string, touch: boolean, portrait: boolean }

export type SpecialCard = {
	setMove: (key: string, name: string) -> (),
	startCooldown: (seconds: number) -> (),
}

export type Controls = {
	special1: SpecialCard,
	special2: SpecialCard,
	attackButton: TextButton,
	blockButton: TextButton,
	special1Button: TextButton,
	special2Button: TextButton,
	setBlocking: (blocking: boolean) -> (),
}

local MobileControlsController = {}

local function round(button: GuiObject)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = button
end

-- A button with a short label and a cooldown overlay (pooled once, reused for the whole session).
local function makeButton(parent: Instance, name: string, text: string, color: Color3, size: number): (TextButton, Frame, TextLabel)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Size = UDim2.fromOffset(size, size)
	button.BackgroundColor3 = color
	button.BackgroundTransparency = 0.25
	button.AutoButtonColor = true
	button.Font = Enum.Font.GothamBlack
	button.TextSize = 13
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextStrokeTransparency = 0.5
	button.Text = text
	button.Parent = parent
	round(button)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0.6
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	local overlay = Instance.new("Frame")
	overlay.Name = "Cooldown"
	overlay.AnchorPoint = Vector2.new(0, 1)
	overlay.Position = UDim2.fromScale(0, 1)
	overlay.Size = UDim2.fromScale(1, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.4
	overlay.BorderSizePixel = 0
	overlay.Active = false
	overlay.Parent = button
	round(overlay)
	local timer = Instance.new("TextLabel")
	timer.Size = UDim2.fromScale(1, 1)
	timer.BackgroundTransparency = 1
	timer.Font = Enum.Font.GothamBold
	timer.TextSize = 14
	timer.TextColor3 = Color3.new(1, 1, 1)
	timer.Text = ""
	timer.Active = false
	timer.Parent = button
	return button, overlay, timer
end

local function cooldown(overlay: Frame, timer: TextLabel): (number) -> ()
	local token = 0
	return function(seconds: number)
		token += 1
		local myToken = token
		overlay.Size = UDim2.fromScale(1, 1)
		TweenService:Create(overlay, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 0) }):Play()
		task.spawn(function()
			local endTime = os.clock() + seconds
			while token == myToken and os.clock() < endTime do
				timer.Text = ("%.0f"):format(math.ceil(endTime - os.clock()))
				task.wait(0.2)
			end
			if token == myToken then
				timer.Text = ""
			end
		end)
	end
end

local function shortName(name: string): string
	local first = name:match("^(%S+)") or name
	return if #first > 7 then first:sub(1, 6) .. "." else first
end

function MobileControlsController.start(group: (string, Vector2, UDim2, UDim2?) -> Frame, visibility: Visibility, onLayout: ((Layout) -> ()) -> (), isTouch: () -> boolean): Controls
	------------------------------------------------------------------ touch buttons
	local touchFrame = group("TouchControls", Vector2.new(1, 1), UDim2.fromScale(1, 1), UDim2.fromOffset(320, 420))
	local attack = makeButton(touchFrame, "Attack", "ATK", Color3.fromRGB(170, 60, 40), UiConfig.TouchButtonSize)
	local block = makeButton(touchFrame, "Block", "BLOCK", Color3.fromRGB(40, 90, 160), UiConfig.TouchButtonSize)
	local s1Button, s1Overlay, s1Timer = makeButton(touchFrame, "Special1", "S1", UiConfig.Panel, UiConfig.TouchSpecialSize)
	local s2Button, s2Overlay, s2Timer = makeButton(touchFrame, "Special2", "S2", UiConfig.Panel, UiConfig.TouchSpecialSize)
	for _, button in { s1Button, s2Button } do
		button.TextSize = 11
		button.TextWrapped = true
		local stroke = button:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = UiConfig.Gold
			stroke.Transparency = 0.2
		end
	end
	visibility.register("Controls", touchFrame, isTouch)

	------------------------------------------------------------------ desktop special cards
	local cardsFrame = group("SpecialCards", Vector2.new(1, 1), UDim2.new(1, -12, 1, -12), UDim2.fromOffset(2 * UiConfig.DesktopSpecialSize + 8, UiConfig.DesktopSpecialSize))
	local function card(index: number): (TextButton, Frame, TextLabel, TextLabel, TextLabel)
		local button, overlay, timer = makeButton(cardsFrame, "Card" .. index, "", UiConfig.Panel, UiConfig.DesktopSpecialSize)
		button.AnchorPoint = Vector2.new(0, 0)
		button.Position = UDim2.fromOffset((index - 1) * (UiConfig.DesktopSpecialSize + 8), 0)
		local corner = button:FindFirstChildOfClass("UICorner")
		if corner then
			corner.CornerRadius = UDim.new(0, 10)
		end
		local overlayCorner = overlay:FindFirstChildOfClass("UICorner")
		if overlayCorner then
			overlayCorner.CornerRadius = UDim.new(0, 10)
		end
		local key = Instance.new("TextLabel")
		key.Size = UDim2.new(1, 0, 0, 22)
		key.Position = UDim2.fromOffset(0, 6)
		key.BackgroundTransparency = 1
		key.Font = Enum.Font.GothamBlack
		key.TextSize = 20
		key.TextColor3 = UiConfig.Gold
		key.Text = if index == 1 then "Q" else "E"
		key.Parent = button
		local moveName = Instance.new("TextLabel")
		moveName.Size = UDim2.new(1, -6, 0, 26)
		moveName.Position = UDim2.fromOffset(3, 32)
		moveName.BackgroundTransparency = 1
		moveName.Font = Enum.Font.GothamBold
		moveName.TextSize = 10
		moveName.TextWrapped = true
		moveName.TextColor3 = Color3.new(1, 1, 1)
		moveName.Parent = button
		timer.ZIndex = 2
		return button, overlay, key, moveName, timer
	end
	local _, c1Overlay, c1Key, c1Name, c1Timer = card(1)
	local _, c2Overlay, c2Key, c2Name, c2Timer = card(2)
	visibility.register("Specials", cardsFrame, function()
		return not isTouch()
	end)

	onLayout(function(layout: Layout)
		local positions = if layout.device == "Phone" then UiConfig.TouchLayoutPhone else UiConfig.TouchLayoutTablet
		attack.Position = UDim2.new(1, -positions.Attack.X, 1, -positions.Attack.Y)
		block.Position = UDim2.new(1, -positions.Block.X, 1, -positions.Block.Y)
		s1Button.Position = UDim2.new(1, -positions.Special1.X, 1, -positions.Special1.Y)
		s2Button.Position = UDim2.new(1, -positions.Special2.X, 1, -positions.Special2.Y)
	end)

	local s1Cooldown = cooldown(s1Overlay, s1Timer)
	local s2Cooldown = cooldown(s2Overlay, s2Timer)
	local c1Cooldown = cooldown(c1Overlay, c1Timer)
	local c2Cooldown = cooldown(c2Overlay, c2Timer)

	return {
		special1 = {
			setMove = function(keyText: string, name: string)
				c1Key.Text = keyText
				c1Name.Text = name
				s1Button.Text = shortName(name)
			end,
			startCooldown = function(seconds: number)
				s1Cooldown(seconds)
				c1Cooldown(seconds)
			end,
		},
		special2 = {
			setMove = function(keyText: string, name: string)
				c2Key.Text = keyText
				c2Name.Text = name
				s2Button.Text = shortName(name)
			end,
			startCooldown = function(seconds: number)
				s2Cooldown(seconds)
				c2Cooldown(seconds)
			end,
		},
		attackButton = attack,
		blockButton = block,
		special1Button = s1Button,
		special2Button = s2Button,
		setBlocking = function(blocking: boolean)
			block.BackgroundTransparency = if blocking then 0 else 0.25
			local stroke = block:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Transparency = if blocking then 0 else 0.6
			end
		end,
	}
end

return MobileControlsController
