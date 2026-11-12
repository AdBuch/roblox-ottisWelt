--!strict
-- Roman town houses from interchangeable bricks. Six types (RomeLayout.HouseType):
--   Row        Reihenhaus: narrow, two storeys, a door and small windows, sometimes a stall
--   Tenement   Mietshaus (insula): three storeys, shops on the ground floor, a wooden balcony
--   Shop       Ladenhaus: a wide shop opening (closed shutters), awning and sign
--   Courtyard  Hofhaus: wings round an atrium with a basin, a portal, blank street walls
--   Villa      Patriziervilla: a portico, wings round a colonnaded garden, a garden wall
--   Storehouse Speicher / Werkstatt: robust socket, a wide timber gate, high slit windows
-- Bricks: socket, body, dado band, ground-floor front (door, shop front, gate), upper floor
-- (windows with shutters), balcony, awning, sign, corner quoins, cornice, roof (gable along or
-- across the street, or inward-sloping atrium roofs). Variants come from the house's seed:
-- plaster family, roof colour and direction, floor count, shutter colour.
--
-- Every house model carries its plan data as attributes (HouseId, HouseType, Name, District,
-- FacesStreet, OpenInMVP, Floors) and its door anchor (DoorAnchor: CFrame on the threshold,
-- -Z looking out to the street) for a later interior or mission entrance. Only the smithy is open
-- in the MVP (Smithy.luau builds it); all other doors are closed and solid.
local RomeLayout = require(script.Parent.RomeLayout)
local Parts = require(script.Parent.RomeParts)

type House = RomeLayout.House
local C = Parts.Colors
local STOREY = 8.5
local SOCKET = 1.2

local HouseKit = {}

