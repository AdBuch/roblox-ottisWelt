--!strict
-- Generates the circular training arena from plain Parts.
-- Calling build() again replaces the previous Workspace.GeneratedArena, so restarts never duplicate it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local PREFIX = "[OttiArena][Server]"

local SAND = Color3.fromRGB(226, 202, 145)
local STONE = Color3.fromRGB(168, 162, 150)
local STONE_LIGHT = Color3.fromRGB(196, 190, 176)
local MARBLE = Color3.fromRGB(236, 231, 220)
local WOOD = Color3.fromRGB(110, 72, 40)
local DARK_WOOD = Color3.fromRGB(78, 50, 30)
local BRONZE = Color3.fromRGB(176, 125, 60)
local GOLD = Color3.fromRGB(255, 205, 70)

local RADIUS = Config.ArenaRadius
local FLOOR_TOP = 1
local WALL_HEIGHT = 28
local WALL_THICKNESS = 6
local WALL_SEGMENTS = 40
local COLUMN_HEIGHT = 22
local GATE_WIDTH = 11
local GATE_HEIGHT = 21

local Arena = {}

-- Positions other modules use to place things inside the arena.
Arena.Layout = {
	Center = Vector3.new(0, FLOOR_TOP, 0),
	Radius = RADIUS,
	FloorTop = FLOOR_TOP,
	WallHeight = WALL_HEIGHT,
	SpawnPosition = Vector3.new(0, FLOOR_TOP + 0.5, RADIUS - 8),
	ZombiePosition = Vector3.new(0, FLOOR_TOP, -4),
	ShellPositions = {} :: { Vector3 },
}

for i, degrees in { 30, 150, 270 } do
	local angle = math.rad(degrees)
	Arena.Layout.ShellPositions[i] = Vector3.new(math.cos(angle) * 28, FLOOR_TOP + 2, math.sin(angle) * 28)
end

