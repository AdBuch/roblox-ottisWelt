--!strict
-- Touch combat buttons: FOUR equal buttons as an exact rhombus (UiConfig.TouchRhombus):
--   BLOCK top C+(0,-r) · SPECIAL left C+(-r,0) · ATTACK right C+(r,0) · JUMP bottom C+(0,r)
-- One square container (side = size + 2r) sits at the bottom-right edge with a margin; C is its
-- centre, every button uses the same size, shape, stroke and label layout, and all four scale with
-- the same UIScale (no distortion; phone and tablet only differ in size / radius / margin).
-- JUMP replaces Roblox's own touch jump button functionally (tap = jump, hold = jump again on every
-- landing). The native button is hidden while ours is shown and re-hidden whenever Roblox recreates
-- or re-shows it (respawn, new TouchGui), so there is never a fifth button.
-- The SPECIAL ring shows server-owned Momentum continuously, including while not held.
-- Labels never rotate; decorative children never consume touch input.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
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
	jumpButton: TextButton,
	frame: Frame,
	setBlocking: (blocking: boolean) -> (),
	setCharge: (seconds: number?) -> (),
	releaseJump: () -> (), -- a menu opened: end a held jump
}
local MobileControlsController = {}
local Preview = require(script.Parent.SpecialPreview)
local PHASE = UiConfig.SpecialPhaseColors
local STAGE = UiConfig.BlockStageColors
local EMPTY = Color3.fromRGB(65, 57, 46)
local DOT_COUNT = 40
local MENU = UiConfig.Menu
local BLOCK_ACCENT = Color3.fromRGB(120, 170, 255)

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

type Face = { button: TextButton, icon: TextLabel, name: TextLabel, sub: TextLabel, stroke: UIStroke }

-- One button face; identical for all four (only icon, name and accent color differ).
local function makeButton(parent: Instance, id: string, icon: string, text: string, accent: Color3): Face
	local button = Instance.new("TextButton")
	button.Name = id
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.BackgroundColor3 = MENU.Panel
	button.BackgroundTransparency = 0.2
	button.AutoButtonColor = true
	button.Text = ""
	button.Selectable = false -- gamepad UI navigation never lands on touch buttons
	button.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button
	local stroke = Instance.new("UIStroke")
	stroke.Color = accent
	stroke.Transparency = 0.15
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	local function label(name: string, y: number, height: number, font: Enum.Font, color: Color3, maxSize: number): TextLabel
		local l = Instance.new("TextLabel")
		l.Name = name
		l.AnchorPoint = Vector2.new(0.5, 0)
		l.Position = UDim2.fromScale(0.5, y)
		l.Size = UDim2.fromScale(0.74, height)
		l.BackgroundTransparency = 1
		l.Font = font
		l.TextScaled = true
		l.TextColor3 = color
		l.TextStrokeTransparency = 0.55
		l.Active = false
		l.ZIndex = button.ZIndex + 2
		l.Parent = button
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = maxSize
		limit.Parent = l
		return l
	end
	local iconLabel = label("Icon", 0.17, 0.3, MENU.LabelFont, accent, 22)
	iconLabel.Text = icon
	local nameLabel = label("Name", 0.47, 0.2, MENU.TitleFont, MENU.Text, 13)
	nameLabel.Text = text
	local subLabel = label("Sub", 0.67, 0.15, MENU.LabelFont, MENU.TextMuted, 10)
	subLabel.Text = ""
	return { button = button, icon = iconLabel, name = nameLabel, sub = subLabel, stroke = stroke }
end

-- Keeps Roblox's own touch jump button hidden while ours is shown (and restores what Roblox
-- wanted when ours is hidden). Handles respawns and recreated TouchGuis. Returns a refresh function.
local function nativeJumpGuard(playerGui: Instance, suppressed: () -> boolean): () -> ()
	local wanted: { [GuiObject]: boolean } = {}
	local applying = false
	local function apply(button: GuiObject)
		applying = true
		button.Visible = if suppressed() then false else (wanted[button] ~= false)
		applying = false
	end
	local function watch(instance: Instance)
		if instance.Name ~= "JumpButton" or not instance:IsA("GuiObject") or not instance:FindFirstAncestor("TouchGui") then
			return
		end
		local button = instance :: GuiObject
		wanted[button] = button.Visible
		button:GetPropertyChangedSignal("Visible"):Connect(function()
			if not applying then
				wanted[button] = button.Visible -- what Roblox's TouchJump wants right now
				if suppressed() and button.Visible then
					apply(button)
				end
			end
		end)
		button.AncestryChanged:Connect(function()
			if not button:IsDescendantOf(playerGui) then
				wanted[button] = nil
			end
		end)
		apply(button)
	end
	playerGui.DescendantAdded:Connect(watch)
	for _, descendant in playerGui:GetDescendants() do
		watch(descendant)
	end
	return function()
		for button in wanted do
			if button.Parent then
				apply(button)
			end
		end
	end
end

