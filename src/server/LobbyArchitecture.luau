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
--     against the podium wall (zombies with Otti, legionaries with Kroko, ninjas with Schili).
--   KROKO (gate 210) bay 190..250 and SCHILI (gate 330) bay 290..350: monument, boards.
--   THE ARENA IS CLOSED in the Hub: the three hero gates keep their grilles, nobody walks on the
--     sand. Each gate is a way into a fight instead:
--       Otti's gate (the first one, straight ahead of the arrival): the SOLO mosaic lies in the
--         gateway; standing on it starts the solo fight in the Arena place.
--       Kroko's gate leads down to the TEAM CELLAR, Schili's gate to the CO-OP CELLAR: walking
--         into the gateway places the player in the cellar (Architecture portals, CellarService).
--   THE CELLARS (hypogeum): two vaulted halls under the arena, built like the first lobby
--     (stone, piers, braziers, banners, mosaics) but without any shop. The co-op cellar holds the
--     three group mosaics for the zombie arena, the team cellar the two opposing team mosaics.
--     Each has a gate back to the Colosseum (to the hall in front of the gate it was entered by).
--   Training is in Rome (the yards behind the smithy and the helm shop, RomeLayout.training), the
--     shops too. The way to Rome leaves through the west arch (180).
--
-- In the ring frames local +X points towards DEcreasing angle, local +Z outward, -Z into the arena.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local Layout = require(ReplicatedStorage.Shared.ColosseumLayout)
-- The gathering cellars under the arena: floor 35 studs below the sand (above the Hub's deep-fall
-- line at -45), each 72 x 48 and 16 high. RomeWorld carves them out of the island's terrain.
local CELLAR = { y = -34, width = 72, depth = 48, height = 16, wall = 2 }
local Config = require(ReplicatedStorage.Shared.Config)
local PadDefinitions = require(ReplicatedStorage.Shared.LobbyPadDefinitions)
local Statue = require(script.Parent.LobbyStatue)
local Mosaics = require(script.Parent.LobbyMosaics)
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
local RUG = Color3.fromRGB(150, 54, 40)
-- The hero monuments: twice the size the heroes fight at (a rig is built at fight size)
local STATUE_SCALE = 2

-- The Hub's anchors (ring angle in degrees, outward offset in studs)
Architecture.Anchors = table.freeze({
	ArrivalAngle = 90, ArrivalOffset = 52, -- Otti's lobby: direct joins, facing the gate
	RespawnAngle = 87.5, RespawnOffset = 58, -- later characters and Arena returns
	CityExitAngle = 180, -- the facade's west arch: the way to Rome
})

type Volume = { cf: CFrame, size: Vector3, kinds: { [string]: boolean }? }
-- A walk-in doorway: a player inside the box is placed at `target` (CellarService).
export type Portal = { name: string, cframe: CFrame, size: Vector3, target: CFrame, text: string }
local carves: { Volume } = {}
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

-- The solo start in Otti's gateway: the mosaic lies on the hall floor right in front of the closed
-- gate (offsets 6..14, the start pedestal between it and the grille), its board hangs above the
-- way under the second tier (7.5 studs of headroom below it), facing the arrival.
local function gatewayPad(buildPad: any, parent: Instance, def: any, deg: number): any
	local size = Vector2.new(12, 8)
	local center = ring(deg, 10)
	local board = ring(deg, 14.4, 10) * CFrame.Angles(0, math.pi, 0)
	return buildPad(parent, def, center, size, board, -1)
end

