--!strict
-- The Hub's three hero lobbies, built INTO the Colosseum: each one lives in the open ground hall
-- under the stands, between the arena side (podium) and the facade, around its hero gate. The
-- Colosseum itself (stands, galleries, facade, piers, stair houses, gates, sand, collision) is
-- exactly the shared Arena builder's; this file only adds lobby fittings on the hall floor and
-- the Hub anchors. Everything is placed in ring coordinates (ellipse angle + outward offset,
-- ColosseumLayout.frame), so it follows the oval and stays between the pier rays:
--
--   piers stand on the rays 10 30 70 110 150 170 190 250 270 290 350 (deg), at the tier fronts
--   stair houses at 45 135 225 315 fill offsets 57..74; vomitoria at 3 121 177 301 lie at y 22
--   headroom under the stands: offset 13..22 -> 15, 22..31 -> 21, 31..40 -> 27, 40..48.5 -> 33
--
--   OTTI (gate 90, main lobby) bay 70..110: arrival on the gate axis, a few seconds' walk from the
--     gate; Otti's monument and mosaic beside the way; the team, mode, boss and live boards on
--     two notice walls near the gate.
--   Every hall: the cages of its chapter's fighters stand under the lowest tier, their backs
--     against the podium wall (zombies with Otti, legionaries with Kroko, ninjas with Schili),
--     and one shop bay: blades, balanced shields and armor with Otti (112..131), heavy weapons
--     and heavy shields with Kroko (224..238), ranged weapons and light shields with Schili
--     (302..316).
--   KROKO (gate 210) bay 190..250 and SCHILI (gate 330) bay 290..350: monument, shop bay, boards.
--   THE ARENA: the hero gates stand open in the Hub. On the sand: six straw dummies in a ring,
--     and in front of every gate the solo start mosaic, the hall's co-op group and (Kroko,
--     Schili) the team's gathering mosaic. The way to Rome leaves through the west arch (180).
--
-- In the ring frames local +X points towards DEcreasing angle, local +Z outward, -Z into the arena.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local Layout = require(ReplicatedStorage.Shared.ColosseumLayout)
local Config = require(ReplicatedStorage.Shared.Config)
local PadDefinitions = require(ReplicatedStorage.Shared.LobbyPadDefinitions)
local Statue = require(script.Parent.LobbyStatue)
local Mosaics = require(script.Parent.LobbyMosaics)
local Battles = require(script.Parent.ShopBattleMosaics)
local Arena = require(script.Parent.Arena)

local Architecture = {}
local FLOOR = Layout.FloorTop
local STONE = Color3.fromRGB(116, 103, 87)
local SANDSTONE = Color3.fromRGB(207, 182, 141)
local DARK = Color3.fromRGB(68, 56, 45)
local GOLD = Color3.fromRGB(224, 176, 70)
local IRON = Color3.fromRGB(62, 64, 61)
local WOOD = Color3.fromRGB(100, 65, 38)
local WHITE = Color3.fromRGB(245, 231, 202)
local YARD = Color3.fromRGB(196, 170, 120)
local RUG = Color3.fromRGB(150, 54, 40)
-- The hero monuments: twice the size the heroes fight at (a rig is built at fight size)
local STATUE_SCALE = 2

-- The Hub's anchors (ring angle in degrees, outward offset in studs)
Architecture.Anchors = table.freeze({
	ArrivalAngle = 90, ArrivalOffset = 52, -- Otti's lobby: direct joins, facing the gate
	RespawnAngle = 87.5, RespawnOffset = 58, -- later characters and Arena returns
	CityExitAngle = 180, -- the facade's west arch: the way to Rome
})

type Volume = { cf: CFrame, size: Vector3 }
local volumes: { Volume } = {}
local shops: { Volume } = {}
local function inside(v: Volume, p: Vector3): boolean
	local o = v.cf:PointToObjectSpace(p)
	return math.abs(o.X) <= v.size.X / 2 and math.abs(o.Y) <= v.size.Y / 2 and math.abs(o.Z) <= v.size.Z / 2
end
local function zone(cf: CFrame, size: Vector3, shop: boolean?)
	local v = { cf = cf, size = size }
	table.insert(volumes, v)
	if shop then
		table.insert(shops, v)
	end
end

-- Ring frame on the hall floor: angle (deg), outward offset, height above the floor.
local function ring(deg: number, offset: number, y: number?): CFrame
	return Layout.frame(math.rad(deg), offset, FLOOR + (y or 0))
end
-- A frame at `position` whose +Z (the statue's / board's face) looks at `target` (level).
local function facing(position: Vector3, target: Vector3): CFrame
	local flat = Vector3.new(target.X, position.Y, target.Z)
	return CFrame.lookAt(position, position - (flat - position))
