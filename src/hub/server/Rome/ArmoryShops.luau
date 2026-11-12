--!strict
-- The shops of Rome: four open shop rooms in town houses, beside and opposite the smithy.
--   WeaponShop  Waffenladen (BN1, beside the smithy): blades and heavy weapons on the side walls,
--               ranged weapons on the back wall
--   HelmShop    Helmhändler (BS1, opposite the smithy): helmets on the left wall
--   ArmorShop   Rüstungsladen (BS1, beside the helm shop): armor sets on the left wall
--   ShieldShop  Schildhaus (BS1): the three shield classes (light left, balanced right, heavy back)
-- Each room is open to the street like the smithy, with a counter, a shopkeeper behind it and the
-- display walls. This module only builds the rooms and describes them: RomeWorld gives the display
-- lines to EquipmentShopService (the same prompts and cards as before), registers the room as an
-- armory volume (LobbyArchitecture.addArmoryVolume) and spawns the shopkeeper at `keeper`.
local RomeLayout = require(script.Parent.RomeLayout)
local Parts = require(script.Parent.RomeParts)

type House = RomeLayout.House
local C = Parts.Colors

local ArmoryShops = {}

export type DisplayLine = { cframe: CFrame, length: number }
export type Look = { skin: Color3, cloth: Color3, accent: Color3, apron: boolean? }
export type Record = {
	kind: string,
	name: string,
	layout: {
		blades: DisplayLine?,
		heavy: DisplayLine?,
		ranged: DisplayLine?,
		shields: { [string]: DisplayLine }?,
		armor: DisplayLine?,
		helmets: DisplayLine?,
	},
	volume: { cf: CFrame, size: Vector3 },
	keeper: CFrame,
	look: Look,
}

local WALL = 1.2
local HALL = 12 -- interior clear height
local SOCKET = 1.2
local OPENING, OPENING_HEIGHT = 7, 9

local records: { Record } = {}

local SHOP_KINDS: { [string]: boolean } = { WeaponShop = true, HelmShop = true, ArmorShop = true, ShieldShop = true }
ArmoryShops.Kinds = SHOP_KINDS

-- Forgets the shops of an earlier build (RomeWorld rebuilds the town from scratch).
function ArmoryShops.reset()
	table.clear(records)
end

-- Every shop built so far (RomeWorld reads them once the houses exist).
function ArmoryShops.shops(): { Record }
	return records
end

-- Side walls: the run along z (from..to), looking into the room along +x (left) or -x (right).
local function sideLine(frame: CFrame, x: number, from: number, to: number, facing: number): DisplayLine
	local mid = Vector3.new(x, SOCKET, (from + to) / 2)
	local look = CFrame.lookAt(mid, mid + Vector3.new(facing, 0, 0))
	return { cframe = frame * look, length = math.abs(to - from) }
end

-- The back wall: the run along x (from..to) at depth z, looking towards the street (-z).
local function backLine(frame: CFrame, z: number, from: number, to: number): DisplayLine
	local mid = Vector3.new((from + to) / 2, SOCKET, z)
	local look = CFrame.lookAt(mid, mid + Vector3.new(0, 0, -1))
	return { cframe = frame * look, length = math.abs(to - from) }
end

