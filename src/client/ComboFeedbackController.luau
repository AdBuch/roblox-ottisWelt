--!strict
-- Training feedback (display only; the server decides what every action does):
--   * tiny input chips (ATK, BLK, SPC) near the combat controls that fade after a moment
--   * the TRAINING board in the lobby training yard: the Classic controls, block directions, the
--     special charge tiers with the equipped weapon's moves, and Momentum (local SurfaceGui)
-- Nothing large stays on screen during combat.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MomentumConfig = require(Shared:WaitForChild("MomentumConfig"))
local SpecialMoveDefinitions = require(Shared:WaitForChild("SpecialMoveDefinitions"))
local UiConfig = require(Shared:WaitForChild("UiConfig"))
local SpecialChargeDefinitions = require(Shared:WaitForChild("SpecialChargeDefinitions"))
local Practice = require(Shared:WaitForChild("SpecialPracticeDefinitions"))

type Visibility = {
	register: (group: string, element: GuiObject, wanted: (() -> boolean)?, forced: (() -> boolean)?) -> (),
}
type Layout = { device: string, touch: boolean }

export type ComboFeedback = {
	input: (label: string) -> (),
	clear: () -> (),
	showBoard: (weapon: any) -> (),
}

local ComboFeedbackController = {}

local CHIP_LIMIT = 6
local CHIP_GAP = 1.1 -- seconds of silence before a new chip row starts
local COLORS: { [string]: Color3 } = {
	ATK = Color3.fromRGB(230, 90, 60),
	BLK = Color3.fromRGB(80, 140, 230),
	SPC = UiConfig.Gold,
}


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
			frame.Position = UDim2.new(1, -16, 1, -(positions.Block.Y + 48))
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
		showBoard = function(weapon: any)
			local label = boardText
			if not label or not weapon then
				return
			end
			local lines = { '<font size="22" color="#FFD246"><b>TRAINING</b></font>', ("<b>%s</b>"):format(weapon.DisplayName:upper()) }
			table.insert(lines, "ATTACK (LMB / R2): tap again for the combo · movement turns you.")
			table.insert(lines, "Hold BLOCK (RMB / L2): stages I-III · crouch and raise shield overhead.")
			table.insert(lines, "Blocking while charging works · ATTACK or firing a special lowers the shield.")
			table.insert(lines, "")
			table.insert(lines, '<font color="#FFD246"><b>SPECIAL</b></font>  hold Q / X / SPECIAL, release to fire')
			for _, def in SpecialChargeDefinitions.Tiers do
				local moveId = SpecialChargeDefinitions.specialFor(nil, weapon.Basic, def.Family)
				local move = moveId and (SpecialMoveDefinitions :: any)[moveId]
				table.insert(lines, ("%s · %d Momentum · %.1f s · %s · %s"):format(def.Name, def.MomentumCost, def.From, if move then move.Name else "-", Practice.label(Players.LocalPlayer, weapon.Id, moveId or "")))
			end
			local ultimateId = SpecialChargeDefinitions.specialFor(nil, weapon.Basic, "Ultimate")
			local ultimate = ultimateId and (SpecialMoveDefinitions :: any)[ultimateId]
			if ultimate and ultimateId then
				table.insert(lines, ("ULTIMATE · 100 Momentum · 2.5 s · %s · %s"):format(ultimate.Name, Practice.label(Players.LocalPlayer, weapon.Id, ultimateId)))
			end
			for _, family in { "Up", "Circle" } do
				local id = SpecialChargeDefinitions.specialFor(nil, weapon.Basic, family)
				local special = id and (SpecialMoveDefinitions :: any)[id]
				if special and id then
					table.insert(lines, ("%s · %s · %s"):format(if family == "Up" then "Lv5 AIR: release SPECIAL in air" else "Lv9 ELITE: release SPECIAL holding BLOCK", special.Name, Practice.label(Players.LocalPlayer, weapon.Id, id)))
				end
			end
			table.insert(lines, "Failed special = fall. Every valid attempt improves success by 1%; saved, also in training.")
			table.insert(lines, ('<font color="#BBBBBB">MOMENTUM 0-%d: recharges over time; attacks and blocks do not change it.</font>'):format(MomentumConfig.Max))
			table.insert(lines, '<font color="#BBBBBB">Practise on the dummies: no Aura here.</font>')
			label.Text = table.concat(lines, "\n")
		end,
	}
end

return ComboFeedbackController
