--!strict
-- Builds a Roman gladiator zombie rig for any ZombieDefinition from Parts only:
-- built-in SpecialMesh shapes (Sphere/Head) give the rounded body, Motor6D joints let it
-- walk and pose, and a Humanoid lets it use PathfindingService. No asset IDs.
-- Coordinates are in rest pose with the feet at y = 0, facing -Z, before scaling.
-- Only the HumanoidRootPart collides: it is sized to the torso so zombies have a solid body.
-- Damage support: every part carries a "Limb" attribute (the limb it hangs on), detachable armor a
-- "Detach" group (Helmet, ShoulderR, ShoulderL), and hidden "DamageDetail" parts (scratches,
-- cracks, torn cloth) are prepared up front, so condition changes only toggle visibility
-- (ZombieDamageStateService / ZombieDismembermentService) instead of rebuilding the model.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ZombieDefinitions = require(ReplicatedStorage.Shared.ZombieDefinitions)

type ZombieDefinition = ZombieDefinitions.ZombieDefinition

-- Palette
local SKIN = Color3.fromRGB(112, 150, 84) -- moss green
local SKIN_DARK = Color3.fromRGB(78, 108, 58)
local EYES = Color3.fromRGB(255, 176, 40) -- glowing amber
local PUPIL = Color3.fromRGB(70, 30, 10)
local MOUTH = Color3.fromRGB(44, 30, 26)
local TEETH = Color3.fromRGB(232, 222, 196)
local BRONZE = Color3.fromRGB(176, 125, 60)
local BRONZE_DARK = Color3.fromRGB(126, 86, 42)
local GOLD = Color3.fromRGB(230, 185, 80)
local OXIDE = Color3.fromRGB(96, 150, 122) -- green patina on bronze
local CRACK = Color3.fromRGB(52, 38, 24)
local LEATHER = Color3.fromRGB(110, 70, 40)
local LEATHER_DARK = Color3.fromRGB(74, 46, 26)
local WOOD = Color3.fromRGB(122, 84, 50)
local SHIELD_RED = Color3.fromRGB(128, 40, 32)
local STEEL = Color3.fromRGB(186, 186, 180)
local NET = Color3.fromRGB(196, 182, 150)

export type ZombieRig = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	torso: BasePart,
	head: BasePart,
	leftArm: BasePart,
	rightArm: BasePart,
	leftLeg: BasePart,
	rightLeg: BasePart,
	rootJoint: Motor6D,
	rootJointRest: CFrame,
	rightShoulder: Motor6D,
	rightShoulderRest: CFrame,
	leftShoulder: Motor6D,
	leftShoulderRest: CFrame,
	hitSparks: ParticleEmitter,
	deathPuff: ParticleEmitter,
	guardGlow: PointLight?, -- champion shield telegraph
	visibleParts: { BasePart },
}

type MeshKind = "Sphere" | "Head"

local ZombieFactory = {}