local function makePart(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Faces the point at the same height toward the arena center.
local function facingCenter(position: Vector3): CFrame
	return CFrame.lookAt(position, Vector3.new(0, position.Y, 0))
end

local function buildFloor(folder: Folder)
	local diameter = (RADIUS + WALL_THICKNESS) * 2
	-- Cylinders run along X, so roll 90° to make a flat disc.
	local floor = makePart(
		"Floor",
		Vector3.new(FLOOR_TOP, diameter, diameter),
		CFrame.new(0, FLOOR_TOP / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		SAND,
		Enum.Material.Sand,
		folder
	)
	floor.Shape = Enum.PartType.Cylinder
end

-- A ring of straight segments. Each segment is sized for the OUTER radius, so neighbours
-- overlap on the inside and meet on the outside: no gaps to squeeze through.
local function buildWall(folder: Folder)
	local wall = Instance.new("Model")
	wall.Name = "Wall"
	local centerRadius = RADIUS + WALL_THICKNESS / 2
	local outerRadius = RADIUS + WALL_THICKNESS
	local segmentLength = 2 * outerRadius * math.tan(math.pi / WALL_SEGMENTS) + 0.4

	for i = 0, WALL_SEGMENTS - 1 do
		local angle = i / WALL_SEGMENTS * 2 * math.pi
		local x, z = math.cos(angle), math.sin(angle)
		local position = Vector3.new(x * centerRadius, FLOOR_TOP + WALL_HEIGHT / 2, z * centerRadius)
		makePart("Segment", Vector3.new(segmentLength, WALL_HEIGHT, WALL_THICKNESS), facingCenter(position), STONE, Enum.Material.Slate, wall)

		-- Decorative cornice on top
		local capPosition = Vector3.new(x * centerRadius, FLOOR_TOP + WALL_HEIGHT + 0.5, z * centerRadius)
		makePart("Cap", Vector3.new(segmentLength + 0.2, 1, WALL_THICKNESS + 1), facingCenter(capPosition), STONE_LIGHT, Enum.Material.Limestone, wall)
	end
	wall.Parent = folder
end

local function buildColumns(folder: Folder)
	for _, degrees in { 45, 135, 225, 315 } do
		local angle = math.rad(degrees)
		local x, z = math.cos(angle) * (RADIUS - 4), math.sin(angle) * (RADIUS - 4)
		local column = Instance.new("Model")
		column.Name = "Column"

		makePart("Base", Vector3.new(4, 1, 4), CFrame.new(x, FLOOR_TOP + 0.5, z), STONE, Enum.Material.Slate, column)
		local shaft = makePart(
			"Shaft",
			Vector3.new(COLUMN_HEIGHT, 3, 3),
			CFrame.new(x, FLOOR_TOP + 1 + COLUMN_HEIGHT / 2, z) * CFrame.Angles(0, 0, math.rad(90)),
			MARBLE,
			Enum.Material.Marble,
			column
		)
		shaft.Shape = Enum.PartType.Cylinder
		makePart("Capital", Vector3.new(4, 1, 4), CFrame.new(x, FLOOR_TOP + 1.5 + COLUMN_HEIGHT, z), STONE, Enum.Material.Slate, column)

		column.Parent = folder
	end
end

-- The entrance: an arched frame with closed wooden gate doors. The wall continues
-- solidly behind it, so the gate is purely visual and can't be passed.
local function buildGate(folder: Folder)
	local gate = Instance.new("Model")
	gate.Name = "Gate"
	local z = RADIUS - 0.5
	local pillarX = GATE_WIDTH / 2 + 1.5

	for _, side in { -1, 1 } do
		makePart("Pillar", Vector3.new(3, GATE_HEIGHT + 2, 3), CFrame.new(side * pillarX, FLOOR_TOP + (GATE_HEIGHT + 2) / 2, z - 1), STONE_LIGHT, Enum.Material.Limestone, gate)
	end
	makePart("Lintel", Vector3.new(GATE_WIDTH + 6, 3, 3.4), CFrame.new(0, FLOOR_TOP + GATE_HEIGHT + 3.5, z - 1), STONE_LIGHT, Enum.Material.Limestone, gate)

	makePart("Doors", Vector3.new(GATE_WIDTH, GATE_HEIGHT, 1), CFrame.new(0, FLOOR_TOP + GATE_HEIGHT / 2, z), DARK_WOOD, Enum.Material.WoodPlanks, gate)
	makePart("Seam", Vector3.new(0.25, GATE_HEIGHT, 0.2), CFrame.new(0, FLOOR_TOP + GATE_HEIGHT / 2, z - 0.6), Color3.new(0.1, 0.07, 0.05), Enum.Material.Wood, gate)
	for _, x in { -4.5, -1.5, 1.5, 4.5 } do
		makePart("Bar", Vector3.new(0.5, GATE_HEIGHT, 0.4), CFrame.new(x, FLOOR_TOP + GATE_HEIGHT / 2, z - 0.7), BRONZE, Enum.Material.Metal, gate)
	end
	for _, y in { 5, 15 } do
		makePart("Band", Vector3.new(GATE_WIDTH, 0.7, 0.4), CFrame.new(0, FLOOR_TOP + y, z - 0.75), BRONZE, Enum.Material.Metal, gate)
	end
	for _, x in { -1.2, 1.2 } do
		local ring = makePart("Handle", Vector3.new(0.3, 1.2, 1.2), CFrame.new(x, FLOOR_TOP + 9, z - 1) * CFrame.Angles(0, math.rad(90), 0), BRONZE, Enum.Material.Metal, gate)
		ring.Shape = Enum.PartType.Cylinder
	end

	gate.Parent = folder
end

local function buildSpawn(folder: Folder)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "ArenaSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.CFrame = facingCenter(Arena.Layout.SpawnPosition)
	spawn.Color = STONE
	spawn.Material = Enum.Material.Slate
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = folder
end

local function buildSign(folder: Folder)
	local z = -(RADIUS - 1.5)
	local sign = Instance.new("Model")
	sign.Name = "Sign"

	for _, x in { -8, 8 } do
		makePart("Post", Vector3.new(1, 7, 1), CFrame.new(x, FLOOR_TOP + 3.5, z), WOOD, Enum.Material.Wood, sign)
	end
	local board = makePart("Board", Vector3.new(18, 4, 1), facingCenter(Vector3.new(0, FLOOR_TOP + 9, z)), WOOD, Enum.Material.Wood, sign)

	-- Front face (-Z) points at the arena center because of facingCenter().
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = board

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "OTTI ARENA"
	label.Font = Enum.Font.Garamond
	label.TextScaled = true
	label.TextColor3 = GOLD
	label.Parent = gui

	sign.Parent = folder
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

	local folder = Instance.new("Folder")
	folder.Name = Config.ArenaFolderName
	buildFloor(folder)
	buildWall(folder)
	buildGate(folder)
	buildColumns(folder)
	buildSpawn(folder)
	buildSign(folder)
	folder.Parent = Workspace

	return folder
end

-- True if a position is inside the playable area (with a little tolerance).
function Arena.isInside(position: Vector3, margin: number?): boolean
	local flat = Vector3.new(position.X, 0, position.Z)
	return flat.Magnitude <= RADIUS + (margin or 0) and position.Y >= FLOOR_TOP - 10
end

function Arena.getSpawnCFrame(): CFrame
	return facingCenter(Arena.Layout.SpawnPosition + Vector3.new(0, 3.5, 0))
end

return Arena
