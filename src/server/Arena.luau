--!strict
-- Generates a Colosseum-style arena from anchored Parts: an oval sand floor (~140 x 110),
-- a podium wall with barred gates and red banners, stepped spectator seating, and a tall
-- outer wall with three layers of arches. An invisible barrier on the podium keeps
-- everyone on the arena floor. Decorations inside the floor area are non-collidable,
-- so they never block movement or pathfinding.
-- Calling build() again replaces the previous Workspace.GeneratedArena (no duplicates).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

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
local A, B = 70, 55 -- semi-axes of the playable oval (140 x 110 studs)
local FLOOR_TOP = 1
local PODIUM_HEIGHT = 10
local PODIUM_THICKNESS = 4
local BARRIER_TOP = FLOOR_TOP + 70
local SEAT_TIERS = 4
local SEAT_DEPTH = 6
local SEAT_RISE = 4.5
local OUTER_OFFSET = PODIUM_THICKNESS + SEAT_TIERS * SEAT_DEPTH
local OUTER_THICKNESS = 5
local OUTER_TOP = FLOOR_TOP + 58
local ARCADE_ROWS = { { bottom = 31, height = 6 }, { bottom = 40, height = 6 }, { bottom = 49, height = 5 } }

local ZOMBIE_GATE_ANGLES = { 0, 45, 135, 180, 225, 270, 315 }
local PLAYER_GATE_ANGLE = 90

local Arena = {}