function MobileControlsController.start(group: (string, Vector2, UDim2, UDim2?) -> Frame, visibility: Visibility, onLayout: ((Layout) -> ()) -> (), shown: () -> boolean): Controls
	local player = Players.LocalPlayer
	local phone = UiConfig.TouchRhombus.Phone
	local phoneBox = UiConfig.rhombusBox(phone.Size, phone.Radius)
	local frame = group("TouchControls", Vector2.new(1, 1), UDim2.new(1, -phone.Margin, 1, -phone.Margin), UDim2.fromOffset(phoneBox, phoneBox))

	local block = makeButton(frame, "Block", "🛡", "BLOCK", BLOCK_ACCENT)
	local special = makeButton(frame, "Special", "✦", "SPEZIAL", MENU.Gold)
	local attack = makeButton(frame, "Attack", "⚔", "ANGRIFF", Color3.fromRGB(255, 140, 110))
	local jump = makeButton(frame, "Jump", "▲", "SPRUNG", Color3.fromRGB(150, 225, 150))
	local faces: { [string]: Face } = { Block = block, Special = special, Attack = attack, Jump = jump }

	-- Momentum ring on SPECIAL (inside the button: it never changes the button's size or shape)
	local dots = makeRing(special.button, "Momentum_")
	local blockDots = makeRing(block.button, "BlockStage_")

	-- Layout: one centre (the container's middle), one radius, the same size for every button
	onLayout(function(layout: Layout)
		local rhombus = if layout.device == "Phone" then UiConfig.TouchRhombus.Phone else UiConfig.TouchRhombus.Tablet
		local box = UiConfig.rhombusBox(rhombus.Size, rhombus.Radius)
		frame.Size = UDim2.fromOffset(box, box)
		frame.Position = UDim2.new(1, -rhombus.Margin, 1, -rhombus.Margin)
		for id, offset in UiConfig.rhombusOffsets(rhombus.Radius) do
			local face = faces[id]
			face.button.Size = UDim2.fromOffset(rhombus.Size, rhombus.Size)
			face.button.Position = UDim2.new(0.5, offset.X, 0.5, offset.Y)
		end
	end)
	visibility.register("Controls", frame, shown)

	------------------------------------------------------------------ JUMP (replaces the native button)
	local playerGui = player:WaitForChild("PlayerGui")
	local refreshNative = nativeJumpGuard(playerGui, function()
		return frame.Visible
	end)
	frame:GetPropertyChangedSignal("Visible"):Connect(refreshNative)

	local jumpInput: InputObject? = nil
	local jumpLoop: RBXScriptConnection? = nil
	local function tryJump()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 or not humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping) then
			return
		end
		local state = humanoid:GetState()
		if humanoid.Sit or state == Enum.HumanoidStateType.Seated then
			humanoid.Sit = false
			humanoid.Jump = true
			return
		end
		local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
			and state ~= Enum.HumanoidStateType.Jumping
			and state ~= Enum.HumanoidStateType.Freefall
		if grounded then
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping) -- the server measures the jump as usual
		end
	end
	local function releaseJump()
		jumpInput = nil
		if jumpLoop then
			jumpLoop:Disconnect()
			jumpLoop = nil
		end
		jump.button.BackgroundTransparency = 0.2
	end
	jump.button.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		jumpInput = input
		jump.button.BackgroundTransparency = 0
		tryJump()
		if not jumpLoop then
			jumpLoop = RunService.Heartbeat:Connect(tryJump) -- held: jump again on every landing
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input == jumpInput then
			releaseJump() -- also when the finger slid off the button
		end
	end)
	player.CharacterAdded:Connect(releaseJump)
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		if not frame.Visible then
			releaseJump()
		end
	end)

	------------------------------------------------------------------ SPECIAL ring
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
		special.sub.Text = ("%s · %d%%"):format(tierName, math.floor(value))
		if held ~= nil then
			local preview = Preview.text(player, held, value)
			local failure = preview:match("fail %d+%%") or ""
			if failure ~= "" then special.sub.Text = failure end
		end
		special.stroke.Color = if held ~= nil then color else UiConfig.Gold
		special.stroke.Transparency = if held ~= nil then 0 else 0.3
		special.stroke.Thickness = if held ~= nil then 3 else 2
		special.button.BackgroundColor3 = if held ~= nil then color:Lerp(UiConfig.Panel, 0.45) else UiConfig.Panel
		special.button.BackgroundTransparency = if held ~= nil then 0.05 elseif available then 0.15 else 0.45
	end
	player:GetAttributeChangedSignal(Config.MomentumAttribute):Connect(refresh)
	refresh()

	-- BLOCK: the ring fills over BraceSeconds while the confirmed guard is held, colour per stage
	-- (display timing only; the server's own clock decides the real stage)
	local blockColor = block.button.BackgroundColor3
	local blockStroke = block.stroke
	local blockSince: number? = nil
	local blockLoop: RBXScriptConnection? = nil
	local function renderBlock()
		if not blockSince then
			fillRing(blockDots, 0, EMPTY)
			block.sub.Text = ""
			block.button.BackgroundColor3 = blockColor
			block.button.BackgroundTransparency = 0.25
			blockStroke.Color = BLOCK_ACCENT
			blockStroke.Transparency = 0.15
			blockStroke.Thickness = 2
			return
		end
		local seconds = os.clock() - blockSince
		local stage = BlockDefinitions.stageFor(seconds)
		local color = STAGE[stage.Stage] or STAGE[1]
		fillRing(blockDots, math.clamp(seconds / BlockDefinitions.BraceSeconds, 0, 1), color)
		block.sub.Text = stage.Name
		block.button.BackgroundColor3 = color:Lerp(blockColor, 0.5)
		block.button.BackgroundTransparency = 0
		blockStroke.Color = color
		blockStroke.Transparency = 0
		blockStroke.Thickness = 2 + stage.Stage
	end

	return {
		attackButton = attack.button,
		blockButton = block.button,
		specialButton = special.button,
		jumpButton = jump.button,
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
		releaseJump = releaseJump,
	}
end

return MobileControlsController
