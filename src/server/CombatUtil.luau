--!strict
-- Small server-side helpers for distance, facing and line-of-sight checks.

local Workspace = game:GetService("Workspace")

local CombatUtil = {}

function CombatUtil.flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function CombatUtil.flatDistance(a: Vector3, b: Vector3): number
	return CombatUtil.flat(a - b).Magnitude
end

-- True if targetPosition lies inside the cone given by minDot in front of cframe (height ignored).
function CombatUtil.isFacing(cframe: CFrame, targetPosition: Vector3, minDot: number): boolean
	local toTarget = CombatUtil.flat(targetPosition - cframe.Position)
	local look = CombatUtil.flat(cframe.LookVector)
	if toTarget.Magnitude < 0.01 or look.Magnitude < 0.01 then
		return true
	end
	return look.Unit:Dot(toTarget.Unit) >= minDot
end

-- True if no solid (CanCollide) part lies between the two points, ignoring the given instances.
function CombatUtil.hasLineOfSight(from: Vector3, to: Vector3, ignore: { Instance }): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	return Workspace:Raycast(from, to - from, params) == nil
end

-- Returns the character, humanoid and root only while the character is alive.
function CombatUtil.getLivingCharacter(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root
end

return CombatUtil
