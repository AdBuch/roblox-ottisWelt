--!strict
-- Builds the Roman gladiator zombie rig from plain Parts: a Humanoid, a HumanoidRootPart
-- and Motor6D joints (so it can walk with PathfindingService and pose procedurally).
-- All coordinates below are in rest pose with the feet at y = 0, facing -Z.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatConfig = require(ReplicatedStorage.Shared.CombatConfig)

local SKIN = Color3.fromRGB(112, 146, 84) -- moss green
local SKIN_DARK = Color3.fromRGB(84, 112, 62)
local EYES = Color3.fromRGB(255, 176, 40) -- glowing amber
local BRONZE = Color3.fromRGB(176, 125, 60)
local BRONZE_DARK = Color3.fromRGB(128, 88, 42)
local CRACK = Color3.fromRGB(52, 38, 24)
local CREST = Color3.fromRGB(110, 20, 26)
local CLOTH = Color3.fromRGB(120, 26, 30)
local LEATHER = Color3.fromRGB(104, 66, 38)
local LEATHER_DARK = Color3.fromRGB(74, 46, 26)
local SHIELD_WOOD = Color3.fromRGB(128, 44, 32)
local STEEL = Color3.fromRGB(186, 186, 180)
local MOUTH = Color3.fromRGB(40, 28, 24)
local TEETH = Color3.fromRGB(232, 222, 196)

export type ZombieRig = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	torso: BasePart,
	rightShoulder: Motor6D,
	rightShoulderRest: CFrame,
	highlight: Highlight,
	hitSparks: ParticleEmitter,
	nameLabel: TextLabel,
}

local ZombieModel = {}

