--!strict
-- Builds the Hub lobby: a gladiator dungeon beneath the Colosseum. Seen from the spawn (looking
-- north, the Otti statue beside the central approach):
--   FRONT  the ARENA GATE: a main corridor lined with zombie and gladiator cages (the ZOMBIE ARCHIVE)
--          rises gently to a portcullis; the sunlit arena is visible behind it (sealed, decor)
--   BACK   the monumental GATE TO ROME (closed for now; later the way into the open Roman world)
--   LEFT   TEAM HALL: opposing Schili / Krokero mosaics; both captains confirm
--   RIGHT  CO-OP: one Otti mosaic close to the hall, the TRAINING yard beyond
--   SIDES  stone stairs in the front corners up to the TRIBUNES doors (WATCH LIVE)
--   BACK-LEFT a side passage with a forge to the GLADIATOR ARMORY (weapons, shields, armor)
-- Pads come from LobbyPadDefinitions (LobbyPadService runs them). Everything is anchored Parts
-- with built-in materials (no asset ids); decoration never collides, is never queried and small
-- pieces cast no shadow. The whole lobby is a safe zone: no blood, no violence on display.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local LobbyPadDefinitions = require(ReplicatedStorage.Shared.LobbyPadDefinitions)
local LobbyMosaics = require(script.Parent.LobbyMosaics)
local LobbyStatue = require(script.Parent.LobbyStatue)

type PadDefinition = LobbyPadDefinitions.PadDefinition

local STONE = Color3.fromRGB(118, 104, 90)
local STONE_DARK = Color3.fromRGB(86, 76, 66)
local SANDSTONE = Color3.fromRGB(196, 164, 118)
local FLOOR = Color3.fromRGB(108, 98, 86)
local SAND = Color3.fromRGB(214, 190, 136)
local WOOD = Color3.fromRGB(116, 78, 46)
local DARK_WOOD = Color3.fromRGB(78, 52, 32)
local IRON = Color3.fromRGB(64, 64, 68)
local BRONZE = Color3.fromRGB(176, 125, 60)
local HAY = Color3.fromRGB(212, 180, 92)
local RED = Color3.fromRGB(128, 22, 28)
local GOLD = Color3.fromRGB(240, 196, 80)
local FLAME = Color3.fromRGB(255, 150, 60)
local WHITE = Color3.new(1, 1, 1)
local SOON = Color3.fromRGB(190, 190, 200)

local FLOOR_Y = -80

-- Central hall
local HALL_HX, HALL_HZ, HALL_H = 40, 36, 26
local WING_OPEN_HZ, WING_OPEN_H = 12, 16 -- openings to the wings (z -12..12)
local GATE_HX, GATE_H = 9, 18 -- the arena gate in the north wall

-- Main corridor to the arena (north)
local CORR_HX, CORR_H = 10, 22
local CAGE_DEPTH = 9
local FLAT_END, RAMP_END, LANDING_END = -88, -104, -112 -- z
local RAMP_RISE = 6

-- Wings
local MULTI_X0, MULTI_X1, MULTI_HZ, MULTI_H = -42, -114, 34, 22
local SINGLE_X0, SINGLE_X1, SINGLE_HZ, SINGLE_H = 42, 124, 28, 20

-- Gladiator Armory: the original chamber (local x -178..-78, z -38..38, door in its east wall)
-- moved as a whole to the end of the side passage behind the hall's south-west corner.
local ARMORY_X0, ARMORY_X1 = -178, -78
local ARMORY_HALF_Z = 38
local ARMORY_HEIGHT = 24
local ARMORY_OFFSET = Vector3.new(42, 0, 80) -- -> interior x -136..-36, z 42..118, door z 73..87
local DOOR_HALF = 7
local DOOR_HEIGHT = 13
local PASSAGE_X0, PASSAGE_X1 = -34, -20 -- side passage interior (south of the hall)
local PASSAGE_END = 88

-- A row of displays: centre on the floor, LookVector into the room, usable length along RightVector.
export type DisplayLine = { cframe: CFrame, length: number }

export type ArmoryLayout = {
	blades: DisplayLine,
	heavy: DisplayLine,
	ranged: DisplayLine,
	shields: { Light: DisplayLine, Balanced: DisplayLine, Heavy: DisplayLine },
	armor: DisplayLine,
	floorY: number,
}

export type PadButton = { action: string, part: BasePart }

export type PadLayout = {
	def: PadDefinition,
	cframe: CFrame, -- centre on the floor; -Z points to the pad's board
	size: Vector3, -- X x Z extent of the walk-on area
	status: TextLabel, -- live text on the pad's board (members, countdown, queue)
	ring: BasePart, -- glowing border (LobbyPadService colours it while players stand on it)
	buttons: { PadButton },
}

export type LobbyLayout = {
	folder: Folder,
	spawnCFrame: CFrame, -- safe return / respawn position
	arrivalSpawn: SpawnLocation, -- first character on a direct Hub join
	respawnSpawn: SpawnLocation, -- later characters and Arena returns
	armory: ArmoryLayout,
	pads: { PadLayout },
	arenaGate: BasePart, -- portcullis at the end of the main corridor (starts Solo Zombies)
	romeGate: BasePart, -- the closed gate to Rome
	tribuneDoors: { BasePart }, -- WATCH LIVE entrances at the top of the side stairs
	liveBoard: TextLabel,
	liveCFrame: CFrame, -- where returning spectators arrive
	archiveSlots: { CFrame },
	archivePlaques: { CFrame },
	trainingSlots: { CFrame },
	trainingCFrame: CFrame,
	trainingSize: Vector3,
	floorY: number,
}

local LobbyService = {}

-- Walkable volumes of the lobby (LobbyService.isInside); filled while building
type Zone = { min: Vector3, max: Vector3 }
local zones: { Zone } = {}

local function zone(x0: number, x1: number, z0: number, z1: number, height: number)
	table.insert(zones, {
		min = Vector3.new(math.min(x0, x1) - 1, FLOOR_Y - 10, math.min(z0, z1) - 1),
		max = Vector3.new(math.max(x0, x1) + 1, FLOOR_Y + height + 5, math.max(z0, z1) + 1),
	})
end

type PartOptions = { collide: boolean?, shape: Enum.PartType?, transparency: number?, shadow: boolean? }
local DECOR: PartOptions = { collide = false, shadow = false }

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
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
		if options.transparency then
			part.Transparency = options.transparency
		end
		if options.shadow == false then
			part.CastShadow = false
		end
	end
	part.Parent = parent
	return part
end

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, FLOOR_Y + y, z)
end

-- Facing helpers: a CFrame at (x, y, z) whose front (-Z) looks in the given direction.
local function facing(x: number, y: number, z: number, direction: Vector3): CFrame
	local position = Vector3.new(x, FLOOR_Y + y, z)
	return CFrame.lookAt(position, position + direction)
end

local NORTH, SOUTH, EAST, WEST = -Vector3.zAxis, Vector3.zAxis, Vector3.xAxis, -Vector3.xAxis

-- An axis-aligned box from two floor corners (x0..x1, z0..z1) and a height range.
local function box(name: string, parent: Instance, x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, color: Color3, material: Enum.Material, options: PartOptions?): Part
	return makePart(name, Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)), at((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), color, material, parent, options)
end

type Line = { text: string, color: Color3, scale: number }

-- A board with text on its front face. Returns the labels in order.
local function sign(parent: Instance, name: string, size: Vector3, cframe: CFrame, lines: { Line }, background: Color3): { TextLabel }
	local board = makePart(name, size, cframe, background, Enum.Material.Wood, parent, DECOR)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.MaxDistance = 140
	gui.Parent = board
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = gui
	local labels = {}
	for i, line in lines do
		local label = Instance.new("TextLabel")
		label.LayoutOrder = i
		label.Size = UDim2.fromScale(0.95, line.scale)
		label.BackgroundTransparency = 1
		label.Text = line.text
		label.Font = if i == 1 then Enum.Font.Garamond else Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = line.color
		label.Parent = gui
		table.insert(labels, label)
	end
	return labels
end

local function torch(parent: Instance, cframe: CFrame, range: number?)
	makePart("TorchBracket", Vector3.new(0.4, 0.4, 1.2), cframe * CFrame.new(0, 0, -0.5) * CFrame.Angles(math.rad(30), 0, 0), IRON, Enum.Material.Metal, parent, DECOR)
	local flame = makePart("TorchFlame", Vector3.one * 0.7, cframe * CFrame.new(0, 0.6, -0.95), FLAME, Enum.Material.Neon, parent, { collide = false, shadow = false, shape = Enum.PartType.Ball })
	local light = Instance.new("PointLight")
	light.Color = FLAME
	light.Range = range or 20
	light.Brightness = 1.4
	light.Parent = flame
	local fire = Instance.new("Fire")
	fire.Size = 2
	fire.Heat = 4
	fire.Color = FLAME
	fire.SecondaryColor = Color3.fromRGB(255, 220, 120)
	fire.Parent = flame
end

