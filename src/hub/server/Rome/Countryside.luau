--!strict
-- Outside the walls: einkorn plots north-east of the Landtor (separated by paths and low dry-stone
-- walls), a loose forest of stone pines and oaks with rocks and a clearing, the sandy bay with
-- headland rocks, a ruin on the cliff (reserved for a later secret stair under the disc) and a
-- safe viewpoint over the rim. The paths (RomeLayout.Paths, beaten earth in the terrain) are led
-- by striking rocks, tree groups and low walls instead of invisible guides. Placement is seeded.
local Workspace = game:GetService("Workspace")
local RomeLayout = require(script.Parent.RomeLayout)
local Parts = require(script.Parent.RomeParts)
local IslandBuilder = require(script.Parent.IslandBuilder)

local C = Parts.Colors
local Countryside = {}

local function ground(x: number, z: number): number
	return (IslandBuilder.heightAt(x, z))
end

local function nearPath(x: number, z: number, clearance: number): boolean
	for _, path in RomeLayout.Paths do
		for i = 1, #path.points - 1 do
			if RomeLayout.distanceToSegment(x, z, path.points[i], path.points[i + 1]) < RomeLayout.PathWidth / 2 + clearance then
				return true
			end
		end
	end
	return false
end

local function pine(parent: Instance, x: number, z: number, scale: number)
	local y = ground(x, z)
	local h = 13 * scale
	Parts.part(parent, "PineTrunk", CFrame.new(x, y + h / 2 - 1, z) * CFrame.Angles(0, 0, 0.04), Vector3.new(1.1 * scale, h, 1.1 * scale), Color3.fromRGB(110, 78, 54), { material = Enum.Material.Wood, shadow = true })
	Parts.part(parent, "PineCrown", CFrame.new(x, y + h + 0.6, z), Vector3.new(12 * scale, 3.4 * scale, 12 * scale), C.LeafDark, { collide = false, shape = Enum.PartType.Ball, material = Enum.Material.Grass })
	Parts.part(parent, "PineCrown", CFrame.new(x + 1.5 * scale, y + h + 2, z - 1), Vector3.new(8 * scale, 2.6 * scale, 8 * scale), Color3.fromRGB(70, 100, 58), { collide = false, shadow = false, shape = Enum.PartType.Ball, material = Enum.Material.Grass })
end

local function oak(parent: Instance, x: number, z: number, scale: number)
	local y = ground(x, z)
	local h = 6 * scale
	Parts.part(parent, "OakTrunk", CFrame.new(x, y + h / 2 - 1, z), Vector3.new(1.6 * scale, h, 1.6 * scale), Color3.fromRGB(96, 74, 56), { material = Enum.Material.Wood })
	for i, offset in { Vector3.new(0, 0, 0), Vector3.new(2.6, -0.8, 1), Vector3.new(-2.2, -0.6, -1.4) } do
		Parts.part(parent, "OakCrown", CFrame.new(Vector3.new(x, y + h + 2.4, z) + offset * scale), Vector3.new(9, 7, 9) * scale * (if i == 1 then 1 else 0.75), if i == 1 then C.Leaf else Color3.fromRGB(96, 126, 70), { collide = false, shadow = i == 1, shape = Enum.PartType.Ball, material = Enum.Material.Grass })
	end
end

local function rock(x: number, z: number, radius: number)
	Workspace.Terrain:FillBall(Vector3.new(x, ground(x, z) + radius * 0.25, z), radius, Enum.Material.Rock)
end

local function dryWall(parent: Instance, ax: number, az: number, bx: number, bz: number)
	local a = Vector3.new(ax, ground(ax, az), az)
	local b = Vector3.new(bx, ground(bx, bz), bz)
	local mid = (a + b) / 2
	local length = (Vector3.new(b.X, 0, b.Z) - Vector3.new(a.X, 0, a.Z)).Magnitude
	Parts.part(parent, "DryStoneWall", CFrame.lookAt(mid, Vector3.new(b.X, mid.Y, b.Z)) * CFrame.new(0, 0.5, 0), Vector3.new(1.4, 2.2, length), Color3.fromRGB(150, 138, 118), { material = Enum.Material.Slate })
end

