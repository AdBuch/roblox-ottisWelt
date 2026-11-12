--!strict
-- ROME on the world disc: the deterministic plan of the Hub's island town. Pure data and plain
-- geometry (numbers only, no Roblox types), so tests can check it outside Roblox.
--
-- Coordinates: x east, z SOUTH (Roblox: -Z is north), y up, in studs. The Colosseum stands at the
-- origin (outer facade ~ 338 x 282 studs). The town lies west of it on three terraces:
--   UPPER  y  1   x >= -232     Colosseum, its plaza and the west forecourt (Kolosseumsvorplatz)
--   LOWER  y -2   -508..-232    Handwerksgasse, forum and temple, living quarter (north), villas (south)
--   HARBOR y -6   x < -508      fortified harbour: quays, warehouses, the two moles
-- Sea level is y -12 (a voxel boundary: the sea surface is flat). Retaining walls separate the terraces; streets ramp through them.
--
-- SCALE (docs/ROM_INSEL.md): the Colosseum is fixed at about 0.56 m per stud (189 m <-> 338 studs),
-- avatars at about 0.35 m per stud. The town keeps avatar-sized houses (doors 8 studs, storeys
-- 8.5) and is compressed: the walled town (plus the quarter around the harbour basin, without
-- its water) measures `cityArea()` stud^2 = about 0.27 km^2 at 1 m per stud, the ~22 ha of the
-- Pompeii reference at a compression of ~1.0-1.1 m per stud, i.e. 0.35-0.4 of the Colosseum's
-- scale. The island around it (fields, forest, beach) is about twice the town's area.

export type Point = { x: number, z: number }
export type StreetPoint = { x: number, z: number, y: number }
export type StreetKind = "Main" | "Lane" | "Shore"
export type Street = { id: string, name: string, kind: StreetKind, points: { StreetPoint } }
export type Crossing = { id: string, street: string, segment: number, t: number, stones: number, lowered: boolean, label: string }
export type HouseType = "Row" | "Tenement" | "Shop" | "Courtyard" | "Villa" | "Storehouse"
export type FrontItem = { type: HouseType, w: number, d: number, name: string?, special: string?, open: boolean?, variant: string? }
export type Front = { side: "N" | "S" | "E" | "W", start: number, dir: number, square: string?, items: { FrontItem } }
export type Block = { id: string, district: string, level: number, x0: number, x1: number, z0: number, z1: number, fronts: { Front } }
export type House = {
	id: string,
	type: HouseType,
	variant: string,
	name: string?,
	special: string?,
	open: boolean, -- has a playable interior in the MVP (only the smithy)
	facesStreet: boolean,
	square: string?, -- the facade looks onto this square (RomeLayout.Squares) rather than a street
	block: string,
	district: string,
	x: number, -- footprint centre
	z: number,
	w: number, -- along the street
	d: number, -- depth into the block
	fx: number, -- facade direction (unit, pointing at the street)
	fz: number,
	level: number,
	floors: number,
	seed: number,
	door: { x: number, z: number, y: number, fx: number, fz: number },
}

local RomeLayout = {}

RomeLayout.Levels = table.freeze({ Upper = 1, Lower = -2, Harbor = -6, Water = -12, SeaFloor = -42 })
RomeLayout.Terraces = table.freeze({ UpperLowerX = -232, LowerHarborX = -508 })

-- Street cross sections (studs): carriageway, each sidewalk incl. its kerb, sidewalk height.
RomeLayout.Sections = table.freeze({
	Main = table.freeze({ road = 10, walk = 4.5, kerb = 0.7 }),
	Lane = table.freeze({ road = 6, walk = 2.5, kerb = 0.55 }),
	Shore = table.freeze({ road = 14, walk = 0, kerb = 0 }),
})

function RomeLayout.halfWidth(kind: StreetKind): number
	local s = RomeLayout.Sections[kind]
	return s.road / 2 + s.walk
end

-- Terrace level for a point of the town (no ramps; streets carry their own heights).
function RomeLayout.levelAt(x: number, _z: number): number
	if x >= RomeLayout.Terraces.UpperLowerX then
		return RomeLayout.Levels.Upper
	elseif x >= RomeLayout.Terraces.LowerHarborX then
		return RomeLayout.Levels.Lower
	end
	return RomeLayout.Levels.Harbor
end

