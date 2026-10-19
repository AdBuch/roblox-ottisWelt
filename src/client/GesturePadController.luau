--!strict
-- The gesture combat pad (Wild mode) and the Special gesture surface (both modes).
--   * Pad: a compact circle in the lower-right combat area, sized relative to the screen
--     (ControlModeDefinitions.PadRadius*). Input that STARTS inside the pad is a gesture; everything
--     outside stays normal camera control. One gesture = one request; it locks when the finger lifts.
--   * Samples are normalized by the pad radius (never pixels) and sent to the server, which
--     re-classifies them (GestureDefinitions.classify) - the local classification is preview only.
--   * Hold the pad centre = block (release ends it); a short tap = parry attempt (a quick block).
--   * Special Mode: the pad turns gold, the next gesture is a Special. While drawing, a compact
--     preview shows the move and its Momentum cost (red if not affordable). Expires after
--     SpecialModeSeconds. Desktop Classic: draw with the mouse anywhere (virtual pad around the
--     press point); touch Classic: the pad appears just for the Special.
--   * Training: an optional trace shows the recognized path, direction and tier.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ControlModeDefinitions = require(Shared:WaitForChild("ControlModeDefinitions"))
local GestureDefinitions = require(Shared:WaitForChild("GestureDefinitions"))
local SpecialMoveDefinitions = require(Shared:WaitForChild("SpecialMoveDefinitions"))
local UiConfig = require(Shared:WaitForChild("UiConfig"))
local WeaponAttackDefinitions = require(Shared:WaitForChild("WeaponAttackDefinitions"))
local WeaponDefinitions = require(Shared:WaitForChild("WeaponDefinitions"))
local WeaponSpecialDefinitions = require(Shared:WaitForChild("WeaponSpecialDefinitions"))

export type GesturePayload = { points: { Vector2 }, seconds: number, special: boolean }

export type Options = {
	gui: ScreenGui,
	onGesture: (payload: GesturePayload, result: GestureDefinitions.Result) -> (),
	onBlock: (held: boolean) -> (),
	isTouch: () -> boolean,
	device: () -> string,
	showTrace: () -> boolean, -- training area only
}

export type Pad = {
	setWild: (wild: boolean) -> (),
	setVisible: (visible: boolean) -> (),
	enterSpecial: () -> (),
	cancel: () -> (),
	isSpecial: () -> boolean,
	captureMouse: (input: InputObject) -> boolean, -- desktop Classic special drawing
}

local GesturePadController = {}

local GOLD = UiConfig.Gold
local PAD_COLOR = Color3.fromRGB(40, 30, 22)

-- Name + cost preview for a gesture result with the equipped weapon.
local function preview(result: GestureDefinitions.Result): (string?, number)
	local weapon = WeaponDefinitions.ById[tostring(Players.LocalPlayer:GetAttribute(Config.EquippedWeaponAttribute))] or WeaponDefinitions.ById[WeaponDefinitions.Starter]
	local specials = WeaponSpecialDefinitions.forPrefix(WeaponAttackDefinitions.prefixOf(weapon.Basic))
	if not specials then
		return nil, 0
	end
	local family = if result.kind == "CircleDown" then "Ultimate" else result.kind
	local id = (specials :: any)[family]
	local move = id and (SpecialMoveDefinitions :: any)[id]
	if not move then
		return nil, 0
	end
	local tier = if family == "Ultimate" then 4 elseif family == "Circle" then WeaponSpecialDefinitions.CircleTier else result.tier
	local name = if tier == 4 then move.Name else ("%s %s"):format(move.Name, WeaponSpecialDefinitions.TierNames[tier])
	return name, WeaponSpecialDefinitions.TierCost[tier]
end

