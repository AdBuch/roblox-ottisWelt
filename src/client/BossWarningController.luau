--!strict
-- Big, readable warnings for Otti's major attacks ("TAIL SWEEP — JUMP!", "GRAPPLE — DODGE!",
-- "TAIL SLAM — MOVE!") and phase changes. Normal sword strikes are not announced, so the fight
-- stays a fight; their telegraphs are the visible wind-ups.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local BossWarningController = {}

function BossWarningController.start(gui: ScreenGui, arena: Instance)
	local player = Players.LocalPlayer
	local label = Instance.new("TextLabel")
	label.Name = "BossWarning"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.38)
	label.Size = UDim2.fromOffset(700, 54)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 40
	label.TextColor3 = Color3.fromRGB(255, 120, 60)
	label.TextStrokeColor3 = Color3.fromRGB(40, 10, 0)
	label.TextStrokeTransparency = 0.1
	label.Text = ""
	label.Visible = false
	label.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = label

	local function refresh()
		local text = tostring(arena:GetAttribute(Config.BossWarningAttribute) or "")
		local location = player:GetAttribute("Location")
		local show = text ~= "" and (location == "Arena" or location == "Tribune")
		label.Visible = show
		if show then
			label.Text = text
			scale.Scale = 1.25
			TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
	end
	arena:GetAttributeChangedSignal(Config.BossWarningAttribute):Connect(refresh)
	arena:GetAttributeChangedSignal(Config.BossWarningIdAttribute):Connect(refresh)
	refresh()
end

return BossWarningController
