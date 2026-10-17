--!strict
-- Builds the on-screen HUD from code and exposes small setters to update it.

local Hud = {}

export type HudApi = {
	setShells: (count: number, total: number) -> (),
	setDummyHealth: (health: number, maxHealth: number, alive: boolean) -> (),
	setAttacksSent: (count: number) -> (),
	setComplete: (complete: boolean) -> (),
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

function Hud.create(playerGui: Instance): HudApi
	local existing = playerGui:FindFirstChild("OttiArenaHud")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "OttiArenaHud"
	gui.ResetOnSpawn = false

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0, 1)
	panel.Position = UDim2.new(0, 16, 1, -16)
	panel.Size = UDim2.fromOffset(320, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Color3.fromRGB(30, 24, 18)
	panel.BackgroundTransparency = 0.25
	panel.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = panel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = panel

	local title = makeLabel(panel, "Title", "Otti Arena – Setup Check", 1, 18)
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = Color3.fromRGB(255, 205, 70)
	makeLabel(panel, "Instruction", "Collect 3 shells and defeat the training zombie.", 2, 14)
	local shellsLabel = makeLabel(panel, "Shells", "Shells: 0 / 3", 3, 16)
	local dummyLabel = makeLabel(panel, "DummyHealth", "Zombie HP: waiting for server…", 4, 16)
	local attacksLabel = makeLabel(panel, "Attacks", "Left-click near the zombie to attack (sent: 0)", 5, 13)
	attacksLabel.TextColor3 = Color3.fromRGB(200, 200, 200)

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
	banner.Text = "Setup successful — Rojo, client and server are working!"
	banner.Visible = false
	banner.Parent = gui
	local bannerCorner = Instance.new("UICorner")
	bannerCorner.CornerRadius = UDim.new(0, 8)
	bannerCorner.Parent = banner

	gui.Parent = playerGui

	return {
		setShells = function(count: number, total: number)
			shellsLabel.Text = ("Shells: %d / %d"):format(count, total)
		end,
		setDummyHealth = function(health: number, maxHealth: number, alive: boolean)
			if alive then
				dummyLabel.Text = ("Zombie HP: %d / %d"):format(health, maxHealth)
			else
				dummyLabel.Text = "Zombie HP: defeated – respawning…"
			end
		end,
		setAttacksSent = function(count: number)
			attacksLabel.Text = ("Left-click near the zombie to attack (sent: %d)"):format(count)
		end,
		setComplete = function(complete: boolean)
			banner.Visible = complete
		end,
	}
end

return Hud
