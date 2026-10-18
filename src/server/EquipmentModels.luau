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

-- A weapon trail from the grip to the farthest point of the weapon (enabled only while a strike
-- travels; PlayerCombatService toggles it). Returns nil for tiny models.
function EquipmentModels.addTrail(model: Model, core: BasePart): Trail?
	local tip = Vector3.zero
	for _, child in model:GetDescendants() do
		if child:IsA("Weld") and child.Part0 == core then
			local far = child.C0.Position
			if far.Magnitude > tip.Magnitude then
				tip = far
			end
		end
	end
	if tip.Magnitude < 1 then
		return nil
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailBase"
	a0.Position = tip * 0.35
	a0.Parent = core
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailTip"
	a1.Position = tip
	a1.Parent = core
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.18
	trail.MinLength = 0.05
	trail.FaceCamera = true
	trail.LightEmission = 0.6
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 240, 200))
	trail.Transparency = NumberSequence.new(0.35, 1)
	trail.Enabled = false
	trail.Parent = core
	return trail
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

local function trident(add: AddFn)
	add("Shaft", Vector3.new(0.22, 6.4, 0.22), CFrame.new(0, 1.2, 0), DARK_WOOD, Enum.Material.Wood)
	add("Butt", Vector3.one * 0.3, CFrame.new(0, -2.0, 0), BRONZE, Enum.Material.Metal, BALL)
	add("Collar", Vector3.new(1.3, 0.22, 0.26), CFrame.new(0, 4.45, 0), BRONZE, Enum.Material.Metal)
	for _, x in { -0.55, 0, 0.55 } do
		local length = if x == 0 then 1.5 else 1.15
		add("Prong", Vector3.new(0.14, length, 0.14), CFrame.new(x, 4.55 + length / 2, 0), STEEL, Enum.Material.Metal)
		add("Barb", Vector3.new(0.12, 0.3, 0.12), CFrame.new(x, 4.6 + length, 0) * CFrame.Angles(0, 0, math.rad(45)), STEEL, Enum.Material.Metal)
	end
	add("Grip", Vector3.new(0.3, 0.9, 0.3), CFrame.identity, LEATHER, Enum.Material.Leather)
end

local function hopliteSpear(add: AddFn)
	add("Shaft", Vector3.new(0.2, 7.4, 0.2), CFrame.new(0, 1.6, 0), WOOD, Enum.Material.Wood)
	add("Sauroter", Vector3.new(0.18, 0.7, 0.18), CFrame.new(0, -2.4, 0), BRONZE, Enum.Material.Metal)
	add("Socket", Vector3.new(0.3, 0.5, 0.3), CFrame.new(0, 5.4, 0), BRONZE, Enum.Material.Metal)
	add("Head", Vector3.new(0.5, 1.4, 0.1), CFrame.new(0, 6.3, 0), STEEL, Enum.Material.Metal)
	add("HeadTip", Vector3.new(0.35, 0.35, 0.1), CFrame.new(0, 7.0, 0) * CFrame.Angles(0, 0, math.rad(45)), STEEL, Enum.Material.Metal)
	add("Grip", Vector3.new(0.28, 0.8, 0.28), CFrame.identity, LEATHER, Enum.Material.Leather)
end

local function dagger(add: AddFn)
	add("Grip", Vector3.new(0.24, 0.7, 0.24), CFrame.identity, LEATHER, Enum.Material.Leather)
	add("Pommel", Vector3.one * 0.3, CFrame.new(0, -0.45, 0), BRONZE, Enum.Material.Metal, BALL)
	add("Guard", Vector3.new(0.7, 0.16, 0.24), CFrame.new(0, 0.42, 0), BRONZE, Enum.Material.Metal)
	add("Blade", Vector3.new(0.3, 1.3, 0.1), CFrame.new(0, 1.15, 0), STEEL, Enum.Material.Metal)
	add("Tip", Vector3.new(0.21, 0.21, 0.1), CFrame.new(0, 1.8, 0) * CFrame.Angles(0, 0, math.rad(45)), STEEL, Enum.Material.Metal)
end

