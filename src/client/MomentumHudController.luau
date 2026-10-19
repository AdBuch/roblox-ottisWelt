--!strict
-- The ARENA MOMENTUM bar: a narrow gold bar under the round line (group "Momentum"). It shows the
-- server-owned "Momentum" player attribute (0-100) and marks the Special tiers at 25 / 50 / 75 (the
-- Ultimate costs 100). Display only: the server spends and gains Momentum (MomentumService).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MomentumConfig = require(Shared:WaitForChild("MomentumConfig"))
local UiConfig = require(Shared:WaitForChild("UiConfig"))
local WeaponSpecialDefinitions = require(Shared:WaitForChild("WeaponSpecialDefinitions"))

type Visibility = {
	register: (group: string, element: GuiObject, wanted: (() -> boolean)?, forced: (() -> boolean)?) -> (),
}
type Layout = { device: string, touch: boolean, portrait: boolean }

export type MomentumHud = {
	refresh: () -> (),
}

local MomentumHudController = {}

local GOLD = UiConfig.Gold
local DIM = Color3.fromRGB(70, 56, 40)

function MomentumHudController.start(group: (string, Vector2, UDim2, UDim2?) -> Frame, visibility: Visibility, onLayout: ((Layout) -> ()) -> (), player: Player): MomentumHud
	local frame = group("Momentum", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 44), UDim2.fromOffset(200, 22))
	frame.BackgroundTransparency = 1

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0.5, 0.5)
	track.Position = UDim2.fromScale(0.5, 0.5)
	track.Size = UDim2.new(1, 0, 0, 6)
	track.BackgroundColor3 = DIM
	track.BackgroundTransparency = 0.3
	track.BorderSizePixel = 0
	track.Parent = frame
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = GOLD
	fill.BorderSizePixel = 0
	fill.Parent = track
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	-- Tier marks: the Special costs (25 / 50 / 75) and the Ultimate line (100 is the end)
	local tiers = { WeaponSpecialDefinitions.TierCost[1], WeaponSpecialDefinitions.TierCost[2], WeaponSpecialDefinitions.TierCost[3] }
	for _, cost in tiers do
		local mark = Instance.new("Frame")
		mark.AnchorPoint = Vector2.new(0.5, 0.5)
		mark.Position = UDim2.fromScale(cost / MomentumConfig.Max, 0.5)
		mark.Size = UDim2.fromOffset(2, 12)
		mark.BackgroundColor3 = Color3.new(1, 1, 1)
		mark.BackgroundTransparency = 0.45
		mark.BorderSizePixel = 0
		mark.Parent = track
	end

	local label = Instance.new("TextLabel")
	label.Name = "Value"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 1, 2)
	label.Size = UDim2.new(1, 0, 0, 12)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 10
	label.TextColor3 = GOLD
	label.Text = "MOMENTUM 0"
	label.Parent = frame

	visibility.register("Momentum", frame)
	onLayout(function(layout: Layout)
		frame.Size = UDim2.fromOffset(if layout.device == "Phone" then 150 else 200, 22)
	end)

	local function refresh()
		local value = math.clamp(tonumber(player:GetAttribute(Config.MomentumAttribute)) or 0, 0, MomentumConfig.Max)
		TweenService:Create(fill, TweenInfo.new(0.2), { Size = UDim2.fromScale(value / MomentumConfig.Max, 1) }):Play()
		label.Text = ("MOMENTUM %d"):format(math.floor(value + 0.5))
	end
	player:GetAttributeChangedSignal(Config.MomentumAttribute):Connect(refresh)
	refresh()

	return { refresh = refresh }
end

return MomentumHudController
