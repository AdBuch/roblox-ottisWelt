--!strict
-- Minimal shared physics/encounter adapter; character anatomy lives in the skinned asset.
local ServerStorage = game:GetService("ServerStorage")
local HeroRigTypes = require(script.Parent.HeroRigTypes)
local SkinnedCompanionModel = {}
local PROFILES = {
	Kroko = {body="Krokero_Body", guard="Krokero_Shield", weapon="Krokero_TrainingClub", height=4, width=3},
	Schili = {body="Schili_Body", guard="Schili_Shell", weapon="Schili_Staff", height=2.6, width=2.3},
	Otti = {body="Otti_Body", guard="Otti_Shield", weapon="Otti_Sword", height=3.4, width=2.7},
}

function SkinnedCompanionModel.build(id: string): HeroRigTypes.OttiRig?
	local assets = ServerStorage:FindFirstChild("HeroAssets")
	local template = assets and assets:FindFirstChild(id)
	local profile = (PROFILES :: any)[id]
	if not profile or not template or not template:IsA("Model") then return nil end
	local model = template:Clone()
	local rigRoot = model:FindFirstChild("RootPart") :: BasePart
	local body = model:FindFirstChild(profile.body) :: BasePart
	local shield = model:FindFirstChild(profile.guard) :: BasePart
	local club = model:FindFirstChild(profile.weapon) :: BasePart
	assert(rigRoot and body and shield and club, "Incomplete skinned hero import: " .. id)
	model.Name = if id == "Otti" then "OttiTheGladiator" else "Companion_" .. id
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("HeroId", id)
	model:SetAttribute("BossName", id)
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
	root.Size = Vector3.new(profile.width, 2, 2.5)
	root.Transparency = 1
	root.CanCollide = true
	root.CanTouch = false
	root.CFrame = rigRoot.CFrame * CFrame.new(0, profile.height, 0)
	root.RootPriority = 127
	root.Parent = model
	rigRoot.Size = Vector3.new(.1,.1,.1)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root; weld.Part1 = rigRoot; weld.Parent = root
	local humanoid = Instance.new("Humanoid")
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.HipHeight = profile.height - 1
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
	local sheathed = model:FindFirstChild("Otti_Sheathed")
	if sheathed and sheathed:IsA("BasePart") then sheathed.Transparency = 1 end
	local drawnParts={club}
	if id=="Otti" then
		for _,name in {"Otti_Trident","Otti_NetHeld"} do
			local part=model:FindFirstChild(name)
			if part and part:IsA("BasePart") then table.insert(drawnParts,part) end
		end
		model:SetAttribute("SwordDrawn",true)
		require(script.Parent.OttiEquipment).select(model,"Retiarius")
	end
	return {
		model=model, humanoid=humanoid, root=root,
		pelvis=body, chest=body, head=body, rightArm=body, leftArm=body,
		swordParts=drawnParts, sheathedParts=if sheathed and sheathed:IsA("BasePart") then {sheathed} else {}, shieldFace=shield, guardLight=glow,
		tail={segments={},motors={}}, motors={}, bodyParts=parts,
	}
end
return SkinnedCompanionModel
