--!strict
-- Builds the underground Colosseum lobby: a vaulted stone hall with prison cells, torches,
-- benches, crates, barrels and hay, a welcome board, the equipment wall (pedestal slots for
-- EquipmentShopService), the barred ARENA gate with a tunnel and stairs behind it, the TRIBUNE
-- door, and a dark side corridor. Everything is anchored Parts and built-in materials.
-- The lobby is enclosed and far below the arena floor, so zombies can never reach it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local STONE = Color3.fromRGB(118, 104, 90)
local STONE_DARK = Color3.fromRGB(86, 76, 66)
local STONE_LIGHT = Color3.fromRGB(156, 140, 118)
local FLOOR = Color3.fromRGB(108, 98, 86)
local WOOD = Color3.fromRGB(116, 78, 46)
local DARK_WOOD = Color3.fromRGB(78, 52, 32)
local IRON = Color3.fromRGB(64, 64, 68)
local BRONZE = Color3.fromRGB(176, 125, 60)
local HAY = Color3.fromRGB(212, 180, 92)
local RED = Color3.fromRGB(128, 22, 28)
local GOLD = Color3.fromRGB(240, 196, 80)
local FLAME = Color3.fromRGB(255, 150, 60)

local FLOOR_Y = -80 -- top of the lobby floor
local HALF_X, HALF_Z = 40, 30
local HEIGHT = 20

export type LobbyLayout = {
	folder: Folder,
	spawnCFrame: CFrame,
	arenaGate: BasePart, -- hosts the ENTER ARENA prompt
	arenaGateLabel: TextLabel, -- status text above the gate
	tribuneDoor: BasePart, -- hosts the TRIBUNE prompt
	weaponSlots: { CFrame }, -- pedestal bases on the floor, LookVector pointing into the hall
	shieldSlots: { CFrame },
	floorY: number,
}

local LobbyService = {}

type PartOptions = { collide: boolean?, shape: Enum.PartType?, transparency: number? }

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

local DECOR: PartOptions = { collide = false }

local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, FLOOR_Y + y, z)
end

local function segment(parent: Instance, name: string, a: Vector3, b: Vector3, width: number, thickness: number, color: Color3, material: Enum.Material)
	makePart(name, Vector3.new(width, thickness, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), color, material, parent, DECOR)
end

-- A sign with text on its front face (front = -Z of the given frame).
local function sign(parent: Instance, name: string, size: Vector3, cframe: CFrame, lines: { { text: string, color: Color3, scale: number } }, background: Color3): TextLabel
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
	local first: TextLabel? = nil
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
		first = first or label
	end
	return first :: TextLabel
end

local function torch(parent: Instance, cframe: CFrame)
	-- cframe: on the wall surface, LookVector pointing into the room
	makePart("TorchBracket", Vector3.new(0.4, 0.4, 1.2), cframe * CFrame.new(0, 0, -0.5) * CFrame.Angles(math.rad(30), 0, 0), IRON, Enum.Material.Metal, parent, DECOR)
	local flame = makePart("TorchFlame", Vector3.one * 0.7, cframe * CFrame.new(0, 0.6, -0.95), FLAME, Enum.Material.Neon, parent, { collide = false, shape = Enum.PartType.Ball })
	local light = Instance.new("PointLight")
	light.Color = FLAME
	light.Range = 18
	light.Brightness = 1.4
	light.Shadows = false
	light.Parent = flame
	local fire = Instance.new("Fire")
	fire.Size = 2
	fire.Heat = 4
	fire.Color = FLAME
	fire.SecondaryColor = Color3.fromRGB(255, 220, 120)
	fire.Parent = flame
end

