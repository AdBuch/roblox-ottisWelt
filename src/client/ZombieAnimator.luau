--!strict
-- Client-only walk cycle for every living zombie (found via the CollectionService tag):
-- swings legs and the off-hand arm based on how fast each zombie moves. Uses
-- Motor6D.Transform, so it never fights the server's attack pose (which changes C0).

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local ZombieAnimator = {}

local STRIDE_SPEED = 0.9
local LEG_SWING = math.rad(35)
local ARM_SWING = math.rad(15)

type Joints = {
	root: BasePart,
	rightHip: Motor6D?,
	leftHip: Motor6D?,
	leftShoulder: Motor6D?,
	phase: number,
}

local function getMotor(parent: Instance?, name: string): Motor6D?
	local joint = parent and parent:FindFirstChild(name)
	if joint and joint:IsA("Motor6D") then
		return joint
	end
	return nil
end

function ZombieAnimator.start(tag: string)
	local cache: { [Instance]: Joints } = setmetatable({}, { __mode = "k" }) :: any

	local function getJoints(model: Instance): Joints?
		local joints = cache[model]
		if joints and joints.root.Parent then
			return joints
		end
		local root = model:FindFirstChild("HumanoidRootPart")
		local torso = model:FindFirstChild("Torso")
		if not root or not root:IsA("BasePart") or not torso then
			return nil
		end
		local created: Joints = {
			root = root,
			rightHip = getMotor(torso, "RightHip"),
			leftHip = getMotor(torso, "LeftHip"),
			leftShoulder = getMotor(torso, "LeftShoulder"),
			phase = math.random() * math.pi,
		}
		cache[model] = created
		return created
	end

	RunService.Stepped:Connect(function(_time: number, dt: number)
		for _, model in CollectionService:GetTagged(tag) do
			local joints = getJoints(model)
			if joints then
				local velocity = joints.root.AssemblyLinearVelocity
				local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
				local amount = math.clamp(speed / 12, 0, 1)
				joints.phase += dt * speed * STRIDE_SPEED
				local swing = math.sin(joints.phase) * amount
				if joints.rightHip then
					joints.rightHip.Transform = CFrame.Angles(swing * LEG_SWING, 0, 0)
				end
				if joints.leftHip then
					joints.leftHip.Transform = CFrame.Angles(-swing * LEG_SWING, 0, 0)
				end
				if joints.leftShoulder then
					joints.leftShoulder.Transform = CFrame.Angles(swing * ARM_SWING, 0, 0)
				end
			end
		end
	end)
end

return ZombieAnimator