end
-- A frame at `position` whose -Z (text side of a sign) looks at `target` (level).
local function toward(position: Vector3, target: Vector3): CFrame
	return CFrame.lookAt(position, Vector3.new(target.X, position.Y, target.Z))
end

-- Intro: decoration built while this is set appears for a player only from that intro stage on
-- (LobbyIntroController hides it locally until then). Colliding parts are never hidden.
local revealStage: number? = nil
local function part(parent: Instance, name: string, cf: CFrame, size: Vector3, color: Color3, decor: boolean?): Part
	local p = Instance.new("Part")
	p.Name, p.Anchored, p.CFrame, p.Size = name, true, cf, size
	p.Color, p.Material = color, Enum.Material.Limestone
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	if decor then
		p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = false, false, false, false
	end
	if decor and revealStage then
		p:SetAttribute("IntroStage", revealStage)
	end
	p.Parent = parent
	return p
end
local function model(parent: Instance, name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end
-- Text faces the board's -Z (Front). `size` resizes the board together with its accent strip.
local function sign(parent: Instance, name: string, cf: CFrame, title: string, subtitle: string, color: Color3?, size: Vector2?): (BasePart, TextLabel)
	local w, h = if size then size.X else 18, if size then size.Y else 4.5
	local host = part(parent, name, cf, Vector3.new(w, h, 0.35), DARK, true)
	host.Material = Enum.Material.Wood
	if color then
		part(parent, "SignAccent", cf * CFrame.new(0, h / 2 - 0.1, -0.2), Vector3.new(w, 0.2, 0.12), color, true)
	end
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 32
	gui.MaxDistance = 110
	gui.Parent = host
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(0.94, 0.5)
	label.Position = UDim2.fromScale(0.03, 0.04)
	label.BackgroundTransparency = 1
	label.TextColor3 = GOLD
	label.Font = Enum.Font.Garamond
	label.TextScaled = true
	label.Text = title
	label.Parent = gui
	local sub = Instance.new("TextLabel")
	sub.Size = UDim2.fromScale(0.94, 0.38)
	sub.Position = UDim2.fromScale(0.03, 0.56)
	sub.BackgroundTransparency = 1
	sub.TextColor3 = WHITE
	sub.Font = Enum.Font.GothamBold
	sub.TextScaled = true
	sub.Text = subtitle
	sub.Parent = gui
	return host, sub
end
local function lamp(parent: Instance, cf: CFrame)
	local p = part(parent, "BrazierFlame", cf, Vector3.new(0.8, 1.2, 0.8), Color3.fromRGB(255, 180, 76), true)
	p.Material = Enum.Material.Neon
	part(parent, "BrazierBowl", cf * CFrame.new(0, -0.75, 0), Vector3.new(1.8, 0.5, 1.8), GOLD, true).Material = Enum.Material.Metal
	part(parent, "BrazierBracket", cf * CFrame.new(0, -1.3, 0), Vector3.new(0.45, 0.8, 0.45), IRON, true).Material = Enum.Material.Metal
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 219, 168)
	light.Range = 24
	light.Brightness = 0.85
	light.Parent = p
end
-- A standing brazier on the floor (decoration; the hall is open around it).
local function brazier(parent: Instance, floor: CFrame)
	part(parent, "BrazierStand", floor * CFrame.new(0, 2.2, 0), Vector3.new(0.5, 4.4, 0.5), IRON, true).Material = Enum.Material.Metal
	part(parent, "BrazierFoot", floor * CFrame.new(0, 0.1, 0), Vector3.new(2, 0.2, 2), IRON, true).Material = Enum.Material.Metal
	lamp(parent, floor * CFrame.new(0, 5.7, 0))
end
local function spawn(parent: Instance, name: string, cf: CFrame): SpawnLocation
	local p = Instance.new("SpawnLocation")
	p.Name = name
	p.Anchored = true
	p.Neutral = true
	p.Duration = 0
	p.Transparency = 1
	p.CanCollide = false -- the hall floor carries the player; the spawn only marks the spot
	p.Size = Vector3.new(6, 1, 6)
	p.CFrame = cf * CFrame.new(0, -0.5, 0)
	p.Parent = parent
	return p
end
local function monument(parent: Instance, cf: CFrame, hero: any)
	part(parent, "MonumentStep", cf * CFrame.new(0, 0.5, 0), Vector3.new(14, 1, 14), SANDSTONE)
	part(parent, "MonumentPedestal", cf * CFrame.new(0, 3, 0), Vector3.new(10, 5, 10), SANDSTONE)
	part(parent, "BronzePedestalCap", cf * CFrame.new(0, 5.7, 0), Vector3.new(11, 0.5, 11), GOLD, true)
	-- the statue looks along the monument frame's +Z, the inscription sits on that face
	Statue.build(parent, cf * CFrame.new(0, 6, 0) * CFrame.Angles(0, math.pi, 0), STATUE_SCALE, hero.id)
	sign(parent, "HeroInscription", cf * CFrame.new(0, 3, 5.2) * CFrame.Angles(0, math.pi, 0), hero.name, hero.motto, hero.color)