function GesturePadController.start(options: Options): Pad
	local player = Players.LocalPlayer
	local wild = false
	local specialUntil = 0
	local forcedVisible = false

	-- Pad UI
	local pad = Instance.new("Frame")
	pad.Name = "GesturePad"
	pad.AnchorPoint = Vector2.new(0.5, 0.5)
	pad.BackgroundColor3 = PAD_COLOR
	pad.BackgroundTransparency = 0.45
	pad.Visible = false
	pad.Active = false
	pad.Parent = options.gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = pad
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0.55
	stroke.Thickness = 2
	stroke.Parent = pad
	local center = Instance.new("Frame")
	center.AnchorPoint = Vector2.new(0.5, 0.5)
	center.Position = UDim2.fromScale(0.5, 0.5)
	center.Size = UDim2.fromScale(ControlModeDefinitions.PadCenterHold * 2, ControlModeDefinitions.PadCenterHold * 2)
	center.BackgroundColor3 = Color3.fromRGB(70, 110, 170)
	center.BackgroundTransparency = 0.55
	center.Parent = pad
	local centerCorner = Instance.new("UICorner")
	centerCorner.CornerRadius = UDim.new(1, 0)
	centerCorner.Parent = center
	local hint = Instance.new("TextLabel")
	hint.Size = UDim2.fromScale(1, 1)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.GothamBold
	hint.TextScaled = true
	hint.TextColor3 = Color3.new(1, 1, 1)
	hint.TextTransparency = 0.35
	hint.Text = "BLOCK"
	hint.Parent = center
	local hintLimit = Instance.new("UITextSizeConstraint")
	hintLimit.MaxTextSize = 12
	hintLimit.Parent = hint

	-- Preview label (special name + cost) and trace dots
	local previewLabel = Instance.new("TextLabel")
	previewLabel.Name = "SpecialPreview"
	previewLabel.AnchorPoint = Vector2.new(0.5, 1)
	previewLabel.Size = UDim2.fromOffset(220, 36)
	previewLabel.BackgroundColor3 = UiConfig.Panel
	previewLabel.BackgroundTransparency = 0.25
	previewLabel.Font = Enum.Font.GothamBlack
	previewLabel.TextSize = 13
	previewLabel.TextColor3 = GOLD
	previewLabel.RichText = true
	previewLabel.Visible = false
	previewLabel.ZIndex = 5
	previewLabel.Parent = options.gui
	local previewCorner = Instance.new("UICorner")
	previewCorner.CornerRadius = UDim.new(0, 8)
	previewCorner.Parent = previewLabel
	local traceDots: { Frame } = {}
	for i = 1, GestureDefinitions.MaxSamples do
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Size = UDim2.fromOffset(6, 6)
		dot.BackgroundColor3 = GOLD
		dot.BackgroundTransparency = 0.2
		dot.Visible = false
		dot.ZIndex = 4
		dot.Parent = options.gui
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = dot
		traceDots[i] = dot
	end

	local function radiusPixels(): number
		local camera = Workspace.CurrentCamera
		local viewport = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		local short = math.min(viewport.X, viewport.Y)
		local device = options.device()
		local share = if device == "Phone" then ControlModeDefinitions.PadRadiusPhone elseif device == "Tablet" then ControlModeDefinitions.PadRadiusTablet else ControlModeDefinitions.PadRadiusDesktop
		return math.max(48, short * share)
	end

	local function layout()
		local radius = radiusPixels()
		local device = options.device()
		local anchor = if not options.isTouch() then UiConfig.DesktopPad elseif device == "Phone" then UiConfig.TouchLayoutPhone.Pad else UiConfig.TouchLayoutTablet.Pad
		local inset = 0
		pad.Size = UDim2.fromOffset(radius * 2, radius * 2)
		pad.Position = UDim2.new(1, -math.max(anchor.X, radius + 8), 1, -math.max(anchor.Y, radius + 8) - inset)
	end

	local function specialActive(): boolean
		return os.clock() < specialUntil
	end

	local function refreshVisual()
		local special = specialActive()
		pad.Visible = (wild or forcedVisible or (special and options.isTouch()))
		stroke.Color = if special then GOLD else Color3.new(1, 1, 1)
		stroke.Transparency = if special then 0 else 0.55
		pad.BackgroundColor3 = if special then Color3.fromRGB(90, 66, 20) else PAD_COLOR
		hint.Text = if special then "SPECIAL" else "BLOCK"
		center.BackgroundColor3 = if special then GOLD else Color3.fromRGB(70, 110, 170)
	end

	-- Gesture tracking ------------------------------------------------------------------
	type Track = { input: InputObject?, origin: Vector2, radius: number, points: { Vector2 }, started: number, holdBlock: boolean, special: boolean, centerStart: boolean }
	local track: Track? = nil

	local function hideTrace()
		for _, dot in traceDots do
			dot.Visible = false
		end
		previewLabel.Visible = false
	end

	local function updatePreview(current: Track)
		local result = GestureDefinitions.classify(current.points, os.clock() - current.started)
		local last = current.points[#current.points]
		local screen = current.origin + Vector2.new(last.X, -last.Y) * current.radius
		if current.special then
			local name, cost = preview(result)
			local momentum = tonumber(player:GetAttribute(Config.MomentumAttribute)) or 0
			if name then
				local affordable = momentum >= cost
				previewLabel.Text = ('%s\n<font size="11" color="%s">%d MOMENTUM</font>'):format(name, if affordable then "#FFE6A0" else "#FF6B5E", cost)
				previewLabel.TextColor3 = if affordable then GOLD else Color3.fromRGB(255, 110, 100)
				previewLabel.Position = UDim2.fromOffset(screen.X, screen.Y - 18)
				previewLabel.Visible = true
			else
				previewLabel.Visible = false
			end
		end
		if options.showTrace() then
			for i, dot in traceDots do
				local p = current.points[i]
				if p then
					local s = current.origin + Vector2.new(p.X, -p.Y) * current.radius
					dot.Position = UDim2.fromOffset(s.X, s.Y)
					dot.Visible = true
				else
					dot.Visible = false
				end
			end
			if not current.special and result.kind ~= "None" then
				previewLabel.Text = ("%s · TIER %d"):format(result.kind:upper(), result.tier)
				previewLabel.TextColor3 = Color3.new(1, 1, 1)
				previewLabel.Position = UDim2.fromOffset(screen.X, screen.Y - 18)
				previewLabel.Visible = true
			end
		end
	end

	local function begin(input: InputObject?, origin: Vector2, radius: number, special: boolean, centerStart: boolean)
		track = { input = input, origin = origin, radius = radius, points = { Vector2.zero }, started = os.clock(), holdBlock = false, special = special, centerStart = centerStart }
		local myTrack = track
		if centerStart and not special then
			task.delay(ControlModeDefinitions.HoldBlockSeconds, function()
				local current = track
				if current == myTrack and current then
					local last = current.points[#current.points]
					if last.Magnitude <= ControlModeDefinitions.PadCenterHold then
						current.holdBlock = true -- holding the centre = block
						options.onBlock(true)
					end
				end
			end)
		end
	end

	local function move(position: Vector2)
		local current = track
		if not current then
			return
		end
		local relative = (position - current.origin) / current.radius
		local point = Vector2.new(relative.X, -relative.Y) -- y up
		local last = current.points[#current.points]
		if (point - last).Magnitude >= GestureDefinitions.SampleSpacing and #current.points < GestureDefinitions.MaxSamples then
			table.insert(current.points, point)
			if current.holdBlock and point.Magnitude > ControlModeDefinitions.PadCenterHold * 1.6 then
				-- dragged out of the centre while blocking: the block ends, the gesture continues
				current.holdBlock = false
				options.onBlock(false)
			end
			updatePreview(current)
		end
	end

	local function finish()
		local current = track
		track = nil
		hideTrace()
		if not current then
			return
		end
		local seconds = os.clock() - current.started
		if current.holdBlock then
			options.onBlock(false)
			return
		end
		local result = GestureDefinitions.classify(current.points, seconds)
		if result.kind == "Tap" and not current.special then
			-- a short tap = parry attempt: a quick block press (the server judges the timing)
			options.onBlock(true)
			task.delay(0.15, function()
				options.onBlock(false)
			end)
			return
		end
		if result.kind == "None" or result.kind == "Tap" then
			return -- too small / unrecognized: nothing happens, no accidental attack
		end
		local special = current.special and specialActive()
		if current.special then
			specialUntil = 0
			refreshVisual()
		end
		options.onGesture({ points = current.points, seconds = seconds, special = special }, result)
	end

	local function insidePad(position: Vector2): (boolean, boolean)
		if not pad.Visible then
			return false, false
		end
		local centerPoint = pad.AbsolutePosition + pad.AbsoluteSize / 2
		local radius = pad.AbsoluteSize.X / 2
		local distance = (position - centerPoint).Magnitude
		return distance <= radius, distance <= radius * ControlModeDefinitions.PadCenterHold
	end

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if track then
			return
		end
		local isTouch = input.UserInputType == Enum.UserInputType.Touch
		local isMouse = input.UserInputType == Enum.UserInputType.MouseButton1
		if not isTouch and not isMouse then
			return
		end
		local position = Vector2.new(input.Position.X, input.Position.Y)
		local inside, inCenter = insidePad(position)
		if inside then
			local centerPoint = pad.AbsolutePosition + pad.AbsoluteSize / 2
			begin(input, if inCenter then position else centerPoint, pad.AbsoluteSize.X / 2, specialActive(), inCenter)
			-- Starting off-centre: the first sample is where the finger went down
			if not inCenter then
				move(position)
			end
		end
		if processed and not inside then
			return
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		local current = track
		if not current then
			return
		end
		if input == current.input or (current.input and current.input.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement) or (current.input == nil and input.UserInputType == Enum.UserInputType.MouseMovement) then
			move(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local current = track
		if current and (input == current.input or (input.UserInputType == Enum.UserInputType.MouseButton1 and (current.input == nil or current.input.UserInputType == Enum.UserInputType.MouseButton1))) then
			finish()
		end
	end)

	-- Special Mode expiry
	task.spawn(function()
		while true do
			task.wait(0.25)
			if specialUntil > 0 and not specialActive() and not track then
				specialUntil = 0
				refreshVisual()
			end
		end
	end)
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	end
	layout()

	return {
		setWild = function(value: boolean)
			wild = value
			track = nil
			hideTrace()
			layout()
			refreshVisual()
		end,
		setVisible = function(value: boolean)
			forcedVisible = value
			refreshVisual()
		end,
		enterSpecial = function()
			specialUntil = os.clock() + GestureDefinitions.SpecialModeSeconds
			layout()
			refreshVisual()
		end,
		cancel = function()
			local current = track
			track = nil
			hideTrace()
			if current and current.holdBlock then
				options.onBlock(false)
			end
			specialUntil = 0
			refreshVisual()
		end,
		isSpecial = specialActive,
		captureMouse = function(input: InputObject): boolean
			-- Desktop Classic special: a virtual pad around the press point
			if not specialActive() or track then
				return false
			end
			local camera2 = Workspace.CurrentCamera
			local height = if camera2 then camera2.ViewportSize.Y else 720
			begin(input, Vector2.new(input.Position.X, input.Position.Y), height * GestureDefinitions.DesktopPadShare, true, false)
			return true
		end,
	}
end

return GesturePadController