-- A fire bowl on a tripod (statue, forge): one light, one fire.
local function brazier(parent: Instance, x: number, z: number, height: number)
	makePart("BrazierStand", Vector3.new(0.6, height, 0.6), at(x, height / 2, z), IRON, Enum.Material.Metal, parent, DECOR)
	makePart("BrazierBowl", Vector3.new(0.8, 2.4, 2.4), at(x, height + 0.3, z) * CFrame.Angles(0, 0, math.rad(90)), BRONZE, Enum.Material.Metal, parent, { collide = false, shadow = false, shape = Enum.PartType.Cylinder })
	local coals = makePart("BrazierCoals", Vector3.new(2, 0.3, 2), at(x, height + 0.75, z), FLAME, Enum.Material.Neon, parent, DECOR)
	local light = Instance.new("PointLight")
	light.Color = FLAME
	light.Range = 26
	light.Brightness = 1.8
	light.Parent = coals
	local fire = Instance.new("Fire")
	fire.Size = 4
	fire.Heat = 7
	fire.Color = FLAME
	fire.SecondaryColor = Color3.fromRGB(255, 220, 120)
	fire.Parent = coals
end

local function banner(parent: Instance, cframe: CFrame, color: Color3?, text: string?)
	makePart("BannerRod", Vector3.new(4, 0.3, 0.3), cframe * CFrame.new(0, 3.2, -0.3), BRONZE, Enum.Material.Metal, parent, DECOR)
	local cloth = makePart("Banner", Vector3.new(3.4, 6, 0.15), cframe * CFrame.new(0, 0, -0.25), color or RED, Enum.Material.Fabric, parent, DECOR)
	makePart("BannerStripe", Vector3.new(3.4, 0.4, 0.17), cframe * CFrame.new(0, -2.2, -0.27), GOLD, Enum.Material.Fabric, parent, DECOR)
	if text then
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.MaxDistance = 90
		gui.Parent = cloth
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(0.9, 0.5)
		label.Position = UDim2.fromScale(0.05, 0.15)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.Garamond
		label.TextScaled = true
		label.TextColor3 = GOLD
		label.Text = text
		label.Parent = gui
	end
end

-- A soft beam of light falling from the vault (purely visual, one light).
local function lightShaft(parent: Instance, x: number, z: number, height: number)
	makePart("LightShaft", Vector3.new(5, height, 5), at(x, height / 2, z), Color3.fromRGB(255, 236, 196), Enum.Material.Neon, parent, { collide = false, shadow = false, transparency = 0.92 })
	makePart("LightPool", Vector3.new(7, 0.06, 7), at(x, 0.04, z), Color3.fromRGB(236, 214, 170), Enum.Material.SmoothPlastic, parent, { collide = false, shadow = false, transparency = 0.55 })
	local glow = makePart("ShaftGlow", Vector3.one * 0.5, at(x, height - 1, z), Color3.fromRGB(255, 236, 196), Enum.Material.Neon, parent, DECOR)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 236, 200)
	light.Range = 30
	light.Brightness = 1.2
	light.Parent = glow
end

local function segment(parent: Instance, name: string, a: Vector3, b: Vector3, width: number, thickness: number, color: Color3, material: Enum.Material)
	makePart(name, Vector3.new(width, thickness, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), color, material, parent, DECOR)
end

-- A floor guide strip from the spawn toward an area (colour-coded, flat, decor only).
local function guide(parent: Instance, points: { Vector2 }, color: Color3)
	for i = 1, #points - 1 do
		local a = Vector3.new(points[i].X, FLOOR_Y + 0.06, points[i].Y)
		local b = Vector3.new(points[i + 1].X, FLOOR_Y + 0.06, points[i + 1].Y)
		local length = (b - a).Magnitude + 1.6
		makePart("GuideStrip", Vector3.new(1.6, 0.08, length), CFrame.lookAt((a + b) / 2, b), color, Enum.Material.Slate, parent, DECOR)
	end
end

-- A bronze sign (metal plate, dark lettering).
local function bronzeSign(parent: Instance, name: string, width: number, cframe: CFrame, text: string, sub: string?): { TextLabel }
	local lines: { Line } = { { text = text, color = Color3.fromRGB(48, 28, 14), scale = if sub then 0.62 else 0.85 } }
	if sub then
		table.insert(lines, { text = sub, color = Color3.fromRGB(70, 40, 20), scale = 0.3 })
	end
	local labels = sign(parent, name, Vector3.new(width, if sub then 3.2 else 2.4, 0.3), cframe, lines, BRONZE)
	local board = labels[1]:FindFirstAncestorWhichIsA("BasePart")
	if board then
		board.Material = Enum.Material.Metal
		makePart(name .. "Frame", board.Size + Vector3.new(0.5, 0.5, -0.1), board.CFrame * CFrame.new(0, 0, 0.12), DARK_WOOD, Enum.Material.Wood, parent, DECOR)
	end
	return labels
end

local function signpost(parent: Instance, x: number, z: number, face: Vector3, boards: { string })
	makePart("Signpost", Vector3.new(0.6, 9, 0.6), at(x, 4.5, z), DARK_WOOD, Enum.Material.Wood, parent)
	makePart("SignpostBase", Vector3.new(1.6, 0.6, 1.6), at(x, 0.3, z), STONE, Enum.Material.Limestone, parent)
	for i, text in boards do
		sign(parent, "ArrowBoard", Vector3.new(9, 1.4, 0.25), facing(x, 8.6 - (i - 1) * 1.7, z, face) * CFrame.new(0, 0, -0.45), { { text = text, color = GOLD, scale = 0.85 } }, RED)
	end
end

local function crateStack(parent: Instance, x: number, z: number, count: number)
	for i = 1, count do
		local offset = Vector3.new(((i - 1) % 2) * 3.1, math.floor((i - 1) / 2) * 3, (i % 3) * 0.3)
		makePart("Crate", Vector3.one * 3, at(x + offset.X, 1.5 + offset.Y, z + offset.Z) * CFrame.Angles(0, math.rad(i * 9), 0), WOOD, Enum.Material.WoodPlanks, parent)
	end
end

-- Storage shelf with stored goods (rolled leather, spare shield rims, boxes). Front faces -Z.
local function shelf(parent: Instance, cframe: CFrame, width: number)
	for _, side in { -1, 1 } do
		makePart("ShelfPost", Vector3.new(0.4, 9, 0.4), cframe * CFrame.new(side * width / 2, 4.5, 0), DARK_WOOD, Enum.Material.Wood, parent)
	end
	for i, y in { 0.6, 3.4, 6.2, 8.8 } do
		makePart("ShelfBoard", Vector3.new(width, 0.3, 2.2), cframe * CFrame.new(0, y, 0), WOOD, Enum.Material.WoodPlanks, parent)
		if i < 4 then
			makePart("Box", Vector3.new(1.6, 1.4, 1.4), cframe * CFrame.new(-width / 2 + 1.4, y + 0.85, 0), WOOD, Enum.Material.WoodPlanks, parent, DECOR)
			makePart("Roll", Vector3.new(2.2, 0.8, 0.8), cframe * CFrame.new(0.4, y + 0.55, 0.2), Color3.fromRGB(96, 62, 36), Enum.Material.Leather, parent, { collide = false, shadow = false, shape = Enum.PartType.Cylinder })
			makePart("SpareRim", Vector3.new(0.25, 2, 2), cframe * CFrame.new(width / 2 - 1.3, y + 1.15, 0) * CFrame.Angles(0, math.rad(80), 0), BRONZE, Enum.Material.Metal, parent, { collide = false, shadow = false, shape = Enum.PartType.Cylinder })
		end
	end
end

-- Hanging chain links from a wall ring (decor).
local function chain(parent: Instance, cframe: CFrame, links: number)
	local ring = makePart("WallRing", Vector3.new(0.2, 1, 1), cframe * CFrame.Angles(0, math.rad(90), 0), IRON, Enum.Material.Metal, parent, { collide = false, shadow = false, shape = Enum.PartType.Cylinder })
	for link = 1, links do
		makePart("ChainLink", Vector3.new(0.15, 0.5, 0.3), ring.CFrame * CFrame.new(0, -0.3 - link * 0.45, 0) * CFrame.Angles(0, if link % 2 == 0 then math.rad(90) else 0, 0), IRON, Enum.Material.Metal, parent, DECOR)
	end
end

-- Vault ribs across a room at x (from wall z0 to wall z1), arching up to the ceiling.
local function ribs(parent: Instance, x: number, z0: number, z1: number, height: number)
	local y0, y1 = FLOOR_Y + height - 7, FLOOR_Y + height - 0.6
	local inner0, inner1 = z0 + (z1 - z0) * 0.3, z1 - (z1 - z0) * 0.3
	segment(parent, "Rib", Vector3.new(x, y0, z0), Vector3.new(x, y1, inner0), 1.8, 1.4, SANDSTONE, Enum.Material.Sandstone)
	segment(parent, "Rib", Vector3.new(x, y1, inner0), Vector3.new(x, y1, inner1), 1.8, 1.4, SANDSTONE, Enum.Material.Sandstone)
	segment(parent, "Rib", Vector3.new(x, y1, inner1), Vector3.new(x, y0, z1), 1.8, 1.4, SANDSTONE, Enum.Material.Sandstone)