end
-- Cloth banners hanging from the underside of the stands (decoration).
local function banner(parent: Instance, cf: CFrame, color: Color3)
	local flag = part(parent, "HeroBanner", cf, Vector3.new(5, 8, 0.15), color, true)
	flag.Material = Enum.Material.Fabric
	part(parent, "BannerGoldHem", cf * CFrame.new(0, -3.8, 0), Vector3.new(5, 0.5, 0.2), GOLD, true)
	part(parent, "BannerRod", cf * CFrame.new(0, 4.1, 0), Vector3.new(6, 0.3, 0.3), GOLD, true).Material = Enum.Material.Metal
end
-- A free-standing notice wall (the only colliding part) for boards: its face looks at `target`.
local function noticeWall(parent: Instance, position: Vector3, target: Vector3, width: number, height: number): CFrame
	local cf = toward(position, target)
	part(parent, "NoticeWall", cf * CFrame.new(0, height / 2, 0.6), Vector3.new(width, height, 1), STONE)
	part(parent, "NoticeWallCap", cf * CFrame.new(0, height + 0.2, 0.6), Vector3.new(width + 0.6, 0.4, 1.4), GOLD, true).Material = Enum.Material.Metal
	return cf
end
-- A sign on a post at `position`, readable from `target`.
local function signpost(parent: Instance, position: Vector3, target: Vector3, title: string, subtitle: string, color: Color3?)
	local cf = toward(position, target)
	part(parent, "SignPost", cf * CFrame.new(0, 4, 0.4), Vector3.new(0.6, 8, 0.6), WOOD, true)
	sign(parent, "Direction", cf * CFrame.new(0, 8.2, 0), title, subtitle, color, Vector2.new(13, 3.2))
end
-- A straight display line between two ring angles at `offset`; LookVector toward `face`
-- (+1 outward, -1 into the arena), its length along the RightVector.
local function chord(fromDeg: number, toDeg: number, offset: number, face: number): { cframe: CFrame, length: number }
	local a = ring(fromDeg, offset).Position
	local b = ring(toDeg, offset).Position
	local mid = (a + b) / 2
	local normal = Layout.normal(math.rad((fromDeg + toDeg) / 2))
	return { cframe = CFrame.lookAt(mid, mid + normal * face), length = (b - a).Magnitude }
end

-- The ring angle `studs` further along the ring from `deg` at `offset` (positive: increasing angle).
local function along(deg: number, offset: number, studs: number): number
	local theta = math.rad(deg)
	local steps = math.max(1, math.ceil(math.abs(studs) / 2))
	for _ = 1, steps do
		local speed = (Layout.point(theta + 1e-3, offset) - Layout.point(theta, offset)).Magnitude / 1e-3
		theta += studs / steps / speed
	end
	return math.deg(theta)
end
-- A frame on the sand: `inset` studs inside the podium wall, -Z towards the arena's middle.
local function sand(deg: number, inset: number, y: number?): CFrame
	return Layout.frame(math.rad(deg), -inset, FLOOR + (y or 0))
end

-- `foes`: the fighters of the hero's campaign chapter, shown in the cages of the hero's hall.
local HEROES = {
	{ id = "Otti", name = "OTTI", angle = 90, color = Color3.fromRGB(140, 38, 37), motto = "COURAGE · FRIENDSHIP · UNITY", emblem = "Otti", foes = { "LegionRemnant", "RottenVelite", "ArenaBrute", "NetFighter", "ArenaChampion", "UndeadSagittarius" } },
	{ id = "Schili", name = "SCHILIBITZLI · SCHILI", angle = 330, color = Color3.fromRGB(52, 111, 112), motto = "WISDOM · ENDURANCE · KINDNESS", emblem = "Schili", foes = { "ZombieNinja", "NunchakuNinja", "NinjaArcher", "TerracottaSamurai" } },
	{ id = "Kroko", name = "KROKERO · KROKO", angle = 210, color = Color3.fromRGB(125, 93, 43), motto = "COURAGE · ACTION · LOYALTY", emblem = "Krokero", foes = { "TestudoLegionary", "MountedPraetorian" } },
}

local function coopDefinition(id: string, emblem: string): any
	local coop = table.clone(assert(PadDefinitions.get("ZombieCoop"), "ZombieCoop pad missing"))
	coop.Id = id
	coop.Title = "JOIN GROUP · ZOMBIES"
	coop.Emblem = emblem
	coop.Subtitle = "Co-op · the group forms on this mosaic"
	coop.Actions = { { Id = "StartCoop", Label = "START GROUP" }, { Id = "COOP_ZOMBIES", Label = "FIND PLAYERS" }, { Id = "Ready", Label = "READY" }, { Id = "LeaveGroup", Label = "LEAVE" } }
	return coop
