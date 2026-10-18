--!strict
-- Small, temporary combo feedback (display only; the server decides what a sequence does):
--   * tiny input chips (A B J E) near the combat controls that fade after a moment
--   * the COMBO TRAINING board in the basement training yard lists the equipped weapon's
--     combinations, its aerial attack and the input mapping (local SurfaceGui per player)
-- Nothing large stays on screen during combat.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ComboDefinitions = require(Shared:WaitForChild("ComboDefinitions"))
local InputDefinitions = require(Shared:WaitForChild("InputDefinitions"))
local SpecialMoveDefinitions = require(Shared:WaitForChild("SpecialMoveDefinitions"))
local UiConfig = require(Shared:WaitForChild("UiConfig"))

type Visibility = {
	register: (group: string, element: GuiObject, wanted: (() -> boolean)?, forced: (() -> boolean)?) -> (),
}
type Layout = { device: string, touch: boolean }

export type ComboFeedback = {
	input: (letter: string) -> (),
	clear: () -> (),
	showBoard: (weapon: any) -> (),
}

local ComboFeedbackController = {}

local COLORS: { [string]: Color3 } = {
	A = Color3.fromRGB(230, 90, 60),
	B = Color3.fromRGB(80, 140, 230),
	J = Color3.fromRGB(110, 210, 120),
	E = UiConfig.Gold,
}

function ComboFeedbackController.start(group: (string, Vector2, UDim2, UDim2?) -> Frame, visibility: Visibility, onLayout: ((Layout) -> ()) -> (), lobby: Instance?): ComboFeedback
	local frame = group("ComboInputs", Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -34), UDim2.fromOffset(6 * 26, 22))
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 4)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = frame
	-- Pooled chips (never created per input)
	local chips: { TextLabel } = {}
	for i = 1, InputDefinitions.MaxLength do
		local chip = Instance.new("TextLabel")
		chip.Size = UDim2.fromOffset(22, 22)
		chip.BackgroundTransparency = 0.15
		chip.Font = Enum.Font.GothamBlack
		chip.TextSize = 13
		chip.TextColor3 = Color3.new(1, 1, 1)
		chip.Visible = false
		chip.LayoutOrder = i
		chip.Parent = frame
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = chip
		table.insert(chips, chip)
	end
	local count = 0
	local token = 0
	local lastInput = 0

	local function clear()
		token += 1
		count = 0
		for _, chip in chips do
			chip.Visible = false
		end
	end

	visibility.register("Specials", frame, function()
		return count > 0
	end)

	onLayout(function(layout: Layout)
		-- Touch: above the combat buttons on the right; otherwise just above the bottom hint
		if layout.touch then
			frame.AnchorPoint = Vector2.new(1, 1)
			frame.Position = UDim2.new(1, -16, 1, -(if layout.device == "Phone" then 270 else 430))
		else
			frame.AnchorPoint = Vector2.new(0.5, 1)
			frame.Position = UDim2.new(0.5, 0, 1, -34)
		end
	end)

	------------------------------------------------------------------ training board
	local boardText: TextLabel? = nil
	local board = lobby and lobby:FindFirstChild("ComboTrainingBoard", true)
	if board and board:IsA("BasePart") then
		local surface = Instance.new("SurfaceGui")
		surface.Name = "ComboTraining"
		surface.Face = Enum.NormalId.Front
		surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		surface.PixelsPerStud = 40
		surface.LightInfluence = 0
		surface.Adornee = board
		surface.Parent = board
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = 15
		label.TextColor3 = Color3.new(1, 1, 1)
		label.RichText = true
		label.TextWrapped = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Top
		label.Parent = surface
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 14)
		padding.PaddingTop = UDim.new(0, 10)
		padding.Parent = label
		boardText = label
	end

	return {
		input = function(letter: string)
			local now = os.clock()
			if now - lastInput > InputDefinitions.MaxGap or count >= #chips then
				clear()
			end
			lastInput = now
			count += 1
			local chip = chips[count]
			chip.Text = letter
			chip.BackgroundColor3 = COLORS[letter] or UiConfig.Panel
			chip.TextTransparency = 0
			chip.BackgroundTransparency = 0.15
			chip.Visible = true
			token += 1
			local myToken = token
			task.delay(1.2, function()
				if token == myToken then
					for i = 1, count do
						TweenService:Create(chips[i], TweenInfo.new(0.3), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
					end
					task.wait(0.3)
					if token == myToken then
						clear()
					end
				end
			end)
			if letter == "E" then
				task.delay(0.4, function()
					if token == myToken then
						clear()
					end
				end)
			end
		end,
		clear = clear,
		showBoard = function(weapon: any)
			local label = boardText
			if not label or not weapon then
				return
			end
			local lines = { ('<font size="22" color="#FFD246"><b>COMBO TRAINING</b></font>'), ("<b>%s</b>"):format(weapon.DisplayName:upper()) }
			local aerial = SpecialMoveDefinitions[weapon.Aerial]
			table.insert(lines, ("JUMP → ATTACK: %s"):format(if aerial then aerial.Name else "-"))
			local combos: { any } = ComboDefinitions.ByWeapon[weapon.Id] or {}
			for _, entry in combos do
				local color = if entry.Advanced then "#FFD246" else "#DDDDDD"
				table.insert(lines, ('<font color="%s">%s</font>  %s'):format(color, entry.Name, ComboDefinitions.describe(entry.Sequence)))
			end
			local d, t = InputDefinitions.Desktop, InputDefinitions.Touch
			table.insert(lines, "")
			table.insert(lines, ('<font color="#BBBBBB">A %s / %s · B %s · J %s · ENTER %s</font>'):format(d.Attack, t.Attack, "block tap", d.Jump, t.Execute))
			table.insert(lines, '<font color="#BBBBBB">Practise on the dummies: no Aura here.</font>')
			label.Text = table.concat(lines, "\n")
		end,
	}
end

return ComboFeedbackController