end

-- A wall along x from x0 to x1 at z with openings { {from, to, height} } (gaps in the wall).
local function wallX(parent: Instance, x0: number, x1: number, z: number, height: number, openings: { { number } }, color: Color3)
	local cursor = math.min(x0, x1)
	local finish = math.max(x0, x1)
	table.sort(openings, function(a, b)
		return a[1] < b[1]
	end)
	for _, opening in openings do
		if opening[1] > cursor then
			box("Wall", parent, cursor, opening[1], 0, height, z - 1, z + 1, color, Enum.Material.Cobblestone)
		end
		if opening[3] < height then
			box("WallTop", parent, opening[1], opening[2], opening[3], height, z - 1, z + 1, color, Enum.Material.Cobblestone)
		end
		cursor = opening[2]
	end
	if finish > cursor then
		box("Wall", parent, cursor, finish, 0, height, z - 1, z + 1, color, Enum.Material.Cobblestone)
	end
end

-- The same along z at x.
local function wallZ(parent: Instance, z0: number, z1: number, x: number, height: number, openings: { { number } }, color: Color3)
	local cursor = math.min(z0, z1)
	local finish = math.max(z0, z1)
	table.sort(openings, function(a, b)
		return a[1] < b[1]
	end)
	for _, opening in openings do
		if opening[1] > cursor then
			box("Wall", parent, x - 1, x + 1, 0, height, cursor, opening[1], color, Enum.Material.Cobblestone)
		end
		if opening[3] < height then
			box("WallTop", parent, x - 1, x + 1, opening[3], height, opening[1], opening[2], color, Enum.Material.Cobblestone)
		end
		cursor = opening[2]
	end
	if finish > cursor then
		box("Wall", parent, x - 1, x + 1, 0, height, cursor, finish, color, Enum.Material.Cobblestone)
	end
end

-- An arch frame (two pillars + lintel) around an opening centred at (x, z), facing `face`.
local function archFrame(parent: Instance, x: number, z: number, face: Vector3, halfWidth: number, height: number)
	local right = face:Cross(Vector3.yAxis)
	for _, side in { -1, 1 } do
		local p = Vector3.new(x, 0, z) + right * side * (halfWidth + 0.9) + face * 0.6
		makePart("ArchPillar", Vector3.new(1.8, height + 1, 1.8), at(p.X, (height + 1) / 2, p.Z), SANDSTONE, Enum.Material.Limestone, parent)
	end
	local lintelCenter = Vector3.new(x, 0, z) + face * 0.6
	makePart("ArchLintel", Vector3.new(halfWidth * 2 + 4, 1.6, 2), facing(lintelCenter.X, height + 0.8, lintelCenter.Z, face), SANDSTONE, Enum.Material.Limestone, parent)
end

------------------------------------------------------------------------------------------
-- Central hall: spawn, Otti statue, signs, guide strips, columns, light shafts
------------------------------------------------------------------------------------------

local function buildHall(folder: Folder): (CFrame, SpawnLocation, SpawnLocation)
	local hall = Instance.new("Model")
	hall.Name = "CentralHall"
	local hx, hz, h = HALL_HX, HALL_HZ, HALL_H
	box("Floor", hall, -hx - 2, hx + 2, -2, 0, -hz - 2, hz + 2, FLOOR, Enum.Material.Cobblestone)
	box("SandWear", hall, -hx + 6, hx - 6, 0, 0.04, -hz + 6, hz - 6, SAND, Enum.Material.Sand, DECOR)
	box("Ceiling", hall, -hx - 2, hx + 2, h, h + 2, -hz - 2, hz + 2, STONE_DARK, Enum.Material.Slate)
	-- North wall: the arena gate (and the tribune doors at the top of the corner stairs)
	wallX(hall, -hx - 2, hx + 2, -hz - 1, h, { { -GATE_HX, GATE_HX, GATE_H } }, STONE)
	-- South wall: the Gate to Rome is a closed monumental door in front of the solid wall; the
	-- armory side passage opens at the back-left
	wallX(hall, -hx - 2, hx + 2, hz + 1, h, { { PASSAGE_X0, PASSAGE_X1, DOOR_HEIGHT } }, STONE)
	-- West (multiplayer) and east (singleplayer) openings
	wallZ(hall, -hz, hz, -hx - 1, h, { { -WING_OPEN_HZ, WING_OPEN_HZ, WING_OPEN_H } }, STONE)
	wallZ(hall, -hz, hz, hx + 1, h, { { -WING_OPEN_HZ, WING_OPEN_HZ, WING_OPEN_H } }, STONE)
	zone(-hx, hx, -hz, hz, h)

	-- Columns and vault ribs
	for _, x in { -24, 24 } do
		for _, z in { -20, 20 } do
			box("Column", hall, x - 2, x + 2, 0, h, z - 2, z + 2, SANDSTONE, Enum.Material.Sandstone)
			box("ColumnBase", hall, x - 2.5, x + 2.5, 0, 1, z - 2.5, z + 2.5, STONE, Enum.Material.Limestone)
		end
		ribs(hall, x, -hz, hz, h)
	end
	lightShaft(hall, -14, 8, h)
	lightShaft(hall, 14, 8, h)

	-- OTTI statue on a stepped pedestal in the middle, four braziers around it
	local monument = Instance.new("Model")
	monument.Name = "OttiMonument"
	box("PedestalStep", monument, -8, 8, 0, 1, -8, 8, STONE, Enum.Material.Limestone)
	box("Pedestal", monument, -6, 6, 1, 5, -6, 6, SANDSTONE, Enum.Material.Sandstone)
	box("PedestalCap", monument, -6.6, 6.6, 5, 5.8, -6.6, 6.6, STONE, Enum.Material.Limestone)
	box("PedestalTrim", monument, -6.1, 6.1, 3.6, 4, -6.1, 6.1, BRONZE, Enum.Material.Metal, DECOR)
	sign(monument, "StatueInscription", Vector3.new(10, 2.6, 0.3), facing(0, 3, 6.2, SOUTH), {
		{ text = "OTTI", color = GOLD, scale = 0.6 },
		{ text = "CHAMPION OF THE COLOSSEUM", color = WHITE, scale = 0.3 },
	}, DARK_WOOD)
	for _, corner in { Vector2.new(-9, -9), Vector2.new(9, -9), Vector2.new(-9, 9), Vector2.new(9, 9) } do
		brazier(monument, corner.X, corner.Y, 4)
	end
	LobbyStatue.build(monument, facing(0, 5.8, 0, SOUTH), 1.7) -- Otti faces the spawn (about 16 studs tall)
	-- Keep the entire monument beside the approach, including its pedestal and braziers.
	-- The spawn-to-arena centre line must stay walkable and visible.
	monument:PivotTo(monument:GetPivot() + Vector3.new(-18, 0, 0))
	monument.Parent = hall

	-- Direct arrivals face the unobstructed central route; later spawns use the side of the hall.
	local function makeSpawn(name: string, x: number, z: number): SpawnLocation
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = name
		spawn.Anchored = true
		spawn.Size = Vector3.new(6, 1, 6)
		spawn.CFrame = facing(x, 0.5, z, NORTH)
		spawn.Color = SANDSTONE
		spawn.Material = Enum.Material.Limestone
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.Parent = folder
		return spawn
	end
	local arrivalSpawn = makeSpawn("LobbyArrivalSpawn", 0, 28)
	local respawnSpawn = makeSpawn("LobbyRespawn", 18, 12)
	local spawnCFrame = respawnSpawn.CFrame
	-- Direction signs right at the spawn and big signs over every way out
	signpost(hall, 7, 22, NORTH, { "▲ ZOMBIE SOLO · walk in", "◄ TEAM BATTLE", "CO-OP & TRAINING ►", "▼ ROMA · closed" })
	sign(hall, "ArenaSign", Vector3.new(20, 4.4, 0.5), facing(0, GATE_H + 2.6, -hz + 0.3, SOUTH), {
		{ text = "ZOMBIE SOLO", color = GOLD, scale = 0.55 },
		{ text = "walk straight ahead to enter the arena", color = WHITE, scale = 0.25 },
	}, RED)
	sign(hall, "MultiplayerSign", Vector3.new(20, 4.4, 0.5), facing(-hx + 0.3, WING_OPEN_H + 2.6, 0, EAST), {
		{ text = "TEAM BATTLE", color = GOLD, scale = 0.55 },
		{ text = "Schili versus Krokero · choose your side", color = WHITE, scale = 0.25 },
	}, RED)
	sign(hall, "SingleplayerSign", Vector3.new(20, 4.4, 0.5), facing(hx - 0.3, WING_OPEN_H + 2.6, 0, WEST), {
		{ text = "CO-OP & TRAINING", color = GOLD, scale = 0.55 },
		{ text = "fight together · practise beyond", color = WHITE, scale = 0.25 },
	}, RED)
	archFrame(hall, 0, -hz, SOUTH, GATE_HX, GATE_H)
	archFrame(hall, -hx, 0, EAST, WING_OPEN_HZ, WING_OPEN_H)
	archFrame(hall, hx, 0, WEST, WING_OPEN_HZ, WING_OPEN_H)
	-- raised portcullis teeth over the arena gate
	for x = -GATE_HX + 0.5, GATE_HX - 0.5, 1 do
		box("GateTooth", hall, x - 0.18, x + 0.18, GATE_H - 1.6, GATE_H, -hz, -hz + 0.4, IRON, Enum.Material.Metal, DECOR)
	end

	-- Colour-coded guide strips on the floor: blue to MULTIPLAYER, gold to SINGLEPLAYER
	guide(hall, { Vector2.new(-6, 24), Vector2.new(-30, 24), Vector2.new(-30, 0), Vector2.new(-hx, 0) }, Color3.fromRGB(70, 110, 190))
	guide(hall, { Vector2.new(6, 24), Vector2.new(30, 24), Vector2.new(30, 0), Vector2.new(hx, 0) }, GOLD)
	guide(hall, { Vector2.new(0, 24), Vector2.new(0, 0) }, RED)
	guide(hall, { Vector2.new(0, 0), Vector2.new(0, -hz) }, RED)

	-- Torches and banners on the walls
	for _, x in { -32, -16, 16, 32 } do
		torch(hall, facing(x, 12, hz, NORTH))
	end
	for _, z in { -26, 26 } do
		torch(hall, facing(-hx, 12, z, EAST))
		torch(hall, facing(hx, 12, z, WEST))
	end
	banner(hall, facing(-hx, 14, -20, EAST), RED, "SPQR")
	banner(hall, facing(hx, 14, -20, WEST), RED, "SPQR")
	banner(hall, facing(-hx, 14, 20, EAST))
	banner(hall, facing(hx, 14, 20, WEST))
	-- benches near the spawn
	for _, x in { -14, 14 } do
		box("Bench", hall, x - 3.5, x + 3.5, 1, 1.5, 30, 31.6, WOOD, Enum.Material.Wood)
		for _, dx in { -2.8, 2.8 } do
			box("BenchLeg", hall, x + dx - 0.25, x + dx + 0.25, 0, 1, 30.1, 31.5, DARK_WOOD, Enum.Material.Wood)
		end
	end
	hall.Parent = folder
	return spawnCFrame, arrivalSpawn, respawnSpawn
