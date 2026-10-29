--!strict
-- Kroko and Schili: native procedural 3D heroes, with species-specific proportions and gear.
-- HeroSkeleton adds the common articulated limbs; the shared animator reads each hero's profile.
-- Primitive shapes keep the models asset-free and editable; they are not raster sprites or SVGs.

local PhysicsService = game:GetService("PhysicsService")

local OttiTailService = require(script.Parent.OttiTailService)
local OttiModel = require(script.Parent.OttiModel)
local HeroSkeleton = require(script.Parent.HeroSkeleton)

type OttiRig = OttiModel.OttiRig

local CompanionModel = {}

local BRONZE = Color3.fromRGB(170, 122, 62)
local PATINA = Color3.fromRGB(92, 146, 118)
local LEATHER = Color3.fromRGB(104, 66, 40)
local LEATHER_DARK = Color3.fromRGB(70, 44, 28)
local WOOD = Color3.fromRGB(110, 76, 46)
local WOOD_LIGHT = Color3.fromRGB(150, 108, 66)
local SHIELD_RED = Color3.fromRGB(122, 30, 28)
local CREAM = Color3.fromRGB(232, 214, 178)
local EYE_AMBER = Color3.fromRGB(255, 176, 40)
local NOSE = Color3.fromRGB(30, 24, 20)
local GOLD = Color3.fromRGB(230, 185, 80)

type Palette = {
	body: Color3,
	belly: Color3,
	ridge: Color3,
	name: string,
	scale: number,
}

local SPECIES: { [string]: Palette } = {
	Kroko = { body = Color3.fromRGB(64, 120, 58), belly = Color3.fromRGB(178, 186, 88), ridge = Color3.fromRGB(38, 78, 40), name = "Kroko", scale = 1.1 },
	Schili = { body = Color3.fromRGB(126, 140, 90), belly = Color3.fromRGB(222, 214, 174), ridge = Color3.fromRGB(92, 104, 64), name = "Schili", scale = 1.0 },
}

-- Companion ids this module can build.
function CompanionModel.has(id: string): boolean
	return SPECIES[id] ~= nil
end