----------------------------------------------------------------------------- outlines
-- The town wall, clockwise from the north mole head round the Colosseum's east side to the south
-- mole head. The harbour mouth between the last and the first point stays open.
RomeLayout.Wall = table.freeze({
	{ x = -712, z = -24 }, { x = -688, z = -62 }, { x = -640, z = -108 }, { x = -580, z = -150 },
	{ x = -510, z = -186 }, { x = -420, z = -204 }, { x = -320, z = -212 }, { x = -200, z = -214 },
	{ x = -90, z = -210 }, { x = 10, z = -198 }, { x = 110, z = -180 }, { x = 185, z = -130 },
	{ x = 226, z = -50 }, { x = 230, z = 40 }, { x = 196, z = 120 }, { x = 120, z = 178 },
	{ x = 10, z = 198 }, { x = -90, z = 210 }, { x = -200, z = 214 }, { x = -320, z = 212 },
	{ x = -420, z = 204 }, { x = -510, z = 186 }, { x = -580, z = 150 }, { x = -640, z = 108 },
	{ x = -688, z = 62 }, { x = -712, z = 24 },
} :: { Point })
RomeLayout.WallThickness = 5
RomeLayout.WallHeight = 14

-- The harbour basin (water inside the walls). The north quay -560..-648 is straight: the berth.
RomeLayout.Basin = table.freeze({
	{ x = -698, z = -18 }, { x = -678, z = -52 }, { x = -648, z = -76 }, { x = -560, z = -76 },
	{ x = -548, z = -60 }, { x = -542, z = -28 }, { x = -542, z = 28 }, { x = -548, z = 60 },
	{ x = -560, z = 76 }, { x = -648, z = 76 }, { x = -678, z = 52 }, { x = -698, z = 18 },
} :: { Point })
-- Water that the terrain leaves free: the basin plus the mouth between the moles to the sea.
RomeLayout.WaterCut = table.freeze({
	{ x = -760, z = -18 }, { x = -698, z = -18 }, { x = -678, z = -52 }, { x = -648, z = -76 },
	{ x = -560, z = -76 }, { x = -548, z = -60 }, { x = -542, z = -28 }, { x = -542, z = 28 },
	{ x = -548, z = 60 }, { x = -560, z = 76 }, { x = -648, z = 76 }, { x = -678, z = 52 },
	{ x = -698, z = 18 }, { x = -760, z = 18 },
} :: { Point })
RomeLayout.QuayWidth = 14
RomeLayout.MoleWidth = 10

-- The island's coastline (clockwise from the south mole).
RomeLayout.Coast = table.freeze({
	{ x = -722, z = 30 }, { x = -712, z = 82 }, { x = -680, z = 132 }, { x = -630, z = 182 },
	{ x = -560, z = 226 }, { x = -470, z = 262 }, { x = -360, z = 290 }, { x = -230, z = 305 },
	{ x = -100, z = 325 }, { x = 30, z = 332 }, { x = 160, z = 320 }, { x = 285, z = 282 },
	{ x = 390, z = 215 }, { x = 460, z = 120 }, { x = 495, z = 10 }, { x = 495, z = -110 },
	{ x = 470, z = -230 }, { x = 415, z = -345 }, { x = 330, z = -440 }, { x = 225, z = -510 },
	{ x = 95, z = -560 }, { x = -60, z = -590 }, { x = -200, z = -612 }, { x = -340, z = -625 },
	{ x = -460, z = -615 }, { x = -560, z = -575 }, { x = -625, z = -508 }, { x = -660, z = -450 },
	{ x = -700, z = -420 }, { x = -716, z = -386 }, { x = -700, z = -350 }, { x = -716, z = -318 },
	{ x = -748, z = -290 }, { x = -760, z = -230 }, { x = -754, z = -160 }, { x = -740, z = -100 },
	{ x = -726, z = -40 },
} :: { Point })
-- The world disc: the sea ends at its rim and falls into the depth.
RomeLayout.Disc = table.freeze({ x = -150, z = -140, radius = 1080, rim = 10 })

----------------------------------------------------------------------------- gates
RomeLayout.Gates = table.freeze({
	-- the land gate in the north wall, at the road to the fields and the forest
	Landtor = table.freeze({ x = -300, z = -212.3, width = 16, height = 16, yaw = 0, level = -2, name = "LANDTOR" }),
	-- the small coast gate in the north harbour flank: quay <-> coastal path
	Kuestentor = table.freeze({ x = -664, z = -85, width = 8, height = 11, yaw = math.deg(math.atan2(-46, 48)), level = -6, name = "KÜSTENTOR" }),
})

