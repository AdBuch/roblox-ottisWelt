--!strict
-- Builds the underground gladiator complex beneath the Colosseum (about twice the old lobby):
--   central arrival hall (spawn + welcome board), WEAPONS wall (west), SHIELDS wall (south),
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

export type LobbyLayout = {
	folder: Folder,
	spawnCFrame: CFrame,
	weaponSlots: { CFrame },
	shieldSlots: { CFrame },
	soloGate: BasePart,
	soloLabel: TextLabel,
	coopJoin: BasePart,
	coopReady: BasePart,
	coopStart: BasePart,
	coopBoard: TextLabel,
	redPad: BasePart,
	bluePad: BasePart,
	teamReady: BasePart,
	teamLeave: BasePart,
	teamBalance: BasePart,
	redBoard: TextLabel,
	blueBoard: TextLabel,
	teamStatus: TextLabel,
	tribuneDoor: BasePart,
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
	makePart("WestWall", Vector3.new(2, HEIGHT, HALF_Z * 2 + 4), at(-HALF_X - 1, HEIGHT / 2, 0), STONE, Enum.Material.Cobblestone, hall)
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
		{ text = "Choose your weapon and shield", color = WHITE, scale = 0.15 },
		{ text = "Pick SOLO, CO-OP or TEAM BATTLE (north)", color = WHITE, scale = 0.15 },
		{ text = "Learn your foes in the ZOMBIE ARCHIVE (east)", color = WHITE, scale = 0.15 },
		{ text = "Interact: hold F · Specials: Q and E", color = Color3.fromRGB(255, 210, 120), scale = 0.13 },
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

local function buildShopWalls(folder: Folder): ({ CFrame }, { CFrame })
	local shop = Instance.new("Model")
	shop.Name = "ShopWalls"
	-- Weapons: west wall
	makePart("WeaponBackboard", Vector3.new(0.4, 11, 66), at(-HALF_X + 0.3, 7, -2), DARK_WOOD, Enum.Material.WoodPlanks, shop)
	makePart("WeaponRail", Vector3.new(0.5, 0.3, 66), at(-HALF_X + 0.6, 10, -2), BRONZE, Enum.Material.Metal, shop, DECOR)
	sign(shop, "WeaponsSign", Vector3.new(16, 3, 0.4), facing(-HALF_X + 0.6, 15, -2, EAST), { { text = "WEAPONS", color = GOLD, scale = 0.9 } }, RED)
	-- Shields: south wall
	makePart("ShieldBackboard", Vector3.new(66, 11, 0.4), at(16, 7, HALF_Z - 0.3), DARK_WOOD, Enum.Material.WoodPlanks, shop)
	makePart("ShieldRail", Vector3.new(66, 0.3, 0.5), at(16, 10, HALF_Z - 0.6), BRONZE, Enum.Material.Metal, shop, DECOR)
	sign(shop, "ShieldsSign", Vector3.new(16, 3, 0.4), facing(16, 15, HALF_Z - 0.6, NORTH), { { text = "SHIELDS", color = GOLD, scale = 0.9 } }, RED)
	shop.Parent = folder

	local weaponSlots, shieldSlots = {}, {}
	for i = 1, 8 do
		local position = Vector3.new(-HALF_X + 4, FLOOR_Y, -30 + (i - 1) * 8)
		weaponSlots[i] = CFrame.lookAt(position, position + EAST)
	end
	for i = 1, 8 do
		local position = Vector3.new(-12 + (i - 1) * 8, FLOOR_Y, HALF_Z - 4)
		shieldSlots[i] = CFrame.lookAt(position, position + NORTH)
	end
	return weaponSlots, shieldSlots
end

type ModeArea = {
	soloGate: BasePart,
	soloLabel: TextLabel,
	coopJoin: BasePart,
	coopReady: BasePart,
	coopStart: BasePart,
	coopBoard: TextLabel,
	redPad: BasePart,
	bluePad: BasePart,
	teamReady: BasePart,
	teamLeave: BasePart,
	teamBalance: BasePart,
	redBoard: TextLabel,
	blueBoard: TextLabel,
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
	makePart("PartyCircle", Vector3.new(0.2, 26, 26), at(0, 0.1, -30) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(150, 120, 70), Enum.Material.Sandstone, area, { collide = false, shape = Enum.PartType.Cylinder })

	-- TEAM BATTLE (x = 36): red/blue pads, posts, roster boards
	portcullis(area, 36)
	local teamLabels = sign(area, "TeamSign", Vector3.new(14, 4, 0.5), facing(36, 15, -HALF_Z + 0.3, SOUTH), {
		{ text = "TEAM BATTLE", color = GOLD, scale = 0.5 },
		{ text = "Red vs Blue · up to 4 v 4", color = WHITE, scale = 0.22 },
		{ text = "Choose a team", color = Color3.fromRGB(220, 220, 220), scale = 0.2 },
	}, RED)
	local redPad = makePart("RedPad", Vector3.new(0.4, 9, 9), at(27, 0.2, -30) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(190, 40, 40), Enum.Material.Neon, area, { shape = Enum.PartType.Cylinder })
	local bluePad = makePart("BluePad", Vector3.new(0.4, 9, 9), at(45, 0.2, -30) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(40, 90, 210), Enum.Material.Neon, area, { shape = Enum.PartType.Cylinder })
	local redBoard = sign(area, "RedRoster", Vector3.new(9, 7, 0.4), facing(23, 6, -HALF_Z + 0.6, SOUTH), {
		{ text = "RED GLADIATORS", color = Color3.fromRGB(255, 120, 120), scale = 0.2 },
		{ text = "-", color = WHITE, scale = 0.75 },
	}, Color3.fromRGB(70, 20, 20))
	local blueBoard = sign(area, "BlueRoster", Vector3.new(9, 7, 0.4), facing(50, 6, -HALF_Z + 0.6, SOUTH), {
		{ text = "BLUE GLADIATORS", color = Color3.fromRGB(140, 180, 255), scale = 0.2 },
		{ text = "-", color = WHITE, scale = 0.75 },
	}, Color3.fromRGB(20, 30, 70))
	local teamReady = post(area, "TeamReadyPost", 36, -32, "READY / UNREADY", Color3.fromRGB(140, 255, 140))
	local teamLeave = post(area, "TeamLeavePost", 31, -24, "LEAVE TEAM", Color3.fromRGB(220, 220, 220))
	local teamBalance = post(area, "TeamBalancePost", 41, -24, "AUTO BALANCE", Color3.fromRGB(255, 220, 120))

	banner(area, facing(-18, 13, -HALF_Z, SOUTH))
	banner(area, facing(18, 13, -HALF_Z, SOUTH))
	area.Parent = folder
	return {
		soloGate = soloGate,
		soloLabel = soloLabels[3],
		coopJoin = coopJoin,
		coopReady = coopReady,
		coopStart = coopStart,
		coopBoard = coopLabels[3],
		redPad = redPad,
		bluePad = bluePad,
		teamReady = teamReady,
		teamLeave = teamLeave,
		teamBalance = teamBalance,
		redBoard = redBoard[2],
		blueBoard = blueBoard[2],
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
		{ text = "Test attacks, specials and combos", color = WHITE, scale = 0.3 },
	}, RED)
	local slots = { facing(center.X - 5, 0.2, center.Z + 2, NORTH), facing(center.X + 5, 0.2, center.Z + 2, NORTH) }
	yard.Parent = folder
	return slots, CFrame.new(center + Vector3.new(0, 6, 0)), Vector3.new(26, 16, 22)
end

local function buildTribuneDoor(folder: Folder): BasePart
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
		{ text = "TRIBUNES", color = GOLD, scale = 0.62 },
		{ text = "Watch the fights · hold F", color = WHITE, scale = 0.3 },
	}, RED)
	-- Stone stairs climbing along the wall toward the stands
	for i = 1, 12 do
		makePart("WallStair", Vector3.new(3, i, 1.2), at(HALF_X - 1.6, i / 2, z + 6 + i * 1.2), SANDSTONE, Enum.Material.Limestone, door)
	end
	torch(door, facing(HALF_X, 9, z - 7.5, WEST))
	door.Parent = folder
	return leaf
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
	local weaponSlots, shieldSlots = buildShopWalls(folder)
	local modes = buildModeArea(folder)
	local archiveSlots, archivePlaques = buildArchive(folder)
	local trainingSlots, trainingCFrame, trainingSize = buildTraining(folder)
	local tribuneDoor = buildTribuneDoor(folder)
	buildPrisonAndStorage(folder)
	buildLighting(folder)

	folder.Parent = Workspace
	return {
		folder = folder,
		spawnCFrame = spawnCFrame,
		weaponSlots = weaponSlots,
		shieldSlots = shieldSlots,
		soloGate = modes.soloGate,
		soloLabel = modes.soloLabel,
		coopJoin = modes.coopJoin,
		coopReady = modes.coopReady,
		coopStart = modes.coopStart,
		coopBoard = modes.coopBoard,
		redPad = modes.redPad,
		bluePad = modes.bluePad,
		teamReady = modes.teamReady,
		teamLeave = modes.teamLeave,
		teamBalance = modes.teamBalance,
		redBoard = modes.redBoard,
		blueBoard = modes.blueBoard,
		teamStatus = modes.teamStatus,
		tribuneDoor = tribuneDoor,
		archiveSlots = archiveSlots,
		archivePlaques = archivePlaques,
		trainingSlots = trainingSlots,
		trainingCFrame = trainingCFrame,
		trainingSize = trainingSize,
		floorY = FLOOR_Y,
	}
end

-- Lobby players far outside the complex (e.g. fell through) are sent back to the spawn.
function LobbyService.isInside(position: Vector3): boolean
	return position.X >= -HALF_X - 2
		and position.X <= ANNEX_X + 4
		and position.Z >= -HALF_Z - 26
		and position.Z <= HALF_Z + 4
		and position.Y >= FLOOR_Y - 10
		and position.Y <= FLOOR_Y + HEIGHT + 5
end

return LobbyService
