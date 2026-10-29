--!strict
-- Shared articulated limbs. Keeps the existing shoulder/hip sockets and accessory positions;
-- weapons, paws and bracers follow the lower limb instead of remaining on a rigid arm.
local HeroSkeleton = {}

function HeroSkeleton.articulate(model: Model, motors: { [string]: Motor6D }, parts: { BasePart })
	for _, limbName in { "RightArm", "LeftArm", "RightLeg", "LeftLeg" } do
		local upper = model:FindFirstChild(limbName) :: BasePart
		local arm = string.find(limbName, "Arm") ~= nil
		local side = if string.find(limbName, "Right") then "Right" else "Left"
		local socket = motors[side .. (if arm then "Shoulder" else "Hip")]
		local rest, size = upper.CFrame, upper.Size
		local jointWorld = rest * socket.C1
		local lower = upper:Clone()
		lower:ClearAllChildren()
		-- Clone only the primitive shape; the motor graph is built explicitly below.
		local mesh = upper:FindFirstChildOfClass("SpecialMesh")
		if mesh then mesh:Clone().Parent = lower end
		lower.Name = side .. (if arm then "Forearm" else "Shin")
		upper.Size = Vector3.new(size.X, size.Y * 0.55, size.Z)
		upper.CFrame = rest * CFrame.new(0, size.Y * 0.225, 0)
		socket.C1 = upper.CFrame:ToObjectSpace(jointWorld)
		lower.Size = Vector3.new(size.X * 0.95, size.Y * 0.55, size.Z * 0.95)
		lower.CFrame = rest * CFrame.new(0, -size.Y * 0.225, 0)
		lower.Parent = model
		table.insert(parts, lower)
		for _, child in model:GetDescendants() do
			if child:IsA("Weld") and child.Part0 == upper and child.Part1 then
				local attachment = child.Part1
				child.Part0 = if rest:PointToObjectSpace(attachment.Position).Y < 0 then lower else upper
				child.C0 = (child.Part0 :: BasePart).CFrame:ToObjectSpace(attachment.CFrame) * child.C1
			end
		end
		local joint = Instance.new("Motor6D")
		joint.Name = side .. (if arm then "Elbow" else "Knee")
		joint.Part0, joint.Part1 = upper, lower
		joint.C0 = upper.CFrame:ToObjectSpace(rest)
		joint.C1 = lower.CFrame:ToObjectSpace(rest)
		joint.Parent = upper
		motors[joint.Name] = joint
	end
	model:SetAttribute("HeroRigVersion", 2)
end

return HeroSkeleton