end
-- The solo start: standing on the mosaic for a moment starts a solo zombie run (LobbyPadService).
local function soloDefinition(hero: any): any
	return {
		Id = hero.id .. "Solo", Wing = "Single", Kind = "Solo", Title = "SOLO · ZOMBIE ARENA",
		Subtitle = "Stay on the mosaic · your fight starts", Enabled = true, Mode = "SOLO_ZOMBIES",
		Emblem = hero.emblem, Color = hero.color,
	}
end

-- A walk-on mosaic on the sand. Group mosaics lie along the podium wall, their board in front of
-- the wall and the start pedestals towards the arena's middle; the solo mosaic lies on the gate
-- axis, its board beyond it, facing the gate.
local function sandPad(buildPad: any, parent: Instance, def: any, deg: number, inset: number, size: Vector2, solo: boolean): any
	local center = sand(deg, inset) * (if solo then CFrame.identity else CFrame.Angles(0, math.pi, 0))
	local board = center * CFrame.new(0, 7, -(size.Y / 2 + (if solo then 4.5 else 2.3))) * CFrame.Angles(0, math.pi, 0)
	for _, x in { -7.7, 7.7 } do
		part(parent, "PadBoardPost", board * CFrame.new(x, -1.75, 0.45), Vector3.new(0.5, 10.5, 0.5), WOOD, true)
	end
	return buildPad(parent, def, center, size, board, if solo then -1 else 1)
end

-- Cages under the stands. A cage stands under tier 1, its back against the podium wall and its
-- bars towards the hall; a stable (for the mounted praetorian) reaches on under tier 2, where
-- there is room for horse and rider. Cages keep clear of the gate way and of the pier rays.
local PIER_RAYS = { 10, 30, 70, 110, 150, 170, 190, 250, 270, 290, 350 }
local CAGE_BACK = Layout.PodiumThickness + 0.5
local CAGE_FRONT, CAGE_HEIGHT = 12.6, 7.6 -- under tier 1: 8 studs of headroom
local STABLE_FRONT, STABLE_HEIGHT = 21.6, 11 -- under tier 2: 14 studs of headroom
local function cage(parent: Instance, deg: number, width: number, stable: boolean): (CFrame, CFrame)
	local m = model(parent, "ArchiveCage")
	local half = width / 2
	local low = if stable then 13.4 else CAGE_FRONT
	local function at(x: number, y: number, offset: number): CFrame
		return ring(deg, offset, y) * CFrame.new(x, 0, 0)
	end
	local function box(name: string, x: number, y0: number, y1: number, o0: number, o1: number, w: number, decor: boolean?)
		part(m, name, at(x, (y0 + y1) / 2, (o0 + o1) / 2), Vector3.new(w, y1 - y0, o1 - o0), IRON, decor).Material = Enum.Material.Metal
	end
	part(m, "CageBack", at(0, CAGE_HEIGHT / 2, CAGE_BACK - 0.15), Vector3.new(width, CAGE_HEIGHT, 0.3), DARK, true)
	for _, s in { -1, 1 } do
		box("CageSide", s * (half - 0.3), 0, CAGE_HEIGHT, CAGE_BACK, low, 0.6)
	end
	box("CageRoof", 0, CAGE_HEIGHT, CAGE_HEIGHT + 0.3, CAGE_BACK, low, width)
	local front, height = CAGE_FRONT, CAGE_HEIGHT
	if stable then
		front, height = STABLE_FRONT, STABLE_HEIGHT
		for _, s in { -1, 1 } do
			box("CageSide", s * (half - 0.3), 0, height, low, front, 0.6)
		end
		box("CageRoof", 0, height, height + 0.3, low, front, width)
	end
	for bx = -(half - 0.6), half - 0.59, 1.2 do
		box("PrisonBars", bx, 0, height, front - 0.15, front + 0.15, 0.3)
	end
	-- the fighter looks out at the hall; its plaque hangs on the terrace's front above the bars
	local slot = ring(deg, if stable then 16.6 else (CAGE_BACK + CAGE_FRONT) / 2) * CFrame.Angles(0, math.pi, 0)
	local plaque = ring(deg, front + (if stable then 0.65 else 0.75), if stable then 14 else 11) * CFrame.Angles(0, math.pi, 0)
	return slot, plaque
