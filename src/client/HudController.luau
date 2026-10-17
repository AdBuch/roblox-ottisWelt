--!strict
-- Builds the compact HUD from code and exposes small setters to update it.

local TweenService = game:GetService("TweenService")

local HudController = {}

export type HudApi = {
	setHeader: (title: string, subtitle: string) -> (),
	setHealth: (health: number, maxHealth: number) -> (),
	setCoins: (coins: number) -> (),
	setLoadout: (weapon: string, shield: string) -> (),
	setStatus: (location: string, state: string, color: Color3) -> (),
	setControlsHint: (text: string) -> (),
	setTarget: (name: string?, health: number, maxHealth: number) -> (),
	setBanner: (title: string?, subtitle: string?, detail: string?) -> (),
	setBlocking: (blocking: boolean) -> (),
	popup: (text: string, color: Color3) -> (),
	toast: (text: string, ok: boolean) -> (),
	flashHit: (blocked: boolean) -> (),
}

local PANEL_COLOR = Color3.fromRGB(30, 24, 18)
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

local function bar(parent: Instance, name: string, position: UDim2, size: UDim2, color: Color3): Frame
	local back = Instance.new("Frame")
	back.Name = name
	back.Position = position
	back.Size = size
	back.BackgroundColor3 = Color3.fromRGB(45, 25, 20)
	back.BorderSizePixel = 0
	back.Parent = parent
	corner(back, 4)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = back
	corner(fill, 4)
	return fill
end