local function buildHall(folder: Folder)
	local hall = Instance.new("Model")
	hall.Name = "Hall"
	makePart("Floor", Vector3.new(HALF_X * 2 + 4, 2, HALF_Z * 2 + 4), at(0, -1, 0), FLOOR, Enum.Material.Cobblestone, hall)
	makePart("Ceiling", Vector3.new(HALF_X * 2 + 4, 2, HALF_Z * 2 + 4), at(0, HEIGHT + 1, 0), STONE_DARK, Enum.Material.Slate, hall)

	-- West (shop) and east (tribune door) walls are solid; north has the arena gate opening,
	-- south has the dark corridor opening.
	makePart("WestWall", Vector3.new(2, HEIGHT, HALF_Z * 2 + 4), at(-HALF_X - 1, HEIGHT / 2, 0), STONE, Enum.Material.Cobblestone, hall)
	makePart("EastWall", Vector3.new(2, HEIGHT, HALF_Z * 2 + 4), at(HALF_X + 1, HEIGHT / 2, 0), STONE, Enum.Material.Cobblestone, hall)
	for _, side in { -1, 1 } do
		makePart("NorthWall", Vector3.new(HALF_X - 5, HEIGHT, 2), at(side * (HALF_X + 5) / 2, HEIGHT / 2, -HALF_Z - 1), STONE, Enum.Material.Cobblestone, hall)
		makePart("SouthWall", Vector3.new(HALF_X - 4, HEIGHT, 2), at(side * (HALF_X + 4) / 2, HEIGHT / 2, HALF_Z + 1), STONE, Enum.Material.Cobblestone, hall)
	end
	makePart("NorthWallTop", Vector3.new(10, HEIGHT - 12, 2), at(0, 12 + (HEIGHT - 12) / 2, -HALF_Z - 1), STONE, Enum.Material.Cobblestone, hall)
	makePart("SouthWallTop", Vector3.new(8, HEIGHT - 10, 2), at(0, 10 + (HEIGHT - 10) / 2, HALF_Z + 1), STONE, Enum.Material.Cobblestone, hall)

	-- Pillars and vaulted ribs
	for _, x in { -24, -8, 8, 24 } do
		for _, z in { -12, 12 } do
			makePart("Pillar", Vector3.new(3, HEIGHT, 3), at(x, HEIGHT / 2, z), STONE_LIGHT, Enum.Material.Limestone, hall)
		end
		local y0, y1 = FLOOR_Y + HEIGHT - 6, FLOOR_Y + HEIGHT - 0.6
		segment(hall, "Rib", Vector3.new(x, y0, -HALF_Z), Vector3.new(x, y1, -12), 1.6, 1.2, STONE_LIGHT, Enum.Material.Limestone)
		segment(hall, "Rib", Vector3.new(x, y1, -12), Vector3.new(x, y1, 12), 1.6, 1.2, STONE_LIGHT, Enum.Material.Limestone)
		segment(hall, "Rib", Vector3.new(x, y1, 12), Vector3.new(x, y0, HALF_Z), 1.6, 1.2, STONE_LIGHT, Enum.Material.Limestone)
	end
	hall.Parent = folder
end

local function buildCells(folder: Folder)
	local cells = Instance.new("Model")
	cells.Name = "PrisonCells"
	local front, back = HALF_Z - 8, HALF_Z
	for _, cx in { -30, -18, 18, 30 } do
		for _, side in { -1, 1 } do
			makePart("Divider", Vector3.new(0.8, 12, back - front), at(cx + side * 5.5, 6, (front + back) / 2), STONE, Enum.Material.Cobblestone, cells)
		end
		for x = -4, 4 do
			makePart("Bar", Vector3.new(0.25, 12, 0.25), at(cx + x, 6, front), IRON, Enum.Material.Metal, cells)
		end
		makePart("BarBeam", Vector3.new(11, 0.6, 0.6), at(cx, 11.5, front), IRON, Enum.Material.Metal, cells)
		makePart("BarBand", Vector3.new(10, 0.3, 0.35), at(cx, 4, front), IRON, Enum.Material.Metal, cells)
		makePart("CellBench", Vector3.new(5, 0.5, 1.6), at(cx - 1.5, 1.4, back - 1.2), WOOD, Enum.Material.Wood, cells)
		makePart("CellBenchBase", Vector3.new(4.4, 1.2, 1.2), at(cx - 1.5, 0.6, back - 1.2), STONE_DARK, Enum.Material.Cobblestone, cells)
		makePart("Hay", Vector3.new(3, 0.8, 2.6), at(cx + 2.5, 0.4, back - 2.5), HAY, Enum.Material.Grass, cells)
		-- Wall ring with a short chain
		local ring = makePart("WallRing", Vector3.new(0.2, 1, 1), at(cx, 7, back - 0.1) * CFrame.Angles(0, math.rad(90), 0), IRON, Enum.Material.Metal, cells, { collide = false, shape = Enum.PartType.Cylinder })
		for link = 1, 3 do
			makePart("ChainLink", Vector3.new(0.15, 0.5, 0.3), ring.CFrame * CFrame.new(0, -0.3 - link * 0.45, 0) * CFrame.Angles(0, if link % 2 == 0 then math.rad(90) else 0, 0), IRON, Enum.Material.Metal, cells, DECOR)
		end
	end
	cells.Parent = folder