end

------------------------------------------------------------------------------------------
-- BACK: the closed Gate to Rome (decor + a prompt host)
------------------------------------------------------------------------------------------

local function buildRomeGate(folder: Folder): BasePart
	local gate = Instance.new("Model")
	gate.Name = "GateToRome"
	local z = HALL_HZ - 0.4
	local hw, height = 10, 17
	for _, side in { -1, 1 } do
		box("GatePillar", gate, side * (hw + 0.5) - 2, side * (hw + 0.5) + 2, 0, height + 2, z - 3.2, z, SANDSTONE, Enum.Material.Limestone)
		box("PillarBase", gate, side * (hw + 0.5) - 2.6, side * (hw + 0.5) + 2.6, 0, 1.2, z - 3.8, z, STONE, Enum.Material.Limestone)
	end
	box("GateLintel", gate, -hw - 3, hw + 3, height, height + 2.6, z - 3.4, z, SANDSTONE, Enum.Material.Limestone)
	-- two massive door leaves, iron bands and bronze studs
	local leaf = box("GateLeaf", gate, -hw, 0, 0, height, z - 1.4, z, DARK_WOOD, Enum.Material.WoodPlanks)
	box("GateLeaf", gate, 0, hw, 0, height, z - 1.4, z, DARK_WOOD, Enum.Material.WoodPlanks)
	for _, y in { 3, 8.5, 14 } do
		box("GateBand", gate, -hw, hw, y - 0.4, y + 0.4, z - 1.6, z - 1.3, IRON, Enum.Material.Metal, DECOR)
	end
	for x = -hw + 1.5, hw - 1.5, 3 do
		for _, y in { 3, 8.5, 14 } do
			makePart("Stud", Vector3.one * 0.6, at(x, y, z - 1.7), BRONZE, Enum.Material.Metal, gate, { collide = false, shadow = false, shape = Enum.PartType.Ball })
		end
	end
	box("GateBar", gate, -hw - 1, hw + 1, 8, 9, z - 2.4, z - 1.4, IRON, Enum.Material.Metal) -- barred shut
	sign(gate, "RomaSign", Vector3.new(18, 4.4, 0.5), facing(0, height + 5.4, z - 0.6, NORTH), {
		{ text = "ROMA", color = GOLD, scale = 0.6 },
		{ text = "the road to Rome · opening soon", color = WHITE, scale = 0.25 },
	}, RED)
	banner(gate, facing(-hw - 5, 14, z, NORTH), RED, "SPQR")
	banner(gate, facing(hw + 5, 14, z, NORTH), RED, "SPQR")
	chain(gate, at(-hw + 2, 13, z - 1.5), 5)
	chain(gate, at(hw - 2, 13, z - 1.5), 5)
	gate.Parent = folder
	return leaf
end

------------------------------------------------------------------------------------------
-- FRONT: the main corridor (zombie / gladiator cages = the ZOMBIE ARCHIVE), the rising ramp, the
-- portcullis and the sealed view into the sunlit arena
------------------------------------------------------------------------------------------

type Corridor = { slots: { CFrame }, plaques: { CFrame }, portcullis: BasePart }

local function cage(parent: Instance, side: number, z: number, zombie: boolean)
	-- side = 1: east wall (faces west), -1: west wall (faces east)
	local bars = side * CORR_HX
	local back = side * (CORR_HX + CAGE_DEPTH)
	for _, dz in { -3.6, 3.6 } do
		box("CageSide", parent, bars, back, 0, 13, z + dz - 0.4, z + dz + 0.4, STONE, Enum.Material.Cobblestone)
	end
	box("CageTop", parent, bars, back, 13, 14, z - 4, z + 4, STONE, Enum.Material.Cobblestone)
	box("CageFloor", parent, bars, back, 0, 0.4, z - 3.2, z + 3.2, HAY, Enum.Material.Grass, DECOR)
	for bz = -3, 3 do
		box("CageBar", parent, bars - 0.15, bars + 0.15, 0, 13, z + bz - 0.15, z + bz + 0.15, IRON, Enum.Material.Metal)
	end
	for _, y in { 1, 7, 12.6 } do
		box("CageBand", parent, bars - 0.2, bars + 0.2, y - 0.2, y + 0.2, z - 3.6, z + 3.6, IRON, Enum.Material.Metal, DECOR)
	end
	if not zombie then
		-- an empty gladiator cell: bench, hay and a chain on the back wall
		box("CellBench", parent, back - side * 1.5, back - side * 3, 1, 1.5, z - 2.2, z + 2.2, WOOD, Enum.Material.Wood)
		box("Hay", parent, bars + side * 2, bars + side * 4.5, 0, 0.8, z - 2, z + 1, HAY, Enum.Material.Grass, DECOR)
		chain(parent, at(back - side * 0.4, 7, z), 4)
	else
		local lamp = makePart("CageLamp", Vector3.one * 0.6, at(side * (CORR_HX + CAGE_DEPTH / 2), 12.4, z), FLAME, Enum.Material.Neon, parent, { collide = false, shadow = false, shape = Enum.PartType.Ball })
		local light = Instance.new("PointLight")
		light.Color = FLAME
		light.Range = 12
		light.Brightness = 1
		light.Parent = lamp
	end
end