end
-- The cages of one hall, alternately on both sides of its gate. Fills the three lists.
local function cages(parent: Instance, hero: any, slots: { CFrame }, plaques: { CFrame }, ids: { string })
	local taken = { [-1] = 11, [1] = 11 } -- the gate way stays 22 studs wide
	for i, id in hero.foes do
		local side = if i % 2 == 1 then -1 else 1
		local stable = id == "MountedPraetorian"
		local width = if stable then 11 else 8.4
		local front = if stable then STABLE_FRONT else CAGE_FRONT
		local start = taken[side]
		local deg: number
		while true do
			deg = along(hero.angle, front, side * (start + width / 2))
			local a = along(hero.angle, front, side * (start - 2)) - deg
			local b = along(hero.angle, front, side * (start + width + 2)) - deg
			local blocked = false
			for _, ray in PIER_RAYS do
				local d = (ray - deg + 180) % 360 - 180
				if d >= math.min(a, b) and d <= math.max(a, b) then
					blocked = true
				end
			end
			if not blocked then
				break
			end
			start += 0.5
		end
		taken[side] = start + width + 0.6
		local slot, plaque = cage(parent, deg, width, stable)
		table.insert(slots, slot)
		table.insert(plaques, plaque)
		table.insert(ids, id)
	end
end

-- In the Hub the hero gates stand open: the grilles and their collision go, the stone frame stays.
local function openHeroGates(arena: Instance)
	local gates = arena:FindFirstChild("Gates")
	if not gates then
		return
	end
	for _, entrance in gates:GetChildren() do
		if entrance.Name:match("^ArenaEntrance") then
			for _, item in entrance:GetChildren() do
				if item.Name == "GateCollision" or item.Name == "IronBar" or item.Name == "GateBand" or item.Name == "TimberLeaves" then
					item:Destroy()
				end
			end
		end
	end
end