----------------------------------------------------------------------------- streets
local U, L, H = RomeLayout.Levels.Upper, RomeLayout.Levels.Lower, RomeLayout.Levels.Harbor
local function sp(x: number, z: number, y: number): StreetPoint
	return { x = x, z = z, y = y }
end
RomeLayout.Streets = table.freeze({
	-- the main axis: forecourt -> down into the Handwerksgasse -> forum entrance
	{ id = "Decumanus", name = "Handwerksgasse", kind = "Main", points = { sp(-214, 0, U), sp(-232, 0, U), sp(-260, 0, L), sp(-330, 0, L) } },
	-- forum -> living quarter (slight bend) -> Landtor
	{ id = "Landtorstrasse", name = "Landtorstrasse", kind = "Main", points = { sp(-372, -32, L), sp(-372, -100, L), sp(-318, -196, L), sp(-302, -206, L) } },
	-- forum -> past the temple -> down to the harbour
	{ id = "Hafenstrasse", name = "Hafenstrasse", kind = "Main", points = { sp(-423, -42, L), sp(-496, -42, L), sp(-526, -42, H), sp(-536, -42, H) } },
	{ id = "Villenstrasse", name = "Villenstrasse", kind = "Main", points = { sp(-372, 32, L), sp(-372, 100, L) } },
	{ id = "Nordgasse", name = "Nordgasse", kind = "Lane", points = { sp(-500, -120, L), sp(-262, -120, L), sp(-234, -120, U) } },
	{ id = "Suedgasse", name = "Südgasse", kind = "Lane", points = { sp(-500, 100, L), sp(-262, 100, L), sp(-234, 100, U) } },
	{ id = "Schmiedgasse", name = "Schmiedgasse", kind = "Lane", points = { sp(-318, 0, L), sp(-318, -120, L) } },
	{ id = "Tempelgasse", name = "Tempelgasse", kind = "Lane", points = { sp(-420, -32, L), sp(-420, -120, L) } },
	{ id = "Brunnengasse", name = "Brunnengasse", kind = "Lane", points = { sp(-318, 0, L), sp(-318, 100, L) } },
	{ id = "Hofgasse", name = "Hofgasse", kind = "Lane", points = { sp(-430, 32, L), sp(-430, 100, L) } },
	{ id = "Gartenschleife", name = "Gartenschleife", kind = "Lane", points = { sp(-372, 100, L), sp(-372, 170, L), sp(-262, 170, L), sp(-262, 100, L) } },
} :: { Street })

-- Pompeian stepping-stone crossings (segment index, position 0..1 along it).
RomeLayout.Crossings = table.freeze({
	{ id = "Kolosseumsvorplatz", street = "Decumanus", segment = 1, t = 0.45, stones = 3, lowered = true, label = "Kolosseumsvorplatz" },
	{ id = "Schmiedevorplatz", street = "Decumanus", segment = 3, t = 0.2, stones = 3, lowered = false, label = "Schmiedevorplatz" },
	{ id = "Forumseingang", street = "Decumanus", segment = 3, t = 0.86, stones = 3, lowered = true, label = "Forumseingang" },
	{ id = "AbzweigHafen", street = "Hafenstrasse", segment = 1, t = 0.3, stones = 3, lowered = true, label = "Abzweig Hafenstrasse" },
	{ id = "Landtor", street = "Landtorstrasse", segment = 2, t = 0.82, stones = 3, lowered = true, label = "Landtor" },
	{ id = "Schmiedgasse", street = "Schmiedgasse", segment = 1, t = 0.55, stones = 2, lowered = false, label = "Schmiedgasse" },
	{ id = "Suedgasse", street = "Suedgasse", segment = 1, t = 0.6, stones = 1, lowered = false, label = "Südgasse" },
} :: { Crossing })

