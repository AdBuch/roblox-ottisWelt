--!strict
-- Procedural models for all weapons and shields, used both in the player's hands and on the
-- shop displays. Each model is built around a small "Core" part at the origin; every other
-- part is welded to it (rigid, no free physics).
--   Weapons: grip at the origin, blade/arrow direction along +Y, bow limbs along ±Z.
--   Shields: face normal along +Y, width along X, height along Z.

local EquipmentModels = {}

local BRONZE = Color3.fromRGB(176, 125, 60)
local GOLD = Color3.fromRGB(235, 190, 80)
local LEATHER = Color3.fromRGB(74, 46, 26)
local WOOD = Color3.fromRGB(120, 80, 46)
local DARK_WOOD = Color3.fromRGB(84, 54, 32)
local STEEL = Color3.fromRGB(205, 205, 200)
local RUST = Color3.fromRGB(150, 108, 78)
local IRON = Color3.fromRGB(80, 80, 84)
local SHIELD_RED = Color3.fromRGB(140, 34, 30)
local PLANK_LINE = Color3.fromRGB(80, 30, 22)

local CYLINDER = Enum.PartType.Cylinder
local BALL = Enum.PartType.Ball
local DISC = CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis X -> Y (a disc facing +Y)

type AddFn = (name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?) -> Part