local function battleAxe(add: AddFn)
	add("Haft", Vector3.new(0.3, 4.2, 0.3), CFrame.new(0, 1.2, 0), DARK_WOOD, Enum.Material.Wood)
	add("Grip", Vector3.new(0.34, 1.0, 0.34), CFrame.identity, LEATHER, Enum.Material.Leather)
	add("Socket", Vector3.new(0.45, 0.8, 0.45), CFrame.new(0, 3.0, 0), BRONZE, Enum.Material.Metal)
	add("Blade", Vector3.new(1.6, 1.3, 0.14), CFrame.new(0.9, 3.0, 0), STEEL, Enum.Material.Metal)
	add("Edge", Vector3.new(0.2, 1.8, 0.16), CFrame.new(1.7, 3.0, 0), Color3.fromRGB(230, 230, 225), Enum.Material.Metal)
	add("Spike", Vector3.new(0.6, 0.3, 0.14), CFrame.new(-0.5, 3.0, 0), BRONZE, Enum.Material.Metal)
	add("Band", Vector3.new(0.4, 0.15, 0.4), CFrame.new(0, 1.8, 0), BRONZE, Enum.Material.Metal)
end

function EquipmentModels.buildWeapon(id: string): (Model, BasePart)
	return build(id, function(add)
		if id == "LegionSword" then
			sword(add, STEEL, Enum.Material.Metal, 2.7, BRONZE, true)
		elseif id == "HunterBow" then
			bow(add)
		elseif id == "MorningStar" then
			morningStar(add)
		elseif id == "Trident" then
			trident(add)
		elseif id == "HopliteSpear" then
			hopliteSpear(add)
		elseif id == "TwinDaggers" then
			dagger(add)
		elseif id == "BattleAxe" then
			battleAxe(add)
		else -- RustyGladius
			sword(add, RUST, Enum.Material.CorrodedMetal, 2.1, Color3.fromRGB(120, 90, 60), false)
		end
	end)
end

-- The second dagger of the Twin Arena Daggers (left hand, replaces the shield).
function EquipmentModels.buildOffhandDagger(): (Model, BasePart)
	return build("OffhandDagger", dagger)
end

-- Resting pose relative to the hand's grip attachment (+Y forward when the arm hangs).
function EquipmentModels.weaponRestPose(id: string): CFrame
	if id == "HunterBow" or id == "Trident" or id == "HopliteSpear" then
		return CFrame.identity -- pointing forward
	elseif id == "MorningStar" or id == "BattleAxe" then
		return CFrame.Angles(math.rad(20), 0, 0)
	end
	return CFrame.Angles(math.rad(30), 0, 0)
end

