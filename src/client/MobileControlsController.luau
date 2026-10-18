--!strict
-- Touch combat buttons (presentation only; InputController sends the actions): ATK, BLOCK and a
-- small COMBO (Execute) button in an arc around Roblox's own jump button, which stays the Jump
-- input (no second jump button). 50-56 px targets, short labels, never on the thumbstick side or
-- the health bar. They belong to the "Controls" group, which every HUD mode keeps.
-- Nothing here shows charging or loading: moves start when the input arrives.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UiConfig"))

type Visibility = {
	register: (group: string, element: GuiObject, wanted: (() -> boolean)?, forced: (() -> boolean)?) -> (),
}
type Layout = { device: string, touch: boolean, portrait: boolean }

export type Controls = {
	attackButton: TextButton,
	blockButton: TextButton,
	comboButton: TextButton,
	frame: Frame,
	setBlocking: (blocking: boolean) -> (),
}

local MobileControlsController = {}

local function makeButton(parent: Instance, name: string, text: string, color: Color3, size: number): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Size = UDim2.fromOffset(size, size)
	button.BackgroundColor3 = color
	button.BackgroundTransparency = 0.25
	button.AutoButtonColor = true
	button.Font = Enum.Font.GothamBlack
	button.TextSize = 13
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
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	return button
end

function MobileControlsController.start(group: (string, Vector2, UDim2, UDim2?) -> Frame, visibility: Visibility, onLayout: ((Layout) -> ()) -> (), isTouch: () -> boolean): Controls
	local frame = group("TouchControls", Vector2.new(1, 1), UDim2.fromScale(1, 1), UDim2.fromOffset(320, 420))
	local attack = makeButton(frame, "Attack", "ATK", Color3.fromRGB(170, 60, 40), UiConfig.TouchButtonSize)
	local block = makeButton(frame, "Block", "BLOCK", Color3.fromRGB(40, 90, 160), UiConfig.TouchButtonSize)
	local combo = makeButton(frame, "Combo", "COMBO", UiConfig.Panel, UiConfig.TouchSpecialSize)
	combo.TextSize = 11
	local comboStroke = combo:FindFirstChildOfClass("UIStroke")
	if comboStroke then
		comboStroke.Color = UiConfig.Gold
		comboStroke.Transparency = 0.2
	end
	visibility.register("Controls", frame, isTouch)

	onLayout(function(layout: Layout)
		local positions = if layout.device == "Phone" then UiConfig.TouchLayoutPhone else UiConfig.TouchLayoutTablet
		attack.Position = UDim2.new(1, -positions.Attack.X, 1, -positions.Attack.Y)
		block.Position = UDim2.new(1, -positions.Block.X, 1, -positions.Block.Y)
		combo.Position = UDim2.new(1, -positions.Combo.X, 1, -positions.Combo.Y)
	end)

	return {
		attackButton = attack,
		blockButton = block,
		comboButton = combo,
		frame = frame,
		setBlocking = function(blocking: boolean)
			block.BackgroundTransparency = if blocking then 0 else 0.25
			local stroke = block:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Transparency = if blocking then 0 else 0.6
			end
		end,
	}
end

return MobileControlsController