end

local function buildProps(folder: Folder)
	local props = Instance.new("Model")
	props.Name = "Props"
	-- Benches near the spawn
	for _, x in { -12, 12 } do
		makePart("Bench", Vector3.new(6, 0.5, 1.6), at(x, 1.3, 16), WOOD, Enum.Material.Wood, props)
		for _, dx in { -2.3, 2.3 } do
			makePart("BenchLeg", Vector3.new(0.5, 1.1, 1.4), at(x + dx, 0.55, 16), DARK_WOOD, Enum.Material.Wood, props)
		end
	end
	-- Crates, barrels and hay in the north-east corner
	for i, offset in { Vector3.new(0, 0, 0), Vector3.new(3.2, 0, 0.4), Vector3.new(1.6, 3, 0.2) } do
		makePart("Crate", Vector3.one * 3, at(32 + offset.X, 1.5 + offset.Y, -24 + offset.Z) * CFrame.Angles(0, math.rad(i * 7), 0), WOOD, Enum.Material.WoodPlanks, props)
	end
	for _, position in { Vector3.new(36, 0, -16), Vector3.new(33.5, 0, -14.5), Vector3.new(-12, 0, -26) } do
		makePart("Barrel", Vector3.new(3, 2.4, 2.4), at(position.X, 1.5, position.Z) * CFrame.Angles(0, 0, math.rad(90)), DARK_WOOD, Enum.Material.Wood, props, { shape = Enum.PartType.Cylinder })
		makePart("BarrelHoop", Vector3.new(0.25, 2.5, 2.5), at(position.X, 2.3, position.Z) * CFrame.Angles(0, 0, math.rad(90)), IRON, Enum.Material.Metal, props, { collide = false, shape = Enum.PartType.Cylinder })
	end
	makePart("HayBale", Vector3.new(4, 2, 2.5), at(26, 1, -26), HAY, Enum.Material.Grass, props)
	makePart("HayBale", Vector3.new(4, 2, 2.5), at(26.5, 3, -26.2), HAY, Enum.Material.Grass, props)
	-- A decorative spear rack by the tribune door
	makePart("RackBase", Vector3.new(1.2, 0.6, 6), at(39, 0.3, -12), DARK_WOOD, Enum.Material.Wood, props)
	makePart("RackBar", Vector3.new(0.6, 0.4, 6), at(39.4, 6, -12), DARK_WOOD, Enum.Material.Wood, props, DECOR)
	for i = -2, 2 do
		makePart("Spear", Vector3.new(0.18, 7, 0.18), at(39.2, 3.6, -12 + i * 1.2), WOOD, Enum.Material.Wood, props, DECOR)
		makePart("SpearTip", Vector3.new(0.3, 0.7, 0.1), at(39.2, 7.4, -12 + i * 1.2), BRONZE, Enum.Material.Metal, props, DECOR)
	end
	props.Parent = folder
end

