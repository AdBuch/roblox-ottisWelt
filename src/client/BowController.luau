--!strict
-- A subtle crosshair while the Hunter Bow is equipped and you can shoot (no aim assistance):
-- at the mouse on keyboard & mouse, at the screen centre on gamepad and touch.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local BowController = {}

function BowController.start(gui: ScreenGui, weaponAttribute: string, canAct: () -> boolean)
	local player = Players.LocalPlayer
	local cross = Instance.new("Frame")
	cross.Name = "BowCrosshair"
	cross.AnchorPoint = Vector2.new(0.5, 0.5)
	cross.Size = UDim2.fromOffset(28, 28)
	cross.BackgroundTransparency = 1
	cross.Visible = false
	cross.Parent = gui
	local function bar(size: UDim2, position: UDim2)
		local line = Instance.new("Frame")
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.Size = size
		line.Position = position
		line.BackgroundColor3 = Color3.new(1, 1, 1)
		line.BackgroundTransparency = 0.35
		line.BorderSizePixel = 0
		line.Parent = cross
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new(0, 0, 0)
		stroke.Transparency = 0.6
		stroke.Parent = line
	end
	bar(UDim2.fromOffset(2, 7), UDim2.new(0.5, 0, 0, 3))
	bar(UDim2.fromOffset(2, 7), UDim2.new(0.5, 0, 1, -3))
	bar(UDim2.fromOffset(7, 2), UDim2.new(0, 3, 0.5, 0))
	bar(UDim2.fromOffset(7, 2), UDim2.new(1, -3, 0.5, 0))
	bar(UDim2.fromOffset(3, 3), UDim2.fromScale(0.5, 0.5))

	RunService.RenderStepped:Connect(function()
		local equipped = player:GetAttribute(weaponAttribute) == "HunterBow"
		local show = equipped and canAct()
		cross.Visible = show
		if not show then
			return
		end
		local lastInput = UserInputService:GetLastInputType()
		if UserInputService.MouseEnabled and lastInput ~= Enum.UserInputType.Gamepad1 and lastInput ~= Enum.UserInputType.Touch then
			local mouse = UserInputService:GetMouseLocation()
			local inset = GuiService:GetGuiInset()
			cross.Position = UDim2.fromOffset(mouse.X, mouse.Y - inset.Y)
		else
			cross.Position = UDim2.fromScale(0.5, 0.5)
		end
	end)
end

return BowController