----------------------------------------------------------------------------- squares
RomeLayout.Forum = table.freeze({ x0 = -446, x1 = -330, z0 = -32, z1 = 32, top = -1, colonnade = 27, columnStep = 8 })
-- Openings in the forum colonnades (x centre, half width) where streets come in
RomeLayout.ForumOpenings = table.freeze({
	north = table.freeze({ { x = -372, half = 10 }, { x = -420, half = 6 }, { x = -436, half = 10 } }),
	south = table.freeze({ { x = -372, half = 10 }, { x = -430, half = 6 } }),
})
RomeLayout.Temple = table.freeze({
	x0 = -500, x1 = -452, z0 = -17, z1 = 17, -- the podium
	top = 4, -- podium floor (forum + 5)
	stairsTo = -440, -- the front stairs run down into the forum's west end
	ramp = table.freeze({ x0 = -446, x1 = -490, z0 = 17, z1 = 23, landingTo = -500 }), -- the flat side ascent (south)
	cella = table.freeze({ x0 = -497, x1 = -466, z0 = -12, z1 = 12, wall = 1.5, height = 15 }),
	columns = 14,
})
RomeLayout.Forecourt = table.freeze({ x0 = -214, x1 = -160, z0 = -45, z1 = 45 }) -- Kolosseumsvorplatz
-- Small paved squares (polygons): the gate square inside the Landtor
RomeLayout.Squares = table.freeze({
	Torplatz = table.freeze({ { x = -299, z = -207 }, { x = -299, z = -128 }, { x = -352, z = -128 } } :: { Point }),
})
RomeLayout.Plaza = table.freeze({ inner = 92, outer = 118 }) -- paved ring round the Colosseum (ring offsets)

-- Lower work yards (Werkhöfe) behind the shop fronts of the Handwerksgasse: private, walled, with
-- lean-to sheds along one side (`shed`: "N" | "S" | "E" | "W" edge of the yard).
export type Yard = { id: string, block: string, x0: number, x1: number, z0: number, z1: number, level: number, shed: string }
RomeLayout.Yards = table.freeze({
	{ id = "WerkhofNord", block = "BN1", x0 = -290, x1 = -238, z0 = -92, z1 = -38, level = L, shed = "N" },
	{ id = "WerkhofSued", block = "BS1", x0 = -281, x1 = -238, z0 = 29, z1 = 75, level = L, shed = "S" },
} :: { Yard })
-- Low walls (2.4 studs, an invisible guard above) that close private yards and gardens toward the
-- public way; `gate` (0..1 along the wall) puts a closed arched gate (Torbogen) into it.
export type YardWall = { id: string, a: Point, b: Point, level: number, gate: number? }
RomeLayout.YardWalls = table.freeze({
	{ id = "BN1-Ost", a = { x = -235.6, z = -11.6 }, b = { x = -235.6, z = -94 }, level = L },
	{ id = "BN1-Sued", a = { x = -259.4, z = -11.6 }, b = { x = -235.6, z = -11.6 }, level = L, gate = 0.5 },
	{ id = "BS1-Ost", a = { x = -235.6, z = 11.6 }, b = { x = -235.6, z = 92.6 }, level = L },
	{ id = "BS1-Nord", a = { x = -261.4, z = 11.6 }, b = { x = -235.6, z = 11.6 }, level = L, gate = 0.5 },
	{ id = "BS1-Sued", a = { x = -265.4, z = 92.6 }, b = { x = -235.6, z = 92.6 }, level = L, gate = 0.55 },
	{ id = "BS1-Luecke", a = { x = -282.6, z = 92.6 }, b = { x = -279.4, z = 92.6 }, level = L },
	{ id = "BS6-Garten", a = { x = -358, z = 162.6 }, b = { x = -270, z = 162.6 }, level = L, gate = 0.5 },
	{ id = "BS6-West", a = { x = -364.6, z = 108 }, b = { x = -364.6, z = 162.6 }, level = L, gate = 0.5 },
	{ id = "BS3-West", a = { x = -423.6, z = 35 }, b = { x = -423.6, z = 92.6 }, level = L, gate = 0.5 },
	{ id = "BS4-Nord", a = { x = -505, z = 26.6 }, b = { x = -467, z = 26.6 }, level = L, gate = 0.5 },
	{ id = "BS5-Ost", a = { x = -383.6, z = 108 }, b = { x = -383.6, z = 181 }, level = L, gate = 0.6 },
} :: { YardWall })
RomeLayout.YardWallHeight = 2.4
-- Storage arcades (horrea) along the east quay: with the warehouses and the quay wall they close
-- the harbour front. They face the water (west).
RomeLayout.QuayArcades = table.freeze({
	{ id = "HorreaSued", x0 = -516, x1 = -510, z0 = -28, z1 = 60 },
	{ id = "HorreaNord", x0 = -516, x1 = -510, z0 = -90, z1 = -56 },
})