-- North: barred ARENA gate, with a lit tunnel and stairs leading up behind the bars.
local function buildArenaGate(folder: Folder): (BasePart, TextLabel)
	local gate = Instance.new("Model")
	gate.Name = "ArenaGate"
	local z0 = -HALF_Z - 2
	-- Tunnel
	makePart("TunnelFloor", Vector3.new(12, 2, 24), at(0, -1, z0 - 12), FLOOR, Enum.Material.Cobblestone, gate)
	for _, side in { -1, 1 } do
		makePart("TunnelWall", Vector3.new(2, HEIGHT, 24), at(side * 6, HEIGHT / 2, z0 - 12), STONE_DARK, Enum.Material.Cobblestone, gate)
	end
	makePart("TunnelEnd", Vector3.new(14, HEIGHT, 2), at(0, HEIGHT / 2, z0 - 24), STONE_DARK, Enum.Material.Cobblestone, gate)
	makePart("TunnelCeiling", Vector3.new(14, 2, 24), at(0, HEIGHT + 1, z0 - 12), STONE_DARK, Enum.Material.Slate, gate)
	for i = 1, 16 do
		makePart("Stair", Vector3.new(9, 0.75 * i, 1), at(0, 0.75 * i / 2, z0 - 3 - i), STONE_LIGHT, Enum.Material.Limestone, gate)
	end
	torch(gate, at(5, 9, z0 - 8) * CFrame.Angles(0, math.rad(90), 0))
	torch(gate, at(-5, 13, z0 - 16) * CFrame.Angles(0, math.rad(-90), 0))

	-- Portcullis across the opening
	local zGate = -HALF_Z - 0.3
	for x = -4.5, 4.51, 1 do
		makePart("GateBar", Vector3.new(0.35, 12, 0.35), at(x, 6, zGate), IRON, Enum.Material.Metal, gate)
	end
	for _, y in { 2.5, 6, 9.5 } do
		makePart("GateBand", Vector3.new(10, 0.35, 0.45), at(0, y, zGate), IRON, Enum.Material.Metal, gate)
	end
	for _, side in { -1, 1 } do
		makePart("GatePillar", Vector3.new(1.6, 13, 1.6), at(side * 5.8, 6.5, -HALF_Z + 0.2), STONE_LIGHT, Enum.Material.Limestone, gate)
	end
	local promptHost = makePart("ArenaGatePrompt", Vector3.new(10, 6, 0.5), at(0, 3, zGate + 0.8), IRON, Enum.Material.Metal, gate, { collide = false, transparency = 1 })

	local label = sign(gate, "ArenaSign", Vector3.new(14, 3.2, 0.5), at(0, 14.5, -HALF_Z + 0.3) * CFrame.Angles(0, math.rad(180), 0), {
		{ text = "ENTER ARENA", color = GOLD, scale = 0.62 },
		{ text = "Hold E at the gate", color = Color3.new(1, 1, 1), scale = 0.3 },
	}, RED)
	torch(gate, at(-7.5, 10, -HALF_Z + 0.1) * CFrame.Angles(0, math.rad(180), 0))
	torch(gate, at(7.5, 10, -HALF_Z + 0.1) * CFrame.Angles(0, math.rad(180), 0))
	gate.Parent = folder
	return promptHost, label
end

