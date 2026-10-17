--!strict
-- Builds the on-screen HUD from code and exposes small setters to update it.

local TweenService = game:GetService("TweenService")

local Hud = {}

export type HudApi = {
	setPlayerHealth: (health: number, maxHealth: number) -> (),
	setZombieHealth: (health: number, maxHealth: number, alive: boolean) -> (),
	setShells: (count: number, total: number) -> (),
	setState: (state: string) -> (),
	setBlocking: (blocking: boolean) -> (),
	setComplete: (complete: boolean) -> (),
	flashHit: (blocked: boolean) -> (),
}

local STATE_COLORS: { [string]: Color3 } = {
	READY = Color3.fromRGB(220, 220, 220),
	ATTACKING = Color3.fromRGB(255, 205, 70),
	BLOCKING = Color3.fromRGB(120, 190, 255),
	HIT = Color3.fromRGB(255, 90, 80),
	VICTORY = Color3.fromRGB(110, 230, 120),
}

local function makeLabel(parent: Instance, name: string, text: string, order: number, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Text = text
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, textSize + 6)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextSize = textSize
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.Parent = parent
	return label
end

local function addCorner(parent: Instance)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = parent
end

function Hud.create(playerGui: Instance): HudApi
	local existing = playerGui:FindFirstChild("OttiArenaHud")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "OttiArenaHud"
	gui.ResetOnSpawn = false

	-- Red/white screen flash when the player gets hit
	local hitFlash = Instance.new("Frame")
	hitFlash.Name = "HitFlash"
	hitFlash.Size = UDim2.fromScale(1, 1)
	hitFlash.BackgroundColor3 = Color3.fromRGB(255, 40, 30)
	hitFlash.BackgroundTransparency = 1
	hitFlash.BorderSizePixel = 0
	hitFlash.Parent = gui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0, 16, 1, -16)
	panel.Size = UDim2.fromOffset(300, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Color3.fromRGB(30, 24, 18)
	panel.BackgroundTransparency = 0.25
	panel.Parent = gui
	addCorner(panel)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 3)
	layout.Parent = panel

	local title = makeLabel(panel, "Title", "Otti Arena – Combat", 1, 18)
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = Color3.fromRGB(255, 205, 70)
	makeLabel(panel, "Instruction", "Defeat the Roman zombie. Bonus: collect 3 golden shells.", 2, 13)
	local healthLabel = makeLabel(panel, "PlayerHealth", "Health: –", 3, 16)
	local zombieLabel = makeLabel(panel, "ZombieHealth", "Zombie HP: waiting for server…", 4, 16)
	local shellsLabel = makeLabel(panel, "Shells", "Shells: 0 / 3", 5, 14)
	local swordHint = makeLabel(panel, "SwordHint", "Sword: click to attack", 6, 13)
	swordHint.TextColor3 = Color3.fromRGB(200, 200, 200)
	local shieldHint = makeLabel(panel, "ShieldHint", "Shield: hold click to block", 7, 13)
	shieldHint.TextColor3 = Color3.fromRGB(200, 200, 200)
	local stateLabel = makeLabel(panel, "State", "State: READY", 8, 16)
	stateLabel.Font = Enum.Font.GothamBold

	local blocking = Instance.new("TextLabel")
	blocking.Name = "Blocking"
	blocking.AnchorPoint = Vector2.new(0.5, 1)
	blocking.Position = UDim2.new(0.5, 0, 1, -120)
	blocking.Size = UDim2.fromOffset(160, 36)
	blocking.BackgroundColor3 = Color3.fromRGB(40, 90, 160)
	blocking.BackgroundTransparency = 0.15
	blocking.Font = Enum.Font.GothamBold
	blocking.TextSize = 20
	blocking.TextColor3 = Color3.new(1, 1, 1)
	blocking.Text = "BLOCKING"
	blocking.Visible = false
	blocking.Parent = gui
	addCorner(blocking)

	local banner = Instance.new("TextLabel")
	banner.Name = "SuccessBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 16)
	banner.Size = UDim2.fromOffset(560, 52)
	banner.BackgroundColor3 = Color3.fromRGB(40, 140, 70)
	banner.Font = Enum.Font.GothamBold
	banner.TextSize = 20
	banner.TextWrapped = true
	banner.TextColor3 = Color3.new(1, 1, 1)
	banner.Text = "SETUP COMPLETE — Otti Arena combat works!"
	banner.Visible = false
	banner.Parent = gui
	addCorner(banner)

	gui.Parent = playerGui

	return {
		setPlayerHealth = function(health: number, maxHealth: number)
			healthLabel.Text = ("Health: %d / %d"):format(math.ceil(health), maxHealth)
		end,
		setZombieHealth = function(health: number, maxHealth: number, alive: boolean)
			if alive then
				zombieLabel.Text = ("Zombie HP: %d / %d"):format(health, maxHealth)
			else
				zombieLabel.Text = "Zombie HP: defeated – respawning…"
			end
		end,
		setShells = function(count: number, total: number)
			shellsLabel.Text = ("Shells: %d / %d"):format(count, total)
		end,
		setState = function(state: string)
			stateLabel.Text = "State: " .. state
			stateLabel.TextColor3 = STATE_COLORS[state] or Color3.new(1, 1, 1)
		end,
		setBlocking = function(isBlocking: boolean)
			blocking.Visible = isBlocking
		end,
		setComplete = function(complete: boolean)
			banner.Visible = complete
		end,
		flashHit = function(blocked: boolean)
			hitFlash.BackgroundColor3 = if blocked then Color3.fromRGB(150, 200, 255) else Color3.fromRGB(255, 40, 30)
			hitFlash.BackgroundTransparency = 0.6
			TweenService:Create(hitFlash, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
		end,
	}
end

return Hud
