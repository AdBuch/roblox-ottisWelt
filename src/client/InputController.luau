--!strict
-- All player combat input. The client only sends INTENT; the server validates everything (state,
-- ownership, cooldowns, Momentum, targets, damage) and decides which move actually runs.
--   CLASSIC  LMB / R2 / ATK attack (server picks the contextual chain move), RMB / L2 / BLOCK hold
--            to block, Space / A / jump button jump, Left Shift or C / B / SLIDE slide,
--            Q / X / SPECIAL enters Special Mode (then draw: mouse drag, the touch pad, or flick the
--            right stick)
--   WILD     the gesture pad (GesturePadController): swipes, circle, hold centre = block, tap =
--            parry; Soft Targeting rotates the player moderately toward the enemy in front and
--            aims there; jump / SLIDE / SPECIAL as above
-- Switching modes ends a held block and cancels unfinished gestures (CombatSettingsController).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatConfig = require(Shared:WaitForChild("CombatConfig"))
local Config = require(Shared:WaitForChild("Config"))
local ControlModeDefinitions = require(Shared:WaitForChild("ControlModeDefinitions"))
local SpecialMoveDefinitions = require(Shared:WaitForChild("SpecialMoveDefinitions"))
local WeaponDefinitions = require(Shared:WaitForChild("WeaponDefinitions"))

type Remotes = {
	combatAction: RemoteEvent,
	shieldBlock: RemoteEvent,
}

export type Scheme = "Keyboard & Mouse" | "Gamepad" | "Touch"

export type Options = {
	remotes: Remotes,
	canAct: () -> boolean,
	attackButton: TextButton, -- touch buttons come from MobileControlsController
	blockButton: TextButton,
	slideButton: TextButton,
	specialButton: TextButton,
	pad: any, -- GesturePadController.Pad
	getMode: () -> string,
	onSchemeChanged: (scheme: Scheme) -> (),
	onInput: (input: string) -> (), -- local feedback chips (display only)
}

export type Input = {
	isBlockHeld: () -> boolean,
	setBlock: (held: boolean) -> (),
	sendGesture: (payload: any) -> (),
	onModeChanged: (mode: string) -> (),
	lastTarget: (model: Instance?) -> (),
}

local InputController = {}

local AIM_DISTANCE = 300