function CompanionModel.build(id: string): OttiRig
	local palette = SPECIES[id] or SPECIES.Kroko
	local isTortoise = id == "Schili"
	local S = palette.scale
	local model = Instance.new("Model")
	model.Name = "Companion_" .. id
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("BossName", palette.name)
	model:SetAttribute("HeroId", id)
	local bodyParts: { BasePart } = {}

	local function makePart(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, mesh: string?): BasePart
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.CFrame = cframe
		part.Color = color
		part.Material = material
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Massless = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		if mesh == "Ball" then
			part.Shape = Enum.PartType.Ball
		elseif mesh == "Cylinder" then
			part.Shape = Enum.PartType.Cylinder
		elseif mesh then
			local specialMesh = Instance.new("SpecialMesh")
			specialMesh.MeshType = if mesh == "Head" then Enum.MeshType.Head else Enum.MeshType.Sphere
			specialMesh.Parent = part
		end
		part.Parent = model
		table.insert(bodyParts, part)
		return part
	end

	-- Unscaled rig-space helpers (multiplied by S here)
	local function body(name: string, size: Vector3, position: Vector3, color: Color3, mesh: string?, material: Enum.Material?): BasePart
		local part = makePart(name, size * S, CFrame.new(position * S), color, material or Enum.Material.SmoothPlastic, mesh)
		part.CanQuery = true -- arrows and aim rays can hit the body
		return part
	end
	local function add(limb: BasePart, name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material, rotation: CFrame?, mesh: string?): BasePart
		local part = makePart(name, size * S, CFrame.new(position * S) * (rotation or CFrame.identity), color, material, mesh)
		local weld = Instance.new("Weld")
		weld.Part0 = limb
		weld.Part1 = part
		weld.C0 = limb.CFrame:Inverse() * part.CFrame
		weld.Parent = part
		return part
	end
	local motors: { [string]: Motor6D } = {}
	local function motor(name: string, part0: BasePart, part1: BasePart, joint: Vector3)
		local m = Instance.new("Motor6D")
		m.Name = name
		m.Part0 = part0
		m.Part1 = part1
		local world = CFrame.new(joint * S)
		m.C0 = part0.CFrame:Inverse() * world
		m.C1 = part1.CFrame:Inverse() * world
		m.Parent = part0
		motors[name] = m
	end

	local smooth = Enum.Material.SmoothPlastic
	local leather = Enum.Material.Leather
	local metal = Enum.Material.CorrodedMetal
	local legLen = if isTortoise then 1.2 else 2.2

	-- Core rig: the root collides, everything else is visual
	local root = makePart("HumanoidRootPart", Vector3.new(3, 2.6, 3) * S, CFrame.new(Vector3.new(0, legLen + 1.2, 0) * S), palette.body, smooth)
	root.Transparency = 1
	root.CanCollide = true
	root.CanQuery = true
	root.Massless = false
	root.CustomPhysicalProperties = PhysicalProperties.new(6, 0.4, 0.2)
	table.remove(bodyParts, table.find(bodyParts, root) :: number)

	local pelvisY = legLen + 0.9
	local chestY = pelvisY + (if isTortoise then 1.4 else 2.0)
	local pelvis = body("Pelvis", Vector3.new(2.6, 2.0, 2.3), Vector3.new(0, pelvisY, 0.1), palette.body, "Sphere")
	local chest = body("Chest", Vector3.new(if isTortoise then 2.8 else 3.1, if isTortoise then 2.2 else 2.8, 2.2), Vector3.new(0, chestY, 0), palette.body, "Sphere")
	local headY = chestY + 2.0
	local head = body("Head", Vector3.new(2.0, 1.7, 2.1), Vector3.new(0, headY, -0.2), palette.body, "Sphere")
	local rightArm = body("RightArm", Vector3.new(0.8, 2.1, 0.8), Vector3.new(1.5, chestY + 0.6, 0), palette.body, "Head")
	local leftArm = body("LeftArm", Vector3.new(0.8, 2.1, 0.8), Vector3.new(-1.5, chestY + 0.6, 0), palette.body, "Head")
	local rightLeg = body("RightLeg", Vector3.new(1.0, legLen + 0.2, 1.1), Vector3.new(0.8, legLen / 2, 0.2), palette.body, "Head")
	local leftLeg = body("LeftLeg", Vector3.new(1.0, legLen + 0.2, 1.1), Vector3.new(-0.8, legLen / 2, 0.2), palette.body, "Head")

	motor("RootJoint", root, pelvis, Vector3.new(0, pelvisY, 0))
	motor("Waist", pelvis, chest, Vector3.new(0, pelvisY + 1.0, 0))
	motor("Neck", chest, head, Vector3.new(0, chestY + 1.3, -0.1))
	motor("RightShoulder", chest, rightArm, Vector3.new(1.3, chestY + 1.1, 0))
	motor("LeftShoulder", chest, leftArm, Vector3.new(-1.3, chestY + 1.1, 0))
	motor("RightHip", pelvis, rightLeg, Vector3.new(0.75, pelvisY - 0.4, 0.2))
	motor("LeftHip", pelvis, leftLeg, Vector3.new(-0.75, pelvisY - 0.4, 0.2))

	-- Belly and throat in the lighter colour
	add(chest, "Belly", Vector3.new(1.9, 2.2, 0.5), Vector3.new(0, chestY - 0.1, -0.9), palette.belly, smooth, nil, "Ball")
	add(pelvis, "BellyLow", Vector3.new(1.7, 1.2, 0.4), Vector3.new(0, pelvisY - 0.2, -0.9), palette.belly, smooth, nil, "Ball")

	if isTortoise then
		-- Large domed shell with a bronze rim, plates and a gold emblem (the centre of the design)
		local shellY = chestY - 0.2
		add(chest, "ShellRim", Vector3.new(4.4, 4.5, 0.55), Vector3.new(0, shellY, 1.0), GOLD, metal, nil, "Ball")
		add(chest, "Shell", Vector3.new(4.1, 4.2, 2.2), Vector3.new(0, shellY, 1.45), Color3.fromRGB(112, 76, 43), Enum.Material.Wood, nil, "Ball")
		for i = 0, 5 do
			local angle = math.rad(i * 60)
			local position = Vector3.new(math.sin(angle) * 1.05, shellY + math.cos(angle) * 1.1, 2.43)
			local normal = Vector3.new(math.sin(angle) * 0.3, math.cos(angle) * 0.3, 1).Unit
			add(chest, "ShellPlate", Vector3.new(1.25, 1.4, 0.32), position, if i % 2 == 0 then Color3.fromRGB(184, 131, 63) else Color3.fromRGB(136, 147, 74), Enum.Material.Wood, CFrame.lookAt(Vector3.zero, -normal) * CFrame.Angles(0, 0, -angle), "Sphere")
		end
		add(chest, "ShellSun", Vector3.new(1.0, 1.0, 0.2), Vector3.new(0, shellY, 2.59), GOLD, metal, nil, "Ball")
		for i = 0, 7 do
			local a = math.rad(i * 45)
			add(chest, "SunRay", Vector3.new(0.1, 0.3, 0.12), Vector3.new(math.sin(a) * 0.72, shellY + math.cos(a) * 0.72, 2.57), GOLD, metal, CFrame.Angles(0, 0, -a))
		end
		add(head, "Muzzle", Vector3.new(1.5, 0.8, 0.8), Vector3.new(0, headY - 0.35, -1.17), palette.belly, smooth, nil, "Ball")
		for _, side in { -1, 1 } do
			add(head, "Eye", Vector3.new(0.48, 0.56, 0.25), Vector3.new(side * 0.53, headY + 0.2, -1.16), Color3.fromRGB(62, 37, 24), smooth, nil, "Ball")
			add(head, "Catchlight", Vector3.new(0.14, 0.16, 0.08), Vector3.new(side * 0.53 - 0.06, headY + 0.32, -1.3), CREAM, smooth, nil, "Ball")
			add(head, "Brow", Vector3.new(0.54, 0.13, 0.17), Vector3.new(side * 0.53, headY + 0.62, -1.07), palette.ridge, smooth, CFrame.Angles(0, 0, side * math.rad(6)), "Ball")
		end
		add(pelvis, "TealCloth", Vector3.new(1.35, 0.9, 0.15), Vector3.new(0, pelvisY - 0.7, -1.04), Color3.fromRGB(37, 104, 105), Enum.Material.Fabric)
		add(pelvis, "UtilityPouch", Vector3.new(0.6, 0.7, 0.4), Vector3.new(-1.3, pelvisY, -0.7), LEATHER, leather, nil, "Head")
		add(pelvis, "ScrollCase", Vector3.new(0.45, 1.1, 0.45), Vector3.new(1.3, pelvisY + 0.1, -0.5), WOOD_LIGHT, Enum.Material.Wood, CFrame.Angles(0, 0, math.rad(-15)), "Head")
		-- bronze bracers and a narrow leather chest strap
		add(chest, "Strap", Vector3.new(0.35, 2.4, 0.12), Vector3.new(0.2, chestY, -1.1), LEATHER, leather, CFrame.Angles(0, 0, math.rad(34)))
		for _, arm in { rightArm, leftArm } do
			add(arm, "Bracer", Vector3.new(0.95, 0.6, 0.95), Vector3.new(arm.Position.X / S, chestY - 0.7, 0), BRONZE, metal, nil, "Head")
		end
		-- soft bronze forehead band
		add(head, "Band", Vector3.new(1.9, 0.22, 1.9), Vector3.new(0, headY + 0.6, -0.2), BRONZE, metal, nil, "Head")
	else
		-- Crocodile: long snout, cream jaw, back ridges, amber eyes, bronze shoulder guard, harness
		add(head, "Snout", Vector3.new(2.0, 0.9, 1.9), Vector3.new(0, headY - 0.1, -1.4), palette.body, smooth, nil, "Ball")
		add(head, "Jaw", Vector3.new(1.9, 0.5, 1.8), Vector3.new(0, headY - 0.7, -1.3), CREAM, smooth, nil, "Ball")
		add(head, "Nose", Vector3.new(0.5, 0.3, 0.3), Vector3.new(0, headY + 0.1, -2.3), NOSE, smooth, nil, "Ball")
		for _, side in { -1, 1 } do
			add(head, "Eye", Vector3.new(0.4, 0.4, 0.3), Vector3.new(side * 0.7, headY + 0.5, -1.2), EYE_AMBER, smooth, nil, "Ball")
			add(head, "Pupil", Vector3.new(0.18, 0.27, 0.12), Vector3.new(side * 0.7, headY + 0.5, -1.36), NOSE, smooth, nil, "Ball")
			add(head, "Catchlight", Vector3.new(0.08, 0.09, 0.06), Vector3.new(side * 0.7 - 0.04, headY + 0.59, -1.43), CREAM, smooth, nil, "Ball")
			add(head, "Brow", Vector3.new(0.6, 0.15, 0.3), Vector3.new(side * 0.7, headY + 0.85, -1.2), palette.ridge, smooth, CFrame.Angles(0, 0, side * math.rad(-14)))
		end
		for _, x in { -0.5, 0.5 } do
			add(head, "Tooth", Vector3.new(0.14, 0.18, 0.14), Vector3.new(x, headY - 0.45, -2.0), CREAM, smooth, nil, "Ball")
		end
		for i = 0, 4 do
			add(chest, "Ridge", Vector3.new(0.4, 0.5, 0.4), Vector3.new(0, chestY + 1.4 - i * 0.7, 1.0), palette.ridge, smooth, nil, "Ball")
		end
		add(chest, "ShoulderGuard", Vector3.new(1.9, 0.6, 1.8), Vector3.new(1.4, chestY + 1.2, 0), BRONZE, metal, CFrame.Angles(0, 0, math.rad(-18)), "Sphere")
		add(chest, "Patina", Vector3.new(0.6, 0.2, 0.5), Vector3.new(1.5, chestY + 1.5, -0.2), PATINA, metal, nil, "Sphere")
		add(chest, "Harness", Vector3.new(0.35, 2.4, 0.12), Vector3.new(0.2, chestY, -1.1), LEATHER, leather, CFrame.Angles(0, 0, math.rad(34)))
		for _, arm in { rightArm, leftArm } do
			add(arm, "WristGuard", Vector3.new(0.95, 0.6, 0.95), Vector3.new(arm.Position.X / S, chestY - 0.7, 0), LEATHER_DARK, leather, nil, "Head")
		end
	end

	-- An affectionate smile: curved corners, never a threatening row of teeth.
	for i = -2, 2 do
		local z = if isTortoise then -1.57 else -2.16
		add(head, "Smile", Vector3.new(0.19, 0.055, 0.06), Vector3.new(i * 0.16, headY - 0.48 + math.abs(i) * 0.045, z), LEATHER_DARK, smooth, CFrame.Angles(0, 0, i * math.rad(10)), "Ball")
	end
	add(pelvis, "Belt", Vector3.new(2.75, 0.3, 2.4), Vector3.new(0, pelvisY, 0.1), LEATHER_DARK, leather, nil, "Head")
	add(pelvis, "BeltEmblem", Vector3.new(0.55, 0.55, 0.15), Vector3.new(0, pelvisY, -1.19), BRONZE, metal, nil, "Ball")
	if not isTortoise then
		add(pelvis, "RedCloth", Vector3.new(1.4, 1.0, 0.15), Vector3.new(0, pelvisY - 0.65, -1.12), SHIELD_RED, Enum.Material.Fabric)
	end
	-- Feet: sturdy rounded paws.
	for _, leg in { leftLeg, rightLeg } do
		local x = leg.Position.X / S
		add(leg, "Foot", Vector3.new(1.2, 0.4, 1.8), Vector3.new(x, 0.2, -0.3), palette.body, smooth, nil, "Ball")
		add(leg, "Sole", Vector3.new(1.2, 0.2, 1.7), Vector3.new(x, 0.12, -0.3), LEATHER_DARK, leather)
	end

	-- Tail: the same six-segment tail as Otti (scaled to the species)
	local tail = OttiTailService.build(pelvis, Vector3.new(0, pelvisY - 0.3, 1.2), S, palette.body, makePart, if isTortoise then 0.15 else 1.15)

	if not isTortoise then
		for _, segment in tail.segments do
			local ridge = makePart("TailRidge", Vector3.new(0.35, 0.4, 0.5) * S, segment.CFrame * CFrame.new(0, segment.Size.Y / 2, 0), palette.ridge, smooth, "Ball")
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1, weld.Parent = segment, ridge, ridge
		end
	end
	-- Weapon in the right hand (swordParts: shown while the boss is armed)
	local swordParts: { BasePart } = {}
	local function weapon(name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material, rotation: CFrame?, mesh: string?)
		table.insert(swordParts, add(rightArm, name, size, position, color, material, rotation, mesh))
	end
	local hx, hy = 1.5, chestY - 1.0
	if isTortoise then
		-- wooden staff with a bronze tip
		weapon("Staff", Vector3.new(0.25, 0.25, 4.6), Vector3.new(hx, hy, -2.0), WOOD_LIGHT, Enum.Material.Wood)
		weapon("StaffTip", Vector3.new(0.4, 0.4, 0.5), Vector3.new(hx, hy, -4.4), BRONZE, metal, nil, "Ball")
	else
		-- chunky wooden club
		weapon("Club", Vector3.new(0.6, 0.6, 3.2), Vector3.new(hx, hy, -1.6), WOOD, Enum.Material.Wood)
		weapon("ClubHead", Vector3.new(1.1, 1.1, 1.2), Vector3.new(hx, hy, -3.6), WOOD_LIGHT, Enum.Material.Wood, nil, "Ball")
		weapon("ClubBand", Vector3.new(1.2, 0.25, 1.25), Vector3.new(hx, hy, -3.0), BRONZE, metal, nil, "Cylinder")
	end

	-- Round wooden shield on the left arm (Kroko; Schili carries a small shield too for the same rig)
	local shieldFace: BasePart
	do
		local diameter = if isTortoise then 2.0 else 2.8
		local center = Vector3.new(-1.9, chestY - 0.1, -1.0)
		add(leftArm, "ShieldRim", Vector3.new(0.25, diameter, diameter), center, BRONZE, metal, CFrame.Angles(0, math.rad(90), 0), "Cylinder")
		shieldFace = add(leftArm, "ShieldFace", Vector3.new(0.3, diameter * 0.9, diameter * 0.9), center - Vector3.new(0, 0, 0.05), SHIELD_RED, Enum.Material.WoodPlanks, CFrame.Angles(0, math.rad(90), 0), "Cylinder")
		add(leftArm, "ShieldBoss", Vector3.new(1.0, 1.0, 0.7), center - Vector3.new(0, 0, 0.3), BRONZE, metal, nil, "Sphere")
	end
	local guardLight = Instance.new("PointLight")
	guardLight.Name = "GuardGlow"
	guardLight.Color = Color3.fromRGB(255, 220, 120)
	guardLight.Range = 10
	guardLight.Brightness = 3
	guardLight.Enabled = false
	guardLight.Parent = shieldFace

	-- Humanoid (no health of its own: the encounter keeps the real health, as with Otti)
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = legLen * S
	humanoid.MaxHealth = 1e6
	humanoid.Health = 1e6
	humanoid.WalkSpeed = 9
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	for _, state in { Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.Climbing, Enum.HumanoidStateType.Dead, Enum.HumanoidStateType.Swimming } do
		humanoid:SetStateEnabled(state, false)
	end
	humanoid.Parent = model
	Instance.new("Animator").Parent = humanoid
	model.PrimaryPart = root

	HeroSkeleton.articulate(model, motors, bodyParts)
	pcall(function()
		local group = "OttiBoss"
		if not PhysicsService:IsCollisionGroupRegistered(group) then
			PhysicsService:RegisterCollisionGroup(group)
		end
		PhysicsService:CollisionGroupSetCollidable(group, "Default", true)
	end)
	root.CollisionGroup = "OttiBoss"
	for _, part in bodyParts do
		part.CollisionGroup = "OttiBoss"
	end

	return {
		model = model,
		humanoid = humanoid,
		root = root,
		pelvis = pelvis,
		chest = chest,
		head = head,
		rightArm = rightArm,
		leftArm = leftArm,
		swordParts = swordParts,
		sheathedParts = {},
		shieldFace = shieldFace,
		guardLight = guardLight,
		tail = tail,
		motors = motors,
		bodyParts = bodyParts,
	}
end

return CompanionModel
