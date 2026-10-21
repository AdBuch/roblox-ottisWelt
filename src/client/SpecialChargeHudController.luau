--!strict
-- The special CHARGE display (display only; the server measures the real hold time):
-- a compact bar above the bottom centre with three clearly separated phases I · II · III
-- (SpecialChargeDefinitions), filling while SPECIAL is held and showing MAX at full strength.
-- It also fills the touch SPECIAL button (MobileControlsController.setCharge). It belongs to the
-- "Momentum" HUD group (shown in every fight and in training).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SpecialChargeDefinitions = require(Shared:WaitForChild("SpecialChargeDefinitions"))
local UiConfig = require(Shared:WaitForChild("UiConfig"))

type Visibility = {
	register: (group: string, element: GuiObject, wanted: (() -> boolean)?, forced: (() -> boolean)?) -> (),
}

export type ChargeHud = {
	start: () -> (),
	stop: () -> (),
}

local SpecialChargeHudController = {}

local COLORS = { Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 160, 60), Color3.fromRGB(255, 80, 60) }
local DIM = Color3.fromRGB(60, 50, 40)

function SpecialChargeHudController.start(group: (string, Vector2, UDim2, UDim2?) -> Frame, visibility: Visibility, onCharge: (seconds: number?) -> ()): ChargeHud
	local frame = group("SpecialCharge", Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -64), UDim2.fromOffset(240, 34))
	frame.Visible = false
	local tiers = SpecialChargeDefinitions.Tiers
	local max = SpecialChargeDefinitions.MaxChargeSeconds
	local segments: { Frame } = {}
	local fills: { Frame } = {}
	for i, def in tiers do
		local nextFrom = if tiers[i + 1] then tiers[i + 1].From else max
		local segment = Instance.new("Frame")
		segment.Position = UDim2.new(def.From / max, 2, 0, 0)
		segment.Size = UDim2.new((nextFrom - def.From) / max, -4, 0, 12)
		segment.BackgroundColor3 = DIM
		segment.BackgroundTransparency = 0.25
		segment.BorderSizePixel = 0
		segment.Parent = frame
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 4)
		corner.Parent = segment
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(0, 1)
		fill.BackgroundColor3 = COLORS[i]
		fill.BorderSizePixel = 0
		fill.Parent = segment
		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(0, 4)
		fillCorner.Parent = fill
		local label = Instance.new("TextLabel")
		label.Position = UDim2.new(0, 0, 1, 2)
		label.Size = UDim2.new(1, 0, 0, 14)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.TextSize = 11
		label.TextColor3 = UiConfig.Gold
		label.Text = def.Name
		label.Parent = segment
		table.insert(segments, segment)
		table.insert(fills, fill)
	end
	local maxLabel = Instance.new("TextLabel")
	maxLabel.AnchorPoint = Vector2.new(0, 0)
	maxLabel.Position = UDim2.new(1, 6, 0, -2)
	maxLabel.Size = UDim2.fromOffset(40, 16)
	maxLabel.BackgroundTransparency = 1
	maxLabel.Font = Enum.Font.GothamBlack
	maxLabel.TextSize = 12
	maxLabel.TextColor3 = COLORS[3]
	maxLabel.TextXAlignment = Enum.TextXAlignment.Left
	maxLabel.Text = "MAX"
	maxLabel.Visible = false
	maxLabel.Parent = frame
	local active = false
	visibility.register("Momentum", frame, function()
		return active
	end)

	local started = 0
	local connection: RBXScriptConnection? = nil
	local function render(seconds: number)
		for i, def in tiers do
			local nextFrom = if tiers[i + 1] then tiers[i + 1].From else max
			local share = math.clamp((seconds - def.From) / (nextFrom - def.From), 0, 1)
			fills[i].Size = UDim2.fromScale(share, 1)
			segments[i].BackgroundTransparency = if seconds >= def.From then 0.05 else 0.25
		end
		maxLabel.Visible = seconds >= max
		onCharge(seconds)
	end

	local api = {} :: ChargeHud
	function api.start()
		active = true
		started = os.clock()
		frame.Visible = true
		render(0)
		if connection then
			connection:Disconnect()
		end
		connection = RunService.RenderStepped:Connect(function()
			render(math.min(os.clock() - started, max))
		end)
	end
	function api.stop()
		active = false
		if connection then
			connection:Disconnect()
			connection = nil
		end
		frame.Visible = false
		onCharge(nil)
	end
	return api
end

return SpecialChargeHudController
