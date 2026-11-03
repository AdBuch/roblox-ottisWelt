--!strict
-- Generates a Colosseum-style arena from anchored Parts: an oval sand floor (~152 x 96, the
-- Flavian proportions), a podium wall with barred gates and red banners, eight steep seating
-- tiers in two storeys carried by an open substructure (piers and four switchback stair houses),
-- an ambulatory per storey behind them and an outer facade like the Roman Colosseum's (three
-- storeys of arches with a statue in every upper arch, attic on top) standing on an endless
-- granite plate. An invisible barrier on the podium keeps everyone on the arena floor.
-- Decorations inside the floor area are non-collidable, so they never block movement or pathfinding.
-- Calling build() again replaces the previous Workspace.GeneratedArena (no duplicates).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Architecture = require(ReplicatedStorage.Shared.ColosseumLayout)
local ColosseumGate = require(script.Parent.ColosseumGate)

local PREFIX = "[OttiArena][Server]"

-- Roman palette
local SAND = Color3.fromRGB(226, 202, 145)
local TRAVERTINE = Color3.fromRGB(222, 210, 184)
local SANDSTONE = Color3.fromRGB(204, 168, 120)
local STONE_DARK = Color3.fromRGB(150, 128, 100)
local OPENING = Color3.fromRGB(58, 44, 34)
local BRONZE = Color3.fromRGB(176, 125, 60)
local BANNER_RED = Color3.fromRGB(128, 22, 28)
local GOLD = Color3.fromRGB(240, 196, 80)

-- Dimensions
local A, B = Architecture.SemiAxisX, Architecture.SemiAxisZ
local FLOOR_TOP = Architecture.FloorTop
local PODIUM_HEIGHT = Architecture.PodiumHeight
local PODIUM_THICKNESS = Architecture.PodiumThickness
local BARRIER_TOP = FLOOR_TOP + 70
local SEAT_TIERS = Architecture.SeatTiers
local SLAB = Architecture.SlabThickness
local tierTop, tierFront, tierDepth = Architecture.tierTop, Architecture.tierFront, Architecture.tierDepth
-- Underside of tier k's slab: its riser starts on the terrace below, the space beneath stays open
local function tierBottom(k: number): number
	return tierTop(k - 1) - SLAB
end
local SEATS_END = Architecture.seatsEnd() -- behind the top tier: the ambulatories
local GALLERY_END = SEATS_END + Architecture.GalleryWidth -- inner face of the facade
local OUTER_OFFSET = Architecture.facadeEnd() -- outer face of the facade
local GALLERY_TOP = tierTop(SEAT_TIERS) -- top gallery floor, level with the top tier
local STOREY = (GALLERY_TOP - FLOOR_TOP) / 3 -- three arcade storeys below it
local OUTER_TOP = GALLERY_TOP + Architecture.AtticHeight
local FACADE_ARCHES = Architecture.FacadeArches
-- Stair houses: under tiers 7 and 8, against the ambulatories (which stay clear), each storey
-- climbs in two flights that turn on a half landing. Local x runs along the ring, +z outward.
local TOWER_ANGLES = { 45, 135, 225, 315 }
local TOWER_INNER = tierFront(7)
local TOWER_HALF_DEPTH = (SEATS_END - TOWER_INNER) / 2
local TOWER_LENGTH, TOWER_END_WALL, TOWER_LANDING = 36, 3, 7
local TOWER_RISERS = math.round(STOREY / 2) -- per flight: ten steps, then the landing
-- Vomitoria: flat passages along the normal from the ambulatories of storeys 2 and 3 onto the
-- terrace at the same height (tier 2 and tier 5), one per level and quarter, clear of the stair
-- houses, the tribune stairs and the imperial box. `exit`: the offset where they come out.
local VOMITORIUM_HALF, VOMITORIUM_CLEAR = 4, 8
local VOMITORIA: { { theta: number, from: number, to: number, exit: number } } = {}
for _, set in {
	{ level = 1, tier = 2, degrees = { 3, 121, 177, 301 } },
	{ level = 2, tier = 5, degrees = { 59, 160, 239, 340 } },
} do
	for _, degrees in set.degrees do
		table.insert(VOMITORIA, { theta = math.rad(degrees), from = FLOOR_TOP + set.level * STOREY, to = tierTop(set.tier), exit = tierFront(set.tier + 1) })
	end
end

local ZOMBIE_GATE_ANGLES = { 0, 45, 135, 180, 225, 270, 315 }

local Arena = {}

Arena.Layout = {
	Center = Vector3.new(0, FLOOR_TOP, 0),
	SemiAxisX = A,
	SemiAxisZ = B,
	FloorTop = FLOOR_TOP,
	BarrierTop = BARRIER_TOP,
	OuterOffset = OUTER_OFFSET,
	SeatsEnd = SEATS_END,
	GalleryTop = GALLERY_TOP,
	Storey = STOREY,
	PodiumThickness = PODIUM_THICKNESS,
	PodiumHeight = PODIUM_HEIGHT,
	SeatTiers = SEAT_TIERS,
	-- The main gladiator gate (north, under the OTTI ARENA sign): Otti enters here
	MainGateAngle = math.rad(270),
	-- Where the fighter enters the arena floor (south, facing the center)
	StartPosition = Vector3.new(0, FLOOR_TOP + 3.5, B - 10),
	-- Lower tribune walkway (top of the first seating tier) and its return door
	TribuneWalkwayY = tierTop(1),
	ReturnDoor = nil :: BasePart?,
	-- Imperial box (pulvinar) above the north side: Otti watches the zombie rounds from here
	ImperialSeat = CFrame.identity, -- floor point in front of the throne, facing the arena
	ImperialRail = CFrame.identity, -- top of the front railing (where Otti jumps from)
	BossStart = CFrame.identity, -- where Otti lands on the sand
	ZombieSpawns = {} :: { CFrame },
	-- Passages from the galleries onto the stands (theta, gallery floor, terrace floor, exit offset)
	Vomitoria = {} :: { { theta: number, from: number, to: number, exit: number } },
	-- Every flight of the stair houses: foot of its first step, its run direction and size
	StairFlights = {} :: { { cf: CFrame, rise: number, run: number, count: number } },
	-- 12 symmetric shell spots; any prefix of 4, 6, 8, 10 or 12 stays point-symmetric
	ShellPositions = {
		Vector3.new(35, FLOOR_TOP + 2, 0),
		Vector3.new(-35, FLOOR_TOP + 2, 0),
		Vector3.new(0, FLOOR_TOP + 2, 27),
		Vector3.new(0, FLOOR_TOP + 2, -27),
		Vector3.new(25, FLOOR_TOP + 2, 19),
		Vector3.new(-25, FLOOR_TOP + 2, -19),
		Vector3.new(-25, FLOOR_TOP + 2, 19),
		Vector3.new(25, FLOOR_TOP + 2, -19),
		Vector3.new(14, FLOOR_TOP + 2, 0),
		Vector3.new(-14, FLOOR_TOP + 2, 0),
		Vector3.new(0, FLOOR_TOP + 2, 12),
		Vector3.new(0, FLOOR_TOP + 2, -12),
	},
}

-- Ellipse helpers (y = 0 plane). Offset moves along the outward normal.
local function normal(theta: number): Vector3
	return Vector3.new(math.cos(theta) / A, 0, math.sin(theta) / B).Unit
end

local function ellipsePoint(theta: number, offset: number): Vector3
	return Vector3.new(A * math.cos(theta), 0, B * math.sin(theta)) + normal(theta) * offset
end

-- CFrame on the curve at height y whose LookVector (-Z) points into the arena.
local function frameAt(theta: number, offset: number, y: number): CFrame
	local p = ellipsePoint(theta, offset)
	local n = normal(theta)
	local position = Vector3.new(p.X, y, p.Z)
	return CFrame.lookAt(position, position - n)
end

-- Frame for segment i of a ring, aligned with its chord (-Z points into the arena).
local function segmentFrame(i: number, segments: number, offset: number, y: number): (CFrame, number)
	local a = ellipsePoint(i / segments * 2 * math.pi, offset)
	local b = ellipsePoint((i + 1) / segments * 2 * math.pi, offset)
	local mid = (a + b) / 2
	local tangent = (b - a).Unit
	return CFrame.fromMatrix(Vector3.new(mid.X, y, mid.Z), -tangent, Vector3.yAxis), (b - a).Magnitude
end

type PartOptions = {
	shape: Enum.PartType?,
	collide: boolean?,
	transparency: number?,
}