----------------------------------------------------------------------------- anchors
-- Named anchors (x, z, y = floor height, yaw = facing in degrees: 0 = north/-z, 90 = east/+x).
export type Anchor = { x: number, z: number, y: number, yaw: number }
RomeLayout.Anchors = table.freeze({
	CityGate = { x = -176, z = 0, y = U, yaw = 270 }, -- the forecourt in front of the Colosseum's west arch
	ForumFountain = { x = -346, z = 0, y = -1, yaw = 270 },
	ForumRespawn = { x = -337, z = 0, y = -1, yaw = 270 }, -- safe respawn after a fall off the world's edge
	QuestBoard = { x = -352, z = -24, y = -1, yaw = 180 }, -- reserved: notice board (later)
	QuestFigureA = { x = -346, z = -19, y = -1, yaw = 180 }, -- reserved: quest figures (later)
	QuestFigureB = { x = -358, z = -19, y = -1, yaw = 180 },
	TempleDoor = { x = -466, z = 0, y = 4, yaw = 90 },
	OracleSpot = { x = -486, z = 0, y = 4, yaw = 90 },
	Berth = { x = -608, z = -68, y = -12, yaw = 270 }, -- trireme placeholder centre (on the water)
	TravelPoint = { x = -608, z = -84, y = H, yaw = 0 }, -- later: boarding / travel interaction
	SecretRuin = { x = -698, z = -330, y = 0, yaw = 270 }, -- later: a hidden stair below the disc
	Viewpoint = { x = -712, z = -300, y = 0, yaw = 270 }, -- safe cliff with a view of the rim
	Clearing = { x = -430, z = -455, y = 0, yaw = 0 },
	Beach = { x = -672, z = -388, y = 0, yaw = 270 },
} :: { [string]: Anchor })
-- The trireme placeholder (outline only, kept free): 64 x 12 studs along the north quay.
RomeLayout.Trireme = table.freeze({ length = 64, beam = 12 })

----------------------------------------------------------------------------- houses
RomeLayout.TypeLabels = table.freeze({
	Row = "Reihenhaus", Tenement = "Mietshaus", Shop = "Ladenhaus", Courtyard = "Hofhaus", Villa = "Villa", Storehouse = "Speicher/Werkstatt",
})
RomeLayout.TypeTargets = table.freeze({ Row = 24, Tenement = 16, Shop = 16, Courtyard = 10, Villa = 6, Storehouse = 8 })
local FLOORS: { [HouseType]: number } = { Row = 2, Tenement = 3, Shop = 2, Courtyard = 1, Villa = 1, Storehouse = 2 }

local function item(t: HouseType, w: number, d: number, extra: { name: string?, special: string?, open: boolean?, variant: string? }?): FrontItem
	local e: { name: string?, special: string?, open: boolean?, variant: string? } = extra or {}
	return { type = t, w = w, d = d, name = e.name, special = e.special, open = e.open, variant = e.variant }
end

