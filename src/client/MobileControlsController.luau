--!strict
-- Touch combat buttons (presentation only; InputController sends the actions): ATK, BLOCK, SLIDE and
-- SPECIAL in an arc around Roblox's own jump button, which stays the Jump input (no second jump
-- button). Classic shows ATK and BLOCK; Wild hides them because the gesture pad handles attacks and
-- blocks, while SLIDE and SPECIAL stay available in both modes. 50-56 px targets, short labels,
-- never on the thumbstick side or the health bar. Belongs to the "Controls" group, which every HUD
-- mode keeps. Nothing here shows charging or loading: moves start when the input arrives.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UiConfig"))

type Visibility = {
	register: (group: string, element: GuiObject, wanted: (() -> boolean)?, forced: (() -> boolean)?) -> (),
}
type Layout = { device: string, touch: boolean, portrait: boolean }

export type Controls = {
	attackButton: TextButton,
	blockButton: TextButton,
	slideButton: TextButton,
	specialButton: TextButton,
	frame: Frame,
	setBlocking: (blocking: boolean) -> (),
	setMode: (mode: string) -> (),
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

local function accent(button: TextButton, color: Color3)
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
		stroke.Transparency = 0.2
	end
end

function MobileControlsController.start(group: (string, Vector2, UDim2, UDim2?) -> Frame, visibility: Visibility, onLayout: ((Layout) -> ()) -> (), isTouch: () -> boolean): Controls
	local frame = group("TouchControls", Vector2.new(1, 1), UDim2.fromScale(1, 1), UDim2.fromOffset(320, 420))
	local attack = makeButton(frame, "Attack", "ATK", Color3.fromRGB(170, 60, 40), UiConfig.TouchButtonSize)
	local block = makeButton(frame, "Block", "BLOCK", Color3.fromRGB(40, 90, 160), UiConfig.TouchButtonSize)
	local slide = makeButton(frame, "Slide", "SLIDE", UiConfig.Panel, UiConfig.TouchSpecialSize)
	slide.TextSize = 11
	accent(slide, Color3.fromRGB(120, 200, 255))
	local special = makeButton(frame, "Special", "SPECIAL", UiConfig.Panel, UiConfig.TouchSpecialSize)
	special.TextSize = 11
	accent(special, UiConfig.Gold)
	visibility.register("Controls", frame, isTouch)

	onLayout(function(layout: Layout)
		local positions = if layout.device == "Phone" then UiConfig.TouchLayoutPhone else UiConfig.TouchLayoutTablet
		attack.Position = UDim2.new(1, -positions.Attack.X, 1, -positions.Attack.Y)
		block.Position = UDim2.new(1, -positions.Block.X, 1, -positions.Block.Y)
		slide.Position = UDim2.new(1, -positions.Slide.X, 1, -positions.Slide.Y)
		special.Position = UDim2.new(1, -positions.Special.X, 1, -positions.Special.Y)
	end)

	return {
		attackButton = attack,
		blockButton = block,
		slideButton = slide,
		specialButton = special,
		frame = frame,
		setBlocking = function(blocking: boolean)
			block.BackgroundTransparency = if blocking then 0 else 0.25
			local stroke = block:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Transparency = if blocking then 0 else 0.6
			end
		end,
		setMode = function(mode: string)
			-- Wild: the pad replaces ATK and BLOCK
			attack.Visible = mode == "Classic"
			block.Visible = mode == "Classic"
		end,
	}
end

return MobileControlsController