function Architecture.build(buildPad: any): any
	table.clear(volumes)
	table.clear(shops)
	local existing = Workspace:FindFirstChild(Config.LobbyFolderName)
	if existing then
		existing:Destroy()
	end
	-- Exactly the same builder, gates, sand, stands and galleries as the fight place.
	local arenaFolder = Arena.build()
	Arena.setGroundExits(true) -- in the Hub the ground floor, galleries and stands are part of the lobby
	openHeroGates(arenaFolder)
	local folder = Instance.new("Folder")
	folder.Name = Config.LobbyFolderName
	local pads, menus, liveDoors, liveBoards, matchActions = {}, {}, {}, {}, {}
	local bossHosts = {}
	local soloPads: { [string]: any } = {}
	local hallFrames: { [string]: CFrame } = {}
	local shopFrames: { [string]: CFrame } = {}
	local archives, plaques, archiveIds = {}, {}, {}

	---------------------------------------------------------------- the arena (open in the Hub)
	-- Through every hero gate onto the sand: the solo start on the gate axis, the hall's co-op
	-- group beside it and, with Kroko and Schili, the team's gathering mosaic on the other side.
	local arena = model(folder, "ArenaGrounds")
	for _, hero in HEROES do
		local g = hero.angle
		local gate = Layout.frame(math.rad(g), 0, FLOOR)
		local approach = model(folder, hero.id .. "ArenaApproach")
		sign(approach, "ArenaRampSign", gate * CFrame.new(0, 10.5, 8) * CFrame.Angles(0, math.pi, 0), "THE ARENA", "Training · solo start · groups gather on the sand", hero.color, Vector2.new(16, 3.5))
		local length = if hero.id == "Otti" then Architecture.Anchors.ArrivalOffset - 9 else 36
		local guide = part(approach, "ArenaGuide", gate * CFrame.new(0, 0.03, length / 2), Vector3.new(1.2, 0.06, length + 18), GOLD, true)
		guide.Material = Enum.Material.Neon
		hallFrames[hero.id] = ring(g, 40)
		local solo = sandPad(buildPad, arena, soloDefinition(hero), g, 14, Vector2.new(10, 10), true)
		soloPads[hero.id] = solo
		table.insert(pads, solo)
		local coopId = if hero.id == "Otti" then "ZombieCoop" else hero.id .. "ZombieCoop"
		table.insert(pads, sandPad(buildPad, arena, coopDefinition(coopId, hero.emblem), along(g, -16, -24), 16, Vector2.new(22, 14), false))
		if hero.id ~= "Otti" then
			local def = table.clone(assert(PadDefinitions.get(if hero.id == "Schili" then "TeamSchili" else "TeamKrokero"), "team pad missing"))
			def.Actions = { { Id = "ConfirmTeam", Label = "READY TEAM" }, { Id = "Ready", Label = "READY" }, { Id = "LeaveGroup", Label = "LEAVE" } }
			table.insert(pads, sandPad(buildPad, arena, def, along(g, -16, 24), 16, Vector2.new(22, 14), false))
		end
	end
	-- Training: six straw dummies in a ring around the middle, each looking outward
	local training = {}
	for k = 0, 5 do
		table.insert(training, CFrame.new(0, FLOOR, 0) * CFrame.Angles(0, math.rad(30 + 60 * k), 0) * CFrame.new(0, 0, -16))
	end
	part(arena, "TrainingRing", CFrame.new(0, FLOOR + 0.03, 0), Vector3.new(44, 0.06, 44), YARD, true).Material = Enum.Material.Sand
	part(arena, "ComboTrainingBoard", sand(along(90, -5, 24), 5, 6), Vector3.new(12, 9, 0.5), WOOD, true)
	sign(arena, "TrainingEntrance", sand(along(90, -5, 24), 5.4, 12.4), "TRAINING", "Straw dummies in the middle · practise attacks, blocks and specials · no rewards", nil, Vector2.new(14, 3))
	local trainingCFrame = CFrame.new(0, FLOOR + 8, 0)
	local trainingSize = Vector3.new(2 * Layout.SemiAxisX, 18, 2 * Layout.SemiAxisZ)

	-- One shop bay under the stands: an inner row (offset 26) and an outer row (offset 44) of
	-- displays face each other across a rug. `faceUp`: the sign reads from increasing angles.
	local INNER, OUTER = 26, 44
	local function shopBay(hero: any, from: number, to: number, theme: string, second: string, title: string, goods: string, faceUp: boolean)
		local frame = ring((from + to) / 2, 35)
		shopFrames[hero.id] = frame
		local arc = (ring(from, 35).Position - ring(to, 35).Position).Magnitude
		local room = model(folder, hero.id .. "Shop")
		part(room, "ShopRug", frame * CFrame.new(0, 0.04, 0), Vector3.new(arc, 0.08, 12), RUG, true).Material = Enum.Material.Fabric
		sign(room, "ShopSign", frame * CFrame.new(0, 13, 0) * CFrame.Angles(0, if faceUp then math.pi / 2 else -math.pi / 2, 0), title, goods, hero.color, Vector2.new(14, 3.4))
		Battles.build(room, frame, theme, hero.emblem, second, { floor = frame * CFrame.new(0, 0.11, 0) * CFrame.Angles(math.pi / 2, 0, 0) * CFrame.Angles(0, 0, math.pi), floorSize = Vector2.new(math.min(arc - 4, 24), 10), walls = false })
		for _, at in { from + 1, to - 1 } do
			brazier(room, ring(at, 35))
		end
		zone(frame * CFrame.new(0, 10, 0), Vector3.new(arc + 4, 26, OUTER - INNER + 8), true)
	end
	local armory = {
		blades = chord(112, 121.5, INNER, 1),
		ranged = chord(306, 312, OUTER, -1),
		heavy = chord(224, 238, OUTER, -1),
		shields = {
			Light = chord(303, 315, INNER, 1),
			Balanced = chord(123.5, 130.5, INNER, 1),
			Heavy = chord(225, 237, INNER, 1),
		},
		armor = chord(112, 130, OUTER, -1),
		floorY = FLOOR,
	}

	---------------------------------------------------------------- OTTI · the main lobby
	local otti = HEROES[1]
	local hall = model(folder, "OttiHeroLobby")
	hall:SetAttribute("Hero", "Otti")
	local A = Architecture.Anchors
	local arrivalCF = ring(A.ArrivalAngle, A.ArrivalOffset)
	local axis = function(offset: number): Vector3
		return ring(90, offset).Position
	end
	zone(ring(90, 40, 10), Vector3.new(60, 24, 60))
	-- Otti's monument beside the way to the gate (west side), looking at the arriving player
	local monumentAt = (ring(90, 38) * CFrame.new(-17, 0, 0)).Position
	monument(hall, facing(monumentAt, axis(48)), otti)
	Mosaics.build(hall, ring(90, 38) * CFrame.new(17, 0.05, 0) * CFrame.Angles(0, math.pi, 0), "Otti", 1.0, SANDSTONE)
	for _, x in { -11, 11 } do
		part(hall, "Bench", ring(90, 56) * CFrame.new(x, 1.1, 0), Vector3.new(3, 2.2, 9), WOOD)
	end
	for _, spot in { { -9, 30 }, { 9, 30 }, { -9, 58 }, { 9, 58 } } do
		brazier(hall, ring(90, spot[2]) * CFrame.new(spot[1], 0, 0))
	end
	for _, x in { -26, 26 } do
		banner(hall, ring(90, 52) * CFrame.new(x, 30, 0), otti.color)
	end
	sign(hall, "HallName", ring(90, 70, 20) * CFrame.Angles(0, math.pi, 0), "OTTI'S HALL", "The start · arena gate · blades, shields and armor · zombie cages", otti.color, Vector2.new(24, 4))
	sign(hall, "ArenaSign", ring(90, 30, 15) * CFrame.Angles(0, math.pi, 0), "THE ARENA", "Straight ahead · through the open gate", GOLD, Vector2.new(16, 3.6))
	-- The notice walls near the gate face the arrival: teams (stage 3) to the west, all modes,
	-- bosses and live battles (stage 4) to the east
	local west = noticeWall(hall, (ring(90, 24) * CFrame.new(-19, 0, 0)).Position, axis(A.ArrivalOffset), 18, 13)
	revealStage = 3
	local teams = sign(hall, "TeamsMenu", west * CFrame.new(0, 11, 0), "TEAM BATTLES", "Time · First to · Elimination", GOLD, Vector2.new(18, 4))
	teams:SetAttribute("MenuTab", "TEAMS")
	table.insert(menus, teams)
	for i, mode in { { "TIME_BATTLE", "TIME BATTLE" }, { "FIRST_TO", "FIRST TO" }, { "ELIMINATION", "ELIMINATION" } } do
		local queueHost = sign(hall, "TeamQueueEntrance", west * CFrame.new((i - 2) * 6, 5, 0), mode[2], "F · join / leave queue", GOLD, Vector2.new(5.6, 4))
		table.insert(matchActions, { part = queueHost, mode = mode[1] })
	end
	revealStage = nil
	local east = noticeWall(hall, (ring(90, 24) * CFrame.new(19, 0, 0)).Position, axis(A.ArrivalOffset), 18, 13)
	revealStage = 4
	table.insert(menus, (sign(hall, "AllModes", east * CFrame.new(0, 7.4, 0), "PLAY · ALL MODES", "Solo · Co-op · Teams · Boss · Watch", otti.color, Vector2.new(18, 4))))
	table.insert(bossHosts, (sign(hall, "BossSelection", east * CFrame.new(0, 2.8, 0), "BOSS FIGHT", "Otti · Schili · Krokero", otti.color, Vector2.new(18, 4))))
	local live, liveCount = sign(hall, "WatchLive", east * CFrame.new(0, 11.6, 0), "LIVE BATTLES", "No live battles", otti.color, Vector2.new(18, 4))
	table.insert(liveDoors, live)
	table.insert(liveBoards, liveCount)
	revealStage = nil
	-- Directions on posts beside the way: west to Otti's shop, Kroko's hall and Rome, east to
	-- Schili's hall; the training and the groups are on the sand
	revealStage = 1
	signpost(hall, (ring(90, 44) * CFrame.new(-27, 0, 0)).Position, axis(44), "OTTI'S SHOP", "Blades · balanced shields · armor · west", otti.color)
	revealStage = 3
	signpost(hall, (ring(90, 44) * CFrame.new(27, 0, 0)).Position, axis(44), "TRAINING & GROUPS", "On the sand · through the gate", otti.color)
	revealStage = 2
	signpost(hall, (ring(90, 33) * CFrame.new(-27, 0, 0)).Position, axis(33), "KROKO HALL · ROMA", "Heavy weapons and shields · the west arch leads to Rome", otti.color)
	signpost(hall, (ring(90, 33) * CFrame.new(27, 0, 0)).Position, axis(33), "SCHILI HALL", "Ranged weapons · light shields · east", otti.color)
	revealStage = nil
	cages(hall, otti, archives, plaques, archiveIds)
	shopBay(otti, 112, 131, "Weapons", "Krokero", "OTTI'S SHOP", "Blades · balanced shields · armor", false)

	---------------------------------------------------------------- SCHILI and KROKO
	for index = 2, 3 do
		local hero = HEROES[index]
		local g = hero.angle
		local kroko = hero.id == "Kroko"
		local s = if kroko then 1 else -1 -- +1: the tower side lies at increasing angle
		local small = model(folder, hero.id .. "HeroLobby")
		small:SetAttribute("Hero", hero.id)
		zone(ring(g, 36, 10), Vector3.new(70, 24, 50))
		-- the monument beside the way, towards the stair tower; it looks at the gate axis
		local monumentPosition = ring(g + s * 8, 46).Position
		monument(small, facing(monumentPosition, ring(g, 40).Position), hero)
		-- the hall's shop bay beyond the monument, then the boards on a notice wall facing the way
		if kroko then
			shopBay(hero, 224, 238, "Shields", "Otti", "KROKO'S SHOP", "Heavy weapons · heavy shields", false)
		else
			shopBay(hero, 302, 316, "Armor", "Otti", "SCHILI'S SHOP", "Ranged weapons · light shields", true)
		end
		local boardsAt = ring(g + s * 33, 38).Position
		local wall = noticeWall(small, boardsAt, ring(g + s * 10, 34).Position, 16, 13)
		table.insert(menus, (sign(small, "AllModes", wall * CFrame.new(0, 7.4, 0), "PLAY · ALL MODES", "Solo · Co-op · Teams · Boss · Watch", hero.color, Vector2.new(14, 4))))
		table.insert(bossHosts, (sign(small, "BossSelection", wall * CFrame.new(0, 2.8, 0), "BOSS FIGHT", "Otti · Schili · Krokero", hero.color, Vector2.new(14, 4))))
		local liveHost, count = sign(small, "WatchLive", wall * CFrame.new(0, 12, 0), "LIVE BATTLES", "No live battles", hero.color, Vector2.new(14, 4))
		table.insert(liveDoors, liveHost)
		table.insert(liveBoards, count)
		sign(small, "HallName", ring(g, 62, 18) * CFrame.Angles(0, math.pi, 0), hero.name .. " HALL", if kroko then "Legionaries · heavy weapons and shields" else "Ninjas · ranged weapons and light shields", hero.color, Vector2.new(24, 4))
		for _, deg in { g - 6, g + 6 } do
			brazier(small, ring(deg, 50))
			banner(small, ring(deg, 46, 26), hero.color)
		end
		part(small, "Bench", ring(g - s * 12, 40) * CFrame.new(0, 1.1, 0), Vector3.new(3, 2.2, 9), WOOD)
		cages(small, hero, archives, plaques, archiveIds)
	end

	---------------------------------------------------------------- the way to Rome (west arch)
	local roma = model(folder, "WayToRome")
	local exitDeg = Architecture.Anchors.CityExitAngle
	sign(roma, "RomaSign", ring(exitDeg, 80, 14), "ROMA · FORUM", "Out through the west arch · smithy · temple · harbour", GOLD, Vector2.new(18, 4))
	signpost(roma, ring(196, 46).Position, ring(185, 46).Position, "ROMA →", "The west arch · the city", GOLD)
	for deg = exitDeg - 4, exitDeg + 4, 8 do
		brazier(roma, ring(deg, 82))
	end
	local cityGuide = part(roma, "CityGuide", ring(exitDeg, 84, 0.03), Vector3.new(1.2, 0.06, 18), Color3.fromRGB(176, 125, 60), true)
	cityGuide.Material = Enum.Material.Metal

	-- Spawns: direct joins in Otti's lobby facing the gate; later respawns and fighter returns close by
	local arrival = spawn(folder, "LobbyArrivalSpawn", arrivalCF)
	local respawn = spawn(folder, "LobbyRespawn", ring(A.RespawnAngle, A.RespawnOffset))
	-- Where each intro stage points (LobbyIntroService): the solo start beyond Otti's gate, Otti's
	-- shop, Schili's hall, the training ring on the sand and the boards near the gate
	local introTargets = {
		soloPads.Otti.cframe.Position,
		ring(112, 35).Position,
		hallFrames.Schili.Position,
		Vector3.new(0, FLOOR, 0),
		(ring(90, 24) * CFrame.new(19, 0, 0)).Position,
	}
	Lighting.Ambient = Color3.fromRGB(96, 88, 78)
	Lighting.OutdoorAmbient = Color3.fromRGB(128, 120, 106)
	Lighting.Brightness = 2
	Lighting.ClockTime = 14
	Lighting.EnvironmentDiffuseScale = 0.4
	Lighting.EnvironmentSpecularScale = 0.2
	Lighting.ExposureCompensation = -0.1
	folder.Parent = Workspace
	return {
		folder = folder,
		spawnCFrame = respawn.CFrame,
		arrivalSpawn = arrival,
		respawnSpawn = respawn,
		armory = armory,
		pads = pads,
		arenaGate = soloPads.Otti.ring,
		arenaTriggers = {},
		introTargets = introTargets,
		bossBoard = bossHosts[1],
		bossBoards = bossHosts,
		modeBoards = menus,
		matchActions = matchActions,
		tribuneDoors = liveDoors,
		liveBoards = liveBoards,
		liveCFrame = respawn.CFrame,
		archiveSlots = archives,
		archivePlaques = plaques,
		archiveIds = archiveIds,
		trainingSlots = training,
		trainingCFrame = trainingCFrame,
		trainingSize = trainingSize,
		floorY = FLOOR,
		hallFrames = hallFrames,
		shopFrames = shopFrames,
		cityExit = ring(exitDeg, Layout.facadeEnd() + 2),
	}
end
-- Inside a lobby room, on the open arena's sand or anywhere on the Colosseum's floors.
function Architecture.isInside(p: Vector3): boolean
	for _, v in volumes do
		if inside(v, p) then
			return true
		end
	end
	return Arena.isInside(p) or Arena.isOnGrounds(p)
end
function Architecture.isInArmory(p: Vector3): boolean
	for _, v in shops do
		if inside(v, p) then
			return true
		end
	end
	return false
end
return Architecture
