--!strict
-- Touch combat buttons (presentation only; InputController sends the actions). Right side, in an arc
-- around Roblox's own jump button, which IS the JUMP button (no second jump button):
--   ATTACK   the largest, left of JUMP (tap = attack, tap again = combo)
--   SPECIAL  above JUMP: hold to charge (the ring fills in three phases), release to fire
--   BLOCK    diagonal: tap = guard on / off (lit while on)
-- The left side stays free for Roblox's thumbstick; dragging on free screen space turns the camera.
-- Positions per device class come from UiConfig (phone / tablet); nothing overlaps the jump button,
-- the health bar or the thumbstick. They belong to the "Controls" group, which every HUD mode keeps.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
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
	setCharge: (seconds: number?) -> (), -- nil = not charging
}

local MobileControlsController = {}

local TIER_COLORS = { Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 160, 60), Color3.fromRGB(255, 80, 60) }

local function makeButton(parent: Instance, name: string, text: string, color: Color3, size: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Size = UDim2.fromOffset(size, size)
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
	local attack = makeButton(frame, "Attack", "ATTACK", Color3.fromRGB(170, 60, 40), UiConfig.TouchAttackSize)
	attack.TextSize = 13
	local block = makeButton(frame, "Block", "BLOCK", Color3.fromRGB(40, 90, 160), UiConfig.TouchButtonSize)
	local special = makeButton(frame, "Special", "SPECIAL", UiConfig.Panel, UiConfig.TouchButtonSize)
	local specialStroke = special:FindFirstChildOfClass("UIStroke") :: UIStroke
	specialStroke.Color = UiConfig.Gold
	specialStroke.Transparency = 0.2
	-- Charge fill inside the SPECIAL button (rises from the bottom, colour per tier)
	local fill = Instance.new("Frame")
	fill.Name = "ChargeFill"
	fill.AnchorPoint = Vector2.new(0.5, 1)
	fill.Position = UDim2.fromScale(0.5, 1)
	fill.Size = UDim2.fromScale(1, 0)
	fill.BackgroundColor3 = TIER_COLORS[1]
	fill.BackgroundTransparency = 0.35
	fill.BorderSizePixel = 0
	fill.ZIndex = special.ZIndex
	fill.Parent = special
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill
	visibility.register("Controls", frame, isTouch)

	onLayout(function(layout: Layout)
		local positions = if layout.device == "Phone" then UiConfig.TouchLayoutPhone else UiConfig.TouchLayoutTablet
		attack.Position = UDim2.new(1, -positions.Attack.X, 1, -positions.Attack.Y)
		block.Position = UDim2.new(1, -positions.Block.X, 1, -positions.Block.Y)
		special.Position = UDim2.new(1, -positions.Special.X, 1, -positions.Special.Y)
	end)

	return {
		attackButton = attack,
		blockButton = block,
		specialButton = special,
		frame = frame,
		setBlocking = function(blocking: boolean)
			block.BackgroundTransparency = if blocking then 0 else 0.25
			block.Text = if blocking then "BLOCK\nON" else "BLOCK"
			local stroke = block:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = if blocking then UiConfig.Gold else Color3.new(1, 1, 1)
				stroke.Transparency = if blocking then 0 else 0.6
			end
		end,
		setCharge = function(seconds: number?)
			if not seconds then
				fill.Size = UDim2.fromScale(1, 0)
				return
			end
			local tier = SpecialChargeDefinitions.tierFor(seconds).Tier
			fill.Size = UDim2.fromScale(1, math.clamp(seconds / SpecialChargeDefinitions.MaxChargeSeconds, 0, 1))
			fill.BackgroundColor3 = TIER_COLORS[tier] or TIER_COLORS[1]
		end,
	}
end

return MobileControlsController