local function buildCorridor(folder: Folder): Corridor
	local corridor = Instance.new("Model")
	corridor.Name = "ArenaCorridor"
	local z0 = -HALL_HZ - 2
	local outer = CORR_HX + CAGE_DEPTH + 1
	box("CorridorFloor", corridor, -outer, outer, -2, 0, z0, LANDING_END, FLOOR, Enum.Material.Cobblestone)
	box("CorridorSand", corridor, -CORR_HX + 1.5, CORR_HX - 1.5, 0, 0.04, z0, FLAT_END, SAND, Enum.Material.Sand, DECOR)
	box("CorridorCeiling", corridor, -outer, outer, CORR_H, CORR_H + 2, z0, LANDING_END - 2, STONE_DARK, Enum.Material.Slate)
	for _, side in { -1, 1 } do
		box("CorridorOuterWall", corridor, side * outer, side * (outer + 2), 0, CORR_H, z0, LANDING_END - 2, STONE_DARK, Enum.Material.Cobblestone)
	end

	-- Cages along both walls: three zombie cages (the archive) and one gladiator cell per side
	local slots, plaques = {}, {}
	local cageZs = { -46, -58, -70 }
	for _, side in { 1, -1 } do
		local wallStart = z0
		for _, z in { -46, -58, -70, -82 } do
			-- solid inner wall between the cages
			box("InnerWall", corridor, side * CORR_HX - 1, side * CORR_HX + 1, 0, CORR_H, z + 4, wallStart, STONE, Enum.Material.Cobblestone)
			box("CageLintel", corridor, side * CORR_HX - 1, side * CORR_HX + 1, 14, CORR_H, z - 4, z + 4, STONE, Enum.Material.Cobblestone)
			cage(corridor, side, z, table.find(cageZs, z) ~= nil)
			if table.find(cageZs, z) then
				local face = if side > 0 then WEST else EAST
				table.insert(slots, facing(side * (CORR_HX + CAGE_DEPTH / 2), 0.4, z, face))
				table.insert(plaques, facing(side * (CORR_HX - 0.2), 15.6, z, face))
			end
			wallStart = z - 4
		end
		box("InnerWall", corridor, side * CORR_HX - 1, side * CORR_HX + 1, 0, CORR_H, LANDING_END - 2, wallStart, STONE, Enum.Material.Cobblestone)
		-- the space behind the inner wall beyond the cells is solid rock
		box("Rock", corridor, side * (CORR_HX + 1), side * outer, 0, CORR_H, LANDING_END - 2, -86, STONE_DARK, Enum.Material.Rock)
	end
	sign(corridor, "ArchiveSign", Vector3.new(14, 3, 0.4), facing(0, 18.5, -40.5, SOUTH), {
		{ text = "ZOMBIE ARCHIVE", color = GOLD, scale = 0.6 },
		{ text = "know your foes before the arena", color = WHITE, scale = 0.3 },
	}, RED)
	for _, z in { -52, -64, -76 } do
		torch(corridor, facing(CORR_HX - 0.9, 11, z, WEST), 16)
		torch(corridor, facing(-CORR_HX + 0.9, 11, z, EAST), 16)
	end

	-- The gentle ramp and the landing in front of the portcullis
	local steps = 12
	local stepDepth = (FLAT_END - RAMP_END) / steps
	for i = 1, steps do
		local rise = RAMP_RISE * i / steps
		box("RampStep", corridor, -CORR_HX + 1, CORR_HX - 1, 0, rise, FLAT_END - (i - 1) * stepDepth, FLAT_END - i * stepDepth, SANDSTONE, Enum.Material.Limestone)
	end
	box("Landing", corridor, -CORR_HX + 1, CORR_HX - 1, 0, RAMP_RISE, RAMP_END, LANDING_END, SANDSTONE, Enum.Material.Limestone)
	-- Portcullis (closed: regular matches run on their own arena servers)
	local gate = Instance.new("Model")
	gate.Name = "ArenaPortcullis"
	local zp = LANDING_END - 0.4
	for x = -CORR_HX + 1.5, CORR_HX - 1.5, 1.2 do
		box("GateBar", gate, x - 0.2, x + 0.2, RAMP_RISE, CORR_H, zp - 0.2, zp + 0.2, IRON, Enum.Material.Metal)
	end
	for _, y in { RAMP_RISE + 3, RAMP_RISE + 8, RAMP_RISE + 13 } do
		box("GateBand", gate, -CORR_HX + 1, CORR_HX - 1, y - 0.2, y + 0.2, zp - 0.3, zp + 0.3, IRON, Enum.Material.Metal)
	end
	local portcullis = box("PortcullisPrompt", gate, -6, 6, RAMP_RISE, RAMP_RISE + 7, zp + 0.4, zp + 0.9, IRON, Enum.Material.Metal, { collide = false, transparency = 1 })
	torch(gate, facing(-CORR_HX + 0.9, RAMP_RISE + 8, LANDING_END + 2, EAST), 18)
	torch(gate, facing(CORR_HX - 0.9, RAMP_RISE + 8, LANDING_END + 2, WEST), 18)
	gate.Parent = corridor
	zone(-CORR_HX - CAGE_DEPTH, CORR_HX + CAGE_DEPTH, z0, LANDING_END, CORR_H)

	-- The arena beyond: bright sand, the arena wall and stands under the open sky (not walkable)
	local view = Instance.new("Model")
	view.Name = "ArenaView"
	local y = RAMP_RISE
	box("ArenaSand", view, -60, 60, y - 2, y, LANDING_END - 1, LANDING_END - 70, SAND, Enum.Material.Sand)
	for i = -4, 4 do
		local angle = math.rad(i * 14)
		local position = Vector3.new(math.sin(angle) * 64, 0, LANDING_END - 6 - math.cos(angle) * 58)
		local wall = makePart("ArenaWall", Vector3.new(16, 12, 2), CFrame.lookAt(Vector3.new(position.X, FLOOR_Y + y + 6, position.Z), Vector3.new(0, FLOOR_Y + y + 6, LANDING_END - 6)), Color3.fromRGB(196, 170, 128), Enum.Material.Sandstone, view)
		for tier = 1, 3 do
			local stand = wall.CFrame * CFrame.new(0, 4 + tier * 3, 2 + tier * 3.2)
			makePart("Stand", Vector3.new(16, 3, 3.2), stand, Color3.fromRGB(150, 128, 98), Enum.Material.Limestone, view, DECOR)
			local crowd = makePart("Crowd", Vector3.new(15, 1.4, 1.6), stand * CFrame.new(0, 2.1, -0.4), Color3.fromHSV(((i + tier) % 6) / 6, 0.35, 0.75), Enum.Material.Fabric, view, DECOR)
			crowd.CastShadow = false
		end
	end
	local sun = makePart("ArenaSun", Vector3.one, at(0, 40, LANDING_END - 30), Color3.fromRGB(255, 240, 210), Enum.Material.Neon, view, { collide = false, shadow = false, transparency = 1 })
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 240, 210)
	light.Range = 60
	light.Brightness = 2.5
	light.Parent = sun
	view.Parent = corridor
	corridor.Parent = folder
	return { slots = slots, plaques = plaques, portcullis = portcullis }
end

------------------------------------------------------------------------------------------
-- SIDES: stone stairs in both front corners up to the tribune doors (WATCH LIVE)
------------------------------------------------------------------------------------------

type Tribunes = { doors: { BasePart }, liveBoard: TextLabel, liveCFrame: CFrame }

local function buildTribunes(folder: Folder): Tribunes
	local stairs = Instance.new("Model")
	stairs.Name = "TribuneStairs"
	local doors: { BasePart } = {}
	local landingY = 12
	local z0, z1 = -HALL_HZ, -HALL_HZ + 6 -- along the north wall
	for _, side in { -1, 1 } do
		-- 12 steps from |x| = 14 outward to the corner landing
		for i = 1, 12 do
			local x0 = side * (14 + (i - 1) * 1.5)
			local x1 = side * (14 + i * 1.5)
			box("TribuneStair", stairs, x0, x1, 0, i * 1, z0, z1, SANDSTONE, Enum.Material.Limestone)
		end
		local lx0, lx1 = side * 32, side * HALL_HX
		box("TribuneLanding", stairs, lx0, lx1, 0, landingY, z0, z0 + 10, SANDSTONE, Enum.Material.Limestone)
		box("Parapet", stairs, side * 14, lx0, 0.5, 0, z1, z1 + 0.6, STONE, Enum.Material.Limestone) -- low rim
		box("LandingRail", stairs, lx0, lx1, landingY, landingY + 1.2, z0 + 10, z0 + 10.6, STONE, Enum.Material.Limestone)
		-- the tribune door in the north wall above the landing
		local dx = side * 36
		local door = box("TribuneDoor", stairs, dx - 3, dx + 3, landingY, landingY + 9, z0 - 0.2, z0 + 0.4, DARK_WOOD, Enum.Material.WoodPlanks)
		for _, y in { 2, 5, 8 } do
			box("DoorBand", stairs, dx - 3, dx + 3, landingY + y - 0.2, landingY + y + 0.2, z0 + 0.4, z0 + 0.5, IRON, Enum.Material.Metal, DECOR)
		end
		sign(stairs, "TribuneSign", Vector3.new(8, 2.6, 0.4), facing(dx, landingY + 11, z0 + 0.6, SOUTH), {
			{ text = "TRIBUNES", color = GOLD, scale = 0.6 },
			{ text = "WATCH LIVE · hold F", color = WHITE, scale = 0.3 },
		}, RED)
		torch(stairs, facing(side * 29, landingY + 6, z0, SOUTH))
		table.insert(doors, door)
	end
	-- LIVE IN THE COLOSSEUM board on the floor between the west stairs and the statue
	local live = sign(stairs, "LiveBoard", Vector3.new(9, 5, 0.4), facing(-18, 3.5, -22, SOUTH), {
		{ text = "LIVE IN THE COLOSSEUM", color = GOLD, scale = 0.3 },
		{ text = "No live battles", color = WHITE, scale = 0.35 },
		{ text = "stairs to the tribunes ↖ ↗", color = Color3.fromRGB(255, 210, 120), scale = 0.2 },
	}, DARK_WOOD)
	box("LiveBoardPost", stairs, -18.3, -17.7, 0, 1.1, -22.3, -21.7, DARK_WOOD, Enum.Material.Wood)
	stairs.Parent = folder
	local arrival = Vector3.new(-18, FLOOR_Y + 3.5, -16)
	return { doors = doors, liveBoard = live[2], liveCFrame = CFrame.lookAt(arrival, arrival + SOUTH) }