-- A thrown net (flat square of cords) for NET AND STRIKE.
function EquipmentModels.buildNet(): BasePart
	local net = newPart("ThrownNet", Vector3.new(3, 0.15, 3), CFrame.identity, Color3.fromRGB(196, 182, 150), Enum.Material.Fabric, nil :: any)
	net.Anchored = true
	net.Transparency = 0.3
	return net
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
		elseif id == "Scutum" then
			-- Tall curved Roman shield: three angled panels, bronze edging, boss and wings motif
			for i, x in { -0.95, 0, 0.95 } do
				local angle = if i == 1 then -18 elseif i == 3 then 18 else 0
				local depth = if i == 2 then 0 else -0.25
				add("Panel", Vector3.new(1.0, 0.25, 4.2), CFrame.new(x, depth, 0) * CFrame.Angles(0, 0, math.rad(angle)), SHIELD_RED, Enum.Material.WoodPlanks)
			end
			for _, z in { -2.1, 2.1 } do
				add("EdgeEnd", Vector3.new(2.9, 0.3, 0.16), CFrame.new(0, -0.05, z), BRONZE, Enum.Material.Metal)
			end
			add("Boss", Vector3.one * 0.85, CFrame.new(0, 0.25, 0), BRONZE, Enum.Material.Metal, BALL)
			add("Spine", Vector3.new(0.2, 0.05, 3.9), CFrame.new(0, 0.15, 0), GOLD, Enum.Material.Metal)
			for _, side in { -1, 1 } do
				add("Wing", Vector3.new(0.7, 0.05, 0.18), CFrame.new(side * 0.55, 0.15, 0.9) * CFrame.Angles(0, side * math.rad(25), 0), GOLD, Enum.Material.Metal)
				add("Wing", Vector3.new(0.7, 0.05, 0.18), CFrame.new(side * 0.55, 0.15, -0.9) * CFrame.Angles(0, -side * math.rad(25), 0), GOLD, Enum.Material.Metal)
			end
		elseif id == "Hoplon" then
			-- Large round bronze-and-wood shield with a wide rim and a geometric band
			add("Rim", Vector3.new(0.3, 3.8, 3.8), DISC, BRONZE, Enum.Material.Metal, CYLINDER)
			add("Face", Vector3.new(0.34, 3.3, 3.3), CFrame.new(0, 0.05, 0) * DISC, Color3.fromRGB(150, 104, 62), Enum.Material.Wood, CYLINDER)
			add("Band", Vector3.new(0.36, 2.5, 2.5), CFrame.new(0, 0.07, 0) * DISC, Color3.fromRGB(40, 50, 90), Enum.Material.Fabric, CYLINDER)
			add("Center", Vector3.new(0.38, 1.9, 1.9), CFrame.new(0, 0.08, 0) * DISC, Color3.fromRGB(150, 104, 62), Enum.Material.Wood, CYLINDER)
			for i = 0, 7 do
				local angle = i / 8 * 2 * math.pi
				add("Meander", Vector3.new(0.25, 0.06, 0.25), CFrame.new(math.cos(angle) * 1.1, 0.27, math.sin(angle) * 1.1), Color3.fromRGB(235, 225, 200), Enum.Material.SmoothPlastic)
			end
			add("Boss", Vector3.one * 0.7, CFrame.new(0, 0.3, 0), BRONZE, Enum.Material.Metal, BALL)
		elseif id == "ParmaEquestris" then
			-- Medium round cavalry shield: cream face, dark-blue ring
			add("Rim", Vector3.new(0.2, 2.7, 2.7), DISC, BRONZE, Enum.Material.Metal, CYLINDER)
			add("Face", Vector3.new(0.24, 2.4, 2.4), CFrame.new(0, 0.05, 0) * DISC, Color3.fromRGB(235, 225, 200), Enum.Material.Wood, CYLINDER)
			add("Ring", Vector3.new(0.26, 1.6, 1.6), CFrame.new(0, 0.06, 0) * DISC, Color3.fromRGB(40, 50, 90), Enum.Material.Fabric, CYLINDER)
			add("Inner", Vector3.new(0.28, 1.2, 1.2), CFrame.new(0, 0.07, 0) * DISC, Color3.fromRGB(235, 225, 200), Enum.Material.Wood, CYLINDER)
			add("Boss", Vector3.one * 0.55, CFrame.new(0, 0.22, 0), BRONZE, Enum.Material.Metal, BALL)
		elseif id == "ThraexShield" then
			-- Small, high rectangular gladiator shield (parmula-like), weathered bronze trim
			add("Body", Vector3.new(1.7, 0.25, 2.5), CFrame.identity, Color3.fromRGB(40, 50, 90), Enum.Material.Wood)
			for _, x in { -0.85, 0.85 } do
				add("EdgeSide", Vector3.new(0.14, 0.3, 2.55), CFrame.new(x, 0.02, 0), Color3.fromRGB(140, 120, 80), Enum.Material.CorrodedMetal)
			end
			for _, z in { -1.25, 1.25 } do
				add("EdgeEnd", Vector3.new(1.85, 0.3, 0.14), CFrame.new(0, 0.02, z), Color3.fromRGB(140, 120, 80), Enum.Material.CorrodedMetal)
			end
			add("Diamond", Vector3.new(0.7, 0.05, 0.7), CFrame.new(0, 0.15, 0) * CFrame.Angles(0, math.rad(45), 0), Color3.fromRGB(235, 225, 200), Enum.Material.SmoothPlastic)
			add("Boss", Vector3.one * 0.45, CFrame.new(0, 0.2, 0), BRONZE, Enum.Material.Metal, BALL)
		else -- WoodenBuckler
			roundShield(add, 2.0, Color3.fromRGB(150, 104, 62), Enum.Material.Wood, true)
		end
	end)
end

------------------------------------------------------------------------------------------
-- Armor (ArmorDefinitions): pieces welded to the body's limbs. Works on R15 characters, on R6
-- (mapped onto the six R6 limbs) and on the armory mannequins (R15 limb names). No helmet, so
-- the face and avatar stay visible. Cloth pieces carry the "TeamCloth" attribute: Team Battle
-- recolors them (PlayerCombatService.applyTeamColor).
------------------------------------------------------------------------------------------

local CREAM = Color3.fromRGB(226, 214, 186)
local DARK_RED = Color3.fromRGB(104, 26, 28)
local DEEP_RED = Color3.fromRGB(128, 24, 30)
local WORN_BRONZE = Color3.fromRGB(150, 108, 58)
local LIGHT_LEATHER = Color3.fromRGB(122, 82, 48)