local function newPart(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.CanCollide = false
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function weldTo(limb: BasePart, part: BasePart)
	local weld = Instance.new("Weld")
	weld.Part0 = limb
	weld.Part1 = part
	weld.C0 = limb.CFrame:Inverse() * part.CFrame
	weld.Parent = part
end

local function motor(name: string, part0: BasePart, part1: BasePart, jointPosition: Vector3): Motor6D
	local joint = Instance.new("Motor6D")
	joint.Name = name
	joint.Part0 = part0
	joint.Part1 = part1
	joint.C0 = part0.CFrame:Inverse() * CFrame.new(jointPosition)
	joint.C1 = part1.CFrame:Inverse() * CFrame.new(jointPosition)
	joint.Parent = part0
	return joint
end

function ZombieModel.build(): ZombieRig
	local model = Instance.new("Model")
	model.Name = CombatConfig.ZombieName
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	-- Accessory helper: creates a part in rest pose and welds it to a limb.
	local function add(limb: BasePart, name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material, rotation: CFrame?): Part
		local part = newPart(name, size, CFrame.new(position) * (rotation or CFrame.identity), color, material, model)
		weldTo(limb, part)
		return part
	end

	-- Body (chunky proportions)
	local root = newPart("HumanoidRootPart", Vector3.new(2, 2, 1), CFrame.new(0, 3.4, 0), SKIN, Enum.Material.SmoothPlastic, model)
	root.Transparency = 1
	root.CanCollide = true
	root.Massless = false

	local torso = newPart("Torso", Vector3.new(2.4, 2.2, 1.3), CFrame.new(0, 3.6, 0), SKIN, Enum.Material.SmoothPlastic, model)
	local head = newPart("Head", Vector3.new(1.9, 1.8, 1.7), CFrame.new(0, 5.6, 0), SKIN, Enum.Material.SmoothPlastic, model)
	local rightArm = newPart("RightArm", Vector3.new(1, 2.3, 1), CFrame.new(1.7, 3.35, 0), SKIN, Enum.Material.SmoothPlastic, model)
	local leftArm = newPart("LeftArm", Vector3.new(1, 2.3, 1), CFrame.new(-1.7, 3.35, 0), SKIN, Enum.Material.SmoothPlastic, model)
	local rightLeg = newPart("RightLeg", Vector3.new(1.1, 2.5, 1.1), CFrame.new(0.6, 1.25, 0), SKIN, Enum.Material.SmoothPlastic, model)
	local leftLeg = newPart("LeftLeg", Vector3.new(1.1, 2.5, 1.1), CFrame.new(-0.6, 1.25, 0), SKIN, Enum.Material.SmoothPlastic, model)

	motor("RootJoint", root, torso, Vector3.new(0, 3.4, 0))
	motor("Neck", torso, head, Vector3.new(0, 4.7, 0))
	local rightShoulder = motor("RightShoulder", torso, rightArm, Vector3.new(1.7, 4.4, 0))
	motor("LeftShoulder", torso, leftArm, Vector3.new(-1.7, 4.4, 0))
	motor("RightHip", torso, rightLeg, Vector3.new(0.6, 2.5, 0))
	motor("LeftHip", torso, leftLeg, Vector3.new(-0.6, 2.5, 0))

	-- Face: amber eyes, angry brows, toothy (friendly) grin
	for _, side in { -1, 1 } do
		add(head, "Eye", Vector3.new(0.38, 0.26, 0.1), Vector3.new(side * 0.42, 5.75, -0.86), EYES, Enum.Material.Neon)
		add(head, "Brow", Vector3.new(0.6, 0.16, 0.1), Vector3.new(side * 0.42, 6.0, -0.88), SKIN_DARK, Enum.Material.SmoothPlastic, CFrame.Angles(0, 0, side * math.rad(18)))
	end
	add(head, "Mouth", Vector3.new(0.95, 0.24, 0.1), Vector3.new(0, 5.12, -0.86), MOUTH, Enum.Material.SmoothPlastic)
	for _, x in { -0.3, 0, 0.3 } do
		add(head, "Tooth", Vector3.new(0.16, 0.14, 0.06), Vector3.new(x, 5.18, -0.92), TEETH, Enum.Material.SmoothPlastic)
	end
	local eyeGlow = Instance.new("PointLight")
	eyeGlow.Color = EYES
	eyeGlow.Range = 6
	eyeGlow.Brightness = 1.5
	eyeGlow.Parent = head

	-- Cracked bronze gladiator helmet (Corinthian style) with a short crest
	local metal = Enum.Material.CorrodedMetal
	add(head, "HelmetCap", Vector3.new(2.1, 0.7, 1.95), Vector3.new(0, 6.45, 0.02), BRONZE, metal)
	add(head, "HelmetBrow", Vector3.new(2.1, 0.3, 0.15), Vector3.new(0, 6.05, -0.92), BRONZE_DARK, metal)
	add(head, "HelmetBack", Vector3.new(2.1, 1.3, 0.15), Vector3.new(0, 5.8, 0.92), BRONZE, metal)
	add(head, "NoseGuard", Vector3.new(0.25, 0.55, 0.15), Vector3.new(0, 5.75, -0.97), BRONZE_DARK, metal)
	for _, side in { -1, 1 } do
		add(head, "HelmetSide", Vector3.new(0.15, 1.3, 1.75), Vector3.new(side * 1.02, 5.8, 0), BRONZE, metal)
		add(head, "CheekGuard", Vector3.new(0.35, 1.0, 0.7), Vector3.new(side * 0.85, 5.5, -0.7), BRONZE, metal)
	end
	add(head, "Crack", Vector3.new(0.06, 0.5, 0.04), Vector3.new(0.55, 6.4, -0.97), CRACK, Enum.Material.SmoothPlastic, CFrame.Angles(0, 0, math.rad(30)))
	add(head, "Crack", Vector3.new(0.06, 0.35, 0.04), Vector3.new(0.68, 6.22, -0.97), CRACK, Enum.Material.SmoothPlastic, CFrame.Angles(0, 0, math.rad(-25)))
	add(head, "Crack", Vector3.new(0.06, 0.45, 0.04), Vector3.new(-0.85, 5.35, -1.06), CRACK, Enum.Material.SmoothPlastic, CFrame.Angles(0, 0, math.rad(-20)))
	add(head, "Crest", Vector3.new(0.35, 0.55, 1.7), Vector3.new(0, 7.05, 0.05), CREST, Enum.Material.Fabric)

	-- Torso: tattered scarf, leather strap, belt with bronze buckle
	add(torso, "Scarf", Vector3.new(2.5, 0.4, 1.5), Vector3.new(0, 4.6, 0), CLOTH, Enum.Material.Fabric)
	add(torso, "ScarfTail", Vector3.new(0.7, 0.6, 0.1), Vector3.new(-0.4, 4.2, -0.7), CLOTH, Enum.Material.Fabric, CFrame.Angles(0, 0, math.rad(12)))
	add(torso, "Strap", Vector3.new(0.35, 2.7, 0.08), Vector3.new(0, 3.75, -0.68), LEATHER, Enum.Material.Leather, CFrame.Angles(0, 0, math.rad(40)))
	add(torso, "Belt", Vector3.new(2.55, 0.45, 1.45), Vector3.new(0, 2.75, 0), LEATHER_DARK, Enum.Material.Leather)
	local buckle = add(torso, "Buckle", Vector3.new(0.15, 0.65, 0.65), Vector3.new(0, 2.75, -0.75), BRONZE, metal, CFrame.Angles(0, math.rad(90), 0))
	buckle.Shape = Enum.PartType.Cylinder

	-- Gladiator skirt: red cloth with leather strips and bronze studs
	add(torso, "SkirtCloth", Vector3.new(2.45, 0.8, 1.35), Vector3.new(0, 2.2, 0), CLOTH, Enum.Material.Fabric)
	for _, x in { -0.9, -0.3, 0.3, 0.9 } do
		add(torso, "Strip", Vector3.new(0.5, 1.1, 0.12), Vector3.new(x, 2.0, -0.74), LEATHER, Enum.Material.Leather)
		add(torso, "Stud", Vector3.new(0.18, 0.18, 0.06), Vector3.new(x, 1.7, -0.82), BRONZE, Enum.Material.Metal)
		add(torso, "Strip", Vector3.new(0.5, 1.1, 0.12), Vector3.new(x, 2.0, 0.74), LEATHER, Enum.Material.Leather)
	end
	for _, side in { -1, 1 } do
		add(torso, "Strip", Vector3.new(0.12, 1.1, 0.5), Vector3.new(side * 1.28, 2.0, 0), LEATHER, Enum.Material.Leather)
	end

	-- Right (sword) arm: one bronze shoulder guard, bracer, short sword
	add(rightArm, "ShoulderGuard", Vector3.new(1.4, 0.4, 1.4), Vector3.new(1.85, 4.55, 0), BRONZE, metal, CFrame.Angles(0, 0, math.rad(-20)))
	add(rightArm, "ShoulderGuard", Vector3.new(1.25, 0.32, 1.3), Vector3.new(2.1, 4.2, 0), BRONZE_DARK, metal, CFrame.Angles(0, 0, math.rad(-32)))
	local rivet = add(rightArm, "Rivet", Vector3.new(0.3, 0.3, 0.3), Vector3.new(1.75, 4.8, -0.45), BRONZE, Enum.Material.Metal)
	rivet.Shape = Enum.PartType.Ball
	add(rightArm, "Bracer", Vector3.new(1.1, 0.7, 1.1), Vector3.new(1.7, 2.65, 0), LEATHER, Enum.Material.Leather)
	add(rightArm, "SwordGrip", Vector3.new(0.3, 0.3, 0.9), Vector3.new(1.7, 2.35, -0.15), LEATHER_DARK, Enum.Material.Leather)
	local pommel = add(rightArm, "SwordPommel", Vector3.new(0.4, 0.4, 0.4), Vector3.new(1.7, 2.35, 0.4), BRONZE, Enum.Material.Metal)
	pommel.Shape = Enum.PartType.Ball
	add(rightArm, "SwordGuard", Vector3.new(0.9, 0.22, 0.22), Vector3.new(1.7, 2.35, -0.65), BRONZE, Enum.Material.Metal)
	add(rightArm, "SwordBlade", Vector3.new(0.14, 0.42, 2.1), Vector3.new(1.7, 2.35, -1.8), STEEL, Enum.Material.Metal)
	add(rightArm, "SwordTip", Vector3.new(0.14, 0.3, 0.3), Vector3.new(1.7, 2.35, -2.95), STEEL, Enum.Material.Metal, CFrame.Angles(math.rad(45), 0, 0))

	-- Left (shield) arm: bracer and a small round red/brown wooden shield
	add(leftArm, "Bracer", Vector3.new(1.1, 0.7, 1.1), Vector3.new(-1.7, 2.65, 0), LEATHER, Enum.Material.Leather)
	local rim = add(leftArm, "ShieldRim", Vector3.new(0.2, 2.7, 2.7), Vector3.new(-1.8, 3.0, -0.75), BRONZE, metal, CFrame.Angles(0, math.rad(90), 0))
	rim.Shape = Enum.PartType.Cylinder
	local wood = add(leftArm, "ShieldWood", Vector3.new(0.25, 2.35, 2.35), Vector3.new(-1.8, 3.0, -0.82), SHIELD_WOOD, Enum.Material.WoodPlanks, CFrame.Angles(0, math.rad(90), 0))
	wood.Shape = Enum.PartType.Cylinder
	local boss = add(leftArm, "ShieldBoss", Vector3.new(0.75, 0.75, 0.75), Vector3.new(-1.8, 3.0, -0.95), BRONZE, Enum.Material.Metal)
	boss.Shape = Enum.PartType.Ball

	-- Legs: bronze greaves, leather sandals, green toes
	for _, leg in { leftLeg, rightLeg } do
		local x = leg.Position.X
		add(leg, "Greave", Vector3.new(0.95, 1.1, 0.22), Vector3.new(x, 0.95, -0.6), BRONZE, metal)
		add(leg, "KneeGuard", Vector3.new(1.05, 0.35, 0.28), Vector3.new(x, 1.6, -0.62), BRONZE_DARK, metal)
		add(leg, "Sole", Vector3.new(1.25, 0.25, 1.55), Vector3.new(x, 0.125, -0.2), LEATHER_DARK, Enum.Material.Leather)
		add(leg, "Toes", Vector3.new(1.0, 0.3, 0.35), Vector3.new(x, 0.4, -0.75), SKIN, Enum.Material.SmoothPlastic)
		add(leg, "SandalStrap", Vector3.new(1.18, 0.15, 1.18), Vector3.new(x, 0.65, 0), LEATHER, Enum.Material.Leather)
		add(leg, "SandalStrap", Vector3.new(1.18, 0.15, 1.18), Vector3.new(x, 0.25, 0), LEATHER, Enum.Material.Leather)
	end

	-- Humanoid (R15 rules: HipHeight = ground to bottom of the root part)
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = 2.4
	humanoid.MaxHealth = CombatConfig.ZombieMaxHealth
	humanoid.Health = CombatConfig.ZombieMaxHealth
	humanoid.WalkSpeed = CombatConfig.ZombieWalkSpeed
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	humanoid.Parent = model
	model.PrimaryPart = root

	-- Hit feedback
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.new(1, 1, 1)
	highlight.FillTransparency = 0.1
	highlight.OutlineColor = Color3.fromRGB(255, 200, 80)
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Enabled = false
	highlight.Parent = model

	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "HitSparks"
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new(0.4, 0)
	sparks.Lifetime = NumberRange.new(0.2, 0.4)
	sparks.Speed = NumberRange.new(10, 18)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Rate = 120
	sparks.Enabled = false
	sparks.Parent = torso

	-- Name tag
	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Adornee = head
	tag.Size = UDim2.fromOffset(180, 30)
	tag.StudsOffset = Vector3.new(0, 3, 0)
	tag.MaxDistance = 80
	tag.Parent = model

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Parent = tag

	return {
		model = model,
		humanoid = humanoid,
		root = root,
		torso = torso,
		rightShoulder = rightShoulder,
		rightShoulderRest = rightShoulder.C0,
		highlight = highlight,
		hitSparks = sparks,
		nameLabel = label,
	}
end

return ZombieModel
