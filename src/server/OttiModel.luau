--!strict
-- Builds Otti the Gladiator from Parts only (built-in SpecialMesh shapes, no asset IDs), after the
-- reference art: a chocolate-brown otter with a cream muzzle, throat and chest, broad dark nose,
-- short rounded ears, dark eyes, whiskers, webbed paws, a long thick tapered tail and his
-- black-and-cream braided necklace. Gear: chipped gladius (right paw), battered round wooden
-- shield with dark-red panels and an oxidized bronze rim/boss (left paw), asymmetric bronze
-- shoulder armor, bronze bracers and shin guards, a layered leather skirt and worn dark-red cloth.
--
-- Rig (Motor6D, rest pose = standing on the hind legs, facing -Z, feet at y = 0):
--   HumanoidRootPart -RootJoint- Pelvis -Waist- Chest -Neck- Head
--   Chest -RightShoulder/LeftShoulder- arms, Pelvis -RightHip/LeftHip- legs, Pelvis -Tail1..6
-- The server never animates joints; OttiAnimator (client) poses them from the model attributes
-- published by OttiAnimationService. Only the root collides.

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OttiBossConfig = require(ReplicatedStorage.Shared.OttiBossConfig)
local OttiTailService = require(script.Parent.OttiTailService)

local FUR = Color3.fromRGB(92, 58, 38) -- chocolate brown
local FUR_DARK = Color3.fromRGB(66, 40, 26)
local CREAM = Color3.fromRGB(232, 214, 178)
local NOSE = Color3.fromRGB(40, 28, 24)
local EYE = Color3.fromRGB(26, 18, 14)
local WHISKER = Color3.fromRGB(240, 232, 214)
local BRONZE = Color3.fromRGB(170, 122, 62)
local BRONZE_DARK = Color3.fromRGB(122, 86, 44)
local PATINA = Color3.fromRGB(92, 146, 118)
local LEATHER = Color3.fromRGB(104, 66, 40)
local LEATHER_DARK = Color3.fromRGB(70, 44, 28)
local CLOTH = Color3.fromRGB(118, 26, 30) -- worn dark red
local SHIELD_RED = Color3.fromRGB(122, 30, 28)
local WOOD = Color3.fromRGB(110, 76, 46)
local STEEL = Color3.fromRGB(178, 176, 168)
local STEEL_DARK = Color3.fromRGB(120, 118, 112)

export type OttiRig = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	pelvis: BasePart,
	chest: BasePart,
	head: BasePart,
	rightArm: BasePart,
	leftArm: BasePart,
	swordParts: { BasePart }, -- in the paw while drawn
	sheathedParts: { BasePart }, -- hilt at the hip while sheathed
	shieldFace: BasePart,
	guardLight: PointLight,
	tail: OttiTailService.TailRig,
	motors: { [string]: Motor6D },
	bodyParts: { BasePart },
}

local OttiModel = {}

local function setupCollisionGroup()
	local group = "OttiBoss"
	if not PhysicsService:IsCollisionGroupRegistered(group) then
		PhysicsService:RegisterCollisionGroup(group)
	end
	PhysicsService:CollisionGroupSetCollidable(group, "Default", true)
end

