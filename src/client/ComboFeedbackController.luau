--!strict
-- Training feedback (display only; the server decides what every action does):
--   * tiny input chips (ATK, BLK, SLD, SPC, PAD) near the combat controls that fade after a moment
--   * the TRAINING board in the lobby training yard: Classic and Wild in short steps, Momentum and
--     the equipped weapon's Special families with their costs (local SurfaceGui per player)
-- Nothing large stays on screen during combat. The gesture trace is drawn by GesturePadController
-- and only shown in the training area.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MomentumConfig = require(Shared:WaitForChild("MomentumConfig"))
local SpecialMoveDefinitions = require(Shared:WaitForChild("SpecialMoveDefinitions"))
local UiConfig = require(Shared:WaitForChild("UiConfig"))
local WeaponAttackDefinitions = require(Shared:WaitForChild("WeaponAttackDefinitions"))
local WeaponSpecialDefinitions = require(Shared:WaitForChild("WeaponSpecialDefinitions"))

type Visibility = {
	register: (group: string, element: GuiObject, wanted: (() -> boolean)?, forced: (() -> boolean)?) -> (),
}
type Layout = { device: string, touch: boolean }

export type ComboFeedback = {
	input: (label: string) -> (),
	clear: () -> (),
	showBoard: (weapon: any, mode: string) -> (),
}

local ComboFeedbackController = {}

local CHIP_LIMIT = 6
local CHIP_GAP = 1.1 -- seconds of silence before a new chip row starts
local COLORS: { [string]: Color3 } = {
	ATK = Color3.fromRGB(230, 90, 60),
	BLK = Color3.fromRGB(80, 140, 230),
	SLD = Color3.fromRGB(120, 200, 255),
	SPC = UiConfig.Gold,
	PAD = Color3.fromRGB(150, 220, 150),
}

local FAMILY_ORDER = { "Left", "Right", "Up", "Down", "Circle", "Ultimate" }

function ComboFeedbackController.start(group: (string, Vector2, UDim2, UDim2?) -> Frame, visibility: Visibility, onLayout: ((Layout) -> ()) -> (), lobby: Instance?): ComboFeedback
	local frame = group("ComboInputs", Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -34), UDim2.fromOffset(CHIP_LIMIT * 46, 22))
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Padding = UDim.new(0, 4)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = frame
	-- Pooled chips (never created per input)
	local chips: { TextLabel } = {}
	for i = 1, CHIP_LIMIT do
		local chip = Instance.new("TextLabel")
		chip.Size = UDim2.fromOffset(42, 22)
		chip.BackgroundTransparency = 0.15
		chip.Font = Enum.Font.GothamBlack
		chip.TextSize = 11
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
			local positions = if layout.device == "Phone" then UiConfig.TouchLayoutPhone else UiConfig.TouchLayoutTablet
			frame.AnchorPoint = Vector2.new(1, 1)
			frame.Position = UDim2.new(1, -16, 1, -(positions.Attack.Y + 60))
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
		label.TextSize = 14
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
		input = function(label: string)
			local now = os.clock()
			if now - lastInput > CHIP_GAP or count >= #chips then
				clear()
			end
			lastInput = now
			count += 1
			local chip = chips[count]
			chip.Text = label
			chip.BackgroundColor3 = COLORS[label] or UiConfig.Panel
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
		end,
		clear = clear,
		showBoard = function(weapon: any, mode: string)
			local label = boardText
			if not label or not weapon then
				return
			end
			local lines = { '<font size="22" color="#FFD246"><b>TRAINING</b></font>', ("<b>%s</b>  ·  %s"):format(weapon.DisplayName:upper(), mode:upper()) }
			if mode == "Wild" then
				table.insert(lines, "Swipe the pad: Left / Right / Up / Down, or a circle for the spin.")
				table.insert(lines, "Hold the pad centre = block · quick tap = parry · SLIDE for mobility.")
			else
				table.insert(lines, "LMB / R2 / ATK: attack chain (moving changes the move).")
				table.insert(lines, "RMB / L2 / BLOCK hold = block · Shift / C / SLIDE · Space / A jump.")
			end
			table.insert(lines, ('<font color="#BBBBBB">MOMENTUM 0-100: vary your attacks, slide-dodge, perfect-block. Start: %d in Elimination rounds.</font>'):format(MomentumConfig.Start.EliminationRound))
			table.insert(lines, "")
			local prefix = WeaponAttackDefinitions.prefixOf(weapon.Basic)
			local families = WeaponSpecialDefinitions.forPrefix(prefix)
			if families then
				table.insert(lines, '<font color="#FFD246"><b>SPECIALS</b></font>  Q / X / SPECIAL, then draw: tier by length (25 / 50 / 75)')
				for _, family in FAMILY_ORDER do
					local moveId = (families :: any)[family]
					local move = moveId and (SpecialMoveDefinitions :: any)[moveId]
					if move then
						table.insert(lines, ("%s  %s"):format(family:upper(), move.Name))
					end
				end
			end
			table.insert(lines, '<font color="#BBBBBB">Practise on the dummies: no Aura here.</font>')
			label.Text = table.concat(lines, "\n")
		end,
	}
end

return ComboFeedbackController
