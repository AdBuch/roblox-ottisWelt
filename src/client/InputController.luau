--!strict
-- All player combat input (Classic controls, ControlModeDefinitions). The client only sends INTENT;
-- the server validates everything (state, ownership, cooldowns, charge time, targets, damage).
--   ATTACK   LMB / R2 / ATTACK button: one attack per press (tap again for the combo chain).
--            An active block is lowered first (the server does the same).
--   BLOCK    hold RMB / L2 / BLOCK button: the guard stays up while held and grows through the
--            block stages (server: BlockDefinitions); releasing lowers it. The server confirms the
--            state (Feedback.Block -> syncBlock); a guard it lowered needs a new press.
--   SPECIAL  hold Q / X / SPECIAL to charge, release to fire ("SpecialStart" / "SpecialRelease";
--            the server measures the hold time). Block may stay on while charging.
--   JUMP     Space / A / Roblox's own jump button (no second jump button).
-- Soft Targeting: an attack turns the character smoothly (at most MaxTurnDegrees) toward the enemy
-- in a cone in front with a clear line of sight and aims there; otherwise it hits straight ahead.
-- With the bow and a mouse the cursor aims instead.

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
	specialButton: TextButton,
	onSchemeChanged: (scheme: Scheme) -> (),
	onInput: (input: string) -> (), -- local feedback chips (display only)
	onChargeStart: () -> (), -- the charge display (SpecialChargeHudController)
	onChargeEnd: () -> (),
}

export type Input = {
	isBlockOn: () -> boolean,
	syncBlock: (active: boolean) -> (), -- the server's confirmed block state
	chargeEnded: () -> (), -- the server cancelled / fired the charge
	lastTarget: (model: Instance?) -> (),
}

local InputController = {}

local AIM_DISTANCE = 300