local function newPart(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, parent: Instance, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		part.Shape = shape
	end
	part.Parent = parent
	return part
end

local function build(name: string, body: (add: AddFn) -> ()): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = name
	local core = newPart("Core", Vector3.new(0.25, 0.25, 0.25), CFrame.identity, LEATHER, Enum.Material.Leather, model)
	core.Transparency = 1
	local function add(partName: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
		local part = newPart(partName, size, cframe, color, material, model, shape)
		local weld = Instance.new("Weld")
		weld.Part0 = core
		weld.Part1 = part
		weld.C0 = cframe
		weld.Parent = part
		return part
	end
	body(add)
	model.PrimaryPart = core
	return model, core
end

-- Connects two points with a thin part (for bow limbs, chains, ...).
local function segment(add: AddFn, name: string, a: Vector3, b: Vector3, thickness: number, color: Color3, material: Enum.Material)
	local length = (b - a).Magnitude
	add(name, Vector3.new(thickness, thickness, length), CFrame.lookAt((a + b) / 2, b), color, material)
end

------------------------------------------------------------------------------------------
-- Weapons
------------------------------------------------------------------------------------------

local function sword(add: AddFn, bladeColor: Color3, bladeMaterial: Enum.Material, bladeLength: number, guardColor: Color3, fancy: boolean)
	add("Grip", Vector3.new(0.28, 1.0, 0.28), CFrame.identity, LEATHER, Enum.Material.Leather)
	add("Pommel", Vector3.one * 0.42, CFrame.new(0, -0.62, 0), if fancy then GOLD else guardColor, Enum.Material.Metal, BALL)
	add("Guard", Vector3.new(1.15, 0.22, 0.36), CFrame.new(0, 0.6, 0), guardColor, Enum.Material.Metal)
	add("Blade", Vector3.new(0.4, bladeLength, 0.12), CFrame.new(0, 0.7 + bladeLength / 2, 0), bladeColor, bladeMaterial)
	add("Tip", Vector3.new(0.28, 0.28, 0.12), CFrame.new(0, 0.7 + bladeLength, 0) * CFrame.Angles(0, 0, math.rad(45)), bladeColor, bladeMaterial)
	if fancy then
		add("Fuller", Vector3.new(0.08, bladeLength * 0.8, 0.13), CFrame.new(0, 0.7 + bladeLength * 0.45, 0), GOLD, Enum.Material.Metal)
		add("GuardGem", Vector3.one * 0.22, CFrame.new(0, 0.6, -0.15), Color3.fromRGB(170, 30, 40), Enum.Material.Glass, BALL)
	else
		add("Notch", Vector3.new(0.12, 0.2, 0.13), CFrame.new(0.15, 0.7 + bladeLength * 0.6, 0), Color3.fromRGB(90, 60, 40), Enum.Material.CorrodedMetal)
	end
end

local function bow(add: AddFn)
	add("Grip", Vector3.new(0.3, 0.3, 0.9), CFrame.identity, LEATHER, Enum.Material.Leather)
	-- Curved limbs: points along ±Z bending back (-Y)
	local points = { Vector3.new(0, 0, 0.4), Vector3.new(0, -0.08, 1.1), Vector3.new(0, -0.3, 1.8), Vector3.new(0, -0.65, 2.4) }
	for _, side in { 1, -1 } do
		for i = 1, #points - 1 do
			local a, b = points[i], points[i + 1]
			segment(add, "Limb", Vector3.new(a.X, a.Y, a.Z * side), Vector3.new(b.X, b.Y, b.Z * side), 0.22, WOOD, Enum.Material.Wood)
		end
		add("Nock", Vector3.one * 0.2, CFrame.new(0, -0.65, 2.4 * side), BRONZE, Enum.Material.Metal, BALL)
	end
	add("String", Vector3.new(0.05, 0.05, 4.8), CFrame.new(0, -0.65, 0), Color3.fromRGB(235, 230, 215), Enum.Material.Fabric)
	add("Wrap", Vector3.new(0.34, 0.34, 0.3), CFrame.new(0, 0, 0.3), BRONZE, Enum.Material.Metal)
	add("Wrap", Vector3.new(0.34, 0.34, 0.3), CFrame.new(0, 0, -0.3), BRONZE, Enum.Material.Metal)
end

local function morningStar(add: AddFn)
	add("Handle", Vector3.new(0.32, 1.8, 0.32), CFrame.new(0, 0.3, 0), DARK_WOOD, Enum.Material.Wood)
	add("Pommel", Vector3.one * 0.42, CFrame.new(0, -0.65, 0), BRONZE, Enum.Material.Metal, BALL)
	add("Cap", Vector3.new(0.5, 0.25, 0.5), CFrame.new(0, 1.25, 0), BRONZE, Enum.Material.Metal)
	for i = 1, 4 do
		add("Link", Vector3.new(0.12, 0.34, 0.24), CFrame.new(0, 1.35 + i * 0.3, 0) * CFrame.Angles(0, if i % 2 == 0 then math.rad(90) else 0, 0), IRON, Enum.Material.Metal)
	end
	local center = Vector3.new(0, 3.2, 0)
	add("Ball", Vector3.one * 1.15, CFrame.new(center), IRON, Enum.Material.Metal, BALL)
	local directions = {
		Vector3.xAxis, -Vector3.xAxis, Vector3.yAxis, Vector3.zAxis, -Vector3.zAxis,
		Vector3.new(1, 1, 0).Unit, Vector3.new(-1, 1, 0).Unit, Vector3.new(0, 1, 1).Unit, Vector3.new(0, 1, -1).Unit,
		Vector3.new(1, -0.5, 1).Unit, Vector3.new(-1, -0.5, -1).Unit,
	}
	for _, direction in directions do
		local tip = center + direction * 0.85
		add("Spike", Vector3.new(0.16, 0.16, 0.45), CFrame.lookAt(tip, tip + direction), Color3.fromRGB(150, 150, 150), Enum.Material.Metal)
	end
end

function EquipmentModels.buildWeapon(id: string): (Model, BasePart)
	return build(id, function(add)
		if id == "LegionSword" then
			sword(add, STEEL, Enum.Material.Metal, 2.7, BRONZE, true)
		elseif id == "HunterBow" then
			bow(add)
		elseif id == "MorningStar" then
			morningStar(add)
		else -- RustyGladius
			sword(add, RUST, Enum.Material.CorrodedMetal, 2.1, Color3.fromRGB(120, 90, 60), false)
		end
	end)
end

-- Resting pose relative to the hand's grip attachment (+Y forward when the arm hangs).
function EquipmentModels.weaponRestPose(id: string): CFrame
	if id == "HunterBow" then
		return CFrame.identity -- limbs vertical, arrow forward
	elseif id == "MorningStar" then
		return CFrame.Angles(math.rad(20), 0, 0)
	end
	return CFrame.Angles(math.rad(30), 0, 0)
end

-- A single arrow (shaft along -Z so CFrame.lookAt points it at the target).
function EquipmentModels.buildArrow(): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "Arrow"
	local shaft = newPart("Shaft", Vector3.new(0.16, 0.16, 2.6), CFrame.identity, WOOD, Enum.Material.Wood, model)
	shaft.Anchored = true
	local function welded(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material)
		local part = newPart(name, size, offset, color, material, model)
		local weld = Instance.new("Weld")
		weld.Part0 = shaft
		weld.Part1 = part
		weld.C0 = offset
		weld.Parent = part
	end
	welded("Tip", Vector3.new(0.3, 0.3, 0.5), CFrame.new(0, 0, -1.5) * CFrame.Angles(0, 0, math.rad(45)), BRONZE, Enum.Material.Metal)
	welded("Fletch", Vector3.new(0.05, 0.4, 0.6), CFrame.new(0, 0.12, 1.1), Color3.fromRGB(200, 40, 40), Enum.Material.Fabric)
	welded("Fletch", Vector3.new(0.4, 0.05, 0.6), CFrame.new(0.12, 0, 1.1), Color3.fromRGB(200, 40, 40), Enum.Material.Fabric)

	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.08, 1.2)
	a0.Parent = shaft
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.08, 1.2)
	a1.Parent = shaft
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.2
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 240, 200))
	trail.Transparency = NumberSequence.new(0.3, 1)
	trail.Parent = shaft

	model.PrimaryPart = shaft
	return model, shaft
