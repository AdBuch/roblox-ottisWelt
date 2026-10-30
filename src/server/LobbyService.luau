--!strict
-- Lobby contracts and the existing group mosaic builder. Architecture builds the world.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LobbyPadDefinitions = require(ReplicatedStorage.Shared.LobbyPadDefinitions)
local LobbyMosaics = require(script.Parent.LobbyMosaics)
type PadDefinition = LobbyPadDefinitions.PadDefinition
local STONE_DARK = Color3.fromRGB(66, 58, 50)
local SANDSTONE = Color3.fromRGB(210, 186, 143)
local BRONZE = Color3.fromRGB(176, 125, 60)
local RED = Color3.fromRGB(128, 22, 28)
local GOLD = Color3.fromRGB(240, 196, 80)
local WHITE = Color3.new(1, 1, 1)
local SOON = Color3.fromRGB(190, 190, 200)
local DARK_WOOD = Color3.fromRGB(78, 52, 32)
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
	bossBoard: BasePart,
	bossBoards: { BasePart },
	arenaTriggers: { BasePart }, -- invisible volumes at every arena gate: walking in starts a solo run
	introTargets: { Vector3 }, -- where each Hub intro stage points (index = stage + 1)
	matchActions: { { part: BasePart, mode: string } },
	modeBoards: { BasePart },
	arenaGate: BasePart, -- the trigger at Otti's gate (the start hall's way into the arena)
	tribuneDoors: { BasePart }, -- WATCH LIVE entrances at the top of the side stairs
	liveBoards: { TextLabel }, -- live battle count on every hall's LIVE BATTLES sign
	liveCFrame: CFrame, -- where returning spectators arrive
	archiveSlots: { CFrame },
	archivePlaques: { CFrame },
	trainingSlots: { CFrame },
	trainingCFrame: CFrame,
	trainingSize: Vector3,
	floorY: number,
}

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

local Architecture = require(script.Parent.LobbyArchitecture)
local LobbyService = {}
function LobbyService.build(): LobbyLayout
    return Architecture.build(buildPad)
end
function LobbyService.isInside(position: Vector3): boolean
    return Architecture.isInside(position)
end
function LobbyService.isInArmory(position: Vector3): boolean
    return Architecture.isInArmory(position)
end
return LobbyService
