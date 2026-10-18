--!strict
-- The HUD, built from code. Always visible: AURA at the top. Plus a mode/round header, a
-- target bar, banners, combo popups, a kill feed, the player panel (health, weapon, shield,
-- status, controls) and two special-attack cards with cooldown overlays (tappable on touch).

local TweenService = game:GetService("TweenService")

local CombatHudController = {}

export type SpecialCard = {
	button: TextButton,
	setMove: (key: string, name: string) -> (),
	startCooldown: (seconds: number) -> (),
}

export type HudApi = {
	setAura: (amount: number) -> (),
	setHeader: (title: string, subtitle: string) -> (),
	setHealth: (health: number, maxHealth: number) -> (),
	setLoadout: (weapon: string, shield: string) -> (),
	setStatus: (location: string, state: string, color: Color3) -> (),
	setControlsHint: (text: string) -> (),
	setTarget: (name: string?, health: number, maxHealth: number) -> (),
	setBanner: (title: string?, subtitle: string?, detail: string?) -> (),
	setBlocking: (blocking: boolean) -> (),
	setSpecialsVisible: (visible: boolean) -> (),
	special1: SpecialCard,
	special2: SpecialCard,
	combo: (name: string) -> (),
	popup: (text: string, color: Color3) -> (),
	toast: (text: string, ok: boolean) -> (),
	feed: (text: string) -> (),
	flashHit: (blocked: boolean) -> (),
	gui: ScreenGui,
}

local PANEL = Color3.fromRGB(30, 24, 18)
local GOLD = Color3.fromRGB(255, 205, 70)

local function corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
end