function HudController.create(playerGui: Instance): HudApi
	local existing = playerGui:FindFirstChild("OttiArenaHud")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "OttiArenaHud"
	gui.ResetOnSpawn = false

	local hitFlash = Instance.new("Frame")
	hitFlash.Name = "HitFlash"
	hitFlash.Size = UDim2.fromScale(1, 1)
	hitFlash.BackgroundTransparency = 1
	hitFlash.BorderSizePixel = 0
	hitFlash.Parent = gui

	-- Top center header: lobby title / round / tribune
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.AnchorPoint = Vector2.new(0.5, 0)
	header.Position = UDim2.new(0.5, 0, 0, 8)
	header.Size = UDim2.fromOffset(330, 54)
	header.BackgroundColor3 = PANEL_COLOR
	header.BackgroundTransparency = 0.25
	header.Parent = gui
	corner(header)
	local title = label(header, "Title", "OTTI COLOSSEUM", UDim2.new(1, 0, 0, 28), UDim2.fromOffset(0, 2), 22, Enum.Font.GothamBold)
	title.TextColor3 = GOLD
	local subtitle = label(header, "Subtitle", "", UDim2.new(1, -10, 0, 20), UDim2.fromOffset(5, 30), 14)

	-- Target bar under the header
	local target = Instance.new("Frame")
	target.Name = "Target"
	target.AnchorPoint = Vector2.new(0.5, 0)
	target.Position = UDim2.new(0.5, 0, 0, 68)
	target.Size = UDim2.fromOffset(300, 38)
	target.BackgroundColor3 = PANEL_COLOR
	target.BackgroundTransparency = 0.35
	target.Visible = false
	target.Parent = gui
	corner(target)
	local targetName = label(target, "Name", "", UDim2.new(1, -16, 0, 16), UDim2.fromOffset(8, 2), 13, Enum.Font.GothamBold)
	targetName.TextXAlignment = Enum.TextXAlignment.Left
	local targetValue = label(target, "Value", "", UDim2.new(1, -16, 0, 16), UDim2.fromOffset(8, 2), 13)
	targetValue.TextXAlignment = Enum.TextXAlignment.Right
	local targetFill = bar(target, "Bar", UDim2.fromOffset(8, 21), UDim2.new(1, -16, 0, 10), Color3.fromRGB(220, 60, 50))

	-- Center banner
	local bannerTitle = label(gui, "BannerTitle", "", UDim2.fromOffset(700, 60), UDim2.new(0.5, -350, 0.26, 0), 44, Enum.Font.GothamBlack)
	bannerTitle.TextColor3 = GOLD
	bannerTitle.TextStrokeTransparency = 0.3
	bannerTitle.Visible = false
	local bannerSubtitle = label(gui, "BannerSubtitle", "", UDim2.fromOffset(700, 30), UDim2.new(0.5, -350, 0.26, 60), 24, Enum.Font.GothamBold)
	bannerSubtitle.TextStrokeTransparency = 0.3
	bannerSubtitle.Visible = false
	local bannerDetail = label(gui, "BannerDetail", "", UDim2.fromOffset(700, 26), UDim2.new(0.5, -350, 0.26, 92), 18, Enum.Font.GothamMedium)
	bannerDetail.TextStrokeTransparency = 0.3
	bannerDetail.Visible = false

	-- Bottom left: health, coins, loadout, state, controls
	local panel = Instance.new("Frame")
	panel.Name = "Player"
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0, 16, 1, -16)
	panel.Size = UDim2.fromOffset(280, 142)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BackgroundTransparency = 0.25
	panel.Parent = gui
	corner(panel)
	local function row(name: string, y: number, size: number, font: Enum.Font?): TextLabel
		local l = label(panel, name, "", UDim2.new(1, -20, 0, size + 4), UDim2.fromOffset(10, y), size, font)
		l.TextXAlignment = Enum.TextXAlignment.Left
		return l
	end
	local healthLabel = row("Health", 6, 16, Enum.Font.GothamBold)
	local healthFill = bar(panel, "HealthBar", UDim2.fromOffset(10, 28), UDim2.new(1, -20, 0, 10), Color3.fromRGB(90, 200, 90))
	local coinsLabel = row("Coins", 42, 16, Enum.Font.GothamBold)
	coinsLabel.TextColor3 = GOLD
	local weaponLabel = row("Weapon", 64, 13)
	local shieldLabel = row("Shield", 82, 13)
	local statusLabel = row("Status", 100, 14, Enum.Font.GothamBold)
	local controls = row("Controls", 120, 12)
	controls.TextColor3 = Color3.fromRGB(190, 190, 190)

	-- Popups (+10 COINS, +3 HEALTH, SLOWED) above the panel, and shop toasts
	local popupHolder = Instance.new("Frame")
	popupHolder.Name = "Popups"
	popupHolder.AnchorPoint = Vector2.new(0, 1)
	popupHolder.Position = UDim2.new(0, 16, 1, -166)
	popupHolder.Size = UDim2.fromOffset(280, 120)
	popupHolder.BackgroundTransparency = 1
	popupHolder.Parent = gui
	local popupLayout = Instance.new("UIListLayout")
	popupLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	popupLayout.SortOrder = Enum.SortOrder.LayoutOrder
	popupLayout.Parent = popupHolder
	local popupOrder = 0

	local toastLabel = label(gui, "Toast", "", UDim2.fromOffset(520, 34), UDim2.new(0.5, -260, 1, -210), 18, Enum.Font.GothamBold)
	toastLabel.BackgroundColor3 = PANEL_COLOR
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

	return {
		setHeader = function(titleText: string, subtitleText: string)
			title.Text = titleText
			subtitle.Text = subtitleText
		end,
		setHealth = function(health: number, maxHealth: number)
			healthLabel.Text = ("HEALTH %d / %d"):format(math.ceil(health), maxHealth)
			healthFill.Size = UDim2.fromScale(math.clamp(health / math.max(maxHealth, 1), 0, 1), 1)
		end,
		setCoins = function(coins: number)
			coinsLabel.Text = ("COINS %d"):format(coins)
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
		flashHit = function(blocked: boolean)
			hitFlash.BackgroundColor3 = if blocked then Color3.fromRGB(150, 200, 255) else Color3.fromRGB(255, 40, 30)
			hitFlash.BackgroundTransparency = 0.6
			TweenService:Create(hitFlash, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		end,
	}
end

return HudController