type Region = { limb: BasePart, offset: CFrame, size: Vector3 }
type PieceFn = (size: Vector3) -> (Vector3, CFrame)
type PieceOptions = { shape: Enum.PartType?, teamCloth: boolean? }

-- R15 limb name -> (R6 limb, centre as share of its height, share of its height)
local R6_REGIONS: { [string]: { any } } = {
	UpperTorso = { "Torso", 0.2, 0.6 },
	LowerTorso = { "Torso", -0.4, 0.2 },
	LeftUpperArm = { "Left Arm", 0.25, 0.5 },
	LeftLowerArm = { "Left Arm", -0.22, 0.45 },
	RightUpperArm = { "Right Arm", 0.25, 0.5 },
	RightLowerArm = { "Right Arm", -0.22, 0.45 },
	LeftUpperLeg = { "Left Leg", 0.25, 0.5 },
	LeftLowerLeg = { "Left Leg", -0.25, 0.5 },
	RightUpperLeg = { "Right Leg", 0.25, 0.5 },
	RightLowerLeg = { "Right Leg", -0.25, 0.5 },
}

local function region(body: Model, name: string): Region?
	local limb = body:FindFirstChild(name)
	if limb and limb:IsA("BasePart") then
		return { limb = limb, offset = CFrame.identity, size = limb.Size }
	end
	local r6 = R6_REGIONS[name]
	local r6Limb = r6 and body:FindFirstChild(r6[1])
	if r6Limb and r6Limb:IsA("BasePart") then
		local s = r6Limb.Size
		return { limb = r6Limb, offset = CFrame.new(0, s.Y * r6[2], 0), size = Vector3.new(s.X, s.Y * r6[3], s.Z) }
	end
	return nil
end