function OttiModel.build(): OttiRig
	local S = OttiBossConfig.Scale
	local model = Instance.new("Model")
	model.Name = "OttiTheGladiator"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
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

	-- Unscaled rig-space helpers
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
	local fabric = Enum.Material.Fabric
	local leather = Enum.Material.Leather
	local metal = Enum.Material.CorrodedMetal
	local faceForward = CFrame.Angles(0, math.rad(90), 0) -- cylinder axis X -> Z

	-- Core rig
	local root = makePart("HumanoidRootPart", Vector3.new(3, 2.6, 3) * S, CFrame.new(Vector3.new(0, 3.5, 0) * S), FUR, smooth)
	root.Transparency = 1
	root.CanCollide = true
	root.CanQuery = true
	root.Massless = false
	root.CustomPhysicalProperties = PhysicalProperties.new(6, 0.4, 0.2) -- heavy: players can't shove him
	table.remove(bodyParts, table.find(bodyParts, root) :: number)

	local pelvis = body("Pelvis", Vector3.new(2.6, 2.0, 2.3), Vector3.new(0, 3.3, 0.1), FUR, "Sphere")
	local chest = body("Chest", Vector3.new(2.5, 3.0, 2.1), Vector3.new(0, 5.3, 0), FUR, "Sphere")
	local head = body("Head", Vector3.new(2.1, 1.75, 2.0), Vector3.new(0, 7.55, -0.15), FUR, "Sphere")
	local rightArm = body("RightArm", Vector3.new(0.85, 2.3, 0.85), Vector3.new(1.55, 5.2, 0), FUR, "Head")
	local leftArm = body("LeftArm", Vector3.new(0.85, 2.3, 0.85), Vector3.new(-1.55, 5.2, 0), FUR, "Head")
	local rightLeg = body("RightLeg", Vector3.new(1.05, 2.3, 1.15), Vector3.new(0.8, 1.6, 0.25), FUR, "Head")
	local leftLeg = body("LeftLeg", Vector3.new(1.05, 2.3, 1.15), Vector3.new(-0.8, 1.6, 0.25), FUR, "Head")

	motor("RootJoint", root, pelvis, Vector3.new(0, 3.3, 0))
	motor("Waist", pelvis, chest, Vector3.new(0, 4.0, 0))
	motor("Neck", chest, head, Vector3.new(0, 6.75, -0.1))
	motor("RightShoulder", chest, rightArm, Vector3.new(1.45, 6.3, 0))
	motor("LeftShoulder", chest, leftArm, Vector3.new(-1.45, 6.3, 0))
	motor("RightHip", pelvis, rightLeg, Vector3.new(0.75, 2.75, 0.2))
	motor("LeftHip", pelvis, leftLeg, Vector3.new(-0.75, 2.75, 0.2))

	-- Cream throat, chest and belly
	add(chest, "ChestFur", Vector3.new(1.75, 2.7, 0.5), Vector3.new(0, 5.35, -0.82), CREAM, smooth, nil, "Sphere")
	add(pelvis, "BellyFur", Vector3.new(1.6, 1.3, 0.45), Vector3.new(0, 3.5, -0.9), CREAM, smooth, nil, "Sphere")

	-- Head: broad otter face
	add(head, "Muzzle", Vector3.new(1.45, 0.95, 1.1), Vector3.new(0, 7.2, -0.95), CREAM, smooth, nil, "Sphere")
	add(head, "Chin", Vector3.new(1.1, 0.5, 0.8), Vector3.new(0, 6.85, -0.75), CREAM, smooth, nil, "Sphere")
	for _, side in { -1, 1 } do
		add(head, "Cheek", Vector3.new(0.8, 0.7, 0.6), Vector3.new(side * 0.55, 7.2, -0.7), CREAM, smooth, nil, "Sphere")
	end
	add(head, "Nose", Vector3.new(0.72, 0.42, 0.45), Vector3.new(0, 7.5, -1.5), NOSE, smooth, nil, "Sphere")
	add(head, "NoseShine", Vector3.new(0.18, 0.08, 0.1), Vector3.new(-0.12, 7.64, -1.66), Color3.fromRGB(120, 100, 90), smooth, nil, "Sphere")
	add(head, "Mouth", Vector3.new(0.5, 0.06, 0.06), Vector3.new(0, 7.0, -1.47), NOSE, smooth)
	for _, side in { -1, 1 } do
		add(head, "Eye", Vector3.new(0.36, 0.38, 0.3), Vector3.new(side * 0.48, 7.85, -0.86), EYE, Enum.Material.Glass, nil, "Sphere")
		add(head, "EyeShine", Vector3.new(0.1, 0.1, 0.08), Vector3.new(side * 0.42, 7.93, -1.0), Color3.new(1, 1, 1), Enum.Material.Neon, nil, "Sphere")
		add(head, "Brow", Vector3.new(0.48, 0.1, 0.14), Vector3.new(side * 0.5, 8.12, -0.88), FUR_DARK, smooth, CFrame.Angles(0, 0, side * math.rad(-14)))
		-- Short rounded ears
		local ear = add(head, "Ear", Vector3.new(0.55, 0.5, 0.32), Vector3.new(side * 0.9, 8.3, -0.05), FUR, smooth, nil, "Sphere")
		add(ear, "InnerEar", Vector3.new(0.32, 0.28, 0.1), Vector3.new(side * 0.9, 8.3, -0.2), FUR_DARK, smooth, nil, "Sphere")
		-- Whiskers
		for k, dy in { 0.12, -0.02, -0.16 } do
			local origin = Vector3.new(side * 0.55, 7.25 + dy, -1.25)
			local yaw = side * math.rad(18 + k * 8)
			local pitch = math.rad(dy * 40)
			add(head, "Whisker", Vector3.new(0.04, 0.04, 1.35), origin + Vector3.new(side * 0.55, dy * 0.4, 0.2), WHISKER, smooth, CFrame.Angles(pitch, yaw, 0))
		end
	end

	-- Arms with webbed paws and small claws
	for _, arm in { rightArm, leftArm } do
		local x = arm.Position.X / S
		local paw = add(arm, "Paw", Vector3.new(0.9, 0.6, 0.95), Vector3.new(x, 3.95, -0.05), FUR_DARK, smooth, nil, "Sphere")
		for _, dx in { -0.25, 0, 0.25 } do
			add(paw, "Claw", Vector3.new(0.12, 0.12, 0.18), Vector3.new(x + dx, 3.82, -0.5), CREAM, smooth, nil, "Sphere")
		end
		-- Bronze bracers
		add(arm, "Bracer", Vector3.new(1.0, 0.75, 1.0), Vector3.new(x, 4.55, 0), BRONZE, metal, nil, "Head")
		add(arm, "BracerRim", Vector3.new(1.05, 0.12, 1.05), Vector3.new(x, 4.92, 0), BRONZE_DARK, metal, nil, "Head")
		add(arm, "Patina", Vector3.new(0.35, 0.25, 0.08), Vector3.new(x + 0.1, 4.55, -0.5), PATINA, metal)
	end

	-- Legs: bronze shin guards, webbed feet
	for _, leg in { rightLeg, leftLeg } do
		local x = leg.Position.X / S
		add(leg, "ShinGuard", Vector3.new(0.95, 1.3, 0.45), Vector3.new(x, 1.15, -0.3), BRONZE, metal, nil, "Sphere")
		add(leg, "ShinRidge", Vector3.new(0.12, 1.2, 0.12), Vector3.new(x, 1.15, -0.53), BRONZE_DARK, metal)
		add(leg, "Patina", Vector3.new(0.4, 0.35, 0.08), Vector3.new(x - 0.12, 1.0, -0.52), PATINA, metal)
		local foot = add(leg, "Foot", Vector3.new(1.25, 0.42, 1.95), Vector3.new(x, 0.21, -0.35), FUR_DARK, smooth, nil, "Sphere")
		add(foot, "Web", Vector3.new(1.15, 0.07, 0.5), Vector3.new(x, 0.12, -1.05), Color3.fromRGB(54, 34, 24), smooth)
		for t = -1.5, 1.5 do
			add(foot, "Toe", Vector3.new(0.22, 0.2, 0.3), Vector3.new(x + t * 0.3, 0.2, -1.22), FUR_DARK, smooth, nil, "Sphere")
			add(foot, "Claw", Vector3.new(0.09, 0.09, 0.16), Vector3.new(x + t * 0.3, 0.16, -1.4), CREAM, smooth, nil, "Sphere")
		end
	end

	-- Signature black-and-cream braided necklace
	for i = 0, 15 do
		local angle = i / 16 * 2 * math.pi
		local position = Vector3.new(math.sin(angle) * 1.0, 6.75 - math.max(0, -math.cos(angle)) * 0.25, -math.cos(angle) * 0.92)
		add(chest, "Bead", Vector3.one * 0.3, position, if i % 2 == 0 then Color3.fromRGB(28, 24, 22) else CREAM, smooth, nil, "Ball")
		local inner = Vector3.new(math.sin(angle + 0.2) * 0.95, position.Y - 0.12, -math.cos(angle + 0.2) * 0.87)
		add(chest, "Bead", Vector3.one * 0.22, inner, if i % 2 == 0 then CREAM else Color3.fromRGB(28, 24, 22), smooth, nil, "Ball")
	end

	-- Worn dark-red cloth around the shoulders, with a jagged edge
	add(chest, "Drape", Vector3.new(2.75, 0.75, 2.35), Vector3.new(0, 6.45, 0), CLOTH, fabric, nil, "Head")
	for i, x in { -0.9, -0.45, 0, 0.45, 0.9 } do
		add(chest, "DrapeTatter", Vector3.new(0.42, 0.42, 0.1), Vector3.new(x, 5.95 - (i % 2) * 0.12, -1.02), CLOTH, fabric, CFrame.Angles(0, 0, math.rad(45)))
	end

	-- Asymmetric bronze shoulder armor (sword side), strap with a bronze disc
	add(rightArm, "Pauldron", Vector3.new(1.65, 0.7, 1.6), Vector3.new(1.65, 6.55, 0), BRONZE, metal, CFrame.Angles(0, 0, math.rad(-18)), "Sphere")
	add(rightArm, "Pauldron", Vector3.new(1.5, 0.6, 1.45), Vector3.new(1.85, 6.15, 0), BRONZE_DARK, metal, CFrame.Angles(0, 0, math.rad(-28)), "Sphere")
	add(rightArm, "Pauldron", Vector3.new(1.3, 0.5, 1.3), Vector3.new(2.0, 5.8, 0), BRONZE, metal, CFrame.Angles(0, 0, math.rad(-36)), "Sphere")
	add(rightArm, "Patina", Vector3.new(0.6, 0.18, 0.5), Vector3.new(1.7, 6.85, -0.2), PATINA, metal, CFrame.Angles(0, 0, math.rad(-18)), "Sphere")
	for _, z in { -0.55, 0.55 } do
		add(rightArm, "Rivet", Vector3.one * 0.18, Vector3.new(1.75, 6.6, z), BRONZE_DARK, Enum.Material.Metal, nil, "Ball")
	end
	add(chest, "Strap", Vector3.new(0.35, 3.3, 0.12), Vector3.new(0.15, 5.2, -1.02), LEATHER_DARK, leather, CFrame.Angles(0, 0, math.rad(34)))
	add(chest, "StrapDisc", Vector3.new(0.12, 0.7, 0.7), Vector3.new(0.45, 5.6, -1.12), BRONZE, metal, faceForward, "Cylinder")
	add(chest, "StrapDiscBoss", Vector3.one * 0.25, Vector3.new(0.45, 5.6, -1.2), BRONZE_DARK, Enum.Material.Metal, nil, "Ball")

	-- Belt with a bronze disc, layered leather skirt (pteruges) over dark-red cloth
	add(pelvis, "Belt", Vector3.new(2.75, 0.55, 2.45), Vector3.new(0, 3.95, 0.05), LEATHER_DARK, leather, nil, "Head")
	add(pelvis, "BeltDisc", Vector3.new(0.14, 0.8, 0.8), Vector3.new(0, 3.95, -1.2), BRONZE, metal, faceForward, "Cylinder")
	add(pelvis, "BeltDiscBoss", Vector3.one * 0.3, Vector3.new(0, 3.95, -1.28), PATINA, Enum.Material.Metal, nil, "Ball")
	add(pelvis, "SkirtCloth", Vector3.new(2.5, 1.2, 2.2), Vector3.new(0, 3.05, 0.05), CLOTH, fabric, nil, "Head")
	for i = 0, 11 do
		local angle = i / 12 * 2 * math.pi
		if math.cos(angle) < 0.8 then -- leave room for the tail at the back
			local offset = Vector3.new(math.sin(angle) * 1.18, 0, -math.cos(angle) * 1.08)
			local position = Vector3.new(offset.X, 3.0, offset.Z + 0.05)
			local outward = position + Vector3.new(offset.X, 0, offset.Z)
			local strip = add(pelvis, "Pteruges", Vector3.new(0.5, 1.25, 0.1), position, if i % 2 == 0 then LEATHER else LEATHER_DARK, leather, CFrame.lookAt(position, outward).Rotation)
			add(strip, "Stud", Vector3.one * 0.16, position + (outward - position).Unit * 0.08 - Vector3.new(0, 0.35, 0), BRONZE, Enum.Material.Metal, nil, "Ball")
		end
	end
	for i, x in { -0.5, 0, 0.5 } do
		add(pelvis, "ClothTatter", Vector3.new(0.4, 0.4, 0.1), Vector3.new(x, 2.35 - (i % 2) * 0.1, -1.0), CLOTH, fabric, CFrame.Angles(0, 0, math.rad(45)))
	end

	-- Chipped gladius in the right paw (blade forward while the arm hangs)
	local swordParts: { BasePart } = {}
	local hx, hy = 1.55, 3.95
	local function sword(name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material, rotation: CFrame?, mesh: string?)
		table.insert(swordParts, add(rightArm, name, size, position, color, material, rotation, mesh))
	end
	sword("Grip", Vector3.new(0.26, 0.26, 0.85), Vector3.new(hx, hy, -0.2), LEATHER_DARK, leather)
	sword("Pommel", Vector3.one * 0.4, Vector3.new(hx, hy, 0.32), BRONZE, Enum.Material.Metal, nil, "Ball")
	sword("Guard", Vector3.new(0.95, 0.24, 0.26), Vector3.new(hx, hy, -0.68), BRONZE, metal)
	sword("Blade", Vector3.new(0.16, 0.52, 2.6), Vector3.new(hx, hy, -2.08), STEEL, Enum.Material.Metal)
	sword("Tip", Vector3.new(0.16, 0.37, 0.37), Vector3.new(hx, hy, -3.38), STEEL, Enum.Material.Metal, CFrame.Angles(math.rad(45), 0, 0))
	for _, notch in { { -1.4, 0.24 }, { -2.3, -0.24 }, { -2.8, 0.24 } } do
		sword("Chip", Vector3.new(0.18, 0.12, 0.16), Vector3.new(hx, hy + notch[2], notch[1]), STEEL_DARK, smooth)
	end
	sword("Patina", Vector3.new(0.17, 0.2, 0.35), Vector3.new(hx, hy + 0.05, -1.7), PATINA, metal)

	-- Sheathed hilt at the left hip (shown before the sword is drawn in the intro)
	local sheathedParts: { BasePart } = {}
	table.insert(sheathedParts, add(pelvis, "Scabbard", Vector3.new(0.4, 0.4, 2.2), Vector3.new(-1.3, 3.2, 0.2), LEATHER_DARK, leather, CFrame.Angles(math.rad(60), 0, 0)))
	table.insert(sheathedParts, add(pelvis, "SheathedHilt", Vector3.new(0.3, 0.3, 0.8), Vector3.new(-1.3, 3.95, -0.55), BRONZE, metal, CFrame.Angles(math.rad(60), 0, 0)))
	for _, part in sheathedParts do
		part.Transparency = 1
	end

	-- Battered round wooden shield on the left paw: dark-red panels, oxidized bronze rim and boss
	local diameter = 3.6
	local center = Vector3.new(-1.75, 4.6, -0.75)
	add(leftArm, "ShieldRim", Vector3.new(0.25, diameter, diameter), center, BRONZE_DARK, metal, faceForward, "Cylinder")
	local shieldFace = add(leftArm, "ShieldFace", Vector3.new(0.3, diameter * 0.9, diameter * 0.9), center - Vector3.new(0, 0, 0.05), SHIELD_RED, Enum.Material.WoodPlanks, faceForward, "Cylinder")
	for _, x in { -0.75, 0, 0.75 } do
		add(leftArm, "Plank", Vector3.new(0.06, diameter * 0.82, 0.05), center + Vector3.new(x, 0, -0.22), WOOD, Enum.Material.Wood)
	end
	add(leftArm, "BarePatch", Vector3.new(0.9, 0.6, 0.05), center + Vector3.new(0.65, -0.85, -0.23), WOOD, Enum.Material.Wood, CFrame.Angles(0, 0, math.rad(20)))
	add(leftArm, "Crack", Vector3.new(0.06, 1.2, 0.05), center + Vector3.new(-0.9, 0.55, -0.24), Color3.fromRGB(40, 26, 18), smooth, CFrame.Angles(0, 0, math.rad(30)))
	add(leftArm, "ShieldBoss", Vector3.new(1.1, 1.1, 0.75), center - Vector3.new(0, 0, 0.35), BRONZE, metal, nil, "Sphere")
	add(leftArm, "BossPatina", Vector3.new(0.45, 0.35, 0.2), center + Vector3.new(0.2, 0.2, -0.65), PATINA, metal, nil, "Sphere")
	for i = 0, 9 do
		local angle = i / 10 * 2 * math.pi
		add(leftArm, "RimStud", Vector3.one * 0.2, center + Vector3.new(math.cos(angle) * diameter * 0.46, math.sin(angle) * diameter * 0.46, -0.18), BRONZE, Enum.Material.Metal, nil, "Ball")
	end
	add(leftArm, "RimPatina", Vector3.new(0.08, 0.9, 0.5), center + Vector3.new(-diameter * 0.45, -0.6, -0.1), PATINA, metal)
	local guardLight = Instance.new("PointLight")
	guardLight.Name = "GuardGlow"
	guardLight.Color = Color3.fromRGB(255, 220, 120)
	guardLight.Range = 12
	guardLight.Brightness = 4
	guardLight.Enabled = false
	guardLight.Parent = shieldFace

	-- Tail
	local tail = OttiTailService.build(pelvis, Vector3.new(0, 2.9, 1.05), S, FUR, makePart)

	-- Humanoid (R15 rules: HipHeight = ground to the bottom of the root)
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = 2.2 * S
	humanoid.MaxHealth = 1e6 -- Otti's real health lives in OttiBossService (he is defeated, never killed)
	humanoid.Health = 1e6
	humanoid.WalkSpeed = OttiBossConfig.WalkSpeedBiped
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	for _, state in { Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.Climbing, Enum.HumanoidStateType.Dead, Enum.HumanoidStateType.Swimming } do
		humanoid:SetStateEnabled(state, false)
	end
	humanoid.Parent = model
	Instance.new("Animator").Parent = humanoid -- for authored animations later (OttiBossConfig.AnimationIds)
	model.PrimaryPart = root

	pcall(setupCollisionGroup)
	root.CollisionGroup = "OttiBoss"
	for _, part in bodyParts do
		part.CollisionGroup = "OttiBoss"
	end
	model:SetAttribute("BossName", OttiBossConfig.DisplayName)

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
		sheathedParts = sheathedParts,
		shieldFace = shieldFace,
		guardLight = guardLight,
		tail = tail,
		motors = motors,
		bodyParts = bodyParts,
	}
end

return OttiModel
