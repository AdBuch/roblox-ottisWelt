--!strict
-- The forum and its temple (RomeLayout.Forum / Temple / Anchors).
--   FORUM: a bright, long square one step above the streets, colonnades along both long sides
--   (open where streets come in), the fountain at the east entrance (the safe respawn after a
--   fall off the world's edge) and a reserved place for a notice board and quest figures. The
--   middle stays free.
--   TEMPLE: on a podium at the forum's west end, a wide front stair, six columns and a pediment
--   (a second pediment faces the harbour), a flat ramp along the south side, a walk-in cella with
--   a floor mosaic, quiet light, a statue and the oracle's tripod. The NPC routes are anchors.
local RomeLayout = require(script.Parent.RomeLayout)
local Parts = require(script.Parent.RomeParts)

local C = Parts.Colors
local ForumTemple = {}

export type Result = {
	fountain: CFrame,
	respawn: CFrame,
	questBoard: CFrame,
	oracle: CFrame, -- where the oracle priest stands (facing the door)
	priestRoutes: { { Vector3 } },
	cellaCenter: CFrame,
	cellaSize: Vector3,
}

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

local function forum(parent: Instance): (CFrame, CFrame, CFrame)
	local F = RomeLayout.Forum
	local L = RomeLayout.Levels.Lower
	local model = Parts.model(parent, "Forum")
	local cx, cz = (F.x0 + F.x1) / 2, (F.z0 + F.z1) / 2
	local w, d = F.x1 - F.x0, F.z1 - F.z0
	Parts.part(model, "ForumPaving", CFrame.new(cx, F.top - 1, cz), v(w, 2, d), C.Travertine, { material = Enum.Material.Pavement, shadow = false })
	-- a pattern of large slabs (joints) in the paving
	for x = F.x0 + 12, F.x1 - 1, 12 do
		Parts.decor(model, "SlabJoint", CFrame.new(x, F.top + 0.01, cz), v(0.2, 0.02, d - 1), C.Stone)
	end
	-- the step round the forum: a lighter kerb, an invisible flat run-up all round (not at the temple)
	local step = F.top - L
	for _, side in { { name = "N", z = F.z0 }, { name = "S", z = F.z1 } } do
		local z = side.z
		local out = if side.name == "N" then -1 else 1
		Parts.decor(model, "ForumKerb", CFrame.new(cx, F.top - step / 2 + 0.02, z + out * 0.2), v(w, step + 0.04, 0.4), C.Kerb)
		local p = v(cx, L + step / 2, z + out * 1.2)
		Parts.colliderWedge(model, "ForumRunUp", CFrame.lookAt(p, p + v(0, 0, out)), v(w, step, 2.4))
	end
	do
		local x = F.x1
		Parts.decor(model, "ForumKerb", CFrame.new(x + 0.2, F.top - step / 2 + 0.02, cz), v(0.4, step + 0.04, d), C.Kerb)
		local p = v(x + 1.2, L + step / 2, cz)
		Parts.colliderWedge(model, "ForumRunUp", CFrame.lookAt(p, p + v(1, 0, 0)), v(2.4, step, d))
	end
	-- colonnades along both long sides, a back wall, a lean-to roof; open where streets come in
	for _, side in { { name = "north", z = F.z0, s = -1 }, { name = "south", z = F.z1, s = 1 } } do
		local openings = (RomeLayout.ForumOpenings :: any)[side.name]
		local function open(x: number): boolean
			for _, o in openings do
				if math.abs(x - o.x) < o.half then
					return true
				end
			end
			return false
		end
		local colZ = side.s * F.colonnade
		local x = F.x0 + 10
		while x <= F.x1 - 6 do
			if not open(x) then
				Parts.column(model, "Colonnade", CFrame.new(x, F.top, colZ), 11, 1.4, C.Travertine, { material = Enum.Material.Marble })
				Parts.decor(model, "ColumnBase", CFrame.new(x, F.top + 0.3, colZ), v(2, 0.6, 2), C.Limestone)
				Parts.decor(model, "Capital", CFrame.new(x, F.top + 11.2, colZ), v(2.2, 0.6, 2.2), C.Limestone)
			end
			x += F.columnStep
		end
		-- beam and roof in spans between the openings
		local spans = {}
		local start: number? = nil
		local sx = F.x0 + 6
		while sx <= F.x1 - 2 do
			local free = not open(sx)
			if free and not start then
				start = sx
			elseif not free and start then
				table.insert(spans, { start, sx - 1 })
				start = nil
			end
			sx += 1
		end
		if start then
			table.insert(spans, { start, F.x1 - 2 })
		end
		for _, span in spans do
			local mx, len = (span[1] + span[2]) / 2, span[2] - span[1]
			Parts.decor(model, "Entablature", CFrame.new(mx, F.top + 12, colZ), v(len, 1.2, 2), C.Limestone)
			local roofZ = colZ + side.s * 3
			Parts.wedge(model, "PorticoRoof", CFrame.new(mx, F.top + 13.4, roofZ) * (if side.s > 0 then CFrame.identity else CFrame.Angles(0, math.pi, 0)), v(len, 1.6, 7), Parts.Roofs[1], { collide = false, shadow = true, material = Enum.Material.ClayRoofTiles })
			Parts.part(model, "PorticoWall", CFrame.new(mx, F.top + 6, side.s * (F.colonnade + 5.6)), v(len, 12, 0.8), Parts.Plaster[1], { material = Enum.Material.Plaster })
		end
	end
	-- the fountain at the east entrance: a round basin, a column with a bronze bowl and spouts
	local A = RomeLayout.Anchors
	local f = A.ForumFountain
	local base = CFrame.new(f.x, f.y, f.z)
	Parts.column(model, "FountainBasin", base, 1.6, 11, C.Travertine, { material = Enum.Material.Marble })
	Parts.column(model, "FountainWater", base * CFrame.new(0, 1.2, 0), 0.5, 9.8, C.Water, { collide = false, shadow = false, material = Enum.Material.Glass }).Transparency = 0.25
	Parts.column(model, "FountainPillar", base, 5, 1.4, C.Limestone, { material = Enum.Material.Marble })
	Parts.column(model, "FountainBowl", base * CFrame.new(0, 5, 0), 0.6, 3.6, C.Bronze, { collide = false, material = Enum.Material.Metal })
	local spout = Instance.new("ParticleEmitter")
	spout.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	spout.Color = ColorSequence.new(Color3.fromRGB(200, 230, 255))
	spout.Size = NumberSequence.new(0.3)
	spout.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	spout.Lifetime = NumberRange.new(0.7, 1)
	spout.Rate = 30
	spout.Speed = NumberRange.new(4, 6)
	spout.SpreadAngle = Vector2.new(25, 25)
	spout.Acceleration = v(0, -20, 0)
	local spoutHost = Parts.decor(model, "FountainSpout", base * CFrame.new(0, 5.6, 0), v(0.6, 0.6, 0.6), C.Bronze, Enum.Material.Metal)
	spout.Parent = spoutHost
	local respawnAnchor = A.ForumRespawn
	local respawn = Parts.at(respawnAnchor.x, respawnAnchor.y, respawnAnchor.z, respawnAnchor.yaw)
	-- reserved: the notice board and the places of the quest figures (a plinth and a blank board)
	local q = A.QuestBoard
	local board = Parts.at(q.x, q.y, q.z, q.yaw)
	local reserved = Parts.model(model, "ReservedQuestBoard")
	reserved:SetAttribute("Reserved", "NoticeBoard")
	Parts.part(reserved, "BoardPlinth", board * CFrame.new(0, 0.4, 0), v(7, 0.8, 2.2), C.Limestone)
	for _, s in { -1, 1 } do
		Parts.part(reserved, "BoardPost", board * CFrame.new(s * 3, 3.6, 0), v(0.5, 5.6, 0.5), C.Timber, { material = Enum.Material.Wood })
	end
	Parts.sign(reserved, "NoticeBoard", board * CFrame.new(0, 4.2, -0.1) * CFrame.Angles(0, 0, 0), Vector2.new(6, 3.6), "BEKANNTMACHUNGEN", "Bald: Aufträge des Forums", C.TimberDark)
	for _, key in { "QuestFigureA", "QuestFigureB" } do
		local a = (A :: any)[key]
		local spot = Parts.decor(reserved, key, Parts.at(a.x, a.y + 0.03, a.z, a.yaw), v(3, 0.06, 3), C.Bronze, Enum.Material.Metal)
		spot.Transparency = 0.5
		spot:SetAttribute("Reserved", "QuestFigure")
	end
	-- lamps at the corners of the free middle
	for _, p in { { F.x0 + 20, -18 }, { F.x0 + 20, 18 }, { F.x1 - 20, -18 }, { F.x1 - 20, 18 } } do
		Parts.lampPost(model, CFrame.new(p[1], F.top, p[2]))
	end
	return base, respawn, board
end

local function temple(parent: Instance): (CFrame, { { Vector3 } }, CFrame, Vector3)
	local T = RomeLayout.Temple
	local F = RomeLayout.Forum
	local model = Parts.model(parent, "Temple")
	model:SetAttribute("Interior", "Temple")
	local cx, cz = (T.x0 + T.x1) / 2, (T.z0 + T.z1) / 2
	local w, d = T.x1 - T.x0, T.z1 - T.z0
	local groundY = RomeLayout.Levels.Lower
	-- podium with a moulded base and crown
	Parts.part(model, "Podium", CFrame.new(cx, (T.top + groundY - 4) / 2, cz), v(w, T.top - groundY + 4, d), C.Limestone, { material = Enum.Material.Limestone })
	Parts.decor(model, "PodiumCrown", CFrame.new(cx, T.top - 0.3, cz), v(w + 0.8, 0.6, d + 0.8), C.Travertine, Enum.Material.Marble)
	Parts.decor(model, "PodiumBase", CFrame.new(cx, groundY + 0.6, cz), v(w + 1, 1.2, d + 1), C.Stone, Enum.Material.Limestone)
	-- the front stair from the forum: ten steps of half a stud, every step a solid block
	local rise = T.top - F.top
	local steps = math.floor(rise / 0.5 + 0.5)
	local run = (T.stairsTo - T.x1) / steps -- the stair runs east from the podium into the forum
	for k = 1, steps do
		local top = F.top + k * rise / steps
		-- k = 1 is the lowest step, nearest the forum
		Parts.part(model, "TempleStep", CFrame.new(T.stairsTo - run * (k - 0.5), (top + F.top - 1) / 2, cz), v(run + 0.02, top - F.top + 1, d - 4), if k % 2 == 0 then C.Travertine else C.Limestone, { material = Enum.Material.Marble })
	end
	-- the flat side ascent along the south flank, then a landing at the podium's height
	local R = T.ramp
	local rampLength = math.abs(R.x1 - R.x0)
	local rampMid = v((R.x0 + R.x1) / 2, (F.top + T.top) / 2, (R.z0 + R.z1) / 2)
	-- rises toward the west: the wedge's +Z points to -x
	Parts.wedge(model, "SideRamp", CFrame.lookAt(rampMid, rampMid + v(1, 0, 0)), v(R.z1 - R.z0, T.top - F.top, rampLength), C.Limestone, { material = Enum.Material.Limestone })
	Parts.part(model, "RampBody", CFrame.new((R.x0 + R.x1) / 2, (F.top + groundY) / 2 - 0.5, (R.z0 + R.z1) / 2), v(rampLength, F.top - groundY + 1, R.z1 - R.z0), C.Stone, { shadow = false })
	Parts.part(model, "RampLanding", CFrame.new((R.x1 + R.landingTo) / 2, (T.top + groundY) / 2, (R.z0 + R.z1) / 2), v(math.abs(R.landingTo - R.x1), T.top - groundY, R.z1 - R.z0), C.Limestone, { material = Enum.Material.Limestone })
	do -- the parapet along the ramp's outer edge follows its slope, then the landing
		local a, b = v(R.x0, F.top + 0.6, R.z1 + 0.35), v(R.x1, T.top + 0.6, R.z1 + 0.35)
		Parts.part(model, "RampParapet", CFrame.lookAt((a + b) / 2, b), v(0.7, 1.2, (b - a).Magnitude), C.Kerb, { material = Enum.Material.Limestone })
		Parts.part(model, "RampParapet", CFrame.new((R.x1 + R.landingTo) / 2, T.top + 0.6, R.z1 + 0.35), v(math.abs(R.landingTo - R.x1), 1.2, 0.7), C.Kerb, { material = Enum.Material.Limestone })
	end
	-- the cella: walls with a door to the east, a ceiling, the interior
	local Cc = T.cella
	local ccx, ccz = (Cc.x0 + Cc.x1) / 2, (Cc.z0 + Cc.z1) / 2
	local cw, cd = Cc.x1 - Cc.x0, Cc.z1 - Cc.z0
	local wallY = T.top + Cc.height / 2
	local plaster = Color3.fromRGB(236, 226, 206)
	Parts.part(model, "CellaWall", CFrame.new(Cc.x0 + Cc.wall / 2, wallY, ccz), v(Cc.wall, Cc.height, cd), plaster, { material = Enum.Material.Marble })
	for _, s in { -1, 1 } do
		Parts.part(model, "CellaWall", CFrame.new(ccx, wallY, ccz + s * (cd / 2 - Cc.wall / 2)), v(cw, Cc.height, Cc.wall), plaster, { material = Enum.Material.Marble })
	end
	local doorW, doorH = 8, 11
	local sideW = (cd - doorW) / 2
	for _, s in { -1, 1 } do
		Parts.part(model, "CellaWall", CFrame.new(Cc.x1 - Cc.wall / 2, wallY, s * (doorW / 2 + sideW / 2)), v(Cc.wall, Cc.height, sideW), plaster, { material = Enum.Material.Marble })
	end
	Parts.part(model, "CellaWall", CFrame.new(Cc.x1 - Cc.wall / 2, T.top + doorH + (Cc.height - doorH) / 2, 0), v(Cc.wall, Cc.height - doorH, doorW), plaster, { material = Enum.Material.Marble })
	Parts.decor(model, "DoorFrame", CFrame.new(Cc.x1 + 0.1, T.top + doorH / 2, 0), v(0.5, doorH + 1, doorW + 1.4), C.Bronze, Enum.Material.Metal)
	-- the open bronze doors folded back inside
	for _, s in { -1, 1 } do
		Parts.decor(model, "BronzeDoor", CFrame.new(Cc.x1 - 2.2, T.top + doorH / 2, s * (doorW / 2 + 0.3)), v(3.8, doorH - 0.4, 0.3), C.Bronze, Enum.Material.Metal)
	end
	Parts.part(model, "CellaCeiling", CFrame.new(ccx, T.top + Cc.height + 0.5, ccz), v(cw, 1, cd), C.Travertine, { material = Enum.Material.Marble })
	-- floor mosaic: concentric frames and a gold centre
	local floorY = T.top + 0.03
	for i, color in { Color3.fromRGB(150, 58, 44), C.Cream, Color3.fromRGB(40, 70, 86), C.Cream, C.Gold } do
		local inset = (i - 1) * 2.2
		Parts.decor(model, "Mosaic", CFrame.new(ccx + 1, floorY + i * 0.005, ccz), v(cw - 5 - inset * 2, 0.02, cd - 5 - inset * 2), color, Enum.Material.CeramicTiles)
	end
	-- the statue in the back and the oracle's tripod with its flame in front of it
	local statueBase = CFrame.new(Cc.x0 + 2.4, T.top, ccz)
	Parts.part(model, "StatuePlinth", statueBase * CFrame.new(0, 1.2, 0), v(3.6, 2.4, 4.4), C.Travertine, { material = Enum.Material.Marble })
	Parts.decor(model, "StatueBody", statueBase * CFrame.new(0, 5.6, 0), v(1.8, 6.4, 2.2), C.Cream, Enum.Material.Marble)
	Parts.part(model, "StatueHead", statueBase * CFrame.new(0, 9.5, 0), v(1.5, 1.5, 1.5), C.Cream, { collide = false, shadow = false, shape = Enum.PartType.Ball, material = Enum.Material.Marble })
	Parts.decor(model, "StatueSpear", statueBase * CFrame.new(0, 6.5, 1.6), v(0.25, 11, 0.25), C.Gold, Enum.Material.Metal)
	local o = RomeLayout.Anchors.OracleSpot
	local tripod = CFrame.new(o.x - 3.5, T.top, o.z)
	for i = 0, 2 do
		local a = i * math.pi * 2 / 3
		Parts.decor(model, "TripodLeg", tripod * CFrame.new(math.cos(a) * 0.9, 1.6, math.sin(a) * 0.9) * CFrame.Angles(math.sin(a) * 0.25, 0, -math.cos(a) * 0.25), v(0.2, 3.3, 0.2), C.Bronze, Enum.Material.Metal)
	end
	Parts.column(model, "TripodBowl", tripod * CFrame.new(0, 3.2, 0), 0.6, 2.2, C.Bronze, { collide = false, material = Enum.Material.Metal })
	local flame = Parts.flame(model, tripod * CFrame.new(0, 4.1, 0), 26, 1.1)
	local fire = Instance.new("Fire")
	fire.Size = 2
	fire.Heat = 3
	fire.Color = Color3.fromRGB(255, 190, 110)
	fire.SecondaryColor = Color3.fromRGB(255, 120, 60)
	fire.Parent = flame
	Parts.collider(model, "TripodGuard", tripod * CFrame.new(0, 2, 0), v(2.6, 4, 2.6))
	-- quiet light along the walls
	for _, x in { Cc.x0 + 9, Cc.x1 - 6 } do
		for _, s in { -1, 1 } do
			Parts.flame(model, CFrame.new(x, T.top + 7, s * (cd / 2 - 1.4)), 16, 0.5)
		end
	end
	-- the peristyle: front columns (six) and the flanks, the entablature, the roof and two pediments
	local colTop = T.top + T.columns
	local frontX = T.x1 - 2
	for i = 0, 5 do
		local z = -12.5 + i * 5
		Parts.column(model, "TempleColumn", CFrame.new(frontX, T.top, z), T.columns, 2.2, C.Travertine, { material = Enum.Material.Marble })
		Parts.decor(model, "ColumnCapital", CFrame.new(frontX, colTop - 0.4, z), v(2.8, 0.8, 2.8), C.Limestone)
	end
	for x = T.x1 - 9, T.x0 + 2, -7 do
		for _, s in { -1, 1 } do
			Parts.column(model, "TempleColumn", CFrame.new(x, T.top, s * (d / 2 - 1.6)), T.columns, 1.8, C.Travertine, { collide = false, material = Enum.Material.Marble })
		end
	end
	Parts.part(model, "Entablature", CFrame.new(cx, colTop + 1.1, cz), v(w + 0.6, 2.2, d + 0.6), C.Limestone, { material = Enum.Material.Limestone })
	Parts.decor(model, "Frieze", CFrame.new(T.x1 + 0.35, colTop + 1.1, cz), v(0.2, 1.4, d - 2), C.Bronze, Enum.Material.Metal)
	local roofRise = 6
	local roofY = colTop + 2.2
	for _, s in { -1, 1 } do
		local half = CFrame.new(cx, roofY + roofRise / 2, s * (d / 4 + 0.2)) * (if s > 0 then CFrame.Angles(0, math.pi, 0) else CFrame.identity)
		Parts.wedge(model, "TempleRoof", half, v(w + 1.6, roofRise, d / 2 + 0.8), Parts.Roofs[2], { material = Enum.Material.ClayRoofTiles })
	end
	-- pediments (front and back): marble triangles slightly proud of the roof ends, a gilded acroterion
	for _, x in { T.x1 + 0.6, T.x0 - 0.6 } do
		for _, s in { -1, 1 } do
			local half = CFrame.new(x, roofY + roofRise / 2, s * (d / 4 + 0.2)) * (if s > 0 then CFrame.Angles(0, math.pi, 0) else CFrame.identity)
			Parts.wedge(model, "Pediment", half, v(0.5, roofRise - 0.2, d / 2 + 0.4), C.Travertine, { collide = false, shadow = false, material = Enum.Material.Marble })
		end
		Parts.decor(model, "Acroterion", CFrame.new(x, roofY + roofRise + 0.8, 0), v(0.6, 1.6, 1.6), C.Gold, Enum.Material.Metal)
	end
	Parts.sign(model, "TempleName", CFrame.new(T.x1 + 0.6, colTop + 1.1, cz) * CFrame.Angles(0, -math.pi / 2, 0), Vector2.new(16, 1.6), "TEMPLUM · ORACULUM", nil, C.Travertine, C.TimberDark)
	-- NPC routes (podium and cella)
	local oracle = CFrame.lookAt(v(o.x, T.top, o.z), v(Cc.x1 + 5, T.top, 0))
	local routes = {
		-- the oracle priest: between the tripod and the door, inside the cella
		{ v(o.x, T.top, o.z), v(o.x - 1, T.top, -6), v(o.x + 7, T.top, -6), v(o.x + 7, T.top, 6), v(o.x - 1, T.top, 6) },
		-- the second priest: across the pronaos and along the south walkway (there and back)
		{ v(T.x1 - 6, T.top, -11), v(T.x1 - 6, T.top, 11), v(T.x1 - 10, T.top, 13.3), v(T.x0 + 6, T.top, 13.3), v(T.x1 - 10, T.top, 13.3), v(T.x1 - 6, T.top, 11) },
	}
	return oracle, routes, CFrame.new(ccx, T.top + Cc.height / 2, ccz), v(cw, Cc.height, cd)
end

function ForumTemple.build(parent: Instance): Result
	local fountain, respawn, board = forum(parent)
	local oracle, routes, cellaCenter, cellaSize = temple(parent)
	return {
		fountain = fountain,
		respawn = respawn,
		questBoard = board,
		oracle = oracle,
		priestRoutes = routes,
		cellaCenter = cellaCenter,
		cellaSize = cellaSize,
	}
end

return ForumTemple
