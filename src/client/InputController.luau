--!strict
-- Player input: LMB attacks (melee or bow), RMB held blocks; on touch devices ATTACK / BLOCK
-- buttons. The client only sends requests (plus an aim point for the bow, which the server
-- validates). For intuitive aiming it turns the character toward the cursor before an attack
-- and keeps it facing the camera direction while blocking.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

type Remotes = {
	weaponAttack: RemoteEvent,
	shieldBlock: RemoteEvent,
}

local InputController = {}

local AIM_DISTANCE = 300

function InputController.init(remotes: Remotes, canFight: () -> boolean): { isBlockHeld: () -> boolean }
	local player = Players.LocalPlayer
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

	-- The point the player aims at: under the mouse, or straight ahead of the camera.
	local function aimPoint(root: BasePart): Vector3
		local camera = Workspace.CurrentCamera
		if not camera then
			return root.Position + root.CFrame.LookVector * 50
		end
		local ray: Ray
		if UserInputService.MouseEnabled then
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

	local function attack()
		if blockHeld or not canFight() then
			return -- attacking while blocking (or outside the arena) is ignored
		end
		local _, root = getParts()
		if not root then
			return
		end
		local point = aimPoint(root)
		faceDirection(root, point - root.Position)
		remotes.weaponAttack:FireServer(point)
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
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			attack()
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			setBlock(true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
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

	-- Touch fallback
	if UserInputService.TouchEnabled then
		local gui = Instance.new("ScreenGui")
		gui.Name = "OttiArenaTouchControls"
		gui.ResetOnSpawn = false

		local function makeButton(name: string, text: string, position: UDim2, color: Color3): TextButton
			local button = Instance.new("TextButton")
			button.Name = name
			button.Text = text
			button.AnchorPoint = Vector2.new(1, 1)
			button.Position = position
			button.Size = UDim2.fromOffset(96, 96)
			button.BackgroundColor3 = color
			button.BackgroundTransparency = 0.2
			button.Font = Enum.Font.GothamBold
			button.TextSize = 16
			button.TextColor3 = Color3.new(1, 1, 1)
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(1, 0)
			corner.Parent = button
			button.Parent = gui
			return button
		end

		local attackButton = makeButton("Attack", "ATTACK", UDim2.new(1, -130, 1, -150), Color3.fromRGB(170, 60, 40))
		local blockButton = makeButton("Block", "BLOCK", UDim2.new(1, -240, 1, -100), Color3.fromRGB(40, 90, 160))
		attackButton.Activated:Connect(attack)
		blockButton.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				setBlock(true)
			end
		end)
		blockButton.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				setBlock(false)
			end
		end)
		gui.Parent = player:WaitForChild("PlayerGui")
	end

	return {
		isBlockHeld = function()
			return blockHeld
		end,
	}
end

return InputController
