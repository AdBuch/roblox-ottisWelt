--!strict
-- The shell of the town: the wall with towers along RomeLayout.Wall (round the Colosseum's east
-- side and out onto the two moles), the Landtor and the small Küstentor, the retaining walls
-- between the terraces (streets ramp through them), the paved ring round the Colosseum and the
-- forecourt in front of its west arch.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Layout = require(ReplicatedStorage.Shared.ColosseumLayout)
local RomeLayout = require(script.Parent.RomeLayout)
local Parts = require(script.Parent.RomeParts)

local C = Parts.Colors
local CityShell = {}

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

-- A straight wall piece between two ground points (x, z) from y0 to y1, with merlons on top.
local function wallPiece(parent: Instance, ax: number, az: number, bx: number, bz: number, y0: number, y1: number, thickness: number, merlons: boolean)
	local a, b = v(ax, 0, az), v(bx, 0, bz)
	local length = (b - a).Magnitude
	if length < 0.5 then
		return
	end
	local mid = (a + b) / 2
	local frame = CFrame.lookAt(mid, b)
	Parts.part(parent, "Wall", frame * CFrame.new(0, (y0 + y1) / 2, 0), v(thickness, y1 - y0, length + 0.6), C.Stone, { material = Enum.Material.Limestone })
	Parts.decor(parent, "WallWalk", frame * CFrame.new(0, y1 + 0.15, 0), v(thickness + 0.4, 0.3, length + 0.6), C.Limestone, Enum.Material.Limestone)
	if merlons then
		local count = math.floor(length / 5)
		for i = 0, count - 1 do
			local z = -length / 2 + (i + 0.5) * length / count
			for _, s in { -1, 1 } do
				Parts.decor(parent, "Merlon", frame * CFrame.new(s * (thickness / 2 - 0.4), y1 + 1.3, z), v(0.8, 2.2, 2.2), C.Stone, Enum.Material.Limestone)
			end
		end
	end
end

local function tower(parent: Instance, x: number, z: number, y0: number, top: number, size: number, yaw: number)
	local frame = CFrame.new(x, 0, z) * CFrame.Angles(0, yaw, 0)
	Parts.part(parent, "Tower", frame * CFrame.new(0, (y0 + top) / 2, 0), v(size, top - y0, size), C.StoneDark, { material = Enum.Material.Limestone })
	Parts.decor(parent, "TowerCornice", frame * CFrame.new(0, top + 0.3, 0), v(size + 1, 0.6, size + 1), C.Limestone, Enum.Material.Limestone)
	for _, p in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		Parts.decor(parent, "Merlon", frame * CFrame.new(p[1] * (size / 2 - 0.6), top + 1.6, p[2] * (size / 2 - 0.6)), v(1.2, 2.4, 1.2), C.StoneDark, Enum.Material.Limestone)
	end
	Parts.decor(parent, "TowerRoof", frame * CFrame.new(0, top + 0.1, 0), v(size - 2, 0.3, size - 2), C.Terracotta, Enum.Material.ClayRoofTiles)
end

-- A gate: the wall's opening with an arch, two gate towers and the paving through it.
local function gate(parent: Instance, g: any, along: Vector3)
	local model = Parts.model(parent, "Gate_" .. g.name)
	model:SetAttribute("Gate", g.name)
	local p = v(g.x, 0, g.z)
	local frame = CFrame.lookAt(p, p + along)
	local thickness = RomeLayout.WallThickness + 2
	local top = g.level + RomeLayout.WallHeight + 3
	local half = g.width / 2
	for _, s in { -1, 1 } do
		local t = frame * CFrame.new(0, 0, s * (half + 4))
		tower(model, t.Position.X, t.Position.Z, g.level - 8, top + 4, 8, math.atan2(-along.X, -along.Z))
	end
	Parts.part(model, "GateLintel", frame * CFrame.new(0, (g.level + g.height + top) / 2, 0), v(thickness, top - g.level - g.height, g.width + 2), C.Stone, { material = Enum.Material.Limestone })
	Parts.decor(model, "GateArch", frame * CFrame.new(0, g.level + g.height + 0.4, 0), v(thickness + 0.4, 0.8, g.width + 1), C.Travertine, Enum.Material.Limestone)
	Parts.part(model, "GatePaving", frame * CFrame.new(0, g.level - 0.75, 0), v(thickness + 10, 1.5, g.width), C.Paving, { material = Enum.Material.Cobblestone, shadow = false })
	-- inscription on both faces
	for _, s in { -1, 1 } do
		Parts.sign(model, "GateName", frame * CFrame.new(s * (thickness / 2 + 0.2), g.level + g.height + 2.2, 0) * CFrame.Angles(0, -s * math.pi / 2, 0), Vector2.new(math.min(g.width + 2, 16), 2), g.name, nil, C.Travertine, C.TimberDark)
	end
	return model