function ZombieFactory.build(def: ZombieDefinition): ZombieRig
	local body = def.Body
	local gear = def.Gear
	local S = body.Scale
	local CLOTH = gear.ClothColor

	local model = Instance.new("Model")
	model.Name = def.Id
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("ZombieType", def.DisplayName)
	model:SetAttribute("MaxHealth", def.Health)
	model:SetAttribute("Health", def.Health)

	local visibleParts: { BasePart } = {}

	local function scaled(cframe: CFrame): CFrame
		return CFrame.new(cframe.Position * S) * cframe.Rotation
	end

	local function newPart(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?, mesh: MeshKind?): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size * S
		part.CFrame = scaled(cframe)
		part.Color = color
		part.Material = material
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Massless = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		if shape then
			part.Shape = shape
		end
		if mesh then
			local specialMesh = Instance.new("SpecialMesh")
			specialMesh.MeshType = if mesh == "Sphere" then Enum.MeshType.Sphere else Enum.MeshType.Head
			specialMesh.Parent = part
		end
		if color == SKIN then
			part:SetAttribute("Skin", true) -- recolored by the damage states
		end
		part.Parent = model
		table.insert(visibleParts, part)
		return part
	end

	local detachGroup: string? = nil -- while set, new accessories belong to this detachable group

	-- Creates an accessory part in rest pose and welds it to a limb.
	local function add(limb: BasePart, name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material, rotation: CFrame?, shape: Enum.PartType?, mesh: MeshKind?): Part
		local part = newPart(name, size, CFrame.new(position) * (rotation or CFrame.identity), color, material, shape, mesh)
		local weld = Instance.new("Weld")
		weld.Part0 = limb
		weld.Part1 = part
		weld.C0 = limb.CFrame:Inverse() * part.CFrame
		weld.Parent = part
		part:SetAttribute("Limb", limb:GetAttribute("Limb"))
		if detachGroup then
			part:SetAttribute("Detach", detachGroup)
		end
		return part
	end

	-- A prepared damage detail: hidden until the zombie reaches `state` (Wounded / Critical).
	local function detail(limb: BasePart, state: string, name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material, rotation: CFrame?)
		local part = add(limb, name, size, position, color, material, rotation)
		part.Transparency = 1
		part:SetAttribute("DamageDetail", state)
	end

	local function motor(name: string, part0: BasePart, part1: BasePart, joint: Vector3): Motor6D
		local m = Instance.new("Motor6D")
		m.Name = name
		m.Part0 = part0
		m.Part1 = part1
		local world = CFrame.new(joint * S)
		m.C0 = part0.CFrame:Inverse() * world
		m.C1 = part1.CFrame:Inverse() * world
		m.Parent = part0
		return m
	end

	local CYLINDER = Enum.PartType.Cylinder
	local BALL = Enum.PartType.Ball
	local faceForward = CFrame.Angles(0, math.rad(90), 0) -- cylinder axis X -> Z
	local metal = Enum.Material.CorrodedMetal
	local leather = Enum.Material.Leather
	local fabric = Enum.Material.Fabric
	local smooth = Enum.Material.SmoothPlastic

	-- Body landmarks (unscaled)
	local T, H, Arm, Leg = body.Torso, body.Head, body.Arm, body.Leg
	local legLen = Leg.Y
	local torsoY = legLen + T.Y / 2 - 0.2
	local torsoTop = torsoY + T.Y / 2
	local shoulderY = torsoTop - 0.3
	local shoulderX = T.X / 2 + Arm.X / 2 - 0.2
	local armY = shoulderY - Arm.Y / 2 + 0.25
	local handY = armY - Arm.Y / 2 + Arm.X * 0.25
	local headY = torsoTop + H.Y / 2 - 0.15
	local frontZ = -H.Z / 2

	-- Core rig. The root is the zombie's solid body (sized to the torso); everything else is visual.
	local rootSize = Vector3.new(math.max(2, T.X * 0.8), 2, math.max(1.2, T.Z * 0.85))
	local root = newPart("HumanoidRootPart", rootSize, CFrame.new(0, legLen + 1, 0), SKIN, smooth)
	root.Transparency = 1
	root.CanCollide = true
	root.CanQuery = true
	root.Massless = false
	local rootIndex = table.find(visibleParts, root)
	if rootIndex then
		table.remove(visibleParts, rootIndex) -- the root stays invisible; skip it in fade effects
	end

	local torso = newPart("Torso", T, CFrame.new(0, torsoY, 0), SKIN, smooth, nil, "Sphere")
	local head = newPart("Head", H, CFrame.new(0, headY, 0), SKIN, smooth, nil, "Head")
	local rightArm = newPart("RightArm", Arm, CFrame.new(shoulderX, armY, 0), SKIN, smooth, nil, "Head")
	local leftArm = newPart("LeftArm", Arm, CFrame.new(-shoulderX, armY, 0), SKIN, smooth, nil, "Head")
	local rightLeg = newPart("RightLeg", Leg, CFrame.new(body.HipSpread, legLen / 2, 0), SKIN, smooth, nil, "Head")
	local leftLeg = newPart("LeftLeg", Leg, CFrame.new(-body.HipSpread, legLen / 2, 0), SKIN, smooth, nil, "Head")

	for _, limb in { torso, head, rightArm, leftArm, rightLeg, leftLeg } do
		limb:SetAttribute("Limb", limb.Name)
	end

	local rootJoint = motor("RootJoint", root, torso, Vector3.new(0, legLen + 1, 0))
	motor("Neck", torso, head, Vector3.new(0, torsoTop, 0))
	local rightShoulder = motor("RightShoulder", torso, rightArm, Vector3.new(shoulderX, shoulderY, 0))
	local leftShoulder = motor("LeftShoulder", torso, leftArm, Vector3.new(-shoulderX, shoulderY, 0))
	motor("RightHip", torso, rightLeg, Vector3.new(body.HipSpread, legLen, 0))
	motor("LeftHip", torso, leftLeg, Vector3.new(-body.HipSpread, legLen, 0))

	-- Fists
	for _, arm in { rightArm, leftArm } do
		add(arm, "Fist", Vector3.one * Arm.X * 1.15, Vector3.new(arm.Position.X / S, handY, 0), SKIN, smooth, nil, BALL)
	end

	-- Face: glowing amber eyes with pupils, angry brows, toothy (friendly) grin, a few stitches
	local eyeSize = H.X * (if gear.EyeGlow > 2 then 0.27 else 0.24)
	for _, side in { -1, 1 } do
		local eye = add(head, "Eye", Vector3.one * eyeSize, Vector3.new(side * H.X * 0.22, headY + H.Y * 0.02, frontZ * 0.78), EYES, Enum.Material.Neon, nil, BALL)
		add(eye, "Pupil", Vector3.one * eyeSize * 0.4, Vector3.new(side * H.X * 0.2, headY + H.Y * 0.02, frontZ * 0.78 - eyeSize * 0.42), PUPIL, smooth, nil, BALL)
		add(head, "Brow", Vector3.new(H.X * 0.3, 0.16, 0.14), Vector3.new(side * H.X * 0.22, headY + H.Y * 0.16, frontZ * 0.9), SKIN_DARK, smooth, CFrame.Angles(0, 0, side * math.rad(20)))
	end
	add(head, "Mouth", Vector3.new(H.X * 0.46, 0.24, 0.12), Vector3.new(0, headY - H.Y * 0.24, frontZ * 0.94), MOUTH, smooth)
	for _, x in { -0.28, 0, 0.28 } do
		add(head, "Tooth", Vector3.new(0.16, 0.14, 0.06), Vector3.new(x * H.X / 2, headY - H.Y * 0.2, frontZ * 0.98), TEETH, smooth)
	end
	add(head, "Tooth", Vector3.new(0.14, 0.14, 0.06), Vector3.new(H.X * 0.1, headY - H.Y * 0.28, frontZ * 0.98), TEETH, smooth)
	add(head, "Stitch", Vector3.new(0.05, 0.4, 0.05), Vector3.new(-H.X * 0.36, headY - H.Y * 0.08, frontZ * 0.8), CRACK, smooth)
	for _, y in { -0.02, -0.14 } do
		add(head, "Stitch", Vector3.new(0.2, 0.04, 0.05), Vector3.new(-H.X * 0.36, headY + H.Y * y, frontZ * 0.81), CRACK, smooth)
	end
	local eyeGlow = Instance.new("PointLight")
	eyeGlow.Color = EYES
	eyeGlow.Range = 6 + gear.EyeGlow * 2
	eyeGlow.Brightness = gear.EyeGlow
	eyeGlow.Parent = head

	-- Helmet (detachable as one group)
	local capBottom = headY + H.Y * 0.2
	detachGroup = "Helmet"
	if gear.Helmet == "Wrap" then
		-- Archer: cloth head wrap with a small bronze browband
		add(head, "HeadWrap", Vector3.new(H.X * 1.08, H.Y * 0.5, H.Z * 1.08), Vector3.new(0, capBottom + H.Y * 0.18, 0), gear.ClothColor, fabric, nil, nil, "Head")
		add(head, "WrapKnot", Vector3.new(0.5, 0.45, 0.4), Vector3.new(0, capBottom + H.Y * 0.1, H.Z * 0.55), gear.ClothColor, fabric, nil, BALL)
		add(head, "WrapTail", Vector3.new(0.35, 0.9, 0.1), Vector3.new(0.15, capBottom - 0.3, H.Z * 0.6), gear.ClothColor, fabric, CFrame.Angles(math.rad(15), 0, math.rad(10)))
		add(head, "Browband", Vector3.new(H.X * 1.1, 0.16, H.Z * 1.1), Vector3.new(0, capBottom + 0.02, 0), BRONZE, metal, nil, nil, "Head")
	elseif gear.Helmet == "Cap" then
		-- Small open bronze cap with a brim
		local capHeight = H.Y * 0.42
		add(head, "Cap", Vector3.new(H.X * 1.08, capHeight, H.Z * 1.08), Vector3.new(0, capBottom + capHeight / 2, 0), BRONZE, metal, nil, nil, "Head")
		add(head, "Brim", Vector3.new(H.X * 1.14, 0.14, H.Z * 1.14), Vector3.new(0, capBottom + 0.05, 0), BRONZE_DARK, metal, nil, nil, "Head")
		add(head, "Knob", Vector3.one * 0.35, Vector3.new(0, capBottom + capHeight + 0.05, 0), BRONZE, Enum.Material.Metal, nil, BALL)
		add(head, "Patina", Vector3.new(0.5, 0.22, 0.06), Vector3.new(H.X * 0.25, capBottom + capHeight * 0.45, frontZ * 1.04), OXIDE, metal)
	else
		-- Gladiator helmet: rounded dome, brow ridge, cheek guards (+ nose guard unless open-faced)
		local capHeight = H.Y * (if gear.Helmet == "OpenFace" then 0.5 else 0.62)
		add(head, "HelmetDome", Vector3.new(H.X * 1.12, capHeight, H.Z * 1.12), Vector3.new(0, capBottom + capHeight / 2, 0), BRONZE, metal, nil, nil, "Head")
		add(head, "BrowRidge", Vector3.new(H.X * 1.1, 0.18, 0.2), Vector3.new(0, capBottom + 0.05, frontZ * 1.04), if gear.Helmet == "Ornate" then GOLD else BRONZE_DARK, metal)
		if gear.Helmet ~= "OpenFace" then
			add(head, "NoseGuard", Vector3.new(0.18, H.Y * 0.32, 0.12), Vector3.new(0, headY + H.Y * 0.06, frontZ * 1.04), BRONZE_DARK, metal)
		end
		for _, side in { -1, 1 } do
			if gear.Helmet ~= "Damaged" or side == -1 then -- the damaged helmet lost one cheek guard
				add(head, "CheekGuard", Vector3.new(0.22, H.Y * 0.5, H.Z * 0.45), Vector3.new(side * H.X * 0.47, headY - H.Y * 0.04, frontZ * 0.5), BRONZE, metal)
			end
		end
		add(head, "Crack", Vector3.new(0.05, 0.5, 0.05), Vector3.new(H.X * 0.26, capBottom + capHeight * 0.45, frontZ * 1.08), CRACK, smooth, CFrame.Angles(0, 0, math.rad(28)))
		add(head, "Crack", Vector3.new(0.05, 0.32, 0.05), Vector3.new(H.X * 0.33, capBottom + capHeight * 0.25, frontZ * 1.08), CRACK, smooth, CFrame.Angles(0, 0, math.rad(-24)))
		add(head, "Patina", Vector3.new(0.55, 0.3, 0.06), Vector3.new(-H.X * 0.28, capBottom + capHeight * 0.5, frontZ * 1.05), OXIDE, metal)
		add(head, "Patina", Vector3.new(0.3, 0.22, 0.06), Vector3.new(H.X * 0.1, capBottom + capHeight * 0.75, frontZ * 0.95), OXIDE, metal)

		if gear.Helmet == "Crested" or gear.Helmet == "Ornate" then
			local ornate = gear.Helmet == "Ornate"
			add(head, "CrestHolder", Vector3.new(0.4, 0.14, 0.5), Vector3.new(0, capBottom + capHeight + 0.02, 0), if ornate then GOLD else BRONZE, Enum.Material.Metal)
			add(head, "Crest", Vector3.new(0.36, H.Y * (if ornate then 0.42 else 0.3), H.Z * (if ornate then 1.15 else 0.95)), Vector3.new(0, capBottom + capHeight + H.Y * (if ornate then 0.19 else 0.13), 0.05), gear.CrestColor, fabric)
			if ornate then
				for _, side in { -1, 1 } do
					add(head, "Rosette", Vector3.new(0.12, 0.55, 0.55), Vector3.new(side * H.X * 0.57, capBottom + capHeight * 0.3, 0), GOLD, Enum.Material.Metal, nil, CYLINDER)
				end
				add(head, "Dent", Vector3.new(0.45, 0.3, 0.1), Vector3.new(H.X * 0.2, capBottom + capHeight * 0.65, frontZ * 0.98), BRONZE_DARK, metal)
			end
		elseif gear.Helmet == "Damaged" or gear.Helmet == "OpenFace" then
			add(head, "Dent", Vector3.new(0.6, 0.35, 0.1), Vector3.new(-H.X * 0.15, capBottom + capHeight * 0.7, frontZ * 0.98), BRONZE_DARK, metal, CFrame.Angles(0, 0, math.rad(12)))
			add(head, "BigCrack", Vector3.new(0.06, 0.8, 0.05), Vector3.new(-H.X * 0.05, capBottom + capHeight * 0.4, frontZ * 1.09), CRACK, smooth, CFrame.Angles(0, 0, math.rad(-35)))
			if gear.Helmet == "Damaged" then
				add(head, "CrestStub", Vector3.new(0.34, 0.25, 0.5), Vector3.new(0, capBottom + capHeight + 0.08, 0.2), gear.CrestColor, fabric)
			end
		end
	end

	detachGroup = nil

	-- Torso gear
	local beltY = torsoY - T.Y * 0.3
	local beltHeight = if gear.ThickBelt then 0.7 else 0.42
	add(torso, "Belt", Vector3.new(T.X * 0.94, beltHeight, T.Z * 0.98), Vector3.new(0, beltY, 0), LEATHER_DARK, leather, nil, nil, "Head")
	add(torso, "Buckle", Vector3.new(0.15, beltHeight * 1.2, beltHeight * 1.2), Vector3.new(0, beltY, -T.Z * 0.5), if gear.Armor == "Heavy" then GOLD else BRONZE, metal, faceForward, CYLINDER)

	if gear.Armor == "Harness" then
		add(torso, "Strap", Vector3.new(0.32, T.Y * 0.95, 0.1), Vector3.new(0, torsoY + 0.1, -T.Z * 0.47), LEATHER, leather, CFrame.Angles(0, 0, math.rad(38)))
		add(torso, "Phalera", Vector3.new(0.12, 0.55, 0.55), Vector3.new(-T.X * 0.12, torsoY + 0.35, -T.Z * 0.5), BRONZE, metal, faceForward, CYLINDER)
	elseif gear.Armor == "Straps" then
		for _, side in { -1, 1 } do
			add(torso, "Strap", Vector3.new(0.4, T.Y * 0.95, 0.12), Vector3.new(0, torsoY + 0.1, -T.Z * 0.47), LEATHER, leather, CFrame.Angles(0, 0, side * math.rad(36)))
		end
		add(torso, "Phalera", Vector3.new(0.14, 0.75, 0.75), Vector3.new(0, torsoY + 0.15, -T.Z * 0.52), BRONZE, metal, faceForward, CYLINDER)
		add(torso, "Patina", Vector3.new(0.1, 0.35, 0.35), Vector3.new(0.12, torsoY + 0.25, -T.Z * 0.53), OXIDE, metal, faceForward, CYLINDER)
	elseif gear.Armor == "Vest" then
		add(torso, "Vest", Vector3.new(T.X * 1.04, T.Y * 0.62, T.Z * 1.06), Vector3.new(0, torsoY + T.Y * 0.16, 0), LEATHER, leather, nil, nil, "Sphere")
		add(torso, "Lacing", Vector3.new(0.08, T.Y * 0.4, 0.08), Vector3.new(0, torsoY + T.Y * 0.16, -T.Z * 0.53), LEATHER_DARK, leather)
	elseif gear.Armor == "Light" then
		add(torso, "Sash", Vector3.new(0.45, T.Y * 0.95, 0.1), Vector3.new(0, torsoY + 0.1, -T.Z * 0.47), CLOTH, fabric, CFrame.Angles(0, 0, math.rad(-35)))
		add(torso, "ChestDisc", Vector3.new(0.12, 0.6, 0.6), Vector3.new(T.X * 0.15, torsoY + 0.4, -T.Z * 0.5), BRONZE, metal, faceForward, CYLINDER)
		add(torso, "Patina", Vector3.new(0.13, 0.25, 0.25), Vector3.new(T.X * 0.2, torsoY + 0.45, -T.Z * 0.51), OXIDE, metal, faceForward, CYLINDER)
	else -- Heavy bronze cuirass
		add(torso, "Cuirass", Vector3.new(T.X * 1.05, T.Y * 0.72, T.Z * 1.08), Vector3.new(0, torsoY + T.Y * 0.1, 0), BRONZE, metal, nil, nil, "Sphere")
		add(torso, "CuirassTrim", Vector3.new(T.X * 0.98, 0.16, T.Z * 1.0), Vector3.new(0, torsoY - T.Y * 0.18, 0), GOLD, Enum.Material.Metal, nil, nil, "Head")
		add(torso, "Patina", Vector3.new(0.7, 0.4, 0.08), Vector3.new(-T.X * 0.2, torsoY + T.Y * 0.2, -T.Z * 0.54), OXIDE, metal)
		add(torso, "Medallion", Vector3.new(0.12, 0.6, 0.6), Vector3.new(0, torsoY + T.Y * 0.18, -T.Z * 0.55), GOLD, Enum.Material.Metal, faceForward, CYLINDER)
	end

	if gear.Scarf then
		add(torso, "Scarf", Vector3.new(T.X * 0.72, 0.4, T.Z * 0.85), Vector3.new(0, torsoTop - 0.15, 0), CLOTH, fabric, nil, nil, "Head")
		add(torso, "ScarfTail", Vector3.new(0.55, 0.8, 0.1), Vector3.new(-T.X * 0.18, torsoTop - 0.6, -T.Z * 0.42), CLOTH, fabric, CFrame.Angles(0, 0, math.rad(14)))
	end

	-- Gladiator skirt: cloth under layered leather strips (pteruges) with bronze studs
	add(torso, "SkirtCloth", Vector3.new(T.X * 0.88, 0.85, T.Z * 0.88), Vector3.new(0, beltY - 0.5, 0), CLOTH, fabric, nil, nil, "Head")
	for i = 0, 9 do
		local angle = i / 10 * 2 * math.pi
		local offset = Vector3.new(math.sin(angle) * T.X * 0.42, 0, -math.cos(angle) * T.Z * 0.44)
		local position = Vector3.new(offset.X, beltY - 0.55, offset.Z)
		local outward = position + Vector3.new(offset.X, 0, offset.Z)
		local strip = add(torso, "Strip", Vector3.new(0.45, 1.05, 0.1), position, if i % 2 == 0 then LEATHER else LEATHER_DARK, leather, CFrame.lookAt(position, outward).Rotation)
		if i == 0 or i == 1 or i == 9 then
			add(strip, "Stud", Vector3.one * 0.18, position + (outward - position).Unit * 0.08 - Vector3.new(0, 0.3, 0), BRONZE, Enum.Material.Metal, nil, BALL)
		end
	end

	-- Prepared damage details (hidden until the condition state shows them). Stylized only:
	-- dark scratches, cracks and torn cloth; no wounds.
	local front = -T.Z * 0.5
	for i, offset in { Vector3.new(-0.35, 0.35, 0), Vector3.new(0.1, 0.15, 0), Vector3.new(0.45, 0.45, 0) } do
		detail(torso, "Wounded", "Scratch", Vector3.new(0.08, 0.75, 0.06), Vector3.new(offset.X * T.X * 0.5, torsoY + offset.Y, front * 1.02), CRACK, smooth, CFrame.Angles(0, 0, math.rad(25 + i * 8)))
	end
	detail(head, "Wounded", "Scratch", Vector3.new(0.07, 0.5, 0.05), Vector3.new(H.X * 0.3, headY + H.Y * 0.05, frontZ * 0.97), CRACK, smooth, CFrame.Angles(0, 0, math.rad(-30)))
	for i = 0, 3 do
		local angle = (i / 4 + 0.1) * 2 * math.pi
		local position = Vector3.new(math.sin(angle) * T.X * 0.43, beltY - 1.05, -math.cos(angle) * T.Z * 0.45)
		detail(torso, "Wounded", "TornCloth", Vector3.new(0.4, 0.45, 0.08), position, CLOTH:Lerp(Color3.new(0, 0, 0), 0.35), fabric, CFrame.lookAt(position, position + Vector3.new(position.X, 0, position.Z)).Rotation * CFrame.Angles(0, 0, math.rad(45)))
	end
	for _, arm in { rightArm, leftArm } do
		detail(arm, "Wounded", "Scratch", Vector3.new(0.06, 0.6, 0.06), Vector3.new(arm.Position.X / S, armY + 0.1, -Arm.Z * 0.5), CRACK, smooth, CFrame.Angles(0, 0, math.rad(20)))
	end
	detail(torso, "Critical", "BigCrack", Vector3.new(0.1, 1.3, 0.07), Vector3.new(-T.X * 0.1, torsoY, front * 1.04), CRACK, smooth, CFrame.Angles(0, 0, math.rad(-35)))
	detail(torso, "Critical", "BigCrack", Vector3.new(0.08, 0.7, 0.07), Vector3.new(T.X * 0.05, torsoY - 0.35, front * 1.04), CRACK, smooth, CFrame.Angles(0, 0, math.rad(40)))
	detail(head, "Critical", "Crack", Vector3.new(0.06, 0.7, 0.05), Vector3.new(-H.X * 0.15, headY + H.Y * 0.1, frontZ * 0.99), CRACK, smooth, CFrame.Angles(0, 0, math.rad(15)))
	for _, leg in { leftLeg, rightLeg } do
		detail(leg, "Critical", "Scratch", Vector3.new(0.06, 0.6, 0.06), Vector3.new(leg.Position.X / S, Leg.Y * 0.55, -Leg.Z * 0.52), CRACK, smooth, CFrame.Angles(0, 0, math.rad(-25)))
	end

	-- Shoulder armor (detachable per side)
	local function shoulderPlate(arm: BasePart, side: number, size: number)
		detachGroup = if side > 0 then "ShoulderR" else "ShoulderL"
		local x = side * (shoulderX + 0.1)
		add(arm, "ShoulderPlate", Vector3.new(Arm.X * size, 0.5, Arm.Z * size), Vector3.new(x, shoulderY + 0.25, 0), BRONZE, metal, CFrame.Angles(0, 0, -side * math.rad(18)), nil, "Sphere")
		add(arm, "ShoulderPlate", Vector3.new(Arm.X * size * 0.9, 0.42, Arm.Z * size * 0.92), Vector3.new(x + side * 0.25, shoulderY - 0.1, 0), BRONZE_DARK, metal, CFrame.Angles(0, 0, -side * math.rad(30)), nil, "Sphere")
		add(arm, "Patina", Vector3.new(Arm.X * 0.6, 0.12, Arm.Z * 0.5), Vector3.new(x - side * 0.1, shoulderY + 0.48, -0.1), OXIDE, metal, CFrame.Angles(0, 0, -side * math.rad(18)), nil, "Sphere")
		add(arm, "Rivet", Vector3.one * 0.25, Vector3.new(x, shoulderY + 0.2, -Arm.Z * size * 0.45), if gear.Armor == "Heavy" then GOLD else BRONZE, Enum.Material.Metal, nil, BALL)
		detachGroup = nil
	end
	if gear.Shoulders == "Single" then
		shoulderPlate(rightArm, 1, 1.75)
	elseif gear.Shoulders == "HeavyBoth" then
		shoulderPlate(rightArm, 1, 1.9)
		shoulderPlate(leftArm, -1, 1.9)
	else
		detachGroup = "ShoulderR"
		add(rightArm, "ShoulderPad", Vector3.new(Arm.X * 1.3, 0.35, Arm.Z * 1.3), Vector3.new(shoulderX, shoulderY + 0.2, 0), LEATHER, leather, nil, nil, "Sphere")
		detachGroup = nil
	end

	-- Bracers
	for _, arm in { rightArm, leftArm } do
		add(arm, "Bracer", Vector3.new(Arm.X * 1.15, 0.6, Arm.Z * 1.15), Vector3.new(arm.Position.X / S, handY + Arm.X * 0.55, 0), LEATHER, leather, nil, nil, "Head")
	end

	-- Legs: bronze greaves with patina, knee guards, sandals with straps, green toes
	for _, leg in { leftLeg, rightLeg } do
		local x = leg.Position.X / S
		add(leg, "Greave", Vector3.new(Leg.X * 0.85, Leg.Y * 0.42, 0.4), Vector3.new(x, Leg.Y * 0.38, -Leg.Z * 0.42), BRONZE, metal, nil, nil, "Sphere")
		add(leg, "Patina", Vector3.new(Leg.X * 0.3, 0.3, 0.08), Vector3.new(x + 0.1, Leg.Y * 0.32, -Leg.Z * 0.6), OXIDE, metal)
		add(leg, "KneeGuard", Vector3.one * Leg.X * 0.55, Vector3.new(x, Leg.Y * 0.66, -Leg.Z * 0.38), BRONZE_DARK, Enum.Material.Metal, nil, BALL)
		add(leg, "Sole", Vector3.new(Leg.X * 1.15, 0.28, Leg.Z * 1.45), Vector3.new(x, 0.14, -0.2), LEATHER_DARK, leather, nil, nil, "Head")
		for _, y in { 0.35, 0.8 } do
			add(leg, "SandalStrap", Vector3.new(Leg.X * 1.1, 0.14, Leg.Z * 1.1), Vector3.new(x, y, 0), LEATHER, leather, nil, nil, "Head")
		end
		for t = -1, 1 do
			add(leg, "Toe", Vector3.one * 0.3, Vector3.new(x + t * Leg.X * 0.28, 0.38, -Leg.Z * 0.62), SKIN, smooth, nil, BALL)
		end
	end

	-- Weapon in the right hand (points forward while the arm hangs; raised for attacks)
	local hx = shoulderX
	if gear.Weapon == "Gladius" or gear.Weapon == "LargeSword" then
		local k = if gear.Weapon == "LargeSword" then 1.45 else 1
		add(rightArm, "Grip", Vector3.new(0.26, 0.26, 0.8 * k), Vector3.new(hx, handY, -0.15), LEATHER_DARK, leather)
		add(rightArm, "Pommel", Vector3.one * 0.38 * k, Vector3.new(hx, handY, 0.35 * k), if k > 1 then GOLD else BRONZE, Enum.Material.Metal, nil, BALL)
		add(rightArm, "Guard", Vector3.new(0.9 * k, 0.22, 0.22), Vector3.new(hx, handY, -0.62 * k), if k > 1 then GOLD else BRONZE, metal)
		add(rightArm, "Blade", Vector3.new(0.14, 0.42 * k, 2.0 * k), Vector3.new(hx, handY, -0.62 * k - 1.05 * k), STEEL, Enum.Material.Metal)
		add(rightArm, "Tip", Vector3.new(0.14, 0.3 * k, 0.3 * k), Vector3.new(hx, handY, -0.62 * k - 2.1 * k), STEEL, Enum.Material.Metal, CFrame.Angles(math.rad(45), 0, 0))
	elseif gear.Weapon == "Club" then
		add(rightArm, "Shaft", Vector3.new(2.6, 0.5, 0.5), Vector3.new(hx, handY, -1.0), WOOD, Enum.Material.Wood, faceForward, CYLINDER)
		add(rightArm, "ClubHead", Vector3.new(1.8, 1.1, 1.1), Vector3.new(hx, handY, -2.9), WOOD, Enum.Material.Wood, faceForward, CYLINDER)
		for _, z in { -2.3, -3.5 } do
			add(rightArm, "Band", Vector3.new(0.2, 1.18, 1.18), Vector3.new(hx, handY, z), BRONZE, metal, faceForward, CYLINDER)
		end
		add(rightArm, "Stud", Vector3.one * 0.3, Vector3.new(hx, handY + 0.55, -2.9), BRONZE, Enum.Material.Metal, nil, BALL)
		add(rightArm, "Crack", Vector3.new(0.05, 0.05, 0.9), Vector3.new(hx + 0.55, handY + 0.1, -2.9), CRACK, smooth)
	elseif gear.Weapon == "Bow" then
		-- Roman recurve bow in the LEFT hand (vertical), the right hand draws
		local bx, by, bz = -shoulderX, handY, -0.35
		add(leftArm, "BowGrip", Vector3.new(0.22, 0.5, 0.22), Vector3.new(bx, by, bz), LEATHER_DARK, leather)
		for _, dir in { 1, -1 } do
			add(leftArm, "BowLimb", Vector3.new(0.16, 1.5, 0.16), Vector3.new(bx, by + dir * 0.9, bz - 0.25), WOOD, Enum.Material.Wood, CFrame.Angles(math.rad(dir * 18), 0, 0))
			add(leftArm, "BowTip", Vector3.new(0.14, 0.45, 0.14), Vector3.new(bx, by + dir * 1.7, bz - 0.2), BRONZE, metal, CFrame.Angles(math.rad(-dir * 35), 0, 0))
		end
		add(leftArm, "BowString", Vector3.new(0.04, 3.5, 0.04), Vector3.new(bx, by, bz + 0.15), NET, fabric)
		add(rightArm, "DrawGlove", Vector3.one * Arm.X * 0.7, Vector3.new(hx, handY - 0.1, -0.1), LEATHER, leather, nil, BALL)
	else -- Spear (long reach: the visible shaft matches the validated attack range)
		add(rightArm, "Shaft", Vector3.new(5.6, 0.22, 0.22), Vector3.new(hx, handY, -1.9), WOOD, Enum.Material.Wood, faceForward, CYLINDER)
		add(rightArm, "SpearTip", Vector3.new(0.1, 0.5, 0.75), Vector3.new(hx, handY, -4.95), BRONZE, metal, CFrame.Angles(math.rad(45), 0, 0))
		add(rightArm, "Binding", Vector3.one * 0.3, Vector3.new(hx, handY, -4.6), LEATHER_DARK, leather, nil, BALL)
	end

	-- Archer extras: quiver with visible arrows on the back, leather wrist guard on the bow arm
	if gear.Quiver then
		local quiverPos = Vector3.new(T.X * 0.18, torsoY + 0.3, T.Z * 0.55)
		local tilt = CFrame.Angles(0, 0, math.rad(-20))
		add(torso, "Quiver", Vector3.new(0.75, 2.0, 0.75), quiverPos, LEATHER, leather, tilt, nil, "Head")
		add(torso, "QuiverStrap", Vector3.new(0.25, T.Y * 1.05, 0.08), Vector3.new(0, torsoY + 0.1, -T.Z * 0.5), LEATHER_DARK, leather, CFrame.Angles(0, 0, math.rad(32)))
		for i, dx in { -0.18, 0.05, 0.25 } do
			local arrowBase = quiverPos + tilt:VectorToWorldSpace(Vector3.new(dx, 1.2, 0))
			add(torso, "QuiverArrow", Vector3.new(0.08, 0.7, 0.08), arrowBase, WOOD, Enum.Material.Wood, tilt)
			add(torso, "Fletching", Vector3.new(0.05, 0.3, 0.22), arrowBase + tilt:VectorToWorldSpace(Vector3.new(0, 0.4, 0)), if i == 2 then SHIELD_RED else NET, fabric, tilt)
		end
	end
	if gear.WristGuard then
		add(leftArm, "WristGuard", Vector3.new(Arm.X * 1.25, 0.9, Arm.Z * 1.25), Vector3.new(-shoulderX, handY + Arm.X * 0.75, 0), LEATHER_DARK, leather, nil, nil, "Head")
	end

	-- Left hand: shield or folded net
	local guardGlow: PointLight? = nil
	if gear.Shield ~= "None" then
		local diameter = if gear.Shield == "Round" then 2.6 elseif gear.Shield == "Ornate" then 3.0 else 1.5
		local ornate = gear.Shield == "Ornate"
		local center = Vector3.new(-shoulderX - 0.1, armY - 0.2, -Arm.Z * 0.5 - 0.3)
		add(leftArm, "ShieldRim", Vector3.new(0.2, diameter, diameter), center, if ornate then GOLD else BRONZE, metal, faceForward, CYLINDER)
		local face = add(leftArm, "ShieldFace", Vector3.new(0.25, diameter * 0.88, diameter * 0.88), center - Vector3.new(0, 0, 0.06), if ornate then BRONZE else SHIELD_RED, if ornate then Enum.Material.Metal else Enum.Material.WoodPlanks, faceForward, CYLINDER)
		add(leftArm, "ShieldBoss", Vector3.one * diameter * 0.27, center - Vector3.new(0, 0, 0.2), if ornate then GOLD else BRONZE, Enum.Material.Metal, nil, BALL)
		add(leftArm, "Patina", Vector3.new(0.06, diameter * 0.25, diameter * 0.2), center + Vector3.new(diameter * 0.3, diameter * 0.25, -0.12), OXIDE, metal)
		if gear.Shield == "Round" then
			for _, x in { -0.55, 0.55 } do
				add(leftArm, "Plank", Vector3.new(0.05, diameter * 0.78, 0.04), center + Vector3.new(x, 0, -0.2), LEATHER_DARK, Enum.Material.Wood)
			end
		elseif ornate then
			add(leftArm, "ShieldRing", Vector3.new(0.28, diameter * 0.6, diameter * 0.6), center - Vector3.new(0, 0, 0.09), BRONZE_DARK, Enum.Material.Metal, faceForward, CYLINDER)
			for i = 0, 5 do
				local angle = i / 6 * 2 * math.pi
				add(leftArm, "ShieldStud", Vector3.one * 0.2, center + Vector3.new(math.cos(angle) * diameter * 0.37, math.sin(angle) * diameter * 0.37, -0.2), GOLD, Enum.Material.Metal, nil, BALL)
			end
			local glow = Instance.new("PointLight")
			glow.Name = "GuardGlow"
			glow.Color = Color3.fromRGB(255, 220, 120)
			glow.Range = 10
			glow.Brightness = 4
			glow.Enabled = false
			glow.Parent = face
			guardGlow = glow
		end
	end
	if gear.Net then
		local netCenter = Vector3.new(-shoulderX, handY - 0.1, -0.45)
		add(leftArm, "Net", Vector3.new(0.95, 0.75, 0.95), netCenter, NET, fabric, nil, nil, "Sphere")
		for _, rot in { 30, -30 } do
			add(leftArm, "NetCord", Vector3.new(1.0, 0.06, 0.06), netCenter - Vector3.new(0, 0, 0.42), CRACK, fabric, CFrame.Angles(0, 0, math.rad(rot)))
		end
		add(leftArm, "NetWeight", Vector3.one * 0.25, netCenter + Vector3.new(0.3, -0.35, -0.3), Color3.fromRGB(90, 90, 95), Enum.Material.Metal, nil, BALL)
	end

	-- Humanoid (R15 rules: HipHeight = ground to bottom of the root part)
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = legLen * S
	humanoid.MaxHealth = def.Health
	humanoid.Health = def.Health
	humanoid.WalkSpeed = def.WalkSpeed
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	humanoid.Parent = model
	model.PrimaryPart = root

	-- Effects
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

	local puff = Instance.new("ParticleEmitter")
	puff.Name = "DeathPuff"
	puff.Color = ColorSequence.new(Color3.fromRGB(190, 230, 170))
	puff.LightEmission = 0.4
	puff.Size = NumberSequence.new(1.2, 2.5)
	puff.Transparency = NumberSequence.new(0.3, 1)
	puff.Lifetime = NumberRange.new(0.5, 0.8)
	puff.Speed = NumberRange.new(2, 5)
	puff.SpreadAngle = Vector2.new(180, 180)
	puff.Rate = 60
	puff.Enabled = false
	puff.Parent = torso

	return {
		model = model,
		humanoid = humanoid,
		root = root,
		torso = torso,
		head = head,
		leftArm = leftArm,
		rightArm = rightArm,
		leftLeg = leftLeg,
		rightLeg = rightLeg,
		rootJoint = rootJoint,
		rootJointRest = rootJoint.C0,
		rightShoulder = rightShoulder,
		rightShoulderRest = rightShoulder.C0,
		leftShoulder = leftShoulder,
		leftShoulderRest = leftShoulder.C0,
		hitSparks = sparks,
		deathPuff = puff,
		guardGlow = guardGlow,
		visibleParts = visibleParts,
	}
end

return ZombieFactory
