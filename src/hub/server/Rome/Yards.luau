--!strict
-- Private ground behind the public way (RomeLayout.Yards / YardWalls):
--   * the lower work yards behind the shop fronts of the Handwerksgasse: beaten earth, a row of
--     lean-to sheds one storey high (lower than the houses round them), a cart, firewood, a
--     sawhorse, a grindstone and amphorae
--   * low walls with closed arched gates (Torbögen) that close the yards and the villa gardens
--     toward lanes and squares. The walls are 2.4 studs high; an invisible guard above keeps
--     players on the public side without blocking the view.
local RomeLayout = require(script.Parent.RomeLayout)
local Parts = require(script.Parent.RomeParts)

local C = Parts.Colors
local Yards = {}

local GUARD = 8 -- the invisible guard reaches this high above the ground

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local function wallPiece(parent: Instance, a: Vector3, b: Vector3, level: number)
	local length = (b - a).Magnitude
	if length < 0.3 then
		return
	end
	local height = RomeLayout.YardWallHeight
	local mid = (a + b) / 2
	local frame = CFrame.lookAt(Vector3.new(mid.X, level, mid.Z), Vector3.new(b.X, level, b.Z))
	Parts.part(parent, "GardenWall", frame * CFrame.new(0, (height - 1) / 2, 0), v(0.8, height + 1, length), Parts.Plaster[2], { material = Enum.Material.Plaster })
	Parts.decor(parent, "WallCoping", frame * CFrame.new(0, height + 0.12, 0), v(1.1, 0.24, length), Parts.Roofs[1], Enum.Material.ClayRoofTiles)
	local guard = Parts.collider(parent, "WallGuard", frame * CFrame.new(0, height + (GUARD - height) / 2, 0), v(0.8, GUARD - height, length))
	guard.CanQuery = false
end

-- A closed arched gate 4 wide: two piers, an arch, timber leaves (all solid).
local function gate(parent: Instance, center: Vector3, along: Vector3, level: number)
	local frame = CFrame.lookAt(Vector3.new(center.X, level, center.Z), Vector3.new(center.X, level, center.Z) + along)
	local width, height = 4, 4.6
	for _, s in { -1, 1 } do
		Parts.part(parent, "GatePier", frame * CFrame.new(0, height / 2, s * (width / 2 + 0.5)), v(1.2, height + 0.6, 1), C.Limestone, { material = Enum.Material.Limestone })
	end
	Parts.part(parent, "GateArch", frame * CFrame.new(0, height + 0.5, 0), v(1.2, 1, width + 2), C.Limestone, { material = Enum.Material.Limestone })
	Parts.part(parent, "GateArchCrown", frame * CFrame.new(0, height + 0.15, 0) * CFrame.Angles(math.pi / 4, 0, 0), v(1, 1.6, 1.6), C.Limestone, { collide = false, shadow = false, material = Enum.Material.Limestone })
	Parts.part(parent, "GateLeaves", frame * CFrame.new(0, (height - 0.4) / 2, 0), v(0.3, height - 0.4, width), C.Timber, { material = Enum.Material.WoodPlanks })
	Parts.decor(parent, "GateRing", frame * CFrame.new(-0.2, height * 0.45, 0.6), v(0.1, 0.5, 0.5), C.Bronze, Enum.Material.Metal)
	Parts.collider(parent, "WallGuard", frame * CFrame.new(0, height + 1 + (GUARD - height - 1) / 2, 0), v(1, math.max(0.5, GUARD - height - 1), width + 2)).CanQuery = false
end