-- East: wooden TRIBUNE door with a stone frame and stairs climbing along the wall.
local function buildTribuneDoor(folder: Folder): BasePart
	local door = Instance.new("Model")
	door.Name = "TribuneDoor"
	local x = HALF_X - 0.4
	local leaf = makePart("Door", Vector3.new(0.6, 10, 8), at(x, 5, 0), DARK_WOOD, Enum.Material.WoodPlanks, door)
	for _, y in { 2, 5, 8 } do
		makePart("DoorBand", Vector3.new(0.7, 0.4, 8.1), at(x - 0.05, y, 0), IRON, Enum.Material.Metal, door)
	end
	makePart("DoorRing", Vector3.new(0.2, 0.9, 0.9), at(x - 0.4, 5, -1.6), IRON, Enum.Material.Metal, door, { collide = false, shape = Enum.PartType.Cylinder })
	for _, side in { -1, 1 } do
		makePart("DoorPillar", Vector3.new(1.4, 11, 1.4), at(x - 0.3, 5.5, side * 4.8), STONE_LIGHT, Enum.Material.Limestone, door)
	end
	makePart("DoorLintel", Vector3.new(1.6, 1.4, 11), at(x - 0.3, 11.7, 0), STONE_LIGHT, Enum.Material.Limestone, door)
	sign(door, "TribuneSign", Vector3.new(10, 3, 0.5), at(x - 0.5, 14.2, 0) * CFrame.Angles(0, math.rad(90), 0), {
		{ text = "TRIBUNE", color = GOLD, scale = 0.62 },
		{ text = "Watch the fights", color = Color3.new(1, 1, 1), scale = 0.3 },
	}, RED)
	torch(door, at(HALF_X, 9, 7.5) * CFrame.Angles(0, math.rad(90), 0))
	torch(door, at(HALF_X, 9, -7.5) * CFrame.Angles(0, math.rad(90), 0))
	-- Stone stairs climbing the wall toward the stands (decorative, ends at the vault)
	for i = 1, 12 do
		makePart("WallStair", Vector3.new(3, i, 1.2), at(HALF_X - 1.6, i / 2, 8 + i * 1.2), STONE_LIGHT, Enum.Material.Limestone, door)
	end
	door.Parent = folder
	return leaf
end

-- South: a dark corridor behind the spawn ending in a barred gate.
local function buildCorridor(folder: Folder)
	local corridor = Instance.new("Model")
	corridor.Name = "DarkCorridor"
	local z0 = HALF_Z + 2
	makePart("CorridorFloor", Vector3.new(8, 2, 14), at(0, -1, z0 + 7), FLOOR, Enum.Material.Cobblestone, corridor)
	for _, side in { -1, 1 } do
		makePart("CorridorWall", Vector3.new(1, 10, 14), at(side * 4.5, 5, z0 + 7), STONE_DARK, Enum.Material.Cobblestone, corridor)
	end
	makePart("CorridorCeiling", Vector3.new(10, 1, 14), at(0, 10.5, z0 + 7), STONE_DARK, Enum.Material.Slate, corridor)
	makePart("CorridorEnd", Vector3.new(10, 10, 1), at(0, 5, z0 + 14.5), STONE_DARK, Enum.Material.Cobblestone, corridor)
	for x = -3, 3 do
		makePart("Bar", Vector3.new(0.25, 10, 0.25), at(x, 5, z0 + 12), IRON, Enum.Material.Metal, corridor)
	end
	local glow = makePart("DimLight", Vector3.one * 0.5, at(0, 9.5, z0 + 13.5), FLAME, Enum.Material.Neon, corridor, DECOR)
	local light = Instance.new("PointLight")
	light.Color = FLAME
	light.Range = 10
	light.Brightness = 0.5
	light.Parent = glow
	corridor.Parent = folder
end

-- West: the equipment wall with weapon and shield sections; returns pedestal slots.
local function buildShopWall(folder: Folder): ({ CFrame }, { CFrame })
	local shop = Instance.new("Model")
	shop.Name = "EquipmentWall"
	local x = -HALF_X + 0.3
	makePart("Backboard", Vector3.new(0.4, 10, 44), at(x, 6, 0), DARK_WOOD, Enum.Material.WoodPlanks, shop)
	for _, y in { 3, 9 } do
		makePart("RackRail", Vector3.new(0.5, 0.3, 44), at(x + 0.3, y, 0), BRONZE, Enum.Material.Metal, shop, DECOR)
	end
	sign(shop, "WeaponsSign", Vector3.new(14, 2.6, 0.4), at(x + 0.5, 12.6, -11.5) * CFrame.Angles(0, math.rad(-90), 0), {
		{ text = "WEAPONS", color = GOLD, scale = 0.9 },
	}, RED)
	sign(shop, "ShieldsSign", Vector3.new(14, 2.6, 0.4), at(x + 0.5, 12.6, 11.5) * CFrame.Angles(0, math.rad(-90), 0), {
		{ text = "SHIELDS", color = GOLD, scale = 0.9 },
	}, RED)
	torch(shop, at(-HALF_X, 10, 0) * CFrame.Angles(0, math.rad(-90), 0))
	torch(shop, at(-HALF_X, 10, -24) * CFrame.Angles(0, math.rad(-90), 0))
	torch(shop, at(-HALF_X, 10, 24) * CFrame.Angles(0, math.rad(-90), 0))
	shop.Parent = folder

	local weaponSlots, shieldSlots = {}, {}
	for i, z in { -19, -14, -9, -4 } do
		local position = Vector3.new(-HALF_X + 4, FLOOR_Y, z)
		weaponSlots[i] = CFrame.lookAt(position, position + Vector3.xAxis)
	end
	for i, z in { 4, 9, 14, 19 } do
		local position = Vector3.new(-HALF_X + 4, FLOOR_Y, z)
		shieldSlots[i] = CFrame.lookAt(position, position + Vector3.xAxis)
	end
	return weaponSlots, shieldSlots