end

------------------------------------------------------------------------------------------
-- Shields
------------------------------------------------------------------------------------------

local function roundShield(add: AddFn, diameter: number, faceColor: Color3, faceMaterial: Enum.Material, planks: boolean)
	add("Rim", Vector3.new(0.22, diameter, diameter), DISC, BRONZE, Enum.Material.Metal, CYLINDER)
	add("Face", Vector3.new(0.26, diameter * 0.88, diameter * 0.88), CFrame.new(0, 0.05, 0) * DISC, faceColor, faceMaterial, CYLINDER)
	add("Boss", Vector3.one * diameter * 0.26, CFrame.new(0, 0.22, 0), BRONZE, Enum.Material.Metal, BALL)
	if planks then
		for _, x in { -diameter * 0.22, diameter * 0.22 } do
			add("Plank", Vector3.new(0.05, 0.04, diameter * 0.78), CFrame.new(x, 0.19, 0), PLANK_LINE, Enum.Material.Wood)
		end
	end
end

function EquipmentModels.buildShield(id: string): (Model, BasePart)
	return build(id, function(add)
		if id == "LegionShield" then
			roundShield(add, 3.2, SHIELD_RED, Enum.Material.WoodPlanks, true)
		elseif id == "TowerShield" then
			-- Tall rectangular gladiator shield
			add("Body", Vector3.new(2.6, 0.3, 3.8), CFrame.identity, SHIELD_RED, Enum.Material.WoodPlanks)
			for _, x in { -1.3, 1.3 } do
				add("EdgeSide", Vector3.new(0.18, 0.36, 3.85), CFrame.new(x, 0.02, 0), BRONZE, Enum.Material.Metal)
			end
			for _, z in { -1.9, 1.9 } do
				add("EdgeEnd", Vector3.new(2.75, 0.36, 0.18), CFrame.new(0, 0.02, z), BRONZE, Enum.Material.Metal)
			end
			add("Boss", Vector3.one * 0.8, CFrame.new(0, 0.25, 0), BRONZE, Enum.Material.Metal, BALL)
			add("Stripe", Vector3.new(0.25, 0.04, 3.4), CFrame.new(0, 0.17, 0), GOLD, Enum.Material.Metal)
			add("Bar", Vector3.new(2.2, 0.04, 0.25), CFrame.new(0, 0.17, 0), GOLD, Enum.Material.Metal)
		elseif id == "ChampionShield" then
			-- Ornate bronze: gold rings, studs and a gold boss
			add("Rim", Vector3.new(0.24, 3.4, 3.4), DISC, GOLD, Enum.Material.Metal, CYLINDER)
			add("Face", Vector3.new(0.28, 3.1, 3.1), CFrame.new(0, 0.05, 0) * DISC, BRONZE, Enum.Material.Metal, CYLINDER)
			add("Ring", Vector3.new(0.3, 2.2, 2.2), CFrame.new(0, 0.07, 0) * DISC, Color3.fromRGB(150, 100, 45), Enum.Material.Metal, CYLINDER)
			add("Inner", Vector3.new(0.32, 1.9, 1.9), CFrame.new(0, 0.08, 0) * DISC, BRONZE, Enum.Material.Metal, CYLINDER)
			add("Boss", Vector3.one * 0.8, CFrame.new(0, 0.3, 0), GOLD, Enum.Material.Metal, BALL)
			for i = 0, 7 do
				local angle = i / 8 * 2 * math.pi
				add("Stud", Vector3.one * 0.22, CFrame.new(math.cos(angle) * 1.3, 0.2, math.sin(angle) * 1.3), GOLD, Enum.Material.Metal, BALL)
			end
		else -- WoodenBuckler
			roundShield(add, 2.0, Color3.fromRGB(150, 104, 62), Enum.Material.Wood, true)
		end
	end)
end

return EquipmentModels
