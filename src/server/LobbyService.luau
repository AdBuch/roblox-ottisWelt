--!strict
-- Builds the underground gladiator complex beneath the Colosseum (about twice the old lobby):
--   central arrival hall (spawn + welcome board), GLADIATOR ARMORY (separate room, west),
--   mode area (north): SOLO ARENA gate, CO-OP LEGIONS party posts, TEAM BATTLE pads,
--   ZOMBIE ARCHIVE gallery (east annex), TRAINING yard (south-west), TRIBUNES door (east),
--   a barred prison corridor and storage corners. Wide open floor, clear signs, no maze.
-- Everything is anchored Parts and built-in materials. The lobby is a complete safe zone.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local STONE = Color3.fromRGB(118, 104, 90)
local STONE_DARK = Color3.fromRGB(86, 76, 66)
local SANDSTONE = Color3.fromRGB(196, 164, 118)
local FLOOR = Color3.fromRGB(108, 98, 86)
local WOOD = Color3.fromRGB(116, 78, 46)
local DARK_WOOD = Color3.fromRGB(78, 52, 32)
local IRON = Color3.fromRGB(64, 64, 68)
local BRONZE = Color3.fromRGB(176, 125, 60)
local HAY = Color3.fromRGB(212, 180, 92)
local RED = Color3.fromRGB(128, 22, 28)
local GOLD = Color3.fromRGB(240, 196, 80)
local FLAME = Color3.fromRGB(255, 150, 60)
local WHITE = Color3.new(1, 1, 1)

local FLOOR_Y = -80
local HALF_X, HALF_Z = 64, 44
local HEIGHT = 22
local ANNEX_X = 92 -- east annex (archive) reaches this x

-- Gladiator Armory (west of the hall, see buildArmory)
local ARMORY_X0, ARMORY_X1 = -178, -78
local ARMORY_HALF_Z = 38
local ARMORY_HEIGHT = 24
local DOOR_HALF = 7 -- the armory door / corridor spans z -7..7
local DOOR_HEIGHT = 13

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