Arena.Layout = {
	Center = Vector3.new(0, FLOOR_TOP, 0),
	SemiAxisX = A,
	SemiAxisZ = B,
	FloorTop = FLOOR_TOP,
	BarrierTop = BARRIER_TOP,
	OuterOffset = OUTER_OFFSET,
	PodiumThickness = PODIUM_THICKNESS,
	PodiumHeight = PODIUM_HEIGHT,
	SeatTiers = SEAT_TIERS,
	SeatDepth = SEAT_DEPTH,
	SeatRise = SEAT_RISE,
	-- The main gladiator gate (north, under the OTTI ARENA sign): Otti enters here
	MainGateAngle = math.rad(270),
	-- Where the fighter enters the arena floor (south, facing the center)
	StartPosition = Vector3.new(0, FLOOR_TOP + 3.5, B - 10),
	-- Lower tribune walkway (top of the first seating tier) and its return door
	TribuneWalkwayY = FLOOR_TOP + PODIUM_HEIGHT + SEAT_RISE,
	ReturnDoor = nil :: BasePart?,
	ZombieSpawns = {} :: { CFrame },
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

-- A closed ring of wall segments around the oval. Segments overlap generously so the
-- outer corners never leave gaps.
local function ring(parent: Instance, name: string, segments: number, innerOffset: number, thickness: number, bottomY: number, topY: number, color: Color3, material: Enum.Material, options: PartOptions?)
	local model = Instance.new("Model")
	model.Name = name
	for i = 0, segments - 1 do
		local frame, chord = segmentFrame(i, segments, innerOffset + thickness / 2, (bottomY + topY) / 2)
		makePart("Segment", Vector3.new(chord + thickness * 0.2 + 0.6, topY - bottomY, thickness), frame, color, material, model, options)
	end
	model.Parent = parent
end

local function buildFloor(folder: Folder)
	local width = (A + OUTER_OFFSET + OUTER_THICKNESS + 4) * 2
	local depth = (B + OUTER_OFFSET + OUTER_THICKNESS + 4) * 2
	makePart("Floor", Vector3.new(width, 1, depth), CFrame.new(0, FLOOR_TOP - 0.5, 0), SAND, Enum.Material.Sand, folder)
end

local function buildWalls(folder: Folder)
	-- Podium wall around the floor, plus an invisible barrier up to BARRIER_TOP on top of it
	ring(folder, "PodiumWall", 64, 0, PODIUM_THICKNESS, FLOOR_TOP, FLOOR_TOP + PODIUM_HEIGHT, TRAVERTINE, Enum.Material.Limestone)
	ring(folder, "InvisibleBarrier", 64, 0, PODIUM_THICKNESS, FLOOR_TOP + PODIUM_HEIGHT, BARRIER_TOP, TRAVERTINE, Enum.Material.SmoothPlastic, { transparency = 1 })

	-- Spectator seating rising behind the podium
	local seating = Instance.new("Model")
	seating.Name = "Seating"
	for tier = 0, SEAT_TIERS - 1 do
		local top = FLOOR_TOP + PODIUM_HEIGHT + (tier + 1) * SEAT_RISE
		local color = if tier % 2 == 0 then SANDSTONE else TRAVERTINE
		ring(seating, "Tier" .. (tier + 1), 48, PODIUM_THICKNESS + tier * SEAT_DEPTH, SEAT_DEPTH, FLOOR_TOP, top, color, Enum.Material.Sandstone)
	end
	seating.Parent = folder

	ring(folder, "OuterWall", 36, OUTER_OFFSET, OUTER_THICKNESS, FLOOR_TOP, OUTER_TOP, SANDSTONE, Enum.Material.Sandstone)
end

-- Three rows of arches with engaged columns on the inner face of the outer wall.
local function buildArcades(folder: Folder)
	local arcades = Instance.new("Model")
	arcades.Name = "Arcades"
	local segments = 36
	for i = 0, segments - 1 do
		for _, row in ARCADE_ROWS do
			local bottom = FLOOR_TOP + row.bottom
			local frame, chord = segmentFrame(i, segments, OUTER_OFFSET, bottom + row.height / 2)
			local face = frame * CFrame.new(0, 0, -0.2)
			local width = chord * 0.5

			makePart("Opening", Vector3.new(width, row.height, 0.4), face, OPENING, Enum.Material.Slate, arcades, DECOR)
			makePart("ArchTop", Vector3.new(0.4, width, width), face * CFrame.new(0, row.height / 2, 0) * CFrame.Angles(0, math.rad(90), 0), OPENING, Enum.Material.Slate, arcades, { shape = Enum.PartType.Cylinder, collide = false })
			makePart("Column", Vector3.new(row.height + 2.5, 1.3, 1.3), face * CFrame.new(-chord / 2, 0.6, 0) * CFrame.Angles(0, 0, math.rad(90)), TRAVERTINE, Enum.Material.Limestone, arcades, { shape = Enum.PartType.Cylinder, collide = false })
			makePart("Cornice", Vector3.new(chord + 1, 0.8, 1.4), face * CFrame.new(0, -row.height / 2 - 1, 0), STONE_DARK, Enum.Material.Limestone, arcades, DECOR)
		end
	end
	arcades.Parent = folder
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
	buildGate(gates, math.rad(PLAYER_GATE_ANGLE), "PlayerGate")
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
-- lower walkway = top of seating tier 1, middle walkway = top of tier 3, two staircases between
-- them, a railing along the front, two viewing platforms and the basement entrance/return door.
local function buildTribune(folder: Folder)
	local tribune = Instance.new("Model")
	tribune.Name = "Tribune"
	local lowerY = FLOOR_TOP + PODIUM_HEIGHT + SEAT_RISE
	local middleY = lowerY + 2 * SEAT_RISE

	-- Railing along the front edge of the lower walkway
	ring(tribune, "Railing", 64, PODIUM_THICKNESS, 0.8, lowerY, lowerY + 2.8, TRAVERTINE, Enum.Material.Limestone)

	-- Two staircases from the lower walkway (over tier 2) up to the middle walkway
	local steps = 14
	local run = (SEAT_DEPTH * 2 - 0.8) / steps
	local rise = (middleY - lowerY) / steps
	for _, degrees in { 30, 210 } do
		local theta = math.rad(degrees)
		local stair = Instance.new("Model")
		stair.Name = "Staircase"
		for k = 1, steps do
			local height = rise * k
			local offset = PODIUM_THICKNESS + 0.8 + run * (k - 0.5)
			makePart("Step", Vector3.new(5, height, run + 0.05), frameAt(theta, offset, lowerY + height / 2), if k % 2 == 0 then TRAVERTINE else SANDSTONE, Enum.Material.Limestone, stair)
		end
		for _, side in { -1, 1 } do
			local a = frameAt(theta, PODIUM_THICKNESS + 0.8, lowerY + 3) * CFrame.new(side * 2.7, 0, 0)
			local b = frameAt(theta, PODIUM_THICKNESS + 0.8 + run * steps, middleY + 3) * CFrame.new(side * 2.7, 0, 0)
			local length = (b.Position - a.Position).Magnitude
			makePart("Handrail", Vector3.new(0.3, 0.3, length), CFrame.lookAt((a.Position + b.Position) / 2, b.Position), BRONZE, Enum.Material.Metal, stair, DECOR)
		end
		stair.Parent = tribune
	end

	-- Viewing platforms on the middle walkway, north and south
	for _, degrees in { 90, 270 } do
		local theta = math.rad(degrees)
		makePart("ViewingPlatform", Vector3.new(14, 1, 5), frameAt(theta, PODIUM_THICKNESS + 2 * SEAT_DEPTH + 2.5, middleY + 0.5), TRAVERTINE, Enum.Material.Marble, tribune)
		makePart("PlatformRail", Vector3.new(14, 2.5, 0.6), frameAt(theta, PODIUM_THICKNESS + 2 * SEAT_DEPTH + 0.3, middleY + 2.25), SANDSTONE, Enum.Material.Limestone, tribune)
		for _, side in { -1, 1 } do
			makePart("Post", Vector3.new(0.6, 5, 0.6), frameAt(theta, PODIUM_THICKNESS + 2 * SEAT_DEPTH + 0.3, middleY + 3.5) * CFrame.new(side * 6.7, 0, 0), BRONZE, Enum.Material.Metal, tribune)
			makePart("Pennant", Vector3.new(1.6, 2.4, 0.1), frameAt(theta, PODIUM_THICKNESS + 2 * SEAT_DEPTH + 0.3, middleY + 4.6) * CFrame.new(side * 6.7 + side * 0.9, 0, 0), BANNER_RED, Enum.Material.Fabric, tribune, DECOR)
		end
	end

	-- Basement entrance / RETURN TO LOBBY: a barred door in the riser of tier 2, east side
	local doorBase = frameAt(0, PODIUM_THICKNESS + SEAT_DEPTH, lowerY)
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
	label.Text = "RETURN TO LOBBY"
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
	buildArcades(folder)
	buildGates(folder)
	buildBanners(folder)
	buildTribune(folder)
	buildSign(folder)

	local zombies = Instance.new("Folder")
	zombies.Name = Config.ZombiesFolderName
	zombies.Parent = folder

	folder.Parent = Workspace
	return folder
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

-- Where spectators arrive on the lower tribune walkway (east, in front of the return door).
function Arena.getTribuneCFrame(): CFrame
	return frameAt(0, PODIUM_THICKNESS + 3.5, Arena.Layout.TribuneWalkwayY + 3)
end

-- True if a position is somewhere on the spectator stands (between barrier and outer wall).
function Arena.isInTribune(position: Vector3): boolean
	return not Arena.isInside(position, PODIUM_THICKNESS - 0.5)
		and Arena.isInside(position, OUTER_OFFSET)
		and position.Y >= Arena.Layout.TribuneWalkwayY - 2
		and position.Y <= OUTER_TOP + 10
end

return Arena
