--!strict
-- Local camera for Otti's entrance (display only; the server runs the entrance regardless):
-- when Otti rises in the imperial box the camera looks up at him, follows his leap into the arena
-- and returns to normal right after the landing. A small, distance-based shake marks the landing.
-- Players who already saw the entrance this session may skip the camera part; skipping never
-- changes anything on the server. Movement stays possible the whole time.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local OttiEntranceConfig = require(Shared:WaitForChild("OttiEntranceConfig"))

export type Entrance = {
	skip: () -> (),
	canSkip: () -> boolean,
}

local OttiEntranceController = {}

function OttiEntranceController.start(arena: Instance): Entrance
	local player = Players.LocalPlayer
	local active = false
	local token = 0
	local seenBefore = false
	local connection: RBXScriptConnection? = nil

	local function restore()
		token += 1
		active = false
		if connection then
			connection:Disconnect()
			connection = nil
		end
		local camera = Workspace.CurrentCamera
		if camera then
			camera.CameraType = Enum.CameraType.Custom
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				camera.CameraSubject = humanoid
			end
		end
	end

	local function ottiRoot(): BasePart?
		for _, tag in { Config.OttiTag, Config.OttiSpectatorTag } do
			for _, model in CollectionService:GetTagged(tag) do
				local root = model:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					return root
				end
			end
		end
		return nil
	end

	local function begin()
		local location = player:GetAttribute("Location")
		if active or (location ~= "Arena" and location ~= "Tribune") then
			return
		end
		local camera = Workspace.CurrentCamera
		local root = ottiRoot()
		if not camera or not root then
			return
		end
		active = true
		token += 1
		local myToken = token
		camera.CameraType = Enum.CameraType.Scriptable
		-- Watch from the sand in front of the box, slightly to the side
		local boxFront = root.Position
		local eye = Vector3.new(boxFront.X * 0.4 + 14, 8, boxFront.Z * 0.35)
		local current = camera.CFrame
		connection = RunService.RenderStepped:Connect(function(dt: number)
			local target = ottiRoot()
			if not target or token ~= myToken then
				return
			end
			local goal = CFrame.lookAt(eye, target.Position + Vector3.new(0, 2, 0))
			current = current:Lerp(goal, math.min(1, dt * 4))
			camera.CFrame = current
		end)
		task.delay(OttiEntranceConfig.CameraSeconds + 2.5, function()
			if token == myToken then
				restore() -- safety net: the normal camera always comes back
			end
		end)
	end

	arena:GetAttributeChangedSignal(Config.BossIntroAttribute):Connect(function()
		local stage = arena:GetAttribute(Config.BossIntroAttribute)
		if stage == "Rise" then
			begin()
		elseif stage == "" and active then
			restore()
			seenBefore = true
		end
	end)

	-- Landing shake (stronger nearby), then the camera returns
	arena:GetAttributeChangedSignal(Config.BossLandingAttribute):Connect(function()
		local position = arena:GetAttribute("BossLandPosition")
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if typeof(position) ~= "Vector3" or not humanoid or not root or not root:IsA("BasePart") then
			return
		end
		local strength = math.clamp(1 - (root.Position - position).Magnitude / 80, 0.15, 1) * 0.6
		task.spawn(function()
			for i = 1, 8 do
				humanoid.CameraOffset = Vector3.new(math.random(-10, 10) / 10, math.random(-10, 10) / 10, 0) * strength * (1 - i / 9)
				task.wait(0.03)
			end
			humanoid.CameraOffset = Vector3.zero
		end)
		task.delay(0.8, function()
			if active then
				restore()
				seenBefore = true
			end
		end)
	end)

	player.CharacterAdded:Connect(function()
		if active then
			restore()
		end
	end)

	return {
		skip = function()
			if active then
				restore()
			end
		end,
		canSkip = function()
			return active and player:GetAttribute(Config.IntroSeenAttribute) == true and seenBefore
		end,
	}
end

return OttiEntranceController