export type LobbyLayout = {
	folder: Folder,
	spawnCFrame: CFrame,
	armory: ArmoryLayout,
	soloGate: BasePart,
	soloLabel: TextLabel,
	coopJoin: BasePart,
	coopReady: BasePart,
	coopStart: BasePart,
	coopQueue: BasePart,
	coopBoard: TextLabel,
	timePost: BasePart,
	firstToPost: BasePart,
	elimPost: BasePart,
	leaveQueuePost: BasePart,
	teamStatus: TextLabel,
	tribuneDoor: BasePart, -- WATCH LIVE spectator entrance (opens the live-battle overlay)
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

type PartOptions = { collide: boolean?, shape: Enum.PartType?, transparency: number? }
local DECOR: PartOptions = { collide = false }

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

type Line = { text: string, color: Color3, scale: number }

-- A board with text on its front face. Returns the labels in order.
local function sign(parent: Instance, name: string, size: Vector3, cframe: CFrame, lines: { Line }, background: Color3): { TextLabel }
	local board = makePart(name, size, cframe, background, Enum.Material.Wood, parent, DECOR)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
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

local function torch(parent: Instance, cframe: CFrame)
	makePart("TorchBracket", Vector3.new(0.4, 0.4, 1.2), cframe * CFrame.new(0, 0, -0.5) * CFrame.Angles(math.rad(30), 0, 0), IRON, Enum.Material.Metal, parent, DECOR)
	local flame = makePart("TorchFlame", Vector3.one * 0.7, cframe * CFrame.new(0, 0.6, -0.95), FLAME, Enum.Material.Neon, parent, { collide = false, shape = Enum.PartType.Ball })
	local light = Instance.new("PointLight")
	light.Color = FLAME
	light.Range = 20
	light.Brightness = 1.4
	light.Parent = flame
	local fire = Instance.new("Fire")
	fire.Size = 2
	fire.Heat = 4
	fire.Color = FLAME
	fire.SecondaryColor = Color3.fromRGB(255, 220, 120)
	fire.Parent = flame
end

local function banner(parent: Instance, cframe: CFrame)
	makePart("BannerRod", Vector3.new(4, 0.3, 0.3), cframe * CFrame.new(0, 3.2, -0.3), BRONZE, Enum.Material.Metal, parent, DECOR)
	makePart("Banner", Vector3.new(3.4, 6, 0.15), cframe * CFrame.new(0, 0, -0.25), RED, Enum.Material.Fabric, parent, DECOR)
	makePart("BannerStripe", Vector3.new(3.4, 0.4, 0.17), cframe * CFrame.new(0, -2.2, -0.27), GOLD, Enum.Material.Fabric, parent, DECOR)
end

-- A labelled stone post that hosts a ProximityPrompt (label floats above it).
local function post(parent: Instance, name: string, x: number, z: number, text: string, color: Color3): BasePart
	local stone = makePart(name, Vector3.new(2, 4, 2), at(x, 2, z), SANDSTONE, Enum.Material.Sandstone, parent)
	makePart(name .. "Cap", Vector3.new(2.4, 0.4, 2.4), at(x, 4.2, z), color, Enum.Material.Metal, parent, DECOR)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(150, 30)
	billboard.StudsOffset = Vector3.new(0, 3.6, 0)
	billboard.MaxDistance = 45
	billboard.Parent = stone
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(30, 24, 18)
	label.BackgroundTransparency = 0.2
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextColor3 = color
	label.Text = text
	label.Parent = billboard
	return stone
end

local function segment(parent: Instance, name: string, a: Vector3, b: Vector3, width: number, thickness: number, color: Color3, material: Enum.Material)
	makePart(name, Vector3.new(width, thickness, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), color, material, parent, DECOR)
end

------------------------------------------------------------------------------------------
-- Structure
------------------------------------------------------------------------------------------

local function buildShell(folder: Folder)
	local hall = Instance.new("Model")
	hall.Name = "Hall"
	makePart("Floor", Vector3.new(HALF_X * 2 + 4, 2, HALF_Z * 2 + 4), at(0, -1, 0), FLOOR, Enum.Material.Cobblestone, hall)
	makePart("Ceiling", Vector3.new(HALF_X * 2 + 4, 2, HALF_Z * 2 + 4), at(0, HEIGHT + 1, 0), STONE_DARK, Enum.Material.Slate, hall)
	-- West wall with the Gladiator Armory opening (z -DOOR_HALF..DOOR_HALF)
	local westLength = HALF_Z + 2 - DOOR_HALF
	for _, side in { -1, 1 } do
		makePart("WestWall", Vector3.new(2, HEIGHT, westLength), at(-HALF_X - 1, HEIGHT / 2, side * (DOOR_HALF + westLength / 2)), STONE, Enum.Material.Cobblestone, hall)
	end
	makePart("WestWallTop", Vector3.new(2, HEIGHT - DOOR_HEIGHT, DOOR_HALF * 2), at(-HALF_X - 1, DOOR_HEIGHT + (HEIGHT - DOOR_HEIGHT) / 2, 0), STONE, Enum.Material.Cobblestone, hall)
	makePart("SouthWall", Vector3.new(HALF_X * 2 + 4, HEIGHT, 2), at(0, HEIGHT / 2, HALF_Z + 1), STONE, Enum.Material.Cobblestone, hall)

	-- North wall with three gate openings (10 wide, 12 high) at x = -36, 0, 36
	local gateXs = { -36, 0, 36 }
	local edges = { -HALF_X - 2 }
	for _, gx in gateXs do
		table.insert(edges, gx - 5)
		table.insert(edges, gx + 5)
	end
	table.insert(edges, HALF_X + 2)
	for i = 1, #edges, 2 do
		local x0, x1 = edges[i], edges[i + 1]
		makePart("NorthWall", Vector3.new(x1 - x0, HEIGHT, 2), at((x0 + x1) / 2, HEIGHT / 2, -HALF_Z - 1), STONE, Enum.Material.Cobblestone, hall)
	end
	for _, gx in gateXs do
		makePart("NorthWallTop", Vector3.new(10, HEIGHT - 12, 2), at(gx, 12 + (HEIGHT - 12) / 2, -HALF_Z - 1), STONE, Enum.Material.Cobblestone, hall)
		-- Tunnel behind each gate, with stairs leading up toward the arena
		makePart("TunnelFloor", Vector3.new(12, 2, 20), at(gx, -1, -HALF_Z - 12), FLOOR, Enum.Material.Cobblestone, hall)
		for _, side in { -1, 1 } do
			makePart("TunnelWall", Vector3.new(2, HEIGHT, 20), at(gx + side * 6, HEIGHT / 2, -HALF_Z - 12), STONE_DARK, Enum.Material.Cobblestone, hall)
		end
		makePart("TunnelEnd", Vector3.new(14, HEIGHT, 2), at(gx, HEIGHT / 2, -HALF_Z - 22), STONE_DARK, Enum.Material.Cobblestone, hall)
		makePart("TunnelCeiling", Vector3.new(14, 2, 20), at(gx, HEIGHT + 1, -HALF_Z - 12), STONE_DARK, Enum.Material.Slate, hall)
		for i = 1, 12 do
			makePart("TunnelStair", Vector3.new(9, 0.8 * i, 1.2), at(gx, 0.4 * i, -HALF_Z - 4 - i * 1.2), SANDSTONE, Enum.Material.Limestone, hall)
		end
		torch(hall, facing(gx + 5, 10, -HALF_Z - 10, WEST))
	end

	-- East wall with the archive opening (z -14..14) and the prison corridor opening (z 28..38)
	local eastEdges = { { -HALF_Z - 2, -14 }, { 14, 28 }, { 38, HALF_Z + 2 } }
	for _, range in eastEdges do
		makePart("EastWall", Vector3.new(2, HEIGHT, range[2] - range[1]), at(HALF_X + 1, HEIGHT / 2, (range[1] + range[2]) / 2), STONE, Enum.Material.Cobblestone, hall)
	end
	makePart("EastWallTop", Vector3.new(2, HEIGHT - 14, 28), at(HALF_X + 1, 14 + (HEIGHT - 14) / 2, 0), STONE, Enum.Material.Cobblestone, hall)
	makePart("EastWallTop", Vector3.new(2, HEIGHT - 10, 10), at(HALF_X + 1, 10 + (HEIGHT - 10) / 2, 33), STONE, Enum.Material.Cobblestone, hall)

	-- Thick sandstone columns and vault ribs
	for _, x in { -46, -22, 22, 46 } do
		for _, z in { -18, 18 } do
			makePart("Column", Vector3.new(4, HEIGHT, 4), at(x, HEIGHT / 2, z), SANDSTONE, Enum.Material.Sandstone, hall)
			makePart("ColumnBase", Vector3.new(5, 1, 5), at(x, 0.5, z), STONE, Enum.Material.Limestone, hall)
		end
		local y0, y1 = FLOOR_Y + HEIGHT - 7, FLOOR_Y + HEIGHT - 0.6
		segment(hall, "Rib", Vector3.new(x, y0, -HALF_Z), Vector3.new(x, y1, -18), 1.8, 1.4, SANDSTONE, Enum.Material.Sandstone)
		segment(hall, "Rib", Vector3.new(x, y1, -18), Vector3.new(x, y1, 18), 1.8, 1.4, SANDSTONE, Enum.Material.Sandstone)
		segment(hall, "Rib", Vector3.new(x, y1, 18), Vector3.new(x, y0, HALF_Z), 1.8, 1.4, SANDSTONE, Enum.Material.Sandstone)
	end
	hall.Parent = folder
end

local function buildArrival(folder: Folder): CFrame
	local area = Instance.new("Model")
	area.Name = "ArrivalHall"
	sign(area, "WelcomeBoard", Vector3.new(26, 9, 0.6), facing(0, 14, 2, SOUTH), {
		{ text = "OTTI COLOSSEUM", color = GOLD, scale = 0.3 },
		{ text = "Gear up in the GLADIATOR ARMORY (west)", color = WHITE, scale = 0.15 },
		{ text = "Pick SOLO, CO-OP or TEAM BATTLE (north)", color = WHITE, scale = 0.15 },
		{ text = "Learn your foes in the ZOMBIE ARCHIVE (east)", color = WHITE, scale = 0.15 },
		{ text = "Interact: F · Combos: attack, block and jump", color = Color3.fromRGB(255, 210, 120), scale = 0.13 },
	}, DARK_WOOD)
	for _, x in { -11, 11 } do
		makePart("BoardChain", Vector3.new(0.2, HEIGHT - 18.5, 0.2), at(x, 18.5 + (HEIGHT - 18.5) / 2, 2), IRON, Enum.Material.Metal, area, DECOR)
	end
	for _, x in { -10, 10 } do
		makePart("Bench", Vector3.new(7, 0.5, 1.6), at(x, 1.3, 22), WOOD, Enum.Material.Wood, area)
		for _, dx in { -2.8, 2.8 } do
			makePart("BenchLeg", Vector3.new(0.5, 1.1, 1.4), at(x + dx, 0.55, 22), DARK_WOOD, Enum.Material.Wood, area)
		end
	end
	area.Parent = folder

	local spawnPosition = Vector3.new(0, FLOOR_Y + 0.5, 14)
	local spawnCFrame = CFrame.lookAt(spawnPosition, spawnPosition + NORTH)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = spawnCFrame
	spawn.Color = SANDSTONE
	spawn.Material = Enum.Material.Limestone
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = folder
	return spawnCFrame
end

------------------------------------------------------------------------------------------
-- GLADIATOR ARMORY: a separate vaulted sandstone chamber west of the hall, reached through a
-- short corridor from an opening in the hall's west wall. Layout (looking in from the door):
--   north wall  BLADES (row 1)             west wall  HEAVY & REACH (row 2)
--   east wall   RANGED & SPECIAL (row 3, north of the door), storage shelves (south of it)
--   south wall  SHIELDS: LIGHT | BALANCED | HEAVY        centre  ARMOR mannequins on a dais
-- Displays sit on DisplayLines; EquipmentShopService spreads the items along them, so new
-- weapons, shields or armor appear automatically. The whole room is part of the safe lobby.
------------------------------------------------------------------------------------------

-- A bronze sign (metal plate, dark lettering) for the armory sections.
local function bronzeSign(parent: Instance, name: string, width: number, cframe: CFrame, text: string, sub: string?)
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
end

local function signpost(parent: Instance, x: number, z: number, face: Vector3, boards: { string })
	makePart("Signpost", Vector3.new(0.6, 9, 0.6), at(x, 4.5, z), DARK_WOOD, Enum.Material.Wood, parent)
	makePart("SignpostBase", Vector3.new(1.6, 0.6, 1.6), at(x, 0.3, z), STONE, Enum.Material.Limestone, parent)
	for i, text in boards do
		sign(parent, "ArrowBoard", Vector3.new(8, 1.4, 0.25), facing(x, 8.6 - (i - 1) * 1.7, z, face) * CFrame.new(0, 0, -0.45), { { text = text, color = GOLD, scale = 0.85 } }, RED)
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
			makePart("Roll", Vector3.new(2.2, 0.8, 0.8), cframe * CFrame.new(0.4, y + 0.55, 0.2), Color3.fromRGB(96, 62, 36), Enum.Material.Leather, parent, { collide = false, shape = Enum.PartType.Cylinder })
			makePart("SpareRim", Vector3.new(0.25, 2, 2), cframe * CFrame.new(width / 2 - 1.3, y + 1.15, 0) * CFrame.Angles(0, math.rad(80), 0), BRONZE, Enum.Material.Metal, parent, { collide = false, shape = Enum.PartType.Cylinder })
		end
	end
end

local function buildArmory(folder: Folder): ArmoryLayout
	local room = Instance.new("Model")
	room.Name = "GladiatorArmory"
	local x0, x1, hz, h = ARMORY_X0, ARMORY_X1, ARMORY_HALF_Z, ARMORY_HEIGHT
	local width = x1 - x0
	local cx = (x0 + x1) / 2

	-- Corridor from the hall's west wall to the armory's east wall
	local c0, c1 = -HALF_X - 2, x1
	local corridorLength = c0 - c1
	makePart("CorridorFloor", Vector3.new(corridorLength, 2, DOOR_HALF * 2 + 4), at((c0 + c1) / 2, -1, 0), FLOOR, Enum.Material.Cobblestone, room)
	makePart("CorridorCeiling", Vector3.new(corridorLength, 2, DOOR_HALF * 2 + 4), at((c0 + c1) / 2, DOOR_HEIGHT + 1, 0), STONE_DARK, Enum.Material.Slate, room)
	for _, side in { -1, 1 } do
		makePart("CorridorWall", Vector3.new(corridorLength, DOOR_HEIGHT, 2), at((c0 + c1) / 2, DOOR_HEIGHT / 2, side * (DOOR_HALF + 1)), SANDSTONE, Enum.Material.Sandstone, room)
	end
	torch(room, facing((c0 + c1) / 2, 9, -DOOR_HALF, SOUTH))
	torch(room, facing((c0 + c1) / 2, 9, DOOR_HALF, NORTH))

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
		local position = Vector3.new(x, FLOOR_Y, z)
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
		bronzeSign(room, class .. "Sign", 8, facing(l.cframe.Position.X, 13.6, hz - 0.3, NORTH), class:upper())
	end

	-- ARMOR: mannequin dais in the centre with a hanging sign
	local daisX = layout.armor.cframe.Position.X - 2
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

	-- Entrance in the hall: arch, the GLADIATOR ARMORY sign, torches and directional signs
	local entrance = Instance.new("Model")
	entrance.Name = "ArmoryEntrance"
	for _, side in { -1, 1 } do
		makePart("ArchPillar", Vector3.new(1.8, DOOR_HEIGHT + 1, 1.8), at(-HALF_X + 0.6, (DOOR_HEIGHT + 1) / 2, side * (DOOR_HALF + 0.9)), SANDSTONE, Enum.Material.Limestone, entrance)
		torch(entrance, facing(-HALF_X + 0.2, 10, side * (DOOR_HALF + 3), EAST))
	end
	makePart("ArchLintel", Vector3.new(2, 1.6, DOOR_HALF * 2 + 4), at(-HALF_X + 0.6, DOOR_HEIGHT + 0.8, 0), SANDSTONE, Enum.Material.Limestone, entrance)
	bronzeSign(entrance, "ArmoryEntranceSign", 18, facing(-HALF_X + 1.7, DOOR_HEIGHT + 3.4, 0, EAST), "GLADIATOR ARMORY", "weapons · shields · armor")
	signpost(entrance, -HALF_X + 12, -DOOR_HALF - 5, EAST, { "◄ WEAPONS", "◄ SHIELDS", "◄ ARMOR" })
	signpost(room, x1 - 8, -DOOR_HALF - 1, EAST, { "BLADES · RANGED ►", "▲ ARMOR · HEAVY & REACH", "◄ SHIELDS" })
	entrance.Parent = folder
	room.Parent = folder
	return layout
end

type ModeArea = {
	soloGate: BasePart,
	soloLabel: TextLabel,
	coopJoin: BasePart,
	coopReady: BasePart,
	coopStart: BasePart,
	coopQueue: BasePart,
	coopBoard: TextLabel,
	timePost: BasePart,
	firstToPost: BasePart,
	elimPost: BasePart,
	leaveQueuePost: BasePart,
	teamStatus: TextLabel,
}

local function portcullis(parent: Instance, gx: number)
	local z = -HALF_Z - 0.3
	for x = -4.5, 4.51, 1 do
		makePart("GateBar", Vector3.new(0.35, 12, 0.35), at(gx + x, 6, z), IRON, Enum.Material.Metal, parent)
	end
	for _, y in { 2.5, 6, 9.5 } do
		makePart("GateBand", Vector3.new(10, 0.35, 0.45), at(gx, y, z), IRON, Enum.Material.Metal, parent)
	end
	for _, side in { -1, 1 } do
		makePart("GatePillar", Vector3.new(1.6, 13, 1.6), at(gx + side * 5.8, 6.5, -HALF_Z + 0.2), SANDSTONE, Enum.Material.Limestone, parent)
	end
	torch(parent, facing(gx - 7.5, 10, -HALF_Z + 0.1, SOUTH))
	torch(parent, facing(gx + 7.5, 10, -HALF_Z + 0.1, SOUTH))
end

local function buildModeArea(folder: Folder): ModeArea
	local area = Instance.new("Model")
	area.Name = "ModeSelection"

	-- SOLO ARENA (x = -36)
	portcullis(area, -36)
	local soloLabels = sign(area, "SoloSign", Vector3.new(14, 4, 0.5), facing(-36, 15, -HALF_Z + 0.3, SOUTH), {
		{ text = "SOLO ARENA", color = GOLD, scale = 0.5 },
		{ text = "6 rounds alone · hold F at the gate", color = WHITE, scale = 0.22 },
		{ text = "ARENA READY", color = Color3.fromRGB(140, 255, 140), scale = 0.2 },
	}, RED)
	local soloGate = makePart("SoloGatePrompt", Vector3.new(10, 6, 0.5), at(-36, 3, -HALF_Z + 0.6), IRON, Enum.Material.Metal, area, { collide = false, transparency = 1 })

	-- CO-OP LEGIONS (x = 0): party posts and a roster board
	portcullis(area, 0)
	local coopLabels = sign(area, "CoopSign", Vector3.new(16, 7, 0.5), facing(0, 15.5, -HALF_Z + 0.3, SOUTH), {
		{ text = "CO-OP LEGIONS", color = GOLD, scale = 0.28 },
		{ text = "1-4 players · shared waves", color = WHITE, scale = 0.14 },
		{ text = "No party yet", color = Color3.fromRGB(220, 220, 220), scale = 0.5 },
	}, RED)
	local coopJoin = post(area, "CoopJoinPost", -7, -32, "JOIN / LEAVE PARTY", GOLD)
	local coopReady = post(area, "CoopReadyPost", 0, -32, "READY / UNREADY", Color3.fromRGB(140, 255, 140))
	local coopStart = post(area, "CoopStartPost", 7, -32, "START (LEADER)", Color3.fromRGB(255, 180, 120))
	local coopQueue = post(area, "CoopQueuePost", 0, -23, "FIND PLAYERS", Color3.fromRGB(150, 210, 255))
	makePart("PartyCircle", Vector3.new(0.2, 26, 26), at(0, 0.1, -30) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(150, 120, 70), Enum.Material.Sandstone, area, { collide = false, shape = Enum.PartType.Cylinder })

	-- TEAM BATTLES (x = 36): one matchmaking post per submode (teams are formed by the matchmaker)
	portcullis(area, 36)
	local teamLabels = sign(area, "TeamSign", Vector3.new(14, 4, 0.5), facing(36, 15, -HALF_Z + 0.3, SOUTH), {
		{ text = "TEAM BATTLES", color = GOLD, scale = 0.5 },
		{ text = "Time · First to 20 · Elimination", color = WHITE, scale = 0.22 },
		{ text = "1v1 to 4v4 · equal teams", color = Color3.fromRGB(220, 220, 220), scale = 0.2 },
	}, RED)
	local timePost = post(area, "TimeBattlePost", 27, -32, "TIME BATTLE", Color3.fromRGB(255, 200, 120))
	local firstToPost = post(area, "FirstToPost", 36, -32, "FIRST TO 20", Color3.fromRGB(255, 150, 120))
	local elimPost = post(area, "EliminationPost", 45, -32, "ELIMINATION", Color3.fromRGB(255, 110, 110))
	local leaveQueuePost = post(area, "LeaveQueuePost", 36, -23, "LEAVE QUEUE", Color3.fromRGB(220, 220, 220))
	makePart("TeamCircle", Vector3.new(0.2, 26, 26), at(36, 0.1, -30) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(120, 60, 60), Enum.Material.Sandstone, area, { collide = false, shape = Enum.PartType.Cylinder })

	banner(area, facing(-18, 13, -HALF_Z, SOUTH))
	banner(area, facing(18, 13, -HALF_Z, SOUTH))
	area.Parent = folder
	return {
		soloGate = soloGate,
		soloLabel = soloLabels[3],
		coopJoin = coopJoin,
		coopReady = coopReady,
		coopStart = coopStart,
		coopQueue = coopQueue,
		coopBoard = coopLabels[3],
		timePost = timePost,
		firstToPost = firstToPost,
		elimPost = elimPost,
		leaveQueuePost = leaveQueuePost,
		teamStatus = teamLabels[3],
	}
end

-- East annex: the ZOMBIE ARCHIVE with six iron-barred cages along its far wall.
local function buildArchive(folder: Folder): ({ CFrame }, { CFrame })
	local archive = Instance.new("Model")
	archive.Name = "ArchiveGallery"
	local x0, x1 = HALF_X + 2, ANNEX_X
	local halfZ = 22
	makePart("ArchiveFloor", Vector3.new(x1 - x0 + 2, 2, halfZ * 2 + 2), at((x0 + x1) / 2, -1, 0), FLOOR, Enum.Material.Cobblestone, archive)
	makePart("ArchiveCeiling", Vector3.new(x1 - x0 + 2, 2, halfZ * 2 + 2), at((x0 + x1) / 2, HEIGHT + 1, 0), STONE_DARK, Enum.Material.Slate, archive)
	makePart("ArchiveBackWall", Vector3.new(2, HEIGHT, halfZ * 2 + 2), at(x1 + 1, HEIGHT / 2, 0), STONE_DARK, Enum.Material.Cobblestone, archive)
	for _, side in { -1, 1 } do
		makePart("ArchiveSideWall", Vector3.new(x1 - x0 + 2, HEIGHT, 2), at((x0 + x1) / 2, HEIGHT / 2, side * (halfZ + 1)), STONE_DARK, Enum.Material.Cobblestone, archive)
	end
	sign(archive, "ArchiveSign", Vector3.new(16, 3.4, 0.5), facing(HALF_X + 0.4, 17, 0, WEST), {
		{ text = "ZOMBIE ARCHIVE", color = GOLD, scale = 0.62 },
		{ text = "Know your foes before the arena", color = WHITE, scale = 0.3 },
	}, RED)

	local slots, plaques = {}, {}
	local cageFront = x1 - 8
	for i, z in { -18, -10.8, -3.6, 3.6, 10.8, 18 } do
		-- Cage: solid stone sides/back/top + iron bars in front (zombies can never leave)
		for _, side in { -1, 1 } do
			makePart("CageSide", Vector3.new(8, 13, 0.8), at(cageFront + 4, 6.5, z + side * 3.6), STONE, Enum.Material.Cobblestone, archive)
		end
		makePart("CageTop", Vector3.new(8, 0.8, 8), at(cageFront + 4, 13.4, z), STONE, Enum.Material.Cobblestone, archive)
		makePart("CageFloor", Vector3.new(8, 0.4, 7), at(cageFront + 4, 0.2, z), HAY, Enum.Material.Grass, archive)
		for bz = -3, 3 do
			makePart("CageBar", Vector3.new(0.3, 13, 0.3), at(cageFront, 6.5, z + bz), IRON, Enum.Material.Metal, archive)
		end
		for _, y in { 1, 7, 12.8 } do
			makePart("CageBand", Vector3.new(0.4, 0.4, 7.2), at(cageFront, y, z), IRON, Enum.Material.Metal, archive)
		end
		slots[i] = facing(cageFront + 4, 0.4, z, WEST)
		plaques[i] = facing(cageFront - 0.2, 16.2, z, WEST)
		local lamp = makePart("CageLamp", Vector3.one * 0.6, at(cageFront + 4, 12.6, z), FLAME, Enum.Material.Neon, archive, { collide = false, shape = Enum.PartType.Ball })
		local light = Instance.new("PointLight")
		light.Color = FLAME
		light.Range = 12
		light.Brightness = 1.2
		light.Parent = lamp
	end
	torch(archive, facing(x0 + 1, 10, -halfZ + 0.2, SOUTH))
	torch(archive, facing(x0 + 1, 10, halfZ - 0.2, NORTH))
	archive.Parent = folder
	return slots, plaques
end

local function buildTraining(folder: Folder): ({ CFrame }, CFrame, Vector3)
	local yard = Instance.new("Model")
	yard.Name = "TrainingYard"
	local center = Vector3.new(-44, FLOOR_Y, 32)
	makePart("YardFloor", Vector3.new(24, 0.2, 18), at(center.X, 0.1, center.Z), Color3.fromRGB(214, 190, 136), Enum.Material.Sand, yard)
	for _, x in { -12, 12 } do
		makePart("YardRail", Vector3.new(0.4, 1.2, 18), at(center.X + x, 1, center.Z), DARK_WOOD, Enum.Material.Wood, yard, DECOR)
	end
	sign(yard, "TrainingSign", Vector3.new(12, 3, 0.4), facing(center.X, 8.5, HALF_Z - 1, NORTH), {
		{ text = "TRAINING", color = GOLD, scale = 0.6 },
		{ text = "Test attacks, jump attacks and combos", color = WHITE, scale = 0.3 },
	}, RED)
	-- COMBO TRAINING board: the client writes the equipped weapon's combinations onto it
	local board = makePart("ComboTrainingBoard", Vector3.new(9, 7, 0.4), facing(center.X - 11.3, 4.5, center.Z - 1, EAST), Color3.fromRGB(60, 40, 26), Enum.Material.Wood, yard)
	board.CanCollide = false
	local slots = { facing(center.X - 5, 0.2, center.Z + 2, NORTH), facing(center.X + 5, 0.2, center.Z + 2, NORTH) }
	yard.Parent = folder
	return slots, CFrame.new(center + Vector3.new(0, 6, 0)), Vector3.new(26, 16, 22)
end

local function buildTribuneDoor(folder: Folder): (BasePart, TextLabel, CFrame)
	local door = Instance.new("Model")
	door.Name = "TribuneDoor"
	local x, z = HALF_X - 0.4, -30
	local leaf = makePart("Door", Vector3.new(0.6, 10, 8), at(x, 5, z), DARK_WOOD, Enum.Material.WoodPlanks, door)
	for _, y in { 2, 5, 8 } do
		makePart("DoorBand", Vector3.new(0.7, 0.4, 8.1), at(x - 0.05, y, z), IRON, Enum.Material.Metal, door)
	end
	for _, side in { -1, 1 } do
		makePart("DoorPillar", Vector3.new(1.4, 11, 1.4), at(x - 0.3, 5.5, z + side * 4.8), SANDSTONE, Enum.Material.Limestone, door)
	end
	makePart("DoorLintel", Vector3.new(1.6, 1.4, 11), at(x - 0.3, 11.7, z), SANDSTONE, Enum.Material.Limestone, door)
	sign(door, "TribuneSign", Vector3.new(10, 3, 0.5), facing(x - 0.5, 14.2, z, WEST), {
		{ text = "WATCH LIVE", color = GOLD, scale = 0.62 },
		{ text = "Live battles in the Colosseum · hold F", color = WHITE, scale = 0.3 },
	}, RED)
	-- Stone stairs climbing along the wall toward the stands
	for i = 1, 12 do
		makePart("WallStair", Vector3.new(3, i, 1.2), at(HALF_X - 1.6, i / 2, z + 6 + i * 1.2), SANDSTONE, Enum.Material.Limestone, door)
	end
	torch(door, facing(HALF_X, 9, z - 7.5, WEST))
	-- LIVE IN THE COLOSSEUM results board next to the door (server writes the live count)
	local live = sign(door, "LiveBoard", Vector3.new(9, 5, 0.4), facing(x - 0.4, 6, z - 10, WEST), {
		{ text = "LIVE IN THE COLOSSEUM", color = GOLD, scale = 0.3 },
		{ text = "No live battles", color = WHITE, scale = 0.35 },
		{ text = "hold F at the door", color = Color3.fromRGB(255, 210, 120), scale = 0.2 },
	}, DARK_WOOD)
	door.Parent = folder
	local arrival = Vector3.new(x - 8, FLOOR_Y + 3.5, z - 6)
	return leaf, live[2], CFrame.lookAt(arrival, arrival + WEST)
end

-- Barred prison corridor behind the east opening (z 28..38) and storage corners.
local function buildPrisonAndStorage(folder: Folder)
	local prison = Instance.new("Model")
	prison.Name = "PrisonCorridor"
	local x0, x1 = HALF_X + 2, HALF_X + 30
	makePart("CorridorFloor", Vector3.new(x1 - x0 + 2, 2, 20), at((x0 + x1) / 2, -1, 33), FLOOR, Enum.Material.Cobblestone, prison)
	makePart("CorridorCeiling", Vector3.new(x1 - x0 + 2, 2, 20), at((x0 + x1) / 2, 11, 33), STONE_DARK, Enum.Material.Slate, prison)
	for _, z in { 22, 44 } do
		makePart("CorridorWall", Vector3.new(x1 - x0 + 2, 10, 2), at((x0 + x1) / 2, 5, z), STONE_DARK, Enum.Material.Cobblestone, prison)
	end
	makePart("CorridorEnd", Vector3.new(2, 10, 22), at(x1 + 1, 5, 33), STONE_DARK, Enum.Material.Cobblestone, prison)
	for _, side in { -1, 1 } do
		local zBars = 33 + side * 5
		for x = x0 + 2, x1 - 2, 1.2 do
			makePart("CellBar", Vector3.new(0.25, 9, 0.25), at(x, 4.5, zBars), IRON, Enum.Material.Metal, prison)
		end
		for cx = x0 + 6, x1 - 4, 9 do
			makePart("CellBench", Vector3.new(4, 0.5, 1.4), at(cx, 1.3, 33 + side * 9.5), WOOD, Enum.Material.Wood, prison)
			makePart("Hay", Vector3.new(3, 0.8, 2), at(cx + 3, 0.4, 33 + side * 8.5), HAY, Enum.Material.Grass, prison)
			local ring = makePart("WallRing", Vector3.new(0.2, 1, 1), at(cx, 6, 33 + side * 10.9) * CFrame.Angles(0, math.rad(90), 0), IRON, Enum.Material.Metal, prison, { collide = false, shape = Enum.PartType.Cylinder })
			for link = 1, 3 do
				makePart("ChainLink", Vector3.new(0.15, 0.5, 0.3), ring.CFrame * CFrame.new(0, -0.3 - link * 0.45, 0) * CFrame.Angles(0, if link % 2 == 0 then math.rad(90) else 0, 0), IRON, Enum.Material.Metal, prison, DECOR)
			end
		end
	end
	local glow = makePart("DimLight", Vector3.one * 0.5, at(x1 - 2, 9.5, 33), FLAME, Enum.Material.Neon, prison, DECOR)
	local light = Instance.new("PointLight")
	light.Color = FLAME
	light.Range = 14
	light.Brightness = 0.6
	light.Parent = glow
	prison.Parent = folder

	-- Storage corners: crates, barrels, hay, benches
	local storage = Instance.new("Model")
	storage.Name = "Storage"
	local function crates(x: number, z: number)
		for i, offset in { Vector3.new(0, 0, 0), Vector3.new(3.2, 0, 0.4), Vector3.new(1.6, 3, 0.2) } do
			makePart("Crate", Vector3.one * 3, at(x + offset.X, 1.5 + offset.Y, z + offset.Z) * CFrame.Angles(0, math.rad(i * 7), 0), WOOD, Enum.Material.WoodPlanks, storage)
		end
	end
	local function barrel(x: number, z: number)
		makePart("Barrel", Vector3.new(3, 2.4, 2.4), at(x, 1.5, z) * CFrame.Angles(0, 0, math.rad(90)), DARK_WOOD, Enum.Material.Wood, storage, { shape = Enum.PartType.Cylinder })
		makePart("BarrelHoop", Vector3.new(0.25, 2.5, 2.5), at(x, 2.3, z) * CFrame.Angles(0, 0, math.rad(90)), IRON, Enum.Material.Metal, storage, { collide = false, shape = Enum.PartType.Cylinder })
	end
	crates(-60, -40)
	barrel(-55, -40.5)
	barrel(-52, -41)
	crates(56, -12)
	barrel(60, -8)
	makePart("HayBale", Vector3.new(4, 2, 2.5), at(58, 1, 22), HAY, Enum.Material.Grass, storage)
	makePart("HayBale", Vector3.new(4, 2, 2.5), at(58.5, 3, 22.2), HAY, Enum.Material.Grass, storage)
	storage.Parent = folder
end

local function buildLighting(folder: Folder)
	local lights = Instance.new("Model")
	lights.Name = "WallTorches"
	for _, z in { -36, -14, 14, 36 } do
		torch(lights, facing(-HALF_X, 13, z, EAST))
	end
	for _, x in { -40, -16, 30, 52 } do
		torch(lights, facing(x, 13, HALF_Z, NORTH))
	end
	torch(lights, facing(HALF_X, 13, 20, WEST))
	torch(lights, facing(HALF_X, 13, -20, WEST))
	banner(lights, facing(-HALF_X, 13, -22, EAST))
	banner(lights, facing(-HALF_X, 13, 18, EAST))
	banner(lights, facing(-30, 13, HALF_Z, NORTH))
	banner(lights, facing(46, 13, HALF_Z, NORTH))
	lights.Parent = folder
end

function LobbyService.build(): LobbyLayout
	local existing = Workspace:FindFirstChild(Config.LobbyFolderName)
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = Config.LobbyFolderName

	buildShell(folder)
	local spawnCFrame = buildArrival(folder)
	local armory = buildArmory(folder)
	local modes = buildModeArea(folder)
	local archiveSlots, archivePlaques = buildArchive(folder)
	local trainingSlots, trainingCFrame, trainingSize = buildTraining(folder)
	local tribuneDoor, liveBoard, liveCFrame = buildTribuneDoor(folder)
	buildPrisonAndStorage(folder)
	buildLighting(folder)

	folder.Parent = Workspace
	return {
		folder = folder,
		spawnCFrame = spawnCFrame,
		armory = armory,
		soloGate = modes.soloGate,
		soloLabel = modes.soloLabel,
		coopJoin = modes.coopJoin,
		coopReady = modes.coopReady,
		coopStart = modes.coopStart,
		coopBoard = modes.coopBoard,
		coopQueue = modes.coopQueue,
		timePost = modes.timePost,
		firstToPost = modes.firstToPost,
		elimPost = modes.elimPost,
		leaveQueuePost = modes.leaveQueuePost,
		teamStatus = modes.teamStatus,
		tribuneDoor = tribuneDoor,
		liveBoard = liveBoard,
		liveCFrame = liveCFrame,
		archiveSlots = archiveSlots,
		archivePlaques = archivePlaques,
		trainingSlots = trainingSlots,
		trainingCFrame = trainingCFrame,
		trainingSize = trainingSize,
		floorY = FLOOR_Y,
	}
end

-- Lobby players far outside the complex (e.g. fell through) are sent back to the spawn.
-- Inside the Gladiator Armory chamber (the shop only works here).
function LobbyService.isInArmory(position: Vector3): boolean
	return position.X >= ARMORY_X0 - 1
		and position.X <= ARMORY_X1 + 1
		and math.abs(position.Z) <= ARMORY_HALF_Z + 1
		and position.Y >= FLOOR_Y - 5
		and position.Y <= FLOOR_Y + ARMORY_HEIGHT + 2
end

function LobbyService.isInside(position: Vector3): boolean
	if LobbyService.isInArmory(position) or (position.X >= ARMORY_X1 - 1 and position.X <= -HALF_X and math.abs(position.Z) <= DOOR_HALF + 1 and position.Y >= FLOOR_Y - 10 and position.Y <= FLOOR_Y + DOOR_HEIGHT + 5) then
		return true -- the armory and its corridor belong to the lobby
	end
	return position.X >= -HALF_X - 2
		and position.X <= ANNEX_X + 4
		and position.Z >= -HALF_Z - 26
		and position.Z <= HALF_Z + 4
		and position.Y >= FLOOR_Y - 10
		and position.Y <= FLOOR_Y + HEIGHT + 5
end

return LobbyService