-- The doorway to a cellar in a hero gate: a glowing step in front of the grille and a sign above
-- the way. Returns the portal (the gateway's box and where it leads).
local function gatePortal(parent: Instance, hero: any, title: string, subtitle: string, target: CFrame, text: string): Portal
	local g = hero.angle
	sign(parent, "CellarSign", ring(g, 14, 11.2) * CFrame.Angles(0, math.pi, 0), title, subtitle, hero.color, Vector2.new(16, 3.5))
	local glow = part(parent, "CellarDoorGlow", ring(g, 1.9, 5), Vector3.new(15, 10, 0.3), GOLD, true)
	glow.Material, glow.Transparency = Enum.Material.Neon, 0.8
	local step = part(parent, "CellarDoorStep", ring(g, 6, 0.05), Vector3.new(14, 0.1, 8), hero.color, true)
	step.Material, step.Transparency = Enum.Material.Neon, 0.35
	for _, x in { -8, 8 } do
		lamp(parent, ring(g, 5, 7) * CFrame.new(x, 0, 0))
	end
	return { name = hero.id .. "GateDown", cframe = ring(g, 6, 5), size = Vector3.new(14, 10, 8), target = target, text = text }
end

-- A gathering cellar: one vaulted hall like the first lobby (stone walls, piers, ceiling beams,
-- braziers, banners, a carpet), no shop. `room`: the middle of its floor, -Z towards the back wall
-- with the boards, +Z towards the gate back to the Colosseum. Returns the model, where players
-- arrive (looking at the mosaics) and the box of the gate back.
local function cellar(parent: Instance, name: string, room: CFrame, color: Color3, title: string, subtitle: string): (Model, CFrame, CFrame, Vector3)
	local m = model(parent, name)
	local w, d, h, t = CELLAR.width, CELLAR.depth, CELLAR.height, CELLAR.wall
	local function box(partName: string, x: number, y: number, z: number, size: Vector3, colour: Color3, decor: boolean?): Part
		return part(m, partName, room * CFrame.new(x, y, z), size, colour, decor)
	end
	box("CellarFloor", 0, -0.5, 0, Vector3.new(w + 2 * t, 1, d + 2 * t), SANDSTONE).Material = Enum.Material.Pavement
	box("CellarCeiling", 0, h + 1, 0, Vector3.new(w + 2 * t, 2, d + 2 * t), DARK)
	for _, s in { -1, 1 } do
		box("CellarWall", s * (w / 2 + t / 2), h / 2, 0, Vector3.new(t, h, d + 2 * t), STONE)
		box("CellarWall", 0, h / 2, s * (d / 2 + t / 2), Vector3.new(w, h, t), STONE)
		box("WallBase", s * (w / 2 - 0.3), 1, 0, Vector3.new(0.6, 2, d), DARK, true)
		box("WallBand", s * (w / 2 - 0.15), h - 3, 0, Vector3.new(0.3, 0.5, d), GOLD, true).Material = Enum.Material.Metal
	end
	-- the vault: pilasters along the side walls carry beams across the hall; four free piers
	-- stand in the arrival half (the mosaics lie in the back half)
	for z = -d / 2 + 6, d / 2 - 5, 12 do
		for _, s in { -1, 1 } do
			box("Pilaster", s * (w / 2 - 1), h / 2, z, Vector3.new(2, h, 2.4), SANDSTONE)
			lamp(m, room * CFrame.new(s * (w / 2 - 2.6), 8, z))
		end
		box("VaultBeam", 0, h - 0.6, z, Vector3.new(w, 1.2, 1.6), SANDSTONE, true)
	end
	for _, z in { 4, 16 } do
		for _, s in { -1, 1 } do
			box("Pier", s * 13, h / 2, z, Vector3.new(2.6, h, 2.6), SANDSTONE)
			box("PierBase", s * 13, 0.5, z, Vector3.new(3.6, 1, 3.6), STONE, true)
			box("PierCapital", s * 13, h - 1.6, z, Vector3.new(3.6, 0.8, 3.6), GOLD, true).Material = Enum.Material.Metal
		end
	end
	for _, s in { -1, 1 } do
		brazier(m, room * CFrame.new(s * 8, 0, 20))
		brazier(m, room * CFrame.new(s * 30, 0, 2))
		part(m, "Bench", room * CFrame.new(s * 26, 1.1, 14), Vector3.new(3, 2.2, 9), WOOD)
		banner(m, room * CFrame.new(s * 34.6, 9.5, 14) * CFrame.Angles(0, math.pi / 2, 0), color)
		banner(m, room * CFrame.new(s * 34.6, 9.5, -8) * CFrame.Angles(0, math.pi / 2, 0), color)
	end
	local carpet = box("CellarCarpet", 0, 0.04, 9, Vector3.new(8, 0.08, 26), RUG, true)
	carpet.Material = Enum.Material.Fabric
	box("CarpetHem", 0, 0.05, 9, Vector3.new(8.6, 0.06, 26.6), GOLD, true).Material = Enum.Material.Metal
	sign(m, "CellarName", room * CFrame.new(0, 13.4, -d / 2 + 0.4) * CFrame.Angles(0, math.pi, 0), title, subtitle, color, Vector2.new(30, 3.6))
	-- the gate back to the Colosseum in the wall behind the arrival
	local gateAt = room * CFrame.new(0, 0, d / 2)
	for _, x in { -7.2, 7.2 } do
		part(m, "GatePillar", gateAt * CFrame.new(x, 5.5, -0.9), Vector3.new(2, 11, 1.8), SANDSTONE)
	end
	part(m, "GateLintel", gateAt * CFrame.new(0, 10.6, -0.9), Vector3.new(16.4, 1.6, 1.8), SANDSTONE)
	part(m, "GateDark", gateAt * CFrame.new(0, 4.9, -0.1), Vector3.new(12.4, 9.8, 0.2), Color3.fromRGB(24, 20, 18), true)
	local glow = part(m, "GateGlow", gateAt * CFrame.new(0, 4.9, -0.4), Vector3.new(12.4, 9.8, 0.2), GOLD, true)
	glow.Material, glow.Transparency = Enum.Material.Neon, 0.8
	for x = -5.4, 5.41, 1.8 do
		part(m, "IronBar", gateAt * CFrame.new(x, 4.9, -0.7), Vector3.new(0.28, 9.8, 0.3), IRON, true).Material = Enum.Material.Metal
	end
	local step = part(m, "GateStep", gateAt * CFrame.new(0, 0.05, -3), Vector3.new(12, 0.1, 5), color, true)
	step.Material, step.Transparency = Enum.Material.Neon, 0.35
	sign(m, "GateBackSign", gateAt * CFrame.new(0, 13.2, -0.5), "BACK TO THE COLOSSEUM", "Walk into the gate · up to the hall", GOLD, Vector2.new(20, 3.2))
	zone(room * CFrame.new(0, h / 2, 0), Vector3.new(w, h + 4, d))
	table.insert(carves, { cf = room * CFrame.new(0, h / 2 + 0.25, 0), size = Vector3.new(w + 2 * t - 1, h + 2.5, d + 2 * t - 1) })
	return m, room * CFrame.new(0, 0, 9), gateAt * CFrame.new(0, 4.5, -3), Vector3.new(12, 9, 5)
end

-- A group mosaic in a cellar: at (x, z) of the room, its board on the back wall.
local function cellarPad(buildPad: any, parent: Instance, def: any, room: CFrame, x: number, z: number, size: Vector2): any
	local board = room * CFrame.new(x, 6.4, -CELLAR.depth / 2 + 0.5) * CFrame.Angles(0, math.pi, 0)
	return buildPad(parent, def, room * CFrame.new(x, 0, z), size, board, 1)
end

-- Cages under the stands. A cage stands under tier 1, its back against the podium wall and its
-- bars towards the hall; a stable (for the mounted praetorian) reaches on under tier 2, where
-- there is room for horse and rider. Cages keep clear of the gate way and of the pier rays.
local PIER_RAYS = { 10, 30, 70, 110, 150, 170, 190, 250, 270, 290, 350 }
local CAGE_BACK = Layout.PodiumThickness + 0.5
local CAGE_FRONT, CAGE_HEIGHT = 12.6, 7.6 -- under tier 1: 8 studs of headroom
local STABLE_FRONT, STABLE_HEIGHT = 24, 12.4 -- under tier 2: 14 studs of headroom; room for the war horse (12 long, 10.5 high with its rider)
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
	local slot = ring(deg, if stable then 15.2 else (CAGE_BACK + CAGE_FRONT) / 2) * CFrame.Angles(0, math.pi, 0)
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

function Architecture.build(buildPad: any): any
	table.clear(volumes)
	table.clear(shops)
	table.clear(carves)
	local existing = Workspace:FindFirstChild(Config.LobbyFolderName)
	if existing then
		existing:Destroy()
	end
	-- Exactly the same builder, gates, sand, stands and galleries as the fight place.
	local arenaFolder = Arena.build()
	Arena.setGroundExits(true) -- in the Hub the ground floor, galleries and stands are part of the lobby
	local _ = arenaFolder -- the hero gates stay closed: the arena is no part of the lobby
	local folder = Instance.new("Folder")
	folder.Name = Config.LobbyFolderName
	local pads, menus, liveDoors, liveBoards, matchActions = {}, {}, {}, {}, {}
	local bossHosts = {}
	local soloPads: { [string]: any } = {}
	local coopDefs: { [string]: any } = {}
	local teamDefs: { [string]: any } = {}
	local portals: { Portal } = {}
	local hallFrames: { [string]: CFrame } = {}
	local shopFrames: { [string]: CFrame } = {}
	local archives, plaques, archiveIds = {}, {}, {}

	---------------------------------------------------------------- the gates and the cellars
	-- Otti's gate: the solo start in the gateway. Kroko's gate: down to the team cellar. Schili's
	-- gate: down to the co-op cellar. The definitions of the group mosaics are made per hero.
	for _, hero in HEROES do
		local g = hero.angle
		local gate = Layout.frame(math.rad(g), 0, FLOOR)
		local approach = model(folder, hero.id .. "ArenaApproach")
		local length = if hero.id == "Otti" then Architecture.Anchors.ArrivalOffset - 9 else 36
		local guide = part(approach, "ArenaGuide", gate * CFrame.new(0, 0.03, length / 2 + 7), Vector3.new(1.2, 0.06, length - 14), GOLD, true)
		guide.Material = Enum.Material.Neon
		hallFrames[hero.id] = ring(g, 40)
		local coopId = if hero.id == "Otti" then "ZombieCoop" else hero.id .. "ZombieCoop"
		coopDefs[hero.id] = coopDefinition(coopId, hero.emblem)
		if hero.id ~= "Otti" then
			local def = table.clone(assert(PadDefinitions.get(if hero.id == "Schili" then "TeamSchili" else "TeamKrokero"), "team pad missing"))
			def.Actions = { { Id = "ConfirmTeam", Label = "READY TEAM" }, { Id = "Ready", Label = "READY" }, { Id = "LeaveGroup", Label = "LEAVE" } }
			teamDefs[hero.id] = def
		end
	end
	local ottiHero, schiliHero, krokoHero = HEROES[1], HEROES[2], HEROES[3]
	local solo = gatewayPad(buildPad, model(folder, "OttiSoloStart"), soloDefinition(ottiHero), ottiHero.angle)
	soloPads.Otti = solo
	table.insert(pads, solo)

	local cellars = model(folder, "Cellars")
	-- back up from a cellar: into the hall in front of the gate, looking away from it
	local function hallArrival(hero: any): CFrame
		return ring(hero.angle, 24) * CFrame.Angles(0, math.pi, 0)
	end
	-- THE TEAM CELLAR (Kroko's gate): the two teams face each other across the aisle
	local teamRoom = CFrame.new(-40, CELLAR.y, 0)
	local teamCellar, teamArrival, teamGate, teamGateSize = cellar(cellars, "TeamCellar", teamRoom, krokoHero.color, "TEAM CELLAR", "Team Schili against Team Krokero · every captain presses READY TEAM")
	table.insert(pads, cellarPad(buildPad, teamCellar, teamDefs.Schili, teamRoom, -19, -8, Vector2.new(14, 14)))
	table.insert(pads, cellarPad(buildPad, teamCellar, teamDefs.Kroko, teamRoom, 19, -8, Vector2.new(14, 14)))
	banner(teamCellar, teamRoom * CFrame.new(0, 6.6, -CELLAR.depth / 2 + 0.3), GOLD)
	table.insert(portals, gatePortal(model(folder, "KrokoGateDown"), krokoHero, "TEAM BATTLES", "Through this gate · down to the team cellar", teamArrival, "Team cellar · step on a team mosaic"))
	table.insert(portals, { name = "TeamCellarUp", cframe = teamGate, size = teamGateSize, target = hallArrival(krokoHero), text = "Back in Kroko's hall" })
	-- THE CO-OP CELLAR (Schili's gate): three group mosaics for the zombie arena
	local coopRoom = CFrame.new(40, CELLAR.y, 0)
	local coopCellar, coopArrival, coopGate, coopGateSize = cellar(cellars, "CoopCellar", coopRoom, ottiHero.color, "CO-OP CELLAR", "Zombie arena together · 1-4 players gather on a mosaic")
	for i, id in { "Kroko", "Otti", "Schili" } do
		table.insert(pads, cellarPad(buildPad, coopCellar, coopDefs[id], coopRoom, (i - 2) * 23, -9, Vector2.new(18, 12)))
	end
	table.insert(portals, gatePortal(model(folder, "SchiliGateDown"), schiliHero, "CO-OP ZOMBIES", "Through this gate · down to the co-op cellar", coopArrival, "Co-op cellar · gather on a mosaic"))
	table.insert(portals, { name = "CoopCellarUp", cframe = coopGate, size = coopGateSize, target = hallArrival(schiliHero), text = "Back in Schili's hall" })

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
	sign(hall, "HallName", ring(90, 70, 20) * CFrame.Angles(0, math.pi, 0), "OTTI'S HALL", "The start · the gate to your solo fight · zombie cages · the shops are in Rome", otti.color, Vector2.new(24, 4))
	sign(hall, "ArenaSign", ring(90, 30, 15) * CFrame.Angles(0, math.pi, 0), "YOUR FIGHT", "Straight ahead · step into the gate", GOLD, Vector2.new(16, 3.6))
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
	-- Schili's hall; the groups gather in the cellars, the training is in Rome
	revealStage = 1
	signpost(hall, (ring(90, 44) * CFrame.new(-27, 0, 0)).Position, axis(44), "ROMA · SHOPS", "Weapons, shields, armor and helmets · through the west arch", otti.color)
	revealStage = 3
	signpost(hall, (ring(90, 44) * CFrame.new(27, 0, 0)).Position, axis(44), "GROUPS", "In the cellars · through the gates of Kroko and Schili", otti.color)
	revealStage = 2
	signpost(hall, (ring(90, 33) * CFrame.new(-27, 0, 0)).Position, axis(33), "KROKO HALL · TEAMS", "West · his gate leads down to the team cellar · further on: Rome", otti.color)
	signpost(hall, (ring(90, 33) * CFrame.new(27, 0, 0)).Position, axis(33), "SCHILI HALL · CO-OP", "East · his gate leads down to the co-op cellar", otti.color)
	revealStage = nil
	cages(hall, otti, archives, plaques, archiveIds)

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
		-- the boards on a notice wall facing the way
		local boardsAt = ring(g + s * 33, 38).Position
		local wall = noticeWall(small, boardsAt, ring(g + s * 10, 34).Position, 16, 13)
		table.insert(menus, (sign(small, "AllModes", wall * CFrame.new(0, 7.4, 0), "PLAY · ALL MODES", "Solo · Co-op · Teams · Boss · Watch", hero.color, Vector2.new(14, 4))))
		table.insert(bossHosts, (sign(small, "BossSelection", wall * CFrame.new(0, 2.8, 0), "BOSS FIGHT", "Otti · Schili · Krokero", hero.color, Vector2.new(14, 4))))
		local liveHost, count = sign(small, "WatchLive", wall * CFrame.new(0, 12, 0), "LIVE BATTLES", "No live battles", hero.color, Vector2.new(14, 4))
		table.insert(liveDoors, liveHost)
		table.insert(liveBoards, count)
		sign(small, "HallName", ring(g, 62, 18) * CFrame.Angles(0, math.pi, 0), hero.name .. " HALL", if kroko then "Legionaries · the gate leads down to the team cellar" else "Ninjas · the gate leads down to the co-op cellar", hero.color, Vector2.new(24, 4))
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
	sign(roma, "RomaSign", ring(exitDeg, 80, 14), "ROMA · FORUM", "Out through the west arch · training · smithy · shops · temple · harbour", GOLD, Vector2.new(18, 4))
	signpost(roma, ring(196, 46).Position, ring(185, 46).Position, "ROMA →", "The west arch · the city", GOLD)
	for deg = exitDeg - 4, exitDeg + 4, 8 do
		brazier(roma, ring(deg, 82))
	end
	local cityGuide = part(roma, "CityGuide", ring(exitDeg, 84, 0.03), Vector3.new(1.2, 0.06, 18), Color3.fromRGB(176, 125, 60), true)
	cityGuide.Material = Enum.Material.Metal

	-- Spawns: direct joins in Otti's lobby facing the gate; later respawns and fighter returns close by
	local arrival = spawn(folder, "LobbyArrivalSpawn", arrivalCF)
	local respawn = spawn(folder, "LobbyRespawn", ring(A.RespawnAngle, A.RespawnOffset))
	-- Where each intro stage leads (LobbyIntroService): a list of waypoints on the floor, the last
	-- one is the place itself. 0 the solo start in Otti's gate · 1 the shops in Rome (round the
	-- hall to the west arch, across the Forecourt, down the Handwerksgasse) · 2 Schili's gate ·
	-- 3 the training yard beside the smithy · 4 the boards near Otti's gate
	local function floorPoint(deg: number, offset: number): Vector3
		return ring(deg, offset).Position
	end
	local toRome = {
		floorPoint(112, 54), floorPoint(134, 50), floorPoint(156, 54), floorPoint(176, 60),
		floorPoint(exitDeg, Layout.facadeEnd() + 6),
		Vector3.new(-200, 1, 0), Vector3.new(-236, -2, 0),
	}
	local function withRome(last: { Vector3 }): { Vector3 }
		local path = table.clone(toRome)
		for _, point in last do
			table.insert(path, point)
		end
		return path
	end
	local introPaths: { { Vector3 } } = {
		{ soloPads.Otti.cframe.Position },
		withRome({ Vector3.new(-272, -2, 0) }), -- the Handwerksgasse between the smithy / weapon shop and the helm shop
		{ floorPoint(68, 54), floorPoint(46, 50), floorPoint(24, 54), floorPoint(2, 54), floorPoint(340, 50), floorPoint(330, 14) },
		withRome({ Vector3.new(-247.5, -2, -6), Vector3.new(-247.5, -2, -30), Vector3.new(-264, -2, -46) }),
		{ (ring(90, 28) * CFrame.new(19, 0, 0)).Position },
	}
	local introTargets: { Vector3 } = {}
	for _, path in introPaths do
		table.insert(introTargets, path[#path])
	end
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
				pads = pads,
		arenaGate = soloPads.Otti.ring,
		arenaTriggers = {},
		introTargets = introTargets,
		introPaths = introPaths,
		portals = portals,
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
		floorY = FLOOR,
		hallFrames = hallFrames,
		shopFrames = shopFrames,
		cityExit = ring(exitDeg, Layout.facadeEnd() + 2),
	}
end
-- Inside a lobby room or a cellar, or anywhere on the Colosseum's floors (the sand is closed, but
-- a player who got onto it is still in the lobby: CellarService puts them back into the hall).
function Architecture.isInside(p: Vector3): boolean
	for _, v in volumes do
		if inside(v, p) then
			return true
		end
	end
	return Arena.isInside(p) or Arena.isOnGrounds(p)
end
-- On the closed arena's sand (below the podium's top).
function Architecture.isOnSand(p: Vector3): boolean
	return Arena.isInside(p) and p.Y < FLOOR + Layout.PodiumHeight
end
-- The cellars' boxes (centre, size): RomeWorld clears the island's terrain there.
function Architecture.cellarCarves(): { { cf: CFrame, size: Vector3 } }
	local list = {}
	for _, v in carves do
		table.insert(list, { cf = v.cf, size = v.size })
	end
	return list
end
-- Rome's shops (ArmoryShops) register their rooms here, so the displays accept purchases there.
-- `kinds` (Weapon / Shield / Armor / Helmet): what this room sells; nil sells everything.
function Architecture.addArmoryVolume(cf: CFrame, size: Vector3, kinds: { string }?)
	local set: { [string]: boolean }? = nil
	if kinds then
		local s: { [string]: boolean } = {}
		for _, kind in kinds do
			s[kind] = true
		end
		set = s
	end
	table.insert(shops, { cf = cf, size = size, kinds = set })
end
-- Inside a shop room that sells `kind`.
function Architecture.armorySells(p: Vector3, kind: string): boolean
	for _, v in shops do
		if inside(v, p) and (v.kinds == nil or (v.kinds :: { [string]: boolean })[kind] == true) then
			return true
		end
	end
	return false
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
