--!strict
-- All player combat input. The client only sends INTENT (action + aim point); the server
-- validates everything (state, ownership, cooldowns, combos, targets, damage).
--   Keyboard/mouse : LMB attack · RMB hold to block · Q Special 1 · E Special 2
--   Gamepad        : R2 attack · L2 hold to block · X Special 1 · Y Special 2
--   Touch          : ATK · hold BLOCK · the two special buttons (MobileControlsController)
-- For intuitive aiming the character turns toward the cursor before an action and keeps
-- facing the camera direction while blocking. Interaction prompts use F (gamepad D-pad up).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

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
	special1Button: TextButton,
	special2Button: TextButton,
	onSchemeChanged: (scheme: Scheme) -> (),
}

local InputController = {}

local AIM_DISTANCE = 300

function InputController.init(options: Options): { isBlockHeld: () -> boolean }
	local player = Players.LocalPlayer
	local remotes = options.remotes
	local blockHeld = false

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

	local function aimPoint(root: BasePart): Vector3
		local camera = Workspace.CurrentCamera
		if not camera then
			return root.Position + root.CFrame.LookVector * 50
		end
		local ray: Ray
		if UserInputService.MouseEnabled and UserInputService:GetLastInputType() ~= Enum.UserInputType.Gamepad1 then
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

	local function act(action: "Basic" | "Special1" | "Special2")
		if not options.canAct() then
			return
		end
		if action == "Basic" and blockHeld then
			return -- basic attacks while blocking are ignored
		end
		local _, root = getParts()
		if not root then
			return
		end
		local point = aimPoint(root)
		faceDirection(root, point - root.Position)
		remotes.combatAction:FireServer(action, point)
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
	end

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		local inputType, key = input.UserInputType, input.KeyCode
		if inputType == Enum.UserInputType.MouseButton1 or key == Enum.KeyCode.ButtonR2 then
			act("Basic")
		elseif inputType == Enum.UserInputType.MouseButton2 or key == Enum.KeyCode.ButtonL2 then
			setBlock(true)
		elseif key == Enum.KeyCode.Q or key == Enum.KeyCode.ButtonX then
			act("Special1")
		elseif key == Enum.KeyCode.E or key == Enum.KeyCode.ButtonY then
			act("Special2")
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.ButtonL2 then
			setBlock(false)
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
	end)

	-- The special cards on the HUD double as touch buttons
	options.special1Button.Activated:Connect(function()
		act("Special1")
	end)
	options.special2Button.Activated:Connect(function()
		act("Special2")
	end)

	-- Touch: ATTACK and hold-BLOCK buttons (drawn by MobileControlsController)
	options.attackButton.Activated:Connect(function()
		act("Basic")
	end)
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
	}
end

return InputController
