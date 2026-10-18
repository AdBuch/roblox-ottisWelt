--!strict
-- The one HUD. Replaces the old desktop HUD (upper-left/bottom-left info panel, header, target bar,
-- permanent Aura panel): everything is compact, anchored to edges and scaled per device.
--   * layout: device class (Phone / Tablet / Desktop / Console), orientation and scale from the
--     viewport, the last input type and touch support; recomputed when they change
--   * groups: every HUD part lives in an anchored container with its own UIScale (UiConfig)
--   * built-in widgets: compact player health (bottom-left, above the thumbstick on phones),
--     the slim round line (top centre) and a short control hint (desktop/gamepad, fades in combat)
-- Safe areas: ScreenInsets = CoreUISafeInsets keeps everything below Roblox's top bar and notches.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local UiConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UiConfig"))

export type Layout = {
	device: string, -- Phone | Tablet | Desktop | Console
	portrait: boolean,
	touch: boolean,
	gamepad: boolean,
	viewport: Vector2,
	scale: number,
	narrow: boolean,
}

export type Hud = {
	gui: ScreenGui,
	layout: Layout,
	onLayout: (callback: (Layout) -> ()) -> (),
	group: (name: string, anchor: Vector2, position: UDim2, size: UDim2?) -> Frame,
	setHealth: (health: number, maxHealth: number) -> (),
	healthFrame: Frame,
	isLowHealth: () -> boolean,
	setRoundLine: (text: string?, keep: boolean?) -> (),
	roundFrame: Frame,
	roundVisible: () -> boolean,
	setHint: (text: string?) -> (),
	fadeHint: () -> (),
	hintFrame: Frame,
	flashHit: (blocked: boolean) -> (),
}

local ResponsiveHudController = {}

local function corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 6)
	c.Parent = parent
end

local function computeLayout(): Layout
	local camera = Workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	local shortest = math.min(viewport.X, viewport.Y)
	local lastInput = UserInputService:GetLastInputType()
	local gamepad = lastInput.Name:sub(1, 7) == "Gamepad" or GuiService:IsTenFootInterface()
	local touch = UserInputService.TouchEnabled and not gamepad
	local portrait = viewport.Y > viewport.X
	local device = "Desktop"
	if GuiService:IsTenFootInterface() then
		device = "Console"
	elseif touch and shortest < UiConfig.MobileBreakpoint then
		device = "Phone"
	elseif touch and shortest < UiConfig.TabletBreakpoint then
		device = "Tablet"
	elseif touch then
		device = "Tablet"
	end
	local scale = if device == "Phone"
		then (if portrait then UiConfig.MobilePortraitScale else UiConfig.MobileLandscapeScale)
		elseif device == "Tablet" then UiConfig.TabletScale
		elseif device == "Console" then UiConfig.ConsoleScale
		else UiConfig.DesktopScale * math.clamp(viewport.Y / 900, 0.85, 1.25)
	return {
		device = device,
		portrait = portrait,
		touch = touch,
		gamepad = gamepad,
		viewport = viewport,
		scale = scale,
		narrow = viewport.X < UiConfig.HideHealthNumberBelowWidth,
	}
end

