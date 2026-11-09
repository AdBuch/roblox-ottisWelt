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
--     walk-in trigger at the gate; Otti's monument and mosaic beside the way; the team, mode, boss
--     and live boards on two notice walls near the gate; the zombie archive behind the arrival.
--   SHOP STREET bay 110..170: weapons, shields and armor along an aisle under the stands.
--   TRAINING YARD bay 30..70: the Otti co-op group at the entrance, six straw dummies beyond.
--   KROKO (gate 210) bay 190..250 and SCHILI (gate 330) bay 290..350: monument, co-op group, team
--     group and their boards. The way to Rome leaves through the facade's west arch (180).
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
	Statue.build(parent, cf * CFrame.new(0, 6, 0) * CFrame.Angles(0, math.pi, 0), 1.5, hero.id)
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

local HEROES = {
	{ id = "Otti", name = "OTTI", angle = 90, color = Color3.fromRGB(140, 38, 37), motto = "COURAGE · FRIENDSHIP · UNITY" },
	{ id = "Schili", name = "SCHILIBITZLI · SCHILI", angle = 330, color = Color3.fromRGB(52, 111, 112), motto = "WISDOM · ENDURANCE · KINDNESS" },
	{ id = "Kroko", name = "KROKERO · KROKO", angle = 210, color = Color3.fromRGB(125, 93, 43), motto = "COURAGE · ACTION · LOYALTY" },
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

-- A walk-on group pad at a ring position. `toward`: the ring angle its start pedestals face (the
-- way players come from); the board stands on the far side and faces the pad. The pad is 22 deep
-- along the radius and 14 wide along the ring.
local function ringPad(buildPad: any, parent: Instance, def: any, deg: number, offset: number, towardDeg: number): any
	-- the ring frame's +X points to decreasing angle: turn the pad so its +Z (pedestals) does too
	-- when `towardDeg` is smaller, otherwise the other way; its X then runs along the radius
	local center = ring(deg, offset) * CFrame.Angles(0, if towardDeg < deg then math.pi / 2 else -math.pi / 2, 0)
	local board = center * CFrame.new(0, 10, -(7 + 2.3)) * CFrame.Angles(0, math.pi, 0)
	return buildPad(parent, def, center, Vector2.new(22, 14), board, 1)
end

function Architecture.build(buildPad: any): any
	table.clear(volumes)
	table.clear(shops)
	local existing = Workspace:FindFirstChild(Config.LobbyFolderName)
	if existing then
		existing:Destroy()
	end
	-- Exactly the same builder, gates, sand, stands and galleries as the fight place.
	Arena.build()
	Arena.setGroundExits(true) -- in the Hub the ground floor, galleries and stands are part of the lobby
	local folder = Instance.new("Folder")
	folder.Name = Config.LobbyFolderName
	local pads, menus, liveDoors, liveBoards, matchActions = {}, {}, {}, {}, {}
	local triggers, bossHosts = {}, {}
	local hallFrames: { [string]: CFrame } = {}

	-- Every hero gate: walking up to it starts a solo zombie run (HubMatchService), no key or menu.
	for _, hero in HEROES do
		local gate = Layout.frame(math.rad(hero.angle), 0, FLOOR)
		local approach = model(folder, hero.id .. "ArenaApproach")
		local trigger = part(approach, "ArenaTrigger", gate * CFrame.new(0, 4, 5.5), Vector3.new(18, 8, 6), GOLD)
		trigger.Transparency, trigger.CanCollide, trigger.CanQuery, trigger.CastShadow = 1, false, false, false
		table.insert(triggers, trigger)
		sign(approach, "ArenaRampSign", gate * CFrame.new(0, 10.5, 8) * CFrame.Angles(0, math.pi, 0), "ZOMBIE ARENA", "Walk through the gate · your fight starts there", hero.color, Vector2.new(16, 3.5))
		local length = if hero.id == "Otti" then Architecture.Anchors.ArrivalOffset - 9 else 36
		local guide = part(approach, "ArenaGuide", gate * CFrame.new(0, 0.03, 9 + length / 2), Vector3.new(1.2, 0.06, length), GOLD, true)
		guide.Material = Enum.Material.Neon
		hallFrames[hero.id] = ring(hero.angle, 40)
	end

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
		part(hall, "Bench", ring(90, 47) * CFrame.new(x, 1.1, 0), Vector3.new(3, 2.2, 9), WOOD)
	end
	for _, spot in { { -9, 30 }, { 9, 30 }, { -9, 58 }, { 9, 58 } } do
		brazier(hall, ring(90, spot[2]) * CFrame.new(spot[1], 0, 0))
	end
	for _, x in { -26, 26 } do
		banner(hall, ring(90, 52) * CFrame.new(x, 30, 0), otti.color)
	end
	sign(hall, "HallName", ring(90, 70, 20) * CFrame.Angles(0, math.pi, 0), "OTTI'S HALL", "The start · arena gate · shops · co-op · training", otti.color, Vector2.new(24, 4))
	sign(hall, "ArenaSign", ring(90, 30, 15) * CFrame.Angles(0, math.pi, 0), "THE ARENA", "Straight ahead · walk through the gate", GOLD, Vector2.new(16, 3.6))
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
	-- Directions on posts beside the way: west to the shops, Kroko's hall and Rome, east to the
	-- training yard and Schili's hall
	revealStage = 1
	signpost(hall, (ring(90, 44) * CFrame.new(-27, 0, 0)).Position, axis(44), "SHOP STREET", "Weapons · shields · armor · west", otti.color)
	revealStage = 3
	signpost(hall, (ring(90, 44) * CFrame.new(27, 0, 0)).Position, axis(44), "CO-OP & TRAINING", "Co-op group · straw dummies · east", otti.color)
	revealStage = 2
	signpost(hall, (ring(90, 33) * CFrame.new(-27, 0, 0)).Position, axis(33), "KROKO HALL · ROMA", "Past the shops · the west arch leads to Rome", otti.color)
	signpost(hall, (ring(90, 33) * CFrame.new(27, 0, 0)).Position, axis(33), "SCHILI HALL", "Past the training yard", otti.color)
	revealStage = nil

	-- The zombie archive behind the arrival: three cages on each side, open towards the hall
	local archives, plaques = {}, {}
	for _, side in { -1, 1 } do
		for _, x in { 12.5, 22.5, 32.5 } do
			local cf = ring(90, 64) * CFrame.new(side * x, 0, 0)
			local cage = model(hall, "ArchiveCage")
			for _, s in { -1, 1 } do
				part(cage, "CageSide", cf * CFrame.new(s * 4.4, 5, 0), Vector3.new(0.6, 10, 8), IRON)
			end
			part(cage, "CageRoof", cf * CFrame.new(0, 10.2, 0), Vector3.new(9.4, 0.4, 8), IRON)
			for bx = -3.6, 3.61, 1.2 do
				part(cage, "PrisonBars", cf * CFrame.new(bx, 5, -4), Vector3.new(0.3, 10, 0.3), IRON)
			end
			table.insert(archives, cf)
			table.insert(plaques, cf * CFrame.new(0, 12.5, -4.3))
		end
		sign(hall, "ArchiveSign", ring(90, 60) * CFrame.new(side * 22.5, 17, 0), "ZOMBIE ARCHIVE", "Know your enemy before the gate", nil, Vector2.new(16, 3))
	end

	---------------------------------------------------------------- the shop street (110..170)
	-- Displays along an aisle under the stands: an inner row (offset 26) and an outer row
	-- (offset 44) face each other. Weapons 112..126, shields 127..148, armor 151..169.
	local street = model(folder, "ShopStreet")
	local INNER, OUTER = 26, 44
	local armory = {
		blades = chord(112, 121.5, INNER, 1),
		ranged = chord(122, 126, INNER, 1),
		heavy = chord(112, 126, OUTER, -1),
		shields = {
			Light = chord(127, 138, INNER, 1),
			Balanced = chord(138.5, 147.5, INNER, 1),
			Heavy = chord(129, 146, OUTER, -1),
		},
		armor = chord(151, 169, OUTER, -1),
		floorY = FLOOR,
	}
	local shopFrames: { [string]: CFrame } = {}
	for _, entry in {
		{ name = "Weapons", from = 112, to = 126, first = "Krokero", second = "Otti" },
		{ name = "Shields", from = 127, to = 148, first = "Otti", second = "Schili" },
		{ name = "Armor", from = 151, to = 169, first = "Schili", second = "Krokero" },
	} do
		local mid = (entry.from + entry.to) / 2
		local frame = ring(mid, 35)
		shopFrames[entry.name] = frame
		local arc = (ring(entry.from, 35).Position - ring(entry.to, 35).Position).Magnitude
		local room = model(street, entry.name .. "Shop")
		part(room, "ShopRug", frame * CFrame.new(0, 0.04, 0), Vector3.new(arc, 0.08, 12), RUG, true).Material = Enum.Material.Fabric
		sign(room, "ShopSign", frame * CFrame.new(0, 13, 0) * CFrame.Angles(0, -math.pi / 2, 0), entry.name:upper(), entry.first .. " & " .. entry.second .. " · equipment", nil, Vector2.new(14, 3.4))
		Battles.build(room, frame, entry.name, entry.first, entry.second, { floor = frame * CFrame.new(0, 0.11, 0) * CFrame.Angles(math.pi / 2, 0, 0) * CFrame.Angles(0, 0, math.pi), floorSize = Vector2.new(math.min(arc - 4, 24), 10), walls = false })
		for _, at in { entry.from + 1, entry.to - 1 } do
			brazier(room, ring(at, 35))
		end
		zone(frame * CFrame.new(0, 10, 0), Vector3.new(arc + 4, 26, OUTER - INNER + 8), true)
	end
	revealStage = 1
	sign(street, "ShopStreetSign", ring(111, 35, 14) * CFrame.Angles(0, -math.pi / 2, 0), "SHOP STREET", "Weapons · shields · armor for denarii", otti.color, Vector2.new(16, 3.4))
	revealStage = nil

	---------------------------------------------------------------- the training yard (30..70)
	local yard = model(folder, "TrainingYard")
	local yardFrame = ring(44, 34)
	local yardArc = (ring(32, 34).Position - ring(56, 34).Position).Magnitude
	part(yard, "YardSand", yardFrame * CFrame.new(0, 0.04, 0), Vector3.new(yardArc, 0.08, 30), YARD, true).Material = Enum.Material.Sand
	table.insert(pads, ringPad(buildPad, yard, coopDefinition("ZombieCoop", "Otti"), 61, 33, 70))
	local training = {}
	for _, deg in { 52, 44, 36 } do
		for _, offset in { 26, 42 } do
			local base = ring(deg, offset)
			-- dummies face the yard's middle (offset 34)
			table.insert(training, if offset < 34 then base * CFrame.Angles(0, math.pi, 0) else base)
		end
	end
	sign(yard, "TrainingEntrance", ring(44, 20, 9) * CFrame.Angles(0, math.pi, 0), "TRAINING YARD", "Straw dummies · practise attacks, blocks and specials · no rewards", nil, Vector2.new(22, 4))
	part(yard, "ComboTrainingBoard", ring(31.5, 34, 6) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(12, 9, 0.5), WOOD, true)
	for _, deg in { 34, 56 } do
		brazier(yard, ring(deg, 50))
	end
	local trainingCFrame = yardFrame * CFrame.new(0, 8, 0)
	local trainingSize = Vector3.new(yardArc + 6, 18, 34)
	zone(trainingCFrame, trainingSize)

	---------------------------------------------------------------- SCHILI and KROKO
	for index = 2, 3 do
		local hero = HEROES[index]
		local g = hero.angle
		local s = if hero.id == "Kroko" then 1 else -1 -- +1: the tower side lies at increasing angle
		local small = model(folder, hero.id .. "HeroLobby")
		small:SetAttribute("Hero", hero.id)
		zone(ring(g, 36, 10), Vector3.new(70, 24, 50))
		-- the monument beside the way, towards the stair tower; it looks at the gate axis
		local monumentPosition = ring(g + s * 8, 46).Position
		monument(small, facing(monumentPosition, ring(g, 40).Position), hero)
		local emblem = if hero.id == "Kroko" then "Krokero" else hero.id
		-- co-op group on the west / east side of the way, the team on the tower side
		table.insert(pads, ringPad(buildPad, small, coopDefinition(hero.id .. "ZombieCoop", emblem), g - s * 12, 32, g))
		local def = table.clone(assert(PadDefinitions.get(if hero.id == "Schili" then "TeamSchili" else "TeamKrokero"), "team pad missing"))
		def.Actions = { { Id = "ConfirmTeam", Label = "READY TEAM" }, { Id = "Ready", Label = "READY" }, { Id = "LeaveGroup", Label = "LEAVE" } }
		table.insert(pads, ringPad(buildPad, small, def, g + s * 19, 30, g))
		-- boards on a notice wall beyond the team, facing the way
		local boardsAt = ring(g + s * 30, 38).Position
		local wall = noticeWall(small, boardsAt, ring(g + s * 10, 34).Position, 16, 13)
		table.insert(menus, (sign(small, "AllModes", wall * CFrame.new(0, 7.4, 0), "PLAY · ALL MODES", "Solo · Co-op · Teams · Boss · Watch", hero.color, Vector2.new(14, 4))))
		table.insert(bossHosts, (sign(small, "BossSelection", wall * CFrame.new(0, 2.8, 0), "BOSS FIGHT", "Otti · Schili · Krokero", hero.color, Vector2.new(14, 4))))
		local liveHost, count = sign(small, "WatchLive", wall * CFrame.new(0, 12, 0), "LIVE BATTLES", "No live battles", hero.color, Vector2.new(14, 4))
		table.insert(liveDoors, liveHost)
		table.insert(liveBoards, count)
		sign(small, "HallName", ring(g, 62, 18) * CFrame.Angles(0, math.pi, 0), hero.name .. " HALL", "Co-op group · team " .. (if hero.id == "Kroko" then "Krokero" else "Schili"), hero.color, Vector2.new(24, 4))
		for _, deg in { g - 6, g + 6 } do
			brazier(small, ring(deg, 50))
			banner(small, ring(deg, 46, 26), hero.color)
		end
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
	-- Where each intro stage points (LobbyIntroService): the gate, the shop street, Schili's hall,
	-- the training yard and the boards near the gate
	local introTargets = {
		triggers[1].Position,
		ring(112, 35).Position,
		hallFrames.Schili.Position,
		ring(66, 34).Position,
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
		arenaGate = triggers[1],
		arenaTriggers = triggers,
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
		trainingSlots = training,
		trainingCFrame = trainingCFrame,
		trainingSize = trainingSize,
		floorY = FLOOR,
		hallFrames = hallFrames,
		shopFrames = shopFrames,
		cityExit = ring(exitDeg, Layout.facadeEnd() + 2),
	}
end
-- Inside a lobby room or anywhere on the Colosseum's floors (not on the sand).
function Architecture.isInside(p: Vector3): boolean
	for _, v in volumes do
		if inside(v, p) then
			return true
		end
	end
	return Arena.isOnGrounds(p)
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
