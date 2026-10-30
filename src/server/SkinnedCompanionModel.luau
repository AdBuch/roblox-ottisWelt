--!strict
-- Small physics/encounter adapter around the imported, genuinely skinned Kroko asset.
local ServerStorage = game:GetService("ServerStorage")
local OttiModel = require(script.Parent.OttiModel)
local SkinnedCompanionModel = {}

function SkinnedCompanionModel.build(id: string): OttiModel.OttiRig?
	local assets = ServerStorage:FindFirstChild("HeroAssets")
	local template = assets and assets:FindFirstChild(id)
	if id ~= "Kroko" or not template or not template:IsA("Model") then return nil end
	local model = template:Clone()
	local rigRoot = model:FindFirstChild("RootPart") :: BasePart
	local body = model:FindFirstChild("Krokero_Body") :: BasePart
	local shield = model:FindFirstChild("Krokero_Shield") :: BasePart
	local club = model:FindFirstChild("Krokero_TrainingClub") :: BasePart
	assert(rigRoot and body and shield and club, "Incomplete Kroko import")
	model.Name = "Companion_Kroko"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("HeroId", "Kroko")
	model:SetAttribute("BossName", "Kroko")
	model:SetAttribute("SkinnedRig", true)
	local parts: {BasePart} = {}
	for _, item in model:GetDescendants() do
		if item:IsA("AnimationController") then item:Destroy()
		elseif item:IsA("BasePart") then
			item.Anchored = false
			item.Massless = true
			item.CanCollide = false
			item.CanTouch = false
			item.CanQuery = item:IsA("MeshPart")
			table.insert(parts, item)
		end
	end
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(3, 2, 2.5)
	root.Transparency = 1
	root.CanCollide = true
	root.CanTouch = false
	root.CFrame = rigRoot.CFrame * CFrame.new(0, 4, 0)
	root.RootPriority = 127
	root.Parent = model
	rigRoot.Size = Vector3.new(.1,.1,.1)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root; weld.Part1 = rigRoot; weld.Parent = root
	local humanoid = Instance.new("Humanoid")
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.HipHeight = 3
	humanoid.MaxHealth = 1e6; humanoid.Health = 1e6
	humanoid.WalkSpeed = 9
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Parent = model
	Instance.new("Animator").Parent = humanoid
	model.PrimaryPart = root
	local glow = Instance.new("PointLight")
	glow.Name = "GuardGlow"; glow.Enabled = false
	glow.Color = Color3.fromRGB(255,220,120); glow.Range = 10; glow.Brightness = 3
	glow.Parent = shield
	return {
		model=model, humanoid=humanoid, root=root,
		pelvis=body, chest=body, head=body, rightArm=body, leftArm=body,
		swordParts={club}, sheathedParts={}, shieldFace=shield, guardLight=glow,
		tail={segments={},motors={}}, motors={}, bodyParts=parts,
	}
end
return SkinnedCompanionModel