local function makePart(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, parent: Instance, options: PartOptions?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if options then
		if options.shape then
			part.Shape = options.shape
		end
		if options.collide == false then
			-- Decoration: never blocks players, zombies, pathfinding or combat raycasts
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
		if options.transparency then
			part.Transparency = options.transparency
		end
	end
	part.Parent = parent
	return part
end

local DECOR: PartOptions = { collide = false }

-- Rails and parapets stay low enough to look over; an invisible extension above each one reaches
-- GUARD_REACH over the floor it protects, so nobody jumps over it (jumps reach about 6.4) nor
-- onto it from a floor beside it (a terrace or balcony up to ten studs higher).
local GUARD_REACH = 17
local function guardAbove(parent: Instance, guard: BasePart, floorY: number)
	local top = guard.Position.Y + guard.Size.Y / 2
	local height = floorY + GUARD_REACH - top
	if height > 0.1 then
		local extension = makePart("GuardExtension", Vector3.new(guard.Size.X, height, guard.Size.Z), guard.CFrame * CFrame.new(0, guard.Size.Y / 2 + height / 2, 0), TRAVERTINE, Enum.Material.SmoothPlastic, parent, { transparency = 1 })
		extension.CanQuery = false
		extension.CanTouch = false
		extension.CastShadow = false
	end
end

-- A closed ring of wall segments around the oval. Segments overlap generously so the
-- outer corners never leave gaps.
local function ring(parent: Instance, name: string, segments: number, innerOffset: number, thickness: number, bottomY: number, topY: number, color: Color3, material: Enum.Material, options: PartOptions?)
	local model = Instance.new("Model")
	model.Name = name
	for i = 0, segments - 1 do
		local frame, chord = segmentFrame(i, segments, innerOffset + thickness / 2, (bottomY + topY) / 2)
		local opening = false
		if name == "PodiumWall" or name == "InvisibleBarrier" or name:match("^Tier") then
			for _, angle in Architecture.HeroAngles do
				-- Only as deep as the basement ramp tunnel (offset 2..30); the rest of the stand stays closed
				local p = Architecture.frame(math.rad(angle), 0, FLOOR_TOP):PointToObjectSpace(frame.Position)
				if math.abs(p.X) < Architecture.GateWidth/2 + chord/2 + 0.7 and p.Z > -3 and p.Z < 34 then opening = true end
			end
		end
		local bottom = if opening then math.max(bottomY, FLOOR_TOP + Architecture.GateHeight + 2) else bottomY
		local length = chord + thickness * 0.2 + 0.6
		-- Vomitoria cut a slot (from just below their floor to their ceiling) through every tier
		-- behind the terrace they open onto; the stair houses replace tiers 7 and 8 entirely
		-- (their end walls take the last stud and a half of the cut)
		local cuts = {}
		local function addCut(theta: number, half: number, y0: number, y1: number)
			local axis = frame:PointToObjectSpace(ellipsePoint(theta, innerOffset + thickness / 2) + Vector3.new(0, frame.Position.Y, 0))
			if math.abs(axis.Z) < thickness and math.abs(axis.X) < length / 2 + half then
				table.insert(cuts, { x0 = axis.X - half, x1 = axis.X + half, y0 = y0, y1 = y1 })
			end
		end
		if name:match("^Tier") or name == "SeatLip" then
			for _, v in VOMITORIA do
				if innerOffset >= v.exit - 0.01 then
					addCut(v.theta, VOMITORIUM_HALF, math.min(v.from, v.to) - 1, v.to + VOMITORIUM_CLEAR)
				end
			end
			if innerOffset >= TOWER_INNER - 0.01 then
				for _, degrees in TOWER_ANGLES do
					addCut(math.rad(degrees), TOWER_LENGTH / 2 - TOWER_END_WALL / 2, -math.huge, math.huge)
				end
			end
			table.sort(cuts, function(a, b)
				return a.x0 < b.x0
			end)
		end
		local function piece(x0: number, x1: number, y0: number, y1: number)
			if x1 - x0 > 0.05 and y1 - y0 > 0.05 then
				makePart("Segment", Vector3.new(x1 - x0, y1 - y0, thickness), frame * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2 - frame.Position.Y, 0), color, material, model, options)
			end
		end
		local cursor = -length / 2
		for _, cut in cuts do
			local c0, c1 = math.max(cut.x0, cursor), math.min(cut.x1, length / 2)
			piece(cursor, c0, bottom, topY)
			piece(c0, c1, bottom, math.min(cut.y0, topY))
			piece(c0, c1, math.max(cut.y1, bottom), topY)
			cursor = math.max(cursor, c1)
		end
		piece(cursor, length / 2, bottom, topY)
	end
	model.Parent = parent
end

local function buildFloor(folder: Folder)
	-- The old rectangular slab sealed every tunnel from above. The sand follows the oval in strips
	-- one stud deep, each as wide as the oval at its inner edge (a cylinder part would be circular:
	-- its diameter is the smaller of the two sizes). Strips reach at most a stud under the podium.
	local sand = Instance.new("Model")
	sand.Name = "Sand"
	for z0 = -B, B - 1 do
		local inner = math.min(math.abs(z0), math.abs(z0 + 1))
		local width = 2 * A * math.sqrt(math.max(0, 1 - (inner / B) ^ 2))
		makePart("Floor", Vector3.new(width, 1, 1), CFrame.new(0, FLOOR_TOP - 0.5, z0 + 0.5), SAND, Enum.Material.Sand, sand)
	end
	sand.Parent = folder
end

