--!strict
-- Equal-sized touch buttons: SPECIAL left, ATTACK right, BLOCK above; native JUMP below.
-- The SPECIAL ring displays server-owned Momentum continuously, including while not held.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MomentumConfig = require(Shared:WaitForChild("MomentumConfig"))
local SpecialChargeDefinitions = require(Shared:WaitForChild("SpecialChargeDefinitions"))
local UiConfig = require(Shared:WaitForChild("UiConfig"))

type Visibility = {
	register: (group: string, element: GuiObject, wanted: (() -> boolean)?, forced: (() -> boolean)?) -> (),
}
type Layout = { device: string, touch: boolean, portrait: boolean }
export type Controls = {
	attackButton: TextButton,
	blockButton: TextButton,
	specialButton: TextButton,
	frame: Frame,
	setBlocking: (blocking: boolean) -> (),
	setCharge: (seconds: number?) -> (),
}
local MobileControlsController = {}
local COLORS = { Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 160, 60), Color3.fromRGB(255, 100, 70) }
local DOT_COUNT = 40

local function makeButton(parent: Instance, name: string, text: string, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Size = UDim2.fromOffset(UiConfig.TouchButtonSize, UiConfig.TouchButtonSize)
	button.BackgroundColor3 = color
	button.BackgroundTransparency = 0.25
	button.AutoButtonColor = true
	button.Font = Enum.Font.GothamBlack
	button.TextSize = 12
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextStrokeTransparency = 0.5
	button.Text = text
	button.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0.6
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	return button
end

function MobileControlsController.start(group: (string, Vector2, UDim2, UDim2?) -> Frame, visibility: Visibility, onLayout: ((Layout) -> ()) -> (), isTouch: () -> boolean): Controls
	local frame = group("TouchControls", Vector2.new(1, 1), UDim2.fromScale(1, 1), UDim2.fromOffset(340, 440))
	local attack = makeButton(frame, "Attack", "ATTACK", Color3.fromRGB(170, 60, 40))
	local block = makeButton(frame, "Block", "BLOCK", Color3.fromRGB(40, 90, 160))
	local special = makeButton(frame, "Special", "", UiConfig.Panel)
	local stroke = special:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Color = UiConfig.Gold
	stroke.Transparency = 0.3
	-- Separate label above the ring; decorative descendants never consume touch input.
	local label = Instance.new("TextLabel")
	label.Name = "SpecialStatus"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.77, 0.65)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 10
	label.TextColor3 = Color3.new(1, 1, 1)
	label.ZIndex = special.ZIndex + 2
	label.Parent = special
	local dots: { Frame } = {}
	for i = 1, DOT_COUNT do
		local angle = (i - 1) / DOT_COUNT * math.pi * 2 - math.pi / 2
		local dot = Instance.new("Frame")
		dot.Name = "Momentum_" .. i
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(0.5 + math.cos(angle) * 0.44, 0.5 + math.sin(angle) * 0.44)
		dot.Size = UDim2.fromOffset(3, 3)
		dot.BorderSizePixel = 0
		dot.ZIndex = special.ZIndex + 1
		dot.Parent = special
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = dot
		table.insert(dots, dot)
	end
	visibility.register("Controls", frame, isTouch)
	onLayout(function(layout: Layout)
		local positions = if layout.device == "Phone" then UiConfig.TouchLayoutPhone else UiConfig.TouchLayoutTablet
		attack.Position = UDim2.new(1, -positions.Attack.X, 1, -positions.Attack.Y)
		block.Position = UDim2.new(1, -positions.Block.X, 1, -positions.Block.Y)
		special.Position = UDim2.new(1, -positions.Special.X, 1, -positions.Special.Y)
	end)

	local player = Players.LocalPlayer
	local held: number? = nil
	local function refresh()
		local value = math.clamp(tonumber(player:GetAttribute(Config.MomentumAttribute)) or 0, 0, MomentumConfig.Max)
		local available = SpecialChargeDefinitions.availableTier(value)
		local selected, ultimate = SpecialChargeDefinitions.forRelease(held or 0, value)
		local color = if available then COLORS[available.Tier] else Color3.fromRGB(95, 85, 70)
		for i, dot in dots do
			dot.BackgroundColor3 = if value >= i / DOT_COUNT * MomentumConfig.Max then color else Color3.fromRGB(65, 57, 46)
		end
		local tierName = if value >= SpecialChargeDefinitions.UltimateMomentum then "ULT" elseif available then available.Name else "..."
		if held ~= nil then
			tierName = if ultimate then "ULT" elseif selected then selected.Name else "..."
		end
		label.Text = ("SPECIAL\n%s · %d%%"):format(tierName, math.floor(value))
		stroke.Color = if held ~= nil then color else UiConfig.Gold
		stroke.Transparency = if held ~= nil then 0 else 0.3
		special.BackgroundTransparency = if available then 0.15 else 0.45
	end
	player:GetAttributeChangedSignal(Config.MomentumAttribute):Connect(refresh)
	refresh()
	return {
		attackButton = attack,
		blockButton = block,
		specialButton = special,
		frame = frame,
		setBlocking = function(blocking: boolean)
			block.BackgroundTransparency = if blocking then 0 else 0.25
			block.Text = if blocking then "BLOCK\nON" else "BLOCK"
			local blockStroke = block:FindFirstChildOfClass("UIStroke")
			if blockStroke then
				blockStroke.Color = if blocking then UiConfig.Gold else Color3.new(1, 1, 1)
				blockStroke.Transparency = if blocking then 0 else 0.6
			end
		end,
		setCharge = function(seconds: number?)
			held = seconds
			refresh()
		end,
	}
end
return MobileControlsController