local function label(parent: Instance, name: string, text: string, size: UDim2, position: UDim2, textSize: number, font: Enum.Font?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Text = text
	l.Size = size
	l.Position = position
	l.BackgroundTransparency = 1
	l.Font = font or Enum.Font.GothamMedium
	l.TextSize = textSize
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextStrokeTransparency = 0.6
	l.Parent = parent
	return l
end

local function bar(parent: Instance, position: UDim2, size: UDim2, color: Color3): Frame
	local back = Instance.new("Frame")
	back.Position = position
	back.Size = size
	back.BackgroundColor3 = Color3.fromRGB(45, 25, 20)
	back.BorderSizePixel = 0
	back.Parent = parent
	corner(back, 4)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = back
	corner(fill, 4)
	return fill
end

local function specialCard(parent: Instance, name: string, position: UDim2): SpecialCard
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = ""
	button.AutoButtonColor = true
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = position
	button.Size = UDim2.fromOffset(112, 74)
	button.BackgroundColor3 = PANEL
	button.BackgroundTransparency = 0.15
	button.Parent = parent
	corner(button, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 2
	stroke.Parent = button
	local key = label(button, "Key", "Q", UDim2.new(1, 0, 0, 24), UDim2.fromOffset(0, 4), 22, Enum.Font.GothamBlack)
	key.TextColor3 = GOLD
	local moveName = label(button, "MoveName", "-", UDim2.new(1, -8, 0, 28), UDim2.fromOffset(4, 28), 12, Enum.Font.GothamBold)
	moveName.TextWrapped = true
	local ready = label(button, "Ready", "READY", UDim2.new(1, 0, 0, 14), UDim2.fromOffset(0, 56), 11, Enum.Font.GothamBold)
	ready.TextColor3 = Color3.fromRGB(140, 255, 140)
	local overlay = Instance.new("Frame")
	overlay.Name = "Cooldown"
	overlay.AnchorPoint = Vector2.new(0, 1)
	overlay.Position = UDim2.fromScale(0, 1)
	overlay.Size = UDim2.fromScale(1, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.45
	overlay.BorderSizePixel = 0
	overlay.Parent = button
	corner(overlay, 10)
	local token = 0
	return {
		button = button,
		setMove = function(keyText: string, text: string)
			key.Text = keyText
			moveName.Text = text
		end,
		startCooldown = function(seconds: number)
			token += 1
			local myToken = token
			overlay.Size = UDim2.fromScale(1, 1)
			ready.Text = ("%.1fs"):format(seconds)
			ready.TextColor3 = Color3.fromRGB(220, 220, 220)
			TweenService:Create(overlay, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 0) }):Play()
			task.spawn(function()
				local endTime = os.clock() + seconds
				while token == myToken and os.clock() < endTime do
					ready.Text = ("%.1fs"):format(endTime - os.clock())
					task.wait(0.1)
				end
				if token == myToken then
					ready.Text = "READY"
					ready.TextColor3 = Color3.fromRGB(140, 255, 140)
				end
			end)
		end,
	}
end

function CombatHudController.create(playerGui: Instance): HudApi
	local existing = playerGui:FindFirstChild("OttiArenaHud")
	if existing then
		existing:Destroy()
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "OttiArenaHud"
	gui.ResetOnSpawn = false

	-- Hit flash: a red (blocked: blue) glow on the screen EDGES only, never covering the view
	local hitEdges: { Frame } = {}
	for _, edge in {
		{ size = UDim2.new(1, 0, 0.14, 0), position = UDim2.fromScale(0, 0), rotation = 90 },
		{ size = UDim2.new(1, 0, 0.14, 0), position = UDim2.fromScale(0, 0.86), rotation = -90 },
		{ size = UDim2.new(0.1, 0, 1, 0), position = UDim2.fromScale(0, 0), rotation = 0 },
		{ size = UDim2.new(0.1, 0, 1, 0), position = UDim2.fromScale(0.9, 0), rotation = 180 },
	} do
		local frame = Instance.new("Frame")
		frame.Size = edge.size
		frame.Position = edge.position
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.Parent = gui
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = edge.rotation
		gradient.Transparency = NumberSequence.new(0, 1)
		gradient.Parent = frame
		table.insert(hitEdges, frame)
	end

	-- Top: AURA (always), then the header
	local aura = label(gui, "Aura", "AURA: 0", UDim2.fromOffset(240, 30), UDim2.new(0.5, -120, 0, 6), 22, Enum.Font.GothamBlack)
	aura.BackgroundColor3 = Color3.fromRGB(60, 36, 90)
	aura.BackgroundTransparency = 0.15
	aura.TextColor3 = Color3.fromRGB(255, 225, 120)
	corner(aura, 15)
	local auraStroke = Instance.new("UIStroke")
	auraStroke.Color = GOLD
	auraStroke.Thickness = 1.5
	auraStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	auraStroke.Parent = aura

	local header = Instance.new("Frame")
	header.AnchorPoint = Vector2.new(0.5, 0)
	header.Position = UDim2.new(0.5, 0, 0, 40)
	header.Size = UDim2.fromOffset(360, 54)
	header.BackgroundColor3 = PANEL
	header.BackgroundTransparency = 0.25
	header.Parent = gui
	corner(header)
	local title = label(header, "Title", "OTTI COLOSSEUM", UDim2.new(1, 0, 0, 28), UDim2.fromOffset(0, 2), 22, Enum.Font.GothamBold)
	title.TextColor3 = GOLD
	local subtitle = label(header, "Subtitle", "", UDim2.new(1, -10, 0, 20), UDim2.fromOffset(5, 30), 14)

	local target = Instance.new("Frame")
	target.AnchorPoint = Vector2.new(0.5, 0)
	target.Position = UDim2.new(0.5, 0, 0, 100)
	target.Size = UDim2.fromOffset(300, 38)
	target.BackgroundColor3 = PANEL
	target.BackgroundTransparency = 0.35
	target.Visible = false
	target.Parent = gui
	corner(target)
	local targetName = label(target, "Name", "", UDim2.new(1, -16, 0, 16), UDim2.fromOffset(8, 2), 13, Enum.Font.GothamBold)
	targetName.TextXAlignment = Enum.TextXAlignment.Left
	local targetValue = label(target, "Value", "", UDim2.new(1, -16, 0, 16), UDim2.fromOffset(8, 2), 13)
	targetValue.TextXAlignment = Enum.TextXAlignment.Right
	local targetFill = bar(target, UDim2.fromOffset(8, 21), UDim2.new(1, -16, 0, 10), Color3.fromRGB(220, 60, 50))

	-- Center: banner and combo popup
	local bannerTitle = label(gui, "BannerTitle", "", UDim2.fromOffset(760, 60), UDim2.new(0.5, -380, 0.26, 0), 44, Enum.Font.GothamBlack)
	bannerTitle.TextColor3 = GOLD
	bannerTitle.TextStrokeTransparency = 0.3
	bannerTitle.Visible = false
	local bannerSubtitle = label(gui, "BannerSubtitle", "", UDim2.fromOffset(760, 30), UDim2.new(0.5, -380, 0.26, 60), 24, Enum.Font.GothamBold)
	bannerSubtitle.TextStrokeTransparency = 0.3
	bannerSubtitle.Visible = false
	local bannerDetail = label(gui, "BannerDetail", "", UDim2.fromOffset(760, 26), UDim2.new(0.5, -380, 0.26, 92), 18)
	bannerDetail.TextStrokeTransparency = 0.3
	bannerDetail.Visible = false
	local comboLabel = label(gui, "Combo", "", UDim2.fromOffset(600, 40), UDim2.new(0.5, -300, 0.42, 0), 30, Enum.Font.GothamBlack)
	comboLabel.TextColor3 = Color3.fromRGB(255, 160, 60)
	comboLabel.TextStrokeTransparency = 0.2
	comboLabel.TextTransparency = 1

	-- Bottom left: player panel
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0, 16, 1, -16)
	panel.Size = UDim2.fromOffset(300, 128)
	panel.BackgroundColor3 = PANEL
	panel.BackgroundTransparency = 0.25
	panel.Parent = gui
	corner(panel)
	local function row(name: string, y: number, size: number, font: Enum.Font?): TextLabel
		local l = label(panel, name, "", UDim2.new(1, -20, 0, size + 4), UDim2.fromOffset(10, y), size, font)
		l.TextXAlignment = Enum.TextXAlignment.Left
		return l
	end
	local healthLabel = row("Health", 6, 16, Enum.Font.GothamBold)
	local healthFill = bar(panel, UDim2.fromOffset(10, 28), UDim2.new(1, -20, 0, 10), Color3.fromRGB(90, 200, 90))
	local weaponLabel = row("Weapon", 44, 13)
	local shieldLabel = row("Shield", 62, 13)
	local statusLabel = row("Status", 82, 14, Enum.Font.GothamBold)
	local controls = row("Controls", 104, 12)
	controls.TextColor3 = Color3.fromRGB(190, 190, 190)

	-- Bottom right: special-attack cards
	local special1 = specialCard(gui, "Special1", UDim2.new(1, -136, 1, -16))
	local special2 = specialCard(gui, "Special2", UDim2.new(1, -16, 1, -16))

	-- Popups (+AURA, +HEALTH, ...) above the player panel
	local popupHolder = Instance.new("Frame")
	popupHolder.AnchorPoint = Vector2.new(0, 1)
	popupHolder.Position = UDim2.new(0, 16, 1, -150)
	popupHolder.Size = UDim2.fromOffset(300, 120)
	popupHolder.BackgroundTransparency = 1
	popupHolder.Parent = gui
	local popupLayout = Instance.new("UIListLayout")
	popupLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	popupLayout.SortOrder = Enum.SortOrder.LayoutOrder
	popupLayout.Parent = popupHolder
	local popupOrder = 0

	-- Kill feed (top right)
	local feedHolder = Instance.new("Frame")
	feedHolder.AnchorPoint = Vector2.new(1, 0)
	feedHolder.Position = UDim2.new(1, -16, 0, 110)
	feedHolder.Size = UDim2.fromOffset(300, 120)
	feedHolder.BackgroundTransparency = 1
	feedHolder.Parent = gui
	local feedLayout = Instance.new("UIListLayout")
	feedLayout.SortOrder = Enum.SortOrder.LayoutOrder
	feedLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	feedLayout.Parent = feedHolder
	local feedOrder = 0

	local toastLabel = label(gui, "Toast", "", UDim2.fromOffset(560, 34), UDim2.new(0.5, -280, 1, -210), 18, Enum.Font.GothamBold)
	toastLabel.BackgroundColor3 = PANEL
	toastLabel.BackgroundTransparency = 0.2
	toastLabel.Visible = false
	corner(toastLabel)
	local toastToken = 0

	local blocking = label(gui, "Blocking", "BLOCKING", UDim2.fromOffset(160, 36), UDim2.new(0.5, -80, 1, -160), 20, Enum.Font.GothamBold)
	blocking.BackgroundColor3 = Color3.fromRGB(40, 90, 160)
	blocking.BackgroundTransparency = 0.15
	blocking.Visible = false
	corner(blocking)

	gui.Parent = playerGui
	local comboToken = 0

	return {
		gui = gui,
		special1 = special1,
		special2 = special2,
		setAura = function(amount: number)
			aura.Text = ("AURA: %d"):format(amount)
		end,
		setHeader = function(titleText: string, subtitleText: string)
			title.Text = titleText
			subtitle.Text = subtitleText
		end,
		setHealth = function(health: number, maxHealth: number)
			healthLabel.Text = ("HEALTH %d / %d"):format(math.ceil(health), maxHealth)
			healthFill.Size = UDim2.fromScale(math.clamp(health / math.max(maxHealth, 1), 0, 1), 1)
		end,
		setLoadout = function(weapon: string, shield: string)
			weaponLabel.Text = "WEAPON  " .. weapon
			shieldLabel.Text = "SHIELD  " .. shield
		end,
		setStatus = function(location: string, state: string, color: Color3)
			statusLabel.Text = ("%s · %s"):format(location:upper(), state)
			statusLabel.TextColor3 = color
		end,
		setControlsHint = function(text: string)
			controls.Text = text
		end,
		setTarget = function(name: string?, health: number, maxHealth: number)
			target.Visible = name ~= nil
			if name then
				targetName.Text = name
				targetValue.Text = ("%d / %d"):format(math.ceil(health), maxHealth)
				targetFill.Size = UDim2.fromScale(math.clamp(health / math.max(maxHealth, 1), 0, 1), 1)
			end
		end,
		setBanner = function(titleText: string?, subtitleText: string?, detailText: string?)
			bannerTitle.Visible = titleText ~= nil
			bannerTitle.Text = titleText or ""
			bannerSubtitle.Visible = subtitleText ~= nil
			bannerSubtitle.Text = subtitleText or ""
			bannerDetail.Visible = detailText ~= nil
			bannerDetail.Text = detailText or ""
		end,
		setBlocking = function(isBlocking: boolean)
			blocking.Visible = isBlocking
		end,
		setSpecialsVisible = function(visible: boolean)
			special1.button.Visible = visible
			special2.button.Visible = visible
		end,
		combo = function(name: string)
			comboToken += 1
			local myToken = comboToken
			comboLabel.Text = name .. "!"
			comboLabel.TextTransparency = 0
			comboLabel.TextStrokeTransparency = 0.2
			task.delay(0.9, function()
				if comboToken == myToken then
					TweenService:Create(comboLabel, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
				end
			end)
		end,
		popup = function(text: string, color: Color3)
			popupOrder += 1
			local l = label(popupHolder, "Popup", text, UDim2.new(1, 0, 0, 28), UDim2.new(), 22, Enum.Font.GothamBlack)
			l.LayoutOrder = popupOrder
			l.TextXAlignment = Enum.TextXAlignment.Left
			l.TextColor3 = color
			l.TextStrokeTransparency = 0.4
			local fade = TweenService:Create(l, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 })
			fade:Play()
			fade.Completed:Connect(function()
				l:Destroy()
			end)
		end,
		toast = function(text: string, ok: boolean)
			toastToken += 1
			local myToken = toastToken
			toastLabel.Text = text
			toastLabel.TextColor3 = if ok then Color3.fromRGB(140, 255, 140) else Color3.fromRGB(255, 150, 130)
			toastLabel.Visible = true
			task.delay(2.5, function()
				if toastToken == myToken then
					toastLabel.Visible = false
				end
			end)
		end,
		feed = function(text: string)
			feedOrder += 1
			local l = label(feedHolder, "Feed", text, UDim2.new(1, 0, 0, 22), UDim2.new(), 15, Enum.Font.GothamBold)
			l.LayoutOrder = feedOrder
			l.TextXAlignment = Enum.TextXAlignment.Right
			l.BackgroundColor3 = PANEL
			l.BackgroundTransparency = 0.35
			task.delay(5, function()
				l:Destroy()
			end)
		end,
		flashHit = function(blocked: boolean)
			for _, edge in hitEdges do
				edge.BackgroundColor3 = if blocked then Color3.fromRGB(150, 200, 255) else Color3.fromRGB(255, 40, 30)
				edge.BackgroundTransparency = 0.35
				TweenService:Create(edge, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
			end
		end,
	}
end

return CombatHudController