function InputController.init(options: Options): Input
	local player = Players.LocalPlayer
	local remotes = options.remotes
	local blockHeld = false
	local engaged: Instance? = nil -- the enemy we last hit (Soft Targeting prefers it)

	local function getParts(): (Humanoid?, BasePart?)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
			return humanoid, root
		end
		return nil, nil
	end

	local function faceDirection(root: BasePart, direction: Vector3)
		local flat = Vector3.new(direction.X, 0, direction.Z)
		if flat.Magnitude > 0.01 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
		end
	end

	local function cursorAim(root: BasePart): Vector3
		local camera = Workspace.CurrentCamera
		if not camera then
			return root.Position + root.CFrame.LookVector * 50
		end
		local ray: Ray
		if UserInputService.MouseEnabled and UserInputService:GetLastInputType() ~= Enum.UserInputType.Gamepad1 and UserInputService:GetLastInputType() ~= Enum.UserInputType.Touch then
			local mouse = UserInputService:GetMouseLocation()
			ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		else
			ray = Ray.new(camera.CFrame.Position, camera.CFrame.LookVector)
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { player.Character :: Instance }
		local result = Workspace:Raycast(ray.Origin, ray.Direction * AIM_DISTANCE, params)
		return if result then result.Position else ray.Origin + ray.Direction * AIM_DISTANCE
	end

	-- Soft Targeting (presentation + aim hint; the server re-validates every target):
	-- the enemy we already fight, else the closest visible enemy inside the forward cone.
	local function softTarget(root: BasePart): BasePart?
		local weapon = WeaponDefinitions.ById[tostring(player:GetAttribute(Config.EquippedWeaponAttribute))] or WeaponDefinitions.ById[WeaponDefinitions.Starter]
		local basic = (SpecialMoveDefinitions :: any)[weapon.Basic]
		local range = math.min(if basic then basic.Range else 8, 60) + ControlModeDefinitions.SoftTargetExtraRange
		local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
		local minDot = math.cos(math.rad(ControlModeDefinitions.SoftTargetCone / 2))
		local myTeam = player:GetAttribute(Config.TeamAttribute)
		local candidates: { BasePart } = {}
		local function consider(model: Instance)
			local primary = if model:IsA("Model") then model.PrimaryPart else nil
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if primary and (not humanoid or humanoid.Health > 0) then
				table.insert(candidates, primary)
			end
		end
		for _, model in CollectionService:GetTagged(CombatConfig.ZombieTag) do
			consider(model)
		end
		for _, model in CollectionService:GetTagged(Config.OttiTag) do
			consider(model)
		end
		for _, model in CollectionService:GetTagged(Config.TrainingDummyTag) do
			consider(model)
		end
		if typeof(myTeam) == "string" and myTeam ~= "" then
			for _, other in Players:GetPlayers() do
				local team = other:GetAttribute(Config.TeamAttribute)
				-- only opposing fighters: never teammates, spectators or lobby players
				if other ~= player and typeof(team) == "string" and team ~= "" and team ~= myTeam and other:GetAttribute(Config.ArenaRoleAttribute) == "FIGHTER" and other.Character then
					consider(other.Character)
				end
			end
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { player.Character :: Instance }
		local best: BasePart? = nil
		local bestScore = -math.huge
		for _, part in candidates do
			local offset = Vector3.new(part.Position.X - root.Position.X, 0, part.Position.Z - root.Position.Z)
			local distance = offset.Magnitude
			if distance > 0.1 and distance <= range and math.abs(part.Position.Y - root.Position.Y) <= 8 then
				local dot = offset.Unit:Dot(look)
				if dot >= minDot then
					local hit = Workspace:Raycast(root.Position, part.Position - root.Position, params)
					local visible = hit == nil or hit.Instance:IsDescendantOf(part.Parent :: Instance)
					if visible then
						local score = dot * 2 - distance / range + (if engaged and part:IsDescendantOf(engaged) then 1.5 else 0)
						if score > bestScore then
							best, bestScore = part, score
						end
					end
				end
			end
		end
		return best
	end

	-- Aim for an attack: Wild -> Soft Target (moderate turn, never a teleport), else the cursor.
	local function aimFor(root: BasePart): Vector3
		if options.getMode() == "Wild" then
			local target = softTarget(root)
			if target then
				local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
				local wanted = Vector3.new(target.Position.X - root.Position.X, 0, target.Position.Z - root.Position.Z).Unit
				local angle = math.acos(math.clamp(look:Dot(wanted), -1, 1))
				local maxTurn = math.rad(ControlModeDefinitions.MaxTurnDegrees)
				if angle > maxTurn then
					local sign = if look:Cross(wanted).Y >= 0 then 1 else -1
					wanted = CFrame.fromAxisAngle(Vector3.yAxis, sign * maxTurn):VectorToWorldSpace(look)
				end
				faceDirection(root, wanted)
				return target.Position
			end
			return root.Position + root.CFrame.LookVector * 30
		end
		local point = cursorAim(root)
		faceDirection(root, point - root.Position)
		return point
	end

	local function attack()
		if not options.canAct() or blockHeld then
			return
		end
		local _, root = getParts()
		if not root then
			return
		end
		remotes.combatAction:FireServer("Basic", aimFor(root))
		options.onInput("ATK")
	end

	local function setBlock(held: boolean)
		if blockHeld == held then
			return
		end
		blockHeld = held
		local humanoid = getParts()
		if humanoid then
			humanoid.AutoRotate = not held
		end
		remotes.shieldBlock:FireServer(held)
		if held and options.canAct() then
			options.onInput("BLK")
		end
	end

	local function slide()
		if not options.canAct() then
			return
		end
		remotes.combatAction:FireServer("Slide")
		options.onInput("SLD")
	end

	local function sendGesture(payload: any)
		if not options.canAct() then
			return
		end
		local _, root = getParts()
		if not root then
			return
		end
		payload.aim = aimFor(root)
		remotes.combatAction:FireServer("Gesture", payload)
		options.onInput(if payload.special then "SPC" else "PAD")
	end

	local function enterSpecial()
		if options.canAct() then
			options.pad.enterSpecial()
			options.onInput("SPC")
		end
	end

	-- Gamepad special: the right stick path while in Special Mode becomes the gesture
	local stickPath: { Vector2 }? = nil
	local stickStart = 0

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		local inputType, key = input.UserInputType, input.KeyCode
		local wild = options.getMode() == "Wild"
		if inputType == Enum.UserInputType.MouseButton1 then
			if options.pad.captureMouse(input) then
				return -- Special Mode: this press draws the gesture
			end
			if not wild then
				attack()
			end
		elseif key == Enum.KeyCode.ButtonR2 then
			attack()
		elseif inputType == Enum.UserInputType.MouseButton2 or key == Enum.KeyCode.ButtonL2 then
			setBlock(true)
		elseif table.find(ControlModeDefinitions.SlideKeys, key) or key == ControlModeDefinitions.GamepadSlide then
			slide()
		elseif key == ControlModeDefinitions.SpecialKey or key == ControlModeDefinitions.GamepadSpecial then
			enterSpecial()
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.ButtonL2 then
			setBlock(false)
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if input.KeyCode ~= Enum.KeyCode.Thumbstick2 or not options.pad.isSpecial() then
			return
		end
		local value = Vector2.new(input.Position.X, input.Position.Y)
		local path = stickPath
		if value.Magnitude >= ControlModeDefinitions.GamepadStickDeadzone then
			if not path then
				stickPath = { Vector2.zero }
				stickStart = os.clock()
				path = stickPath
			end
			local current = path :: { Vector2 }
			if #current < 40 and (value - current[#current]).Magnitude >= 0.08 then
				table.insert(current, value * 1.6)
			end
		elseif path then
			stickPath = nil
			options.pad.cancel()
			sendGesture({ points = path, seconds = os.clock() - stickStart, special = true })
		end
	end)

	-- While blocking, keep facing where the camera looks (so the shield points at the enemy)
	RunService.RenderStepped:Connect(function()
		if not blockHeld then
			return
		end
		local _, root = getParts()
		local camera = Workspace.CurrentCamera
		if root and camera then
			faceDirection(root, camera.CFrame.LookVector)
		end
	end)

	player.CharacterAdded:Connect(function()
		blockHeld = false
		options.pad.cancel()
	end)

	-- Touch buttons (drawn by MobileControlsController)
	options.attackButton.Activated:Connect(attack)
	options.slideButton.Activated:Connect(slide)
	options.specialButton.Activated:Connect(enterSpecial)
	options.blockButton.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			setBlock(true)
		end
	end)
	options.blockButton.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			setBlock(false)
		end
	end)

	-- Detected control scheme for the HUD
	local function schemeFor(inputType: Enum.UserInputType): Scheme?
		if inputType == Enum.UserInputType.Touch then
			return "Touch" :: Scheme
		elseif inputType.Name:sub(1, 7) == "Gamepad" then
			return "Gamepad" :: Scheme
		elseif inputType == Enum.UserInputType.Keyboard or inputType.Name:sub(1, 5) == "Mouse" then
			return "Keyboard & Mouse" :: Scheme
		end
		return nil
	end
	local current: Scheme? = nil
	local function update(inputType: Enum.UserInputType)
		local scheme = schemeFor(inputType)
		if scheme and scheme ~= current then
			current = scheme :: Scheme
			options.onSchemeChanged(scheme :: Scheme)
		end
	end
	UserInputService.LastInputTypeChanged:Connect(update)
	update(UserInputService:GetLastInputType())
	if not current then
		local fallback: Scheme = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "Touch" else "Keyboard & Mouse"
		current = fallback
		options.onSchemeChanged(fallback)
	end

	return {
		isBlockHeld = function()
			return blockHeld
		end,
		setBlock = setBlock,
		sendGesture = sendGesture,
		onModeChanged = function(_mode: string)
			-- switching modes: no block stays up, no half-drawn gesture survives
			setBlock(false)
			options.pad.cancel()
			stickPath = nil
		end,
		lastTarget = function(model: Instance?)
			engaged = model
		end,
	}
end

return InputController