-- Seeded pick from a list (stable per house and purpose).
local function pick<T>(list: { T }, seed: number, salt: number): T
	return list[((seed // (salt * 7 + 1)) % #list) + 1]
end

local SHUTTERS = { Color3.fromRGB(96, 70, 46), Color3.fromRGB(84, 98, 72), Color3.fromRGB(120, 64, 46), Color3.fromRGB(70, 82, 92) }
local DADO = { Color3.fromRGB(150, 62, 44), Color3.fromRGB(176, 118, 70), Color3.fromRGB(122, 98, 74) }
local AWNING = { { C.Cream, C.RomanRed }, { C.Cream, Color3.fromRGB(196, 150, 70) }, { Color3.fromRGB(226, 214, 190), Color3.fromRGB(110, 120, 90) } }

type Ctx = { model: Model, frame: CFrame, w: number, d: number, seed: number, plaster: Color3, roof: Color3, shutter: Color3, top: number }

-- Local frame helpers: x along the street, y up from the ground (house level), z into the block;
-- the facade is the plane z = -d/2 (the frame's -Z looks at the street).
local function at(ctx: Ctx, x: number, y: number, z: number): CFrame
	return ctx.frame * CFrame.new(x, y, z)
end
local function front(ctx: Ctx, x: number, y: number, out: number): CFrame
	return ctx.frame * CFrame.new(x, y, -ctx.d / 2 - out)
end

---------------------------------------------------------------------------- bricks
local function socket(ctx: Ctx, height: number, color: Color3?)
	Parts.part(ctx.model, "Socket", at(ctx, 0, (height - 2) / 2, 0), Vector3.new(ctx.w + 0.5, height + 2, ctx.d + 0.5), color or C.Stone, { material = Enum.Material.Limestone, shadow = false })
end

local function body(ctx: Ctx, x: number, z: number, w: number, d: number, y0: number, height: number, color: Color3?): BasePart
	return Parts.part(ctx.model, "Body", at(ctx, x, y0 + height / 2, z), Vector3.new(w, height, d), color or ctx.plaster, { material = Enum.Material.Plaster })
end

local function dado(ctx: Ctx, color: Color3)
	Parts.decor(ctx.model, "Dado", front(ctx, 0, SOCKET + 1.5, 0.04), Vector3.new(ctx.w - 0.2, 3, 0.1), color, Enum.Material.Plaster)
end

local function cornice(ctx: Ctx, y: number)
	Parts.decor(ctx.model, "Cornice", front(ctx, 0, y, 0.35), Vector3.new(ctx.w + 0.6, 0.7, 0.8), C.Limestone, Enum.Material.Limestone)
end

local function quoins(ctx: Ctx, height: number)
	for _, s in { -1, 1 } do
		Parts.decor(ctx.model, "Quoin", front(ctx, s * (ctx.w / 2 - 0.45), SOCKET + height / 2, 0.08), Vector3.new(0.9, height, 0.2), C.Limestone, Enum.Material.Limestone)
	end
end

-- A closed door with stone jambs and a lintel; `wide` doors are a two-leaf gate.
local function door(ctx: Ctx, x: number, width: number, height: number, wood: Color3?)
	local y0 = SOCKET
	Parts.decor(ctx.model, "DoorLeaf", front(ctx, x, y0 + height / 2, 0.06), Vector3.new(width, height, 0.15), wood or C.Timber, Enum.Material.WoodPlanks)
	if width >= 6 then
		Parts.decor(ctx.model, "GateSeam", front(ctx, x, y0 + height / 2, 0.15), Vector3.new(0.2, height, 0.05), C.TimberDark, Enum.Material.Wood)
		for _, y in { 1.6, height - 1.6 } do
			Parts.decor(ctx.model, "GateBand", front(ctx, x, y0 + y, 0.16), Vector3.new(width, 0.35, 0.06), C.Iron, Enum.Material.Metal)
		end
	else
		Parts.decor(ctx.model, "DoorRing", front(ctx, x + width * 0.25, y0 + height * 0.5, 0.17), Vector3.new(0.5, 0.5, 0.08), C.Bronze, Enum.Material.Metal)
	end
	for _, s in { -1, 1 } do
		Parts.decor(ctx.model, "DoorJamb", front(ctx, x + s * (width / 2 + 0.35), y0 + height / 2, 0.12), Vector3.new(0.7, height + 0.2, 0.3), C.Travertine, Enum.Material.Limestone)
	end
	Parts.decor(ctx.model, "DoorLintel", front(ctx, x, y0 + height + 0.45, 0.14), Vector3.new(width + 1.6, 0.9, 0.35), C.Travertine, Enum.Material.Limestone)
end

local function window(ctx: Ctx, x: number, y: number, width: number, height: number, shutters: boolean)
	Parts.decor(ctx.model, "Window", front(ctx, x, y, 0.03), Vector3.new(width, height, 0.08), Color3.fromRGB(46, 38, 32), Enum.Material.SmoothPlastic)
	Parts.decor(ctx.model, "Sill", front(ctx, x, y - height / 2 - 0.15, 0.2), Vector3.new(width + 0.6, 0.3, 0.45), C.Travertine, Enum.Material.Limestone)
	if shutters then
		for _, s in { -1, 1 } do
			Parts.decor(ctx.model, "Shutter", front(ctx, x + s * (width / 2 + width / 4 + 0.05), y, 0.1), Vector3.new(width / 2, height, 0.12), ctx.shutter, Enum.Material.WoodPlanks)
		end
	end
end

-- A closed shop opening: vertical boards in a stone frame, a masonry counter at the sill.
local function shopFront(ctx: Ctx, x: number, width: number)
	local height = 6.6
	Parts.decor(ctx.model, "ShopShutters", front(ctx, x, SOCKET + height / 2 + 0.3, 0.05), Vector3.new(width, height, 0.12), C.Timber, Enum.Material.WoodPlanks)
	for i = 1, math.floor(width / 1.4) - 1 do
		Parts.decor(ctx.model, "Board", front(ctx, x - width / 2 + i * 1.4, SOCKET + height / 2 + 0.3, 0.13), Vector3.new(0.12, height, 0.04), C.TimberDark, Enum.Material.Wood)
	end
	Parts.decor(ctx.model, "Counter", front(ctx, x, SOCKET + 1.1, 0.35), Vector3.new(width, 2.2, 0.6), C.Limestone, Enum.Material.Limestone)
	Parts.decor(ctx.model, "ShopLintel", front(ctx, x, SOCKET + height + 0.9, 0.12), Vector3.new(width + 1.2, 0.9, 0.3), C.Travertine, Enum.Material.Limestone)
end

-- A striped fabric awning over the ground floor (non-colliding).
local function awning(ctx: Ctx, x: number, width: number, y: number)
	local colors = pick(AWNING, ctx.seed, 5)
	local depth = 3.2
	local stripes = math.max(2, math.floor(width / 1.6))
	local stripe = width / stripes
	for i = 1, stripes do
		local sx = x - width / 2 + (i - 0.5) * stripe
		-- slopes down toward the street: high side (+Z) against the wall
		Parts.wedge(ctx.model, "Awning", front(ctx, sx, y, depth / 2) * CFrame.Angles(0, 0, 0), Vector3.new(stripe, 1.1, depth), if i % 2 == 0 then colors[1] else colors[2], { collide = false, shadow = false, material = Enum.Material.Fabric })
	end
	for _, s in { -1, 1 } do
		Parts.decor(ctx.model, "AwningPole", front(ctx, x + s * (width / 2 - 0.2), y - 1.6, depth - 0.2), Vector3.new(0.25, 3.2, 0.25), C.Timber, Enum.Material.Wood)
	end
end

local function balcony(ctx: Ctx, y: number, width: number)
	local depth = 2.6
	Parts.decor(ctx.model, "BalconyFloor", front(ctx, 0, y, depth / 2), Vector3.new(width, 0.35, depth), C.Timber, Enum.Material.WoodPlanks)
	Parts.decor(ctx.model, "BalconyRail", front(ctx, 0, y + 1.6, depth - 0.1), Vector3.new(width, 0.25, 0.25), C.TimberDark, Enum.Material.Wood)
	for i = 0, math.floor(width / 1.2) do
		Parts.decor(ctx.model, "BalconyPost", front(ctx, -width / 2 + i * width / math.floor(width / 1.2), y + 0.8, depth - 0.1), Vector3.new(0.18, 1.6, 0.18), C.TimberDark, Enum.Material.Wood)
	end
	for _, s in { -1, 1 } do
		Parts.decor(ctx.model, "BalconyBeam", front(ctx, s * (width / 2 - 0.4), y - 0.4, depth / 2), Vector3.new(0.4, 0.5, depth), C.TimberDark, Enum.Material.Wood)
	end
end

local function houseSign(ctx: Ctx, x: number, y: number, text: string, width: number?)
	local board = Parts.sign(ctx.model, "HouseSign", front(ctx, x, y, 0.3), Vector2.new(width or math.min(ctx.w - 1, 12), 1.8), text, nil, C.TimberDark, C.Gold)
	board:SetAttribute("Text", text)
end

-- A gable roof over the box (w x d) at height y. `along` = "X": the ridge runs along the street.
local function gable(ctx: Ctx, cx: number, cz: number, w: number, d: number, y: number, along: string)
	local over = 0.9
	local span = if along == "X" then d else w
	local length = if along == "X" then w else d
	local rise = math.max(1.6, span / 2 * 0.42)
	local base = at(ctx, cx, y, cz) * (if along == "X" then CFrame.identity else CFrame.Angles(0, math.pi / 2, 0))
	for _, s in { -1, 1 } do
		-- each half rises toward the ridge (the wedge's +Z points at the middle)
		local half = base * CFrame.new(0, rise / 2, s * (span / 4 + over / 4)) * (if s > 0 then CFrame.Angles(0, math.pi, 0) else CFrame.identity)
		Parts.wedge(ctx.model, "Roof", half, Vector3.new(length + over * 2, rise, span / 2 + over / 2), ctx.roof, { material = Enum.Material.ClayRoofTiles })
	end
	Parts.decor(ctx.model, "RoofRidge", base * CFrame.new(0, rise + 0.15, 0), Vector3.new(length + over * 2, 0.4, 0.8), C.TerracottaDark, Enum.Material.ClayRoofTiles)
end

-- An atrium roof: four wings sloping inward around an open middle of (iw x id).
local function atriumRoofs(ctx: Ctx, iw: number, id: number, y: number)
	local w, d = ctx.w, ctx.d
	local rise = 2.4
	local fw, sw = (d - id) / 2, (w - iw) / 2
	-- front and back wings: high side outside (wedge +Z pointing away from the middle)
	for _, s in { -1, 1 } do
		local zc = s * (id / 2 + fw / 2)
		local cf = at(ctx, 0, y + rise / 2, zc) * (if s > 0 then CFrame.identity else CFrame.Angles(0, math.pi, 0))
		Parts.wedge(ctx.model, "Roof", cf, Vector3.new(w + 1.2, rise, fw + 0.6), ctx.roof, { material = Enum.Material.ClayRoofTiles })
	end
	for _, s in { -1, 1 } do
		local xc = s * (iw / 2 + sw / 2)
		local cf = at(ctx, xc, y + rise / 2, 0) * CFrame.Angles(0, if s > 0 then math.pi / 2 else -math.pi / 2, 0)
		Parts.wedge(ctx.model, "Roof", cf, Vector3.new(id, rise, sw + 0.6), ctx.roof, { material = Enum.Material.ClayRoofTiles })
	end
end

local function bush(parent: Instance, cf: CFrame, size: number)
	Parts.part(parent, "Bush", cf * CFrame.new(0, size / 2, 0), Vector3.new(size, size * 0.8, size), C.Leaf, { collide = false, shadow = false, shape = Enum.PartType.Ball, material = Enum.Material.Grass })
end

local function cypress(parent: Instance, cf: CFrame, height: number)
	Parts.decor(parent, "CypressTrunk", cf * CFrame.new(0, 1, 0), Vector3.new(0.6, 2, 0.6), C.TimberDark, Enum.Material.Wood)
	Parts.part(parent, "Cypress", cf * CFrame.new(0, 2 + height / 2, 0), Vector3.new(2.4, height, 2.4), C.LeafDark, { collide = false, shadow = false, shape = Enum.PartType.Ball, material = Enum.Material.Grass })
end

-- The open middle of a courtyard house or villa: paving, a basin, plants, an optional colonnade.
local function courtyard(ctx: Ctx, iw: number, id: number, columns: boolean)
	local floor = at(ctx, 0, SOCKET, 0)
	Parts.decor(ctx.model, "Court", floor * CFrame.new(0, 0.05, 0), Vector3.new(iw, 0.1, id), if columns then Color3.fromRGB(110, 140, 82) else C.Limestone, if columns then Enum.Material.Grass else Enum.Material.Pavement)
	Parts.decor(ctx.model, "Impluvium", floor * CFrame.new(0, 0.2, 0), Vector3.new(math.min(6, iw - 4), 0.3, math.min(4, id - 4)), C.Travertine, Enum.Material.Marble)
	Parts.decor(ctx.model, "ImpluviumWater", floor * CFrame.new(0, 0.38, 0), Vector3.new(math.min(6, iw - 4) - 0.8, 0.05, math.min(4, id - 4) - 0.8), C.Water, Enum.Material.Glass)
	if columns then
		local step = 5
		for x = -iw / 2 + 1.5, iw / 2 - 1.5, step do
			for _, s in { -1, 1 } do
				Parts.column(ctx.model, "Peristyle", floor * CFrame.new(x, 0, s * (id / 2 - 1.5)), 7.5, 0.9, C.Travertine, { collide = false, shadow = false, material = Enum.Material.Marble })
			end
		end
		for _, p in { { -iw / 4, -id / 5 }, { iw / 4, id / 5 } } do
			cypress(ctx.model, floor * CFrame.new(p[1], 0, p[2]), 6)
		end
		bush(ctx.model, floor * CFrame.new(iw / 4, 0, -id / 5), 2.4)
		bush(ctx.model, floor * CFrame.new(-iw / 4, 0, id / 5), 2.4)
	else
		bush(ctx.model, floor * CFrame.new(iw / 2 - 1.6, 0, id / 2 - 1.6), 2)
	end
end

---------------------------------------------------------------------------- types
local function row(ctx: Ctx, h: House)
	local height = h.floors * STOREY
	body(ctx, 0, 0, ctx.w, ctx.d, SOCKET, height)
	dado(ctx, pick(DADO, ctx.seed, 2))
	quoins(ctx, height)
	local doorX = if ctx.seed % 2 == 0 then -ctx.w / 2 + 3 else ctx.w / 2 - 3
	door(ctx, doorX, 3.4, 7)
	if ctx.seed % 5 == 0 then
		shopFront(ctx, -doorX * 0.55, 4.4)
	else
		window(ctx, -doorX * 0.6, SOCKET + 5.2, 1.6, 1.6, false)
	end
	for f = 2, h.floors do
		local y = SOCKET + (f - 1) * STOREY + 4
		for _, x in { -ctx.w / 4, ctx.w / 4 } do
			window(ctx, x, y, 2, 2.8, true)
		end
	end
	cornice(ctx, SOCKET + height - 0.3)
	gable(ctx, 0, 0, ctx.w, ctx.d, SOCKET + height, if ctx.seed % 3 == 0 then "Z" else "X")
end

local function tenement(ctx: Ctx, h: House)
	local height = h.floors * STOREY
	body(ctx, 0, 0, ctx.w, ctx.d, SOCKET, height)
	dado(ctx, pick(DADO, ctx.seed, 2))
	quoins(ctx, height)
	door(ctx, 0, 3.4, 7)
	for _, s in { -1, 1 } do
		shopFront(ctx, s * (ctx.w / 4 + 1), ctx.w / 2 - 4.4)
	end
	balcony(ctx, SOCKET + STOREY + 0.2, ctx.w - 2)
	for f = 2, h.floors do
		local y = SOCKET + (f - 1) * STOREY + 4
		for _, x in { -ctx.w / 3, 0, ctx.w / 3 } do
			window(ctx, x, y, if f == 2 then 2.2 else 1.6, if f == 2 then 3.4 else 2.2, f == 2)
		end
	end
	if h.name then
		awning(ctx, 0, ctx.w - 2, SOCKET + 7.4)
		houseSign(ctx, 0, SOCKET + 9.7 - 0.9, h.name, ctx.w - 2)
		-- a tavern lantern and amphorae at the door
		Parts.flame(ctx.model, front(ctx, 2.6, SOCKET + 6.5, 0.6), 16, 0.7)
		for i, x in { -ctx.w / 2 + 1.2, -ctx.w / 2 + 2.4 } do
			Parts.part(ctx.model, "Amphora", front(ctx, x, SOCKET + 1.1, 0.9 + i * 0.2), Vector3.new(1, 2.2, 1), C.Terracotta, { collide = false, shadow = false, shape = Enum.PartType.Ball, material = Enum.Material.Slate })
		end
	end
	cornice(ctx, SOCKET + height - 0.3)
	gable(ctx, 0, 0, ctx.w, ctx.d, SOCKET + height, if ctx.seed % 2 == 0 then "X" else "Z")
end

local function shop(ctx: Ctx, h: House)
	local height = h.floors * STOREY
	body(ctx, 0, 0, ctx.w, ctx.d, SOCKET, height)
	quoins(ctx, height)
	local opening = math.min(ctx.w - 4.6, 8)
	shopFront(ctx, -ctx.w / 2 + 1 + opening / 2, opening)
	door(ctx, ctx.w / 2 - 2.1, 2.6, 7)
	if h.special == "Bakery" then
		-- the oven motif: a brick oven mouth with embers beside the counter, bread on the counter
		local ovenX = -ctx.w / 2 + 1 + opening / 2
		Parts.decor(ctx.model, "OvenArch", front(ctx, ovenX, SOCKET + 9, 0.2), Vector3.new(4.4, 2.6, 0.4), C.TerracottaDark, Enum.Material.Brick)
		Parts.part(ctx.model, "OvenDome", front(ctx, ovenX, SOCKET + 10.6, 0.25), Vector3.new(4.6, 2.6, 0.6), C.Terracotta, { collide = false, shadow = false, shape = Enum.PartType.Ball, material = Enum.Material.Brick })
		Parts.decor(ctx.model, "OvenMouth", front(ctx, ovenX, SOCKET + 8.9, 0.42), Vector3.new(2, 1.3, 0.05), Color3.fromRGB(255, 120, 50), Enum.Material.Neon)
		for i = -2, 2 do
			local basket = front(ctx, ovenX + i * 1.3, SOCKET + 2.45, 0.6)
			Parts.decor(ctx.model, "BreadBasket", basket, Vector3.new(1.1, 0.5, 0.9), Color3.fromRGB(150, 112, 62), Enum.Material.Fabric)
			Parts.part(ctx.model, "Bread", basket * CFrame.new(0, 0.4, 0), Vector3.new(0.8, 0.45, 0.8), Color3.fromRGB(196, 136, 64), { collide = false, shadow = false, shape = Enum.PartType.Ball, material = Enum.Material.Sand })
		end
	end
	awning(ctx, -ctx.w / 2 + 1 + opening / 2, opening + 1, SOCKET + 7.6)
	local label = h.name or (if ctx.seed % 4 == 0 then "TABERNA" elseif ctx.seed % 4 == 1 then "VINUM · OLEUM" elseif ctx.seed % 4 == 2 then "TEXTOR" else "POMA")
	houseSign(ctx, 0, SOCKET + 9.7, label, ctx.w - 1.4)
	if h.special == "Tavern" then
		Parts.flame(ctx.model, front(ctx, ctx.w / 2 - 0.8, SOCKET + 7, 0.6), 16, 0.7)
		Parts.decor(ctx.model, "TavernBench", front(ctx, 0, SOCKET + 0.5, 1.6), Vector3.new(ctx.w - 4, 0.5, 1), C.Timber, Enum.Material.Wood)
	end
	for f = 2, h.floors do
		local y = SOCKET + (f - 1) * STOREY + 4
		for _, x in { -ctx.w / 4, ctx.w / 4 } do
			window(ctx, x, y, 1.8, 2.6, true)
		end
	end
	cornice(ctx, SOCKET + height - 0.3)
	gable(ctx, 0, 0, ctx.w, ctx.d, SOCKET + height, if ctx.seed % 2 == 0 then "Z" else "X")
end

local function courtyardHouse(ctx: Ctx, h: House, villa: boolean)
	local height = h.floors * STOREY + (if villa then 1 else 0)
	local iw = ctx.w - (if villa then 16 else 12)
	local id = ctx.d - (if villa then 18 else 13)
	local fw, sw = (ctx.d - id) / 2, (ctx.w - iw) / 2
	-- four wings (collision) round the open middle
	for _, s in { -1, 1 } do
		body(ctx, 0, s * (id / 2 + fw / 2), ctx.w, fw, SOCKET, height)
		body(ctx, s * (iw / 2 + sw / 2), 0, sw, id + 0.02, SOCKET, height)
	end
	quoins(ctx, height)
	dado(ctx, pick(DADO, ctx.seed, 3))
	if villa then
		-- a portico with two columns before the door, a pediment over it
		door(ctx, 0, 4.4, 8)
		for _, s in { -1, 1 } do
			Parts.column(ctx.model, "PorticoColumn", front(ctx, s * 3.6, SOCKET, 3.2), 9, 1.1, C.Travertine, { collide = false, shadow = false, material = Enum.Material.Marble })
		end
		Parts.decor(ctx.model, "PorticoBeam", front(ctx, 0, SOCKET + 9.4, 1.8), Vector3.new(9.6, 0.8, 3.6), C.Travertine, Enum.Material.Limestone)
		Parts.wedge(ctx.model, "PorticoRoof", front(ctx, 0, SOCKET + 10.4, 1.8) * CFrame.Angles(0, math.pi / 2, 0), Vector3.new(3.6, 1.2, 10), ctx.roof, { collide = false, shadow = false, material = Enum.Material.ClayRoofTiles })
		for _, s in { -1, 1 } do
			window(ctx, s * (ctx.w / 2 - 6), SOCKET + 5.4, 1.4, 1.2, false)
		end
		courtyard(ctx, iw, id, true)
	else
		door(ctx, if ctx.seed % 2 == 0 then -3 else 3, 3.6, 7.6)
		for _, x in { -ctx.w / 3, ctx.w / 3 } do
			window(ctx, x, SOCKET + 5.8, 1.4, 1, false)
		end
		courtyard(ctx, iw, id, false)
	end
	if h.floors > 1 then
		for _, x in { -ctx.w / 4, 0, ctx.w / 4 } do
			window(ctx, x, SOCKET + STOREY + 4, 1.8, 2.4, true)
		end
	end
	cornice(ctx, SOCKET + height - 0.3)
	atriumRoofs(ctx, iw, id, SOCKET + height)
	if villa then
		-- a garden wall and cypresses beside the house, inside its lot
		for _, s in { -1, 1 } do
			cypress(ctx.model, at(ctx, s * (ctx.w / 2 - 1.2), 0, -ctx.d / 2 - 2.2), 7)
		end
	end
end

local function storehouse(ctx: Ctx, h: House)
	local height = h.floors * STOREY + 1
	socket(ctx, 2.2, C.StoneDark)
	body(ctx, 0, 0, ctx.w, ctx.d, SOCKET + 1, height - 1)
	for _, s in { -1, 1 } do
		Parts.decor(ctx.model, "Buttress", front(ctx, s * (ctx.w / 2 - 0.6), SOCKET + height / 2, 0.35), Vector3.new(1.2, height, 0.7), C.Stone, Enum.Material.Limestone)
	end
	door(ctx, 0, math.min(10, ctx.w - 8), 8.4, C.TimberDark)
	for _, x in { -ctx.w / 3, ctx.w / 3 } do
		window(ctx, x, SOCKET + height - 2.4, 1.4, 0.8, false)
	end
	if h.variant == "Workshop" then
		Parts.decor(ctx.model, "WorkshopBench", front(ctx, -ctx.w / 2 + 3, SOCKET + 1.2, 1.2), Vector3.new(3.4, 0.4, 1.4), C.Timber, Enum.Material.Wood)
		houseSign(ctx, 0, SOCKET + 10, "OFFICINA", 8)
	else
		for i = 0, 2 do
			Parts.decor(ctx.model, "Crate", front(ctx, ctx.w / 2 - 3 - i * 1.3, SOCKET + 0.6 + (i % 2) * 1.2, 1.4), Vector3.new(1.2, 1.2, 1.2), C.Timber, Enum.Material.WoodPlanks)
		end
	end
	cornice(ctx, SOCKET + height - 0.3)
	gable(ctx, 0, 0, ctx.w, ctx.d, SOCKET + height, "X")
end

---------------------------------------------------------------------------- build
-- The house's frame on its lot: ground level, -Z toward its street.
function HouseKit.frameOf(h: House): CFrame
	local p = Vector3.new(h.x, h.level, h.z)
	return CFrame.lookAt(p, p + Vector3.new(h.fx, 0, h.fz))
end

-- Houses with an open interior of their own (Smithy.luau, ArmoryShops.luau): `special` builds them.
local SPECIAL_INTERIORS: { [string]: boolean } = { Smithy = true, WeaponShop = true, HelmShop = true, ArmorShop = true, ShieldShop = true }

-- Builds one house (or hands its special interior to `special`). Returns the model.
function HouseKit.build(parent: Instance, h: House, special: ((model: Model, frame: CFrame, house: House) -> ())?): Model
	local model = Instance.new("Model")
	model.Name = ("House_%s"):format(h.id)
	local frame = HouseKit.frameOf(h)
	local ctx: Ctx = {
		model = model,
		frame = frame,
		w = h.w,
		d = h.d,
		seed = h.seed,
		plaster = pick(Parts.Plaster, h.seed, 1),
		roof = pick(Parts.Roofs, h.seed, 4),
		shutter = pick(SHUTTERS, h.seed, 6),
		top = 0,
	}
	if special and h.special and SPECIAL_INTERIORS[h.special] then
		special(model, frame, h)
	else
		if h.type ~= "Storehouse" then
			socket(ctx, SOCKET)
		end
		if h.type == "Row" then
			row(ctx, h)
		elseif h.type == "Tenement" then
			tenement(ctx, h)
		elseif h.type == "Shop" then
			shop(ctx, h)
		elseif h.type == "Courtyard" then
			courtyardHouse(ctx, h, false)
		elseif h.type == "Villa" then
			courtyardHouse(ctx, h, true)
		else
			storehouse(ctx, h)
		end
	end
	model:SetAttribute("HouseId", h.id)
	model:SetAttribute("HouseType", h.type)
	model:SetAttribute("HouseTypeLabel", RomeLayout.TypeLabels[h.type])
	model:SetAttribute("Variant", h.variant)
	model:SetAttribute("District", h.district)
	model:SetAttribute("Floors", h.floors)
	model:SetAttribute("FacesStreet", h.facesStreet)
	model:SetAttribute("OpenInMVP", h.open)
	if h.name then
		model:SetAttribute("Name", h.name)
	end
	if h.square then
		model:SetAttribute("Square", h.square)
	end
	-- the door anchor: on the threshold, -Z looking out to the street
	local doorPoint = Vector3.new(h.door.x, h.door.y + SOCKET, h.door.z)
	model:SetAttribute("DoorAnchor", CFrame.lookAt(doorPoint, doorPoint + Vector3.new(h.door.fx, 0, h.door.fz)))
	model.Parent = parent
	return model
end

HouseKit.Storey = STOREY
HouseKit.Socket = SOCKET

return HouseKit
