--!strict
-- Three statue halls and three equipment shops on a continuous Colosseum concourse.
-- Every hall connects to the real upper seating and the lower training / party floor.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Config = require(ReplicatedStorage.Shared.Config)
local LobbyPadDefinitions = require(ReplicatedStorage.Shared.LobbyPadDefinitions)
local LobbyMosaics = require(script.Parent.LobbyMosaics)
local LobbyStatue = require(script.Parent.LobbyStatue)
local ShopBattleMosaics = require(script.Parent.ShopBattleMosaics)
type PadDefinition = LobbyPadDefinitions.PadDefinition
local STONE = Color3.fromRGB(118, 104, 90)
local STONE_DARK = Color3.fromRGB(66, 58, 50)
local SANDSTONE = Color3.fromRGB(210, 186, 143)
local IRON = Color3.fromRGB(64, 64, 68)
local BRONZE = Color3.fromRGB(176, 125, 60)
local RED = Color3.fromRGB(128, 22, 28)
local GOLD = Color3.fromRGB(240, 196, 80)
local WHITE = Color3.new(1, 1, 1)
local SOON = Color3.fromRGB(190, 190, 200)
local DARK_WOOD = Color3.fromRGB(78, 52, 32)
local FLOOR_Y = -20
local LOWER_Y = -44
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
	modeBoards: { BasePart },
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

local LobbyService = {}
type Volume = { cf: CFrame, size: Vector3 }
local volumes: { Volume } = {}
local shops: { Volume } = {}
local function contains(v: Volume, point: Vector3): boolean
    local p = v.cf:PointToObjectSpace(point)
    return math.abs(p.X) <= v.size.X / 2 and math.abs(p.Y) <= v.size.Y / 2 and math.abs(p.Z) <= v.size.Z / 2
end
local function volume(cf: CFrame, size: Vector3, shop: boolean?)
    local v = { cf = cf, size = size }
    table.insert(volumes, v)
    if shop then table.insert(shops, v) end
end
-- Local +Z points radially outward. Halls alternate with shops at 60 degree intervals.
local function radial(degrees: number, radius: number, y: number): CFrame
    return CFrame.Angles(0, math.rad(degrees), 0) * CFrame.new(0, y, radius)
end
local function slab(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, decor: boolean?): Part
    return makePart(name, size, cf, color, Enum.Material.Limestone, parent, if decor then DECOR else nil)
end
local function board(parent: Instance, name: string, cf: CFrame, title: string, subtitle: string): (BasePart, TextLabel)
    local labels = sign(parent, name, Vector3.new(19, 5, 0.4), cf, {
        { text = title, color = GOLD, scale = 0.52 },
        { text = subtitle, color = WHITE, scale = 0.36 },
    }, RED)
    return labels[1]:FindFirstAncestorWhichIsA("BasePart") :: BasePart, labels[2]
end
local function lamp(parent: Instance, cf: CFrame)
    local host = slab(parent, "BronzeLamp", cf, Vector3.new(1, 1.4, 1), GOLD, true)
    host.Material = Enum.Material.Neon
    local light = Instance.new("PointLight")
    light.Color = Color3.fromRGB(255, 209, 145)
    light.Brightness = 2
    light.Range = 32
    light.Parent = host
end
local function stairs(parent: Instance, base: CFrame, rise: number, run: number, count: number)
    -- base is the LOWER end; steps advance in local +Z. All rises are <= 1 stud.
    for i = 1, count do
        local h = rise * i / count
        slab(parent, "Stair", base * CFrame.new(0, h / 2, (i - 0.5) * run / count), Vector3.new(9, h, run / count + 0.1), SANDSTONE)
    end
    for _, x in { -5, 5 } do
        local a = (base * CFrame.new(x, 3, 0)).Position
        local b = (base * CFrame.new(x, rise + 3, run)).Position
        slab(parent, "StairHandrail", CFrame.lookAt((a + b) / 2, b), Vector3.new(0.5, 0.5, (b - a).Magnitude), BRONZE)
    end
    volume(base * CFrame.new(0, rise / 2 + 3, run / 2), Vector3.new(12, rise + 10, run + 4))
end
local function spawn(parent: Instance, name: string, cf: CFrame): SpawnLocation
    local part = Instance.new("SpawnLocation")
    part.Name = name
    part.Size = Vector3.new(5, 1, 5)
    part.CFrame = cf * CFrame.new(0, -0.5, 0)
    part.Anchored = true
    part.Neutral = true
    part.Duration = 0
    part.Transparency = 1
    part.Parent = parent
    return part