function Countryside.build(parent: Instance)
	local folder = Parts.folder(parent, "Countryside")
	local rng = Random.new(170331)
	-- einkorn plots: a grid with paths between, low walls on the plot edges (gaps at the paths)
	local F = RomeLayout.Fields
	local fields = Parts.folder(folder, "EinkornFields")
	local pw = (F.x1 - F.x0 - (F.columns - 1) * F.path) / F.columns
	local pd = (F.z1 - F.z0 - (F.rows - 1) * F.path) / F.rows
	for c = 0, F.columns - 1 do
		for r = 0, F.rows - 1 do
			local x0 = F.x0 + c * (pw + F.path)
			local z0 = F.z0 + r * (pd + F.path)
			local cx, cz = x0 + pw / 2, z0 + pd / 2
			local y = ground(cx, cz)
			local plot = Parts.model(fields, "EinkornPlot")
			plot:SetAttribute("Crop", "Einkorn")
			local golden = Color3.fromRGB(214 - (c + r) % 3 * 10, 176 - (c * r) % 3 * 8, 92)
			Parts.decor(plot, "Crop", CFrame.new(cx, y + 0.9, cz), Vector3.new(pw - 3, 1.8, pd - 3), golden, Enum.Material.Grass)
			for k = 1, math.floor((pd - 4) / 3) do
				Parts.decor(plot, "Furrow", CFrame.new(cx, y + 1.85, z0 + 1.5 + k * 3), Vector3.new(pw - 3.4, 0.1, 0.5), Color3.fromRGB(176, 132, 70), Enum.Material.Grass)
			end
			-- walls along the north and south edges, open in the middle for a path
			for _, z in { z0, z0 + pd } do
				dryWall(plot, x0, z, cx - 3, z)
				dryWall(plot, cx + 3, z, x0 + pw, z)
			end
		end
	end
	-- a field barn and a scarecrow
	do
		local x, z = F.x0 + pw + F.path / 2, F.z0 - 14
		local y = ground(x, z)
		Parts.part(fields, "Barn", CFrame.new(x + 30, y + 3.5, z), Vector3.new(14, 7, 10), Parts.Plaster[3], { material = Enum.Material.Plaster })
		Parts.wedge(fields, "BarnRoof", CFrame.new(x + 30, y + 8, z - 2.6), Vector3.new(15, 2, 5.4), Parts.Roofs[1], { material = Enum.Material.ClayRoofTiles })
		Parts.wedge(fields, "BarnRoof", CFrame.new(x + 30, y + 8, z + 2.6) * CFrame.Angles(0, math.pi, 0), Vector3.new(15, 2, 5.4), Parts.Roofs[1], { material = Enum.Material.ClayRoofTiles })
	end
	-- the forest: stone pines and oaks, kept off the paths and out of the clearing
	local W = RomeLayout.Forest
	local woods = Parts.folder(folder, "Forest")
	local clearing = RomeLayout.Anchors.Clearing
	local placed = 0
	local tries = 0
	while placed < W.trees and tries < 2000 do
		tries += 1
		local x, z = rng:NextNumber(W.x0, W.x1), rng:NextNumber(W.z0, W.z1)
		local dc = math.sqrt((x - clearing.x) ^ 2 + (z - clearing.z) ^ 2)
		if dc > 34 and not nearPath(x, z, 4) and RomeLayout.isOnIsland(x, z) and RomeLayout.distanceToOutline(x, z, RomeLayout.Coast) > 26 then
			if rng:NextNumber() < 0.55 then
				pine(woods, x, z, rng:NextNumber(0.85, 1.25))
			else
				oak(woods, x, z, rng:NextNumber(0.8, 1.2))
			end
			placed += 1
		end
	end
	for _ = 1, 14 do
		local x, z = rng:NextNumber(W.x0 + 20, W.x1 - 20), rng:NextNumber(W.z0 + 20, W.z1 - 20)
		if not nearPath(x, z, 3) and RomeLayout.isOnIsland(x, z) then
			rock(x, z, rng:NextNumber(2.5, 5))
		end
	end
	-- the clearing: a ring of stones and a fallen log
	for i = 0, 6 do
		local a = i / 7 * 2 * math.pi
		rock(clearing.x + math.cos(a) * 22, clearing.z + math.sin(a) * 22, 2.2)
	end
	local logY = ground(clearing.x + 6, clearing.z - 4)
	Parts.part(woods, "FallenLog", CFrame.new(clearing.x + 6, logY + 0.7, clearing.z - 4) * CFrame.Angles(0, 0.6, math.pi / 2), Vector3.new(1.6, 9, 1.6), Color3.fromRGB(110, 80, 56), { shape = Enum.PartType.Cylinder, material = Enum.Material.Wood })
	-- path markers: a striking rock or a tree group at every bend, low walls on the last stretch
	local markers = Parts.folder(folder, "PathMarkers")
	for _, path in RomeLayout.Paths do
		for i = 2, #path.points - 1 do
			local p, q = path.points[i], path.points[i + 1]
			local dx, dz = q.x - p.x, q.z - p.z
			local length = math.sqrt(dx * dx + dz * dz)
			local nx, nz = -dz / length, dx / length
			local side = if i % 2 == 0 then 1 else -1
			local mx, mz = p.x + nx * side * 9, p.z + nz * side * 9
			if RomeLayout.isOnIsland(mx, mz) and not RomeLayout.isInTown(mx, mz) then
				if i % 3 == 0 then
					rock(mx, mz, 3.6)
				else
					oak(markers, mx, mz, 0.9)
					oak(markers, mx + nx * side * 7, mz + nz * side * 7, 0.7)
				end
			end
		end
	end
	-- the coastal path: low walls on its sea side, the viewpoint and the ruin on the cliff
	local coast = RomeLayout.Paths[3]
	for i = 2, #coast.points - 2 do
		local p, q = coast.points[i], coast.points[i + 1]
		local dx, dz = q.x - p.x, q.z - p.z
		local length = math.sqrt(dx * dx + dz * dz)
		local nx, nz = -dz / length, dx / length
		-- the sea side: the normal that points to the coastline
		local s = if RomeLayout.distanceToOutline(p.x + nx * 10, p.z + nz * 10, RomeLayout.Coast) < RomeLayout.distanceToOutline(p.x - nx * 10, p.z - nz * 10, RomeLayout.Coast) then 1 else -1
		local o = RomeLayout.PathWidth / 2 + 1.5
		dryWall(markers, p.x + nx * s * o + dx / length * 4, p.z + nz * s * o + dz / length * 4, q.x + nx * s * o - dx / length * 4, q.z + nz * s * o - dz / length * 4)
	end
	local view = RomeLayout.Anchors.Viewpoint
	local vy = ground(view.x, view.z)
	local lookout = Parts.model(markers, "Viewpoint")
	lookout:SetAttribute("Anchor", "Viewpoint")
	Parts.part(lookout, "ViewpointFloor", CFrame.new(view.x, vy + 0.3, view.z), Vector3.new(12, 0.8, 10), C.Limestone, { material = Enum.Material.Pavement })
	Parts.part(lookout, "ViewpointParapet", CFrame.new(view.x - 6, vy + 1.5, view.z), Vector3.new(0.8, 2.2, 10), C.Kerb, { material = Enum.Material.Limestone })
	Parts.sign(lookout, "ViewpointSign", CFrame.new(view.x - 5.5, vy + 3.4, view.z - 4) * CFrame.Angles(0, -math.pi / 2, 0), Vector2.new(6, 1.6), "AM RAND DER WELT", "Hier fällt das Meer in die Tiefe", C.TimberDark)
	local ruin = RomeLayout.Anchors.SecretRuin
	local ry = ground(ruin.x, ruin.z)
	local ruins = Parts.model(markers, "CliffRuin")
	ruins:SetAttribute("Reserved", "SecretStair")
	for i, h in { 7, 4.5, 9 } do
		Parts.column(ruins, "BrokenColumn", CFrame.new(ruin.x + (i - 2) * 4, ry - 0.5, ruin.z + (i % 2) * 3), h, 1.6, C.Travertine, { material = Enum.Material.Marble })
	end
	Parts.part(ruins, "RuinBlock", CFrame.new(ruin.x + 1, ry + 0.6, ruin.z - 3) * CFrame.Angles(0.1, 0.4, 0.05), Vector3.new(4, 1.6, 2.4), C.Travertine, { material = Enum.Material.Limestone })
	rock(ruin.x - 6, ruin.z + 4, 5)
	-- headland rocks round the bay and scattered meadow trees east of the town
	for _, p in { { -700, -430 }, { -716, -326 }, { -656, -460 } } do
		rock(p[1], p[2], 7)
	end
	for _ = 1, 30 do
		local x, z = rng:NextNumber(240, 470), rng:NextNumber(-300, 260)
		if RomeLayout.isOnIsland(x, z) and not RomeLayout.isInTown(x, z) and RomeLayout.distanceToOutline(x, z, RomeLayout.Coast) > 30 and not nearPath(x, z, 4) then
			if rng:NextNumber() < 0.4 then
				pine(folder, x, z, rng:NextNumber(0.8, 1.1))
			else
				oak(folder, x, z, rng:NextNumber(0.7, 1))
			end
		end
	end
end

return Countryside