-- Builds the room of `h` (a house with `special` = one of SHOP_KINDS) inside `model`, in the
-- house frame `frame` (origin on the ground at the house centre, -Z towards the street).
function ArmoryShops.build(model: Model, frame: CFrame, h: House)
	local kind = h.special or ""
	if not SHOP_KINDS[kind] then
		return
	end
	local w, d = h.w, h.d
	local plaster = Parts.Plaster[4]
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end
	local top = SOCKET + HALL

	-- socket, floor, walls with the wide front opening and the lintel
	Parts.part(model, "Socket", at(0, (SOCKET - 2) / 2, 0), Vector3.new(w + 0.5, SOCKET + 2, d + 0.5), C.Stone, { shadow = false })
	Parts.decor(model, "ShopFloor", at(0, SOCKET + 0.03, 0), Vector3.new(w - 2 * WALL, 0.06, d - 2 * WALL), Color3.fromRGB(120, 104, 88), Enum.Material.Slate)
	Parts.part(model, "Wall", at(0, SOCKET + HALL / 2, d / 2 - WALL / 2), Vector3.new(w, HALL, WALL), plaster, { material = Enum.Material.Plaster })
	for _, s in { -1, 1 } do
		Parts.part(model, "Wall", at(s * (w / 2 - WALL / 2), SOCKET + HALL / 2, 0), Vector3.new(WALL, HALL, d), plaster, { material = Enum.Material.Plaster })
		local side = (w - OPENING) / 2
		Parts.part(model, "Wall", at(s * (OPENING / 2 + side / 2), SOCKET + HALL / 2, -d / 2 + WALL / 2), Vector3.new(side, HALL, WALL), plaster, { material = Enum.Material.Plaster })
	end
	Parts.part(model, "Wall", at(0, SOCKET + OPENING_HEIGHT + (HALL - OPENING_HEIGHT) / 2, -d / 2 + WALL / 2), Vector3.new(OPENING, HALL - OPENING_HEIGHT, WALL), plaster, { material = Enum.Material.Plaster })
	Parts.colliderWedge(model, "ThresholdRamp", at(0, SOCKET / 2, -d / 2 - 1), Vector3.new(OPENING, SOCKET, 2))
	-- flat roof (collision) and the sign over the opening
	Parts.part(model, "Ceiling", at(0, top + 0.5, 0), Vector3.new(w + 0.8, 1, d + 0.8), Color3.fromRGB(92, 72, 52), { material = Enum.Material.WoodPlanks })
	Parts.decor(model, "Beam", at(0, top - 0.4, 0), Vector3.new(w - 2 * WALL, 0.8, 0.8), C.TimberDark, Enum.Material.Wood)
	Parts.sign(model, "ShopSign", at(0, SOCKET + OPENING_HEIGHT + 1.9, -d / 2 - 0.35), Vector2.new(11, 2.2), h.name or "LADEN", ({ WeaponShop = "Waffen · Schwerter, Speere, Bögen", HelmShop = "Helme · Galeae und Visiere", ArmorShop = "Rüstungen · Lorica und Ringpanzer", ShieldShop = "Schilde · Scutum und Parma" })[kind], C.TimberDark)
	Parts.flame(model, at(0, top - 1.6, 0), 16, 0.6)

	-- the counter across the room, its front 5 studs from the street; the shopkeeper behind it
	local counterZ = -d / 2 + 5
	Parts.part(model, "Counter", at(0, SOCKET + 1.6, counterZ), Vector3.new(w - 2 * WALL - 2, 3.2, 1.6), C.Limestone, { material = Enum.Material.Limestone })
	Parts.decor(model, "CounterTop", at(0, SOCKET + 3.25, counterZ), Vector3.new(w - 2 * WALL - 1.6, 0.25, 2.2), C.Timber, Enum.Material.WoodPlanks)

	-- the display walls: side walls for the racks, the back wall for the ranged weapons and the heavy shields
	local sideFrom, sideTo = -d / 2 + 2, d / 2 - 2
	local leftX, rightX = -w / 2 + WALL + 0.6, w / 2 - WALL - 0.6
	local backZ = d / 2 - WALL - 0.6
	local backFrom, backTo = -w / 2 + WALL + 1, w / 2 - WALL - 1

	local layout: Record = {
		kind = kind,
		name = h.name or kind,
		layout = {},
		volume = { cf = frame * CFrame.new(0, SOCKET + HALL / 2, 0), size = Vector3.new(w - 2 * WALL, HALL, d - 2 * WALL) },
		keeper = frame * CFrame.lookAt(Vector3.new(0, SOCKET, counterZ + 2.2), Vector3.new(0, SOCKET, counterZ + 2.2) + Vector3.new(0, 0, -1)),
		look = { skin = Color3.fromRGB(190, 146, 110), cloth = Color3.fromRGB(96, 74, 60), accent = Color3.fromRGB(176, 125, 60), apron = true },
	}
	if kind == "WeaponShop" then
		layout.layout.blades = sideLine(frame, leftX, sideFrom, sideTo, 1)
		layout.layout.heavy = sideLine(frame, rightX, sideFrom, sideTo, -1)
		layout.layout.ranged = backLine(frame, backZ, backFrom, backTo)
	elseif kind == "HelmShop" then
		layout.layout.helmets = sideLine(frame, leftX, sideFrom, sideTo, 1)
	elseif kind == "ArmorShop" then
		layout.layout.armor = sideLine(frame, leftX, sideFrom, sideTo, 1)
	elseif kind == "ShieldShop" then
		layout.layout.shields = {
			Light = sideLine(frame, leftX, sideFrom, sideTo, 1),
			Balanced = sideLine(frame, rightX, sideFrom, sideTo, -1),
			Heavy = backLine(frame, backZ, backFrom, backTo),
		}
	end
	table.insert(records, layout)
end

return ArmoryShops
