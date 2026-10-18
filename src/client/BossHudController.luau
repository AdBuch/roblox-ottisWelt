--!strict
-- Slim Otti boss bar at the top centre (about 60 % of the width on phones, 45 % on desktop):
-- "OTTI", the phase in compact form (P1..P3, accent color per phase) and a thin health bar.
-- Short attack warnings (JUMP!, DODGE!, TAIL SLAM!, GRAPPLE!) appear right below it and are
-- never hidden by the HUD mode. A small SKIP button appears during the intro once you have seen
-- it this session (camera only: the server entrance always plays). "CHAMPION OF THE COLOSSEUM"
-- only shows in the intro banner (Main.client).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BossPhaseDefinitions = require(Shared:WaitForChild("BossPhaseDefinitions"))
local Config = require(Shared:WaitForChild("Config"))
local GameStates = require(Shared:WaitForChild("GameStates"))
local OttiBossConfig = require(Shared:WaitForChild("OttiBossConfig"))
local UiConfig = require(Shared:WaitForChild("UiConfig"))

type Visibility = {
	register: (group: string, element: GuiObject, wanted: (() -> boolean)?, forced: (() -> boolean)?) -> (),
}
type Layout = { device: string, viewport: Vector2, scale: number }

local BossHudController = {}

type Entrance = { skip: () -> (), canSkip: () -> boolean }

function BossHudController.start(group: (string, Vector2, UDim2, UDim2?) -> Frame, visibility: Visibility, onLayout: ((Layout) -> ()) -> (), arena: Instance, entrance: Entrance?)
	local player = Players.LocalPlayer
	local frame = group("BossBar", Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 6), UDim2.fromOffset(480, 30))
	local name = Instance.new("TextLabel")
	name.Size = UDim2.new(0, 60, 0, 14)
	name.BackgroundTransparency = 1
	name.Font = Enum.Font.GothamBlack
	name.TextSize = 14
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextColor3 = UiConfig.Gold
	name.TextStrokeTransparency = 0.4
	name.Text = OttiBossConfig.DisplayName
	name.Parent = frame
	local phaseLabel = Instance.new("TextLabel")
	phaseLabel.AnchorPoint = Vector2.new(1, 0)
	phaseLabel.Position = UDim2.fromScale(1, 0)
	phaseLabel.Size = UDim2.new(0, 60, 0, 14)
	phaseLabel.BackgroundTransparency = 1
	phaseLabel.Font = Enum.Font.GothamBlack
	phaseLabel.TextSize = 13
	phaseLabel.TextXAlignment = Enum.TextXAlignment.Right
	phaseLabel.TextStrokeTransparency = 0.4
	phaseLabel.Parent = frame
	local back = Instance.new("Frame")
	back.Position = UDim2.fromOffset(0, 16)
	back.Size = UDim2.new(1, 0, 0, 10)
	back.BackgroundColor3 = Color3.fromRGB(35, 22, 18)
	back.BackgroundTransparency = 0.2
	back.BorderSizePixel = 0
	back.Parent = frame
	local backCorner = Instance.new("UICorner")
	backCorner.CornerRadius = UDim.new(1, 0)
	backCorner.Parent = back
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Parent = back
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BorderSizePixel = 0
	fill.Parent = back
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	local warning = Instance.new("TextLabel")
	warning.Name = "Warning"
	warning.Position = UDim2.fromOffset(0, 30)
	warning.Size = UDim2.new(1, 0, 0, 30)
	warning.BackgroundTransparency = 1
	warning.Font = Enum.Font.GothamBlack
	warning.TextSize = 26
	warning.TextColor3 = Color3.fromRGB(255, 120, 60)
	warning.TextStrokeColor3 = Color3.fromRGB(40, 10, 0)
	warning.TextStrokeTransparency = 0.1
	warning.Text = ""
	warning.Parent = frame
	local warningScale = Instance.new("UIScale")
	warningScale.Parent = warning

	local skipFrame = group("SkipIntro", Vector2.new(1, 0), UDim2.new(1, -60, 0, 40), UDim2.fromOffset(88, 44))
	local skip = Instance.new("TextButton")
	skip.Size = UDim2.fromScale(1, 1)
	skip.BackgroundColor3 = UiConfig.Panel
	skip.BackgroundTransparency = 0.25
	skip.Font = Enum.Font.GothamBold
	skip.TextSize = 15
	skip.TextColor3 = UiConfig.Gold
	skip.Text = "SKIP ▶"
	skip.Parent = skipFrame
	local skipCorner = Instance.new("UICorner")
	skipCorner.CornerRadius = UDim.new(0, 8)
	skipCorner.Parent = skip
	skip.Activated:Connect(function()
		if entrance then
			entrance.skip()
		end
	end)

	local function watching(): boolean
		local location = player:GetAttribute(GameStates.LocationAttribute)
		return location == "Arena" or location == "Tribune"
	end

	local lastPhase = 0
	local function refresh()
		local maxHealth = tonumber(arena:GetAttribute(Config.BossMaxHealthAttribute)) or 0
		local health = tonumber(arena:GetAttribute(Config.BossHealthAttribute)) or 0
		local phase = math.clamp(tonumber(arena:GetAttribute(Config.BossPhaseAttribute)) or 1, 1, #BossPhaseDefinitions.Phases)
		local def = BossPhaseDefinitions.Phases[phase]
		TweenService:Create(fill, TweenInfo.new(0.2), { Size = UDim2.fromScale(math.clamp(health / math.max(1, maxHealth), 0, 1), 1) }):Play()
		phaseLabel.Text = if arena:GetAttribute(Config.BossDefeatedAttribute) then "DEFEATED" else ("P%d"):format(phase)
		phaseLabel.TextColor3 = def.Accent
		if phase ~= lastPhase then
			lastPhase = phase
			TweenService:Create(fill, TweenInfo.new(0.4), { BackgroundColor3 = def.Accent }):Play()
			stroke.Color = def.Accent
		end
	end
	for _, attribute in { Config.BossHealthAttribute, Config.BossMaxHealthAttribute, Config.BossPhaseAttribute, Config.BossDefeatedAttribute } do
		arena:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	refresh()

	local function refreshWarning()
		local text = tostring(arena:GetAttribute(Config.BossWarningAttribute) or "")
		warning.Text = text
		if text ~= "" then
			warningScale.Scale = 1.3
			TweenService:Create(warningScale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
	end
	arena:GetAttributeChangedSignal(Config.BossWarningAttribute):Connect(refreshWarning)
	arena:GetAttributeChangedSignal(Config.BossWarningIdAttribute):Connect(refreshWarning)

	onLayout(function(layout: Layout)
		local share = if layout.device == "Phone" then 0.6 elseif layout.device == "Tablet" then 0.5 else 0.45
		frame.Size = UDim2.fromOffset(layout.viewport.X * share / layout.scale, 30)
	end)

	visibility.register("Boss", frame, function()
		return arena:GetAttribute(Config.BossActiveAttribute) == true and (tonumber(arena:GetAttribute(Config.BossMaxHealthAttribute)) or 0) > 0 and watching()
	end, function()
		-- Short unavoidable-danger warnings are never hidden
		return warning.Text ~= "" and watching()
	end)
	visibility.register("Boss", skipFrame, function()
		return false
	end, function()
		return entrance ~= nil and entrance.canSkip()
	end)
end

return BossHudController