function InputController.init(options: Options): Input
	local player = Players.LocalPlayer
	local remotes = options.remotes
	local blockOn = false
	local blockInput: InputObject? = nil -- the press that holds the guard up
	local charging = false
	local engaged: Instance? = nil -- the enemy we last hit (Soft Targeting prefers it)
	local turning: RBXScriptConnection? = nil

	local function getParts(): (Humanoid?, BasePart?)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
			return humanoid, root
		end
		return nil, nil
	end

	local function equippedWeapon(): any
		return WeaponDefinitions.ById[tostring(player:GetAttribute(Config.EquippedWeaponAttribute))] or WeaponDefinitions.ById[WeaponDefinitions.Starter]
	end

	-- Turns the character toward `direction` over TurnSeconds (never a snap).
	local function turnToward(root: BasePart, direction: Vector3)
		local flat = Vector3.new(direction.X, 0, direction.Z)
		if flat.Magnitude < 0.01 then
			return
		end
		if turning then
			turning:Disconnect()
		end
		local from = root.CFrame.LookVector
		local started = os.clock()
		local seconds = ControlModeDefinitions.TurnSeconds
		turning = RunService.RenderStepped:Connect(function()
			local t = math.clamp((os.clock() - started) / seconds, 0, 1)
			local look = from:Lerp(flat.Unit, t)
			if look.Magnitude > 0.01 and root.Parent then
				root.CFrame = CFrame.lookAt(root.Position, root.Position + Vector3.new(look.X, 0, look.Z))
			end
			if t >= 1 and turning then
				turning:Disconnect()
				turning = nil
			end
		end)
	end

	local function cursorAim(root: BasePart): Vector3
		local camera = Workspace.CurrentCamera
		if not camera then
			return root.Position + root.CFrame.LookVector * 50
		end
		local mouse = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { player.Character :: Instance }
		local result = Workspace:Raycast(ray.Origin, ray.Direction * AIM_DISTANCE, params)
		return if result then result.Position else ray.Origin + ray.Direction * AIM_DISTANCE
	end

	-- Soft Targeting (presentation + aim hint; the server re-validates every target):
	-- the enemy we already fight, else the closest visible enemy inside the forward cone.
	local function softTarget(root: BasePart): BasePart?
		local basic = (SpecialMoveDefinitions :: any)[equippedWeapon().Basic]
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
					-- no targeting through walls or other obstacles
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

	-- The aim of an attack: the soft target (turning smoothly toward it), the cursor for the bow
	-- with a mouse, else straight ahead in the movement / facing direction.
	local function aimFor(root: BasePart): Vector3
		local weapon = equippedWeapon()
		if weapon.Kind == "Bow" and UserInputService.MouseEnabled and UserInputService:GetLastInputType() ~= Enum.UserInputType.Touch then
			local point = cursorAim(root)
			turnToward(root, point - root.Position)
			return point
		end
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
			turnToward(root, wanted)
			return target.Position
		end
		return root.Position + root.CFrame.LookVector * 30
	end

	local function setBlock(on: boolean)
		if blockOn == on then
			return
		end
		blockOn = on
		remotes.shieldBlock:FireServer(on)
		if on then
			options.onInput("BLK")
		end
	end

	local function pressBlock(input: InputObject)
		if not options.canAct() then
			return
		end
		blockInput = input
		setBlock(true)
	end

	local function releaseBlock(input: InputObject)
		if blockInput ~= input then
			return
		end
		blockInput = nil
		setBlock(false)
	end

	local function attack()
		if not options.canAct() or charging then
			return
		end
		local _, root = getParts()
		if not root then
			return
		end
		-- An active guard is lowered by the SERVER right before the swing (only if the attack really
		-- happens); its Feedback.Block updates the toggle, so a refused attack keeps the block on.
		remotes.combatAction:FireServer("Basic", aimFor(root))
		options.onInput("ATK")
	end

	local function startCharge()
		if charging or not options.canAct() then
			return
		end
		local _, root = getParts()
		if not root then
			return
		end
		charging = true
		remotes.combatAction:FireServer("SpecialStart")
		options.onChargeStart()
	end

	local function releaseCharge()
		if not charging then
			return
		end
		charging = false
		options.onChargeEnd()
		local _, root = getParts()
		local aim = if root then aimFor(root) else nil
		remotes.combatAction:FireServer("SpecialRelease", aim) -- firing lowers the shield (server-confirmed)
		options.onInput("SPC")
	end

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		local inputType, key = input.UserInputType, input.KeyCode
		if inputType == Enum.UserInputType.MouseButton1 or key == ControlModeDefinitions.GamepadAttack then
			attack()
		elseif inputType == Enum.UserInputType.MouseButton2 or key == ControlModeDefinitions.GamepadBlock then
			pressBlock(input)
		elseif key == ControlModeDefinitions.SpecialKey or key == ControlModeDefinitions.GamepadSpecial then
			startCharge()
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local key = input.KeyCode
		if key == ControlModeDefinitions.SpecialKey or key == ControlModeDefinitions.GamepadSpecial then
			releaseCharge()
		end
		-- every release of the holding press (also a finger that slid off the BLOCK button)
		releaseBlock(input)
	end)

	player.CharacterAdded:Connect(function()
		-- death / respawn: the server resets block and charge, so does the client
		blockOn = false
		blockInput = nil
		if charging then
			charging = false
			options.onChargeEnd()
		end
	end)

	-- Touch buttons (drawn by MobileControlsController)
	options.attackButton.Activated:Connect(attack)
	options.blockButton.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			pressBlock(input)
		end
	end)
	options.blockButton.InputEnded:Connect(releaseBlock)
	options.specialButton.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			startCharge()
		end
	end)
	options.specialButton.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			releaseCharge()
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
		isBlockOn = function()
			return blockOn
		end,
		syncBlock = function(active: boolean)
			blockOn = active
			if not active then
				blockInput = nil -- lowered by the server (attack, special, guard break): press again
			end
		end,
		chargeEnded = function()
			if charging then
				charging = false
				options.onChargeEnd()
			end
		end,
		lastTarget = function(model: Instance?)
			engaged = model
		end,
	}
end

return InputController
