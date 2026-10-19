--!strict
-- Plays an approved combat slide on the OWN character (Feedback.Slide: direction, distance,
-- duration). The server decides whether a slide happens (state, cooldown, distance sanity) and
-- publishes SlideStart/SlideLength for everyone; this only moves the local character because the
-- client owns its physics. No BodyVelocity, no upward velocity, no launching from slopes:
--   * the Humanoid walks the slide direction at the slide speed (WalkSpeed is restored afterwards)
--   * a short raycast ahead stops the slide at walls, barriers, gates and solid enemies
--   * the input only bends the path slightly (SlideDefinitions.Steering)
--   * the camera lowers for the slide (Humanoid.CameraOffset), then returns

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local SlideDefinitions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SlideDefinitions"))

local SlideController = {}

local STOP_DISTANCE = 1.8 -- how far ahead a wall stops the slide
local MAX_SPEED = 60

local sliding = false

function SlideController.isSliding(): boolean
	return sliding
end

-- direction: horizontal unit vector chosen by the server from the aim / movement at the start.
function SlideController.play(player: Player, direction: Vector3, distance: number, duration: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or not root or not root:IsA("BasePart") or humanoid.Health <= 0 then
		return
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.01 then
		return
	end
	flat = flat.Unit
	local seconds = math.max(0.1, duration)
	local speed = math.min(MAX_SPEED, math.max(distance, 1) / seconds)
	local savedSpeed = humanoid.WalkSpeed
	local savedOffset = humanoid.CameraOffset
	local started = os.clock()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	sliding = true
	humanoid.WalkSpeed = speed
	local connection: RBXScriptConnection? = nil
	local function finish()
		if connection then
			connection:Disconnect()
			connection = nil
		end
		sliding = false
		if humanoid.Parent then
			humanoid:Move(Vector3.zero)
			humanoid.WalkSpeed = savedSpeed
			humanoid.CameraOffset = savedOffset
		end
	end
	connection = RunService.RenderStepped:Connect(function()
		local t = (os.clock() - started) / seconds
		if t >= 1 or humanoid.Health <= 0 or humanoid.Parent ~= character then
			finish()
			return
		end
		-- steering: the player's input bends the path only slightly
		local input = Vector3.new(humanoid.MoveDirection.X, 0, humanoid.MoveDirection.Z)
		local heading = flat:Lerp(input, SlideDefinitions.Steering)
		if heading.Magnitude > 0.01 then
			heading = heading.Unit
		else
			heading = flat
		end
		-- walls and solid obstacles at knee height stop the slide
		local origin = root.Position - Vector3.new(0, root.Size.Y * 0.2, 0)
		local hit = Workspace:Raycast(origin, heading * STOP_DISTANCE, params)
		if hit and hit.Normal.Y < 0.5 then
			finish()
			return
		end
		humanoid:Move(heading, false)
		-- the camera dips a little while sliding (purely visual)
		local dip = math.sin(math.pi * math.clamp(t, 0, 1))
		humanoid.CameraOffset = Vector3.new(0, -SlideDefinitions.CameraLower * dip, 0)
	end)
	-- Safety: a connection that never fires must not leave the speed changed
	task.delay(seconds + 0.5, function()
		if connection then
			finish()
		end
	end)
end

return SlideController
