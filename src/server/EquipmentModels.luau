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
	local model, core = build(id, function(add)
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
	if id == "HunterBow" then
		local nock = Instance.new("Attachment")
		nock.Name = "BowNock"
		nock.Position = Vector3.new(0, -0.65, 0.3)
		nock.Parent = core
		for _, side in { -1, 1 } do
			local tip = Instance.new("Attachment")
			tip.Position = Vector3.new(0, -0.65, 2.4 * side)
			tip.Parent = core
			local string = Instance.new("Beam")
			string.Attachment0, string.Attachment1 = tip, nock
			string.Width0, string.Width1 = 0.04, 0.04
			string.FaceCamera = true
			string.Color = ColorSequence.new(Color3.fromRGB(235, 230, 215))
			string.Parent = core
		end
	end
	return model, core
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

-- Where gear is carried outside combat. "Back" mounts are relative to the UpperTorso (+Z = the
-- back), "Belt" mounts to the LowerTorso. Short blades hang at the right hip (the Roman side, and
-- the right hand reaches it without turning the body); long, heavy and ranged weapons sit
-- diagonally across the back, head over the right shoulder.
export type Mount = "Back" | "Belt"

local function mount(position: Vector3, along: Vector3, side: Vector3): CFrame
	return CFrame.fromMatrix(position, side.Unit, along.Unit)
end

local DIAGONAL = Vector3.new(0.4, 0.92, 0)
local DIAGONAL_SIDE = Vector3.new(0.92, -0.4, 0)
local BACK_DEPTH = 0.85 -- weapon on the back, without a shield
local OVER_SHIELD = 0.32 -- extra depth when a shield sits beneath it
-- Half the length of each back-carried weapon from its grip: the weapon is centred on the back
local BACK_MID: { [string]: number } = { Trident = 1.8, HopliteSpear = 2.2, BattleAxe = 1.5, MorningStar = 0.9, HunterBow = 0 }

function EquipmentModels.stowMount(id: string, overShield: boolean): (Mount, CFrame)
	local mid = BACK_MID[id]
	if mid == nil then
		-- hilt at the right hip, blade down and back
		return "Belt" :: Mount, mount(Vector3.new(1.12, 0.05, 0), Vector3.new(0, -0.82, 0.57), Vector3.new(0, 0.57, 0.82))
	end
	local depth = BACK_DEPTH + (if overShield then OVER_SHIELD else 0)
	if id == "HunterBow" then
		-- limbs (grip Z) diagonal across the back, the bow lying flat on it
		return "Back" :: Mount, CFrame.fromMatrix(Vector3.new(0, 0, depth), Vector3.new(0, 0, 1), Vector3.new(0.707, -0.707, 0))
	end
	return "Back" :: Mount, mount(Vector3.new(0, -0.2, depth) - DIAGONAL.Unit * mid, DIAGONAL, DIAGONAL_SIDE)
end

-- The second dagger at the left hip.
EquipmentModels.OffhandDaggerMount = mount(Vector3.new(-1.12, 0.05, 0), Vector3.new(0, -0.94, 0.34), Vector3.new(0, 0.34, 0.94))
-- The shield flat on the back, face outward, long side vertical.
EquipmentModels.ShieldBackMount = CFrame.fromMatrix(Vector3.new(0, -0.1, 0.75), Vector3.new(1, 0, 0), Vector3.new(0, 0, 1))

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
-- (mapped onto the six R6 limbs) and on the armory mannequins (R15 limb names). Helmets are separate (buildHelmet).
-- Cloth pieces carry the "TeamCloth" attribute: Team Battle
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

------------------------------------------------------------------------------------------
-- Helmets (HelmetDefinitions): welded to the body's "Head" part (R15, R6 and the mannequins).
-- "NoHelmet" builds nothing. Visual only; the protection is in the damage numbers
-- (PlayerCombatService.armorReduction). Every helmet is drawn in HEAD UNITS (1 = the head's
-- height), the face looks along -Z:
--   Denarii  SpartaHelm, MurmilloHelm (gladiator), ChampionCrest (Roman general)
--   Robux    the three friends (OttiHead, SchiliHead, KrokoHead), animals (DragonHead, RhinoHead,
--            ToroHead, MonkeyHead) and foreign fighters (SamuraiHelm, SoldierHelm, IncaHelm).
--            The animal heads are whole masks over the head.
------------------------------------------------------------------------------------------

local HELM_BRONZE = Color3.fromRGB(176, 125, 60)
local HELM_STEEL = Color3.fromRGB(170, 172, 180)
local HELM_CREST = Color3.fromRGB(150, 32, 36)
local HELM_GOLD = Color3.fromRGB(214, 176, 80)
local HELM_DARK = Color3.fromRGB(30, 28, 30)
local HELM_CREAM = Color3.fromRGB(232, 214, 178)

type HelmPiece = (name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?) -> Part
type HelmBuilder = (piece: HelmPiece) -> ()

local METAL = Enum.Material.Metal
local SMOOTH = Enum.Material.SmoothPlastic
local FABRIC = Enum.Material.Fabric
local FLAT = CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis X -> Y (a lying disc)
local FRONT = CFrame.Angles(0, math.rad(90), 0) -- cylinder axis X -> Z (a disc facing the front)

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end
local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end
local function deg(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

-- two eyes on the front of a mask
local function eyes(piece: HelmPiece, x: number, y: number, z: number, size: number, color: Color3, material: Enum.Material?)
	for _, side in { -1, 1 } do
		piece("Eye", v(size, size, size * 0.6), at(side * x, y, z), color, material or SMOOTH, BALL)
	end
end

local HELMETS: { [string]: HelmBuilder } = {}

-- DENARII ---------------------------------------------------------------------------------

HELMETS.SpartaHelm = function(piece)
	-- Corinthian bronze helm: deep bowl, long cheek plates, nose guard, horsehair crest front to back
	piece("Shell", v(1.22, 0.7, 1.22), at(0, 0.3, 0), HELM_BRONZE, METAL, BALL)
	piece("Bowl", v(1.2, 0.5, 1.2), at(0, 0.12, 0.02), HELM_BRONZE, METAL)
	piece("NeckGuard", v(1.16, 0.5, 0.14), at(0, -0.3, 0.56), HELM_BRONZE, METAL)
	for _, side in { -1, 1 } do
		piece("CheekGuard", v(0.12, 0.75, 0.9), at(side * 0.58, -0.3, 0.1), HELM_BRONZE, METAL)
		piece("CheekFront", v(0.34, 0.7, 0.1), at(side * 0.42, -0.3, -0.6), HELM_BRONZE, METAL)
	end
	piece("NoseGuard", v(0.12, 0.5, 0.1), at(0, -0.12, -0.63), HELM_BRONZE, METAL)
	piece("BrowBand", v(1.24, 0.08, 0.1), at(0, 0.14, -0.62), HELM_GOLD, METAL)
	piece("CrestHolder", v(0.12, 0.14, 1.0), at(0, 0.68, 0.05), HELM_BRONZE, METAL)
	piece("Crest", v(0.16, 0.42, 1.25), at(0, 0.94, 0.12), HELM_CREST, FABRIC)
	piece("CrestTail", v(0.14, 0.5, 0.16), at(0, 0.55, 0.78) * deg(-25, 0, 0), HELM_CREST, FABRIC)
end

HELMETS.MurmilloHelm = function(piece)
	-- Gladiator (murmillo): steel dome, wide brim, grille visor, tall fish crest
	piece("Shell", v(1.2, 0.72, 1.2), at(0, 0.32, 0), HELM_STEEL, METAL, BALL)
	piece("Brim", v(0.08, 1.7, 1.7), at(0, 0.16, 0) * FLAT, HELM_BRONZE, METAL, CYLINDER)
	piece("Visor", v(1.0, 0.62, 0.12), at(0, -0.18, -0.6), HELM_STEEL, METAL)
	for _, x in { -0.3, -0.1, 0.1, 0.3 } do
		piece("Grille", v(0.06, 0.4, 0.13), at(x, -0.12, -0.61), HELM_DARK, METAL)
	end
	for _, side in { -1, 1 } do
		piece("CheekGuard", v(0.12, 0.62, 0.8), at(side * 0.58, -0.18, -0.1), HELM_STEEL, METAL)
	end
	piece("NeckGuard", v(1.1, 0.4, 0.12), at(0, -0.1, 0.6), HELM_STEEL, METAL)
	piece("FishCrest", v(0.14, 0.5, 1.0), at(0, 0.86, 0.05), HELM_BRONZE, METAL)
	piece("FishFin", v(0.12, 0.3, 0.34), at(0, 0.98, 0.56) * deg(-30, 0, 0), HELM_BRONZE, METAL)
end

HELMETS.ChampionCrest = function(piece)
	-- Roman general (legate): gilded dome, cheek guards, neck guard, tall red crest across the head
	piece("Shell", v(1.2, 0.7, 1.2), at(0, 0.32, 0), HELM_GOLD, METAL, BALL)
	piece("BrowBand", v(1.26, 0.14, 1.26), at(0, 0.1, 0), HELM_BRONZE, METAL)
	piece("Peak", v(1.0, 0.08, 0.3), at(0, 0.18, -0.7), HELM_GOLD, METAL)
	for _, side in { -1, 1 } do
		piece("CheekGuard", v(0.1, 0.62, 0.5), at(side * 0.6, -0.25, -0.22), HELM_GOLD, METAL)
		piece("EarStud", v(0.12, 0.2, 0.2), at(side * 0.64, 0.02, 0.1), HELM_BRONZE, METAL, CYLINDER)
	end
	piece("NeckGuard", v(1.3, 0.08, 0.5), at(0, -0.22, 0.72) * deg(-20, 0, 0), HELM_GOLD, METAL)
	piece("CrestHolder", v(1.0, 0.14, 0.14), at(0, 0.68, 0), HELM_BRONZE, METAL)
	piece("Crest", v(1.5, 0.6, 0.2), at(0, 1.0, 0), HELM_CREST, FABRIC)
	piece("Laurel", v(1.28, 0.06, 1.28), at(0, 0.24, 0), Color3.fromRGB(240, 206, 110), METAL)
end

-- ROBUX: the three friends ----------------------------------------------------------------

HELMETS.OttiHead = function(piece)
	local fur, dark = Color3.fromRGB(92, 58, 38), Color3.fromRGB(66, 40, 26)
	piece("Mask", v(1.45, 1.4, 1.45), at(0, 0.08, 0), fur, SMOOTH, BALL)
	piece("Muzzle", v(0.8, 0.6, 0.55), at(0, -0.14, -0.62), HELM_CREAM, SMOOTH, BALL)
	piece("Chin", v(0.9, 0.5, 0.5), at(0, -0.38, -0.42), HELM_CREAM, SMOOTH, BALL)
	piece("Nose", v(0.26, 0.2, 0.2), at(0, 0.02, -0.9), Color3.fromRGB(40, 28, 24), SMOOTH, BALL)
	eyes(piece, 0.34, 0.26, -0.62, 0.2, Color3.fromRGB(26, 18, 14))
	for _, side in { -1, 1 } do
		piece("Ear", v(0.34, 0.34, 0.2), at(side * 0.58, 0.68, 0.05), dark, SMOOTH, BALL)
		for i = -1, 1 do
			piece("Whisker", v(0.5, 0.03, 0.03), at(side * 0.55, -0.16 + i * 0.07, -0.74) * deg(0, side * 20, side * i * 12), Color3.fromRGB(240, 232, 214), SMOOTH)
		end
	end
end

HELMETS.SchiliHead = function(piece)
	local skin, ridge = Color3.fromRGB(126, 140, 90), Color3.fromRGB(92, 104, 64)
	piece("Mask", v(1.4, 1.35, 1.5), at(0, 0.06, -0.02), skin, SMOOTH, BALL)
	piece("Beak", v(0.7, 0.42, 0.5), at(0, -0.2, -0.68), Color3.fromRGB(222, 214, 174), SMOOTH, BALL)
	piece("Brow", v(1.0, 0.16, 0.3), at(0, 0.42, -0.56), ridge, SMOOTH, BALL)
	eyes(piece, 0.4, 0.2, -0.62, 0.22, Color3.fromRGB(64, 41, 25))
	for _, side in { -1, 1 } do
		piece("Nostril", v(0.06, 0.06, 0.06), at(side * 0.1, -0.06, -0.92), HELM_DARK, SMOOTH, BALL)
	end
	-- a piece of the shell at the nape
	piece("Shell", v(1.5, 1.1, 0.7), at(0, 0.05, 0.6), Color3.fromRGB(112, 76, 43), Enum.Material.Wood, BALL)
	for i, x in { -0.4, 0, 0.4 } do
		piece("ShellPlate", v(0.36, 0.4, 0.12), at(x, 0.1, 0.94), if i % 2 == 0 then Color3.fromRGB(184, 131, 63) else Color3.fromRGB(136, 147, 74), Enum.Material.Wood)
	end
end

HELMETS.KrokoHead = function(piece)
	local skin, belly, ridge = Color3.fromRGB(64, 120, 58), Color3.fromRGB(178, 186, 88), Color3.fromRGB(38, 78, 40)
	piece("Mask", v(1.4, 1.3, 1.45), at(0, 0.05, 0), skin, SMOOTH, BALL)
	piece("Snout", v(0.8, 0.3, 1.1), at(0, -0.02, -1.0), skin, SMOOTH)
	piece("SnoutTip", v(0.86, 0.36, 0.4), at(0, 0, -1.5), skin, SMOOTH, BALL)
	piece("Jaw", v(0.72, 0.2, 1.0), at(0, -0.32, -0.95) * deg(8, 0, 0), belly, SMOOTH)
	for _, side in { -1, 1 } do
		piece("EyeBump", v(0.36, 0.36, 0.4), at(side * 0.36, 0.55, -0.4), skin, SMOOTH, BALL)
		piece("Eye", v(0.2, 0.22, 0.12), at(side * 0.38, 0.58, -0.58), Color3.fromRGB(255, 176, 40), Enum.Material.Neon, BALL)
		piece("Nostril", v(0.1, 0.1, 0.1), at(side * 0.2, 0.18, -1.56), ridge, SMOOTH, BALL)
		for i = 0, 3 do
			piece("Tooth", v(0.08, 0.14, 0.08), at(side * 0.36, -0.2, -0.62 - i * 0.26), HELM_CREAM, SMOOTH)
		end
	end
	for i = 0, 3 do
		piece("Scute", v(0.16, 0.18, 0.22), at(0, 0.68 - i * 0.06, 0.05 + i * 0.26) * deg(-20, 0, 0), ridge, SMOOTH)
	end
end

-- ROBUX: animals --------------------------------------------------------------------------

HELMETS.DragonHead = function(piece)
	local red, dark, horn = Color3.fromRGB(170, 34, 30), Color3.fromRGB(96, 18, 22), Color3.fromRGB(236, 224, 196)
	piece("Mask", v(1.42, 1.34, 1.46), at(0, 0.06, 0), red, SMOOTH, BALL)
	piece("Snout", v(0.74, 0.44, 0.9), at(0, -0.08, -0.9), red, SMOOTH)
	piece("SnoutTip", v(0.8, 0.5, 0.4), at(0, -0.06, -1.32), red, SMOOTH, BALL)
	piece("Jaw", v(0.66, 0.16, 0.8), at(0, -0.4, -0.85) * deg(10, 0, 0), dark, SMOOTH)
	piece("Brow", v(1.1, 0.2, 0.3), at(0, 0.44, -0.56) * deg(15, 0, 0), dark, SMOOTH)
	eyes(piece, 0.36, 0.28, -0.66, 0.2, Color3.fromRGB(255, 150, 30), Enum.Material.Neon)
	for _, side in { -1, 1 } do
		piece("Horn", v(0.2, 0.9, 0.2), at(side * 0.42, 0.95, 0.4) * deg(-40, 0, -side * 12), horn, SMOOTH)
		piece("HornTip", v(0.12, 0.5, 0.12), at(side * 0.5, 1.4, 0.92) * deg(-60, 0, -side * 12), horn, SMOOTH)
		piece("Nostril", v(0.12, 0.1, 0.12), at(side * 0.2, 0.2, -1.36), Color3.fromRGB(255, 120, 40), Enum.Material.Neon, BALL)
		piece("Frill", v(0.06, 0.6, 0.5), at(side * 0.74, 0.0, 0.3) * deg(0, side * 25, 0), dark, SMOOTH)
		for i = 0, 2 do
			piece("Fang", v(0.08, 0.2, 0.08), at(side * 0.32, -0.28, -0.7 - i * 0.26), horn, SMOOTH)
		end
	end
	for i = 0, 4 do
		piece("Spine", v(0.1, 0.32 - i * 0.03, 0.2), at(0, 0.78 - i * 0.1, -0.2 + i * 0.26) * deg(-25, 0, 0), dark, SMOOTH)
	end
end

HELMETS.RhinoHead = function(piece)
	local grey, dark, horn = Color3.fromRGB(128, 130, 134), Color3.fromRGB(92, 94, 98), Color3.fromRGB(226, 216, 196)
	piece("Mask", v(1.45, 1.36, 1.46), at(0, 0.05, 0), grey, Enum.Material.Slate, BALL)
	piece("Snout", v(0.86, 0.6, 1.0), at(0, -0.16, -0.9), grey, Enum.Material.Slate)
	piece("SnoutTip", v(0.9, 0.62, 0.44), at(0, -0.18, -1.38), dark, Enum.Material.Slate, BALL)
	piece("HornBase", v(0.34, 0.4, 0.34), at(0, 0.24, -1.26), horn, SMOOTH, BALL)
	piece("Horn", v(0.24, 0.7, 0.24), at(0, 0.6, -1.32) * deg(12, 0, 0), horn, SMOOTH)
	piece("HornTip", v(0.14, 0.36, 0.14), at(0, 1.02, -1.26) * deg(-8, 0, 0), horn, SMOOTH)
	piece("SmallHorn", v(0.2, 0.36, 0.2), at(0, 0.36, -0.8) * deg(6, 0, 0), horn, SMOOTH)
	eyes(piece, 0.5, 0.16, -0.56, 0.16, HELM_DARK)
	for _, side in { -1, 1 } do
		piece("Ear", v(0.24, 0.44, 0.16), at(side * 0.5, 0.82, 0.2) * deg(0, 0, -side * 20), grey, Enum.Material.Slate, BALL)
		piece("Fold", v(0.08, 0.5, 0.7), at(side * 0.7, -0.2, 0.1), dark, Enum.Material.Slate)
	end
end

HELMETS.ToroHead = function(piece)
	local black, muzzle, horn = Color3.fromRGB(34, 30, 30), Color3.fromRGB(120, 86, 76), Color3.fromRGB(236, 226, 200)
	piece("Mask", v(1.45, 1.36, 1.46), at(0, 0.05, 0), black, SMOOTH, BALL)
	piece("Snout", v(0.8, 0.56, 0.7), at(0, -0.22, -0.8), black, SMOOTH)
	piece("Muzzle", v(0.86, 0.5, 0.36), at(0, -0.26, -1.14), muzzle, SMOOTH, BALL)
	piece("NoseRing", v(0.06, 0.36, 0.36), at(0, -0.5, -1.22) * FRONT, HELM_GOLD, METAL, CYLINDER)
	piece("Forelock", v(0.5, 0.26, 0.3), at(0, 0.62, -0.5), Color3.fromRGB(60, 46, 40), SMOOTH, BALL)
	eyes(piece, 0.42, 0.2, -0.62, 0.18, Color3.fromRGB(190, 40, 30), Enum.Material.Neon)
	for _, side in { -1, 1 } do
		piece("Nostril", v(0.12, 0.1, 0.08), at(side * 0.18, -0.2, -1.3), HELM_DARK, SMOOTH, BALL)
		piece("Ear", v(0.44, 0.2, 0.14), at(side * 0.84, 0.3, 0.1) * deg(0, 0, side * 15), black, SMOOTH, BALL)
		-- the horns: out to the side, then swept up and forward
		piece("HornBase", v(0.6, 0.24, 0.24), at(side * 0.84, 0.62, -0.05) * deg(0, 0, side * 18), horn, SMOOTH, CYLINDER)
		piece("Horn", v(0.2, 0.6, 0.2), at(side * 1.16, 1.0, -0.12) * deg(-15, 0, -side * 14), horn, SMOOTH)
		piece("HornTip", v(0.12, 0.36, 0.12), at(side * 1.2, 1.42, -0.24) * deg(-25, 0, side * 6), Color3.fromRGB(70, 56, 46), SMOOTH)
	end
end

HELMETS.MonkeyHead = function(piece)
	local fur, face = Color3.fromRGB(104, 68, 42), Color3.fromRGB(226, 190, 150)
	piece("Mask", v(1.44, 1.38, 1.44), at(0, 0.06, 0), fur, SMOOTH, BALL)
	piece("Face", v(0.96, 0.7, 0.4), at(0, 0.2, -0.56), face, SMOOTH, BALL)
	piece("Muzzle", v(0.84, 0.6, 0.6), at(0, -0.24, -0.58), face, SMOOTH, BALL)
	piece("Nose", v(0.2, 0.12, 0.12), at(0, -0.1, -0.9), Color3.fromRGB(70, 46, 34), SMOOTH, BALL)
	piece("Mouth", v(0.5, 0.04, 0.06), at(0, -0.34, -0.86), Color3.fromRGB(70, 46, 34), SMOOTH)
	piece("Tuft", v(0.3, 0.3, 0.3), at(0, 0.78, -0.1), fur, SMOOTH, BALL)
	eyes(piece, 0.24, 0.26, -0.74, 0.16, HELM_DARK)
	for _, side in { -1, 1 } do
		piece("Ear", v(0.16, 0.56, 0.56), at(side * 0.78, 0.12, 0), fur, SMOOTH, BALL)
		piece("EarInner", v(0.1, 0.36, 0.36), at(side * 0.84, 0.12, -0.04), face, SMOOTH, BALL)
	end
end

-- ROBUX: foreign fighters -----------------------------------------------------------------

HELMETS.SamuraiHelm = function(piece)
	-- Kabuto: lacquered bowl, peak, layered neck guard, golden crescent
	local lacquer, cord = Color3.fromRGB(28, 26, 30), Color3.fromRGB(170, 30, 34)
	piece("Shell", v(1.22, 0.72, 1.22), at(0, 0.34, 0), lacquer, SMOOTH, BALL)
	piece("Rim", v(0.1, 1.34, 1.34), at(0, 0.2, 0) * FLAT, HELM_GOLD, METAL, CYLINDER)
	piece("Peak", v(0.9, 0.06, 0.4), at(0, 0.16, -0.76) * deg(12, 0, 0), lacquer, SMOOTH)
	for i = 0, 2 do
		local w = 1.36 + i * 0.22
		piece("NeckPlate", v(w, 0.2, 0.1), at(0, 0.04 - i * 0.2, 0.66 + i * 0.1) * deg(-18, 0, 0), lacquer, SMOOTH)
		piece("NeckCord", v(w, 0.04, 0.11), at(0, -0.05 - i * 0.2, 0.69 + i * 0.1) * deg(-18, 0, 0), cord, FABRIC)
		for _, side in { -1, 1 } do
			piece("SidePlate", v(0.1, 0.2, 0.9 + i * 0.1), at(side * (0.66 + i * 0.11), 0.04 - i * 0.2, 0.2), lacquer, SMOOTH)
		end
	end
	piece("CrestDisc", v(0.06, 0.3, 0.3), at(0, 0.5, -0.64) * FRONT, HELM_GOLD, METAL, CYLINDER)
	for _, side in { -1, 1 } do
		piece("Crescent", v(0.14, 0.8, 0.05), at(side * 0.3, 0.9, -0.62) * deg(0, 0, -side * 32), HELM_GOLD, METAL)
		piece("CrescentTip", v(0.1, 0.4, 0.05), at(side * 0.62, 1.34, -0.62) * deg(0, 0, -side * 12), HELM_GOLD, METAL)
		piece("Wing", v(0.06, 0.4, 0.3), at(side * 0.72, 0.36, -0.5) * deg(0, side * 30, 0), lacquer, SMOOTH)
	end
	piece("TopKnob", v(0.16, 0.12, 0.16), at(0, 0.74, 0), HELM_GOLD, METAL)
end

HELMETS.SoldierHelm = function(piece)
	-- Steel helmet of a WW2 soldier: olive pot with a rim, net and chin strap (no insignia)
	local olive, net, strap = Color3.fromRGB(86, 96, 62), Color3.fromRGB(58, 66, 44), Color3.fromRGB(104, 78, 50)
	piece("Shell", v(1.34, 0.86, 1.4), at(0, 0.36, 0), olive, METAL, BALL)
	piece("Rim", v(0.08, 1.46, 1.46), at(0, 0.16, 0) * FLAT, olive, METAL, CYLINDER)
	piece("Peak", v(1.0, 0.07, 0.3), at(0, 0.14, -0.72) * deg(10, 0, 0), olive, METAL)
	for i = -2, 2 do
		piece("Net", v(1.3, 0.56, 0.03), at(0, 0.44, i * 0.26), net, FABRIC)
		piece("Net", v(0.03, 0.56, 1.34), at(i * 0.25, 0.44, 0), net, FABRIC)
	end
	piece("Band", v(1.36, 0.08, 1.42), at(0, 0.3, 0), net, FABRIC)
	for _, side in { -1, 1 } do
		piece("Strap", v(0.05, 0.7, 0.1), at(side * 0.62, -0.2, -0.1), strap, Enum.Material.Leather)
	end
	piece("ChinStrap", v(1.24, 0.08, 0.1), at(0, -0.56, -0.1), strap, Enum.Material.Leather)
end

HELMETS.IncaHelm = function(piece)
	-- Inca headdress: golden band, sun disc with rays, a fan of feathers, ear discs
	local feathers = { Color3.fromRGB(200, 40, 40), Color3.fromRGB(240, 190, 40), Color3.fromRGB(30, 150, 110), Color3.fromRGB(40, 90, 200) }
	piece("Cap", v(1.2, 0.5, 1.2), at(0, 0.36, 0), Color3.fromRGB(150, 40, 40), FABRIC, BALL)
	piece("Band", v(1.26, 0.3, 1.26), at(0, 0.22, 0), HELM_GOLD, METAL)
	piece("BandStripe", v(1.28, 0.08, 1.28), at(0, 0.22, 0), Color3.fromRGB(30, 150, 110), SMOOTH)
	piece("Sun", v(0.08, 0.56, 0.56), at(0, 0.56, -0.66) * FRONT, HELM_GOLD, METAL, CYLINDER)
	piece("SunFace", v(0.1, 0.3, 0.3), at(0, 0.56, -0.68) * FRONT, Color3.fromRGB(240, 206, 110), METAL, CYLINDER)
	for i = 0, 7 do
		local angle = i / 8 * 360
		piece("Ray", v(0.08, 0.2, 0.05), at(0, 0.56, -0.67) * deg(0, 0, angle) * at(0, 0.38, 0), HELM_GOLD, METAL)
	end
	for i = -3, 3 do
		local color = feathers[(i + 3) % #feathers + 1]
		piece("Feather", v(0.2, 0.9 - math.abs(i) * 0.08, 0.05), at(0, 0.5, 0.1) * deg(0, 0, -i * 16) * at(0, 0.7, 0), color, FABRIC)
		piece("FeatherTip", v(0.14, 0.2, 0.06), at(0, 0.5, 0.1) * deg(0, 0, -i * 16) * at(0, 1.2 - math.abs(i) * 0.08, 0), HELM_CREAM, FABRIC)
	end
	for _, side in { -1, 1 } do
		piece("EarDisc", v(0.08, 0.4, 0.4), at(side * 0.66, -0.1, 0), HELM_GOLD, METAL, CYLINDER)
		piece("Tassel", v(0.1, 0.5, 0.1), at(side * 0.62, -0.5, 0.1), Color3.fromRGB(200, 40, 40), FABRIC)
	end
end

function EquipmentModels.buildHelmet(id: string, body: Model): Model?
	local builder = HELMETS[id]
	if not builder then
		return nil -- "NoHelmet" (and anything unknown): bare head
	end
	local head = body:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "Helmet_" .. id
	model:SetAttribute("HelmetId", id)
	-- head units: R15 heads are about as wide as tall; the mesh of an R6 head (2 x 1 x 1) is too
	local u = head.Size.Y
	local function piece(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
		local p = Instance.new("Part")
		p.Name = name
		if shape then
			p.Shape = shape
		end
		p.Size = size * u
		p.CFrame = head.CFrame * (offset.Rotation + offset.Position * u)
		p.Color = color
		p.Material = material or METAL
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
		p.CastShadow = false
		p.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = head, p
		weld.Parent = p
		return p
	end
	builder(piece)
	return model
end

return EquipmentModels