RomeLayout.Blocks = table.freeze({
	-- LOWER town, north of the main axis: crafts on the Handwerksgasse, the living quarter beyond
	{ id = "BN1", district = "Handwerk", level = L, x0 = -311, x1 = -234, z0 = -113, z1 = -11, fronts = {
		{ side = "S", start = -260, dir = -1, items = { item("Storehouse", 24, 24, { name = "SCHMIEDE · FABER", special = "Smithy", open = true, variant = "Workshop" }), item("Shop", 11, 16), item("Shop", 14, 16, { name = "PISTRINUM · BÄCKEREI", special = "Bakery" }) } },
		{ side = "W", start = -36, dir = -1, items = { item("Row", 13, 16), item("Tenement", 18, 18), item("Row", 13, 16), item("Tenement", 18, 18) } },
		{ side = "N", start = -290, dir = 1, items = { item("Row", 13, 18), item("Shop", 12, 18), item("Row", 13, 18), item("Row", 13, 18) } },
	} },
	{ id = "BN2a", district = "Wohnviertel", level = L, x0 = -361, x1 = -325, z0 = -113, z1 = -34, fronts = {
		{ side = "W", start = -36, dir = -1, items = { item("Tenement", 18, 16, { name = "ZUM GOLDENEN KORN", special = "Tavern" }), item("Shop", 12, 16), item("Tenement", 18, 16), item("Row", 11, 16) } },
		{ side = "E", start = -36, dir = -1, items = { item("Row", 13, 15), item("Tenement", 18, 15), item("Shop", 12, 15), item("Row", 13, 15) } },
	} },
	{ id = "BN2b", district = "Wohnviertel", level = L, x0 = -413, x1 = -383, z0 = -113, z1 = -34, fronts = {
		{ side = "E", start = -36, dir = -1, items = { item("Shop", 12, 15), item("Tenement", 18, 15), item("Shop", 12, 15), item("Row", 13, 15), item("Row", 13, 15) } },
		{ side = "W", start = -36, dir = -1, items = { item("Row", 13, 13), item("Tenement", 18, 13), item("Shop", 12, 13) } },
	} },
	{ id = "BN3", district = "Wohnviertel", level = L, x0 = -506, x1 = -427, z0 = -113, z1 = -53, fronts = {
		{ side = "S", start = -429, dir = -1, items = { item("Shop", 12, 18), item("Tenement", 18, 18), item("Shop", 12, 18), item("Tenement", 18, 18), item("Row", 13, 18) } },
		{ side = "N", start = -429, dir = -1, items = { item("Courtyard", 28, 28), item("Courtyard", 28, 28), item("Row", 13, 18) } },
	} },
	{ id = "BN4a", district = "Wohnviertel", level = L, x0 = -500, x1 = -386, z0 = -182, z1 = -127, fronts = {
		{ side = "S", start = -388, dir = -1, items = { item("Courtyard", 28, 28), item("Courtyard", 28, 28), item("Tenement", 18, 20), item("Courtyard", 28, 28) } },
	} },
	{ id = "BN4b", district = "Wohnviertel", level = L, x0 = -300, x1 = -234, z0 = -195, z1 = -127, fronts = {
		{ side = "W", start = -195, dir = 1, square = "Torplatz", items = { item("Shop", 16, 18, { name = "ZUM LETZTEN MEILENSTEIN", special = "Tavern" }), item("Row", 13, 16), item("Row", 13, 16), item("Tenement", 18, 18) } },
		{ side = "S", start = -280, dir = 1, items = { item("Row", 13, 16) } },
	} },
	-- LOWER town, south: shops on the axis, quieter courtyard houses and the villas
	{ id = "BS1", district = "Handwerk", level = L, x0 = -311, x1 = -234, z0 = 11, z1 = 93, fronts = {
		{ side = "N", start = -262, dir = -1, items = { item("Shop", 11, 16), item("Shop", 11, 16), item("Row", 12, 16), item("Row", 12, 16) } },
		{ side = "W", start = 31, dir = 1, items = { item("Courtyard", 28, 28), item("Tenement", 18, 18), item("Row", 12, 16) } },
		{ side = "S", start = -266, dir = -1, items = { item("Row", 13, 16) } },
	} },
	{ id = "BS2", district = "Villen", level = L, x0 = -361, x1 = -325, z0 = 34, z1 = 93, fronts = {
		{ side = "W", start = 36, dir = 1, items = { item("Tenement", 18, 16), item("Shop", 12, 16), item("Row", 13, 16) } },
		{ side = "E", start = 36, dir = 1, items = { item("Row", 12, 15), item("Shop", 11, 15), item("Tenement", 18, 15), item("Row", 12, 15) } },
	} },
	{ id = "BS3", district = "Villen", level = L, x0 = -424, x1 = -383, z0 = 34, z1 = 93, fronts = {
		{ side = "E", start = 36, dir = 1, items = { item("Courtyard", 28, 28), item("Courtyard", 28, 28) } },
	} },
	{ id = "BS4", district = "Villen", level = L, x0 = -506, x1 = -437, z0 = 26, z1 = 93, fronts = {
		{ side = "E", start = 35, dir = 1, items = { item("Courtyard", 28, 28), item("Tenement", 18, 18), item("Row", 10, 18) } },
		{ side = "S", start = -469, dir = -1, items = { item("Villa", 36, 34) } },
	} },
	{ id = "BS5", district = "Villen", level = L, x0 = -505, x1 = -383, z0 = 107, z1 = 182, fronts = {
		{ side = "N", start = -385, dir = -1, items = { item("Villa", 38, 40), item("Villa", 38, 40), item("Villa", 38, 40) } },
	} },
	{ id = "BS6", district = "Villen", level = L, x0 = -365, x1 = -269, z0 = 107, z1 = 163, fronts = {
		{ side = "N", start = -269, dir = -1, items = { item("Villa", 44, 40), item("Villa", 44, 40) } },
	} },
	-- UPPER terrace: warehouses and workshops north-west of the Colosseum
	{ id = "BU1", district = "Kolosseum", level = U, x0 = -226, x1 = -120, z0 = -205, z1 = -160, fronts = {
		{ side = "S", start = -224, dir = 1, items = { item("Storehouse", 24, 22), item("Storehouse", 22, 22, { variant = "Workshop" }), item("Courtyard", 28, 28), item("Tenement", 18, 18) } },
	} },
	-- HARBOR: warehouses and the harbour tavern behind the quays
	{ id = "BH1", district = "Hafen", level = H, x0 = -596, x1 = -516, z0 = -128, z1 = -92, fronts = {
		{ side = "S", start = -596, dir = 1, items = { item("Storehouse", 24, 24), item("Storehouse", 24, 24), item("Storehouse", 22, 22, { variant = "Workshop" }) } },
	} },
	{ id = "BH2", district = "Hafen", level = H, x0 = -596, x1 = -516, z0 = 92, z1 = 128, fronts = {
		{ side = "N", start = -596, dir = 1, items = { item("Storehouse", 24, 24), item("Shop", 16, 18, { name = "ZUM SALZIGEN ANKER", special = "Tavern" }), item("Storehouse", 24, 24) } },
	} },
} :: { Block })