end

local function buildWelcome(folder: Folder): CFrame
	-- Hanging board between spawn and arena gate, readable from the spawn
	sign(folder, "WelcomeBoard", Vector3.new(24, 8, 0.6), at(0, 13, 4) * CFrame.Angles(0, math.rad(180), 0), {
		{ text = "OTTI COLOSSEUM", color = GOLD, scale = 0.34 },
		{ text = "Choose your weapon and shield", color = Color3.new(1, 1, 1), scale = 0.17 },
		{ text = "Enter the arena when ready", color = Color3.new(1, 1, 1), scale = 0.17 },
		{ text = "Defeat all six rounds", color = Color3.fromRGB(255, 210, 120), scale = 0.17 },
	}, DARK_WOOD)
	for _, x in { -10, 10 } do
		makePart("BoardChain", Vector3.new(0.2, HEIGHT - 17, 0.2), at(x, 17 + (HEIGHT - 17) / 2, 4), IRON, Enum.Material.Metal, folder, DECOR)
	end

	local spawnPosition = Vector3.new(0, FLOOR_Y + 0.5, 20)
	local spawnCFrame = CFrame.lookAt(spawnPosition, spawnPosition - Vector3.zAxis)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.CFrame = spawnCFrame
	spawn.Color = STONE_LIGHT
	spawn.Material = Enum.Material.Limestone
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = folder
	return spawnCFrame
end

function LobbyService.build(): LobbyLayout
	local existing = Workspace:FindFirstChild(Config.LobbyFolderName)
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = Config.LobbyFolderName

	buildHall(folder)
	buildCells(folder)
	buildProps(folder)
	buildCorridor(folder)
	local arenaGate, arenaGateLabel = buildArenaGate(folder)
	local tribuneDoor = buildTribuneDoor(folder)
	local weaponSlots, shieldSlots = buildShopWall(folder)
	local spawnCFrame = buildWelcome(folder)
	for _, position in { Vector3.new(-20, 9, HALF_Z), Vector3.new(20, 9, HALF_Z), Vector3.new(-24, 9, -HALF_Z), Vector3.new(24, 9, -HALF_Z) } do
		local facing = if position.Z > 0 then 0 else 180
		torch(folder, at(position.X, position.Y, position.Z) * CFrame.Angles(0, math.rad(facing), 0))
	end

	folder.Parent = Workspace
	return {
		folder = folder,
		spawnCFrame = spawnCFrame,
		arenaGate = arenaGate,
		arenaGateLabel = arenaGateLabel,
		tribuneDoor = tribuneDoor,
		weaponSlots = weaponSlots,
		shieldSlots = shieldSlots,
		floorY = FLOOR_Y,
	}
end

-- Lobby players far outside the hall (e.g. fell through) are sent back to the spawn.
function LobbyService.isInside(position: Vector3): boolean
	return math.abs(position.X) <= HALF_X + 2
		and position.Z >= -HALF_Z - 30
		and position.Z <= HALF_Z + 20
		and position.Y >= FLOOR_Y - 10
		and position.Y <= FLOOR_Y + HEIGHT + 5
end

return LobbyService