end

function CityShell.build(parent: Instance)
	local folder = Parts.folder(parent, "TownWalls")
	local wall = RomeLayout.Wall
	local T = RomeLayout.WallThickness
	local gates: { any } = {}
	for _, g in RomeLayout.Gates do
		table.insert(gates, g)
	end
	for i = 1, #wall - 1 do
		local a, b = wall[i], wall[i + 1]
		local la, lb = RomeLayout.levelAt(a.x, a.z), RomeLayout.levelAt(b.x, b.z)
		local y0 = math.min(la, lb) - 10
		local y1 = math.max(la, lb) + RomeLayout.WallHeight
		-- split the piece at gates that lie on it
		local cuts = {}
		for _, g in gates do
			local d, t = RomeLayout.distanceToSegment(g.x, g.z, a, b)
			if d < 1.5 then
				local length = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
				table.insert(cuts, { t0 = t - (g.width / 2 + 0.5) / length, t1 = t + (g.width / 2 + 0.5) / length, g = g })
			end
		end
		table.sort(cuts, function(p, q)
			return p.t0 < q.t0
		end)
		local cursor = 0
		local function piece(t0: number, t1: number)
			wallPiece(folder, a.x + (b.x - a.x) * t0, a.z + (b.z - a.z) * t0, a.x + (b.x - a.x) * t1, a.z + (b.z - a.z) * t1, y0, y1, T, true)
		end
		for _, cut in cuts do
			piece(cursor, cut.t0)
			cursor = cut.t1
			local along = v(b.x - a.x, 0, b.z - a.z).Unit
			gate(folder, cut.g, along) -- the gate frame looks along the wall (X: through the gate)
		end
		piece(cursor, 1)
	end
	-- towers on the corners; watch posts on the mole heads
	for i, p in wall do
		local level = RomeLayout.levelAt(p.x, p.z)
		local onGate = false
		for _, g in gates do
			if math.abs(g.x - p.x) + math.abs(g.z - p.z) < 14 then
				onGate = true
			end
		end
		if not onGate then
			local mole = i == 1 or i == #wall
			tower(folder, p.x, p.z, level - 12, level + RomeLayout.WallHeight + (if mole then 8 else 5), if mole then 9 else 11, 0)
			if mole then
				Parts.flame(folder, CFrame.new(p.x, level + RomeLayout.WallHeight + 10.5, p.z), 40, 1.2)
			end
		end
	end

	-- retaining walls between the terraces, open where a street ramps through
	local retain = Parts.folder(parent, "RetainingWalls")
	local function retainingWall(x: number, low: number, high: number)
		-- where the wall crosses the town (between the north and south wall)
		local zs = {}
		for i = 1, #wall - 1 do
			local a, b = wall[i], wall[i + 1]
			if (a.x - x) * (b.x - x) <= 0 and a.x ~= b.x then
				table.insert(zs, a.z + (b.z - a.z) * (x - a.x) / (b.x - a.x))
			end
		end
		table.sort(zs)
		if #zs < 2 then
			return
		end
		local z0, z1 = zs[1] + T / 2, zs[#zs] - T / 2
		local openings = {}
		for _, street in RomeLayout.Streets do
			for k = 1, #street.points - 1 do
				local p, q = street.points[k], street.points[k + 1]
				if p.y ~= q.y and (p.x - x) * (q.x - x) <= 0 then
					local z = p.z + (q.z - p.z) * (x - p.x) / (q.x - p.x)
					table.insert(openings, { z - RomeLayout.halfWidth(street.kind), z + RomeLayout.halfWidth(street.kind) })
				end
			end
		end
		table.sort(openings, function(p, q)
			return p[1] < q[1]
		end)
		local cursor = z0
		local function span(from: number, to: number)
			if to - from > 0.5 then
				Parts.part(retain, "RetainingWall", CFrame.new(x, (low - 1 + high) / 2, (from + to) / 2), v(1.6, high - low + 1, to - from), C.Stone, { material = Enum.Material.Limestone })
				Parts.part(retain, "Parapet", CFrame.new(x + 0.4, high + 0.55, (from + to) / 2), v(0.8, 1.1, to - from), C.Kerb, { material = Enum.Material.Limestone })
			end
		end
		for _, o in openings do
			span(cursor, o[1])
			cursor = o[2]
		end
		span(cursor, z1)
	end
	local L = RomeLayout.Levels
	retainingWall(RomeLayout.Terraces.UpperLowerX, L.Lower, L.Upper)
	retainingWall(RomeLayout.Terraces.LowerHarborX, L.Harbor, L.Lower)

	-- the paved ring round the Colosseum and the forecourt before its west arch
	local plaza = Parts.folder(parent, "ColosseumPlaza")
	local segments = 96
	local inner, outer = 93.2, RomeLayout.Plaza.outer
	for i = 0, segments - 1 do
		local t0, t1 = i / segments * 2 * math.pi, (i + 1) / segments * 2 * math.pi
		local a0, a1 = Layout.point(t0, inner), Layout.point(t1, inner)
		local b0, b1 = Layout.point(t0, outer), Layout.point(t1, outer)
		local mid = (a0 + a1 + b0 + b1) / 4
		local along = ((a1 + b1) - (a0 + b0)) / 2
		local length = math.max((a1 - a0).Magnitude, (b1 - b0).Magnitude) + 0.8
		local frame = CFrame.lookAt(mid, mid + along)
		Parts.part(plaza, "PlazaPaving", frame * CFrame.new(0, 0.98 - (i % 2) * 0.01 - 1, 0), v(outer - inner, 2, length), C.Limestone, { material = Enum.Material.Pavement, shadow = false })
	end
	local F = RomeLayout.Forecourt
	local x1 = math.min(F.x1, -170)
	Parts.part(plaza, "Forecourt", CFrame.new((F.x0 + x1) / 2, 0.985 - 1, (F.z0 + F.z1) / 2), v(x1 - F.x0, 2, F.z1 - F.z0), C.Travertine, { material = Enum.Material.Pavement, shadow = false })
	-- the signpost on the forecourt: smithy and forum ahead, the Colosseum behind
	local post = CFrame.new(-205, 1, -20)
	Parts.part(plaza, "SignPost", post * CFrame.new(0, 4, 0), v(0.6, 8, 0.6), C.Timber, { material = Enum.Material.Wood })
	Parts.sign(plaza, "SignSmithy", post * CFrame.new(0, 7.2, 0) * CFrame.Angles(0, -math.pi / 2, 0), Vector2.new(9, 1.6), "SCHMIEDE · FORUM →", nil, C.TimberDark)
	Parts.sign(plaza, "SignHarbour", post * CFrame.new(0, 5.4, 0) * CFrame.Angles(0, -math.pi / 2, 0), Vector2.new(9, 1.4), "TEMPEL · HAFEN →", nil, C.TimberDark)
	Parts.sign(plaza, "SignColosseum", post * CFrame.new(0, 6.3, 0) * CFrame.Angles(0, math.pi / 2, 0), Vector2.new(9, 1.6), "← KOLOSSEUM · ARENA", nil, C.TimberDark)
	-- cypress rows along the plaza
	for i = 0, 23 do
		local theta = i / 24 * 2 * math.pi
		local p = Layout.point(theta, outer + 4)
		if math.abs(math.deg(theta) - 180) > 14 and RomeLayout.isInTown(p.X, p.Z) then
			local base = CFrame.new(p.X, 1, p.Z)
			Parts.decor(plaza, "CypressTrunk", base * CFrame.new(0, 1, 0), v(0.7, 2, 0.7), C.TimberDark, Enum.Material.Wood)
			Parts.part(plaza, "Cypress", base * CFrame.new(0, 7, 0), v(3, 11, 3), C.LeafDark, { collide = false, shadow = true, shape = Enum.PartType.Ball, material = Enum.Material.Grass })
		end
	end
end

return CityShell