local FACING: { [string]: { number } } = { N = { 0, -1 }, S = { 0, 1 }, E = { 1, 0 }, W = { -1, 0 } }

-- Deterministic small hash (seed per house).
local function hash(text: string): number
	local h = 2166136261
	for i = 1, #text do
		h = bit32.bxor(h, string.byte(text, i))
		h = (h * 16777619) % 4294967296
	end
	return h
end
RomeLayout.hash = hash

local cachedHouses: { House }? = nil
-- Every house of the town, in block / front order. Ids are stable: <block>-<side><index>.
function RomeLayout.houses(): { House }
	if cachedHouses then
		return cachedHouses
	end
	local list: { House } = {}
	for _, block in RomeLayout.Blocks do
		for _, front in block.fronts do
			local f = FACING[front.side]
			local fx, fz = f[1], f[2]
			local cursor = front.start
			for index, spec in front.items do
				local a, b = cursor, cursor + front.dir * spec.w
				local along = (a + b) / 2
				local x, z
				if front.side == "N" then
					x, z = along, block.z0 + spec.d / 2
				elseif front.side == "S" then
					x, z = along, block.z1 - spec.d / 2
				elseif front.side == "E" then
					x, z = block.x1 - spec.d / 2, along
				else
					x, z = block.x0 + spec.d / 2, along
				end
				local id = ("%s-%s%d"):format(block.id, front.side, index)
				local floors = FLOORS[spec.type]
				local seed = hash(id)
				if spec.type == "Row" or spec.type == "Shop" then
					floors += if seed % 3 == 0 then 0 else (if spec.type == "Shop" then -1 else 0)
					floors = math.max(1, floors)
				elseif spec.type == "Tenement" and seed % 4 == 0 then
					floors = 2
				elseif (spec.type == "Courtyard" or spec.type == "Villa") and seed % 3 == 0 then
					floors = 2
				end
				local doorX, doorZ = x + fx * spec.d / 2, z + fz * spec.d / 2
				table.insert(list, {
					id = id :: string,
					type = spec.type,
					variant = spec.variant or spec.type,
					name = spec.name,
					special = spec.special,
					open = spec.open == true,
					facesStreet = true,
					square = front.square,
					block = block.id,
					district = block.district,
					x = x,
					z = z,
					w = spec.w,
					d = spec.d,
					fx = fx,
					fz = fz,
					level = block.level,
					floors = floors,
					seed = seed,
					door = { x = doorX, z = doorZ, y = block.level, fx = fx, fz = fz },
				} :: any)
				cursor = b + front.dir * 1 -- a stud of eaves-drip between neighbours
			end
		end
	end
	cachedHouses = list
	return list
end