local function buildWalls(folder: Folder)
	-- Podium wall around the floor, plus an invisible barrier up to BARRIER_TOP on top of it
	ring(folder, "PodiumWall", 64, 0, PODIUM_THICKNESS, FLOOR_TOP, FLOOR_TOP + PODIUM_HEIGHT, TRAVERTINE, Enum.Material.Limestone)
	ring(folder, "InvisibleBarrier", 64, 0, PODIUM_THICKNESS, FLOOR_TOP + PODIUM_HEIGHT, BARRIER_TOP, TRAVERTINE, Enum.Material.SmoothPlastic, { transparency = 1 })

	-- Spectator seating rising steeply behind the podium: every terrace is a slab whose riser stands
	-- on the terrace below, so the substructure underneath stays open
	local seating = Instance.new("Model")
	seating.Name = "Seating"
	for tier = 1, SEAT_TIERS do
		local top = tierTop(tier)
		local color = if tier % 2 == 1 then SANDSTONE else TRAVERTINE
		ring(seating, "Tier" .. tier, 48, tierFront(tier), tierDepth(tier), tierBottom(tier), top, color, Enum.Material.Sandstone)
		-- Marble lip along the front of every terrace (the upper storey's parapet is a taller riser)
		ring(seating, "SeatLip", 48, tierFront(tier), 1.2, top, top + 0.3, TRAVERTINE, Enum.Material.Marble, DECOR)
	end
	seating.Parent = folder
end

-- Under the stands: one paved hall from the podium to the facade, open to the ambulatory, its
-- vault the stepped underside of the terraces. Piers under the risers carry the slabs (none on
-- the way to the hero gates, under a vomitorium or in a stair house), every other one with a lamp.
local function buildSubstructure(folder: Folder)
	local model = Instance.new("Model")
	model.Name = "Substructure"
	local bands = 4
	local inner, outer = PODIUM_THICKNESS - 0.5, SEATS_END + 0.5
	for band = 0, bands - 1 do
		local o0 = inner + band * (outer - inner) / bands
		ring(model, "HallFloor", FACADE_ARCHES, o0, (outer - inner) / bands + 0.5, FLOOR_TOP - 1, FLOOR_TOP, TRAVERTINE, Enum.Material.Pavement)
	end
	local function clear(theta: number, degrees: number): boolean
		for _, angle in Architecture.HeroAngles do
			if math.abs((math.deg(theta) - angle + 180) % 360 - 180) < degrees + 4 then
				return false
			end
		end
		for _, angle in TOWER_ANGLES do
			if math.abs((math.deg(theta) - angle + 180) % 360 - 180) < degrees + 2 then
				return false
			end
		end
		for _, v in VOMITORIA do
			if math.abs((math.deg(theta) - math.deg(v.theta) + 180) % 360 - 180) < degrees then
				return false
			end
		end
		return true
	end
	local lit = 0
	for j = 0, FACADE_ARCHES / 4 - 1 do
		local theta = (4 * j + 2) / FACADE_ARCHES * 2 * math.pi
		for tier = 2, SEAT_TIERS do
			if clear(theta, 5) then
				local height = tierBottom(tier) - FLOOR_TOP
				local pier = frameAt(theta, tierFront(tier) + 1.5, FLOOR_TOP + height / 2)
				makePart("Pier", Vector3.new(3, height, 3), pier, SANDSTONE, Enum.Material.Limestone, model)
				lit += 1
				if lit % 2 == 0 then
					local lamp = makePart("HallLamp", Vector3.new(0.8, 1.2, 0.8), pier * CFrame.new(0, math.min(height - 1.5, 9) - height / 2, -1.9), Color3.fromRGB(255, 180, 90), Enum.Material.Neon, model, DECOR)
					local light = Instance.new("PointLight")
					light.Range = 26
					light.Brightness = 0.9
					light.Color = Color3.fromRGB(255, 205, 150)
					light.Parent = lamp
				end
			end
		end
	end
	model.Parent = folder
end

-- A Roblox-style figure in marble on a plinth; base on the sill, -Z = where it looks.
local MARBLE = Color3.fromRGB(236, 232, 222)
local function buildStatue(parent: Instance, base: CFrame, pose: number)
	local statue = Instance.new("Model")
	statue.Name = "Statue"
	local s = 2.1
	local hip = 1.2 + 2 * s
	makePart("Plinth", Vector3.new(4.6, 1.2, 3.6), base * CFrame.new(0, 0.6, 0), TRAVERTINE, Enum.Material.Limestone, statue, DECOR)
	for _, side in { -1, 1 } do
		makePart("Leg", Vector3.new(s, 2 * s, s), base * CFrame.new(side * s / 2, 1.2 + s, 0), MARBLE, Enum.Material.Marble, statue, DECOR)
	end
	makePart("Torso", Vector3.new(2 * s, 2 * s, s), base * CFrame.new(0, hip + s, 0), MARBLE, Enum.Material.Marble, statue, DECOR)
	local shoulder = hip + 2 * s - s / 2
	for _, side in { -1, 1 } do
		-- pose 1: the right arm raised in salute, pose 2: a sword held out in front
		local lift = if side == 1 and pose == 1 then 165 elseif side == 1 and pose == 2 then 90 else 0
		local arm = base * CFrame.new(side * 1.5 * s, shoulder, 0) * CFrame.Angles(math.rad(lift), 0, 0) * CFrame.new(0, -s / 2, 0)
		makePart("Arm", Vector3.new(s, 2 * s, s), arm, MARBLE, Enum.Material.Marble, statue, DECOR)
		if side == 1 and pose == 2 then
			makePart("Sword", Vector3.new(0.4, 0.4, 3.4 * s), arm * CFrame.new(0, -s, -1.7 * s), BRONZE, Enum.Material.Metal, statue, DECOR)
		end
	end
	local head = makePart("Head", Vector3.new(1.2 * s, 1.2 * s, 1.2 * s), base * CFrame.new(0, hip + 2 * s + 0.6 * s, 0), MARBLE, Enum.Material.Marble, statue, DECOR)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Parent = head
	statue.Parent = parent
end

-- A small wall lamp (decoration) with a warm light.
local function lamp(parent: Instance, cframe: CFrame)
	local flame = makePart("Lamp", Vector3.new(0.8, 1.2, 0.8), cframe, Color3.fromRGB(255, 180, 90), Enum.Material.Neon, parent, DECOR)
	local light = Instance.new("PointLight")
	light.Range = 24
	light.Brightness = 0.9
	light.Color = Color3.fromRGB(255, 205, 150)
	light.Parent = flame
end

-- Behind the top tier: an ambulatory on every storey (the ground one open to the hall under the
-- stands), the top one level with the top tier and roofed, open to the seats. Nothing stands in
-- them: the stairs climb in the stair houses beside them. Over the open substructure the
-- ambulatories of storeys 2 and 3 have a railing, broken only by the vomitoria and stair houses.
local function towerFrame(degrees: number): CFrame
	return frameAt(math.rad(degrees), TOWER_INNER + TOWER_HALF_DEPTH, FLOOR_TOP)
end

local function buildGalleries(folder: Folder)
	local galleries = Instance.new("Model")
	galleries.Name = "Galleries"
	local inner = SEATS_END
	ring(galleries, "GalleryFloor", FACADE_ARCHES, inner - 0.5, OUTER_OFFSET - inner + 0.5, FLOOR_TOP - 1, FLOOR_TOP, TRAVERTINE, Enum.Material.Pavement)
	for level = 1, 3 do
		local y = FLOOR_TOP + level * STOREY
		ring(galleries, if level == 3 then "GalleryFloor" else "Ambulatory", FACADE_ARCHES, inner - 0.5, GALLERY_END - inner + 1, y - 1, y, TRAVERTINE, if level == 3 then Enum.Material.Pavement else Enum.Material.Limestone)
	end
	ring(galleries, "GalleryVault", FACADE_ARCHES, inner, GALLERY_END - inner, GALLERY_TOP + 14, GALLERY_TOP + 16, STONE_DARK, Enum.Material.Limestone)
	-- holes in the railing: { theta, half width along the ring }
	local holes: { { number } } = {}
	for _, degrees in TOWER_ANGLES do
		table.insert(holes, { math.rad(degrees), TOWER_LENGTH / 2 - 0.5 })
	end
	local function rail(i: number, y: number)
		local frame, chord = segmentFrame(i, FACADE_ARCHES, inner + 0.3, y + 1.75)
		local spans = { { -(chord + 0.4) / 2, (chord + 0.4) / 2 } }
		local function open(theta: number, half: number)
			local axis = frame:PointToObjectSpace(ellipsePoint(theta, inner + 0.3) + Vector3.new(0, y + 1.75, 0))
			if math.abs(axis.Z) > 10 then
				return
			end
			local kept = {}
			for _, span in spans do
				table.insert(kept, { span[1], math.min(span[2], axis.X - half) })
				table.insert(kept, { math.max(span[1], axis.X + half), span[2] })
			end
			spans = kept
		end
		for _, hole in holes do
			open(hole[1], hole[2])
		end
		for _, v in VOMITORIA do
			if math.abs(v.from - y) < 0.1 then
				open(v.theta, VOMITORIUM_HALF)
			end
		end
		for _, span in spans do
			if span[2] - span[1] > 0.1 then
				local piece = makePart("GalleryRail", Vector3.new(span[2] - span[1], 3.5, 0.6), frame * CFrame.new((span[1] + span[2]) / 2, 0, 0), TRAVERTINE, Enum.Material.Limestone, galleries)
				guardAbove(galleries, piece, y)
			end
		end
	end
	for i = 0, FACADE_ARCHES - 1 do
		for level = 1, 2 do
			rail(i, FLOOR_TOP + level * STOREY)
		end
	end
	galleries.Parent = folder
end

-- The stair houses. Per storey: a flight of ten steps along the outer lane to the half landing
-- at the far end, a flight back along the inner lane to the next main landing. The main landings
-- open through the outer wall onto the ambulatory of their storey (on the ground also through the
-- inner wall into the hall); the top one comes out on the top tier. A spine wall parts the lanes,
-- a railing guards the stairwell up there, the walls stand as a parapet above tier 7.
local function buildStairHouses(folder: Folder)
	table.clear(Arena.Layout.StairFlights)
	local model = Instance.new("Model")
	model.Name = "StairHouses"
	local L, D = TOWER_LENGTH / 2, TOWER_HALF_DEPTH
	local inside = L - TOWER_END_WALL -- the landings' far edges
	local flightStart = inside - TOWER_LANDING -- flights run between -flightStart and flightStart
	local steps = TOWER_RISERS - 1
	local run = 2 * flightStart / steps
	local rise = STOREY / 2 / TOWER_RISERS
	local top = GALLERY_TOP
	local door = { x0 = -inside + 0.5, x1 = -flightStart - 0.5, height = 8 }
	for _, degrees in TOWER_ANGLES do
		local base = towerFrame(degrees)
		local house = Instance.new("Model")
		house.Name = "StairHouse"
		local function box(name: string, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, options: PartOptions?): Part?
			if x1 - x0 < 0.05 or y1 - y0 < 0.05 or z1 - z0 < 0.05 then
				return nil
			end
			return makePart(name, Vector3.new(x1 - x0, y1 - y0, z1 - z0), base * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2 - FLOOR_TOP, (z0 + z1) / 2), color, Enum.Material.Limestone, house, options)
		end
		for storey = 0, 2 do
			local y0 = FLOOR_TOP + storey * STOREY
			local half = y0 + STOREY / 2
			-- landings: the main one at the near end (not on the ground), the half one at the far end
			if storey > 0 then
				box("Landing", -inside, -flightStart, y0 - 1, y0, -D + 1, D - 0.4, TRAVERTINE)
			end
			box("Landing", flightStart, inside, half - 1, half, -D + 1, D - 1, TRAVERTINE)
			for k = 1, steps do
				local up = box("Step", -flightStart + (k - 1) * run - 0.05, -flightStart + k * run, y0 + k * rise - 1.2, y0 + k * rise, 0.5, D - 1, if k % 2 == 0 then TRAVERTINE else SANDSTONE)
				local back = box("Step", flightStart - k * run, flightStart - (k - 1) * run + 0.05, half + k * rise - 1.2, half + k * rise, -D + 1, -0.5, if k % 2 == 0 then TRAVERTINE else SANDSTONE)
				assert(up and back, "stair house step")
			end
			table.insert(Arena.Layout.StairFlights, { cf = base * CFrame.new(-flightStart, y0 - FLOOR_TOP, (D - 0.5) / 2) * CFrame.Angles(0, math.pi / 2, 0), rise = steps * rise, run = 2 * flightStart, count = steps })
			table.insert(Arena.Layout.StairFlights, { cf = base * CFrame.new(flightStart, half - FLOOR_TOP, -(D - 0.5) / 2) * CFrame.Angles(0, -math.pi / 2, 0), rise = steps * rise, run = 2 * flightStart, count = steps })
			lamp(house, base * CFrame.new(inside - 1, half + 6 - FLOOR_TOP, 0))
			lamp(house, base * CFrame.new(-inside + 1, y0 + 6 - FLOOR_TOP, -D + 2.5))
		end
		-- top: the main landing, the lid over the outer lane and the half landing below it
		box("Landing", -inside, -flightStart, top - 1, top, -D + 1, D - 0.4, TRAVERTINE)
		box("Lid", -flightStart, inside, top - 1, top, -0.5, D - 0.4, TRAVERTINE)
		local railing = box("StairwellRail", -flightStart, inside, top, top + 3.5, -0.8, -0.2, TRAVERTINE)
		if railing then
			guardAbove(house, railing, top)
		end
		-- walls: outer (doors at every main landing), inner (door on the ground, parapet on top),
		-- spine between the flights and the end walls (a parapet beside the stairwell)
		local doorTops = {}
		for storey = 0, 2 do
			table.insert(doorTops, FLOOR_TOP + storey * STOREY)
		end
		box("OuterWall", -L, door.x0, FLOOR_TOP, top, D - 1, D + 1, TRAVERTINE)
		box("OuterWall", door.x1, L, FLOOR_TOP, top, D - 1, D + 1, TRAVERTINE)
		for storey, y in doorTops do
			box("OuterWall", door.x0, door.x1, y + door.height, if storey < #doorTops then doorTops[storey + 1] - 1 else top, D - 1, D + 1, TRAVERTINE)
		end
		box("InnerWall", -L, door.x0, FLOOR_TOP, top + 3, -D - 1.5, -D + 1, SANDSTONE)
		box("InnerWall", door.x1, L, FLOOR_TOP, top + 3, -D - 1.5, -D + 1, SANDSTONE)
		box("InnerWall", door.x0, door.x1, FLOOR_TOP + door.height, top + 3, -D - 1.5, -D + 1, SANDSTONE)
		box("SpineWall", -flightStart, flightStart, FLOOR_TOP, top, -0.5, 0.5, SANDSTONE)
		for _, side in { -1, 1 } do
			local x0, x1 = if side < 0 then -L else inside, if side < 0 then -inside else L
			box("EndWall", x0, x1, FLOOR_TOP, top + 3, -D - 1.5, -0.5, SANDSTONE)
			box("EndWall", x0, x1, FLOOR_TOP, top, -0.5, D + 1, SANDSTONE)
		end
		for _, part in house:GetChildren() do
			if part:IsA("BasePart") and (part.Name == "InnerWall" or part.Name == "EndWall") and part.Position.Y + part.Size.Y / 2 > top + 1 then
				guardAbove(house, part, top)
			end
		end
		house.Parent = model
	end
	model.Parent = folder
end

-- The vomitoria themselves: a level floor inside the slot ring() cut through the tiers, on from
-- the ambulatory across the open substructure (with railings there), parapets where a slot opens
-- through the top of a terrace, and a lamp in every passage.
local function buildVomitoria(folder: Folder)
	local model = Instance.new("Model")
	model.Name = "Vomitoria"
	local width = VOMITORIUM_HALF * 2 - 0.2
	table.clear(Arena.Layout.Vomitoria)
	for _, v in VOMITORIA do
		local theta = v.theta
		table.insert(Arena.Layout.Vomitoria, { theta = theta, from = v.from, to = v.to, exit = v.exit })
		makePart("VomitoriumFloor", Vector3.new(width, 1, SEATS_END + 0.5 - v.exit), frameAt(theta, (v.exit + SEATS_END + 0.5) / 2, v.to - 0.5), TRAVERTINE, Enum.Material.Limestone, model)
		-- railings from the first tier whose slab starts above the floor out to the ambulatory
		local open = SEATS_END
		for tier = SEAT_TIERS, 1, -1 do
			if tierFront(tier) >= v.exit - 0.01 and tierBottom(tier) > v.to + 0.5 then
				open = tierFront(tier)
			end
		end
		for _, side in { -1, 1 } do
			local railing = makePart("VomitoriumRail", Vector3.new(0.6, 3.5, SEATS_END - open), frameAt(theta, (open + SEATS_END) / 2, v.to + 1.75) * CFrame.new(side * (VOMITORIUM_HALF - 0.3), 0, 0), TRAVERTINE, Enum.Material.Limestone, model)
			guardAbove(model, railing, v.to)
		end
		-- Parapets beside the slot where it is open to the sky, and across the front of the first
		-- terrace it runs under (that terrace's edge stands high above the open slot)
		local opened, covered = false, false
		for tier = 1, SEAT_TIERS do
			local front, depth = tierFront(tier), tierDepth(tier)
			local top = tierTop(tier)
			if front >= v.exit - 0.01 and top < v.to + VOMITORIUM_CLEAR then
				opened = true
				for _, side in { -1, 1 } do
					guardAbove(model, makePart("SlotParapet", Vector3.new(0.8, 3, depth), frameAt(theta, front + depth / 2, top + 1.5) * CFrame.new(side * (VOMITORIUM_HALF + 0.4), 0, 0), SANDSTONE, Enum.Material.Limestone, model), top)
				end
			elseif front >= v.exit - 0.01 and opened and not covered then
				covered = true
				guardAbove(model, makePart("SlotParapet", Vector3.new(2 * VOMITORIUM_HALF + 1.6, 3, 0.8), frameAt(theta, front + 0.4, top + 1.5), SANDSTONE, Enum.Material.Limestone, model), top)
			end
		end
		local light = makePart("VomitoriumLamp", Vector3.new(0.8, 0.8, 0.8), frameAt(theta, (v.exit + open) / 2, v.to + VOMITORIUM_CLEAR - 1), Color3.fromRGB(255, 180, 90), Enum.Material.Neon, model, DECOR)
		local glow = Instance.new("PointLight")
		glow.Range = 22
		glow.Brightness = 0.8
		glow.Color = Color3.fromRGB(255, 205, 150)
		glow.Parent = light
	end
	model.Parent = folder
end

-- The outer facade: three storeys of arches between engaged half columns (statues stand in every
-- arch of storeys 2 and 3 behind a low balustrade), an attic with a window per bay and a crown.
-- The ground arches lead out onto the plaza; Arena.setGroundExits opens them (Hub only).
local groundExits: { BasePart } = {}
local function buildFacade(folder: Folder)
	table.clear(groundExits)
	local facade = Instance.new("Model")
	facade.Name = "Facade"
	local thickness = OUTER_OFFSET - GALLERY_END
	local attic = OUTER_TOP - GALLERY_TOP
	local CYL = Enum.PartType.Cylinder
	for i = 0, FACADE_ARCHES - 1 do
		local frame, chord = segmentFrame(i - 0.5, FACADE_ARCHES, GALLERY_END + thickness / 2, FLOOR_TOP) -- arch i centred on i / FACADE_ARCHES
		local function at(x: number, y: number, z: number): CFrame
			return frame * CFrame.new(x, y, z)
		end
		local opening = chord * 0.55
		local pier = chord - opening
		local clear = STOREY - 6 -- opening height below the arch head
		local face = thickness / 2
		for storey = 0, 2 do
			local bottom = storey * STOREY
			makePart("Pier", Vector3.new(pier + 0.8, STOREY, thickness), at(chord / 2, bottom + STOREY / 2, 0), TRAVERTINE, Enum.Material.Limestone, facade)
			makePart("ArchHead", Vector3.new(opening + 0.4, STOREY - clear, thickness), at(0, bottom + clear + (STOREY - clear) / 2, 0), TRAVERTINE, Enum.Material.Limestone, facade)
			for _, side in { -1, 1 } do
				-- haunches round the arch's upper corners
				makePart("Haunch", Vector3.new(opening * 0.42, opening * 0.42, thickness + 0.2), at(side * opening / 2, bottom + clear, 0) * CFrame.Angles(0, 0, math.rad(45)), TRAVERTINE, Enum.Material.Limestone, facade, DECOR)
			end
			-- engaged half column on the pier and the storey's cornice (Tuscan, Ionic, Corinthian)
			makePart("HalfColumn", Vector3.new(STOREY - 1.6, 1.8, 1.8), at(chord / 2, bottom + STOREY / 2 - 0.8, face) * CFrame.Angles(0, 0, math.rad(90)), TRAVERTINE, Enum.Material.Limestone, facade, { shape = CYL, collide = false })
			makePart("Capital", Vector3.new(2.4, 0.8, 1.4), at(chord / 2, bottom + STOREY - 2, face + 0.3), if storey == 0 then TRAVERTINE else SANDSTONE, Enum.Material.Limestone, facade, DECOR)
			makePart("Cornice", Vector3.new(chord + 1.2, 1.2, 1.8), at(0, bottom + STOREY - 0.6, face + 0.5), STONE_DARK, Enum.Material.Limestone, facade, DECOR)
			if storey == 0 then
				local exit = makePart("GroundExit", Vector3.new(opening, clear, 0.4), at(0, clear / 2, face - 0.2), TRAVERTINE, Enum.Material.SmoothPlastic, facade, { transparency = 1 })
				exit.CanQuery = false
				exit.CanTouch = false
				table.insert(groundExits, exit)
			else
				makePart("Balustrade", Vector3.new(opening + 0.4, 3, 1), at(0, bottom + 1.5, face - 0.5), TRAVERTINE, Enum.Material.Limestone, facade)
				local pane = makePart("WindowGuard", Vector3.new(opening, clear - 3, 0.4), at(0, bottom + 3 + (clear - 3) / 2, face - 0.2), TRAVERTINE, Enum.Material.SmoothPlastic, facade, { transparency = 1 })
				pane.CanQuery = false
				pane.CanTouch = false
				buildStatue(facade, at(0, bottom, -0.6) * CFrame.Angles(0, math.pi, 0), (i + storey) % 3)
			end
		end
		-- Attic: a solid band with one window per bay, flat pilasters and the crowning cornice
		local a0 = 3 * STOREY
		local side = (chord - 4) / 2
		for _, s in { -1, 1 } do
			makePart("AtticWall", Vector3.new(side + 0.4, attic, thickness), at(s * (2 + side / 2), a0 + attic / 2, 0), TRAVERTINE, Enum.Material.Limestone, facade)
		end
		makePart("AtticWall", Vector3.new(4.4, 4, thickness), at(0, a0 + 2, 0), TRAVERTINE, Enum.Material.Limestone, facade)
		-- the window looks out over the grounds; a clear pane keeps the top gallery closed
		local window = makePart("WindowGuard", Vector3.new(4.4, 6, 0.4), at(0, a0 + 7, face - 0.2), TRAVERTINE, Enum.Material.SmoothPlastic, facade, { transparency = 1 })
		window.CanQuery = false
		window.CanTouch = false
		makePart("AtticWall", Vector3.new(4.4, attic - 10, thickness), at(0, a0 + 10 + (attic - 10) / 2, 0), TRAVERTINE, Enum.Material.Limestone, facade)
		makePart("Pilaster", Vector3.new(1.6, attic - 3, 0.6), at(chord / 2, a0 + (attic - 3) / 2, face + 0.3), SANDSTONE, Enum.Material.Limestone, facade, DECOR)
		makePart("Crown", Vector3.new(chord + 1.6, 2, 2.4), at(0, a0 + attic - 1, face + 0.6), STONE_DARK, Enum.Material.Limestone, facade, DECOR)
	end
	facade.Parent = folder
end

-- The ground outside the Colosseum: an endless granite plate of big tiles. Its top sits a hair
-- below the paved floors, so overlapping slabs never flicker.
local GRANITE = Color3.fromRGB(128, 126, 122)
local GROUND_TOP = FLOOR_TOP - 0.05
local GROUND_FAR = 4096
local function buildGround(folder: Folder)
	local ground = Instance.new("Model")
	ground.Name = "Ground"
	local n = 5 -- tiles up to 2048 wide, with no seam through the arena axes
	local size = 2 * GROUND_FAR / n
	for a = 0, n - 1 do
		for b = 0, n - 1 do
			makePart("Ground", Vector3.new(size, 1, size), CFrame.new(-GROUND_FAR + (a + 0.5) * size, GROUND_TOP - 0.5, -GROUND_FAR + (b + 0.5) * size), GRANITE, Enum.Material.Granite, ground)
		end
	end
	ground.Parent = folder
end

-- The invisible extension above a rail or parapet (see guardAbove), for the Hub's builders.
function Arena.guardAbove(parent: Instance, guard: BasePart, floorY: number)
	guardAbove(parent, guard, floorY)
end

local portcullises: { { model: Model, open: CFrame, closed: CFrame, main: boolean } } = {}

-- A barred gate in the podium wall (decoration only; the wall behind it is solid). Each gate has a
-- portcullis that drops for the boss round (Arena.setGates).
local function buildGate(parent: Instance, theta: number, name: string)
	local gate = Instance.new("Model")
	gate.Name = name
	local base = frameAt(theta, 0, FLOOR_TOP)
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x, y, z)
	end

	makePart("Opening", Vector3.new(7, 6, 0.4), at(0, 3, -0.2), OPENING, Enum.Material.Slate, gate, DECOR)
	makePart("ArchTop", Vector3.new(0.4, 7, 7), at(0, 6, -0.2) * CFrame.Angles(0, math.rad(90), 0), OPENING, Enum.Material.Slate, gate, { shape = Enum.PartType.Cylinder, collide = false })
	for x = -2.4, 2.41, 1.2 do
		makePart("Bar", Vector3.new(0.3, 8.4, 0.3), at(x, 4.2, -0.55), BRONZE, Enum.Material.Metal, gate, DECOR)
	end
	for _, y in { 2.5, 5.5 } do
		makePart("Band", Vector3.new(7, 0.3, 0.3), at(0, y, -0.6), BRONZE, Enum.Material.Metal, gate, DECOR)
	end
	for _, x in { -4.6, 4.6 } do
		makePart("Column", Vector3.new(PODIUM_HEIGHT, 1.4, 1.4), at(x, PODIUM_HEIGHT / 2, -0.3) * CFrame.Angles(0, 0, math.rad(90)), TRAVERTINE, Enum.Material.Limestone, gate, { shape = Enum.PartType.Cylinder, collide = false })
	end
	makePart("Keystone", Vector3.new(1, 1.4, 0.6), at(0, 9.9, -0.35), SANDSTONE, Enum.Material.Sandstone, gate, DECOR)

	-- Portcullis: a dark grid that drops in front of the opening (raised = hidden in the arch)
	local portcullis = Instance.new("Model")
	portcullis.Name = "Portcullis"
	local closed = at(0, 3.4, -1.0)
	local core = makePart("PortcullisFrame", Vector3.new(7.2, 0.4, 0.4), closed * CFrame.new(0, 3.4, 0), Color3.fromRGB(60, 50, 44), Enum.Material.Metal, portcullis, DECOR)
	for x = -3, 3.01, 1 do
		makePart("PortcullisBar", Vector3.new(0.35, 7, 0.35), closed * CFrame.new(x, 0, 0), Color3.fromRGB(60, 50, 44), Enum.Material.Metal, portcullis, DECOR)
	end
	for _, y in { -2.4, 0, 2.4 } do
		makePart("PortcullisBand", Vector3.new(7, 0.3, 0.3), closed * CFrame.new(0, y, 0), Color3.fromRGB(70, 58, 50), Enum.Material.Metal, portcullis, DECOR)
	end
	portcullis.PrimaryPart = core
	portcullis.Parent = gate
	local open = portcullis:GetPivot() + Vector3.new(0, 7.5, 0)
	local closedPivot = portcullis:GetPivot()
	portcullis:PivotTo(open)
	for _, part in portcullis:GetChildren() do
		if part:IsA("BasePart") then
			part.Transparency = 1
		end
	end
	table.insert(portcullises, { model = portcullis, open = open, closed = closedPivot, main = math.abs(theta - Arena.Layout.MainGateAngle) < 0.01 })

	gate.Parent = parent
end

local function buildGates(folder: Folder)
	local gates = Instance.new("Model")
	gates.Name = "Gates"
	for _, degrees in ZOMBIE_GATE_ANGLES do
		local theta = math.rad(degrees)
		buildGate(gates, theta, "ZombieGate")
		-- Zombies appear on the sand just in front of each gate, facing the center
		table.insert(Arena.Layout.ZombieSpawns, frameAt(theta, -5, FLOOR_TOP))
	end
	for _, angle in Architecture.HeroAngles do
		ColosseumGate.build(gates, Architecture.frame(math.rad(angle), 1, FLOOR_TOP))
	end
	gates.Parent = folder
end

local function buildBanners(folder: Folder)
	local banners = Instance.new("Model")
	banners.Name = "Banners"
	for degrees = 22.5, 360, 45 do
		local base = frameAt(math.rad(degrees), 0, FLOOR_TOP)
		makePart("Rod", Vector3.new(4, 0.3, 0.3), base * CFrame.new(0, PODIUM_HEIGHT - 0.4, -0.4), BRONZE, Enum.Material.Metal, banners, DECOR)
		makePart("Cloth", Vector3.new(3.4, 6, 0.15), base * CFrame.new(0, PODIUM_HEIGHT - 3.5, -0.3), BANNER_RED, Enum.Material.Fabric, banners, DECOR)
		makePart("Stripe", Vector3.new(3.4, 0.4, 0.17), base * CFrame.new(0, PODIUM_HEIGHT - 5.6, -0.32), GOLD, Enum.Material.Fabric, banners, DECOR)
	end
	banners.Parent = folder
end

-- Accessible spectator stands, all outside the invisible barrier (zombies can't get there):
-- lower walkway = top of seating tier 1, middle walkway = top of tier 3, two staircases up the
-- seats (scalaria) from the lower walkway to the top tier, a railing along the front, a viewing
-- platform and the return door.
local function buildTribune(folder: Folder)
	local tribune = Instance.new("Model")
	tribune.Name = "Tribune"
	local lowerY = tierTop(1)
	local middleY = tierTop(3)

	-- Railing along the front edge of the lower walkway
	ring(tribune, "Railing", 64, PODIUM_THICKNESS, 0.8, lowerY, lowerY + 2.8, TRAVERTINE, Enum.Material.Limestone)

	-- Two staircases: across every terrace they climb from its own top to the next terrace's,
	-- so each flight meets the riser above it level. A parapet on both sides of every step that
	-- stands more than a small step above the terrace beside it, so the stairs can only be left at
	-- their ends or where the terrace is level.
	for _, degrees in { 30, 210 } do
		local theta = math.rad(degrees)
		local stair = Instance.new("Model")
		stair.Name = "Staircase"
		for tier = 1, SEAT_TIERS - 1 do
			local front, depth, floor = tierFront(tier), tierDepth(tier), tierTop(tier)
			local rise = tierTop(tier + 1) - floor
			local steps = math.ceil(rise)
			local run = depth / steps
			for k = 1, steps do
				local top = floor + k * rise / steps
				local offset = front + run * (k - 0.5)
				makePart("Step", Vector3.new(5, top - floor + 0.5, run + 0.05), frameAt(theta, offset, (top + floor - 0.5) / 2), if k % 2 == 0 then TRAVERTINE else SANDSTONE, Enum.Material.Limestone, stair)
				if top - floor > 2 then
					for _, side in { -1, 1 } do
						guardAbove(stair, makePart("StairGuard", Vector3.new(0.6, 3.5, run + 0.05), frameAt(theta, offset, top + 1.75) * CFrame.new(side * 2.8, 0, 0), TRAVERTINE, Enum.Material.Limestone, stair), top)
					end
				end
			end
		end
		for _, side in { -1, 1 } do
			local a = frameAt(theta, tierFront(1), lowerY + 3) * CFrame.new(side * 2.7, 0, 0)
			local b = frameAt(theta, tierFront(SEAT_TIERS), GALLERY_TOP + 3) * CFrame.new(side * 2.7, 0, 0)
			local length = (b.Position - a.Position).Magnitude
			makePart("Handrail", Vector3.new(0.3, 0.3, length), CFrame.lookAt((a.Position + b.Position) / 2, b.Position), BRONZE, Enum.Material.Metal, stair, DECOR)
		end
		stair.Parent = tribune
	end

	-- Viewing platform on the middle walkway, south (the north side holds the imperial box)
	for _, degrees in { 90 } do
		local theta = math.rad(degrees)
		makePart("ViewingPlatform", Vector3.new(14, 1, 5), frameAt(theta, tierFront(3) + 2.5, middleY + 0.5), TRAVERTINE, Enum.Material.Marble, tribune)
		makePart("PlatformRail", Vector3.new(14, 2.5, 0.6), frameAt(theta, tierFront(3) + 0.3, middleY + 2.25), SANDSTONE, Enum.Material.Limestone, tribune)
		for _, side in { -1, 1 } do
			makePart("Post", Vector3.new(0.6, 5, 0.6), frameAt(theta, tierFront(3) + 0.3, middleY + 3.5) * CFrame.new(side * 6.7, 0, 0), BRONZE, Enum.Material.Metal, tribune, DECOR)
			makePart("Pennant", Vector3.new(1.6, 2.4, 0.1), frameAt(theta, tierFront(3) + 0.3, middleY + 4.6) * CFrame.new(side * 6.7 + side * 0.9, 0, 0), BANNER_RED, Enum.Material.Fabric, tribune, DECOR)
		end
	end

	-- Basement entrance / RETURN TO LOBBY: a barred door in the riser of tier 2, east side
	local doorBase = frameAt(0, tierFront(2), lowerY)
	makePart("DoorFrame", Vector3.new(6.4, 4.4, 0.4), doorBase * CFrame.new(0, 2.2, -0.15), STONE_DARK, Enum.Material.Limestone, tribune, DECOR)
	local door = makePart("ReturnDoor", Vector3.new(5, 4, 0.4), doorBase * CFrame.new(0, 2, -0.4), OPENING, Enum.Material.Slate, tribune, DECOR)
	for x = -2, 2, 1 do
		makePart("Bar", Vector3.new(0.25, 4, 0.25), doorBase * CFrame.new(x, 2, -0.7), BRONZE, Enum.Material.Metal, tribune, DECOR)
	end
	local sign = makePart("ReturnSign", Vector3.new(9, 1.4, 0.3), doorBase * CFrame.new(0, 4.9, -0.6), BANNER_RED, Enum.Material.Fabric, tribune, DECOR)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "RETURN TO HUB"
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = GOLD
	label.Parent = gui
	Arena.Layout.ReturnDoor = door

	tribune.Parent = folder
end

local function buildSign(folder: Folder)
	-- Sits on top of the podium behind the barrier, above the north gate
	local board = makePart("Sign", Vector3.new(22, 4, 0.8), frameAt(math.rad(270), 1.5, FLOOR_TOP + PODIUM_HEIGHT + 2.5), BRONZE, Enum.Material.Metal, folder, DECOR)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = board

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = BANNER_RED
	label.Text = "OTTI ARENA"
	label.Font = Enum.Font.Garamond
	label.TextScaled = true
	label.TextColor3 = GOLD
	label.Parent = gui
end

-- Spawns from a template place (e.g. Baseplate) would compete with ours; disable them for this session only.
local function disableOtherSpawns()
	local disabled = 0
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("SpawnLocation") and descendant.Enabled then
			descendant.Enabled = false
			disabled += 1
		end
	end
	if disabled > 0 then
		print(PREFIX, ("Disabled %d SpawnLocation(s) outside the arena for this session"):format(disabled))
	end
end

function Arena.build(): Folder
	local existing = Workspace:FindFirstChild(Config.ArenaFolderName)
	if existing then
		existing:Destroy()
		print(PREFIX, "Removed previous GeneratedArena before rebuilding")
	end
	disableOtherSpawns()
	table.clear(Arena.Layout.ZombieSpawns)
	table.clear(portcullises)

	local folder = Instance.new("Folder")
	folder.Name = Config.ArenaFolderName
	buildFloor(folder)
	buildWalls(folder)
	buildSubstructure(folder)
	buildGalleries(folder)
	buildStairHouses(folder)
	buildVomitoria(folder)
	buildFacade(folder)
	buildGround(folder)
	buildGates(folder)
	buildBanners(folder)
	buildTribune(folder)
	buildSign(folder)
	Arena.buildImperialBox(folder)
	Arena.buildSpawnBarriers(folder)
	Arena.buildEliminationBox(folder)
	Arena.buildSpectatorCameras(folder)

	local zombies = Instance.new("Folder")
	zombies.Name = Config.ZombiesFolderName
	zombies.Parent = folder

	folder.Parent = Workspace
	return folder
end

-- The imperial box (pulvinar): the most prestigious seat, centred above the north side with the
-- best view of the sand. Roman-inspired: stone floor and balustrade, columns with bronze capitals,
-- a red canopy with gold fringe, banners on the stand below and a cushioned stone throne.
-- Invisible walls keep players out (Otti's scripted jump is not affected by them).
function Arena.buildImperialBox(folder: Folder)
	local box = Instance.new("Model")
	box.Name = "ImperialBox"
	local theta = math.rad(270)
	local top = tierTop(2)
	local base = frameAt(theta, tierFront(2) + 3, top)
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x, y, z)
	end
	local CRIMSON = Color3.fromRGB(140, 24, 32)
	local CYL = Enum.PartType.Cylinder

	makePart("BoxFloor", Vector3.new(16, 1, 6), at(0, 0.5, 0), TRAVERTINE, Enum.Material.Marble, box)
	makePart("Carpet", Vector3.new(12, 0.06, 5), at(0, 1.03, 0.2), CRIMSON, Enum.Material.Fabric, box, DECOR)
	-- Throne: stone seat, red cushion, carved back with gold trim
	makePart("Throne", Vector3.new(3, 1.6, 2.4), at(0, 1.8, 1.6), SANDSTONE, Enum.Material.Limestone, box, DECOR)
	makePart("Cushion", Vector3.new(2.8, 0.4, 2.2), at(0, 2.8, 1.6), CRIMSON, Enum.Material.Fabric, box, DECOR)
	makePart("ThroneBack", Vector3.new(3.4, 3.2, 0.6), at(0, 3.6, 2.9), SANDSTONE, Enum.Material.Limestone, box, DECOR)
	makePart("ThroneTrim", Vector3.new(3.5, 0.25, 0.7), at(0, 5.25, 2.9), GOLD, Enum.Material.Metal, box, DECOR)
	for _, side in { -1, 1 } do
		makePart("Armrest", Vector3.new(0.5, 0.8, 2.2), at(side * 1.6, 2.6, 1.6), SANDSTONE, Enum.Material.Limestone, box, DECOR)
	end
	-- Front balustrade with balusters and gold trim
	makePart("RailBase", Vector3.new(16, 0.4, 0.7), at(0, 1.2, -2.7), TRAVERTINE, Enum.Material.Limestone, box, DECOR)
	makePart("RailTop", Vector3.new(16, 0.4, 0.6), at(0, 2.7, -2.7), TRAVERTINE, Enum.Material.Limestone, box, DECOR)
	makePart("RailTrim", Vector3.new(16, 0.15, 0.62), at(0, 2.95, -2.7), GOLD, Enum.Material.Metal, box, DECOR)
	for x = -7.5, 7.5, 1 do
		makePart("Baluster", Vector3.new(1.1, 0.35, 0.35), at(x, 1.95, -2.7) * CFrame.Angles(0, 0, math.rad(90)), TRAVERTINE, Enum.Material.Limestone, box, { shape = CYL, collide = false })
	end
	-- Columns with bronze capitals, red canopy with gold fringe and an eagle disc
	for _, x in { -7.4, 7.4 } do
		for _, z in { -2.6, 2.6 } do
			makePart("BoxColumn", Vector3.new(8, 0.9, 0.9), at(x, 5, z) * CFrame.Angles(0, 0, math.rad(90)), TRAVERTINE, Enum.Material.Marble, box, { shape = CYL, collide = false })
			makePart("Capital", Vector3.new(1.4, 0.5, 1.4), at(x, 9.1, z), BRONZE, Enum.Material.Metal, box, DECOR)
		end
	end
	makePart("Canopy", Vector3.new(16.4, 0.5, 6.4), at(0, 9.6, 0), CRIMSON, Enum.Material.Fabric, box, DECOR)
	makePart("Fringe", Vector3.new(16.4, 0.5, 0.2), at(0, 9.2, -3.2), GOLD, Enum.Material.Fabric, box, DECOR)
	makePart("EagleDisc", Vector3.new(0.2, 2.2, 2.2), at(0, 10.2, -3.3) * CFrame.Angles(0, math.rad(90), 0), GOLD, Enum.Material.Metal, box, { shape = CYL, collide = false })
	-- Banners on the stand below the box
	for _, x in { -5, 0, 5 } do
		makePart("ImperialBanner", Vector3.new(2.4, 4, 0.12), at(x, -1.8, -3.1), BANNER_RED, Enum.Material.Fabric, box, DECOR)
		makePart("BannerStripe", Vector3.new(2.4, 0.35, 0.14), at(x, -3.5, -3.12), GOLD, Enum.Material.Fabric, box, DECOR)
		makePart("BannerWreath", Vector3.new(0.14, 1.1, 1.1), at(x, -1.3, -3.13) * CFrame.Angles(0, math.rad(90), 0), GOLD, Enum.Material.Metal, box, { shape = CYL, collide = false })
	end
	-- Access restricted: invisible walls around the box (no queries: arrows and aim ignore them)
	for _, wall in {
		{ size = Vector3.new(16.6, 13, 0.4), position = Vector3.new(0, 7.5, -3.4) },
		{ size = Vector3.new(16.6, 13, 0.4), position = Vector3.new(0, 7.5, 3.4) },
		{ size = Vector3.new(0.4, 13, 7.2), position = Vector3.new(-8.3, 7.5, 0) },
		{ size = Vector3.new(0.4, 13, 7.2), position = Vector3.new(8.3, 7.5, 0) },
	} do
		local part = makePart("BoxBarrier", wall.size, at(wall.position.X, wall.position.Y, wall.position.Z), TRAVERTINE, Enum.Material.SmoothPlastic, box, { transparency = 1 })
		part.CanQuery = false
		part.CanTouch = false
	end
	box.Parent = folder

	Arena.Layout.ImperialSeat = at(0, 1, 1.0)
	Arena.Layout.ImperialRail = at(0, 2.95, -2.7)
	Arena.Layout.BossStart = frameAt(theta, -24, FLOOR_TOP)
end

-- Team spawn pens: translucent team-coloured barriers that hold both teams at their spawns during
-- the Team Battle arena countdown. Open (hidden, non-colliding) otherwise.
local spawnBarriers: { BasePart } = {}

function Arena.buildSpawnBarriers(folder: Folder)
	table.clear(spawnBarriers)
	local model = Instance.new("Model")
	model.Name = "SpawnBarriers"
	for _, side in { -1, 1 } do
		local color = if side < 0 then Color3.fromRGB(255, 90, 90) else Color3.fromRGB(110, 160, 255)
		local inner = side * (A - 18)
		local outer = side * (A - 3)
		local walls = {
			{ size = Vector3.new(0.6, 10, 20), position = Vector3.new(inner, FLOOR_TOP + 5, 0) },
			{ size = Vector3.new(math.abs(outer - inner), 10, 0.6), position = Vector3.new((inner + outer) / 2, FLOOR_TOP + 5, -10) },
			{ size = Vector3.new(math.abs(outer - inner), 10, 0.6), position = Vector3.new((inner + outer) / 2, FLOOR_TOP + 5, 10) },
		}
		for _, wall in walls do
			local part = makePart("SpawnBarrier", wall.size, CFrame.new(wall.position), color, Enum.Material.ForceField, model, { transparency = 1 })
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			table.insert(spawnBarriers, part)
		end
	end
	model.Parent = folder
end

-- Closes (true) or opens the Team Battle spawn pens.
function Arena.setSpawnBarriers(closed: boolean)
	for _, part in spawnBarriers do
		part.CanCollide = closed
		part.Transparency = if closed then 0.4 else 1
	end
end

-- A CFrame on the arena oval at height y; LookVector points into the arena.
function Arena.frameAt(theta: number, offset: number, y: number): CFrame
	return frameAt(theta, offset, y)
end

-- Drops (closed = true) or raises the portcullises. `main`: nil = every gate, true = only the
-- main gladiator gate, false = every gate except the main one.
function Arena.setGates(closed: boolean, main: boolean?)
	local TweenService = game:GetService("TweenService")
	for _, gate in portcullises do
		if main == nil or gate.main == main then
			local model = gate.model
			local value = Instance.new("CFrameValue")
			value.Value = model:GetPivot()
			value.Changed:Connect(function(cframe: CFrame)
				if model.Parent then
					model:PivotTo(cframe)
				end
			end)
			local goal = if closed then gate.closed else gate.open
			TweenService:Create(value, TweenInfo.new(1.1, Enum.EasingStyle.Quad, if closed then Enum.EasingDirection.In else Enum.EasingDirection.Out), { Value = goal }):Play()
			for _, part in model:GetChildren() do
				if part:IsA("BasePart") then
					if closed then
						part.Transparency = 0
					else
						TweenService:Create(part, TweenInfo.new(1.1), { Transparency = 1 }):Play()
					end
				end
			end
			task.delay(1.3, function()
				value:Destroy()
			end)
		end
	end
end

-- True if a position is on the playable floor (margin > 0 is more forgiving).
function Arena.isInside(position: Vector3, margin: number?): boolean
	local m = margin or 0
	local x = position.X / (A + m)
	local z = position.Z / (B + m)
	return x * x + z * z <= 1 and position.Y >= FLOOR_TOP - 10 and position.Y <= BARRIER_TOP + 20
end

-- A floor-level point well inside the arena, in the direction of the given position.
function Arena.getSafePoint(position: Vector3): Vector3
	local theta = math.atan2(position.Z / B, position.X / A)
	local p = ellipsePoint(theta, -10)
	return Vector3.new(p.X, FLOOR_TOP, p.Z)
end

-- Where zombie-mode fighters enter the arena (south), spread out for up to four players.
function Arena.getStartCFrame(index: number?): CFrame
	local offset = ((index or 1) - 1) % 4 - 1.5
	local position = Arena.Layout.StartPosition + Vector3.new(if index then offset * 4 else 0, 0, 0)
	return CFrame.lookAt(position, Vector3.new(position.X, position.Y, 0))
end

-- Team Battle spawns: Red on the west end, Blue on the east end, facing each other.
function Arena.getTeamSpawnCFrame(team: string, index: number): CFrame
	local side = if team == "Red" then -1 else 1
	local lateral = ((index - 1) % 4 - 1.5) * 4
	local position = Vector3.new(side * (A - 12), FLOOR_TOP + 3.5, lateral)
	return CFrame.lookAt(position, Vector3.new(0, position.Y, lateral))
end

-- Spectator spots on the LOWER (close view) and MIDDLE (overview) walkways. The north side
-- (imperial box, Otti's entrance) and the two staircases are never used. `seed` spreads players.
local TRIBUNE_SPOTS: { { degrees: number, middle: boolean } } = {
	{ degrees = 0, middle = false }, { degrees = 60, middle = false }, { degrees = 120, middle = false },
	{ degrees = 180, middle = false }, { degrees = 150, middle = false }, { degrees = 330, middle = false },
	{ degrees = 90, middle = true }, { degrees = 15, middle = true }, { degrees = 195, middle = true },
	{ degrees = 135, middle = true }, { degrees = 75, middle = true }, { degrees = 345, middle = true },
}

function Arena.getTribuneCFrame(seed: number?): CFrame
	local spot = TRIBUNE_SPOTS[((seed or 0) % #TRIBUNE_SPOTS) + 1]
	local theta = math.rad(spot.degrees)
	if spot.middle then
		local middleY = tierTop(3)
		return frameAt(theta, tierFront(3) + 2, middleY + 3)
	end
	return frameAt(theta, PODIUM_THICKNESS + 3.5, Arena.Layout.TribuneWalkwayY + 3)
end

-- Elimination waiting box: a closed room far below the arena (nothing of the fight is visible
-- from inside; eliminated players watch through their teammates' cameras only).
local ELIMINATION_CENTER = Vector3.new(0, FLOOR_TOP - 80, 0)

function Arena.getEliminationCFrame(seed: number?): CFrame
	local offset = (((seed or 0) % 8) - 3.5) * 2.2
	local position = ELIMINATION_CENTER + Vector3.new(offset, 3.5, 0)
	return CFrame.lookAt(position, position + Vector3.zAxis)
end

function Arena.isInEliminationBox(position: Vector3): boolean
	local d = position - ELIMINATION_CENTER
	return math.abs(d.X) <= 14 and math.abs(d.Z) <= 14 and d.Y >= -4 and d.Y <= 14
end

function Arena.buildEliminationBox(folder: Folder)
	local box = Instance.new("Model")
	box.Name = "EliminationBox"
	local c = ELIMINATION_CENTER
	makePart("Floor", Vector3.new(26, 2, 26), CFrame.new(c - Vector3.new(0, 1, 0)), STONE_DARK, Enum.Material.Cobblestone, box)
	makePart("Ceiling", Vector3.new(26, 2, 26), CFrame.new(c + Vector3.new(0, 11, 0)), STONE_DARK, Enum.Material.Slate, box)
	for _, wall in { { Vector3.new(0, 5, 13), Vector3.new(26, 12, 1) }, { Vector3.new(0, 5, -13), Vector3.new(26, 12, 1) }, { Vector3.new(13, 5, 0), Vector3.new(1, 12, 26) }, { Vector3.new(-13, 5, 0), Vector3.new(1, 12, 26) } } do
		makePart("Wall", wall[2], CFrame.new(c + wall[1]), SANDSTONE, Enum.Material.Sandstone, box)
	end
	local lamp = makePart("Lamp", Vector3.one * 0.8, CFrame.new(c + Vector3.new(0, 9, 0)), Color3.fromRGB(255, 160, 80), Enum.Material.Neon, box, DECOR)
	local light = Instance.new("PointLight")
	light.Range = 30
	light.Brightness = 1.5
	light.Color = Color3.fromRGB(255, 190, 130)
	light.Parent = lamp
	box.Parent = folder
	game:GetService("CollectionService"):AddTag(box, Config.EliminatedBoxTag)
end

-- Fixed overview camera points for spectators (client: SpectatorController "Overview" mode).
function Arena.buildSpectatorCameras(folder: Folder)
	local cameras = Instance.new("Folder")
	cameras.Name = "SpectatorCameras"
	local center = Vector3.new(0, FLOOR_TOP, 0)
	local points = {
		{ name = "High South", position = Vector3.new(0, FLOOR_TOP + 46, B + 30) },
		{ name = "High East", position = Vector3.new(A + 32, FLOOR_TOP + 40, 0) },
		{ name = "High West", position = Vector3.new(-A - 32, FLOOR_TOP + 40, 0) },
		{ name = "Imperial View", position = Vector3.new(0, FLOOR_TOP + 36, -B - 26) },
		{ name = "Top Down", position = Vector3.new(0, FLOOR_TOP + 110, 1) },
	}
	for i, point in points do
		local part = Instance.new("Part")
		part.Name = "Camera_" .. i
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.one
		part.CFrame = CFrame.lookAt(point.position, center)
		part:SetAttribute("Order", i)
		part:SetAttribute("Label", point.name)
		part.Parent = cameras
		game:GetService("CollectionService"):AddTag(part, "SpectatorCamera")
	end
	cameras.Parent = folder
end

-- True if a position is somewhere on the spectator stands or in the galleries behind them
-- (between barrier and facade).
function Arena.isInTribune(position: Vector3): boolean
	return not Arena.isInside(position, PODIUM_THICKNESS - 0.5)
		and Arena.isInside(position, OUTER_OFFSET)
		and position.Y >= FLOOR_TOP - 1
		and position.Y <= OUTER_TOP + 10
end

-- Opens (true) or closes the ground-floor arches between galleries and plaza. Closed by
-- default: in the fight place the spectators stay inside; the Hub lets players walk out.
function Arena.setGroundExits(open: boolean)
	for _, exit in groundExits do
		exit.CanCollide = not open
	end
end

-- True anywhere above ground: the granite ground, galleries, stands (not the sand).
function Arena.isOnGrounds(position: Vector3): boolean
	return math.abs(position.X) <= GROUND_FAR
		and math.abs(position.Z) <= GROUND_FAR
		and position.Y >= FLOOR_TOP - 1
		and position.Y <= OUTER_TOP + 10
		and not (Arena.isInside(position, PODIUM_THICKNESS - 0.5) and position.Y < FLOOR_TOP + PODIUM_HEIGHT + 2)
end

return Arena