function ResponsiveHudController.create(playerGui: Instance): Hud
	for _, name in { "OttiArenaHud", "OttiArenaTouchControls" } do
		local existing = playerGui:FindFirstChild(name)
		if existing then
			existing:Destroy()
		end
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "OttiArenaHud"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	pcall(function()
		gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	end)

	local listeners: { (Layout) -> () } = {}
	local scales: { UIScale } = {}
	local layout = computeLayout()

	local function group(name: string, anchor: Vector2, position: UDim2, size: UDim2?): Frame
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.AnchorPoint = anchor
		frame.Position = position
		frame.Size = size or UDim2.fromOffset(0, 0)
		frame.BackgroundTransparency = 1
		frame.Active = false -- containers never swallow input
		frame.Parent = gui
		local scale = Instance.new("UIScale")
		scale.Scale = layout.scale
		scale.Parent = frame
		table.insert(scales, scale)
		return frame
	end

	------------------------------------------------------------------ hit flash on the screen EDGES only
	local edges: { Frame } = {}
	for _, edge in {
		{ size = UDim2.new(1, 0, 0.12, 0), position = UDim2.fromScale(0, 0), rotation = 90 },
		{ size = UDim2.new(1, 0, 0.12, 0), position = UDim2.fromScale(0, 0.88), rotation = -90 },
		{ size = UDim2.new(0.08, 0, 1, 0), position = UDim2.fromScale(0, 0), rotation = 0 },
		{ size = UDim2.new(0.08, 0, 1, 0), position = UDim2.fromScale(0.92, 0), rotation = 180 },
	} do
		local frame = Instance.new("Frame")
		frame.Name = "HitEdge"
		frame.Size = edge.size
		frame.Position = edge.position
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.Active = false
		frame.Parent = gui
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = edge.rotation
		gradient.Transparency = NumberSequence.new(0, 1)
		gradient.Parent = frame
		table.insert(edges, frame)
	end

	------------------------------------------------------------------ compact player health
	local healthFrame = group("PlayerHealth", Vector2.new(0, 1), UDim2.new(0, 16, 1, -24), UDim2.fromOffset(UiConfig.HealthBarWidthDesktop, UiConfig.HealthBarHeight))
	local heart = Instance.new("TextLabel")
	heart.Name = "Heart"
	heart.Size = UDim2.fromOffset(UiConfig.HealthBarHeight, UiConfig.HealthBarHeight)
	heart.BackgroundTransparency = 1
	heart.Text = "♥"
	heart.Font = Enum.Font.GothamBlack
	heart.TextScaled = true
	heart.TextColor3 = UiConfig.HealthLow
	heart.TextStrokeTransparency = 0.5
	heart.Parent = healthFrame
	local back = Instance.new("Frame")
	back.Position = UDim2.fromOffset(UiConfig.HealthBarHeight + 4, 3)
	back.Size = UDim2.new(1, -(UiConfig.HealthBarHeight + 4), 1, -6)
	back.BackgroundColor3 = Color3.fromRGB(35, 22, 18)
	back.BackgroundTransparency = 0.25
	back.BorderSizePixel = 0
	back.Parent = healthFrame
	corner(back, 5)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = UiConfig.HealthHigh
	fill.BorderSizePixel = 0
	fill.Parent = back
	corner(fill, 5)
	local glow = Instance.new("UIStroke")
	glow.Color = Color3.fromRGB(140, 255, 140)
	glow.Thickness = 2
	glow.Transparency = 1
	glow.Parent = back
	local number = Instance.new("TextLabel")
	number.Size = UDim2.fromScale(1, 1)
	number.BackgroundTransparency = 1
	number.Font = Enum.Font.GothamBold
	number.TextSize = 12
	number.TextColor3 = Color3.new(1, 1, 1)
	number.TextStrokeTransparency = 0.4
	number.Parent = back
	local pulse = Instance.new("UIScale")
	pulse.Parent = back
	local lastHealth = -1
	local lowHealth = false

	local function setHealth(health: number, maxHealth: number)
		local share = math.clamp(health / math.max(1, maxHealth), 0, 1)
		fill.Size = UDim2.fromScale(share, 1)
		fill.BackgroundColor3 = if share > 0.5 then UiConfig.HealthHigh elseif share > UiConfig.LowHealthShare then UiConfig.HealthMid else UiConfig.HealthLow
		number.Text = ("%d / %d"):format(math.ceil(health), maxHealth)
		lowHealth = health > 0 and share <= UiConfig.LowHealthShare
		if lastHealth >= 0 and health < lastHealth then
			pulse.Scale = 1.15 -- brief pulse when damaged
			TweenService:Create(pulse, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		elseif lastHealth >= 0 and health > lastHealth then
			glow.Transparency = 0.1 -- soft glow when healed
			TweenService:Create(glow, TweenInfo.new(0.6), { Transparency = 1 }):Play()
		end
		lastHealth = health
	end

	------------------------------------------------------------------ round line (top centre)
	local roundFrame = group("RoundLine", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 6), UDim2.fromOffset(260, 24))
	local roundLabel = Instance.new("TextLabel")
	roundLabel.Size = UDim2.fromScale(1, 1)
	roundLabel.BackgroundColor3 = Color3.new(0, 0, 0)
	roundLabel.BackgroundTransparency = 0.6
	roundLabel.Font = Enum.Font.GothamBold
	roundLabel.TextSize = 14
	roundLabel.TextColor3 = Color3.new(1, 1, 1)
	roundLabel.TextStrokeTransparency = 0.6
	roundLabel.Text = ""
	roundLabel.Parent = roundFrame
	corner(roundLabel, 12)
	local roundShownUntil = 0
	local roundText: string? = nil
	local roundKeep = false

	local function setRoundLine(text: string?, keep: boolean?)
		if text ~= roundText then
			roundShownUntil = os.clock() + UiConfig.RoundIndicatorSeconds -- show briefly on every change
		end
		roundText = text
		roundKeep = keep == true
		roundLabel.Text = text or ""
	end

	------------------------------------------------------------------ control hint (bottom centre)
	local hintFrame = group("ControlHint", Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -8), UDim2.fromOffset(420, 20))
	local hintLabel = Instance.new("TextLabel")
	hintLabel.Size = UDim2.fromScale(1, 1)
	hintLabel.BackgroundTransparency = 1
	hintLabel.Font = Enum.Font.GothamMedium
	hintLabel.TextSize = 13
	hintLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
	hintLabel.TextStrokeTransparency = 0.5
	hintLabel.Parent = hintFrame
	local hintToken = 0

	local hud: Hud
	local function applyLayout()
		layout = computeLayout()
		hud.layout = layout
		for _, scale in scales do
			scale.Scale = layout.scale
		end
		-- Health: above the thumbstick on touch devices, bottom-left on desktop
		if layout.device == "Phone" then
			healthFrame.Position = UDim2.new(0, 16, 1, -UiConfig.HealthBarBottomPhone)
			healthFrame.Size = UDim2.fromOffset(layout.viewport.X * UiConfig.HealthBarWidthPhone / layout.scale, UiConfig.HealthBarHeight)
		elseif layout.device == "Tablet" then
			healthFrame.Position = UDim2.new(0, 20, 1, -UiConfig.HealthBarBottomTablet)
			healthFrame.Size = UDim2.fromOffset(UiConfig.HealthBarWidthDesktop, UiConfig.HealthBarHeight)
		else
			healthFrame.Position = UDim2.new(0, 16, 1, -UiConfig.HealthBarBottomDesktop)
			healthFrame.Size = UDim2.fromOffset(UiConfig.HealthBarWidthDesktop, UiConfig.HealthBarHeight)
		end
		number.Visible = not layout.narrow
		for _, callback in listeners do
			task.spawn(callback, layout)
		end
	end

	hud = {
		gui = gui,
		layout = layout,
		onLayout = function(callback: (Layout) -> ())
			table.insert(listeners, callback)
			task.spawn(callback, layout)
		end,
		group = group,
		setHealth = setHealth,
		healthFrame = healthFrame,
		isLowHealth = function()
			return lowHealth
		end,
		setRoundLine = setRoundLine,
		roundFrame = roundFrame,
		roundVisible = function()
			return roundText ~= nil and roundText ~= "" and (roundKeep or os.clock() < roundShownUntil)
		end,
		setHint = function(text: string?)
			hintToken += 1
			hintLabel.Text = text or ""
			hintLabel.TextTransparency = 0
			hintLabel.TextStrokeTransparency = 0.5
		end,
		fadeHint = function()
			hintToken += 1
			local myToken = hintToken
			task.delay(4, function()
				if hintToken == myToken then
					TweenService:Create(hintLabel, TweenInfo.new(1), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
				end
			end)
		end,
		hintFrame = hintFrame,
		flashHit = function(blocked: boolean)
			for _, edge in edges do
				edge.BackgroundColor3 = if blocked then Color3.fromRGB(150, 200, 255) else Color3.fromRGB(255, 40, 30)
				edge.BackgroundTransparency = 0.4
				TweenService:Create(edge, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
			end
		end,
	}

	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
	end
	local lastTouch = layout.touch
	local lastGamepad = layout.gamepad
	UserInputService.LastInputTypeChanged:Connect(function()
		local next = computeLayout()
		if next.touch ~= lastTouch or next.gamepad ~= lastGamepad then
			lastTouch, lastGamepad = next.touch, next.gamepad
			applyLayout()
		end
	end)
	gui.Parent = playerGui
	applyLayout()
	return hud
end

return ResponsiveHudController