local function yard(parent: Instance, y: RomeLayout.Yard)
	local model = Parts.model(parent, "Werkhof_" .. y.id)
	model:SetAttribute("Private", true)
	local cx, cz = (y.x0 + y.x1) / 2, (y.z0 + y.z1) / 2
	local w, d = y.x1 - y.x0, y.z1 - y.z0
	Parts.decor(model, "YardGround", CFrame.new(cx, y.level + 0.03, cz), v(w, 0.06, d), Color3.fromRGB(150, 122, 92), Enum.Material.Ground)
	-- lean-to sheds along one edge: posts, a back wall, a sloping roof (lower than the houses)
	local depth, height = 6, 6
	local along = if y.shed == "N" or y.shed == "S" then w else d
	local edge = if y.shed == "N" then CFrame.lookAt(v(cx, y.level, y.z0 + depth / 2), v(cx, y.level, y.z0 + depth))
		elseif y.shed == "S" then CFrame.lookAt(v(cx, y.level, y.z1 - depth / 2), v(cx, y.level, y.z1 - depth))
		elseif y.shed == "W" then CFrame.lookAt(v(y.x0 + depth / 2, y.level, cz), v(y.x0 + depth, y.level, cz))
		else CFrame.lookAt(v(y.x1 - depth / 2, y.level, cz), v(y.x1 - depth, y.level, cz))
	-- the frame looks into the yard; its +Z is the back of the sheds
	Parts.part(model, "ShedBackWall", edge * CFrame.new(0, height / 2, depth / 2 - 0.4), v(along - 2, height, 0.8), Parts.Plaster[5], { material = Enum.Material.Plaster })
	for x = -along / 2 + 2, along / 2 - 2, 6 do
		Parts.part(model, "ShedPost", edge * CFrame.new(x, (height - 1.4) / 2, -depth / 2 + 0.4), v(0.5, height - 1.4, 0.5), C.Timber, { material = Enum.Material.Wood })
	end
	-- the roof rises toward the back wall (wedge +Z = back)
	Parts.wedge(model, "ShedRoof", edge * CFrame.new(0, height - 1.4 + 0.7, 0), v(along - 1, 1.4, depth + 1), Parts.Roofs[3], { material = Enum.Material.ClayRoofTiles })
	-- the yard's work: a cart, firewood, a sawhorse, a grindstone, amphorae
	local inside = edge * CFrame.new(0, 0, -depth)
	Parts.part(model, "CartBed", inside * CFrame.new(-w / 5, 1.6, -4), v(3.4, 0.4, 6), C.Timber, { material = Enum.Material.WoodPlanks })
	for _, s in { -1, 1 } do
		Parts.part(model, "CartWheel", inside * CFrame.new(-w / 5 + s * 1.9, 1.3, -4), v(0.3, 2.6, 2.6), C.TimberDark, { shape = Enum.PartType.Cylinder, material = Enum.Material.Wood })
	end
	for i = 0, 3 do
		Parts.part(model, "Firewood", inside * CFrame.new(w / 6, 0.4 + i * 0.7, 1 + (i % 2) * 0.2) * CFrame.Angles(0, 0, math.pi / 2), v(5, 0.7, 0.7), Color3.fromRGB(122, 88, 58), { shape = Enum.PartType.Cylinder, material = Enum.Material.Wood })
	end
	Parts.part(model, "Sawhorse", inside * CFrame.new(w / 4, 1.2, -6), v(4, 0.4, 0.6), C.Timber, { material = Enum.Material.Wood })
	Parts.part(model, "Grindstone", inside * CFrame.new(0, 1.4, -8), v(0.6, 2.4, 2.4), C.Stone, { shape = Enum.PartType.Cylinder, material = Enum.Material.Slate })
	for i = 0, 2 do
		Parts.part(model, "Amphora", inside * CFrame.new(-w / 3 + i * 1.3, 1.1, 1.4), v(1, 2.2, 1), C.Terracotta, { collide = false, shadow = false, shape = Enum.PartType.Ball, material = Enum.Material.Slate })
	end
end

function Yards.build(parent: Instance)
	local folder = Parts.folder(parent, "YardsAndGardens")
	for _, y in RomeLayout.Yards do
		yard(folder, y)
	end
	for _, w in RomeLayout.YardWalls do
		local model = Parts.model(folder, "Wall_" .. w.id)
		local a, b = v(w.a.x, 0, w.a.z), v(w.b.x, 0, w.b.z)
		local along = (b - a).Unit
		if w.gate then
			local g = a + (b - a) * w.gate
			local half = 2 + 1 -- gate opening plus its piers
			wallPiece(model, a, g - along * half, w.level)
			wallPiece(model, g + along * half, b, w.level)
			gate(model, g, along, w.level) -- the gate frame looks along the wall (Z: along, X: through)
		else
			wallPiece(model, a, b, w.level)
		end
	end
end

return Yards
