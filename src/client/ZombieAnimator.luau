--!strict
-- Client-only walk cycle for the zombie: swings legs and the shield arm based on how fast
-- it moves. Uses Motor6D.Transform, so it never fights the server's attack pose (C0).

local RunService = game:GetService("RunService")

local ZombieAnimator = {}

local STRIDE_SPEED = 0.9
local LEG_SWING = math.rad(35)
local ARM_SWING = math.rad(15)

local function getMotor(parent: Instance?, name: string): Motor6D?
	local joint = parent and parent:FindFirstChild(name)
	if joint and joint:IsA("Motor6D") then
		return joint
	end
	return nil
end

function ZombieAnimator.start(arena: Instance, zombieName: string)
	local phase = 0

	RunService.Stepped:Connect(function(_time: number, dt: number)
		local zombie = arena:FindFirstChild(zombieName)
		local root = zombie and zombie:FindFirstChild("HumanoidRootPart")
		local torso = zombie and zombie:FindFirstChild("Torso")
		if not root or not root:IsA("BasePart") then
			return
		end

		local velocity = root.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local amount = math.clamp(speed / 12, 0, 1)
		phase += dt * speed * STRIDE_SPEED
		local swing = math.sin(phase) * amount

		local rightHip = getMotor(torso, "RightHip")
		local leftHip = getMotor(torso, "LeftHip")
		local leftShoulder = getMotor(torso, "LeftShoulder")
		if rightHip then
			rightHip.Transform = CFrame.Angles(swing * LEG_SWING, 0, 0)
		end
		if leftHip then
			leftHip.Transform = CFrame.Angles(-swing * LEG_SWING, 0, 0)
		end
		if leftShoulder then
			leftShoulder.Transform = CFrame.Angles(swing * ARM_SWING, 0, 0)
		end
	end)
end

return ZombieAnimator