----------------------------------------------------------------------------- countryside
RomeLayout.Fields = table.freeze({ x0 = -250, x1 = 60, z0 = -440, z1 = -262, columns = 4, rows = 3, path = 10 })
RomeLayout.Forest = table.freeze({ x0 = -620, x1 = -280, z0 = -575, z1 = -330, trees = 90 })
-- Outside paths (polylines) with their markers. Width 7.
RomeLayout.Paths = table.freeze({
	{ id = "Feldweg", points = { { x = -300, z = -222 }, { x = -292, z = -250 }, { x = -250, z = -266 }, { x = -105, z = -266 }, { x = 60, z = -258 } } },
	{ id = "Waldweg", points = { { x = -260, z = -270 }, { x = -275, z = -330 }, { x = -345, z = -395 }, { x = -430, z = -455 }, { x = -520, z = -470 }, { x = -600, z = -440 }, { x = -668, z = -392 } } },
	{ id = "Kuestenpfad", points = { { x = -668, z = -392 }, { x = -672, z = -350 }, { x = -692, z = -302 }, { x = -726, z = -230 }, { x = -718, z = -160 }, { x = -700, z = -120 }, { x = -676, z = -96 } } },
	{ id = "Ostweg", points = { { x = 60, z = -258 }, { x = 200, z = -240 }, { x = 290, z = -150 }, { x = 300, z = 0 } } },
} :: { { id: string, points: { Point } } })
RomeLayout.PathWidth = 7

----------------------------------------------------------------------------- geometry helpers
function RomeLayout.pointInPolygon(x: number, z: number, polygon: { Point }): boolean
	local inside = false
	local j = #polygon
	for i = 1, #polygon do
		local a, b = polygon[i], polygon[j]
		if (a.z > z) ~= (b.z > z) and x < (b.x - a.x) * (z - a.z) / (b.z - a.z) + a.x then
			inside = not inside
		end
		j = i
	end
	return inside
end

function RomeLayout.polygonArea(polygon: { Point }): number
	local sum = 0
	local j = #polygon
	for i = 1, #polygon do
		sum += (polygon[j].x + polygon[i].x) * (polygon[j].z - polygon[i].z)
		j = i
	end
	return math.abs(sum) / 2
end

function RomeLayout.distanceToSegment(x: number, z: number, a: Point, b: Point): (number, number)
	local dx, dz = b.x - a.x, b.z - a.z
	local length2 = dx * dx + dz * dz
	local t = if length2 > 0 then math.clamp(((x - a.x) * dx + (z - a.z) * dz) / length2, 0, 1) else 0
	local px, pz = a.x + dx * t, a.z + dz * t
	return math.sqrt((x - px) ^ 2 + (z - pz) ^ 2), t
end

-- Distance to a polygon's outline (closed unless `open`).
function RomeLayout.distanceToOutline(x: number, z: number, polygon: { Point }, open: boolean?): number
	local best = math.huge
	local count = #polygon
	for i = 1, if open then count - 1 else count do
		local d = RomeLayout.distanceToSegment(x, z, polygon[i], polygon[i % count + 1])
		if d < best then
			best = d
		end
	end
	return best
end

-- The walled town incl. the harbour quarter: the wall polygon closed across the harbour mouth.
function RomeLayout.isInTown(x: number, z: number): boolean
	return RomeLayout.pointInPolygon(x, z, RomeLayout.Wall)
end
function RomeLayout.isWater(x: number, z: number): boolean
	return RomeLayout.pointInPolygon(x, z, RomeLayout.WaterCut)
end
function RomeLayout.isOnIsland(x: number, z: number): boolean
	return RomeLayout.pointInPolygon(x, z, RomeLayout.Coast) and not RomeLayout.isWater(x, z)
end

-- Area of the town in stud^2: the wall polygon minus the harbour basin's water.
function RomeLayout.cityArea(): (number, number, number)
	local walled = RomeLayout.polygonArea(RomeLayout.Wall)
	local basin = RomeLayout.polygonArea(RomeLayout.Basin)
	return walled - basin, walled, basin
end

-- Street geometry: segment endpoints with heights.
function RomeLayout.street(id: string): Street?
	for _, street in RomeLayout.Streets do
		if street.id == id then
			return street
		end
	end
	return nil
end

-- Distance of a point to the nearest street centreline and that street's kind.
function RomeLayout.nearestStreet(x: number, z: number): (number, Street?)
	local best, which = math.huge, nil
	for _, street in RomeLayout.Streets do
		for i = 1, #street.points - 1 do
			local a, b = street.points[i], street.points[i + 1]
			local d = RomeLayout.distanceToSegment(x, z, { x = a.x, z = a.z }, { x = b.x, z = b.z })
			if d < best then
				best, which = d, street
			end
		end
	end
	return best, which
end

return RomeLayout