function EquipmentModels.buildArmor(id: string, body: Model): Model
	local model = Instance.new("Model")
	model.Name = "Armor_" .. id
	model:SetAttribute("ArmorId", id)

	local function put(limbName: string, name: string, color: Color3, material: Enum.Material, fn: PieceFn, options: PieceOptions?)
		local r = region(body, limbName)
		if not r then
			return
		end
		local size, offset = fn(r.size)
		local c0 = r.offset * offset
		local part = newPart(name, size, r.limb.CFrame * c0, color, material, model, options and options.shape)
		if options and options.teamCloth then
			part:SetAttribute("TeamCloth", true)
			part:SetAttribute("DefaultColor", color)
		end
		local weld = Instance.new("Weld")
		weld.Part0 = r.limb
		weld.Part1 = part
		weld.C0 = c0
		weld.Parent = part
	end

	-- Reusable pieces --------------------------------------------------------------------
	local function bands(limbs: { string }, name: string, color: Color3, material: Enum.Material, yShare: number, hShare: number, grow: number)
		for _, limb in limbs do
			put(limb, name, color, material, function(s)
				return Vector3.new(s.X * grow, s.Y * hShare, s.Z * grow), CFrame.new(0, s.Y * yShare, 0)
			end)
		end
	end
	local function straps(color: Color3)
		for _, z in { -1, 1 } do
			for _, angle in { 38, -38 } do
				put("UpperTorso", "ChestStrap", color, Enum.Material.Leather, function(s)
					return Vector3.new(0.32, s.Y * 1.25, 0.08), CFrame.new(0, 0, z * (s.Z / 2 + 0.04)) * CFrame.Angles(0, 0, math.rad(angle))
				end)
			end
		end
	end
	local function belt(color: Color3, material: Enum.Material, buckle: Color3)
		put("LowerTorso", "Belt", color, material, function(s)
			return Vector3.new(s.X * 1.06, math.max(0.3, s.Y * 0.8), s.Z * 1.08), CFrame.new(0, s.Y * 0.2, 0)
		end)
		put("LowerTorso", "Buckle", buckle, Enum.Material.Metal, function(s)
			return Vector3.new(0.4, 0.3, 0.08), CFrame.new(0, s.Y * 0.2, -s.Z * 0.54 - 0.04)
		end)
	end
	local function plate(limb: string, name: string, color: Color3, material: Enum.Material, width: number, height: number, y: number, front: boolean)
		local side = if front then -1 else 1
		put(limb, name, color, material, function(s)
			return Vector3.new(s.X * width, s.Y * height, 0.16), CFrame.new(0, s.Y * y, side * (s.Z / 2 + 0.08))
		end)
	end
	local function shoulder(limb: string, color: Color3, material: Enum.Material, scale: number, layer: number)
		local side = if limb:find("Left") then -1 else 1
		put(limb, "Shoulder", color, material, function(s)
			return Vector3.new(s.X * 1.3 * scale, 0.26, s.Z * 1.3 * scale),
				CFrame.new(side * s.X * 0.12, s.Y * 0.5 - 0.05 - layer * 0.3, 0) * CFrame.Angles(0, 0, math.rad(side * -(14 + layer * 8)))
		end)
	end
	local function skirt(color: Color3, material: Enum.Material, length: number, row: number, teamCloth: boolean?)
		local drop = row * 0.28
		for _, z in { -1, 1 } do
			for _, x in { -0.62, -0.21, 0.21, 0.62 } do
				put("LowerTorso", "Pteryx", color, material, function(s)
					return Vector3.new(s.X * 0.19, length, 0.08),
						CFrame.new(x * s.X * 0.5 * 1.25, -s.Y / 2 - length / 2 + 0.15 - drop, z * (s.Z / 2 + 0.05 + row * 0.03))
				end, { teamCloth = teamCloth })
			end
		end
		for _, x in { -1, 1 } do
			for _, z in { -0.25, 0.25 } do
				put("LowerTorso", "Pteryx", color, material, function(s)
					return Vector3.new(0.08, length * 0.9, s.Z * 0.42), CFrame.new(x * (s.X / 2 + 0.05 + row * 0.03), -s.Y / 2 - length * 0.45 + 0.15 - drop, z * s.Z)
				end, { teamCloth = teamCloth })
			end
		end
	end
	local function loinCloth(color: Color3, length: number)
		put("LowerTorso", "LoinCloth", color, Enum.Material.Fabric, function(s)
			return Vector3.new(s.X * 0.45, length, 0.06), CFrame.new(0, -s.Y / 2 - length / 2 + 0.2, -s.Z / 2 - 0.1)
		end, { teamCloth = true })
	end
	local function greaves(color: Color3, material: Enum.Material, rim: Color3?)
		for _, limb in { "LeftLowerLeg", "RightLowerLeg" } do
			put(limb, "Greave", color, material, function(s)
				return Vector3.new(s.X * 0.9, s.Y * 0.62, 0.16), CFrame.new(0, s.Y * 0.05, -s.Z / 2 - 0.06)
			end)
			if rim then
				put(limb, "GreaveRim", rim, Enum.Material.Metal, function(s)
					return Vector3.new(s.X * 0.95, 0.12, 0.18), CFrame.new(0, s.Y * 0.36, -s.Z / 2 - 0.07)
				end)
			end
		end
	end
	local function sash(color: Color3)
		put("UpperTorso", "Sash", color, Enum.Material.Fabric, function(s)
			return Vector3.new(0.4, s.Y * 1.2, s.Z * 1.12), CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.rad(-34))
		end, { teamCloth = true })
	end
	local function cape(color: Color3)
		put("UpperTorso", "Cape", color, Enum.Material.Fabric, function(s)
			return Vector3.new(s.X * 0.9, s.Y * 1.5, 0.08), CFrame.new(0, -s.Y * 0.3, s.Z / 2 + 0.22) * CFrame.Angles(math.rad(-6), 0, 0)
		end, { teamCloth = true })
	end

	-- Sets --------------------------------------------------------------------------------
	if id == "MurmilloArmor" then
		plate("UpperTorso", "LeatherCuirass", LIGHT_LEATHER, Enum.Material.Leather, 0.92, 0.85, 0.02, true)
		for _, x in { -0.3, 0, 0.3 } do
			put("UpperTorso", "Stud", BRONZE, Enum.Material.Metal, function(s)
				return Vector3.one * 0.18, CFrame.new(x * s.X, s.Y * 0.1, -s.Z / 2 - 0.17)
			end, { shape = BALL })
		end
		straps(LEATHER)
		shoulder("RightUpperArm", BRONZE, Enum.Material.Metal, 1.2, 0)
		bands({ "RightUpperArm" }, "Manica", LIGHT_LEATHER, Enum.Material.Leather, -0.1, 0.6, 1.08)
		bands({ "LeftLowerArm", "RightLowerArm" }, "Bracer", BRONZE, Enum.Material.Metal, -0.05, 0.55, 1.1)
		belt(BRONZE, Enum.Material.Metal, GOLD)
		loinCloth(DARK_RED, 1.0)
		skirt(DARK_RED, Enum.Material.Fabric, 0.7, 0, true)
		greaves(BRONZE, Enum.Material.Metal, nil)
	elseif id == "HopliteBronze" then
		plate("UpperTorso", "Cuirass", BRONZE, Enum.Material.Metal, 1.0, 0.95, 0, true)
		plate("UpperTorso", "Backplate", BRONZE, Enum.Material.Metal, 1.0, 0.95, 0, false)
		put("UpperTorso", "Pecs", Color3.fromRGB(196, 142, 70), Enum.Material.Metal, function(s)
			return Vector3.new(s.X * 0.7, s.Y * 0.08, 0.06), CFrame.new(0, s.Y * 0.05, -s.Z / 2 - 0.19)
		end)
		bands({ "LowerTorso" }, "AbdomenBand", BRONZE, Enum.Material.Metal, 0.2, 0.9, 1.1)
		skirt(CREAM, Enum.Material.Fabric, 0.95, 0, false)
		skirt(LEATHER, Enum.Material.Leather, 0.7, 1, false)
		shoulder("LeftUpperArm", BRONZE, Enum.Material.Metal, 1.1, 0)
		shoulder("RightUpperArm", BRONZE, Enum.Material.Metal, 1.1, 0)
		bands({ "LeftLowerArm", "RightLowerArm" }, "Bracer", LEATHER, Enum.Material.Leather, -0.05, 0.5, 1.08)
		greaves(BRONZE, Enum.Material.Metal, nil)
		cape(DEEP_RED)
	elseif id == "ChampionArmor" then
		plate("UpperTorso", "Cuirass", WORN_BRONZE, Enum.Material.Metal, 1.02, 0.98, 0, true)
		plate("UpperTorso", "Backplate", WORN_BRONZE, Enum.Material.Metal, 1.02, 0.98, 0, false)
		for _, y in { 0.42, -0.42 } do
			put("UpperTorso", "GoldTrim", GOLD, Enum.Material.Metal, function(s)
				return Vector3.new(s.X * 1.03, 0.1, 0.1), CFrame.new(0, s.Y * y, -s.Z / 2 - 0.18)
			end)
		end
		put("UpperTorso", "Medallion", GOLD, Enum.Material.Metal, function(s)
			return Vector3.new(0.12, 0.5, 0.5), CFrame.new(0, s.Y * 0.08, -s.Z / 2 - 0.2) * CFrame.Angles(0, math.rad(90), 0)
		end, { shape = CYLINDER })
		put("UpperTorso", "BattleScar", Color3.fromRGB(110, 82, 50), Enum.Material.CorrodedMetal, function(s)
			return Vector3.new(0.5, 0.08, 0.06), CFrame.new(s.X * 0.22, -s.Y * 0.18, -s.Z / 2 - 0.18) * CFrame.Angles(0, 0, math.rad(25))
		end)
		for _, limb in { "LeftUpperArm", "RightUpperArm" } do
			shoulder(limb, WORN_BRONZE, Enum.Material.Metal, 1.35, 0)
			shoulder(limb, GOLD, Enum.Material.Metal, 1.15, 1)
		end
		belt(GOLD, Enum.Material.Metal, DEEP_RED)
		skirt(DEEP_RED, Enum.Material.Fabric, 1.0, 0, true)
		skirt(LEATHER, Enum.Material.Leather, 0.8, 1, false)
		bands({ "LeftLowerArm", "RightLowerArm" }, "Bracer", WORN_BRONZE, Enum.Material.Metal, -0.05, 0.6, 1.12)
		bands({ "LeftLowerArm", "RightLowerArm" }, "BracerRim", GOLD, Enum.Material.Metal, 0.25, 0.08, 1.16)
		greaves(WORN_BRONZE, Enum.Material.Metal, GOLD)
		cape(DEEP_RED)
	else -- RecruitLeather
		straps(LEATHER)
		belt(LEATHER, Enum.Material.Leather, BRONZE)
		bands({ "LeftLowerArm", "RightLowerArm" }, "Bracer", LIGHT_LEATHER, Enum.Material.Leather, -0.1, 0.45, 1.08)
		put("LeftUpperArm", "ShoulderPad", LEATHER, Enum.Material.Leather, function(s)
			return Vector3.new(s.X * 1.15, 0.22, s.Z * 1.15), CFrame.new(-s.X * 0.08, s.Y * 0.45, 0) * CFrame.Angles(0, 0, math.rad(14))
		end)
		loinCloth(DARK_RED, 0.9)
		sash(DARK_RED)
	end
	return model
end

return EquipmentModels