end

------------------------------------------------------------------------------------------
-- Pads (LobbyPadDefinitions): carpet, glowing border, board, start pedestals
------------------------------------------------------------------------------------------

-- `center` is on the floor, -Z points to the board side. size = walk-on area (X x Z).
local function buildPad(parent: Instance, def: PadDefinition, center: CFrame, size: Vector2, boardCFrame: CFrame, buttonsSide: number): PadLayout
	local model = Instance.new("Model")
	model.Name = "Pad_" .. def.Id
	local enabled = def.Enabled
	local carpet = makePart("PadCarpet", Vector3.new(size.X, 0.16, size.Y), center * CFrame.new(0, 0.08, 0), if enabled then SANDSTONE else STONE_DARK, Enum.Material.Limestone, model, DECOR)
	carpet.CastShadow = false
	local ring = makePart("PadRing", Vector3.new(size.X + 1.2, 0.12, size.Y + 1.2), center * CFrame.new(0, 0.06, 0), if enabled then BRONZE else SOON, Enum.Material.Metal, model, DECOR)
	ring.Transparency = if enabled then 0.35 else 0.75
	if def.Emblem and LobbyMosaics.has(def.Emblem) then
		LobbyMosaics.build(model, center * CFrame.new(0, 0.16, 0), def.Emblem, 0.9, Color3.fromRGB(196, 176, 140))
	end
	local labels = sign(model, "PadBoard", Vector3.new(16, 7, 0.5), boardCFrame, {
		{ text = def.Title, color = if enabled then GOLD else SOON, scale = 0.3 },
		{ text = def.Subtitle, color = WHITE, scale = 0.14 },
		{ text = if enabled then "" else "COMING SOON", color = Color3.fromRGB(230, 230, 230), scale = 0.46 },
	}, if enabled then RED else DARK_WOOD)
	-- Start pedestals along the pad's front edge (towards the aisle / the hall)
	local buttons: { PadButton } = {}
	local soloActions: { LobbyPadDefinitions.PadAction } = { { Id = "StartNow", Label = "START NOW" } }
	local actions: { LobbyPadDefinitions.PadAction } = def.Actions or (if def.Kind == "Solo" then soloActions else {})
	if enabled then
		for i, action in actions do
			local offset = (i - (#actions + 1) / 2) * 6
			local spot = center * CFrame.new(offset, 0, buttonsSide * (size.Y / 2 + 2))
			local pedestal: BasePart = makePart("StartPedestal", Vector3.new(2.2, 3.4, 2.2), spot * CFrame.new(0, 1.7, 0), SANDSTONE, Enum.Material.Sandstone, model)
			makePart("StartButton", Vector3.new(1.8, 0.4, 1.8), spot * CFrame.new(0, 3.6, 0), if action.Id == "StartCoop" or action.Id == "StartNow" then Color3.fromRGB(90, 200, 110) else Color3.fromRGB(120, 170, 255), Enum.Material.Metal, model, DECOR)
			local billboard = Instance.new("BillboardGui")
			billboard.Size = UDim2.fromOffset(130, 26)
			billboard.StudsOffset = Vector3.new(0, 3.2, 0)
			billboard.MaxDistance = 40
			billboard.Parent = pedestal
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundColor3 = Color3.fromRGB(30, 24, 18)
			label.BackgroundTransparency = 0.2
			label.Font = Enum.Font.GothamBold
			label.TextSize = 14
			label.TextColor3 = GOLD
			label.Text = action.Label
			label.Parent = billboard
			table.insert(buttons, { action = action.Id, part = pedestal })
		end
	end
	model.Parent = parent
	return { def = def, cframe = center, size = Vector3.new(size.X, 0, size.Y), status = labels[3], ring = ring, buttons = buttons }
end

------------------------------------------------------------------------------------------
-- LEFT: MULTIPLAYER wing with four large group rooms
------------------------------------------------------------------------------------------

local function buildMultiplayer(folder: Folder, pads: { PadLayout })
	local wing = Instance.new("Model")
	wing.Name = "TeamHall"
	local x0, x1, hz, h = MULTI_X0, MULTI_X1, MULTI_HZ, MULTI_H
	box("Floor", wing, x0, x1 - 2, -2, 0, -hz - 2, hz + 2, FLOOR, Enum.Material.Cobblestone)
	box("Aisle", wing, x0, x1, 0, 0.04, -5, 5, SAND, Enum.Material.Sand, DECOR)
	box("Ceiling", wing, x0, x1 - 2, h, h + 2, -hz - 2, hz + 2, STONE_DARK, Enum.Material.Slate)
	wallX(wing, x1 - 2, x0, -hz - 1, h, {}, STONE)
	wallX(wing, x1 - 2, x0, hz + 1, h, {}, STONE)
	wallZ(wing, -hz - 2, hz + 2, x1 - 1, h, {}, STONE)
	zone(x0, x1, -hz, hz, h)
	local mid = (x0 + x1) / 2
	ribs(wing, mid, -hz, hz, h)
	lightShaft(wing, mid, 0, h)
	-- One shared room, two opposite mosaics, an open aisle between them.
	for _, def in LobbyPadDefinitions.Pads do
		if def.Wing ~= "Multi" then continue end
		local side = if def.Team == "Blue" then -1 else 1
		local face = if side < 0 then NORTH else SOUTH
		local center = facing(mid, 0, side * 18, face)
		local board = facing(mid, 11, side * (hz - 0.2), -face)
		table.insert(pads, buildPad(wing, def, center, Vector2.new(24, 16), board, 1))
		for _, dx in { -16, 16 } do
			banner(wing, facing(mid + dx, 13, side * hz, -face), def.Color, (def.Emblem or "OTTI"):upper())
			torch(wing, facing(mid + dx, 9, side * hz, -face), 18)
		end
	end
	wing.Parent = folder
end

------------------------------------------------------------------------------------------
-- RIGHT: one Otti CO-OP mosaic near the entrance, TRAINING beyond
------------------------------------------------------------------------------------------

type Training = { slots: { CFrame }, cframe: CFrame, size: Vector3 }

local function buildSingleplayer(folder: Folder, pads: { PadLayout }): Training
	local wing = Instance.new("Model")
	wing.Name = "SingleplayerWing"
	local x0, x1, hz, h = SINGLE_X0, SINGLE_X1, SINGLE_HZ, SINGLE_H
	box("Floor", wing, x0, x1 + 2, -2, 0, -hz - 2, hz + 2, FLOOR, Enum.Material.Cobblestone)
	box("Ceiling", wing, x0, x1 + 2, h, h + 2, -hz - 2, hz + 2, STONE_DARK, Enum.Material.Slate)
	wallX(wing, x0, x1 + 2, -hz - 1, h, {}, STONE)
	wallX(wing, x0, x1 + 2, hz + 1, h, {}, STONE)
	wallZ(wing, -hz - 2, hz + 2, x1 + 1, h, {}, STONE)
	zone(x0, x1, -hz, hz, h)
	for _, x in { 72, 98 } do
		ribs(wing, x, -hz, hz, h)
	end
	lightShaft(wing, 72, 0, h)
	for _, def in LobbyPadDefinitions.Pads do
		if def.Wing ~= "Single" then continue end
		table.insert(pads, buildPad(wing, def, facing(62, 0, 0, EAST), Vector2.new(24, 16), facing(80, 11, 0, WEST), 1))
	end
	-- TRAINING yard at the far end (straw dummies, the training board)
	local yard = Instance.new("Model")
	yard.Name = "TrainingYard"
	local center = Vector3.new(110, FLOOR_Y, 0)
	box("YardFloor", yard, 98, 122, 0, 0.2, -16, 16, SAND, Enum.Material.Sand)
	for _, z in { -16, 16 } do
		box("YardRail", yard, 98, 122, 0.4, 1.6, z - 0.2, z + 0.2, DARK_WOOD, Enum.Material.Wood, DECOR)
	end
	sign(yard, "TrainingSign", Vector3.new(12, 3, 0.4), facing(x1 - 0.2, 12, 0, WEST), {
		{ text = "TRAINING", color = GOLD, scale = 0.6 },
		{ text = "practise attacks, blocks and specials", color = WHITE, scale = 0.3 },
	}, RED)
	-- TRAINING board: the client writes the guide and the weapon's specials onto it
	local board = makePart("ComboTrainingBoard", Vector3.new(9, 7, 0.4), facing(x1 - 0.2, 5, -10, WEST), Color3.fromRGB(60, 40, 26), Enum.Material.Wood, yard)
	board.CanCollide = false
	torch(yard, facing(x1, 10, 10, WEST))
	torch(yard, facing(x1, 10, -16, WEST))
	yard.Parent = wing
	wing.Parent = folder
	local slots = { facing(center.X + 4, 0.2, -5, WEST), facing(center.X + 4, 0.2, 5, WEST) }
	return { slots = slots, cframe = CFrame.new(center + Vector3.new(0, 6, 0)), size = Vector3.new(26, 16, 34) }
end

------------------------------------------------------------------------------------------
-- BACK-LEFT: side passage with a forge, leading to the GLADIATOR ARMORY
------------------------------------------------------------------------------------------

local function buildPassage(folder: Folder)
	local passage = Instance.new("Model")
	passage.Name = "ArmoryPassage"
	local px0, px1 = PASSAGE_X0, PASSAGE_X1
	local z0 = HALL_HZ + 2
	box("PassageFloor", passage, px0 - 2, px1 + 2, -2, 0, z0, PASSAGE_END + 2, FLOOR, Enum.Material.Cobblestone)
	box("PassageCeiling", passage, px0 - 2, px1 + 2, DOOR_HEIGHT, DOOR_HEIGHT + 2, z0, PASSAGE_END + 2, STONE_DARK, Enum.Material.Slate)
	box("PassageEastWall", passage, px1, px1 + 2, 0, DOOR_HEIGHT, z0, PASSAGE_END + 2, SANDSTONE, Enum.Material.Sandstone)
	box("PassageWestWall", passage, px0 - 2, px0, 0, DOOR_HEIGHT, z0, ARMORY_OFFSET.Z - ARMORY_HALF_Z - 2, SANDSTONE, Enum.Material.Sandstone)
	box("PassageEnd", passage, px0 - 2, px1 + 2, 0, DOOR_HEIGHT, PASSAGE_END, PASSAGE_END + 2, SANDSTONE, Enum.Material.Sandstone)
	zone(px0, px1, z0 - 2, PASSAGE_END, DOOR_HEIGHT)
	-- Forge: anvil, glowing coals and tools (decor)
	local forge = Instance.new("Model")
	forge.Name = "Forge"
	box("ForgeHearth", forge, px1 - 4, px1, 0, 2.6, 52, 58, STONE, Enum.Material.Brick)
	local coals = box("ForgeCoals", forge, px1 - 3.6, px1 - 0.4, 2.6, 2.9, 52.4, 57.6, FLAME, Enum.Material.Neon, DECOR)
	local light = Instance.new("PointLight")
	light.Color = FLAME
	light.Range = 20
	light.Brightness = 1.6
	light.Parent = coals
	local fire = Instance.new("Fire")
	fire.Size = 3
	fire.Heat = 6
	fire.Color = FLAME
	fire.Parent = coals
	box("ForgeHood", forge, px1 - 4.4, px1, 8, DOOR_HEIGHT, 51.6, 58.4, STONE_DARK, Enum.Material.Brick)
	box("AnvilBase", forge, px1 - 8.6, px1 - 7, 0, 1.8, 54.2, 55.8, IRON, Enum.Material.Metal)
	box("AnvilTop", forge, px1 - 9.4, px1 - 6.2, 1.8, 2.6, 54.4, 55.6, IRON, Enum.Material.Metal)
	box("Bellows", forge, px1 - 3, px1 - 0.4, 0, 1.4, 59, 62, Color3.fromRGB(96, 62, 36), Enum.Material.Leather)
	forge.Parent = passage
	-- weapon racks with spare blades (decor), torches and signs
	for _, z in { 66, 76 } do
		box("RackBoard", passage, px1 - 0.6, px1, 2, 8, z - 3, z + 3, DARK_WOOD, Enum.Material.WoodPlanks, DECOR)
		for dz = -2, 2, 2 do
			box("RackBlade", passage, px1 - 1, px1 - 0.7, 2.5, 7.5, z + dz - 0.12, z + dz + 0.12, Color3.fromRGB(176, 176, 170), Enum.Material.Metal, DECOR)
		end
	end
	torch(passage, facing(px0, 9, 48, EAST))
	torch(passage, facing(px1, 9, 70, WEST))
	torch(passage, facing(px0, 9, 64, EAST))
	bronzeSign(passage, "PassageSign", 14, facing((px0 + px1) / 2, DOOR_HEIGHT + 3.2, HALL_HZ - 0.4, NORTH), "GLADIATOR ARMORY", "weapons · shields · armor")
	sign(passage, "UpgradesSign", Vector3.new(10, 2.6, 0.4), facing((px0 + px1) / 2, 9, PASSAGE_END - 0.2, NORTH), {
		{ text = "UPGRADES", color = GOLD, scale = 0.6 },
		{ text = "special gear · coming soon", color = WHITE, scale = 0.3 },
	}, DARK_WOOD)
	box("UpgradesDoor", passage, -30, -24, 0, 7.5, PASSAGE_END - 0.4, PASSAGE_END, DARK_WOOD, Enum.Material.WoodPlanks)
	signpost(passage, px1 - 3, z0 + 4, NORTH, { "ARMORY · end of passage ►" })
	passage.Parent = folder
end

------------------------------------------------------------------------------------------
-- GLADIATOR ARMORY: the vaulted sandstone chamber (built in its original local coordinates and
-- moved by ARMORY_OFFSET). Layout (looking in from the door in its east wall):
--   north wall  BLADES (row 1)             west wall  HEAVY & REACH (row 2)
--   east wall   RANGED & SPECIAL (row 3, north of the door), storage shelves (south of it)
--   south wall  SHIELDS: LIGHT | BALANCED | HEAVY        centre  ARMOR mannequins on a dais
-- Displays sit on DisplayLines; EquipmentShopService spreads the items along them, so new
-- weapons, shields or armor appear automatically. The whole room is part of the safe lobby.
------------------------------------------------------------------------------------------

local function buildArmory(folder: Folder): ArmoryLayout
	local room = Instance.new("Model")
	room.Name = "GladiatorArmory"
	local x0, x1, hz, h = ARMORY_X0, ARMORY_X1, ARMORY_HALF_Z, ARMORY_HEIGHT
	local width = x1 - x0
	local cx = (x0 + x1) / 2

	-- Chamber: sandstone walls, cobbled floor with a limestone centre path, dark vault
	makePart("ArmoryFloor", Vector3.new(width + 4, 2, hz * 2 + 4), at(cx, -1, 0), FLOOR, Enum.Material.Cobblestone, room)
	makePart("ArmoryPath", Vector3.new(width - 30, 0.1, 10), at(cx + 15, 0.05, 0), Color3.fromRGB(176, 160, 132), Enum.Material.Limestone, room, DECOR)
	makePart("ArmoryCeiling", Vector3.new(width + 4, 2, hz * 2 + 4), at(cx, h + 1, 0), STONE_DARK, Enum.Material.Slate, room)
	makePart("ArmoryWestWall", Vector3.new(2, h, hz * 2 + 4), at(x0 - 1, h / 2, 0), SANDSTONE, Enum.Material.Sandstone, room)
	local eastSegment = hz - DOOR_HALF + 1
	for _, side in { -1, 1 } do
		makePart("ArmorySideWall", Vector3.new(width + 4, h, 2), at(cx, h / 2, side * (hz + 1)), SANDSTONE, Enum.Material.Sandstone, room)
		makePart("ArmoryEastWall", Vector3.new(2, h, eastSegment), at(x1 + 1, h / 2, side * (DOOR_HALF + eastSegment / 2)), SANDSTONE, Enum.Material.Sandstone, room)
		makePart("Skirting", Vector3.new(width, 1, 0.6), at(cx, 0.5, side * (hz - 0.3)), STONE, Enum.Material.Limestone, room, DECOR)
	end
	makePart("ArmoryEastWallTop", Vector3.new(2, h - DOOR_HEIGHT, DOOR_HALF * 2), at(x1 + 1, DOOR_HEIGHT + (h - DOOR_HEIGHT) / 2, 0), SANDSTONE, Enum.Material.Sandstone, room)

	-- Thick columns and vault ribs
	for _, x in { cx - 32, cx + 32 } do
		for _, z in { -22, 22 } do
			makePart("Column", Vector3.new(4.5, h, 4.5), at(x, h / 2, z), SANDSTONE, Enum.Material.Sandstone, room)
			makePart("ColumnBase", Vector3.new(5.6, 1.2, 5.6), at(x, 0.6, z), STONE, Enum.Material.Limestone, room)
			makePart("ColumnCapital", Vector3.new(5.6, 1, 5.6), at(x, h - 2.5, z), STONE, Enum.Material.Limestone, room, DECOR)
			torch(room, facing(x, 10, z + (if z < 0 then 2.3 else -2.3), if z < 0 then SOUTH else NORTH))
		end
		local y0, y1 = FLOOR_Y + h - 7, FLOOR_Y + h - 0.6
		segment(room, "Rib", Vector3.new(x, y0, -hz), Vector3.new(x, y1, -22), 2, 1.4, SANDSTONE, Enum.Material.Sandstone)
		segment(room, "Rib", Vector3.new(x, y1, -22), Vector3.new(x, y1, 22), 2, 1.4, SANDSTONE, Enum.Material.Sandstone)
		segment(room, "Rib", Vector3.new(x, y1, 22), Vector3.new(x, y0, hz), 2, 1.4, SANDSTONE, Enum.Material.Sandstone)
	end
	for _, z in { -22, 22 } do
		segment(room, "Rib", Vector3.new(cx - 32, FLOOR_Y + h - 0.6, z), Vector3.new(cx + 32, FLOOR_Y + h - 0.6, z), 1.6, 1.2, SANDSTONE, Enum.Material.Sandstone)
	end

	-- Display lines, 2.6 studs in front of each wall, facing into the room
	local function line(x: number, z: number, direction: Vector3, length: number): DisplayLine
		local position = Vector3.new(x, FLOOR_Y, z) + ARMORY_OFFSET
		return { cframe = CFrame.lookAt(position, position + direction), length = length }
	end
	local inset = 2.6
	local rangedZ = -(DOOR_HALF + hz) / 2 - 1
	local layout: ArmoryLayout = {
		blades = line(cx, -hz + inset, SOUTH, 70),
		heavy = line(x0 + inset, 0, EAST, 64),
		ranged = line(x1 - inset, rangedZ, WEST, hz - DOOR_HALF - 8),
		shields = {
			Light = line(cx - 28, hz - inset, NORTH, 24),
			Balanced = line(cx, hz - inset, NORTH, 20),
			Heavy = line(cx + 28, hz - inset, NORTH, 24),
		},
		armor = line(cx + 4, 0, EAST, 36),
		floorY = FLOOR_Y,
	}

	-- Bronze section signs above the rows
	bronzeSign(room, "BladesSign", 14, facing(cx, 16, -hz + 0.3, SOUTH), "BLADES", "fast & balanced")
	bronzeSign(room, "HeavySign", 18, facing(x0 + 0.3, 16, 0, EAST), "HEAVY & REACH", "heavy & long weapons")
	bronzeSign(room, "RangedSign", 17, facing(x1 - 0.3, 16, rangedZ, WEST), "RANGED & SPECIAL", "bows & special weapons")
	bronzeSign(room, "ShieldsSign", 16, facing(cx, 17.8, hz - 0.3, NORTH), "SHIELDS")
	for class, l in layout.shields :: { [string]: DisplayLine } do
		bronzeSign(room, class .. "Sign", 8, facing(l.cframe.Position.X - ARMORY_OFFSET.X, 13.6, hz - 0.3, NORTH), class:upper())
	end

	-- ARMOR: mannequin dais in the centre with a hanging sign
	local daisX = cx + 4 - 2
	makePart("ArmorDais", Vector3.new(12, 0.8, layout.armor.length + 4), at(daisX, 0.4, 0), STONE, Enum.Material.Limestone, room)
	makePart("ArmorDaisRim", Vector3.new(12.6, 0.3, layout.armor.length + 4.6), at(daisX, 0.15, 0), BRONZE, Enum.Material.Metal, room, DECOR)
	makePart("ArmorRug", Vector3.new(10, 0.1, layout.armor.length + 2), at(daisX, 0.85, 0), RED, Enum.Material.Fabric, room, DECOR)
	bronzeSign(room, "ArmorSign", 12, facing(daisX, 14, 0, EAST), "ARMOR", "one set · changed in the lobby only")
	for _, z in { -5, 5 } do
		makePart("SignChain", Vector3.new(0.2, h - 15.6, 0.2), at(daisX, 15.6 + (h - 15.6) / 2, z), IRON, Enum.Material.Metal, room, DECOR)
	end

	-- Red banners and torches along the walls
	for _, x in { cx - 44, cx - 16, cx + 16, cx + 44 } do
		banner(room, facing(x, 14, -hz, SOUTH))
		banner(room, facing(x, 14, hz, NORTH))
	end
	for _, z in { -30, -12, 12, 30 } do
		banner(room, facing(x0, 14, z, EAST))
		torch(room, facing(x0, 12, z + 6, EAST))
	end
	for _, x in { cx - 40, cx - 8, cx + 24 } do
		torch(room, facing(x, 12, -hz, SOUTH))
		torch(room, facing(x, 12, hz, NORTH))
	end
	torch(room, facing(x1, 12, -DOOR_HALF - 3, WEST))
	torch(room, facing(x1, 12, DOOR_HALF + 3, WEST))

	-- Storage south of the door: shelves, crates and barrels
	shelf(room, facing(x1 - 2, 0, 14, EAST) * CFrame.Angles(0, math.rad(180), 0), 8)
	shelf(room, facing(x1 - 2, 0, 24, EAST) * CFrame.Angles(0, math.rad(180), 0), 8)
	crateStack(room, x1 - 13, 32, 5)
	for i, z in { 30, 33.2 } do
		makePart("Barrel", Vector3.new(3, 2.4, 2.4), at(x1 - 3 - i * 0.4, 1.5, z), DARK_WOOD, Enum.Material.Wood, room, { shape = Enum.PartType.Cylinder })
	end
	signpost(room, x1 - 8, -DOOR_HALF - 1, EAST, { "BLADES · RANGED ►", "▲ ARMOR · HEAVY & REACH", "◄ SHIELDS" })

	-- Move the finished chamber to its place at the end of the side passage
	room:PivotTo(room:GetPivot() + ARMORY_OFFSET)
	room.Parent = folder
	zone(x0 + ARMORY_OFFSET.X, x1 + ARMORY_OFFSET.X, -hz + ARMORY_OFFSET.Z, hz + ARMORY_OFFSET.Z, h)
	return layout
end

------------------------------------------------------------------------------------------

-- Dungeon light: warm, dim ambient; torches, braziers and light shafts do the rest.
local function applyLighting()
	Lighting.Ambient = Color3.fromRGB(62, 52, 44)
	Lighting.OutdoorAmbient = Color3.fromRGB(96, 86, 74)
	Lighting.Brightness = 2
	Lighting.EnvironmentDiffuseScale = 0.35
	Lighting.EnvironmentSpecularScale = 0.3
	Lighting.ClockTime = 14
end

function LobbyService.build(): LobbyLayout
	local existing = Workspace:FindFirstChild(Config.LobbyFolderName)
	if existing then
		existing:Destroy()
	end
	table.clear(zones)
	local folder = Instance.new("Folder")
	folder.Name = Config.LobbyFolderName

	local spawnCFrame, arrivalSpawn, respawnSpawn = buildHall(folder)
	local romeGate = buildRomeGate(folder)
	local corridor = buildCorridor(folder)
	local tribunes = buildTribunes(folder)
	local pads: { PadLayout } = {}
	buildMultiplayer(folder, pads)
	local training = buildSingleplayer(folder, pads)
	-- The main arena entrance is the default Solo Zombies walk-on pad, not a mode picker.
	-- No start pedestal in the middle of the approach; the gate prompt is the optional shortcut.
	local entranceDef: PadDefinition = {
		Id = "ArenaSoloEntrance", Wing = "Single", Kind = "Solo", Title = "ZOMBIE SOLO",
		Subtitle = "Walk in · 6 rounds, then Otti", Enabled = true, Mode = "SOLO_ZOMBIES",
		Actions = {}, Color = RED,
	}
	table.insert(pads, buildPad(folder, entranceDef,
		facing(0, RAMP_RISE, -108, NORTH), Vector2.new(14, 6),
		facing(0, RAMP_RISE + 12, -111.5, SOUTH), 1))
	buildPassage(folder)
	local armory = buildArmory(folder)
	applyLighting()

	folder.Parent = Workspace
	return {
		folder = folder,
		spawnCFrame = spawnCFrame,
		arrivalSpawn = arrivalSpawn,
		respawnSpawn = respawnSpawn,
		armory = armory,
		pads = pads,
		arenaGate = corridor.portcullis,
		romeGate = romeGate,
		tribuneDoors = tribunes.doors,
		liveBoard = tribunes.liveBoard,
		liveCFrame = tribunes.liveCFrame,
		archiveSlots = corridor.slots,
		archivePlaques = corridor.plaques,
		trainingSlots = training.slots,
		trainingCFrame = training.cframe,
		trainingSize = training.size,
		floorY = FLOOR_Y,
	}
end

-- Inside the Gladiator Armory chamber (the shop only works here).
function LobbyService.isInArmory(position: Vector3): boolean
	local x0, x1 = ARMORY_X0 + ARMORY_OFFSET.X, ARMORY_X1 + ARMORY_OFFSET.X
	return position.X >= x0 - 1
		and position.X <= x1 + 1
		and math.abs(position.Z - ARMORY_OFFSET.Z) <= ARMORY_HALF_Z + 1
		and position.Y >= FLOOR_Y - 5
		and position.Y <= FLOOR_Y + ARMORY_HEIGHT + 2
end

-- Lobby players far outside the complex (e.g. fell through) are sent back to the spawn.
function LobbyService.isInside(position: Vector3): boolean
	for _, z in zones do
		if position.X >= z.min.X and position.X <= z.max.X and position.Y >= z.min.Y and position.Y <= z.max.Y and position.Z >= z.min.Z and position.Z <= z.max.Z then
			return true
		end
	end
	return false
end

return LobbyService