end

function LobbyService.build(): LobbyLayout
    local existing = Workspace:FindFirstChild(Config.LobbyFolderName)
    if existing then existing:Destroy() end
    table.clear(volumes)
    table.clear(shops)
    local folder = Instance.new("Folder")
    folder.Name = Config.LobbyFolderName
    local pads: { PadLayout } = {}
    local doors: { BasePart } = {}
    local menus: { BasePart } = {}

    -- 96 overlapping tangent segments form a closed, walkable ring without a centre disk.
    for i = 0, 95 do
        local angle = i * 360 / 96
        local cf = radial(angle, 110, FLOOR_Y)
        local nearDownStair = math.abs((angle - 9 + 60) % 120 - 60) < 6
        slab(folder, "ConcourseFloor", cf * CFrame.new(0, -1, if nearDownStair then -2 else 0), Vector3.new(9.4, 2, if nearDownStair then 56 else 60), STONE)
        volume(cf * CFrame.new(0, 10, 0), Vector3.new(10, 26, 61))
        slab(folder, "InnerFoundation", radial(angle, 79, -10), Vector3.new(6, 20, 2), SANDSTONE)
        -- No outer wall or ceiling across the six hall stairways.
        local nearestHall = (angle + 60) % 120 - 60
        if math.abs(nearestHall) > 20 then
            slab(folder, "OuterWall", radial(angle, 141, -10), Vector3.new(10, 20, 2), SANDSTONE)
            slab(folder, "ShopVault", radial(angle, 110, 1), Vector3.new(10, 2, 62), STONE_DARK)
        end
        for tier = 0, 3 do
            -- Open the top of each stair shaft so a character can reach the landing.
            if tier == 0 and math.abs((angle + 17 + 60) % 120 - 60) < 7 then continue end
            local radius = 79 + tier * 17
            local y = 16 + tier * 5
            local seat = radial(angle, radius, y)
            slab(folder, "TribuneTier", seat * CFrame.new(0, -1, 0), Vector3.new(radius * math.pi / 48 + 0.4, 2, 17.2), SANDSTONE)
            volume(seat * CFrame.new(0, 4, 0), Vector3.new(radius * math.pi / 48 + 1, 12, 18))
        end
        slab(folder, "UpperParapet", radial(angle, 139, 33), Vector3.new(10, 4, 2), STONE)
        if i % 4 == 0 then
            slab(folder, "ArcadeColumn", radial(angle, 143, 12), Vector3.new(3, 64, 3), SANDSTONE)
            slab(folder, "ArcadeLintel", radial(angle, 143, 45), Vector3.new(39, 3, 4), SANDSTONE)
            lamp(folder, radial(angle, 135, -8))
        end
    end
    -- Arena vista in the Hub; live matches still run in their reserved Arena place.
    makePart("ArenaSand", Vector3.new(2, 150, 150), CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(226, 202, 145), Enum.Material.Sand, folder, { shape = Enum.PartType.Cylinder })
    volume(CFrame.new(0, 7, 0), Vector3.new(150, 18, 150))
    -- Basement floor beneath all halls; stairs emerge outside the upper ring at r=172.
    makePart("HypogeumFloor", Vector3.new(2, 380, 380), CFrame.new(0, LOWER_Y - 1, 0) * CFrame.Angles(0, 0, math.pi / 2), STONE, Enum.Material.Cobblestone, folder, { shape = Enum.PartType.Cylinder })
    volume(CFrame.new(0, LOWER_Y + 9, 0), Vector3.new(378, 20, 378))
    for i = 0, 23 do
        local cf = radial(i * 15, 189, LOWER_Y + 10)
        slab(folder, "BasementWall", cf, Vector3.new(51, 20, 2), STONE_DARK)
        if i % 2 == 0 then lamp(folder, radial(i * 15, 160, LOWER_Y + 12)) end
    end

    local halls = { { id = "Otti", pad = "ZombieCoop", angle = 0 }, { id = "Schili", pad = "TeamSchili", angle = 120 }, { id = "Kroko", pad = "TeamKrokero", angle = 240 } }
    for _, hall in halls do
        local cf = radial(hall.angle, 110, FLOOR_Y)
        local def = LobbyPadDefinitions.get(hall.pad)
        if def then
            table.insert(pads, buildPad(folder, def, cf * CFrame.new(0, 0, -7), Vector2.new(24, 16), cf * CFrame.new(0, 10, 5), -1))
        end
        slab(folder, "StatuePedestal", cf * CFrame.new(0, 1.5, 17), Vector3.new(11, 3, 10), BRONZE)
        LobbyStatue.build(folder, cf * CFrame.new(0, 3, 17), 1.3, hall.id)
        local menu = board(folder, hall.id .. "Modes", cf * CFrame.new(-12, 5, 17), "ALL GAME MODES", "Solo · Co-op · Teams · Boss · Watch")
        table.insert(menus, menu)
        -- Up: from radius 136 toward radius 76, finishing exactly on tier zero.
        stairs(folder, radial(hall.angle, 136, FLOOR_Y) * CFrame.new(-23, 0, 0) * CFrame.Angles(0, math.pi, 0), 36, 60, 36)
        local landing = radial(hall.angle, 72.5, 16) * CFrame.new(-23, 0, 0)
        slab(folder, "UpperStairLanding", landing * CFrame.new(0, -1, 0), Vector3.new(28, 2, 7), SANDSTONE)
        volume(landing * CFrame.new(0, 4, 0), Vector3.new(29, 12, 8))
        -- Down: lower end at radius 172, climbing inward to the lobby at radius 136.
        stairs(folder, radial(hall.angle, 172, LOWER_Y) * CFrame.new(23, 0, 0) * CFrame.Angles(0, math.pi, 0), 24, 36, 24)
        slab(folder, "LowerStairLanding", radial(hall.angle, 175, LOWER_Y - 1) * CFrame.new(23, 0, 0), Vector3.new(12, 2, 8), SANDSTONE)
        local door = board(folder, "TribuneWatchBoard", radial(hall.angle, 72, 21) * CFrame.new(-23, 0, 0), "WATCH LIVE", "Choose a live match · F")
        table.insert(doors, door)
        board(folder, "UpSign", cf * CFrame.new(-23, 7, 19), "UP · TRIBUNES", "Arena view & live battles")
        board(folder, "DownSign", cf * CFrame.new(23, 7, 22), "DOWN · HYPOGEUM", "Training cages & group meeting point")
        lamp(folder, cf * CFrame.new(0, 17, 0))
    end

    -- Shop alcoves alternate with the statue halls. Their inner side opens onto the ring.
    local function shop(angle: number, name: string): CFrame
        local cf = radial(angle, 118, FLOOR_Y)
        slab(folder, name .. "Rug", cf * CFrame.new(0, 0.04, 0), Vector3.new(46, 0.08, 36), RED, true)
        for _, x in { -25, 25 } do
            slab(folder, name .. "Partition", cf * CFrame.new(x, 9, 4), Vector3.new(1, 18, 34), SANDSTONE)
        end
        board(folder, name .. "Sign", cf * CFrame.new(0, 16, 19), name:upper(), "Buy & equip · approach a display")
        volume(cf * CFrame.new(0, 9, 0), Vector3.new(50, 22, 40), true)
        return cf
    end
    local shields = shop(60, "Shields")
    local armor = shop(180, "Armor")
    local weapons = shop(300, "Weapons")
    ShopBattleMosaics.build(folder, shields, "Shields", "Otti", "Schili")
    ShopBattleMosaics.build(folder, armor, "Armor", "Schili", "Krokero")
    ShopBattleMosaics.build(folder, weapons, "Weapons", "Krokero", "Otti")
    local function line(cf: CFrame, x: number, z: number, length: number): DisplayLine
        return { cframe = cf * CFrame.new(x, 0, z), length = length }
    end
    local armory: ArmoryLayout = {
        blades = line(weapons, 0, 13, 40),
        heavy = line(weapons * CFrame.Angles(0, math.pi / 2, 0), -2, 21, 24),
        ranged = line(weapons * CFrame.Angles(0, -math.pi / 2, 0), 2, 21, 24),
        shields = { Light = line(shields, -14, 13, 12), Balanced = line(shields, 0, 13, 12), Heavy = line(shields, 14, 13, 12) },
        armor = line(armor, 0, 10, 38), floorY = FLOOR_Y,
    }
    local arrival = radial(0, 91, FLOOR_Y) * CFrame.new(12, 0, 0) * CFrame.Angles(0, math.pi, 0)
    local arrivalSpawn = spawn(folder, "LobbyArrivalSpawn", arrival)
    local respawnSpawn = spawn(folder, "LobbyRespawn", radial(0, 94, FLOOR_Y) * CFrame.new(-12, 0, 0))
    local solo = board(folder, "ArenaGate", radial(0, 84, FLOOR_Y + 5) * CFrame.Angles(0, math.pi, 0), "SOLO ARENA", "Start the zombie rounds · F")
    local boss = board(folder, "BossSelection", radial(0, 132, FLOOR_Y + 7) * CFrame.new(12, 0, 0), "BOSS FIGHT · TEST", "Choose Otti · Schili · Krokero")
    local rome = board(folder, "RomeGate", CFrame.new(0, LOWER_Y + 8, 183), "PORTA ROMA", "Road to Rome · coming soon")
    slab(folder, "RomeGateDoors", CFrame.new(0, LOWER_Y + 7, 185), Vector3.new(18, 14, 2), DARK_WOOD)
    local _, live = board(folder, "LiveBoard", radial(0, 116, FLOOR_Y + 7) * CFrame.new(13, 0, 0), "LIVE IN THE COLOSSEUM", "No live battles")
    local meeting = board(folder, "GroupMeetingPoint", CFrame.new(0, LOWER_Y + 8, 20), "GROUP MEETING POINT", "Create party · invite · ready · all modes")
    table.insert(menus, meeting)
    slab(folder, "MeetingMosaic", CFrame.new(0, LOWER_Y + 0.05, 0), Vector3.new(34, 0.1, 34), BRONZE, true)
    for _, x in { -22, 22 } do
        slab(folder, "MeetingBench", CFrame.new(x, LOWER_Y + 1, 0), Vector3.new(3, 2, 24), DARK_WOOD)
        lamp(folder, CFrame.new(x, LOWER_Y + 12, 15))
    end
    -- Six real zombie rigs for hit / block practice, behind an open sparring threshold.
    local trainingSlots: { CFrame } = {}
    for i = 1, 6 do
        local x = (i - 3.5) * 16
        local cf = CFrame.new(x, LOWER_Y, -60) * CFrame.Angles(0, math.pi, 0)
        table.insert(trainingSlots, cf)
        slab(folder, "TrainingCageBack", cf * CFrame.new(0, 6, 6), Vector3.new(14, 12, 0.7), IRON)
        for _, side in { -1, 1 } do
            for z = -5, 5, 2 do
                slab(folder, "TrainingCageBar", cf * CFrame.new(side * 7, 6, z), Vector3.new(0.35, 12, 0.35), IRON)
            end
        end
        board(folder, "CageSign", cf * CFrame.new(0, 13, 5), "TRAINING " .. i, "Enter to practise · no rewards")
        lamp(folder, cf * CFrame.new(0, 14, 0))
    end
    slab(folder, "ComboTrainingBoard", CFrame.new(58, LOWER_Y + 6, -58), Vector3.new(9, 7, 0.4), DARK_WOOD, true)
    Lighting.Ambient = Color3.fromRGB(96, 82, 68)
    Lighting.OutdoorAmbient = Color3.fromRGB(145, 132, 108)
    Lighting.Brightness = 2
    Lighting.ClockTime = 14
    folder.Parent = Workspace
    return {
        folder = folder, spawnCFrame = respawnSpawn.CFrame, arrivalSpawn = arrivalSpawn, respawnSpawn = respawnSpawn,
        armory = armory, pads = pads, arenaGate = solo, bossBoard = boss, modeBoards = menus, romeGate = rome,
        tribuneDoors = doors, liveBoard = live, liveCFrame = radial(0, 81, 17),
        archiveSlots = {}, archivePlaques = {}, trainingSlots = trainingSlots,
        trainingCFrame = CFrame.new(0, LOWER_Y + 7, -60), trainingSize = Vector3.new(116, 18, 30), floorY = FLOOR_Y,
    }
end
function LobbyService.isInArmory(position: Vector3): boolean
    for _, v in shops do if contains(v, position) then return true end end
    return false
end
function LobbyService.isInside(position: Vector3): boolean
    for _, v in volumes do if contains(v, position) then return true end end
    return false
end
return LobbyService
