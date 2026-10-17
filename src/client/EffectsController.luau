--!strict
-- Local visual feedback: small floating damage numbers ("15", "BLOCKED") above zombies.

local TweenService = game:GetService("TweenService")

local EffectsController = {}

local MAX_NUMBERS = 12
local active = 0

function EffectsController.damageNumber(model: Instance, damage: number, blocked: boolean)
	if active >= MAX_NUMBERS then
		return
	end
	local adornee = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart")
	if not adornee or not adornee:IsA("BasePart") then
		return
	end
	active += 1
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(90, 34)
	gui.StudsOffset = Vector3.new(math.random(-10, 10) / 10, 2.5, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = adornee
	gui.Parent = adornee

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = if blocked then 18 else 24
	label.Text = if blocked then "BLOCKED" else tostring(math.round(damage))
	label.TextColor3 = if blocked then Color3.fromRGB(255, 220, 120) else Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.Parent = gui

	TweenService:Create(gui, TweenInfo.new(0.7), { StudsOffset = gui.StudsOffset + Vector3.new(0, 2, 0) }):Play()
	local fade = TweenService:Create(label, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 })
	fade:Play()
	fade.Completed:Connect(function()
		gui:Destroy()
		active -= 1
	end)
end

return EffectsController
