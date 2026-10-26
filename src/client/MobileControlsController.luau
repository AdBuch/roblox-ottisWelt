--!strict
-- Equal-sized touch buttons: SPECIAL left, ATTACK right, BLOCK above; native JUMP below.
-- The SPECIAL ring displays server-owned Momentum continuously, including while not held; while
-- held, the button takes the colour of the phase a release would fire (I · II · III · ULT).
-- BLOCK is held: its ring fills with the hold time and changes colour per block stage (I · II · III).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BlockDefinitions = require(Shared:WaitForChild("BlockDefinitions"))
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
local PHASE = UiConfig.SpecialPhaseColors
local STAGE = UiConfig.BlockStageColors
local EMPTY = Color3.fromRGB(65, 57, 46)
local DOT_COUNT = 40

-- A ring of small dots inside a round button (decorative: never consumes touch input)
local function makeRing(button: TextButton, prefix: string): { Frame }
	local dots: { Frame } = {}
	for i = 1, DOT_COUNT do
		local angle = (i - 1) / DOT_COUNT * math.pi * 2 - math.pi / 2
		local dot = Instance.new("Frame")
		dot.Name = prefix .. i
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(0.5 + math.cos(angle) * 0.44, 0.5 + math.sin(angle) * 0.44)
		dot.Size = UDim2.fromOffset(3, 3)
		dot.BorderSizePixel = 0
		dot.BackgroundColor3 = EMPTY
		dot.ZIndex = button.ZIndex + 1
		dot.Parent = button
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = dot
		table.insert(dots, dot)
	end
	return dots
end

local function fillRing(dots: { Frame }, share: number, color: Color3)
	for i, dot in dots do
		dot.BackgroundColor3 = if share >= i / DOT_COUNT then color else EMPTY
	end
end

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
	local dots = makeRing(special, "Momentum_")
	local blockDots = makeRing(block, "BlockStage_")
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
		local color = if available then PHASE[available.Tier] else Color3.fromRGB(95, 85, 70)
		local tierName = if value >= SpecialChargeDefinitions.UltimateMomentum then "ULT" elseif available then available.Name else "..."
		if held ~= nil then
			-- while held: the colour of the phase a release would fire right now
			local selected, ultimate = SpecialChargeDefinitions.forRelease(held, value)
			color = if ultimate then UiConfig.UltimateColor elseif selected then PHASE[selected.Tier] else Color3.fromRGB(95, 85, 70)
			tierName = if ultimate then "ULT" elseif selected then selected.Name else "..."
		end
		fillRing(dots, value / MomentumConfig.Max, color)
		label.Text = ("SPECIAL\n%s · %d%%"):format(tierName, math.floor(value))
		stroke.Color = if held ~= nil then color else UiConfig.Gold
		stroke.Transparency = if held ~= nil then 0 else 0.3
		stroke.Thickness = if held ~= nil then 3 else 2
		special.BackgroundColor3 = if held ~= nil then color:Lerp(UiConfig.Panel, 0.45) else UiConfig.Panel
		special.BackgroundTransparency = if held ~= nil then 0.05 elseif available then 0.15 else 0.45
	end
	player:GetAttributeChangedSignal(Config.MomentumAttribute):Connect(refresh)
	refresh()

	-- BLOCK: the ring fills over BraceSeconds while the confirmed guard is held, colour per stage
	-- (display timing only; the server's own clock decides the real stage)
	local blockColor = block.BackgroundColor3
	local blockStroke = block:FindFirstChildOfClass("UIStroke") :: UIStroke
	local blockSince: number? = nil
	local blockLoop: RBXScriptConnection? = nil
	local function renderBlock()
		if not blockSince then
			fillRing(blockDots, 0, EMPTY)
			block.Text = "BLOCK"
			block.BackgroundColor3 = blockColor
			block.BackgroundTransparency = 0.25
			blockStroke.Color = Color3.new(1, 1, 1)
			blockStroke.Transparency = 0.6
			blockStroke.Thickness = 2
			return
		end
		local seconds = os.clock() - blockSince
		local stage = BlockDefinitions.stageFor(seconds)
		local color = STAGE[stage.Stage] or STAGE[1]
		fillRing(blockDots, math.clamp(seconds / BlockDefinitions.BraceSeconds, 0, 1), color)
		block.Text = "BLOCK\n" .. stage.Name
		block.BackgroundColor3 = color:Lerp(blockColor, 0.5)
		block.BackgroundTransparency = 0
		blockStroke.Color = color
		blockStroke.Transparency = 0
		blockStroke.Thickness = 2 + stage.Stage
	end

	return {
		attackButton = attack,
		blockButton = block,
		specialButton = special,
		frame = frame,
		setBlocking = function(blocking: boolean)
			if blocking == (blockSince ~= nil) then
				return
			end
			blockSince = if blocking then os.clock() else nil
			if blockLoop then
				blockLoop:Disconnect()
				blockLoop = nil
			end
			if blocking then
				blockLoop = RunService.RenderStepped:Connect(renderBlock)
			end
			renderBlock()
		end,
		setCharge = function(seconds: number?)
			held = seconds
			refresh()
		end,
	}
end
return MobileControlsController
